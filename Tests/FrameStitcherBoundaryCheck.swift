import Foundation
import UIKit

/// Run against JPEGs produced by GenerateFixture. This uses the production
/// decoder, scroll selection, assembly and JPEG renderer, not a gray-only mock.
@main
struct FrameStitcherBoundaryCheck {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            fatalError("Expected GenerateFixture output directory")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LongShotStitchBoundaryChecks-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let targetFrames: [URL]
        if CommandLine.arguments[1] == "--nonperiodic" {
            targetFrames = try makeNonperiodicFrames(in: directory)
        } else {
            let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            targetFrames = try CaptureStorage.frameURLs(in: source)
        }
        require(targetFrames.count >= 4)
        let unrelatedURL = directory.appendingPathComponent("unrelated.jpg")
        try makeUnrelatedFrame(size: imageSize(at: targetFrames[0])).write(to: unrelatedURL)

        try compareTargetWithWrapped(
            targetFrames, unrelatedURL: unrelatedURL, directory: directory, name: "full"
        )
        // Ten raw frames: three opening UI frames, four target frames and three
        // ending UI frames. The former fixed-tail trim kept only the first four,
        // leaving a single target frame and making this short capture fail.
        try compareTargetWithWrapped(
            Array(targetFrames.prefix(4)), unrelatedURL: unrelatedURL,
            directory: directory, name: "short"
        )
        let stationaryDirectory = directory.appendingPathComponent("stationary", isDirectory: true)
        try FileManager.default.createDirectory(at: stationaryDirectory, withIntermediateDirectories: true)
        do {
            _ = try FrameStitcher().stitch(
                frameURLs: [targetFrames[0], targetFrames[0], targetFrames[0]],
                sessionURL: stationaryDirectory
            )
            fatalError("A stationary capture must still be rejected by the stitcher")
        } catch StitchError.noUsableMovement {}
        try verifyPixelAccurateAlignment(in: directory)
        try verifyBidirectionalAndPageSegments(targetFrames, in: directory)
        try verifyOverlayDetection(in: directory)
        print("FrameStitcher boundary checks passed; reverse/revisit, segmented pages and overlay recovery included. Fixtures: \(directory.path)")
    }

    private static func compareTargetWithWrapped(
        _ targetFrames: [URL], unrelatedURL: URL, directory: URL, name: String
    ) throws {
        let baselineDirectory = directory.appendingPathComponent("\(name)-baseline", isDirectory: true)
        let wrappedDirectory = directory.appendingPathComponent("\(name)-wrapped", isDirectory: true)
        try FileManager.default.createDirectory(at: baselineDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wrappedDirectory, withIntermediateDirectories: true)
        let wrappedSources = [unrelatedURL, unrelatedURL, unrelatedURL]
            + targetFrames + [unrelatedURL, unrelatedURL, unrelatedURL]
        var wrappedFrames: [URL] = []
        for (index, source) in wrappedSources.enumerated() {
            let destination = CaptureStorage.frameURL(index: index, sessionURL: wrappedDirectory)
            try FileManager.default.copyItem(at: source, to: destination)
            wrappedFrames.append(destination)
        }

        let baseline = try FrameStitcher().stitch(
            frameURLs: targetFrames, sessionURL: baselineDirectory
        )
        let wrapped = try FrameStitcher().stitch(
            frameURLs: wrappedFrames, sessionURL: wrappedDirectory
        )
        emit("\(name): baseline accepted=\(baseline.acceptedFrameCount), skipped=\(baseline.skippedFrameCount); wrapped accepted=\(wrapped.acceptedFrameCount), skipped=\(wrapped.skippedFrameCount)")
        try dumpSelection(wrappedFrames)
        require(wrapped.acceptedFrameCount == baseline.acceptedFrameCount)
        require(wrapped.skippedFrameCount == baseline.skippedFrameCount + 6)
        require(wrapped.outputURLs.count == baseline.outputURLs.count)
        for (expected, actual) in zip(baseline.outputURLs, wrapped.outputURLs) {
            require(try Data(contentsOf: expected) == Data(contentsOf: actual))
        }
        require(try CaptureStorage.frameURLs(in: wrappedDirectory).count == wrappedSources.count)
        let sizes = try wrapped.outputURLs.map { try imageSize(at: $0) }
        print("\(name): raw=\(wrappedSources.count), accepted=\(wrapped.acceptedFrameCount), skipped=\(wrapped.skippedFrameCount), output=\(sizes), identicalToTargetOnly=true")
    }

    private static func verifyBidirectionalAndPageSegments(_ frames: [URL], in directory: URL) throws {
        func stitch(_ sources: [URL], name: String, boundaries: [Int] = []) throws -> StitchResult {
            let session = directory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
            return try FrameStitcher().stitch(frameURLs: sources, sessionURL: session, segmentStarts: boundaries)
        }
        let baseline = try stitch(frames, name: "forward")
        let reverse = try stitch(Array(frames.reversed()), name: "reverse")
        let revisit = try stitch(frames + Array(frames.reversed()) + frames, name: "revisit")
        require(try Data(contentsOf: baseline.outputURLs[0]) == Data(contentsOf: reverse.outputURLs[0]))
        require(try Data(contentsOf: baseline.outputURLs[0]) == Data(contentsOf: revisit.outputURLs[0]))
        // One static second page still belongs in a manually segmented result.
        let multi = try stitch(frames + [frames[0]], name: "multi-page", boundaries: [0, frames.count])
        let baselineHeight = try imageSize(at: baseline.outputURLs[0]).height
        let secondPageHeight = try imageSize(at: frames[0]).height * 0.925
        let expected = baselineHeight + secondPageHeight + 8
        require(try imageSize(at: multi.outputURLs[0]).height == expected)
        let scrollingPages = try stitch(
            frames + Array(frames.reversed()), name: "two-scrolling-pages", boundaries: [0, frames.count]
        )
        require(try imageSize(at: scrollingPages.outputURLs[0]).height == baselineHeight * 2 + 8)
        let unrelated = directory.appendingPathComponent("unrelated.jpg")
        do {
            _ = try stitch(frames + [frames[0], unrelated], name: "invalid-second-page", boundaries: [0, frames.count])
            fatalError("An invalid explicit page must not be silently dropped")
        } catch StitchError.unusablePage(let number) {
            require(number == 2)
        }

        // The first obstructed frame must not become a permanent header when a
        // later unobstructed viewport contains the same starting content.
        let source = UIImage(contentsOfFile: frames[0].path)!
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let obstructed = UIGraphicsImageRenderer(size: source.size, format: format).image { _ in
            source.draw(at: .zero)
            UIColor.black.setFill()
            UIBezierPath(roundedRect: CGRect(x: 14, y: 12, width: source.size.width - 28, height: 114), cornerRadius: 45).fill()
            UIColor(red: 0.60, green: 0.24, blue: 0.18, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 28, y: 59, width: source.size.width - 56, height: 43), cornerRadius: 20).fill()
        }
        let obstructedURL = directory.appendingPathComponent("obstructed-start.png")
        try obstructed.pngData()!.write(to: obstructedURL)
        let recovered = try stitch([obstructedURL] + frames, name: "overlay-recovery")
        require(try Data(contentsOf: recovered.outputURLs[0]) == Data(contentsOf: baseline.outputURLs[0]))
        print("reverse/revisit: byte-identical to forward; segmented static page height=\(expected)")
        print("two scrolling pages ordered correctly; invalid page rejected; obstructed startup replaced by clean content")
    }

    private static func verifyOverlayDetection(in directory: URL) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844), format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
            UIColor.black.setFill()
            UIBezierPath(roundedRect: CGRect(x: 14, y: 12, width: 362, height: 114), cornerRadius: 45).fill()
            UIColor(red: 0.60, green: 0.24, blue: 0.18, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 28, y: 59, width: 332, height: 43), cornerRadius: 20).fill()
        }
        let detection = CaptureOverlayDetector.inspect(image.cgImage!)
        require(detection.coveredTopRatio > 0.12 && detection.coveredTopRatio < 0.18)
        require(!detection.isSystemPanel)
        let dark = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
            UIColor(red: 0.6, green: 0.24, blue: 0.18, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 55, width: 390, height: 44))
        }
        require(CaptureOverlayDetector.inspect(dark.cgImage!).coveredTopRatio == 0)
        try image.pngData()!.write(to: directory.appendingPathComponent("synthetic-island.png"))
        if CommandLine.arguments.count >= 3 {
            let actual = UIImage(contentsOfFile: CommandLine.arguments[2])!
            let result = CaptureOverlayDetector.inspect(actual.cgImage!)
            require(result.coveredTopRatio > 0.10)
            require(result.isSystemPanel)
            print("user sharing-panel screenshot: island mask and sharing sheet both detected")
        }
    }

    private static func imageSize(at url: URL) throws -> CGSize {
        guard let image = UIImage(contentsOfFile: url.path)?.cgImage else {
            throw CheckError.image
        }
        return CGSize(width: image.width, height: image.height)
    }

    private static func dumpSelection(_ urls: [URL]) throws {
        let frames = try urls.map { url -> GrayFrame in
            guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { throw CheckError.image }
            let top = floor(CGFloat(image.height) * 0.075)
            let bottom = ceil(CGFloat(image.height) * 0.19)
            let contentHeight = CGFloat(image.height) - top - bottom
            guard let cropped = image.cropping(to: CGRect(x: 0, y: top, width: CGFloat(image.width), height: contentHeight)) else {
                throw CheckError.image
            }
            let height = max(96, Int(round(contentHeight / CGFloat(image.width) * 72)))
            var pixels = [UInt8](repeating: 0, count: 72 * height)
            let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: 72, height: height, bitsPerComponent: 8, bytesPerRow: 72, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                context.interpolationQuality = .medium
                context.draw(cropped, in: CGRect(x: 0, y: 0, width: 72, height: height))
                return true
            }
            guard rendered else { throw CheckError.image }
            return GrayFrame(width: 72, height: height, pixels: pixels)
        }
        guard let analysis = ScrollSequenceSelector.analyze(frames: frames) else {
            emit("selection=nil")
            return
        }
        emit("selection=\(analysis.selection)")
        for index in 1..<frames.count {
            if let estimate = analysis.comparisons[index]?.estimate(preferredShiftRows: analysis.selection.preferredShiftRows) {
                emit("edge[\(index - 1)->\(index)]: \(estimate)")
            }
        }
    }

    private static func emit(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private static func makeUnrelatedFrame(size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.95, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let title = "LongShot Capture"
            title.draw(at: CGPoint(x: 50, y: 100), withAttributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.black
            ])
            UIColor.black.setFill()
            context.fill(CGRect(x: 160, y: 235, width: 70, height: 6))
            context.fill(CGRect(x: 160, y: 252, width: 40, height: 6))
            context.fill(CGRect(x: 160, y: 269, width: 70, height: 6))
            UIColor.white.setFill()
            context.fill(CGRect(x: 30, y: 365, width: size.width - 60, height: 240))
            let instruction = "Start capture\nSwitch to another app\nScroll and finish"
            instruction.draw(in: CGRect(x: 50, y: 400, width: size.width - 100, height: 170), withAttributes: [
                .font: UIFont.systemFont(ofSize: 19),
                .foregroundColor: UIColor.darkGray
            ])
        }
        guard let data = image.jpegData(compressionQuality: 0.94) else { throw CheckError.image }
        return data
    }

    private static func makeNonperiodicFrames(in directory: URL) throws -> [URL] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var randomState: UInt64 = 0x58374a0f
        let page = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 2400), format: format).image { context in
            for y in stride(from: 0, to: 2400, by: 10) {
                for x in stride(from: 0, to: 360, by: 10) {
                    randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
                    let shade = CGFloat(35 + Int((randomState >> 32) % 190)) / 255
                    UIColor(white: shade, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 10, height: 10))
                }
            }
        }
        var result: [URL] = []
        for index in 0..<10 {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 800), format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 360, height: 800))
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: 60, width: 360, height: 588))
                page.draw(at: CGPoint(x: 0, y: 60 - index * 100))
                context.cgContext.restoreGState()
            }
            guard let data = image.jpegData(compressionQuality: 0.94) else { throw CheckError.image }
            let url = directory.appendingPathComponent("target-\(index).jpg")
            try data.write(to: url)
            result.append(url)
        }
        return result
    }

    private static func verifyPixelAccurateAlignment(in directory: URL) throws {
        let framesDirectory = directory.appendingPathComponent("precision-frames", isDirectory: true)
        let outputDirectory = directory.appendingPathComponent("precision-output", isDirectory: true)
        try FileManager.default.createDirectory(at: framesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var randomState: UInt64 = 0x10c45ea7
        let page = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 1_600), format: format).image { context in
            for y in stride(from: 0, to: 1_600, by: 6) {
                for x in stride(from: 0, to: 360, by: 6) {
                    randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
                    let shade = CGFloat(30 + Int((randomState >> 32) % 200)) / 255
                    UIColor(white: shade, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 6, height: 6))
                }
            }
        }

        var frameURLs: [URL] = []
        for (index, offset) in [0, 217, 434, 651].enumerated() {
            let frame = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 800), format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 360, height: 800))
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: 60, width: 360, height: 676))
                page.draw(at: CGPoint(x: 0, y: 60 - offset))
                context.cgContext.restoreGState()
                UIColor(white: 0.94, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 360, height: 60))
                context.fill(CGRect(x: 0, y: 736, width: 360, height: 64))
            }
            guard let data = frame.jpegData(compressionQuality: 0.94) else { throw CheckError.image }
            let url = framesDirectory.appendingPathComponent("precision-\(index).jpg")
            try data.write(to: url)
            frameURLs.append(url)
        }

        let result = try FrameStitcher().stitch(
            frameURLs: frameURLs,
            sessionURL: outputDirectory
        )
        require(result.acceptedFrameCount == 4)
        require(result.outputURLs.count == 1)
        // 588 initial content rows + three exact 217-row movements + the
        // final 152-row fixed/footer region. The old thumbnail-only mapping
        // rounded each movement to 219 rows and produced visible duplicate
        // rows when a seam crossed text.
        require(try imageSize(at: result.outputURLs[0]).height == 1_391)
        print(String(format: "precision: accepted=%d, height=1391, processing=%.4fs",
                     result.acceptedFrameCount, result.timings.total))
    }

    private static func require(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
        guard condition else { fatalError("Check failed", file: file, line: line) }
    }
}

private enum CheckError: Error { case image }
