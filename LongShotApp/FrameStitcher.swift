import Foundation
import UIKit
import Vision

enum StitchError: LocalizedError {
    case notEnoughFrames
    case unreadableFrame(URL)
    case inconsistentFrameSize
    case noUsableMovement
    case couldNotEncode
    case unusablePage(Int)
    case unseenGap

    var errorDescription: String? {
        switch self {
        case .notEnoughFrames:
            return "没有采集到足够的画面，请重新录制。"
        case .unreadableFrame(let url):
            return "无法读取画面：\(url.lastPathComponent)"
        case .inconsistentFrameSize:
            return "录制过程中屏幕方向或尺寸发生了变化，请保持竖屏后重试。"
        case .noUsableMovement:
            return "没有识别到连续滚动内容。请缓慢向上或向下滚动，保持相邻画面有重叠。"
        case .couldNotEncode:
            return "长图生成失败，请重试。"
        case .unusablePage(let number):
            return "第 \(number) 页没有采集到可连续拼接的内容。请在切换后点「继续」，再缓慢滚动；原始画面已保留。"
        case .unseenGap:
            return "有一段内容缺少重叠画面，无法完整拼接。请放慢滚动速度后重试；原始画面已保留。"
        }
    }
}

struct StitchResult {
    let outputURLs: [URL]
    let acceptedFrameCount: Int
    let skippedFrameCount: Int
    let timings: StitchTimings
}

struct StitchTimings: Codable {
    let sampling: Double
    let selection: Double
    let assembly: Double
    let rendering: Double
    let total: Double
}

final class FrameStitcher {
#if LONGSHOT_CAPTURE_CHECKS
    nonisolated(unsafe) static var alignmentTrace: ((String) -> Void)?
#endif
    private struct Piece {
        let frameURL: URL?
        let sourceRect: CGRect
    }

    private struct FrameSample {
        let url: URL
        let imageSize: CGSize
        let gray: GrayFrame
        let coveredTop: CGFloat
        let isSystemPanel: Bool
    }

    private struct PositionedFrame {
        let index: Int
        let offset: Int
    }

    private struct FrameCoverage {
        let frame: PositionedFrame
        let start: Int
        let end: Int
    }

    private let topInsetRatio: CGFloat = 0.075
    // Keep common tab bars, coupon strips, and floating purchase rails out of
    // every appended slice. The final frame adds this viewport-fixed area once.
    private let bottomInsetRatio: CGFloat = 0.19
    private let maximumOutputHeight: CGFloat = 16_000

