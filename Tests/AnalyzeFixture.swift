import CoreGraphics
import Foundation
import ImageIO

@main
struct AnalyzeFixture {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix("frame-") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let frames = try urls.map(loadGray)
        let preliminaryShifts = zip(frames, frames.dropFirst()).compactMap {
            OverlapEstimator.estimateDownwardShift(from: $0.0, to: $0.1)?.rows
        }.sorted()
        let preferredShift = preliminaryShifts.isEmpty
            ? nil
            : preliminaryShifts[preliminaryShifts.count / 2]
        print("preferred shift", String(describing: preferredShift))

        for index in 1..<frames.count {
            let forward = OverlapEstimator.estimateDownwardShift(
                from: frames[index - 1],
                to: frames[index],
                preferredShiftRows: preferredShift
            )
            let reverse = OverlapEstimator.estimateDownwardShift(
                from: frames[index],
                to: frames[index - 1]
            )
            let difference = OverlapEstimator.meanAbsoluteDifference(frames[index - 1], frames[index])
            let simple = bestSimpleShift(from: frames[index - 1], to: frames[index])
            let simpleReverse = bestSimpleShift(from: frames[index], to: frames[index - 1])
            print(index, "difference", difference, "forward", String(describing: forward), "reverse", String(describing: reverse), "simple", simple, "simpleReverse", simpleReverse)
        }
    }

    private static func loadGray(url: URL) throws -> GrayFrame {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AnalyzeError.couldNotLoad
        }

        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        let top = floor(sourceHeight * 0.075)
        let bottom = ceil(sourceHeight * 0.09)
        let contentHeight = sourceHeight - top - bottom
        let targetWidth = 72
        let targetHeight = max(96, Int(round((contentHeight / sourceWidth) * CGFloat(targetWidth))))
        let cropRect = CGRect(x: 0, y: top, width: sourceWidth, height: contentHeight)
        guard let cropped = image.cropping(to: cropRect) else {
            throw AnalyzeError.couldNotLoad
        }
        var bitmap = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        let rendered = bitmap.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else { return false }
            guard let context = CGContext(
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
        guard rendered else { throw AnalyzeError.couldNotLoad }
        let gray = bitmap
        if url.lastPathComponent == "frame-000000.jpg" {
            print("gray range", gray.min() ?? 0, gray.max() ?? 0)
        }
        return GrayFrame(width: targetWidth, height: targetHeight, pixels: gray)
    }

    private static func bestSimpleShift(from previous: GrayFrame, to current: GrayFrame) -> String {
        var bestShift = 0
        var bestScore = Double.infinity
        for shift in 1...100 {
            let overlap = previous.height - shift
            var difference = 0
            var count = 0
            for y in 0..<overlap {
                for x in 0..<previous.width {
                    difference += abs(Int(previous[x, y + shift]) - Int(current[x, y]))
                    count += 1
                }
            }
            let score = Double(difference) / Double(count)
            if score < bestScore {
                bestScore = score
                bestShift = shift
            }
        }
        return "\(bestShift):\(String(format: "%.2f", bestScore))"
    }
}

private enum AnalyzeError: Error {
    case couldNotLoad
}
