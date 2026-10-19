import Foundation

/// A translation in original screen pixels. Positive X exposes content to the
/// right; positive Y means the body is lower in the second captured viewport.
struct HorizontalTableEstimate: Equatable {
    let dx: Int
    let dy: Int
    let score: Double
    let confidence: Double
}

/// Layer-specific translation matching. Column labels establish a unique X;
/// the independently moving body must support that X and the measured Y.
/// This is deliberately separate from the vertical screenshot matcher.
enum HorizontalTableMatcher {
    static func estimate(headerA: GrayFrame, headerB: GrayFrame,
                         bodyA: GrayFrame, bodyB: GrayFrame,
                         expectedCrossShift: Int? = nil) -> HorizontalTableEstimate? {
        guard headerA.width == headerB.width, headerA.height == headerB.height,
              bodyA.width == bodyB.width, bodyA.height == bodyB.height,
              headerA.width == bodyA.width, headerA.width >= 48,
              headerA.height >= 8, bodyA.height >= 32 else { return nil }
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
        guard !proposals.isEmpty else { return nil }
        // A patch which has left the viewport can resemble another letter.
        // Only the entire common header can validate its proposed translation.
        var headerScores: [(x: Int, correlation: Double)] = []
        for dx in proposals {
            if let cc = correlation(headerA, headerB, ax: max(0, dx), bx: max(0, -dx),
                width: width - abs(dx), rows: headerRows, xStride: 1) {
                headerScores.append((dx, cc))
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
        return HorizontalTableEstimate(dx: dx, dy: alignedBody.dy,
            score: (1 - min(headerBest.correlation, alignedBody.correlation)) * 100,
            confidence: min(1, min(headerMargin, patchMargins.max() ?? 0) / 0.10))
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

    private static func bodyCorrelation(_ a: GrayFrame, _ b: GrayFrame, dx: Int, dy: Int) -> Double? {
        let startX = max(0, dx), otherX = max(0, -dx), width = a.width - abs(dx)
        let startY = max(0, -dy), otherY = max(0, dy), height = a.height - abs(dy)
        guard width >= a.width * 3 / 10, height >= a.height * 9 / 10 else { return nil }
        let xStride = max(1, width / 300), yStride = max(1, height / 180)
        var aa = 0.0, bb = 0.0, ab = 0.0, sa = 0.0, sb = 0.0, count = 0.0
        for y in stride(from: 0, to: height, by: yStride) {
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
