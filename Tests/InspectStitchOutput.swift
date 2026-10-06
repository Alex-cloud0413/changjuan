import CoreGraphics
import Foundation
import ImageIO

/// Compare the old result after its status-bar crop against the new result.
/// JPEG re-encoding can change pixels slightly, but page content must line up.
@main
struct InspectStitchOutput {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Expected old and new JPEG paths") }
        let old = try load(CommandLine.arguments[1])
        let new = try load(CommandLine.arguments[2])
        let crop = old.height - new.height
        precondition(old.width == new.width && crop > 0)
        let cropped = old.cropping(to: CGRect(x: 0, y: crop, width: new.width, height: new.height))!
        let lhs = try pixels(cropped)
        let rhs = try pixels(new)
        var difference: UInt64 = 0
        var changed: UInt64 = 0
        for index in lhs.indices where index % 4 != 3 {
            let delta = abs(Int(lhs[index]) - Int(rhs[index]))
            difference += UInt64(delta)
            if delta > 12 { changed += 1 }
        }
        let channels = Double(new.width * new.height * 3)
        let mean = Double(difference) / channels
        let changedRatio = Double(changed) / channels
        print("Top crop pixels: \(crop); RGB mean absolute difference: \(mean); channels differing by >12: \(changedRatio)")
        precondition(mean < 3 && changedRatio < 0.03, "Content shifted or changed beyond JPEG rounding")
    }

    private static func load(_ path: String) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CheckError.decode }
        return image
    }

    private static func pixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard success else { throw CheckError.decode }
        return bytes
    }
}

private enum CheckError: Error { case decode }
