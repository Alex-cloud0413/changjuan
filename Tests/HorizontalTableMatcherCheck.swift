import Foundation

/// Pure Swift, deterministic fixtures. No device images, fonts, UIKit,
/// filesystem inputs, OpenCV, or expected displacement fed to X estimation.
@main
struct HorizontalTableMatcherCheck {
    private static var checks = 0
    private static let width = 600, headerHeight = 48, bodyHeight = 720
    private static let columnWidth = 120, rowHeight = 36

    private struct Viewport {
        let header: GrayFrame
        let body: GrayFrame
        let x: Int
        let y: Int
    }

    static func main() {
        let start = Date()
        let forward = [0, 91, 91, 183, 301, 440, 601, 781]
        let smallJitter = [0, 0, -1, 1, 2, -2, 0, 1]
        validateSequence("forward-native-pixels", x: forward, y: smallJitter)
        validateSequence("reverse-native-pixels", x: Array(forward.reversed()), y: Array(smallJitter.reversed()))
        validateSequence("revisit-and-pure-y", x: [0, 121, 241, 121, 121, 0, 91, 241],
                         y: [0, 3, -2, 2, -3, 0, 1, -1])
        validateSequence("near-period-alias", x: [0, 119, 239, 361, 240, 120],
                         y: [0, -1, 1, 2, 0, -2])
        validateSequence("native-three-pixel-step", x: [0, 1, 3, 6, 3, 2, 0],
                         y: [0, 1, -1, 1, 0, 2, 0])

        let a = makeViewport(x: 0, y: 0)
        let b = makeViewport(x: 91, y: 2)
        require(estimate(a, b, hint: -12) == nil, "A wrong independently measured Y must not become an accepted zero shift")
        require(estimate(a, b, hint: bodyHeight) == nil, "An impossible cross-axis hint must be rejected")
        let pureY = makeViewport(x: 0, y: -2)
        require(estimate(a, pureY, hint: 10) == nil, "A wrong Y hint on same-X movement must not be accepted as zero")

        let periodicA = makeViewport(x: 0, y: 0, uniqueHeader: false)
        let periodicB = makeViewport(x: columnWidth, y: 0, uniqueHeader: false)
        require(estimate(periodicA, periodicB, hint: 0) == nil,
                "Perfectly repeated labels cannot prove a column count even if pixels are identical")
        require(estimate(periodicA, periodicB, hint: nil) == nil,
                "Periodic ambiguity must also be rejected without a cross-axis hint")
        let disconnected = makeViewport(x: width + columnWidth, y: 0)
        require(estimate(a, disconnected, hint: 0) == nil,
                "Unique labels with no captured overlap must not match repeated body cells")
        require(estimate(a, disconnected, hint: nil) == nil, "Unobserved horizontal gaps must remain rejected without Y hint")

        let blankHeader = GrayFrame(width: width, height: headerHeight,
                                    pixels: [UInt8](repeating: 255, count: width * headerHeight))
        require(HorizontalTableMatcher.estimate(headerA: blankHeader, headerB: blankHeader,
            bodyA: a.body, bodyB: b.body, expectedCrossShift: 2) == nil,
            "Repeated body cells without labels cannot establish unique motion")
        // A column label can disappear behind a frozen pane before the next
        // label enters view. Distinct body content may prove that overlap.
        let uniqueA = makeViewport(x: 0, y: 0, uniqueBody: true)
        for dx in [0, 1, 91, 252, 419, 450] {
            for dy in [-2, 0, 2] {
                let uniqueB = makeViewport(x: dx, y: dy, uniqueBody: true)
                for reverse in [false, true] {
                    let previous = reverse ? uniqueB : uniqueA, current = reverse ? uniqueA : uniqueB
                    let result = HorizontalTableMatcher.estimate(headerA: blankHeader, headerB: blankHeader,
                        bodyA: previous.body, bodyB: current.body, expectedCrossShift: reverse ? -dy : dy)
                    require(result?.dx == (reverse ? -dx : dx) && result?.dy == (reverse ? -dy : dy),
                        "Unlabeled unique body dx=\(dx) dy=\(dy) reverse=\(reverse): \(String(describing: result))")
                }
            }
        }
        let uniqueB = makeViewport(x: 252, y: 0, uniqueBody: true)
        // Tiny clipped glyphs at a frozen-pane boundary are not contradictory
        // visible labels. Full body verification is still mandatory.
        var clippedA = blankHeader.pixels, clippedB = blankHeader.pixels
        for y in 12..<24 {
            clippedA[y * width + 252] = 65
            clippedB[y * width] = 145
            clippedB[y * width + 1] = 180
        }
        let edgeA = GrayFrame(width: width, height: headerHeight, pixels: clippedA)
        let edgeB = GrayFrame(width: width, height: headerHeight, pixels: clippedB)
        for reverse in [false, true] {
            let result = HorizontalTableMatcher.estimate(headerA: reverse ? edgeB : edgeA,
                headerB: reverse ? edgeA : edgeB, bodyA: reverse ? uniqueB.body : uniqueA.body,
                bodyB: reverse ? uniqueA.body : uniqueB.body, expectedCrossShift: 0)
            require(result?.dx == (reverse ? -252 : 252), "Clipped boundary glyph must not veto verified body overlap")
        }
        for dy in [-2, 0, 2] {
            require(HorizontalTableMatcher.correlationParity(uniqueA.body, makeViewport(x: 159, y: dy, uniqueBody: true).body, dy: dy),
                "Accelerate must match every scalar candidate, including negative X")
            require(HorizontalTableMatcher.correlationParity(periodicA.body, periodicB.body, dy: dy),
                "Accelerate must preserve periodic ambiguity scores")
        }
        for w in [81, 257, 567] {
            let p = (0..<(w * 177)).map { UInt8(($0 * 131 + ($0 / w) * 17) % 256) }
            let a = GrayFrame(width: w, height: 177, pixels: p)
            let b = GrayFrame(width: w, height: 177, pixels: p.reversed())
            require(HorizontalTableMatcher.correlationParity(a, b, dy: -2), "Odd-width all-candidate numerical parity")
            let blank = GrayFrame(width: w, height: 177, pixels: [UInt8](repeating: 255, count: p.count))
            require(HorizontalTableMatcher.correlationParity(blank, blank, dy: 0), "Blank evidence remains absent")
        }
        require(HorizontalTableMatcher.estimate(headerA: blankHeader, headerB: blankHeader,
            bodyA: uniqueA.body, bodyB: uniqueB.body, expectedCrossShift: 12) == nil,
            "Body fallback cannot override contradictory cross-axis evidence")
        require(HorizontalTableMatcher.estimate(headerA: blankHeader, headerB: blankHeader,
            bodyA: uniqueA.body, bodyB: uniqueB.body) == nil,
            "Unlabeled fallback requires independently constrained cross-axis position")
        require(HorizontalTableMatcher.estimate(headerA: blankHeader, headerB: blankHeader,
            bodyA: uniqueA.body, bodyB: makeViewport(x: width + 120, y: 0, uniqueBody: true).body,
            expectedCrossShift: 0) == nil, "Distinct body content without captured overlap must fail")
        require(HorizontalTableMatcher.estimate(headerA: uniqueA.header, headerB: uniqueA.header,
            bodyA: uniqueA.body, bodyB: uniqueB.body, expectedCrossShift: 0) == nil,
            "Body evidence must not overrule contradictory visible column labels")
        var narrowA = uniqueA.body.pixels, narrowB = uniqueB.body.pixels
        for index in (width * bodyHeight / 4)..<narrowA.count { narrowA[index] = 250; narrowB[index] = 250 }
        require(HorizontalTableMatcher.estimate(headerA: blankHeader, headerB: blankHeader,
            bodyA: GrayFrame(width: width, height: bodyHeight, pixels: narrowA),
            bodyB: GrayFrame(width: width, height: bodyHeight, pixels: narrowB), expectedCrossShift: 0) == nil,
            "One localized unique patch cannot establish session-wide table motion")
        let incompatibleHeader = GrayFrame(width: width - 1, height: headerHeight,
                                          pixels: [UInt8](repeating: 255, count: (width - 1) * headerHeight))
        require(HorizontalTableMatcher.estimate(headerA: a.header, headerB: incompatibleHeader,
            bodyA: a.body, bodyB: b.body) == nil, "Mismatched image geometry must fail safely")

        print("Horizontal table matcher passed: \(checks) checks; original-pixel X/Y, independent hinted/unhinted paths, repeated-column ambiguity and unknown gaps; \(String(format: "%.3f", Date().timeIntervalSince(start)))s")
    }