    func stitch(
        frameURLs: [URL],
        sessionURL: URL,
        topCropRatio: Double = 0.075,
        segmentStarts: [Int] = []
    ) throws -> StitchResult {
        let started = ProcessInfo.processInfo.systemUptime
        guard !frameURLs.isEmpty else { throw StitchError.notEnoughFrames }

        var samples: [FrameSample] = []
        samples.reserveCapacity(frameURLs.count)
        for url in frameURLs {
            samples.append(try autoreleasepool { try sample(url: url) })
        }

        let sampled = ProcessInfo.processInfo.systemUptime
        let starts = Array(Set([0] + segmentStarts.filter { $0 >= 0 && $0 < samples.count })).sorted()
        let ranges = starts.enumerated().map { index, start in
            start..<(index + 1 < starts.count ? starts[index + 1] : samples.count)
        }
        let first = samples[0]
        let width = first.imageSize.width
        let height = first.imageSize.height
        guard samples.allSatisfy({ $0.imageSize == first.imageSize }) else {
            throw StitchError.inconsistentFrameSize
        }

        let contentTop = floor(height * topInsetRatio)
        let contentBottom = height - ceil(height * bottomInsetRatio)
        let contentHeight = contentBottom - contentTop
        guard contentHeight > 0 else { throw StitchError.inconsistentFrameSize }
        let outputTop = min(contentTop, ceil(height * max(0, topCropRatio)))

        var pieces: [Piece] = []
        var usedFrames = Set<Int>()
        var alignmentFrames: [Int: GrayFrame] = [:]
        var analyses: [(indices: [Int], analysis: BidirectionalScrollAnalysis?)] = []
        for range in ranges {
            let indices = range.filter { !samples[$0].isSystemPanel }
            analyses.append((indices, BidirectionalScrollSelector.analyze(frames: indices.map { samples[$0].gray })))
        }
        let selected = ProcessInfo.processInfo.systemUptime

        func alignmentFrame(at index: Int) throws -> GrayFrame {
            if let cached = alignmentFrames[index] { return cached }
            let frame = try makeAlignmentGrayFrame(from: samples[index].url)
            alignmentFrames[index] = frame
            return frame
        }

        func displacement(from previous: Int, to current: Int, comparison: VerticalShiftComparison? = nil) throws -> Int? {
            if OverlapEstimator.meanAbsoluteDifference(samples[previous].gray, samples[current].gray) < 2.6 {
                return 0
            }
            let comparison = comparison ?? OverlapEstimator.compareVertical(
                from: samples[previous].gray, to: samples[current].gray
            )
            guard let estimate = comparison.estimate() else { return nil }
            let coarsePixelScale = contentHeight / CGFloat(samples[current].gray.height)
            let refinementRadius = max(6, Int(ceil(coarsePixelScale)) + 3)
            let previousPixels = try alignmentFrame(at: previous)
            let currentPixels = try alignmentFrame(at: current)
            func refine(_ candidate: ShiftEstimate) -> ShiftEstimate? {
                OverlapEstimator.refineVerticalShift(
                    from: previousPixels, to: currentPixels,
                    around: Int(round(coarsePixelScale * CGFloat(candidate.rows))),
                    searchRadius: refinementRadius
                )
            }
            var refined = refine(estimate)
            // Repeated text-card layouts can fool the low-resolution pass into
            // choosing the opposite direction. Only pay for a second fine pass
            // when the first is weak; keep the fast path for clean matches.
            if refined == nil || refined!.score > 3 {
                let other = estimate.rows > 0 ? comparison.upward?.estimate() : comparison.downward?.estimate()
                if let other {
                    let signed = estimate.rows > 0 ? ShiftEstimate(
                        rows: -other.rows, score: other.score, confidence: other.confidence
                    ) : other
                    if let alternative = refine(signed),
                       refined == nil || alternative.score + 0.4 < refined!.score {
                        refined = alternative
                    }
                }
            }
            guard let refined, refined.score <= 6 else { return nil }
#if LONGSHOT_CAPTURE_CHECKS
            let coarseShiftPixels = Int(round(coarsePixelScale * CGFloat(estimate.rows)))
            Self.alignmentTrace?("edge \(previous)->\(current) coarse=\(coarseShiftPixels) refined=\(refined.rows) score=\(refined.score)")
#endif
            return refined.rows
        }

        for (pageIndex, item) in analyses.enumerated() {
            let (indices, analysis) = item
            guard !indices.isEmpty else {
                if ranges.count > 1 { throw StitchError.unusablePage(pageIndex + 1) }
                continue
            }
            var positioned: [PositionedFrame] = []
            if let analysis {
                let anchorLocal = analysis.selection.startIndex
                let anchor = indices[anchorLocal]
                positioned = [PositionedFrame(index: anchor, offset: 0)]
                // Recover useful opening content by matching backward from the
                // scroll seed, not by deleting an arbitrary number of seconds.
                var reference = positioned[0]
                if anchorLocal > 0 {
                    for local in stride(from: anchorLocal - 1, through: 0, by: -1) {
                        guard let shift = try displacement(from: reference.index, to: indices[local]) else { break }
                        reference = PositionedFrame(index: indices[local], offset: reference.offset + shift)
                        positioned.append(reference)
                    }
                }
                reference = positioned[0]
                for local in (anchorLocal + 1)..<indices.count {
                    let current = indices[local]
                    // Revisiting an identical viewport closes accumulated
                    // alignment drift; it never appends the same content twice.
                    let revisited = positioned.suffix(24).first {
                        OverlapEstimator.meanAbsoluteDifference(samples[$0.index].gray, samples[current].gray) < 2.6
                    }
                    if let revisited {
                        reference = PositionedFrame(index: current, offset: revisited.offset)
                        positioned.append(reference)
                        continue
                    }
                    let cached = reference.index == indices[local - 1] ? analysis.comparisons[local] : nil
                    guard let shift = try displacement(from: reference.index, to: current, comparison: cached) else { continue }
                    reference = PositionedFrame(index: current, offset: reference.offset + shift)
                    positioned.append(reference)
                }
                guard let minimum = positioned.map(\.offset).min(),
                      let maximum = positioned.map(\.offset).max(), minimum != maximum else {
                    if ranges.count > 1 { throw StitchError.unusablePage(pageIndex + 1) }
                    continue
                }
            } else if ranges.count > 1 {
                // Explicitly separated static pages are valid screenshots too.
                // A lone stationary capture still fails rather than saving UI.
                let stationary = indices.allSatisfy {
                    OverlapEstimator.meanAbsoluteDifference(samples[indices[0]].gray, samples[$0].gray) < 2.6
                }
                if stationary, let clean = indices.last(where: { samples[$0].coveredTop <= contentTop }) {
                    positioned = [PositionedFrame(index: clean, offset: 0)]
                }
            }
            guard !positioned.isEmpty else {
                if ranges.count > 1 { throw StitchError.unusablePage(pageIndex + 1) }
                continue
            }
            let segment = try makeSegmentPieces(
                positioned: positioned, samples: samples, contentTop: contentTop,
                contentBottom: contentBottom, outputTop: outputTop, width: width, height: height
            )
#if LONGSHOT_CAPTURE_CHECKS
            let locations = positioned.map { "\($0.index):\($0.offset)" }.joined(separator: ",")
            Self.alignmentTrace?("positions=\(locations)")
            for piece in segment {
                let name = piece.frameURL?.lastPathComponent ?? "separator"
                Self.alignmentTrace?("piece \(name) y=\(piece.sourceRect.minY) height=\(piece.sourceRect.height)")
            }
#endif
            guard !segment.isEmpty else { continue }
            if !pieces.isEmpty {
                pieces.append(Piece(frameURL: nil, sourceRect: CGRect(x: 0, y: 0, width: width, height: max(8, floor(width * 0.018)))))
            }
            pieces.append(contentsOf: segment)
            let sources = Set(segment.compactMap(\.frameURL))
            for frame in positioned where sources.contains(samples[frame.index].url) { usedFrames.insert(frame.index) }
        }
        guard !pieces.isEmpty else { throw StitchError.noUsableMovement }

        let pages = paginate(pieces: pieces, maximumHeight: maximumOutputHeight)
        let outputDirectory = try CaptureStorage.outputsDirectory(in: sessionURL)
        try removeOldOutputs(from: outputDirectory)

        var outputURLs: [URL] = []
        let assembled = ProcessInfo.processInfo.systemUptime
        for (index, page) in pages.enumerated() {
            let outputURL = outputDirectory.appendingPathComponent(
                String(format: "longshot-%02d.jpg", index + 1)
            )
            try render(page: page, width: width, to: outputURL)
            outputURLs.append(outputURL)
        }

        return StitchResult(
            outputURLs: outputURLs,
            acceptedFrameCount: usedFrames.count,
            skippedFrameCount: samples.count - usedFrames.count,
            timings: StitchTimings(
                sampling: sampled - started,
                selection: selected - sampled,
                assembly: assembled - selected,
                rendering: ProcessInfo.processInfo.systemUptime - assembled,
                total: ProcessInfo.processInfo.systemUptime - started
            )
        )
    }

