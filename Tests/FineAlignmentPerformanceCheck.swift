import Foundation

/// Models a long iPhone capture after the JPEGs have been reduced horizontally
/// for seam refinement: 43 accepted transitions, 72 samples across, and about
/// 1,900 rows of retained vertical detail.
@main
struct FineAlignmentPerformanceCheck {
    static func main() {
        let width = 72
        let frameHeight = 1_927
        let shift = 137
        let transitionCount = 43
        let pageHeight = frameHeight + shift * transitionCount + 32
        var page = [UInt8](repeating: 0, count: width * pageHeight)

        var state: UInt64 = 0x71a9c5d3
        for y in 0..<pageHeight {
            for x in 0..<width {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let texture = Int((state >> 33) % 190)
                let textLine = y % 37 < 4 && x % 11 > 1 ? 24 : texture + 40
                page[y * width + x] = UInt8(min(255, textLine))
            }
        }

        let frames = (0...transitionCount).map { index -> GrayFrame in
            let start = index * shift * width
            let end = start + frameHeight * width
            return GrayFrame(width: width, height: frameHeight, pixels: Array(page[start..<end]))
        }

        let started = ProcessInfo.processInfo.systemUptime
        for index in 1..<frames.count {
            let estimate = OverlapEstimator.refineDownwardShift(
                from: frames[index - 1],
                to: frames[index],
                around: shift + 7,
                searchRadius: 20
            )
            require(estimate?.rows == shift)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        print(String(format: "Fine alignment: %d transitions in %.4fs", transitionCount, elapsed))
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else { fatalError("Check failed", file: file, line: line) }
    }
}
