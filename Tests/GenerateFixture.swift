import CoreGraphics
import Foundation
import ImageIO

@main
struct GenerateFixture {
    private static let frameWidth = 390
    private static let frameHeight = 844
    private static let headerHeight: CGFloat = 64
    private static let footerHeight: CGFloat = 64

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw FixtureError.missingOutputDirectory
        }

        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let offsets = stride(from: 0, through: 1_980, by: 220)
        var frameCount = 0
        for (index, offset) in offsets.enumerated() {
            let url = outputDirectory.appendingPathComponent(
                String(format: "frame-%06d.jpg", index)
            )
            try writeFrame(offset: CGFloat(offset), to: url)
            frameCount += 1
        }

        let manifest: [String: Any] = [
            "id": outputDirectory.lastPathComponent,
            "startedAt": ISO8601DateFormatter().string(from: Date()),
            "completedAt": ISO8601DateFormatter().string(from: Date()),
            "frameCount": frameCount,
            "state": "complete",
            "autoStopped": true
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(to: outputDirectory.appendingPathComponent("manifest.json"))
        print("Generated \(frameCount) fixture frames in \(outputDirectory.path)")
    }

    private static func writeFrame(offset: CGFloat, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: frameWidth,
            height: frameHeight,
            bitsPerComponent: 8,
            bytesPerRow: frameWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw FixtureError.contextCreationFailed }

        context.translateBy(x: 0, y: CGFloat(frameHeight))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight))

        let contentHeight = CGFloat(frameHeight) - headerHeight - footerHeight
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: headerHeight, width: CGFloat(frameWidth), height: contentHeight))
        context.translateBy(x: 0, y: headerHeight - offset)
        drawPage(in: context)
        context.restoreGState()

        drawFixedBars(in: context)

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.jpeg" as CFString,
                1,
                nil
              ) else { throw FixtureError.encodingFailed }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.94,
            kCGImagePropertyOrientation: 1
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.encodingFailed
        }
    }

    private static func drawPage(in context: CGContext) {
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: frameWidth, height: 2_900))

        for section in 0..<15 {
            let y = CGFloat(section * 190) + 18
            let hue = CGFloat(section) / 17
            let color = colorForHue(hue)
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: 22, y: y + 18, width: 38, height: 38))
            context.fill(CGRect(x: 76, y: y + 18, width: 255, height: 18))

            context.setFillColor(CGColor(red: 0.22, green: 0.25, blue: 0.3, alpha: 1))
            for marker in 0...section {
                let column = marker % 10
                let row = marker / 10
                context.fill(CGRect(
                    x: 27 + CGFloat(column * 3),
                    y: y + 25 + CGFloat(row * 5),
                    width: 2,
                    height: 2
                ))
            }

            for line in 0..<5 {
                let length = 195 + ((section * 29 + line * 41) % 125)
                let shade = CGFloat(110 + ((section * 13 + line * 17) % 70)) / 255
                context.setFillColor(CGColor(red: shade, green: shade, blue: shade, alpha: 1))
                context.fill(CGRect(
                    x: 76,
                    y: y + 55 + CGFloat(line * 21),
                    width: CGFloat(length),
                    height: line == 0 ? 8 : 5
                ))
            }

            context.setStrokeColor(CGColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1))
            context.setLineWidth(1)
            context.move(to: CGPoint(x: 22, y: y + 158))
            context.addLine(to: CGPoint(x: 368, y: y + 158))
            context.strokePath()
        }
    }

    private static func drawFixedBars(in context: CGContext) {
        context.setFillColor(CGColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: frameWidth, height: Int(headerHeight)))
        context.fill(CGRect(
            x: 0,
            y: frameHeight - Int(footerHeight),
            width: frameWidth,
            height: Int(footerHeight)
        ))

        context.setFillColor(CGColor(red: 0.15, green: 0.18, blue: 0.24, alpha: 1))
        context.fill(CGRect(x: 137, y: 25, width: 116, height: 10))

        context.setFillColor(CGColor(red: 0.28, green: 0.5, blue: 0.95, alpha: 1))
        for x in [70, 185, 300] {
            context.fillEllipse(in: CGRect(x: x, y: frameHeight - 41, width: 18, height: 18))
        }
    }

    private static func colorForHue(_ hue: CGFloat) -> CGColor {
        let angle = hue * .pi * 2
        let red = 0.78 + 0.12 * sin(angle)
        let green = 0.84 + 0.1 * sin(angle + 2.1)
        let blue = 0.93 + 0.06 * sin(angle + 4.2)
        return CGColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

private enum FixtureError: LocalizedError {
    case missingOutputDirectory
    case contextCreationFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingOutputDirectory:
            return "Expected one output directory argument"
        case .contextCreationFailed:
            return "Could not create a bitmap context"
        case .encodingFailed:
            return "Could not encode fixture image"
        }
    }
}

