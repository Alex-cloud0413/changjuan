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
            return "录制过程中屏幕方向或尺寸发生了变化，请保持同一屏幕方向后重试。"
        case .noUsableMovement:
            return "没有识别到连续滚动内容。请沿设置中的拼接方向缓慢滚动，保持相邻画面有重叠。"
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
    let preparedFrameCount: Int
    let preparedAlignmentCount: Int
    var omittedOccludedBottomRows = false
    var outputsSeparatedByGeometry = false
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
        var segmentID: Int? = nil
    }

    private struct HorizontalSegmentPlan {
        let frames: [(url: URL, offset: CGFloat)]
        let frozenLeadingPixels: Int
        let grid: HorizontalGridRegistration?
    }

    private struct HorizontalOverlayGap: Error {
        let top: CGFloat
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

    /// These views are analysis-only crops from an original JPEG. Keeping the
    /// horizontal axis at native resolution avoids rounding a narrow column
    /// into the neighbouring repeated column. Rendering never uses these views.
    private struct HorizontalTableLayers {
        let header: GrayFrame
        let body: GrayFrame
    }

    private struct HorizontalIdentityBand {
        let top: Int
        let bottom: Int
        let bodyBottom: Int
    }

    /// Registration is deliberately limited to a proven regular table grid.
    /// Header controls are not part of this small accidental cross-axis drag.
    private struct HorizontalGridRegistration {
        let headerTop: Int
        let rowPeriod: Int
        let top: Int
        let bottom: Int
        let commonTop: Int
        let commonBottom: Int
        let shifts: [URL: Int]
        var crop: Int { bottom - top - (commonBottom - commonTop) }
        func translation(for url: URL) -> CGFloat { CGFloat(top - commonTop - (shifts[url] ?? 0)) }

        private struct Profile {
            let pixels: [UInt8]
            let scores: [Double]
            let peaks: [Int]
        }

        static func detect(_ urls: [URL], height: Int, statusHeight: Int,
                           identityBand: inout HorizontalIdentityBand?) throws -> HorizontalGridRegistration? {
            guard urls.count >= 2, height >= 300 else { return nil }
            let width = 192
            func profile(_ url: URL) -> Profile? {
                guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
                var pixels = [UInt8](repeating: 0, count: width * height)
                let rendered = pixels.withUnsafeMutableBytes { memory -> Bool in
                    guard let context = CGContext(data: memory.baseAddress, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
                }
                guard rendered else { return nil }
                var scores = [Double](repeating: 0, count: height)
                for y in 3..<(height - 3) {
                    var histogram = [Int](repeating: 0, count: 511)
                    for x in 20..<(width - 3) {
                        let value = abs(2 * Int(pixels[y * width + x])
                            - Int(pixels[(y - 2) * width + x]) - Int(pixels[(y + 2) * width + x]))
                        histogram[value] += 1
                    }
                    var cumulative = 0
                    for value in histogram.indices {
                        cumulative += histogram[value]
                        if cumulative > (width - 23) * 2 / 5 { scores[y] = Double(value); break }
                    }
                }
                var peaks: [Int] = []
                for y in 3..<(height - 3) where scores[y] >= 15 {
                    guard ((y - 2)...(y + 2)).allSatisfy({ scores[y] >= scores[$0] }) else { continue }
                    if let last = peaks.last, y - last <= 3 {
                        if scores[y] > scores[last] { peaks[peaks.count - 1] = y }
                    } else { peaks.append(y) }
                }
                return Profile(pixels: pixels, scores: scores, peaks: peaks)
            }
            let profiles = urls.compactMap { url in autoreleasepool { profile(url) } }
            guard profiles.count == urls.count, let anchor = profiles.first else { return nil }
            // Motion union across every capture, not only first/middle/last:
            // a return to the opening viewport must not turn moving headings
            // into a supposedly fixed toolbar. Reuse the decoded grid profiles.
            func unchanged(_ y: Int) -> Bool {
                profiles.dropFirst().allSatisfy { other in
                    var changed = 0, regions = Set<Int>()
                    for x in 20..<(width - 3) {
                        let delta = abs(Int(anchor.pixels[y * width + x]) - Int(other.pixels[y * width + x]))
                        if delta > 10 { changed += 1; regions.insert(x * 6 / width) }
                    }
                    // A clock/badge changing in one small toolbar region is
                    // not the start of the horizontally moving table layer.
                    // Require motion evidence distributed across the row.
                    return changed < max(4, width / 48) || regions.count < 2
                }
            }
            var firstMoving = statusHeight
            while firstMoving < height / 4, unchanged(firstMoving) { firstMoving += 1 }
            let headerTop = max(statusHeight, firstMoving - 2)
            var fixedBottom = 0
            while fixedBottom < height / 5, unchanged(height - fixedBottom - 1) { fixedBottom += 1 }
            let bottomHint = fixedBottom > 2 ? height - fixedBottom + 2 : nil
            // The first moving visual band can identify columns even without
            // a regular row grid or frozen header divider. Detect its bounds
            // from temporal pixels, not a fixed crop or an app-specific label.
            if firstMoving < height / 4 {
                var end = firstMoving + max(8, height / 180)
                let limit = min(height / 3, firstMoving + height / 12)
                while end < limit {
                    if (0..<3).allSatisfy({ unchanged(end + $0) }) { break }
                    end += 1
                }
                if end - headerTop >= 12 {
                    identityBand = HorizontalIdentityBand(top: headerTop, bottom: end + 1,
                        bodyBottom: min(height, bottomHint ?? height))
                }
            }
            let central = anchor.peaks.filter { $0 >= Int(Double(height) * 0.22) && $0 < Int(Double(height) * 0.73) }
            guard central.count >= 8 else { return nil }
            let gaps = zip(central, central.dropFirst()).map { $1 - $0 }
                .filter { $0 >= max(8, height / 120) && $0 < height / 12 }.sorted()
            guard !gaps.isEmpty else { return nil }
            let period = gaps[gaps.count / 2], tolerance = max(2, period / 20)
            var run: [Int] = [], longest: [Int] = []
            for peak in central {
                if let last = run.last, abs(peak - last - period) > tolerance { run = [] }
                run.append(peak)
                if run.count > longest.count { longest = run }
            }
            guard longest.count >= 8, let start = longest.first, let end = longest.last else { return nil }
            // A reversed recording may start at the other end of a small Y
            // drift. Search up to half a row, then independently require the
            // complete session's drift span to remain below half a row.
            let radius = max(2, (period - 1) / 2)
            func phase(_ current: Profile, range: Range<Int>) -> Int? {
                let choices = (-radius...radius).map { shift -> (shift: Int, score: Double) in
                    let score = range.reduce(0.0) { sum, y in sum + min(anchor.scores[y], current.scores[y + shift]) }
                    return (shift, score)
                }.sorted { $0.score > $1.score }
                guard choices.count > 1, let best = choices.first, best.score > 0,
                      abs(best.shift) < radius,
                      best.score - choices[1].score > best.score * 0.10 else { return nil }
                return best.shift
            }
            var offsets: [Int] = []
            for current in profiles {
                let middle = (start + end) / 2
                guard let upper = phase(current, range: start..<(middle + 1)),
                      let lower = phase(current, range: middle..<(end + 1)),
                      let total = phase(current, range: start..<(end + 1)),
                      abs(upper - lower) <= 1, abs(total - upper) <= 1 else { return nil }
                offsets.append(total)
            }
            guard let minimum = offsets.min(), let maximum = offsets.max() else { return nil }
            let hasCrossDrift = minimum != maximum
#if LONGSHOT_CAPTURE_CHECKS
            FrameStitcher.alignmentTrace?("grid evidence rows=\(start)..\(end) period=\(period) header=\(headerTop) shifts=\(offsets)")
#endif
            // Strong row-grid evidence says the body moved across the capture
            // axis. If its boundaries cannot be proven, failing is safer than
            // interpreting that drift as a repeated horizontal column.
            guard maximum - minimum < period / 2 else { throw StitchError.unseenGap }
            // The last unchanged divider before the regular moving row grid
            // separates frozen column headings from the scrollable cells.
            let dividers = anchor.peaks.filter { y in
                guard y > height / 10 && y < start - period / 3 && profiles.dropFirst().allSatisfy({ current in
                    current.peaks.contains(where: { abs($0 - y) <= 2 })
                }) else { return false }
                if !hasCrossDrift { return y > headerTop + 12 }
                // A one-pixel body shift can leave a nearby peak within the
                // positional tolerance. The complete divider profile must
                // positively prefer screen-fixed pixels over the body phase.
                var votes = 0, tested = 0
                for (current, shift) in zip(profiles, offsets) where shift != 0 {
                    tested += 1
                    var fixed = 0.0, moving = 0.0
                    for delta in -4...4 {
                        fixed += abs(anchor.scores[y + delta] - current.scores[y + delta])
                        moving += abs(anchor.scores[y + delta] - current.scores[y + delta + shift])
                    }
                    if fixed + 1 < moving * 0.8 { votes += 1 }
                }
                return tested >= 2 && votes * 5 >= tested * 3
            }
            guard let divider = dividers.last else {
#if LONGSHOT_CAPTURE_CHECKS
                FrameStitcher.alignmentTrace?("grid rejected fixed divider")
#endif
                if hasCrossDrift { throw StitchError.unseenGap }; return nil
            }
            let top = divider + 2
            let headingBandHeight = min(top - 3, headerTop + 2 + period) - (headerTop + 2)
            // A frozen toolbar can end midway through a normal data row.
            // Its few leftover glyph pixels are not a separate column-heading
            // layer. Keep the general horizontal path when no Y drift exists;
            // never fall back *after* a table matcher reports ambiguous X.
            guard headingBandHeight >= max(12, period / 2) else {
                if hasCrossDrift { throw StitchError.unseenGap }; return nil
            }
            // Persistent vertical grid lines reveal the actual table viewport
            // bottom. Text, watermarks and floating controls are minority votes.
            var bottoms: [Int] = []
            for (profileIndex, current) in profiles.enumerated() {
                let bodyRange = (start + period)..<(end - period)
                guard bodyRange.count > period * 3 else {
                    if hasCrossDrift { throw StitchError.unseenGap }; return nil
                }
                var columns: [Int] = [], candidatesInRun: [(x: Int, support: Int)] = []
                func finishRun() {
                    // A broad coloured cell is not a thin vertical grid line.
                    if !candidatesInRun.isEmpty, candidatesInRun.count <= 3,
                       let best = candidatesInRun.max(by: { $0.support < $1.support }) { columns.append(best.x) }
                    candidatesInRun.removeAll(keepingCapacity: true)
                }
                for x in 20..<(width - 3) {
                    let support = bodyRange.reduce(0) { $0 + (current.pixels[$1 * width + x] < 253 ? 1 : 0) }
                    if support * 100 >= bodyRange.count * 85 { candidatesInRun.append((x, support)) }
                    else { finishRun() }
                }
                finishRun()
                let candidates = columns.compactMap { column -> Int? in
                    (end..<min(height - 5, height * 92 / 100)).first { y in
                        (0..<5).allSatisfy { current.pixels[(y + $0) * width + column] >= 253 }
                    }
                }
                let best = candidates.max(by: { candidate, other in
                    candidates.filter { abs($0 - candidate) <= 2 }.count < candidates.filter { abs($0 - other) <= 2 }.count
                })
                let agreeing = best.map { best in candidates.filter { abs($0 - best) <= 2 }.sorted() } ?? []
                if columns.count >= 3, agreeing.count >= 2, agreeing.count * 2 >= columns.count {
                    bottoms.append(agreeing[agreeing.count / 2])
                } else if profileIndex > 0, let bottomHint, let provenBottom = bottoms.first,
                          abs(bottomHint - provenBottom) <= 3 {
                    // Sparse later columns may expose fewer vertical lines.
                    // The already-proven grid and unchanged fixed footer still
                    // establish their viewport; do not weaken the anchor proof.
                    bottoms.append(bottomHint)
                } else {
#if LONGSHOT_CAPTURE_CHECKS
                    FrameStitcher.alignmentTrace?("grid rejected bottom frame=\(profileIndex) columns=\(columns.count) candidates=\(candidates) hint=\(bottomHint ?? -1)")
#endif
                    if hasCrossDrift { throw StitchError.unseenGap }; return nil
                }
            }
            guard let bottom = bottoms.first, bottoms.allSatisfy({ abs($0 - bottom) <= 2 }), bottom > end else {
                if hasCrossDrift { throw StitchError.unseenGap }; return nil
            }
            let commonTop = top - minimum
            let commonBottom = zip(bottoms, offsets).map { $0 - $1 }.min() ?? bottom
            guard commonBottom > commonTop, bottom - top - (commonBottom - commonTop) >= 0 else { throw StitchError.unseenGap }
            var shiftsByURL: [URL: Int] = [:]
            for (url, offset) in zip(urls, offsets) {
                if let prior = shiftsByURL[url], prior != offset { throw StitchError.unseenGap }
                shiftsByURL[url] = offset
            }
            return HorizontalGridRegistration(headerTop: headerTop, rowPeriod: period, top: top, bottom: bottom, commonTop: commonTop,
                commonBottom: commonBottom, shifts: shiftsByURL)
        }
    }

    // Horizontal mode transposes the screen for matching, so the original
    // screen's top/bottom chrome lies on the cross-axis, not the scroll axis.
    // Cropping 20% from the scroll start silently drops the first columns.
    private var topInsetRatio: CGFloat { options.axis == .horizontal ? 0 : 0.075 }
    // Keep common tab bars, coupon strips, and floating purchase rails out of
    // every appended slice. The final frame adds this viewport-fixed area once.
    private var bottomInsetRatio: CGFloat { options.axis == .horizontal ? 0 : 0.19 }
    private let maximumOutputHeight: CGFloat
    private let usePreparedFrames: Bool
    private let options: CaptureOptions

    init(usePreparedFrames: Bool = true, options: CaptureOptions = CaptureOptions()) {
        self.usePreparedFrames = usePreparedFrames
        self.options = options
        self.maximumOutputHeight = 16_000
    }

#if LONGSHOT_CAPTURE_CHECKS
    init(usePreparedFrames: Bool = true, options: CaptureOptions, testPageLimit: CGFloat) {
        precondition(testPageLimit >= 1)
        self.usePreparedFrames = usePreparedFrames
        self.options = options
        self.maximumOutputHeight = testPageLimit
    }
#endif

    func stitch(
        frameURLs: [URL],
        sessionURL: URL,
        topCropRatio: Double = 0.075,
        segmentStarts: [Int] = [],
        geometrySegments: [CaptureGeometrySegment] = []
    ) throws -> StitchResult {
        let started = ProcessInfo.processInfo.systemUptime
        guard !frameURLs.isEmpty else { throw StitchError.notEnoughFrames }

        var samples: [FrameSample] = []
        var preparedFrameCount = 0
        samples.reserveCapacity(frameURLs.count)
        for url in frameURLs {
            samples.append(try autoreleasepool {
                if usePreparedFrames, let prepared = FramePreparationCache.load(for: url, axis: options.axis) {
                    preparedFrameCount += 1
                    return FrameSample(
                        url: url, imageSize: CGSize(width: prepared.imageWidth, height: prepared.imageHeight),
                        gray: prepared.gray, coveredTop: CGFloat(prepared.coveredTop),
                        isSystemPanel: prepared.isSystemPanel
                    )
                }
                return try sample(url: url)
            })
        }

        let sampled = ProcessInfo.processInfo.systemUptime
        let starts = Array(Set([0] + segmentStarts.filter { $0 >= 0 && $0 < samples.count })).sorted()
        let ranges = starts.enumerated().map { index, start in
            start..<(index + 1 < starts.count ? starts[index + 1] : samples.count)
        }
        // Validate *within* declared pages before attempting any match. Old
        // unsegmented recordings still reject unexplained geometry changes.
        for range in ranges {
            guard range.allSatisfy({ samples[$0].imageSize == samples[range.lowerBound].imageSize }) else {
                throw StitchError.inconsistentFrameSize
            }
        }
        let geometryStarts = Set(geometrySegments.dropFirst().map(\.startFrame))
        if !geometrySegments.isEmpty {
            guard geometrySegments.first?.startFrame == 0,
                  Set(geometrySegments.map(\.startFrame)).count == geometrySegments.count,
                  geometrySegments.map(\.startFrame) == geometrySegments.map(\.startFrame).sorted() else {
                throw StitchError.inconsistentFrameSize
            }
            for record in geometrySegments {
                guard starts.contains(record.startFrame) else { throw StitchError.inconsistentFrameSize }
                let expected = options.axis == .horizontal
                    ? CGSize(width: record.pixelHeight, height: record.pixelWidth)
                    : CGSize(width: record.pixelWidth, height: record.pixelHeight)
                guard expected == samples[record.startFrame].imageSize else { throw StitchError.inconsistentFrameSize }
            }
        }
        var groupStarts = [0]
        for start in starts.dropFirst() {
            if samples[start].imageSize != samples[start - 1].imageSize || geometryStarts.contains(start) {
                groupStarts.append(start)
            }
        }
        if groupStarts.count > 1 {
            return try stitchGeometryGroups(samples: samples, starts: groupStarts, segmentStarts: starts,
                sessionURL: sessionURL, topCropRatio: topCropRatio, started: started,
                sampled: sampled, preparedFrameCount: preparedFrameCount)
        }
        return try stitchUniformSamples(samples, sessionURL: sessionURL, topCropRatio: topCropRatio,
            segmentStarts: starts, started: started, sampled: sampled, preparedFrameCount: preparedFrameCount)
    }

    /// Independent native-size outputs are the only honest join when a fold
    /// reflows text or columns. Render into staging so a failed later page can
    /// never replace an earlier complete output or report a partial success.
    private func stitchGeometryGroups(samples: [FrameSample], starts: [Int], segmentStarts: [Int],
        sessionURL: URL, topCropRatio: Double, started: Double, sampled: Double,
        preparedFrameCount: Int) throws -> StitchResult {
        let files = FileManager.default
        let staging = sessionURL.appendingPathComponent(".geometry-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        var results: [StitchResult] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : samples.count
            let localStarts = segmentStarts.filter { $0 >= start && $0 < end }.map { $0 - start }
            let group = Array(samples[start..<end])
            let groupStarted = ProcessInfo.processInfo.systemUptime
            results.append(try stitchUniformSamples(group,
                sessionURL: staging.appendingPathComponent(String(index)), topCropRatio: topCropRatio,
                segmentStarts: localStarts, started: groupStarted, sampled: groupStarted, preparedFrameCount: 0,
                allowsStaticPages: true))
        }
        let outputDirectory = try CaptureStorage.outputsDirectory(in: sessionURL)
        try removeOldOutputs(from: outputDirectory)
        var outputs: [URL] = []
        for result in results {
            for source in result.outputURLs {
                let destination = outputDirectory.appendingPathComponent(String(format: "longshot-%02d.jpg", outputs.count + 1))
                try files.moveItem(at: source, to: destination)
                outputs.append(destination)
            }
        }
        return StitchResult(outputURLs: outputs,
            acceptedFrameCount: results.reduce(0) { $0 + $1.acceptedFrameCount },
            skippedFrameCount: results.reduce(0) { $0 + $1.skippedFrameCount },
            timings: StitchTimings(sampling: sampled - started,
                selection: results.reduce(0) { $0 + $1.timings.selection },
                assembly: results.reduce(0) { $0 + $1.timings.assembly },
                rendering: results.reduce(0) { $0 + $1.timings.rendering },
                total: ProcessInfo.processInfo.systemUptime - started),
            preparedFrameCount: preparedFrameCount,
            preparedAlignmentCount: results.reduce(0) { $0 + $1.preparedAlignmentCount },
            omittedOccludedBottomRows: results.contains { $0.omittedOccludedBottomRows },
            outputsSeparatedByGeometry: true)
    }

    private func stitchUniformSamples(_ samples: [FrameSample], sessionURL: URL, topCropRatio: Double,
        segmentStarts: [Int], started: Double, sampled: Double, preparedFrameCount: Int,
        allowsStaticPages: Bool = false) throws -> StitchResult {
        var preparedAlignmentCount = 0
        let starts = segmentStarts
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
        let outputTop = options.axis == .horizontal || options.keepsStatusBar
            ? 0 : min(contentTop, ceil(height * max(0, topCropRatio)))

        // A proven table grid can drift slightly across the chosen scroll axis.
        // Establish separate heading/body layers before matching and rendering:
        // one 1-D transform cannot represent their different motion. Cached
        // samples remain derived from the unchanged original JPEG.
        var gridByIndex: [Int: HorizontalGridRegistration] = [:]
        var gridMasksByIndex: [Int: [CGRect]] = [:]
        var tableHeaderTopByIndex: [Int: Int] = [:]
        var identityMatchingByIndex: [Int: HorizontalGridRegistration] = [:]
        if options.axis == .horizontal {
            for range in ranges {
                let indices = range.filter { !samples[$0].isSystemPanel }
                var identity: HorizontalIdentityBand?
                let detected = try HorizontalGridRegistration.detect(indices.map { samples[$0].url },
                    height: Int(width), statusHeight: Int(min(floor(width * 0.075), ceil(width * max(0, topCropRatio)))),
                    identityBand: &identity)
                guard let registration = detected else {
                    if let identity {
                        let bodyTop = identity.bottom + 3
                        let matching = HorizontalGridRegistration(headerTop: identity.top,
                            rowPeriod: identity.bottom - identity.top, top: bodyTop, bottom: identity.bodyBottom,
                            commonTop: bodyTop, commonBottom: identity.bodyBottom, shifts: [:])
                        for index in indices {
                            identityMatchingByIndex[index] = matching
                            tableHeaderTopByIndex[index] = identity.top
                        }
                    }
                    continue
                }
#if LONGSHOT_CAPTURE_CHECKS
                Self.alignmentTrace?("table layers header=\(registration.headerTop)..<\(registration.top) bodyEnd=\(registration.bottom) y=\(registration.shifts.values.min() ?? 0)..\(registration.shifts.values.max() ?? 0)")
#endif
                let shifts = registration.shifts.values
                let minimumShift = CGFloat(shifts.min() ?? 0), maximumShift = CGFloat(shifts.max() ?? 0)
                let masks = fixedHorizontalColorOverlays(indices.map { samples[$0].url },
                    top: CGFloat(registration.top), bottom: width - CGFloat(registration.bottom), height: width).map { mask in
                        mask.union(mask.offsetBy(dx: 0, dy: -minimumShift))
                            .union(mask.offsetBy(dx: 0, dy: -maximumShift))
                    }
                for index in indices {
                    gridByIndex[index] = registration
                    gridMasksByIndex[index] = masks
                    tableHeaderTopByIndex[index] = registration.headerTop + 2
                }
            }
        }

        // A frozen pane is a session-level layer, not a fixed percentage of
        // the screen. Reuse this one boundary in matching, coverage and repair.
        var motionByIndex: [Int: HorizontalMotionLayout] = [:]
        if options.axis == .horizontal {
            for range in ranges {
                let indices = range.filter { !samples[$0].isSystemPanel }
                var evidence = HorizontalMotionLayout.Accumulator()
                for index in indices {
                    try autoreleasepool {
                        evidence.observe(try horizontalMotionObservation(samples[index].url,
                            registration: gridByIndex[index] ?? identityMatchingByIndex[index]))
                    }
                }
                let layout = evidence.resolve()
#if LONGSHOT_CAPTURE_CHECKS
                Self.alignmentTrace?("motion layers frozenLeft=\(layout.frozenLeadingPixels) observations=\(layout.observations)")
#endif
                for index in indices { motionByIndex[index] = layout }
            }
        }

        var pieces: [Piece] = []
        var horizontalPlans: [Int: HorizontalSegmentPlan] = [:]
        var usedFrames = Set<Int>()
        var alignmentFrames: [Int: GrayFrame] = [:]
        var alignmentOrder: [Int] = []
        var tableLayerFrames: [Int: HorizontalTableLayers] = [:]
        var tableLayerOrder: [Int] = []
        var analyses: [(indices: [Int], analysis: BidirectionalScrollAnalysis?)] = []
        for range in ranges {
            let indices = range.filter { !samples[$0].isSystemPanel }
            let frames = indices.map { samples[$0].gray }
            let analysis: BidirectionalScrollAnalysis?
            if options.axis == .horizontal {
                analysis = frames.count > 1 ? BidirectionalScrollAnalysis(
                    selection: ScrollSequenceSelection(startIndex: 0, endIndex: frames.count - 1, preferredShiftRows: 0),
                    comparisons: [VerticalShiftComparison?](repeating: nil, count: frames.count)
                ) : nil
            } else {
                analysis = BidirectionalScrollSelector.analyze(frames: frames)
            }
            analyses.append((indices, analysis))
        }
        let selected = ProcessInfo.processInfo.systemUptime

        func movingFrame(_ frame: GrayFrame, at index: Int) -> GrayFrame {
            let left = motionByIndex[index]?.frozenLeadingPixels ?? 0
            guard left > 0 else { return frame }
            let first = Int(floor(Double(left) * Double(frame.height) / Double(height)))
            return GrayFrame(width: frame.width, height: frame.height - first,
                             pixels: Array(frame.pixels[(first * frame.width)...]))
        }

        func alignmentFrame(at index: Int) throws -> GrayFrame {
            if let cached = alignmentFrames[index] { return cached }
            var frame: GrayFrame
            if usePreparedFrames, let prepared = FramePreparationCache.load(for: samples[index].url, axis: options.axis) {
                preparedAlignmentCount += 1
                frame = prepared.alignment
            } else {
                frame = try autoreleasepool { try makeAlignmentGrayFrame(from: samples[index].url) }
            }
            // Adjacent matching only needs a few recent fine-grained frames.
            // Revisited viewports use coarse samples; eviction changes no pixels.
            if alignmentOrder.count >= 8 { alignmentFrames.removeValue(forKey: alignmentOrder.removeFirst()) }
            frame = movingFrame(frame, at: index)
            alignmentFrames[index] = frame
            alignmentOrder.append(index)
            return frame
        }

        func tableLayers(at index: Int) throws -> HorizontalTableLayers {
            if let cached = tableLayerFrames[index] { return cached }
            guard let registration = gridByIndex[index] ?? identityMatchingByIndex[index],
                  let headerTop = tableHeaderTopByIndex[index] else { throw StitchError.unseenGap }
            let layers = try autoreleasepool {
                try makeHorizontalTableLayers(from: samples[index].url, headerTop: headerTop,
                    registration: registration, masks: gridMasksByIndex[index] ?? [],
                    frozenLeadingPixels: motionByIndex[index]?.frozenLeadingPixels ?? 0)
            }
            // Bounded analysis memory even for a long, multi-page recording.
            if tableLayerOrder.count >= 2 {
                tableLayerFrames.removeValue(forKey: tableLayerOrder.removeFirst())
            }
            tableLayerFrames[index] = layers
            tableLayerOrder.append(index)
            return layers
        }

        var horizontalDisplacements: [Int: ShiftEstimate] = [:]
        var horizontalCandidates: [Int: [ShiftEstimate]] = [:]
        if options.axis == .horizontal {
            for range in ranges {
                let indices = range.filter { !samples[$0].isSystemPanel }
                guard indices.count > 1 else { continue }
                // A registered table has separately moving headings and body.
                // It must not be reduced to one transposed 1-D motion path.
                if indices.allSatisfy({ gridByIndex[$0] != nil || identityMatchingByIndex[$0] != nil }) { continue }
                var candidates: [[ShiftEstimate]] = []
                for local in 1..<indices.count {
                    let previous = indices[local - 1], current = indices[local]
                    if sameViewport(samples[previous].gray, samples[current].gray) {
                        candidates.append([ShiftEstimate(rows: 0, score: 0, confidence: 1)])
                    } else {
                        candidates.append(HorizontalScrollMatcher.candidates(
                            movingFrame(samples[previous].gray, at: previous), movingFrame(samples[current].gray, at: current)
                        ))
                    }
                }
                let selected = HorizontalScrollMatcher.selectSequence(candidates)
                for (local, estimate) in selected.enumerated() {
                    if let estimate { horizontalDisplacements[indices[local + 1]] = estimate }
                    horizontalCandidates[indices[local + 1]] = candidates[local]
                }
            }
        }

        func displacement(from previous: Int, to current: Int, comparison: VerticalShiftComparison? = nil) throws -> Int? {
            if sameViewport(samples[previous].gray, samples[current].gray) {
                return 0
            }
            let comparison = comparison ?? OverlapEstimator.compareVertical(from: samples[previous].gray, to: samples[current].gray)
            guard let estimate = comparison.estimate() else { return nil }
            let coarsePixelScale = contentHeight / CGFloat(samples[current].gray.height)
            let refinementRadius = max(6, Int(ceil(coarsePixelScale)) + 3)
            let previousPixels = try alignmentFrame(at: previous)
            let currentPixels = try alignmentFrame(at: current)
            func refine(_ candidate: ShiftEstimate) -> ShiftEstimate? {
                return OverlapEstimator.refineVerticalShift(
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
            if options.axis == .horizontal {
                positioned = [PositionedFrame(index: indices[0], offset: 0)]
                for local in 1..<indices.count {
                    let current = indices[local]
                    let previous = indices[local - 1]
                    if let registration = gridByIndex[current] ?? identityMatchingByIndex[current] {
                        let a = try tableLayers(at: previous), b = try tableLayers(at: current)
                        let crossShift = (registration.shifts[samples[current].url] ?? 0)
                            - (registration.shifts[samples[previous].url] ?? 0)
                        if crossShift == 0, a.header == b.header, a.body == b.body,
                           try identicalCapturedFrame(samples[previous].url, samples[current].url) {
                            // Identical observed pixels add no extent. This
                            // preserves explicit static pages even when their
                            // repeated headings cannot establish a unique X.
                            positioned.append(PositionedFrame(index: current, offset: positioned.last!.offset))
                            continue
                        }
                        let estimate = HorizontalTableMatcher.estimate(
                            headerA: a.header, headerB: b.header, bodyA: a.body, bodyB: b.body,
                            expectedCrossShift: crossShift,
                            isolatedMovingBody: (motionByIndex[current]?.frozenLeadingPixels ?? 0) > 0
                        )
                        guard let estimate, abs(estimate.dy - crossShift) <= 1 else {
#if LONGSHOT_CAPTURE_CHECKS
                            Self.alignmentTrace?("table rejected \(previous)->\(current) header=\(a.header.width)x\(a.header.height) body=\(a.body.width)x\(a.body.height) cross=\(crossShift)")
#endif
                            throw StitchError.unseenGap
                        }
                        // X=0 with a real Y change is a valid same-column
                        // observation, not a reason to invent a repeated column.
                        positioned.append(PositionedFrame(index: current,
                            offset: positioned.last!.offset + estimate.dx))
#if LONGSHOT_CAPTURE_CHECKS
                        Self.alignmentTrace?("table edge \(previous)->\(current) dx=\(estimate.dx) dy=\(estimate.dy)")
#endif
                        continue
                    }
                    if let revisited = positioned.suffix(24).first(where: {
                        sameViewport(samples[$0.index].gray, samples[current].gray)
                    }) {
                        positioned.append(PositionedFrame(index: current, offset: revisited.offset))
                        continue
                    }
                    guard let coarse = horizontalDisplacements[current], coarse.rows != 0 else {
                        throw StitchError.unseenGap
                    }
                    let previousAlignment = try alignmentFrame(at: previous)
                    let currentAlignment = try alignmentFrame(at: current)
                    let scale = CGFloat(previousAlignment.height) / CGFloat(movingFrame(samples[previous].gray, at: previous).height)
                    // Coarse sampling can alias repeated cells. Verify separate
                    // candidate peaks at native X; direction/sequence priors
                    // may propose an offset, never overrule pixel evidence.
                    var peaks = [coarse]
                    for candidate in horizontalCandidates[current] ?? [] where candidate.rows != 0 {
                        if peaks.allSatisfy({ abs($0.rows - candidate.rows) > max(4, Int(12 / scale)) }) {
                            peaks.append(candidate)
                            if peaks.count == 4 { break }
                        }
                    }
                    let verified = peaks.compactMap { candidate in
                        HorizontalScrollMatcher.refine(from: previousAlignment, to: currentAlignment,
                            around: Int(round(CGFloat(candidate.rows) * scale)),
                            searchRadius: max(10, Int(ceil(scale * 2.5))), smoothingRadius: Int(floor(scale / 2)))
                    }.sorted { $0.score < $1.score }
                    guard let refined = verified.first, refined.score < 6 else { throw StitchError.unseenGap }
                    if let rival = verified.dropFirst().first(where: { abs($0.rows - refined.rows) > 2 }),
                       rival.score - refined.score < 0.15 { throw StitchError.unseenGap }
                    let offset = positioned.last!.offset + refined.rows
                    positioned.append(PositionedFrame(index: current, offset: offset))
                }
                if positioned.map(\.offset).min() == positioned.map(\.offset).max() {
                    guard ranges.count > 1 || allowsStaticPages else { continue }
                    // Explicit page boundaries also support a stationary page.
                    // Do not mistake an unrelated or unmatched ending for one.
                    guard indices.allSatisfy({ gridByIndex[$0] != nil || sameViewport(samples[indices[0]].gray, samples[$0].gray) }),
                          let clean = indices.last else { throw StitchError.unusablePage(pageIndex + 1) }
                    positioned = [PositionedFrame(index: clean, offset: 0)]
                }
            } else if let analysis {
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
                        sameViewport(samples[$0.index].gray, samples[current].gray)
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
                if options.axis == .horizontal, let last = indices.last,
                   !positioned.contains(where: { $0.index == last }) {
                    // Never report a complete sheet after silently dropping
                    // an unmatched final region of a sparse/repeating table.
                    throw StitchError.unseenGap
                }
                guard let minimum = positioned.map(\.offset).min(),
                      let maximum = positioned.map(\.offset).max(), minimum != maximum else {
                    if ranges.count > 1 { throw StitchError.unusablePage(pageIndex + 1) }
                    continue
                }
            } else if ranges.count > 1 || allowsStaticPages {
                // Explicitly separated static pages are valid screenshots too.
                // A lone stationary capture still fails rather than saving UI.
                let stationary = indices.allSatisfy {
                    sameViewport(samples[indices[0]].gray, samples[$0].gray)
                }
                if stationary, let clean = indices.last(where: { samples[$0].coveredTop <= contentTop }) {
                    positioned = [PositionedFrame(index: clean, offset: 0)]
                }
            }
            guard !positioned.isEmpty else {
                if ranges.count > 1 { throw StitchError.unusablePage(pageIndex + 1) }
                continue
            }
            if options.axis == .horizontal {
                // A revisited original viewport is an exact loop closure, not
                // permission to accumulate another copy of its columns.
                var known: [URL: Int] = [:]
                for frame in positioned {
                    let url = samples[frame.index].url
                    if let prior = known[url], prior != frame.offset { throw StitchError.unseenGap }
                    known[url] = frame.offset
                }
                let origin = positioned.map(\.offset).min() ?? 0
                var seen = Set<URL>()
                let frames = positioned.compactMap { frame -> (url: URL, offset: CGFloat)? in
                    let url = samples[frame.index].url
                    return seen.insert(url).inserted ? (url, CGFloat(frame.offset - origin)) : nil
                }
                horizontalPlans[pageIndex] = HorizontalSegmentPlan(frames: frames,
                    frozenLeadingPixels: motionByIndex[indices[0]]?.frozenLeadingPixels ?? 0,
                    grid: gridByIndex[indices[0]])
            }
            let segment = try makeSegmentPieces(
                positioned: positioned, samples: samples,
                contentTop: options.axis == .horizontal ? CGFloat(motionByIndex[indices[0]]?.frozenLeadingPixels ?? 0) : contentTop,
                contentBottom: contentBottom, outputTop: outputTop, width: width, height: height
            ).map { piece -> Piece in
                var result = piece
                if options.axis == .horizontal { result.segmentID = pageIndex }
                return result
            }
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
        var omittedOccludedBottomRows = false
        let assembled = ProcessInfo.processInfo.systemUptime
        for (index, page) in pages.enumerated() {
            let outputURL = outputDirectory.appendingPathComponent(
                String(format: "longshot-%02d.jpg", index + 1)
            )
            if options.axis == .horizontal {
                let omitted = try renderHorizontal(page: page, originalHeight: width, topCropRatio: topCropRatio,
                                                  plans: horizontalPlans, to: outputURL)
                omittedOccludedBottomRows = omittedOccludedBottomRows || omitted
            } else {
                try render(page: page, width: width, to: outputURL)
            }
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
            ),
            preparedFrameCount: preparedFrameCount,
            preparedAlignmentCount: preparedAlignmentCount,
            omittedOccludedBottomRows: omittedOccludedBottomRows
        )
    }

    /// Use the exact committed JPEG bytes, not the uncompressed capture buffer:
    /// matching must see the same pixels as the unchanged fallback path.
    func prepareFrame(at url: URL, encodedData: Data) throws -> PreparedFrame {
        let identity = try FramePreparationCache.sourceIdentity(for: url)
        guard identity.bytes == encodedData.count,
              let image = UIImage(data: encodedData), let cgImage = image.cgImage else {
            throw StitchError.unreadableFrame(url)
        }
        let working = try workingImage(cgImage)
        let gray = try makeGrayFrame(from: working)
        let alignment = try makeAlignmentGrayFrame(from: working)
        let overlay = CaptureOverlayDetector.inspect(cgImage)
        return PreparedFrame(
            version: FramePreparationCache.version, sourceByteCount: identity.bytes,
            sourceModifiedAt: identity.modifiedAt, imageWidth: working.width, imageHeight: working.height,
            coarseHeight: gray.height, coarsePixels: Data(gray.pixels),
            alignmentHeight: alignment.height, alignmentPixels: Data(alignment.pixels),
            coveredTop: options.axis == .horizontal ? 0 : Double(ceil(CGFloat(cgImage.height) * overlay.coveredTopRatio)),
            isSystemPanel: overlay.isSystemPanel || (options.axis == .horizontal && overlay.coveredTopRatio > 0),
            axis: options.axis, sampleWidth: gray.width
        )
    }

    private func horizontalMotionObservation(_ url: URL, registration: HorizontalGridRegistration?) throws -> GrayFrame {
        guard let source = UIImage(contentsOfFile: url.path)?.cgImage else { throw StitchError.unreadableFrame(url) }
        let width = source.width, headerRows = registration == nil ? 0 : 32, bodyRows = 128
        let rows = headerRows + bodyRows
        var pixels = [UInt8](repeating: 0, count: width * rows)
        func band(_ rect: CGRect, destination: Int, count: Int) throws {
            guard let cropped = source.cropping(to: rect) else { throw StitchError.inconsistentFrameSize }
            let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
                guard let base = bytes.baseAddress,
                      let context = CGContext(data: base.advanced(by: destination * width), width: width, height: count,
                        bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
                context.interpolationQuality = .medium
                context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: count)); return true
            }
            if !rendered { throw StitchError.couldNotEncode }
        }
        if let registration {
            try band(CGRect(x: 0, y: registration.headerTop + 2, width: width,
                            height: registration.top - registration.headerTop - 5), destination: 0, count: headerRows)
            // Frozen columns follow the table body's small Y movement. Compare
            // them in common body coordinates, not against the static toolbar.
            let shift = registration.shifts[url] ?? 0
            try band(CGRect(x: 0, y: registration.commonTop + shift, width: width,
                            height: registration.commonBottom - registration.commonTop), destination: headerRows, count: bodyRows)
        } else {
            try band(CGRect(x: 0, y: source.height / 4, width: width, height: source.height / 2),
                     destination: 0, count: bodyRows)
        }
        return GrayFrame(width: width, height: rows, pixels: pixels)
    }

    private func makeHorizontalTableLayers(from url: URL, headerTop: Int,
        registration: HorizontalGridRegistration, masks: [CGRect], frozenLeadingPixels: Int) throws -> HorizontalTableLayers {
        guard let original = UIImage(contentsOfFile: url.path)?.cgImage else {
            throw StitchError.unreadableFrame(url)
        }
        let left = frozenLeadingPixels
        let nativeWidth = original.width - left
        // Use the first moving label band, not all the coloured/repeating
        // fields below it. Those fields can swamp the sparse column identity
        // and make an off-screen patch appear to match another repeated column.
        // This changes analysis only, never the output's retained rows.
        let headerBottom = min(registration.top - 3, headerTop + registration.rowPeriod)
        let bodyTop = registration.top + max(6, original.height / 300)
        var bodyBottom = registration.bottom - max(8, (registration.bottom - registration.top) / 10)
        for mask in masks where mask.minY > CGFloat(bodyTop + (registration.bottom - bodyTop) / 2) {
            bodyBottom = min(bodyBottom, Int(floor(mask.minY)) - 4)
        }
        guard headerBottom - headerTop >= 12, bodyBottom - bodyTop >= 80, nativeWidth >= 64 else {
            throw StitchError.unseenGap
        }
        func gray(top: Int, bottom: Int) throws -> GrayFrame {
            let rows = bottom - top
            guard let cropped = original.cropping(to: CGRect(x: left, y: top, width: nativeWidth, height: rows)) else {
                throw StitchError.inconsistentFrameSize
            }
            var pixels = [UInt8](repeating: 0, count: nativeWidth * rows)
            let valid = pixels.withUnsafeMutableBytes { memory -> Bool in
                guard let context = CGContext(data: memory.baseAddress, width: nativeWidth, height: rows,
                    bitsPerComponent: 8, bytesPerRow: nativeWidth,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
                context.interpolationQuality = .none
                context.draw(cropped, in: CGRect(x: 0, y: 0, width: nativeWidth, height: rows))
                return true
            }
            guard valid else { throw StitchError.couldNotEncode }
            return GrayFrame(width: nativeWidth, height: rows, pixels: pixels)
        }
        return HorizontalTableLayers(header: try gray(top: headerTop, bottom: headerBottom),
            body: try gray(top: bodyTop, bottom: bodyBottom))
    }

    private func identicalCapturedFrame(_ a: URL, _ b: URL) throws -> Bool {
        if a == b { return true }
        // The layer crops intentionally exclude UI and overlays. A change in
        // those excluded pixels must not let a periodic moving table take the
        // "stationary" shortcut merely because the two crops look identical.
        return try Data(contentsOf: a, options: .mappedIfSafe) == Data(contentsOf: b, options: .mappedIfSafe)
    }

    private func sameViewport(_ a: GrayFrame, _ b: GrayFrame) -> Bool {
        if options.axis == .vertical { return OverlapEstimator.meanAbsoluteDifference(a, b) < 2.6 }
        return HorizontalScrollMatcher.sameViewport(a, b)
    }

    private func sample(url: URL) throws -> FrameSample {
        guard let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else {
            throw StitchError.unreadableFrame(url)
        }
        let working = try workingImage(cgImage)
        let imageSize = CGSize(width: working.width, height: working.height)
        let gray = try makeGrayFrame(from: working)
        let overlay = CaptureOverlayDetector.inspect(cgImage)
        return FrameSample(
            url: url, imageSize: imageSize, gray: gray,
            coveredTop: options.axis == .horizontal ? 0 : ceil(imageSize.height * overlay.coveredTopRatio),
            isSystemPanel: overlay.isSystemPanel || (options.axis == .horizontal && overlay.coveredTopRatio > 0)
        )
    }

    /// Transpose only the matching view. Final rendering uses original JPEGs
    /// directly, at 1:1 scale, without rotated intermediate JPEGs or re-encoding.
    private func workingImage(_ original: CGImage) throws -> CGImage {
        guard options.axis == .horizontal else { return original }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let size = CGSize(width: original.height, height: original.width)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: original, scale: 1, orientation: .leftMirrored).draw(in: CGRect(origin: .zero, size: size))
        }
        guard let result = image.cgImage else { throw StitchError.couldNotEncode }
        return result
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
            if $0.start != $1.start { return $0.start < $1.start }
            // A stationary opening can still contain a collapsing system
            // animation. At the same confirmed table position, prefer the
            // latest pixels without removing any part of the captured extent.
            return options.axis == .horizontal
                ? $0.frame.index > $1.frame.index : $0.frame.index < $1.frame.index
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

        let targetWidth = options.axis == .horizontal ? 384 : 72
        // In horizontal mode, exclude fixed top/bottom chrome from matching,
        // not from the rendered table. Rows/columns remain in their real order.
        let crossInset = options.axis == .horizontal ? floor(sourceWidth * 0.09) : 0
        let crossWidth = options.axis == .horizontal ? floor(sourceWidth * 0.82) : sourceWidth
        let targetHeight = max(96, Int(round((contentHeight / crossWidth) * CGFloat(targetWidth))))
        let cropRect = CGRect(x: crossInset, y: top, width: crossWidth, height: contentHeight)
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
        return try makeAlignmentGrayFrame(from: workingImage(cgImage))
    }

    private func makeAlignmentGrayFrame(from cgImage: CGImage) throws -> GrayFrame {
        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let top = floor(sourceHeight * topInsetRatio)
        let bottom = ceil(sourceHeight * bottomInsetRatio)
        let contentHeight = sourceHeight - top - bottom
        guard contentHeight > 0 else { throw StitchError.inconsistentFrameSize }

        let targetWidth = options.axis == .horizontal ? 384 : 72
        let targetHeight = Int(contentHeight)
        let crossInset = options.axis == .horizontal ? floor(sourceWidth * 0.09) : 0
        let crossWidth = options.axis == .horizontal ? floor(sourceWidth * 0.82) : sourceWidth
        let cropRect = CGRect(x: crossInset, y: top, width: crossWidth, height: contentHeight)
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
                    ), segmentID: piece.segmentID
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

    private func renderHorizontal(page: [Piece], originalHeight: CGFloat, topCropRatio: Double,
        plans: [Int: HorizontalSegmentPlan] = [:], bottomCuts: [Int: CGFloat] = [:], to outputURL: URL) throws -> Bool {
        let width = page.reduce(CGFloat(0)) { $0 + $1.sourceRect.height }
        let statusHeight = min(floor(originalHeight * 0.075), ceil(originalHeight * max(0, topCropRatio)))
        let headerHeight = options.keepsStatusBar ? statusHeight : 0
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        // Each explicit page keeps its fixed top/bottom chrome once. Moving
        // column headings remain in the table because they differ across frames.
        var groups: [[Piece]] = []
        for piece in page {
            if piece.frameURL == nil { groups.append([piece]); continue }
            if groups.last?.last?.frameURL == nil { groups.append([]) }
            groups[groups.count - 1].append(piece)
        }
        let registrations = groups.map { group in
            group.first?.segmentID.flatMap { plans[$0]?.grid }
        }
        let insets = groups.enumerated().map { index, group in
            if let registration = registrations[index] {
                return (top: registration.headerTop, bottom: Int(originalHeight) - registration.bottom)
            }
            return fixedHorizontalInsets(group, height: Int(originalHeight), statusHeight: Int(statusHeight))
        }
        let omissions = groups.indices.map { index -> CGFloat in
            guard let cutoff = bottomCuts[index] else { return 0 }
            // cutoff is already in the registered output coordinates. The
            // shared-body crop must not be subtracted a second time.
            return max(0, originalHeight - CGFloat(insets[index].bottom)
                - CGFloat(registrations[index]?.crop ?? 0) - cutoff)
        }
        let crop = groups.indices.map { CGFloat(registrations[$0]?.crop ?? 0) + omissions[$0] }.min() ?? 0
        let height = originalHeight - statusHeight + headerHeight - crop
        var unreadable: URL?
        var repairError: Error?
        var fallbackCuts = bottomCuts
        var image: UIImage? = autoreleasepool {
          UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var destinationX: CGFloat = 0
            for (groupIndex, group) in groups.enumerated() {
                let startX = destinationX
                let top = CGFloat(insets[groupIndex].top), originalBottom = CGFloat(insets[groupIndex].bottom)
                let omission = omissions[groupIndex], bottom = originalBottom + omission
                let registration = registrations[groupIndex]
                let groupCrop = CGFloat(registration?.crop ?? 0)
#if LONGSHOT_CAPTURE_CHECKS
                if let registration {
                    Self.alignmentTrace?("horizontal grid top=\(registration.top) bottom=\(registration.bottom) common=\(registration.commonTop)..<\(registration.commonBottom) crop=\(registration.crop)")
                }
#endif
                for piece in group {
                    autoreleasepool {
                        guard let frameURL = piece.frameURL else {
                            UIColor(white: 0.93, alpha: 1).setFill()
                            context.fill(CGRect(x: destinationX, y: headerHeight, width: piece.sourceRect.height,
                                                height: originalHeight - statusHeight))
                            return
                        }
                        guard let source = UIImage(contentsOfFile: frameURL.path) else { unreadable = frameURL; return }
                        func drawBand(top: CGFloat, height: CGFloat, translation: CGFloat = 0) {
                            guard height > 0 else { return }
                            context.cgContext.saveGState()
                            context.cgContext.clip(to: CGRect(x: destinationX, y: headerHeight + top - statusHeight,
                                width: piece.sourceRect.height, height: height))
                            source.draw(at: CGPoint(x: destinationX - piece.sourceRect.minY,
                                y: headerHeight - statusHeight + translation))
                            context.cgContext.restoreGState()
                        }
                        if let registration {
                            drawBand(top: top, height: CGFloat(registration.top) - top)
                            drawBand(top: CGFloat(registration.top), height: CGFloat(registration.commonBottom - registration.commonTop) - omission,
                                     translation: registration.translation(for: frameURL))
                        } else {
                            drawBand(top: top, height: originalHeight - top - bottom)
                        }
                    }
                    destinationX += piece.sourceRect.height
                }
                do {
                    try repairFixedHorizontalOverlays(group, context: context.cgContext, startX: startX,
                        yOffset: headerHeight - statusHeight, top: top, bottom: bottom, originalHeight: originalHeight,
                        registration: registration,
                        frozenLeadingPixels: group.first?.segmentID.flatMap { plans[$0]?.frozenLeadingPixels } ?? 0,
                        plan: group.first?.segmentID.flatMap { plans[$0] })
                } catch let gap as HorizontalOverlayGap {
                    let urls = group.first?.segmentID.flatMap { plans[$0]?.frames.map(\.url) }
                        ?? group.compactMap(\.frameURL)
                    if bottomCuts[groupIndex] == nil,
                       let cutoff = completeHorizontalRowEnd(urls, above: gap.top,
                            contentTop: top, registration: registration) {
                        fallbackCuts[groupIndex] = cutoff
#if LONGSHOT_CAPTURE_CHECKS
                        Self.alignmentTrace?("overlay fallback complete rows end=\(cutoff) previousEnd=\(originalHeight - originalBottom)")
#endif
                    } else { repairError = StitchError.unseenGap }
                } catch { repairError = error }
                if let url = group.first?.frameURL, let source = UIImage(contentsOfFile: url.path) {
                    context.cgContext.saveGState()
                    let chromeWidth = min(destinationX - startX, source.size.width)
                    context.cgContext.clip(to: CGRect(x: startX, y: headerHeight, width: chromeWidth, height: top - statusHeight))
                    source.draw(at: CGPoint(x: startX, y: headerHeight - statusHeight))
                    context.cgContext.restoreGState()
                    let footerTop = registration.map { CGFloat($0.bottom) } ?? (originalHeight - originalBottom)
                    context.cgContext.saveGState()
                    context.cgContext.clip(to: CGRect(x: startX, y: headerHeight - statusHeight + footerTop - groupCrop - omission,
                        width: chromeWidth, height: originalHeight - footerTop))
                    source.draw(at: CGPoint(x: startX, y: headerHeight - statusHeight - groupCrop - omission))
                    context.cgContext.restoreGState()
                }
            }
            // Preserve one authentic status bar, not a stretched/repeated row
            // of time, battery and recording indicators across a wide image.
            if headerHeight > 0, let url = page.compactMap(\.frameURL).first,
               let source = UIImage(contentsOfFile: url.path) {
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: 0, width: min(width, source.size.width), height: headerHeight))
                source.draw(at: .zero)
                context.cgContext.restoreGState()
            }
        }
        }
        if let repairError { throw repairError }
        if let unreadable { throw StitchError.unreadableFrame(unreadable) }
        if fallbackCuts != bottomCuts {
            // Release the full-size first canvas before allocating the retry.
            image = nil
            // Retry only an unsupported bottom overlay, never an unmatched
            // column or internal table gap. Each affected segment retries once.
            return try renderHorizontal(page: page, originalHeight: originalHeight, topCropRatio: topCropRatio,
                plans: plans, bottomCuts: fallbackCuts, to: outputURL)
        }
        guard let data = image?.jpegData(compressionQuality: 0.94) else { throw StitchError.couldNotEncode }
        try data.write(to: outputURL, options: .atomic)
        return !bottomCuts.isEmpty
    }

    /// Find a real row divider above the occlusion in independently observed
    /// viewports. This is not a fixed-percent crop: if a complete row boundary
    /// cannot be established, retain the original failure instead of cutting
    /// through text. Never apply this fallback to central/non-bottom overlays.
    private func completeHorizontalRowEnd(_ urls: [URL], above limit: CGFloat,
        contentTop: CGFloat, registration: HorizontalGridRegistration?) -> CGFloat? {
        guard let first = urls.first, let image = UIImage(contentsOfFile: first.path)?.cgImage,
              limit > CGFloat(image.height) * 0.65 else { return nil }
        let width = 192, height = image.height
        var chosen: [URL] = []
        for url in [first, urls[urls.count / 2], urls[urls.count - 1]] where !chosen.contains(url) { chosen.append(url) }
        guard chosen.count >= 2 else { return nil }
        let profiles: [[UInt8]] = chosen.compactMap { url in
            autoreleasepool {
                guard let source = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
                var pixels = [UInt8](repeating: 0, count: width * height)
                let ok = pixels.withUnsafeMutableBytes { memory -> Bool in
                    guard let c = CGContext(data: memory.baseAddress, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
                    c.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
                }
                return ok ? pixels : nil
            }
        }
        guard profiles.count == chosen.count else { return nil }
        let minimumTranslation = chosen.map { registration?.translation(for: $0) ?? 0 }.min() ?? 0
        let upper = min(height - 4, Int(floor(limit + minimumTranslation)) - 4)
        let lower = max(Int(contentTop) + 40, upper - height / 5)
        guard upper > lower else { return nil }
        for y in stride(from: upper, through: lower, by: -1) {
            let supported = zip(chosen, profiles).allSatisfy { url, p in
                let sourceY = y - Int(registration?.translation(for: url) ?? 0)
                guard sourceY > 3, sourceY < height - 4 else { return false }
                var votes = 0
                for x in 8..<(width - 5) {
                    let ink = Int(p[sourceY * width + x])
                    let surround = min(Int(p[(sourceY - 3) * width + x]), Int(p[(sourceY + 3) * width + x]))
                    if ink < 232 && surround - ink >= 12 { votes += 1 }
                }
                return votes * 5 >= (width - 13) * 3
            }
            if supported { return CGFloat(y + 1) }
        }
        return nil
    }

    private func repairFixedHorizontalOverlays(_ pieces: [Piece], context: CGContext, startX: CGFloat,
        yOffset: CGFloat, top: CGFloat, bottom: CGFloat, originalHeight: CGFloat,
        registration: HorizontalGridRegistration? = nil, frozenLeadingPixels: Int = 0,
        plan: HorizontalSegmentPlan? = nil) throws {
        var frames: [(url: URL, offset: CGFloat)] = [], cursor: CGFloat = 0
        for piece in pieces {
            if let url = piece.frameURL, !frames.contains(where: { $0.url == url }) {
                frames.append((url, cursor - piece.sourceRect.minY))
            }
            cursor += piece.sourceRect.height
        }
        if let plan, let first = pieces.first, let url = first.frameURL,
           let anchor = plan.frames.first(where: { $0.url == url }) {
            let origin = anchor.offset + first.sourceRect.minY
            // All registered observations may recover a covered cell, including
            // frames which added no new output extent. Pagination merely clips
            // this common coordinate system; it must not reset its origin.
            frames = plan.frames.map { ($0.url, $0.offset - origin) }
        }
        guard frames.count > 1 else { return }
        // A coloured selection/badge inside the frozen pane is table content,
        // not a moving-region occlusion. It already appears once in that pane.
        let overlays = fixedHorizontalColorOverlays(frames.map(\.url), top: top, bottom: bottom, height: originalHeight)
            .filter { $0.maxX > CGFloat(frozenLeadingPixels) }
#if LONGSHOT_CAPTURE_CHECKS
        Self.alignmentTrace?("overlay masks=\(overlays) body=\(top)..<\(originalHeight - bottom)")
#endif
        guard !overlays.isEmpty else { return }
        let masks = frames.map { frame in overlays.map { $0.offsetBy(dx: 0, dy: registration?.translation(for: frame.url) ?? 0) } }
        let first = frames.indices.min(by: { frames[$0].offset < frames[$1].offset })!
        let last = frames.indices.max(by: { frames[$0].offset < frames[$1].offset })!
        // A control crossing the frozen boundary covers pixels that can never
        // be exposed by horizontal scrolling. Keep that entire control once at
        // the frozen edge; controls wholly in the moving layer stay at the end.
        let retained = overlays.indices.map { index in
            (frame: overlays[index].minX < CGFloat(frozenLeadingPixels) ? first : last, mask: index)
        }
        let boundaries = Array(Set(masks.flatMap { $0.flatMap { [$0.minY, $0.maxY] } })).sorted()
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: CGRect(x: startX, y: yOffset + CGFloat(registration?.top ?? Int(top)), width: cursor,
            height: registration.map { CGFloat($0.commonBottom - $0.commonTop) } ?? (originalHeight - top - bottom)))
        let sizes = try frames.map { frame -> CGSize in
            guard let size = UIImage(contentsOfFile: frame.url.path)?.size else { throw StitchError.unreadableFrame(frame.url) }
            return size
        }
        var drawPlans: [Int: [CGRect]] = [:]
        for (low, high) in zip(boundaries, boundaries.dropFirst()) {
            guard masks.contains(where: { $0.contains(where: { $0.minY < high && $0.maxY > low }) }) else { continue }
            var spans: [(start: CGFloat, end: CGFloat, frame: Int)] = []
            for (index, frame) in frames.enumerated() {
                let size = sizes[index]
                let hasFrozenLayer = plan.map { plan in plan.frames.contains { $0.url == frame.url && $0.offset == 0 } }
                    ?? (frame.offset == 0)
                let left = hasFrozenLayer ? 0 : CGFloat(frozenLeadingPixels)
                var visible = [CGRect(x: left, y: low, width: size.width - left, height: high - low)]
                for mask in masks[index].filter({ $0.minY < high && $0.maxY > low }) {
                    visible = visible.flatMap { rect -> [CGRect] in
                        guard rect.intersects(mask) else { return [rect] }
                        var result: [CGRect] = []
                        if rect.minX < mask.minX { result.append(CGRect(x: rect.minX, y: low, width: mask.minX - rect.minX, height: high - low)) }
                        if rect.maxX > mask.maxX { result.append(CGRect(x: mask.maxX, y: low, width: rect.maxX - mask.maxX, height: high - low)) }
                        return result
                    }
                }
                for rect in visible where rect.width > 0 {
                    spans.append((frame.offset + rect.minX, frame.offset + rect.maxX, index))
                }
            }
            spans.sort { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }
            // Coverage certificate: every output pixel in an occluded band
            // must be observed elsewhere, or belong to the single authentic
            // final control retained below. Never leave repeated fragments in
            // an interior hole and report the result as a complete table.
            var supported = spans.map { ($0.start, $0.end) }
            for anchor in retained {
                let mask = masks[anchor.frame][anchor.mask]
                if mask.minY < high && mask.maxY > low {
                    supported.append((frames[anchor.frame].offset + mask.minX, frames[anchor.frame].offset + mask.maxX))
                }
            }
            supported.sort { $0.0 < $1.0 }
            var verified: CGFloat = 0
            for interval in supported where interval.1 > verified && interval.0 < cursor {
                guard interval.0 <= verified else {
#if LONGSHOT_CAPTURE_CHECKS
                    Self.alignmentTrace?("overlay unseen band=\(low)..<\(high) x=\(verified)..<\(interval.0) frozen=\(frozenLeadingPixels)")
#endif
                    throw HorizontalOverlayGap(top: overlays.map(\.minY).min() ?? low)
                }
                verified = min(cursor, interval.1)
            }
            guard verified >= cursor else { throw HorizontalOverlayGap(top: overlays.map(\.minY).min() ?? low) }
            var covered: CGFloat = 0
            for span in spans {
                guard span.end > covered else { continue }
                // Restore only actual overlapping pixels. A permanently hidden
                // region remains the original overlay rather than fake content.
                let begin = max(0, max(span.start, covered)), end = min(cursor, span.end)
                guard end > begin else { continue }
                drawPlans[span.frame, default: []].append(CGRect(x: startX + begin, y: yOffset + low,
                    width: end - begin, height: high - low))
                covered = end
            }
        }
        // Decode a source once for all of its disjoint repair strips, instead
        // of repeatedly decoding the full JPEG for each mask-height band.
        for index in frames.indices {
            guard let clips = drawPlans[index], !clips.isEmpty else { continue }
            let frame = frames[index]
            try autoreleasepool {
                guard let image = UIImage(contentsOfFile: frame.url.path) else { throw StitchError.unreadableFrame(frame.url) }
                context.saveGState()
                context.clip(to: clips)
                image.draw(at: CGPoint(x: startX + frame.offset,
                    y: yOffset + (registration?.translation(for: frame.url) ?? 0)))
                context.restoreGState()
            }
        }
        // The final edge may never have been visible behind its floating
        // control. Preserve that authentic control whole once, rather than
        // half-erasing it into alternating blue and white fragments.
        for index in Set(retained.map(\.frame)).sorted() {
            let frame = frames[index]
            try autoreleasepool {
                guard let image = UIImage(contentsOfFile: frame.url.path) else { throw StitchError.unreadableFrame(frame.url) }
                context.saveGState()
                context.clip(to: retained.filter { $0.frame == index }.map {
                    masks[index][$0.mask].offsetBy(dx: startX + frame.offset, dy: yOffset)
                })
                image.draw(at: CGPoint(x: startX + frame.offset,
                    y: yOffset + (registration?.translation(for: frame.url) ?? 0)))
                context.restoreGState()
            }
        }
    }

    /// Persistent saturated floating controls (such as Sheets' blue toolbox).
    /// Broad coloured table rows and transient/different controls do not qualify.
    private func fixedHorizontalColorOverlays(_ urls: [URL], top: CGFloat, bottom: CGFloat, height: CGFloat) -> [CGRect] {
        guard let firstURL = urls.first, let original = UIImage(contentsOfFile: firstURL.path)?.cgImage else { return [] }
        let width = 192, rows = Int(round(height * CGFloat(width) / CGFloat(original.width)))
        var chosen: [URL] = []
        for url in [urls[0], urls[urls.count / 2], urls[urls.count - 1]] where !chosen.contains(url) { chosen.append(url) }
        let images: [[UInt8]] = chosen.compactMap { url in
            autoreleasepool {
                guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
                var data = [UInt8](repeating: 0, count: width * rows * 4)
                let ok = data.withUnsafeMutableBytes { m -> Bool in
                    guard let c = CGContext(data: m.baseAddress, width: width, height: rows, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    c.draw(image, in: CGRect(x: 0, y: 0, width: width, height: rows)); return true
                }
                return ok ? data : nil
            }
        }
        guard images.count == chosen.count, images.count > 1 else { return [] }
        var stable = [Bool](repeating: false, count: width * rows)
        for y in 0..<rows { for x in 0..<width {
            let i = (y * width + x) * 4, color = (0..<3).map { Int(images[0][i + $0]) }
            guard color.max()! - color.min()! > 64 else { continue }
            stable[y * width + x] = images.dropFirst().allSatisfy { image in
                (0..<3).allSatisfy { abs(Int(image[i + $0]) - color[$0]) < 24 }
            }
        } }
        var boxes: [CGRect] = [], blueControls: [CGRect] = [], blueGlyphs: [CGRect] = []
        let scale = CGFloat(original.width) / CGFloat(width)
        for index in stable.indices where stable[index] {
            var queue = [index], head = 0, left = index % width, right = left, low = index / width, high = low
            stable[index] = false
            while head < queue.count {
                let i = queue[head]; head += 1
                let x = i % width, y = i / width
                left = min(left, x); right = max(right, x); low = min(low, y); high = max(high, y)
                for (xx, yy) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                    where xx >= 0 && xx < width && yy >= 0 && yy < rows {
                    let j = yy * width + xx
                    if stable[j] { stable[j] = false; queue.append(j) }
                }
            }
            let box = CGRect(x: max(0, floor(CGFloat(left) * scale) - 2),
                y: max(top, floor(CGFloat(low) * scale) - 2),
                width: min(CGFloat(original.width), ceil(CGFloat(right + 1) * scale) + 2) - max(0, floor(CGFloat(left) * scale) - 2),
                height: min(height - bottom, ceil(CGFloat(high + 1) * scale) + 2) - max(top, floor(CGFloat(low) * scale) - 2))
            guard box.height > 0, CGFloat(low) * scale > top, CGFloat(high) * scale < height - bottom else { continue }
            let blue = queue.filter { index in
                let i = index * 4
                return Int(images[0][i + 2]) - Int(images[0][i]) > 50
            }.count * 2 > queue.count
            if blue, queue.count >= 6, right - left >= 2, high - low >= 3 { blueGlyphs.append(box) }
            if queue.count >= 30, right - left >= 10, high - low >= 5, right - left < width * 2 / 3 {
                boxes.append(box)
                if blue { blueControls.append(box) }
            }
        }
        // A white round button can be part of a compound floating control.
        // Its small blue glyph is independently stable at screen coordinates;
        // only associate it with a nearby, already-proven large blue control.
        // Include the neutral surround and shadow, not just the coloured ink.
        var neutralPanels: [CGRect] = []
#if LONGSHOT_CAPTURE_CHECKS
        Self.alignmentTrace?("overlay proof controls=\(blueControls) glyphs=\(blueGlyphs)")
#endif
        for control in blueControls {
            let neighbors = blueGlyphs.filter { glyph in
                glyph.maxX < control.minX && control.minX - glyph.midX < control.height * 1.5
                    && abs(glyph.midY - control.midY) < control.height * 0.3
                    && glyph.width < control.height * 0.7 && glyph.height < control.height * 0.7
            }
            guard !neighbors.isEmpty else { continue }
            let glyph = neighbors.reduce(CGRect.null) { $0.union($1) }
            let side = ceil(control.height * 1.16)
            let circle = CGRect(x: floor(glyph.midX - side / 2), y: floor(control.midY - side / 2), width: side, height: side)
                .intersection(CGRect(x: 0, y: top, width: CGFloat(original.width), height: height - top - bottom))
            if !circle.isNull { boxes.append(circle); neutralPanels.append(circle) }
        }
        // An independent keyboard button can share that baseline without
        // touching the toolbox. A stable blue mark alone is not evidence of a
        // floating button: prove its white interior and curved neutral rim in
        // every sampled frame. Never union distant glyphs into one large mask.
        func hasWhiteRoundPanel(_ circle: CGRect) -> Bool {
            func evidence(_ image: [UInt8], pixelWidth: Int, pixelRows: Int,
                centerX: CGFloat, centerY: CGFloat, side: CGFloat) -> Bool {
                guard side >= 7 else { return false }
                func pixel(_ x: CGFloat, _ y: CGFloat) -> (light: CGFloat, neutral: Bool)? {
                    guard x >= 0, y >= 0, x < CGFloat(pixelWidth - 1), y < CGFloat(pixelRows - 1) else { return nil }
                    let x0 = Int(floor(x)), y0 = Int(floor(y)), fx = x - CGFloat(x0), fy = y - CGFloat(y0)
                    let colors: [CGFloat] = (0..<3).map { channel in
                        let a = CGFloat(image[(y0 * pixelWidth + x0) * 4 + channel])
                        let b = CGFloat(image[(y0 * pixelWidth + x0 + 1) * 4 + channel])
                        let c = CGFloat(image[((y0 + 1) * pixelWidth + x0) * 4 + channel])
                        let d = CGFloat(image[((y0 + 1) * pixelWidth + x0 + 1) * 4 + channel])
                        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
                    }
                    return (colors.reduce(0, +) / 3, colors.max()! - colors.min()! < 18)
                }
                var whiteInside = 0, curvedRim = 0, diagonalRim = 0, cornerRim = 0
                var edgeRadii = [CGFloat?](repeating: nil, count: 16)
                for step in 0..<16 {
                    let angle = CGFloat(step) * .pi / 8, dx = cos(angle), dy = sin(angle)
                    guard let inner = pixel(centerX + dx * side * 0.27, centerY + dy * side * 0.27),
                          inner.neutral, inner.light > 232 else { continue }
                    whiteInside += 1
                    // Search a narrow radial band, not a broad rectangular
                    // surround. A table grid or a white card cannot establish
                    // a nearly circular edge in diagonal directions as well.
                    // The component bbox includes antialiasing padding, so its
                    // inferred circle is deliberately larger than the panel.
                    // Search densely enough to retain subpixel thin rims.
                    let ring = stride(from: CGFloat(0.32), through: CGFloat(0.49), by: CGFloat(0.01)).compactMap { radius -> (radius: CGFloat, light: CGFloat)? in
                        guard let value = pixel(centerX + dx * side * radius, centerY + dy * side * radius), value.neutral else { return nil }
                        return (radius, value.light)
                    }
                    let rim = ring.map(\.light).min()
                    if let rim, inner.light - rim >= 7 {
                        if let edge = ring.first(where: { inner.light - $0.light >= 7 }) { edgeRadii[step] = edge.radius }
                        curvedRim += 1
                        if step % 4 != 0 { diagonalRim += 1 }
                        if step % 4 == 2 { cornerRim += 1 }
                    }
                }
                // Opposite rays cancel small glyph/baseline centering errors.
                // A circle has the same paired radius around its perimeter;
                // a square's diagonal radius is ~1.414 times its axis radius.
                // Per-ray dark pixels alone must never establish roundness.
                let pairedRadii = (0..<8).compactMap { step -> (direction: Int, radius: CGFloat)? in
                    guard let first = edgeRadii[step], let opposite = edgeRadii[step + 8] else { return nil }
                    return (step, (first + opposite) / 2)
                }
                let radiusSpread = (pairedRadii.map(\.radius).max() ?? 1) - (pairedRadii.map(\.radius).min() ?? 0)
                // A neighboring control/grid can occlude a small arc. Require
                // a dominant common-radius consensus, not unrelated outliers;
                // that same consensus must contain both axial and diagonal
                // evidence, so a square cannot qualify on its straight sides.
                let requiredPairs = max(5, Int(ceil(CGFloat(pairedRadii.count) * 0.7)))
                let coherentCircle = pairedRadii.contains { anchor in
                    let consensus = pairedRadii.filter { $0.radius >= anchor.radius && $0.radius - anchor.radius <= 0.045 }
                    return consensus.count >= requiredPairs
                        && consensus.contains(where: { $0.direction == 0 || $0.direction == 4 })
                        && consensus.contains(where: { $0.direction == 2 || $0.direction == 6 })
                }
#if LONGSHOT_CAPTURE_CHECKS
                Self.alignmentTrace?("overlay circle=\(circle) pixels=\(pixelWidth)x\(pixelRows) white=\(whiteInside) rim=\(curvedRim) diagonal=\(diagonalRim) corner=\(cornerRim) radii=\(edgeRadii) pairs=\(pairedRadii.count) spread=\(radiusSpread)")
#endif
                return whiteInside >= 12 && curvedRim >= 8 && diagonalRim >= 6 && cornerRim >= 3 && coherentCircle
            }
            if images.allSatisfy({ evidence($0, pixelWidth: width, pixelRows: rows,
                centerX: circle.midX / scale, centerY: circle.midY / scale, side: circle.width / scale) }) { return true }
            // Downsampling can erase a subpixel gray rim. Retry only this
            // small candidate ROI at native resolution with identical shape
            // thresholds, never a broader mask or a guessed white background.
            return chosen.allSatisfy { url in
                autoreleasepool {
                    let image = url == firstURL ? original : UIImage(contentsOfFile: url.path)?.cgImage
                    let region = circle.integral
                    guard let image, let crop = image.cropping(to: region) else { return false }
                    var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
                    let drawn = pixels.withUnsafeMutableBytes { memory -> Bool in
                        guard let context = CGContext(data: memory.baseAddress, width: crop.width, height: crop.height,
                            bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
                        return true
                    }
                    return drawn && evidence(pixels, pixelWidth: crop.width, pixelRows: crop.height,
                        centerX: circle.midX - region.minX, centerY: circle.midY - region.minY, side: circle.width)
                }
            }
        }
        for control in blueControls {
            for glyph in blueGlyphs where !glyph.intersects(control)
                && abs(glyph.midY - control.midY) < control.height * 0.3
                && glyph.width < control.height * 0.7 && glyph.height < control.height * 0.7 {
                let side = ceil(control.height * 1.16)
                let circle = CGRect(x: floor(glyph.midX - side / 2), y: floor(control.midY - side / 2), width: side, height: side)
                guard circle.minX >= 0, circle.maxX <= CGFloat(original.width),
                      circle.minY >= top, circle.maxY <= height - bottom,
                      !neutralPanels.contains(where: { abs($0.midX - circle.midX) < side * 0.3 && abs($0.midY - circle.midY) < side * 0.3 }),
                      hasWhiteRoundPanel(circle) else { continue }
                boxes.append(circle)
                neutralPanels.append(circle)
            }
        }
        return boxes.count <= 8 ? boxes : []
    }

    /// Only remove the repetition of rows that are unchanged at the same
    /// viewport coordinates across distant accepted frames. Keep the original
    /// row once; never guess or crop a fixed percentage of the actual table.
    private func fixedHorizontalInsets(_ pieces: [Piece], height: Int, statusHeight: Int) -> (top: Int, bottom: Int) {
        var urls: [URL] = []
        for url in pieces.compactMap(\.frameURL) where !urls.contains(url) { urls.append(url) }
        guard urls.count > 1 else { return (statusHeight, 0) }
        var selected: [URL] = []
        for url in [urls[0], urls[urls.count / 2], urls[urls.count - 1]] where !selected.contains(url) { selected.append(url) }
        let width = 96
        let rows: [[UInt8]] = selected.compactMap { url in
            guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
            var pixels = [UInt8](repeating: 0, count: width * height)
            let valid = pixels.withUnsafeMutableBytes { memory -> Bool in
                guard let ctx = CGContext(data: memory.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
                ctx.interpolationQuality = .medium
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            return valid ? pixels : nil
        }
        guard rows.count == selected.count, let first = rows.first else { return (statusHeight, 0) }
        func unchanged(_ y: Int) -> Bool {
            rows.dropFirst().allSatisfy { other in
                var difference = 0, changed = 0
                for x in 0..<width {
                    let d = abs(Int(first[y * width + x]) - Int(other[y * width + x]))
                    difference += d
                    if d > 10 { changed += 1 }
                }
                return difference <= width && changed <= 1
            }
        }
        var top = statusHeight
        while top < Int(Double(height) * 0.25), unchanged(top) { top += 1 }
        var bottom = 0
        while bottom < Int(Double(height) * 0.20), unchanged(height - bottom - 1) { bottom += 1 }
        // A two-pixel guard leaves antialiased borders with the moving content.
        return (max(statusHeight, top - 2), max(0, bottom - 2))
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

/// Spreadsheet grids and repeated values are not unique features. Score the
/// pixels that actually changed at the same screen coordinates, retaining
/// sparse column-heading evidence instead of trimming it as an outlier. Fixed
/// toolbars/frozen cells have no motion vote; low-contrast watermarks have none.
private enum HorizontalScrollMatcher {
    static func sameViewport(_ a: GrayFrame, _ b: GrayFrame) -> Bool {
        guard a.width == b.width, a.height == b.height,
              OverlapEstimator.meanAbsoluteDifference(a, b) < 0.5 else { return false }
        for top in stride(from: 0, to: a.height, by: 12) {
            for left in stride(from: 0, to: a.width, by: 12) {
                var difference = 0, count = 0
                for y in top..<min(top + 12, a.height) {
                    for x in left..<min(left + 12, a.width) {
                        difference += abs(Int(a[x, y]) - Int(b[x, y])); count += 1
                    }
                }
                if difference > count * 3 { return false }
            }
        }
        return true
    }

    static func candidates(_ a: GrayFrame, _ b: GrayFrame) -> [ShiftEstimate] {
        estimates(a, b, around: nil, radius: 0)
    }

    /// Keep the globally selected direction and column interval. Native-axis
    /// refinement uses the same moving-band evidence as the coarse pass, so
    /// sparse sheets are not rejected for having few textured body tiles.
    /// Symmetric analysis-only filtering matches the coarse sampling scale;
    /// every rendered pixel still comes from the original JPEG.
    static func refine(from previous: GrayFrame, to current: GrayFrame,
                       around rows: Int, searchRadius: Int, smoothingRadius: Int) -> ShiftEstimate? {
        guard rows != 0, searchRadius >= 0 else { return nil }
        func smooth(_ source: GrayFrame) -> GrayFrame {
            guard smoothingRadius > 0 else { return source }
            var pixels = source.pixels
            for y in 0..<source.height {
                let first = max(0, y - smoothingRadius)
                let last = min(source.height - 1, y + smoothingRadius)
                for x in 0..<source.width {
                    var total = 0
                    for row in first...last { total += Int(source[x, row]) }
                    pixels[y * source.width + x] = UInt8(total / (last - first + 1))
                }
            }
            return GrayFrame(width: source.width, height: source.height, pixels: pixels)
        }
        return estimates(smooth(previous), smooth(current), around: rows, radius: searchRadius).first
    }

    private static func estimates(_ a: GrayFrame, _ b: GrayFrame, around: Int?, radius: Int) -> [ShiftEstimate] {
        guard a.width == b.width, a.height == b.height, a.height >= 32 else { return [] }
        let maximum = min(a.height - 8, Int(Double(a.height) * 0.78))
        let firstShift = around.map { max(-maximum, $0 - radius) } ?? -maximum
        let lastShift = around.map { min(maximum, $0 + radius) } ?? maximum
        guard firstShift <= lastShift else { return [] }
        let horizontalStride = max(1, a.width / 192)
        let verticalStride = max(1, a.height / (around == nil ? 128 : 256))
        let bandWidth = max(16, a.width / 12)
        let bandCount = (a.width + bandWidth - 1) / bandWidth
        var bandChanges = [Int](repeating: 0, count: bandCount)
        var bandSamples = [Int](repeating: 0, count: bandCount)
        for y in stride(from: 1, to: a.height - 1, by: verticalStride) {
            for x in stride(from: 1, to: a.width - 1, by: horizontalStride) {
                let band = min(bandCount - 1, x / bandWidth)
                bandSamples[band] += 1
                if abs(Int(a[x, y]) - Int(b[x, y])) >= 8 { bandChanges[band] += 1 }
            }
        }
        let weights = bandChanges.indices.map { index -> Double in
            let ratio = Double(bandChanges[index]) / Double(max(1, bandSamples[index]))
            return ratio < 0.008 ? 0 : min(1, sqrt(ratio * 5))
        }
        guard weights.contains(where: { $0 > 0 }) else { return [] }

        var scored: [(shift: Int, score: Double)] = []
        for shift in firstShift...lastShift where shift != 0
            && (around == nil || shift.signum() == around!.signum()) {
            let start = max(1, -shift)
            let end = min(a.height - 1, a.height - shift - 1)
            guard end > start else { continue }
            var differences = [Double](repeating: 0, count: bandCount)
            var counts = [Int](repeating: 0, count: bandCount)
            for y in stride(from: start, to: end, by: verticalStride) {
                let sourceY = y + shift
                for x in stride(from: 1, to: a.width - 1, by: horizontalStride) {
                    let band = min(bandCount - 1, x / bandWidth)
                    guard weights[band] > 0 else { continue }
                    let index = y * a.width + x
                    let sourceIndex = sourceY * a.width + x
                    differences[band] += Double(abs(Int(a.pixels[sourceIndex]) - Int(b.pixels[index])))
                        + Double(abs(Int(a.edges[sourceIndex]) - Int(b.edges[index]))) * 0.15
                    counts[band] += 1
                }
            }
            var weighted = 0.0, totalWeight = 0.0
            for band in 0..<bandCount where weights[band] > 0 && counts[band] > 0 {
                weighted += differences[band] / Double(counts[band]) * weights[band]
                totalWeight += weights[band]
            }
            guard totalWeight > 0 else { continue }
            let overlapRatio = Double(end - start) / Double(a.height)
            let smallOverlapPenalty = max(0, 0.28 - overlapRatio) * 10
            scored.append((shift, weighted / totalWeight + smallOverlapPenalty))
        }

        var retained: [(shift: Int, score: Double)] = []
        for sign in [-1, 1] {
            let direction = scored.filter { $0.shift.signum() == sign }.sorted { $0.score < $1.score }
            guard let best = direction.first, best.score < 18 else { continue }
            retained.append(contentsOf: direction.prefix(8).filter { $0.score <= best.score + 5 })
        }
#if LONGSHOT_CAPTURE_CHECKS
        if let trace = FrameStitcher.alignmentTrace {
            let top = retained.sorted { $0.score < $1.score }.prefix(6)
                .map { "\($0.shift):\(String(format: "%.2f", $0.score))" }.joined(separator: ",")
            trace("\(around == nil ? "coarse" : "fine") candidates [\(top)]")
        }
#endif
        return retained.sorted { $0.score < $1.score }.map {
            ShiftEstimate(rows: $0.shift, score: $0.score, confidence: 0.5)
        }
    }

    static func selectSequence(_ edgeCandidates: [[ShiftEstimate]]) -> [ShiftEstimate?] {
        guard edgeCandidates.allSatisfy({ !$0.isEmpty }) else {
            return edgeCandidates.map { candidates in
                candidates.first(where: { $0.rows == 0 })
            }
        }
        let movingEdges = edgeCandidates.indices.filter { edgeCandidates[$0].contains(where: { $0.rows != 0 }) }
        var result = [ShiftEstimate?](repeating: nil, count: edgeCandidates.count)
        for index in edgeCandidates.indices where edgeCandidates[index].allSatisfy({ $0.rows == 0 }) {
            result[index] = edgeCandidates[index].first
        }
        guard !movingEdges.isEmpty else { return result }

        let directionVotes = movingEdges.reduce(into: (negative: 0, positive: 0)) { votes, edge in
            guard let best = edgeCandidates[edge].min(by: { $0.score < $1.score }) else { return }
            if best.rows < 0 { votes.negative += 1 } else { votes.positive += 1 }
        }
        let dominantDirection: Int
        if directionVotes.positive == directionVotes.negative {
            dominantDirection = edgeCandidates[movingEdges[0]].min(by: { $0.score < $1.score })?.rows.signum() ?? 1
        } else {
            dominantDirection = directionVotes.positive > directionVotes.negative ? 1 : -1
        }

        var costs = edgeCandidates[movingEdges[0]].map { candidate in
            candidate.score + (candidate.rows.signum() == dominantDirection ? 0 : 2)
        }
        var backPointers: [[Int]] = []
        for movementIndex in 1..<movingEdges.count {
            let previous = edgeCandidates[movingEdges[movementIndex - 1]]
            let current = edgeCandidates[movingEdges[movementIndex]]
            var next = [Double](repeating: .infinity, count: current.count)
            var pointers = [Int](repeating: 0, count: current.count)
            for (currentIndex, candidate) in current.enumerated() {
                for (previousIndex, prior) in previous.enumerated() {
                    var transition = 0.0
                    if prior.rows != 0, candidate.rows != 0 {
                        if prior.rows.signum() != candidate.rows.signum() { transition += 2.5 }
                        else {
                            let ratio = Double(abs(candidate.rows)) / Double(max(1, abs(prior.rows)))
                            transition += min(1.5, abs(log(ratio)) * 0.55)
                        }
                    }
                    let directionPenalty = candidate.rows.signum() == dominantDirection ? 0.0 : 2.0
                    let total = costs[previousIndex] + transition + candidate.score + directionPenalty
                    if total < next[currentIndex] {
                        next[currentIndex] = total
                        pointers[currentIndex] = previousIndex
                    }
                }
            }
            costs = next
            backPointers.append(pointers)
        }
        guard var state = costs.indices.min(by: { costs[$0] < costs[$1] }) else { return result }
        for movementIndex in stride(from: movingEdges.count - 1, through: 0, by: -1) {
            let edgeIndex = movingEdges[movementIndex]
            result[edgeIndex] = edgeCandidates[edgeIndex][state]
            if movementIndex > 0 { state = backPointers[movementIndex - 1][state] }
        }
#if LONGSHOT_CAPTURE_CHECKS
        FrameStitcher.alignmentTrace?("horizontal path " + result.map { String($0?.rows ?? 999_999) }.joined(separator: ","))
#endif
        return result
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
        var dimRedRows = [Double](repeating: 0, count: height)
        var outsideRows = [Double](repeating: 0, count: height)
        for y in 0..<min(height, Int(Double(height) * 0.25)) {
            for x in 10..<86 {
                let (r, g, b) = rgb(x, y)
                if max(r, g, b) < 48 { darkRows[y] += 1 / 76.0 }
                if r > 80, g < 135, b < 120, Double(r) > Double(g) * 1.6, Double(r) > Double(b) * 1.5 {
                    redRows[y] += 1 / 76.0
                }
                if r > 26, r > g + 15, r > b + 12, g < 90, b < 90 {
                    dimRedRows[y] += 1 / 76.0
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

        // During dismissal the red action button shrinks to dim recording
        // indicators before the oversized black activity finishes collapsing.
        // Require a wide top pill, bright sides, a bounded extent beyond the
        // compact status bar and repeated red evidence. Ordinary dark content
        // or the normal compact recording indicator must remain usable.
        if coveredTopRatio == 0,
           let start = (0..<max(1, Int(Double(height) * 0.06))).first(where: {
               darkRows[$0] > 0.60 && outsideRows[$0] > 190
           }) {
            let limit = min(height - 1, Int(Double(height) * 0.11))
            var end = start
            while end + 1 < limit, darkRows[end + 1] > 0.32, outsideRows[end + 1] > 190 {
                end += 1
            }
            let redEvidenceRows = (start...end).filter { dimRedRows[$0] > 0.025 }.count
            if Double(end) / Double(height) > 0.07, end + 1 < limit, redEvidenceRows >= 2 {
                coveredTopRatio = CGFloat(end + 2) / CGFloat(height)
            }
        }

        // OCR is only run for a large neutral-gray card, never for every normal
        // frame. Confirm the sharing controls before discarding an entire frame.
        var neutral = 0, checked = 0
        for y in Int(Double(height) * 0.39)..<Int(Double(height) * 0.61) {
            for x in 24..<72 {
                let (r, g, b) = rgb(x, y)
                checked += 1
                if max(r, g, b) - min(r, g, b) < 16, r > 65, r < 205 {
                    neutral += 1
                }
            }
        }
        var isSystemPanel = false
        // Blurred screen-sharing sheets can have a substantial gray gradient
        // before our activity appears. Neutral coverage only gates OCR work;
        // the sharing-control text must still positively identify the panel.
        if checked > 0, Double(neutral) / Double(checked) > 0.72 {
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
                        .joined(separator: " ").lowercased()
                    let compact = text.replacingOccurrences(of: " ", with: "")
                    isSystemPanel = (text.contains("screen sharing") && text.contains("stop sharing"))
                        || text.contains("share entire screen")
                        || (compact.contains("屏幕共享") && compact.contains("停止共享"))
                        || compact.contains("共享整个屏幕")
                }
            }
        }
        return Detection(coveredTopRatio: coveredTopRatio, isSystemPanel: isSystemPanel)
    }
}