    private func sample(url: URL) throws -> FrameSample {
        guard let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else {
            throw StitchError.unreadableFrame(url)
        }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let gray = try makeGrayFrame(from: cgImage)
        let overlay = CaptureOverlayDetector.inspect(cgImage)
        return FrameSample(
            url: url, imageSize: imageSize, gray: gray,
            coveredTop: ceil(imageSize.height * overlay.coveredTopRatio), isSystemPanel: overlay.isSystemPanel
        )
    }

    private func makeSegmentPieces(
        positioned: [PositionedFrame], samples: [FrameSample], contentTop: CGFloat,
        contentBottom: CGFloat, outputTop: CGFloat, width: CGFloat, height: CGFloat
    ) throws -> [Piece] {
        let contentHeight = Int(contentBottom - contentTop)
        var coverage: [FrameCoverage] = positioned.map { frame in
            let mask = Int(max(0, samples[frame.index].coveredTop - contentTop))
            return FrameCoverage(frame: frame, start: frame.offset + mask, end: frame.offset + contentHeight)
        }
        coverage = coverage.filter { $0.start < $0.end }
        coverage.sort {
            $0.start != $1.start ? $0.start < $1.start : $0.frame.index < $1.frame.index
        }
        guard let first = coverage.first else { return [] }
        var pieces: [Piece] = []
        var cursor = first.start
        var last = first
        if first.start == first.frame.offset, samples[first.frame.index].coveredTop <= outputTop, outputTop < contentTop {
            pieces.append(Piece(frameURL: samples[first.frame.index].url, sourceRect: CGRect(
                x: 0, y: outputTop, width: width, height: contentTop - outputTop
            )))
        }
        for item in coverage {
            // Never stitch across unseen content by inventing a connecting strip.
            // Explicit page boundaries are the only place a separator is inserted.
            if item.start > cursor { throw StitchError.unseenGap }
            guard item.end > cursor else { continue }
            pieces.append(Piece(frameURL: samples[item.frame.index].url, sourceRect: CGRect(
                x: 0, y: contentTop + CGFloat(cursor - item.frame.offset),
                width: width, height: CGFloat(item.end - cursor)
            )))
            cursor = item.end
            last = item
        }
        if contentBottom < height {
            pieces.append(Piece(frameURL: samples[last.frame.index].url, sourceRect: CGRect(
                x: 0, y: contentBottom, width: width, height: height - contentBottom
            )))
        }
        return pieces
    }

