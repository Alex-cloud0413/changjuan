import Foundation
import Accelerate

/// Session-wide motion evidence, independent of app names, colours and column
/// widths. Observations retain native X and a small, normalized Y profile.
/// The accumulator is O(viewport), not O(recording length).
struct HorizontalMotionLayout {
    let frozenLeadingPixels: Int
    let observations: Int

    struct Accumulator {
        private var anchor: GrayFrame?
        private var variation: [UInt8] = []
        private var observations = 0

        mutating func observe(_ frame: GrayFrame) {
            guard let anchor else {
                self.anchor = frame
                variation = [UInt8](repeating: 0, count: frame.pixels.count)
                observations = 1
                return
            }
            guard anchor.width == frame.width, anchor.height == frame.height else { return }
            for index in variation.indices {
                variation[index] = max(variation[index], UInt8(abs(Int(anchor.pixels[index]) - Int(frame.pixels[index]))))
            }
            observations += 1
        }

        func resolve() -> HorizontalMotionLayout {
            guard let anchor, observations >= 2 else {
                return HorizontalMotionLayout(frozenLeadingPixels: 0, observations: observations)
            }
            let width = anchor.width, height = anchor.height
            var moving = [Bool](repeating: false, count: width)
            for x in 0..<width {
                let changed = (0..<height).reduce(0) { $0 + (variation[$1 * width + x] > 18 ? 1 : 0) }
                moving[x] = changed >= max(3, height / 35)
            }
            // Several adjacent columns must carry real temporal differences;
            // a single selected-cell border or compression halo is not motion.
            let firstMoving = (0..<max(0, width - 4)).first { x in
                moving[x] && (x..<min(width, x + 5)).filter { moving[$0] }.count >= 3
            } ?? 0
            guard firstMoving > 2 else {
                return HorizontalMotionLayout(frozenLeadingPixels: 0, observations: observations)
            }
            // Require a screen-fixed, vertically supported boundary. White
            // space alone must never be mistaken for a frozen pane. Choosing
            // a boundary is analysis/coverage only; no source pixels are cut
            // out of the opening viewport.
            var boundary = 0
            let edgeRadius = max(1, width / 384)
            for x in 1..<min(firstMoving + 1, width - 1) {
                var supported = 0
                for y in 0..<height {
                    let p = y * width + x
                    let edge = max(abs(Int(anchor.pixels[p]) - Int(anchor.pixels[y * width + max(0, x - edgeRadius)])),
                                   abs(Int(anchor.pixels[p]) - Int(anchor.pixels[y * width + min(width - 1, x + edgeRadius)])))
                    if variation[p] <= 12 && edge >= 4 { supported += 1 }
                }
                if supported * 5 >= height * 3 { boundary = x + 1 }
            }
            if firstMoving - boundary > max(8, width / 50) {
                // Some panes have no visible divider. The temporal envelope
                // still proves a stable leading region. Use a conservative
                // analysis boundary at its first changing pixels; the entire
                // first viewport is retained, and coverage may reject a gap
                // rather than treating these uncertain edge pixels as overlap.
                boundary = firstMoving + edgeRadius
            }
            // Preserve at least a usable matching strip; narrower/ambiguous
            // viewports fail in registration instead of inventing movement.
            return HorizontalMotionLayout(frozenLeadingPixels: min(boundary, width - 48), observations: observations)
        }
    }
}

/// A translation in original screen pixels. Positive X exposes content to the
/// right; positive Y means the body is lower in the second captured viewport.
struct HorizontalTableEstimate: Equatable {
    let dx: Int
    let dy: Int
    let score: Double
    let confidence: Double
}

