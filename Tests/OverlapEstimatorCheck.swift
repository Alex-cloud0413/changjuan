import Foundation

@main
struct OverlapEstimatorCheck {
    static func main() {
        testKnownScrollDistances()
        testStationaryFrameIsIgnored()
        testLargeScroll()
        testDynamicCommercePage()
        testScrollingPageWithFixedBottomOverlay()
        testStationaryPageWithChangingBannerIsIgnored()
        testFineAlignmentRecoversExactPixelShift()
        testFineAlignmentIgnoresFixedOverlay()
        testRecordingPreludeIsExcluded()
        testBidirectionalMovement()
        testReverseFineAlignment()
        print("OverlapEstimator checks passed")
    }

    private static func testBidirectionalMovement() {
        let page = makePage(width: 48, height: 500)
        let offsets = [140, 113, 86, 59, 86, 113, 140, 167]
        let frames = offsets.map { window(page: page, width: 48, offset: $0, height: 120) }
        require(OverlapEstimator.estimateVerticalShift(from: frames[0], to: frames[1])?.rows == -27)
        require(OverlapEstimator.estimateVerticalShift(from: frames[3], to: frames[4])?.rows == 27)
        let analysis = BidirectionalScrollSelector.analyze(frames: frames)
        require(analysis?.selection.startIndex == 0)
        require(analysis?.selection.endIndex == 7)
        require(analysis?.selection.preferredShiftRows == 27)
        require(OverlapEstimator.estimateVerticalShift(from: frames[0], to: frames[0]) == nil)
    }

    private static func testReverseFineAlignment() {
        let page = makePage(width: 48, height: 1_100)
        let first = window(page: page, width: 48, offset: 156, height: 640)
        let second = window(page: page, width: 48, offset: 19, height: 640)
        require(OverlapEstimator.refineVerticalShift(from: first, to: second, around: -143, searchRadius: 12)?.rows == -137)
    }

    private static func testKnownScrollDistances() {
        let page = makePage(width: 32, height: 260)
        let first = window(page: page, width: 32, offset: 0, height: 100)
        let second = window(page: page, width: 32, offset: 23, height: 100)
        let third = window(page: page, width: 32, offset: 57, height: 100)

        require(OverlapEstimator.estimateDownwardShift(from: first, to: second)?.rows == 23)
        require(OverlapEstimator.estimateDownwardShift(from: second, to: third)?.rows == 34)
    }

    private static func testStationaryFrameIsIgnored() {
        let page = makePage(width: 32, height: 160)
        let frame = window(page: page, width: 32, offset: 12, height: 100)
        require(OverlapEstimator.estimateDownwardShift(from: frame, to: frame) == nil)
    }

    private static func testLargeScroll() {
        let page = makePage(width: 32, height: 260)
        let first = window(page: page, width: 32, offset: 0, height: 100)
        let second = window(page: page, width: 32, offset: 70, height: 100)
        require(OverlapEstimator.estimateDownwardShift(from: first, to: second)?.rows == 70)
    }

    private static func testDynamicCommercePage() {
        let width = 48
        let height = 120
        let page = makePage(width: width, height: 320)
        let first = window(page: page, width: width, offset: 14, height: height)
        var second = window(page: page, width: width, offset: 41, height: height)

        // A viewport-fixed video/banner changes while the product list scrolls behind it.
        overwrite(
            frame: &second,
            xRange: 0..<width,
            yRange: 12..<66,
            seed: 91
        )
        // A live price rail changes independently down one side of the screen.
        overwrite(
            frame: &second,
            xRange: 37..<width,
            yRange: 66..<112,
            seed: 173
        )

        let estimate = OverlapEstimator.estimateDownwardShift(from: first, to: second)
        require(estimate?.rows == 27)
    }

    private static func testStationaryPageWithChangingBannerIsIgnored() {
        let width = 48
        let height = 120
        let page = makePage(width: width, height: 180)
        let first = window(page: page, width: width, offset: 9, height: height)
        var second = first
        overwrite(
            frame: &second,
            xRange: 0..<width,
            yRange: 18..<48,
            seed: 211
        )

        require(OverlapEstimator.estimateDownwardShift(from: first, to: second) == nil)
    }