    private func makeGrayFrame(from cgImage: CGImage) throws -> GrayFrame {
        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let top = floor(sourceHeight * topInsetRatio)
        let bottom = ceil(sourceHeight * bottomInsetRatio)
        let contentHeight = sourceHeight - top - bottom
        guard contentHeight > 0 else { throw StitchError.inconsistentFrameSize }

        let targetWidth = 72
        let targetHeight = max(96, Int(round((contentHeight / sourceWidth) * CGFloat(targetWidth))))
        let cropRect = CGRect(x: 0, y: top, width: sourceWidth, height: contentHeight)
        guard let cropped = cgImage.cropping(to: cropRect) else {
            throw StitchError.inconsistentFrameSize
        }
        var gray = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        let rendered = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: targetWidth,
                    height: targetHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: targetWidth,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            return true
        }
        guard rendered else { throw StitchError.couldNotEncode }
        return GrayFrame(width: targetWidth, height: targetHeight, pixels: gray)
    }

    private func makeAlignmentGrayFrame(from url: URL) throws -> GrayFrame {
        guard let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else {
            throw StitchError.unreadableFrame(url)
        }

        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let top = floor(sourceHeight * topInsetRatio)
        let bottom = ceil(sourceHeight * bottomInsetRatio)
        let contentHeight = sourceHeight - top - bottom
        guard contentHeight > 0 else { throw StitchError.inconsistentFrameSize }

        let targetWidth = 72
        let targetHeight = Int(contentHeight)
        let cropRect = CGRect(x: 0, y: top, width: sourceWidth, height: contentHeight)
        guard let cropped = cgImage.cropping(to: cropRect) else {
            throw StitchError.inconsistentFrameSize
        }

        var gray = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        let rendered = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: targetWidth,
                    height: targetHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: targetWidth,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            return true
        }
        guard rendered else { throw StitchError.couldNotEncode }
        return GrayFrame(width: targetWidth, height: targetHeight, pixels: gray)
    }

    private func paginate(pieces: [Piece], maximumHeight: CGFloat) -> [[Piece]] {
        var pages: [[Piece]] = [[]]
        var currentHeight: CGFloat = 0

        for piece in pieces {
            var remaining = piece.sourceRect
            while remaining.height > 0 {
                let available = maximumHeight - currentHeight
                if available <= 0 {
                    pages.append([])
                    currentHeight = 0
                    continue
                }

                let sliceHeight = min(available, remaining.height)
                let slice = Piece(
                    frameURL: piece.frameURL,
                    sourceRect: CGRect(
                        x: remaining.minX,
                        y: remaining.minY,
                        width: remaining.width,
                        height: sliceHeight
                    )
                )
                pages[pages.count - 1].append(slice)
                currentHeight += sliceHeight
                remaining.origin.y += sliceHeight
                remaining.size.height -= sliceHeight

                if currentHeight >= maximumHeight, remaining.height > 0 {
                    pages.append([])
                    currentHeight = 0
                }
            }
        }
        return pages.filter { !$0.isEmpty }
    }

    private func render(page: [Piece], width: CGFloat, to outputURL: URL) throws {
        let height = page.reduce(CGFloat(0)) { $0 + $1.sourceRect.height }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var destinationY: CGFloat = 0

            for piece in page {
                autoreleasepool {
                    guard let frameURL = piece.frameURL else {
                        UIColor(white: 0.93, alpha: 1).setFill()
                        context.fill(CGRect(x: 0, y: destinationY, width: width, height: piece.sourceRect.height))
                        return
                    }
                    guard let source = UIImage(contentsOfFile: frameURL.path) else { return }
                    let destination = CGRect(
                        x: 0,
                        y: destinationY,
                        width: width,
                        height: piece.sourceRect.height
                    )
                    context.cgContext.saveGState()
                    context.cgContext.clip(to: destination)
                    source.draw(in: CGRect(
                        x: 0,
                        y: destinationY - piece.sourceRect.minY,
                        width: width,
                        height: source.size.height
                    ))
                    context.cgContext.restoreGState()
                }
                destinationY += piece.sourceRect.height
            }
        }

        guard let data = image.jpegData(compressionQuality: 0.94) else {
            throw StitchError.couldNotEncode
        }
        try data.write(to: outputURL, options: .atomic)
    }

    private func removeOldOutputs(from directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for file in files where ["jpg", "jpeg", "png"].contains(file.pathExtension.lowercased()) {
            try FileManager.default.removeItem(at: file)
        }
    }
}