/// Layer-specific translation matching. Labels normally establish a unique X.
/// When labels leave the common viewport, independently unique body evidence
/// may establish X; periodic grids and contradictory visible labels may not.
/// This is deliberately separate from the vertical screenshot matcher.
enum HorizontalTableMatcher {
#if LONGSHOT_CAPTURE_CHECKS
    nonisolated(unsafe) static var diagnosticTrace: ((String) -> Void)?
    static func correlationParity(_ a: GrayFrame, _ b: GrayFrame, dy: Int) -> Bool {
        let maximum = a.width - max(64, a.width / 5)
        let dense = Dictionary(uniqueKeysWithValues: denseBodyCorrelations(a, b, dy: dy, maximum: maximum, sampleRows: 72))
        for dx in -maximum...maximum {
            let scalar = bodyCorrelation(a, b, dx: dx, dy: dy, sampleColumns: a.width,
                sampleRows: 72, minimumOverlap: a.width - maximum)
            switch (dense[dx], scalar) {
            case (nil, nil): break
            case let (actual?, expected?): if abs(actual - expected) > 1e-10 { return false }
            default: return false
            }
        }
        return true
    }
#endif
    static func estimate(headerA: GrayFrame, headerB: GrayFrame,
                         bodyA: GrayFrame, bodyB: GrayFrame,
                         expectedCrossShift: Int? = nil,
                         isolatedMovingBody: Bool = true) -> HorizontalTableEstimate? {
        guard headerA.width == headerB.width, headerA.height == headerB.height,
              bodyA.width == bodyB.width, bodyA.height == bodyB.height,
              headerA.width == bodyA.width, headerA.width >= 48,
              headerA.height >= 8, bodyA.height >= 32 else { return nil }
        if let labeled = estimateUsingHeader(headerA: headerA, headerB: headerB,
            bodyA: bodyA, bodyB: bodyB, expectedCrossShift: expectedCrossShift,
            isolatedMovingBody: isolatedMovingBody) { return labeled }
        return estimateUsingBody(headerA: headerA, headerB: headerB,
            bodyA: bodyA, bodyB: bodyB, expectedCrossShift: expectedCrossShift,
            isolatedMovingBody: isolatedMovingBody)
    }

