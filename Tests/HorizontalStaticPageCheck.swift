import Foundation
import UIKit

/// Explicit page boundaries permit a stationary screenshot, without allowing a
/// lone static recording or silently dropping an unmatched final viewport.
@main
struct HorizontalStaticPageCheck {
    static var checks = 0
    static func require(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }

    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LongShotStaticPages-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let width = 390, height = 844, shift = 120
        let world = UIGraphicsImageRenderer(size: CGSize(width: width + shift, height: height), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width + shift, height: height))
            for row in 0..<25 {
                for column in 0..<18 {
                    let value = (row * 41 + column * 67 + row * column * 13) % 193
                    UIColor(white: CGFloat(value) / 255, alpha: 1).setFill()
                    context.fill(CGRect(x: column * 31 + 3, y: row * 29 + 106,
                                        width: 7 + (column * 7 + row * 11) % 19, height: 7 + (column * 3 + row * 13) % 17))
                }
            }
        }
        func save(_ name: String, offset: Int = 0, color: UIColor? = nil) throws -> URL {
            let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
                if let color {
                    color.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                } else { world.draw(at: CGPoint(x: -offset, y: 0)) }
            }
            let url = root.appendingPathComponent(name + ".jpg")
            try image.jpegData(compressionQuality: 0.9)!.write(to: url)
            return url
        }
        let first = try save("first"), moved = try save("moved", offset: shift)
        let other = try save("other", color: UIColor(red: 0.13, green: 0.43, blue: 0.71, alpha: 1))
        func stitch(_ inputs: [URL], _ name: String, starts: [Int] = []) throws -> StitchResult {
            try FrameStitcher(usePreparedFrames: false, options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
                .stitch(frameURLs: inputs, sessionURL: root.appendingPathComponent(name), segmentStarts: starts)
        }
        let separator = max(8, Int(floor(Double(height) * 0.018)))
        let stationary = try stitch([first, first, other, other], "stationary", starts: [2])
        let stationaryImage = UIImage(contentsOfFile: stationary.outputURLs[0].path)!
        require(Int(stationaryImage.size.width) == width * 2 + separator, "Two static explicit pages must both remain complete")
        require(Int(stationaryImage.size.height) == height, "Stationary pages preserve original pixel height")
        let singleFrames = try stitch([first, other], "single-frame-pages", starts: [1])
        require(Int(UIImage(contentsOfFile: singleFrames.outputURLs[0].path)!.size.width) == width * 2 + separator,
                "One captured viewport per explicit page is valid")
        let mixed = try stitch([first, moved, other, other], "mixed", starts: [2])
        require(Int(UIImage(contentsOfFile: mixed.outputURLs[0].path)!.size.width) == width * 2 + shift + separator,
                "A scrolling page followed by a static page preserves both extents")
        let openingImage = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIImage(contentsOfFile: first.path)!.draw(at: .zero)
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 120, y: 16, width: 25, height: 12))
        }
        let opening = root.appendingPathComponent("opening-animation.jpg")
        try openingImage.jpegData(compressionQuality: 0.9)!.write(to: opening)
        let stable = try stitch([opening, first, moved], "stable-opening")
        let stableImage = UIImage(contentsOfFile: stable.outputURLs[0].path)!
        require(Int(stableImage.size.width) == width + shift, "Stationary opening must preserve every captured column")
        let pixel = stableImage.cgImage!.cropping(to: CGRect(x: 128, y: 20, width: 1, height: 1))!
        var rgb = [UInt8](repeating: 0, count: 4)
        rgb.withUnsafeMutableBytes { memory in
            let context = CGContext(data: memory.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        require(rgb[0] > 240 && rgb[1] > 240 && rgb[2] > 240,
                "Same-position stable opening replaces older transient chrome, including the preserved status bar")
        do {
            _ = try stitch([first, first], "lone-stationary")
            preconditionFailure("A single stationary recording must not produce a misleading long screenshot")
        } catch StitchError.noUsableMovement { checks += 1 }
        do {
            _ = try stitch([first, moved, other], "unmatched-ending")
            preconditionFailure("An unrelated ending must not be silently discarded")
        } catch StitchError.unseenGap { checks += 1 }
        print("Horizontal explicit static pages passed: \(checks) checks")
    }
}