/// Conservative, local inspection of our black/red expanded activity and the
/// neutral system sharing sheet. No arbitrary startup sleep or fixed cropping.
enum CaptureOverlayDetector {
    struct Detection {
        let coveredTopRatio: CGFloat
        let isSystemPanel: Bool
    }

    static func inspect(_ image: CGImage) -> Detection {
        let width = 96
        let height = max(96, Int(round(Double(image.height) / Double(image.width) * Double(width))))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return Detection(coveredTopRatio: 0, isSystemPanel: false) }
        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        var darkRows = [Double](repeating: 0, count: height)
        var redRows = [Double](repeating: 0, count: height)
        var outsideRows = [Double](repeating: 0, count: height)
        for y in 0..<min(height, Int(Double(height) * 0.25)) {
            for x in 10..<86 {
                let (r, g, b) = rgb(x, y)
                if max(r, g, b) < 48 { darkRows[y] += 1 / 76.0 }
                if r > 80, g < 135, b < 120, Double(r) > Double(g) * 1.6, Double(r) > Double(b) * 1.5 {
                    redRows[y] += 1 / 76.0
                }
            }
            let left = rgb(1, y), right = rgb(94, y)
            outsideRows[y] = Double(left.0 + left.1 + left.2 + right.0 + right.1 + right.2) / 6
        }
        var coveredTopRatio: CGFloat = 0
        let maximum = min(height - 3, Int(Double(height) * 0.24))
        if let blackStart = (0..<max(1, Int(Double(height) * 0.06))).first(where: {
            darkRows[$0] > 0.60 && outsideRows[$0] > 65
        }) {
            var redBandRows = 0
            var hasRedBand = false
            for y in blackStart..<maximum {
                if redRows[y] > 0.13 {
                    redBandRows += 1
                    hasRedBand = redBandRows >= 2
                }
                if hasRedBand, redRows[y] < 0.06, darkRows[y] > 0.58,
                   y + 1 < maximum, darkRows[y + 1] > 0.45 {
                    var end = y + 1
                    while end + 1 < maximum, darkRows[end + 1] > 0.32 { end += 1 }
                    coveredTopRatio = CGFloat(end + 2) / CGFloat(height)
                    break
                }
            }
        }

        // OCR is only run for a large neutral-gray card, never for every normal
        // frame. Confirm the sharing controls before discarding an entire frame.
        var neutral = 0, checked = 0
        var shadeSum = 0.0, shadeSquareSum = 0.0
        for y in Int(Double(height) * 0.39)..<Int(Double(height) * 0.61) {
            for x in 24..<72 {
                let (r, g, b) = rgb(x, y)
                checked += 1
                if max(r, g, b) - min(r, g, b) < 16, r > 65, r < 205 {
                    neutral += 1
                    shadeSum += Double(r)
                    shadeSquareSum += Double(r * r)
                }
            }
        }
        var isSystemPanel = false
        let meanShade = neutral > 0 ? shadeSum / Double(neutral) : 0
        let shadeVariance = neutral > 0 ? shadeSquareSum / Double(neutral) - meanShade * meanShade : .infinity
        // The real sharing sheet may contain a blurred, uneven backdrop. Our
        // own expanded activity is a second strong hint; don't reject that
        // startup sheet merely because its gray surface has a gradient.
        if checked > 0, Double(neutral) / Double(checked) > 0.72,
           shadeVariance < 180 || coveredTopRatio > 0 {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            if (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil {
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first }
                    .filter { $0.confidence >= 0.3 }.map(\.string).joined(separator: " ").lowercased()
                isSystemPanel = (text.contains("screen sharing") && text.contains("stop sharing"))
                    || text.contains("share entire screen")
            }
            if !isSystemPanel {
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                if (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil {
                    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                        .joined().replacingOccurrences(of: " ", with: "")
                    isSystemPanel = (text.contains("屏幕共享") && text.contains("停止共享"))
                        || text.contains("共享整个屏幕")
                }
            }
        }
        return Detection(coveredTopRatio: coveredTopRatio, isSystemPanel: isSystemPanel)
    }
}