    private static func estimateUsingHeader(headerA: GrayFrame, headerB: GrayFrame,
        bodyA: GrayFrame, bodyB: GrayFrame, expectedCrossShift: Int?,
        isolatedMovingBody: Bool) -> HorizontalTableEstimate? {
        let width = headerA.width
        let headerRows = texturedRows(headerA, headerB)
        guard headerRows.count >= 3 else { return nil }
        let patchWidth = max(20, Int((Double(width) * 0.38).rounded()))
        let candidateStride = max(1, width / 550)
        var proposals = Set<Int>()
        var patchMargins: [Double] = []
        for fraction in [0.15, 0.31, 0.47] {
            let start = Int(Double(width) * fraction)
            guard start + patchWidth <= width else { continue }
            var coarse: [(x: Int, correlation: Double)] = []
            for source in stride(from: 0, through: width - patchWidth, by: candidateStride) {
                if let correlation = correlation(headerA, headerB, ax: source, bx: start,
                    width: patchWidth, rows: headerRows, xStride: 2) {
                    coarse.append((source, correlation))
                }
            }
            // Refine several separated peaks, not just the first periodic peak.
            let coarsePeaks = separatedPeaks(coarse, distance: max(5, candidateStride * 3), limit: 8)
            var refined: [(x: Int, correlation: Double)] = []
            var visited = Set<Int>()
            for peak in coarsePeaks {
                for source in max(0, peak.x - candidateStride)...min(width - patchWidth, peak.x + candidateStride) {
                    guard visited.insert(source).inserted else { continue }
                    if let correlation = correlation(headerA, headerB, ax: source, bx: start,
                        width: patchWidth, rows: headerRows, xStride: 1) {
                        refined.append((source, correlation))
                    }
                }
            }
            let peaks = separatedPeaks(refined, distance: 8, limit: 2)
            guard let best = peaks.first, best.correlation >= 0.94 else { continue }
            let margin = best.correlation - (peaks.dropFirst().first?.correlation ?? -1)
            guard margin >= 0.025 else { continue }
            let dx = best.x - start
            guard abs(dx) <= width * 7 / 10 else { continue }
            proposals.insert(dx)
            patchMargins.append(margin)
        }
        // A patch which has left the viewport can resemble another letter.
        // Only the entire common header can validate its proposed translation.
        var headerScores: [(x: Int, correlation: Double)] = []
        for dx in proposals {
            if let cc = correlation(headerA, headerB, ax: max(0, dx), bx: max(0, -dx),
                width: width - abs(dx), rows: headerRows, xStride: 1) {
                headerScores.append((dx, cc))
            }
        }
        // A wide frozen pane can leave only one or two visible labels. A
        // fractional patch may contain no glyph at all. Search the complete
        // common label band instead; ambiguity and body validation below are
        // unchanged. This is geometry-driven, not a table/app-specific rule.
        if headerScores.map(\.correlation).max() ?? -1 < 0.96 {
            let maximum = width * 7 / 10
            var coarse: [(x: Int, correlation: Double)] = []
            for dx in stride(from: -maximum, through: maximum, by: candidateStride) {
                if let cc = correlation(headerA, headerB, ax: max(0, dx), bx: max(0, -dx),
                    width: width - abs(dx), rows: headerRows, xStride: 2) { coarse.append((dx, cc)) }
            }
            for peak in separatedPeaks(coarse, distance: max(5, candidateStride * 3), limit: 8) {
                for dx in max(-maximum, peak.x - candidateStride)...min(maximum, peak.x + candidateStride) {
                    if let cc = correlation(headerA, headerB, ax: max(0, dx), bx: max(0, -dx),
                        width: width - abs(dx), rows: headerRows, xStride: 1) { headerScores.append((dx, cc)) }
                }
            }
        }
        let headerPeaks = separatedPeaks(headerScores, distance: 2, limit: 2)
        guard let headerBest = headerPeaks.first, headerBest.correlation >= 0.96 else { return nil }
        let headerMargin = headerBest.correlation - (headerPeaks.dropFirst().first?.correlation ?? -1)
        guard headerMargin >= 0.025 else { return nil }
        let dx = headerBest.x
        let maximumY = max(2, bodyA.height / 40)
        if let expectedCrossShift, abs(expectedCrossShift) > maximumY { return nil }
        let lowerY = expectedCrossShift.map { max(-maximumY, $0 - 2) } ?? -maximumY
        let upperY = expectedCrossShift.map { min(maximumY, $0 + 2) } ?? maximumY
        var bodyScores: [(dx: Int, dy: Int, correlation: Double)] = []
        for candidateX in (dx - 1)...(dx + 1) where abs(candidateX) < width * 7 / 10 {
            for candidateY in lowerY...upperY {
                if let cc = bodyCorrelation(bodyA, bodyB, dx: candidateX, dy: candidateY) {
                    bodyScores.append((candidateX, candidateY, cc))
                }
            }
        }
        guard let bestBody = bodyScores.max(by: { $0.correlation < $1.correlation }),
              let alignedBody = bodyScores.filter({ $0.dx == dx }).max(by: { $0.correlation < $1.correlation }),
              alignedBody.correlation >= 0.85,
              bestBody.correlation - alignedBody.correlation <= 0.01 else { return nil }
        // A cross-axis hint is independent grid-line evidence, not a horizontal
        // continuity guess. Require agreement within one original pixel.
        if let expectedCrossShift, abs(alignedBody.dy - expectedCrossShift) > 1 { return nil }
        // On a narrow viewport a clipped letter plus a periodic grid can make
        // the wrong column pass luminance correlation. Check text edges at
        // native X too, rather than letting white cell area dominate the vote.
        // Only apply this whole-body test after a screen-fixed prefix has been
        // isolated. An unsegmented viewport can still contain fixed row numbers
        // whose ink must not veto an otherwise verified scrolling body.
        if isolatedMovingBody {
            guard let detail = bodyCorrelation(horizontalDetail(bodyA), horizontalDetail(bodyB),
                dx: dx, dy: alignedBody.dy, sampleColumns: width), detail >= 0.92 else { return nil }
        }
        return HorizontalTableEstimate(dx: dx, dy: alignedBody.dy,
            score: (1 - min(headerBest.correlation, alignedBody.correlation)) * 100,
            confidence: min(1, min(headerMargin, patchMargins.max() ?? 0) / 0.10))
    }

