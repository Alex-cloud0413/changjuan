import Foundation
import UIKit

/// Sparse repeating spreadsheet cells must use the moving column headings,
/// not guess a multiple of the repeated column width. All content is synthetic.
@main
struct HorizontalSpreadsheetCheck {
    static let files = FileManager.default
    static var checks = 0
    static func require(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError(message) }
    }

    @MainActor static func main() throws {
        let root = files.temporaryDirectory.appendingPathComponent("LongShotSparseSheet-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.environment["LONGSHOT_ALIGNMENT_TRACE"] == "1" {
            FrameStitcher.alignmentTrace = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let screenWidth = 390, screenHeight = 844, tableTop = 142, tableBottom = 690
        let offsets = [0, 17, 49, 88, 137, 194, 251, 318, 386, 459, 538, 610, 688, 760, 818, 880]
        let outputWidth = offsets.last! + screenWidth
        func text(_ value: String, _ x: Int, _ y: Int, _ size: CGFloat = 11, gray: CGFloat = 0.12) {
            value.draw(at: CGPoint(x: x, y: y), withAttributes: [
                .font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor(white: gray, alpha: 1)])
        }
        let world = UIGraphicsImageRenderer(size: CGSize(width: outputWidth, height: screenHeight), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: outputWidth, height: screenHeight))
            for col in 0..<18 {
                let x = 32 + col * 78
                UIColor(white: 0.82, alpha: 1).setFill(); ctx.fill(CGRect(x: x, y: tableTop, width: 1, height: tableBottom - tableTop))
                // A sparse but decisive identity outside the old 20%-80% crop.
                text(String(UnicodeScalar(65 + col)!), x + 32, tableTop + 2, 12)
                UIColor.orange.setFill(); ctx.fill(CGRect(x: x, y: 160, width: 78, height: 22))
                text(col % 3 == 0 ? "待领取" : col % 3 == 1 ? "名单" : "", x + 6, 164)
                for row in 0..<24 {
                    let y = 184 + row * 21
                    UIColor(white: 0.89, alpha: 1).setFill(); ctx.fill(CGRect(x: x, y: y, width: 78, height: 1))
                    if col % 3 == 0 { text("待领取", x + 6, y + 3) }
                    if col % 3 == 1 { text(["seventeen", "enhypen", "straykids", "riize", "nct", "txt"][row % 6], x + 6, y + 3, 10) }
                }
            }
        }
        try world.pngData()!.write(to: root.appendingPathComponent("world.png"))
        var frames: [URL] = []
        for (index, offset) in offsets.enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: screenWidth, height: screenHeight), format: format).image { ctx in
                world.draw(at: CGPoint(x: -offset, y: 0))
                UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: screenWidth, height: tableTop))
                ctx.fill(CGRect(x: 0, y: tableBottom, width: screenWidth, height: screenHeight - tableBottom))
                text("21:20                 69%", 24, 22, 17)
                text("‹   ☷                    ⌕   ♧   ···", 18, 77, 22)
                text("Sheet1", 15, 117, 14)
                // A changing badge must not defeat recognition of a fixed bar.
                text("\(index % 3)", 330, 84, 9, gray: 0.6)
                UIColor(white: 0.97, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: tableTop, width: 31, height: tableBottom - tableTop))
                for row in 0..<24 { text("\(row + 1)", 6, 187 + row * 21, 9, gray: 0.5) }
                UIColor.white.setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 245, y: 638, width: 38, height: 38))
                UIColor(white: 0.86, alpha: 1).setStroke(); ctx.cgContext.strokeEllipse(in: CGRect(x: 245, y: 638, width: 38, height: 38))
                UIColor.systemBlue.setStroke(); ctx.cgContext.setLineWidth(2)
                ctx.cgContext.stroke(CGRect(x: 258, y: 648, width: 10, height: 18))
                ctx.cgContext.stroke(CGRect(x: 254, y: 650, width: 10, height: 14))
                UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 286, y: 638, width: 101, height: 38))
                text("工具箱", 304, 649, 14, gray: 1)
                text("A1                          ×", 30, 716, 15, gray: 0.5)
                text("问问豆包", 30, 777, 18, gray: 0.5)
                // Faint viewport-fixed watermarks, like the reported app.
                for y in stride(from: 56, to: screenHeight, by: 118) {
                    text("示例账号 3623", 18 + (y % 3), y, 10, gray: 0.965 + CGFloat(index % 2) * 0.004)
                    text("示例账号 3623", 236, y + 38, 10, gray: 0.965)
                }
            }
            let url = root.appendingPathComponent("frame-\(index).jpg")
            try image.jpegData(compressionQuality: 0.9)!.write(to: url)
            frames.append(url)
        }
        func stitch(_ inputs: [URL], _ name: String, cached: Bool = false) throws -> StitchResult {
            do {
                return try FrameStitcher(usePreparedFrames: cached, options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
                    .stitch(frameURLs: inputs, sessionURL: root.appendingPathComponent(name))
            } catch {
                FileHandle.standardError.write(Data(("Horizontal spreadsheet fixture \(name) failed after \(checks) assertions; \(root.path)\n").utf8))
                throw error
            }
        }
        do {
        let result = try stitch(frames, "rightward")
        let image = UIImage(contentsOfFile: result.outputURLs[0].path)!
        require(Int(image.size.width) == outputWidth, "Sparse sheet lost/repeated columns: expected \(outputWidth), got \(image.size.width); fixtures \(root.path)")
        require(Int(image.size.height) == screenHeight, "Original pixel height retained")
        let error = meanError(image, world, rect: CGRect(x: 34, y: tableTop, width: outputWidth - 34, height: 490))
        require(error < 3, "Moving cells and column headings must align; error=\(error); fixtures \(root.path)")
        require(meanError(image, world, rect: CGRect(x: 34, y: 638, width: outputWidth - 34 - 160, height: 38)) < 3,
                "Recover cells covered by the fixed toolbox and adjacent white control from actual overlapping frames")
        // Header and footer are viewport UI, present once, never letter salad.
        let empty = UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: image.size))
        }
        require(meanError(image, empty, rect: CGRect(x: 400, y: 66, width: outputWidth - 400, height: 70)) < 2,
                "Fixed toolbar must not be repeated across the wide output")
        require(meanError(image, empty, rect: CGRect(x: 400, y: 705, width: outputWidth - 400, height: 120)) < 2,
                "Fixed bottom panel must not be repeated")
        let reverse = try stitch(Array(frames.reversed()), "leftward")
        let revisit = try stitch(frames + Array(frames.reversed()) + frames, "revisit")
        for output in [reverse, revisit] {
            let other = UIImage(contentsOfFile: output.outputURLs[0].path)!
            require(Int(other.size.width) == outputWidth, "Reversal must not duplicate a repeated column")
            require(meanError(other, world, rect: CGRect(x: 34, y: tableTop, width: outputWidth - 34, height: 490)) < 3,
                    "Reversal must preserve actual cell order")
        }
        let backtrack = try stitch([0, 1, 2, 3, 4, 5, 6, 5, 4, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15].map { frames[$0] }, "backtrack")
        let backtrackImage = UIImage(contentsOfFile: backtrack.outputURLs[0].path)!
        require(Int(backtrackImage.size.width) == outputWidth, "Short reversals must not append duplicate columns")
        require(meanError(backtrackImage, world, rect: CGRect(x: 34, y: tableTop, width: outputWidth - 34, height: 490)) < 3,
                "Backtracking must preserve screen order and recover the whole sheet")
        for url in frames {
            let data = try Data(contentsOf: url)
            try FramePreparationCache.store(FrameStitcher(options: CaptureOptions(axis: .horizontal)).prepareFrame(at: url, encodedData: data), for: url)
        }
        let prepared = try stitch(frames, "prepared", cached: true)
        require(try Data(contentsOf: prepared.outputURLs[0]) == Data(contentsOf: result.outputURLs[0]), "Prepared/fallback exact output parity")
        let faster = try stitch([0, 3, 6, 8, 10, 12, 15].map { frames[$0] }, "faster")
        let fasterImage = UIImage(contentsOfFile: faster.outputURLs[0].path)!
        require(Int(fasterImage.size.width) == outputWidth, "Larger motion must not pick the nearest repeated column")
        require(meanError(fasterImage, world, rect: CGRect(x: 34, y: tableTop, width: outputWidth - 34, height: 490)) < 3,
                "Larger shifts keep headings and cells in order")
        var full: [URL] = []
        for (index, url) in frames.enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1170, height: 2532), format: format).image { _ in
                UIImage(contentsOfFile: url.path)!.draw(in: CGRect(x: 0, y: 0, width: 1170, height: 2532))
            }
            let destination = root.appendingPathComponent("native-\(index).jpg")
            let data = image.jpegData(compressionQuality: 0.9)!
            try data.write(to: destination)
            try FramePreparationCache.store(FrameStitcher(options: CaptureOptions(axis: .horizontal)).prepareFrame(at: destination, encodedData: data), for: destination)
            full.append(destination)
        }
        let native = try stitch(full, "native", cached: true)
        let nativeImage = UIImage(contentsOfFile: native.outputURLs[0].path)!
        require(Int(nativeImage.size.width) == outputWidth * 3,
                "Full-resolution sparse sheet retains every column at native pixel positions")
        require(Int(nativeImage.size.height) == 2532,
                "A fixed native table must never be trimmed by falsely inferred cross-axis jitter")
        require(native.preparedFrameCount == full.count, "Native search uses capture-time prepared views")
        do {
            _ = try stitch(frames + [full[0]], "size-change")
            fatalError("A changed screen orientation must fail")
        } catch StitchError.inconsistentFrameSize { checks += 1 }
        let unrelated = UIGraphicsImageRenderer(size: CGSize(width: screenWidth, height: screenHeight), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight))
        }
        let ending = root.appendingPathComponent("unrelated.jpg")
        try unrelated.jpegData(compressionQuality: 0.9)!.write(to: ending)
        do {
            _ = try stitch(frames + [ending], "unmatched-ending")
            fatalError("An unmatched ending must not silently disappear")
        } catch StitchError.unseenGap { checks += 1 }
        print(String(format: "Sparse spreadsheet passed: %d checks; MAE %.4f; 16 native prepared frames %.3fs; fixtures %@",
                     checks, error, native.timings.total, root.path))
        }
    }

    static func meanError(_ lhs: UIImage, _ rhs: UIImage, rect: CGRect) -> Double {
        func pixels(_ image: UIImage) -> [UInt8] {
            let w = image.cgImage!.width, h = image.cgImage!.height
            var result = [UInt8](repeating: 0, count: w * h)
            result.withUnsafeMutableBytes { m in
                let ctx = CGContext(data: m.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
                ctx.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            return result
        }
        let a = pixels(lhs), b = pixels(rhs), aw = lhs.cgImage!.width, bw = rhs.cgImage!.width
        var difference = 0, count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) {
            difference += abs(Int(a[y * aw + x]) - Int(b[y * bw + x])); count += 1
        } }
        return Double(difference) / Double(count)
    }
}