    private static func validateSequence(_ name: String, x: [Int], y: [Int]) {
        require(x.count == y.count, "Fixture coordinate arrays must be paired")
        let views = zip(x, y).map { makeViewport(x: $0.0, y: $0.1) }
        for index in 1..<views.count {
            let previous = views[index - 1], current = views[index]
            let dx = current.x - previous.x, dy = current.y - previous.y
            for hinted in [true, false] {
                let result = estimate(previous, current, hint: hinted ? dy : nil)
                require(result?.dx == dx && result?.dy == dy,
                    "\(name) edge \(index - 1)->\(index), hint=\(hinted), expected \(dx),\(dy); got \(String(describing: result))")
                require(result.map { $0.score.isFinite && $0.confidence.isFinite && $0.confidence > 0 } ?? false,
                    "Accepted matches need finite scores and positive evidence confidence")
            }
        }
    }

    private static func estimate(_ a: Viewport, _ b: Viewport, hint: Int?) -> HorizontalTableEstimate? {
        HorizontalTableMatcher.estimate(headerA: a.header, headerB: b.header,
            bodyA: a.body, bodyB: b.body, expectedCrossShift: hint)
    }

    private static func makeViewport(x: Int, y: Int, uniqueHeader: Bool = true, uniqueBody: Bool = false) -> Viewport {
        var header = [UInt8](repeating: 250, count: width * headerHeight)
        var body = [UInt8](repeating: 250, count: width * bodyHeight)
        for localX in 0..<width {
            let worldX = localX + x
            let column = worldX / columnWidth, inColumn = worldX % columnWidth
            for localY in 0..<headerHeight {
                let value: UInt8
                if inColumn == 0 || localY == headerHeight - 1 { value = 205 }
                else if localY >= 12 && localY < 33 && inColumn >= 21 && inColumn < 66 {
                    // Three distinct 5x7 glyph-like bitmaps form a per-column ID.
                    // This deliberately uses no system font/rendering backend.
                    let glyph = (inColumn - 21) / 15
                    let gx = ((inColumn - 21) % 15) / 3, gy = (localY - 12) / 3
                    let identity = uniqueHeader ? column + 1 : 1
                    value = mark(identity: identity * 7 + glyph * 101, x: gx, y: gy) ? 26 : 250
                } else { value = 250 }
                header[localY * width + localX] = value
            }
            for localY in 0..<bodyHeight {
                // Positive y means content moves down on screen, while header Y
                // remains frozen. A margin keeps all generated world Y positive.
                let worldY = localY - y + rowHeight * 3
                let row = worldY / rowHeight, inRow = worldY % rowHeight
                let value: UInt8
                if inColumn == 0 || inRow == 0 { value = 205 }
                else if (uniqueBody || column % 3 != 0) && inColumn >= 18 && inColumn < 48 && inRow >= 9 && inRow < 23 {
                    // Body cell contents repeat across columns, with completely
                    // blank intervening columns. Header identity must resolve X.
                    let gx = ((inColumn - 18) % 15) / 3, gy = (inRow - 9) / 2
                    value = mark(identity: uniqueBody ? column * 151 + row * 7 + 17 : row % 5 + 17, x: gx, y: gy) ? 60 : 250
                } else { value = 250 }
                body[localY * width + localX] = value
            }
        }
        return Viewport(header: GrayFrame(width: width, height: headerHeight, pixels: header),
                        body: GrayFrame(width: width, height: bodyHeight, pixels: body), x: x, y: y)
    }

    private static func mark(identity: Int, x: Int, y: Int) -> Bool {
        var seed = UInt64(identity + 1) &* 0x9e3779b97f4a7c15
        seed ^= UInt64(y * 5 + x + 1) &* 0xbf58476d1ce4e5b9
        seed ^= seed >> 30
        seed &*= 0xbf58476d1ce4e5b9
        seed ^= seed >> 27
        return seed & 1 == 1
    }

    private static func require(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError(message) }
    }
}