    /// No direction or previous displacement is supplied to this search. A
    /// strong match must win across the entire supported overlap range and
    /// agree in separated body regions, not only on a repeated row/column line.
    private static func estimateUsingBody(headerA: GrayFrame, headerB: GrayFrame,
        bodyA: GrayFrame, bodyB: GrayFrame, expectedCrossShift: Int?,
        isolatedMovingBody: Bool) -> HorizontalTableEstimate? {
        guard bodyA.width >= 80, let dy = expectedCrossShift,
              abs(dy) <= max(2, bodyA.height / 40) else { return nil }
        let width = bodyA.width, minimumOverlap = max(64, bodyA.width / 5)
        let maximum = width - minimumOverlap
        let a = horizontalDetail(bodyA), b = horizontalDetail(bodyB)
        let scores = denseBodyCorrelations(a, b, dy: dy, maximum: maximum, sampleRows: 72)
        // Native X avoids both lost narrow peaks and sampling only the middle
        // of repeated three-pixel glyph strokes (a false perfect grid match).
        let peaks = separatedPeaks(scores, distance: 4, limit: 2)
#if LONGSHOT_CAPTURE_CHECKS
        diagnosticTrace?("body peaks=\(peaks) dy=\(dy)")
#endif
        guard let best = peaks.first, best.correlation >= 0.94 else { return nil }
        let margin = best.correlation - (peaks.dropFirst().first?.correlation ?? -1)
        guard margin >= 0.08 else { return nil }
        let dx = best.x
        let detailScore = bodyCorrelation(a, b, dx: dx, dy: dy, sampleColumns: width, minimumOverlap: minimumOverlap)
        let pixelScore = bodyCorrelation(bodyA, bodyB, dx: dx, dy: dy, minimumOverlap: minimumOverlap)
#if LONGSHOT_CAPTURE_CHECKS
        diagnosticTrace?("body verification detail=\(String(describing: detailScore)) pixels=\(String(describing: pixelScore))")
#endif
        guard let detail = detailScore, detail >= 0.94,
              let pixels = pixelScore, pixels >= 0.97 else { return nil }
        // The common heading may be blank when the old label is hidden behind
        // frozen columns and the next label was previously beyond the screen.
        // If both headings DO contain comparable texture, it must corroborate.
        let rows = Array(1..<(headerA.height - 1))
        // The frozen divider clips/antialiases the last few pixels of a label
        // as it leaves the moving viewport. Those boundary pixels are not a
        // contradictory whole glyph. Ignore only this narrow analysis rim;
        // unique body evidence above and three independent bands below still
        // have to prove X. No output pixels or columns are cropped.
        let rim = isolatedMovingBody ? max(1, min(4, headerA.height / 6)) : 0
        if let heading = correlation(headerA, headerB, ax: max(0, dx) + rim, bx: max(0, -dx) + rim,
            width: width - abs(dx) - rim * 2, rows: rows, xStride: 1), heading < 0.90 { return nil }
        let commonHeight = bodyA.height - abs(dy)
        var supported = 0
        for band in 0..<4 {
            let range = (band * commonHeight / 4)..<((band + 1) * commonHeight / 4)
#if LONGSHOT_CAPTURE_CHECKS
            diagnosticTrace?("body band=\(band) score=\(String(describing: bodyCorrelation(a, b, dx: dx, dy: dy, rows: range, sampleColumns: width, minimumOverlap: minimumOverlap)))")
#endif
            guard let agreement = bodyCorrelation(a, b, dx: dx, dy: dy, rows: range, sampleColumns: width, minimumOverlap: minimumOverlap),
                  agreement >= 0.94 else { continue }
            // Each region must independently distinguish the best competing X.
            if let rival = peaks.dropFirst().first,
               let competing = bodyCorrelation(a, b, dx: rival.x, dy: dy, rows: range, sampleColumns: width, minimumOverlap: minimumOverlap),
               agreement - competing < 0.06 { continue }
            supported += 1
        }
        guard supported >= 3 else { return nil }
        return HorizontalTableEstimate(dx: dx, dy: dy,
            score: (1 - min(detail, pixels)) * 100, confidence: min(1, margin / 0.15))
    }