    private static func testScrollingPageWithFixedBottomOverlay() {
        let width = 48
        let height = 120
        let page = makePage(width: width, height: 320)
        var first = window(page: page, width: width, offset: 14, height: height)
        var second = window(page: page, width: width, offset: 41, height: height)

        // Commerce apps often place a coupon strip and tab bar above the page.
        // Those viewport-fixed pixels must not win over the content that moved.
        overwrite(
            frame: &first,
            xRange: 0..<width,
            yRange: 86..<height,
            seed: 233
        )
        overwrite(
            frame: &second,
            xRange: 0..<width,
            yRange: 86..<height,
            seed: 233
        )

        let estimate = OverlapEstimator.estimateDownwardShift(from: first, to: second)
        require(estimate?.rows == 27)
    }

    private static func testFineAlignmentRecoversExactPixelShift() {
        let width = 48
        let height = 640
        let page = makePage(width: width, height: 1_100)
        let first = window(page: page, width: width, offset: 19, height: height)
        let second = window(page: page, width: width, offset: 156, height: height)

        // The fast thumbnail pass can map this movement back to roughly 143
        // source pixels. The seam pass must recover the exact 137-pixel shift.
        let estimate = OverlapEstimator.refineDownwardShift(
            from: first,
            to: second,
            around: 143,
            searchRadius: 12
        )
        require(estimate?.rows == 137)
    }

    private static func testFineAlignmentIgnoresFixedOverlay() {
        let width = 48
        let height = 640
        let page = makePage(width: width, height: 1_100)
        var first = window(page: page, width: width, offset: 19, height: height)
        var second = window(page: page, width: width, offset: 156, height: height)
        overwrite(frame: &first, xRange: 0..<width, yRange: 520..<610, seed: 317)
        overwrite(frame: &second, xRange: 0..<width, yRange: 520..<610, seed: 317)

        let estimate = OverlapEstimator.refineDownwardShift(
            from: first,
            to: second,
            around: 143,
            searchRadius: 12
        )
        require(estimate?.rows == 137)
    }

    private static func testRecordingPreludeIsExcluded() {
        let width = 32
        let page = makePage(width: width, height: 360)
        let unrelated = GrayFrame(
            width: width,
            height: 100,
            pixels: (0..<(width * 100)).map { index in
                UInt8(20 + ((index * 83 + (index / width) * 47) % 216))
            }
        )
        let firstTarget = window(page: page, width: width, offset: 0, height: 100)
        let frames = [unrelated, unrelated, unrelated, firstTarget, firstTarget]
            + [27, 54, 81, 108, 135].map {
                window(page: page, width: width, offset: $0, height: 100)
            }
            + [window(page: page, width: width, offset: 135, height: 100)]

        let selection = ScrollSequenceSelector.select(from: frames)
        require(selection?.startIndex == 4)
        require(selection?.endIndex == 9)
        require(selection?.preferredShiftRows == 27)
    }

    private static func makePage(width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 244, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let stripe = ((y / 7) * 31 + (x / 3) * 17 + y * 3) % 210
                let line = (y % 13 == 0 || x % 11 == 0) ? 25 : stripe + 30
                pixels[(y * width) + x] = UInt8(min(255, line))
            }
        }
        return pixels
    }

    private static func window(
        page: [UInt8],
        width: Int,
        offset: Int,
        height: Int
    ) -> GrayFrame {
        let start = offset * width
        let end = start + height * width
        return GrayFrame(width: width, height: height, pixels: Array(page[start..<end]))
    }

    private static func overwrite(
        frame: inout GrayFrame,
        xRange: Range<Int>,
        yRange: Range<Int>,
        seed: Int
    ) {
        var pixels = frame.pixels
        for y in yRange {
            for x in xRange {
                pixels[(y * frame.width) + x] = UInt8(
                    18 + ((x * 37 + y * 71 + seed) % 220)
                )
            }
        }
        frame = GrayFrame(width: frame.width, height: frame.height, pixels: pixels)
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError("Check failed", file: file, line: line)
        }
    }
}
