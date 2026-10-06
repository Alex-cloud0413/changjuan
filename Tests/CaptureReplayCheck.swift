import Foundation
import UIKit

/// Replays only the explicitly supplied local fixture, never installed app data.
@main
struct CaptureReplayCheck {
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else { fatalError("Pass fixture and isolated output directory") }
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(CaptureManifest.self, from: Data(contentsOf: fixture.appendingPathComponent("manifest.json")))
        var traces: [String] = []
        FrameStitcher.alignmentTrace = { traces.append($0); print($0) }
        let result = try FrameStitcher().stitch(
            frameURLs: CaptureStorage.frameURLs(in: fixture), sessionURL: output,
            topCropRatio: manifest.topCropRatio ?? 0.075, segmentStarts: manifest.segmentStarts ?? []
        )
        print("timings=\(result.timings)")
        for url in result.outputURLs {
            let image = UIImage(contentsOfFile: url.path)!.cgImage!
            print("output=\(url.path) size=\(image.width)x\(image.height)")
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--expect-edge"), flag + 3 < CommandLine.arguments.count {
            let from = CommandLine.arguments[flag + 1], to = CommandLine.arguments[flag + 2]
            let shift = CommandLine.arguments[flag + 3]
            guard traces.contains(where: { $0.hasPrefix("edge \(from)->\(to) ") && $0.contains(" refined=\(shift) ") }) else {
                fatalError("Expected pixel-verified edge was not recovered")
            }
            print("Verified expected edge \(from)->\(to): \(shift) source pixels")
        }
    }
}