    private static func horizontalDetail(_ frame: GrayFrame) -> GrayFrame {
        var pixels = [UInt8](repeating: 128, count: frame.pixels.count)
        for y in 0..<frame.height {
            let row = y * frame.width
            for x in 1..<(frame.width - 1) {
                let delta = Int(frame.pixels[row + x + 1]) - Int(frame.pixels[row + x - 1])
                pixels[row + x] = UInt8(clamping: 128 + delta / 2)
            }
        }
        return GrayFrame(width: frame.width, height: frame.height, pixels: pixels)
    }

    /// All native-X candidates, with exactly the same rows and normalized
    /// correlation as the scalar search. Accelerate computes only dot products;
    /// prefix sums supply overlap-specific moments. No candidates are pruned,
    /// thresholds relaxed, or image pixels resampled to gain speed.
    private static func denseBodyCorrelations(_ a: GrayFrame, _ b: GrayFrame,
        dy: Int, maximum: Int, sampleRows: Int) -> [(x: Int, correlation: Double)] {
        let width = a.width, height = a.height - abs(dy)
        let startY = max(0, -dy), otherY = max(0, dy)
        let ys = Array(stride(from: 0, to: height, by: max(1, height / sampleRows)))
        var sa = [Double](repeating: 0, count: width + 1), sb = sa, aa = sa, bb = sa
        let count = maximum * 2 + 1
        var dots = [Double](repeating: 0, count: count)
        var rowDots = dots, signal = [Double](repeating: 0, count: width + maximum * 2)
        var filter = [Double](repeating: 0, count: width)
        for y in ys {
            for x in 0..<width {
                let av = Double(a[x, y + startY]), bv = Double(b[x, y + otherY])
                signal[maximum + x] = av; filter[x] = bv
                sa[x + 1] += av; sb[x + 1] += bv
                aa[x + 1] += av * av; bb[x + 1] += bv * bv
            }
            vDSP_convD(signal, 1, filter, 1, &rowDots, 1, vDSP_Length(count), vDSP_Length(width))
            for i in dots.indices { dots[i] += rowDots[i] }
        }
        for x in 1...width { sa[x] += sa[x - 1]; sb[x] += sb[x - 1]; aa[x] += aa[x - 1]; bb[x] += bb[x - 1] }
        return (-maximum...maximum).compactMap { dx in
            let ax = max(0, dx), bx = max(0, -dx), overlap = width - abs(dx)
            let n = Double(overlap * ys.count)
            let sumA = sa[ax + overlap] - sa[ax], sumB = sb[bx + overlap] - sb[bx]
            let va = aa[ax + overlap] - aa[ax] - sumA * sumA / n
            let vb = bb[bx + overlap] - bb[bx] - sumB * sumB / n
            guard va / n >= 4, vb / n >= 4 else { return nil }
            return (dx, (dots[dx + maximum] - sumA * sumB / n) / sqrt(va * vb))
        }
    }

    private static func texturedRows(_ a: GrayFrame, _ b: GrayFrame) -> [Int] {
        var rows: [Int] = []
        let rowStride = max(1, a.height / 28)
        for y in stride(from: 1, to: a.height - 1, by: rowStride) {
            var sumA = 0.0, sumB = 0.0, squaresA = 0.0, squaresB = 0.0, count = 0.0
            for x in stride(from: 1, to: a.width - 1, by: 2) {
                let av = Double(a[x, y]), bv = Double(b[x, y])
                sumA += av; sumB += bv; squaresA += av * av; squaresB += bv * bv; count += 1
            }
            guard count > 0 else { continue }
            let varianceA = squaresA / count - pow(sumA / count, 2)
            let varianceB = squaresB / count - pow(sumB / count, 2)
            if min(varianceA, varianceB) >= 4 { rows.append(y) }
        }
        return rows
    }

    private static func separatedPeaks(_ values: [(x: Int, correlation: Double)],
                                       distance: Int, limit: Int) -> [(x: Int, correlation: Double)] {
        var peaks: [(x: Int, correlation: Double)] = []
        for value in values.sorted(by: { $0.correlation > $1.correlation }) {
            guard peaks.allSatisfy({ abs($0.x - value.x) > distance }) else { continue }
            peaks.append(value)
            if peaks.count == limit { break }
        }
        return peaks
    }

    private static func correlation(_ a: GrayFrame, _ b: GrayFrame, ax: Int, bx: Int,
                                    width: Int, rows: [Int], xStride: Int) -> Double? {
        guard width >= 16, ax >= 0, bx >= 0, ax + width <= a.width, bx + width <= b.width else { return nil }
        var aa = 0.0, bb = 0.0, ab = 0.0, sa = 0.0, sb = 0.0, count = 0.0
        for y in rows {
            let offset = y * a.width
            for x in stride(from: 0, to: width, by: xStride) {
                let av = Double(a.pixels[offset + ax + x]), bv = Double(b.pixels[offset + bx + x])
                sa += av; sb += bv; aa += av * av; bb += bv * bv; ab += av * bv; count += 1
            }
        }
        let va = aa - sa * sa / count, vb = bb - sb * sb / count
        guard count > 0, va / count >= 4, vb / count >= 4 else { return nil }
        return (ab - sa * sb / count) / sqrt(va * vb)
    }

    private static func bodyCorrelation(_ a: GrayFrame, _ b: GrayFrame, dx: Int, dy: Int,
        rows: Range<Int>? = nil, sampleColumns: Int = 300, sampleRows: Int = 180,
        minimumOverlap: Int? = nil) -> Double? {
        let startX = max(0, dx), otherX = max(0, -dx), width = a.width - abs(dx)
        let startY = max(0, -dy), otherY = max(0, dy), height = a.height - abs(dy)
        guard width >= (minimumOverlap ?? a.width * 3 / 10), height >= a.height * 9 / 10 else { return nil }
        let selectedRows = rows ?? 0..<height
        guard selectedRows.lowerBound >= 0, selectedRows.upperBound <= height, !selectedRows.isEmpty else { return nil }
        let xStride = max(1, width / sampleColumns), yStride = max(1, selectedRows.count / sampleRows)
        var aa = 0.0, bb = 0.0, ab = 0.0, sa = 0.0, sb = 0.0, count = 0.0
        for y in stride(from: selectedRows.lowerBound, to: selectedRows.upperBound, by: yStride) {
            let aOffset = (startY + y) * a.width + startX
            let bOffset = (otherY + y) * b.width + otherX
            for x in stride(from: 0, to: width, by: xStride) {
                let av = Double(a.pixels[aOffset + x]), bv = Double(b.pixels[bOffset + x])
                sa += av; sb += bv; aa += av * av; bb += bv * bv; ab += av * bv; count += 1
            }
        }
        let va = aa - sa * sa / count, vb = bb - sb * sb / count
        guard count > 0, va / count >= 4, vb / count >= 4 else { return nil }
        return (ab - sa * sb / count) / sqrt(va * vb)
    }
}
