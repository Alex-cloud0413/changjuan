import Foundation

struct GrayFrame: Equatable {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    // A frame participates in hundreds of shift candidates. Compute its edge
    // map once; the values and matching thresholds are unchanged.
    let edges: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0)
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
        var edges = [UInt8](repeating: 0, count: pixels.count)
        if width >= 3, height >= 3 {
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let i = y * width + x
                    let horizontal = abs(Int(pixels[i + 1]) - Int(pixels[i - 1]))
                    let vertical = abs(Int(pixels[i + width]) - Int(pixels[i - width]))
                    edges[i] = UInt8(min(255, horizontal + vertical))
                }
            }
        }
        self.edges = edges
    }

    subscript(x: Int, y: Int) -> UInt8 {
        pixels[(y * width) + x]
    }
}

struct ShiftEstimate: Equatable {
    let rows: Int
    let score: Double
    let confidence: Double
}

struct ScrollSequenceSelection: Equatable {
    let startIndex: Int
    let endIndex: Int
    let preferredShiftRows: Int
}

struct ScrollSequenceAnalysis {
    let selection: ScrollSequenceSelection
    let comparisons: [ShiftComparison?]
}

struct ShiftComparison {
    let candidates: [(shift: Int, score: Double)]
    let frameHeight: Int

    func estimate(preferredShiftRows: Int? = nil) -> ShiftEstimate? {
        OverlapEstimator.chooseEstimate(from: self, preferredShiftRows: preferredShiftRows)
    }
}

struct VerticalShiftComparison {
    let downward: ShiftComparison?
    let upward: ShiftComparison?

    func estimate(preferredShiftRows: Int? = nil) -> ShiftEstimate? {
        let down = downward?.estimate(preferredShiftRows: preferredShiftRows)
        let up = upward?.estimate(preferredShiftRows: preferredShiftRows)
        switch (down, up) {
        case (nil, nil): return nil
        case (let value?, nil): return value
        case (nil, let value?):
            return ShiftEstimate(rows: -value.rows, score: value.score, confidence: value.confidence)
        case (let down?, let up?):
            // Direction is measured from the images, never forced by the last
            // gesture. Ambiguous repeating patterns are not a trustworthy seam.
            guard abs(down.score - up.score) > max(0.4, min(down.score, up.score) * 0.06) else { return nil }
            return down.score < up.score ? down : ShiftEstimate(
                rows: -up.rows, score: up.score, confidence: up.confidence
            )
        }
    }
}

struct BidirectionalScrollAnalysis {
    let selection: ScrollSequenceSelection
    let comparisons: [VerticalShiftComparison?]
}

enum BidirectionalScrollSelector {
    private struct Edge {
        let index: Int
        let estimate: ShiftEstimate
    }

    static func analyze(frames: [GrayFrame]) -> BidirectionalScrollAnalysis? {
        guard frames.count >= 2 else { return nil }
        var comparisons = [VerticalShiftComparison?](repeating: nil, count: frames.count)
        var edges: [Edge] = []
        for index in 1..<frames.count {
            guard OverlapEstimator.meanAbsoluteDifference(frames[index - 1], frames[index]) >= 2.6 else { continue }
            let comparison = OverlapEstimator.compareVertical(from: frames[index - 1], to: frames[index])
            comparisons[index] = comparison
            if let estimate = comparison.estimate() { edges.append(Edge(index: index, estimate: estimate)) }
        }
        // Two agreeing motions reject one app-switch animation. A genuinely
        // two-frame recording is allowed and still receives pixel refinement.
        let minimumEdges = frames.count == 2 ? 1 : 2
        var clusters: [[Edge]] = []
        for edge in edges {
            if let last = clusters.last?.last, edge.index - last.index <= 7 {
                clusters[clusters.count - 1].append(edge)
            } else { clusters.append([edge]) }
        }
        guard var best = clusters.filter({ $0.count >= minimumEdges }).max(by: {
            $0.count < $1.count || ($0.count == $1.count && distance($0) < distance($1))
        }) else { return nil }
        while best.count >= 3 {
            let typical = median(best.dropFirst().map { abs($0.estimate.rows) })
            if best[1].index - best[0].index > 3
                || abs(abs(best[0].estimate.rows) - typical) > max(4, typical) {
                best.removeFirst()
            } else { break }
        }
        return BidirectionalScrollAnalysis(
            selection: ScrollSequenceSelection(
                startIndex: best[0].index - 1, endIndex: best.last!.index,
                preferredShiftRows: median(best.map { abs($0.estimate.rows) })
            ), comparisons: comparisons
        )
    }

    private static func distance(_ edges: [Edge]) -> Int { edges.reduce(0) { $0 + abs($1.estimate.rows) } }
    private static func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }
}

enum ScrollSequenceSelector {
    private struct Edge {
        let currentIndex: Int
        let estimate: ShiftEstimate
    }

    /// Finds the sustained vertical-scroll portion of a screen recording.
    /// Frames captured while the broadcast sheet closes, while the user switches
    /// apps, and after scrolling stops are deliberately left outside the result.
    static func select(from frames: [GrayFrame]) -> ScrollSequenceSelection? {
        analyze(frames: frames)?.selection
    }

    static func analyze(frames: [GrayFrame]) -> ScrollSequenceAnalysis? {
        guard frames.count >= 3 else { return nil }

        // Both selection passes score exactly the same adjacent images. Retain
        // their candidate scores and only reapply the continuity preference.
        var comparisons = [ShiftComparison?](repeating: nil, count: frames.count)
        for index in 1..<frames.count {
            guard OverlapEstimator.meanAbsoluteDifference(frames[index - 1], frames[index]) >= 2.6 else {
                continue
            }
            comparisons[index] = OverlapEstimator.compare(from: frames[index - 1], to: frames[index])
        }
        let rawEdges = motionEdges(in: comparisons, preferredShiftRows: nil)
        guard rawEdges.count >= 2 else { return nil }
        let rawPreferred = median(rawEdges.map { $0.estimate.rows })
        let stabilizedEdges = motionEdges(in: comparisons, preferredShiftRows: rawPreferred)
        guard stabilizedEdges.count >= 2 else { return nil }

        let preferred = median(stabilizedEdges.map { $0.estimate.rows })
        let minimumCompatible = max(1, preferred / 4)
        let maximumCompatible = max(minimumCompatible + 1, preferred * 4)
        let compatible = stabilizedEdges.filter {
            $0.estimate.rows >= minimumCompatible && $0.estimate.rows <= maximumCompatible
        }
        guard compatible.count >= 2 else { return nil }

        // At the capture cadence, six missing edges are roughly 1.5 seconds.
        // That tolerates finger repositioning and a dynamic ad frame, while still
        // separating an app-switch animation from the real scrolling session.
        let maximumGap = 7
        var clusters: [[Edge]] = []
        for edge in compatible {
            if let last = clusters.last?.last,
               edge.currentIndex - last.currentIndex <= maximumGap {
                clusters[clusters.count - 1].append(edge)
            } else {
                clusters.append([edge])
            }
        }

        guard var best = clusters
            .filter({ $0.count >= 2 })
            .max(by: { clusterRank($0) < clusterRank($1) }) else {
            return nil
        }

        // A single vertical-looking transition frame can occur while changing
        // apps. Do not let that weak prelude become the first image of the result.
        while best.count >= 3 {
            let first = best[0]
            let second = best[1]
            let remainingMedian = median(best.dropFirst().map { $0.estimate.rows })
            let deviation = abs(first.estimate.rows - remainingMedian)
            let weakPrelude = second.currentIndex - first.currentIndex > 3
                || deviation > max(4, remainingMedian)
            if weakPrelude {
                best.removeFirst()
            } else {
                break
            }
        }

        guard let first = best.first, let last = best.last else { return nil }
        return ScrollSequenceAnalysis(
            selection: ScrollSequenceSelection(
                startIndex: max(0, first.currentIndex - 1),
                endIndex: last.currentIndex,
                preferredShiftRows: median(best.map { $0.estimate.rows })
            ),
            comparisons: comparisons
        )
    }

    private static func motionEdges(
        in comparisons: [ShiftComparison?],
        preferredShiftRows: Int?
    ) -> [Edge] {
        var result: [Edge] = []
        for currentIndex in 1..<comparisons.count {
            guard let estimate = comparisons[currentIndex]?.estimate(
                    preferredShiftRows: preferredShiftRows
                  ) else { continue }
            result.append(Edge(currentIndex: currentIndex, estimate: estimate))
        }
        return result
    }

    private static func clusterRank(_ cluster: [Edge]) -> Double {
        let supportedDistance = cluster.reduce(0.0) {
            $0 + Double($1.estimate.rows) * (0.65 + $1.estimate.confidence)
        }
        return Double(cluster.count) * 10_000 + supportedDistance
    }

    private static func median<S: Sequence>(_ values: S) -> Int where S.Element == Int {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

enum OverlapEstimator {
    static func compareVertical(from previous: GrayFrame, to current: GrayFrame) -> VerticalShiftComparison {
        VerticalShiftComparison(
            downward: compare(from: previous, to: current),
            upward: compare(from: current, to: previous)
        )
    }

    static func estimateVerticalShift(from previous: GrayFrame, to current: GrayFrame) -> ShiftEstimate? {
        compareVertical(from: previous, to: current).estimate()
    }

    static func refineVerticalShift(
        from previous: GrayFrame, to current: GrayFrame,
        around estimatedRows: Int, searchRadius: Int
    ) -> ShiftEstimate? {
        if estimatedRows > 0 {
            return refineDownwardShift(from: previous, to: current, around: estimatedRows, searchRadius: searchRadius)
        }
        guard estimatedRows < 0,
              let result = refineDownwardShift(
                from: current, to: previous, around: -estimatedRows, searchRadius: searchRadius
              ) else { return nil }
        return ShiftEstimate(rows: -result.rows, score: result.score, confidence: result.confidence)
    }

    static func estimateDownwardShift(
        from previous: GrayFrame,
        to current: GrayFrame,
        maximumShiftRatio: Double = 0.78,
        preferredShiftRows: Int? = nil
    ) -> ShiftEstimate? {
        compare(from: previous, to: current, maximumShiftRatio: maximumShiftRatio)?
            .estimate(preferredShiftRows: preferredShiftRows)
    }

    static func compare(
        from previous: GrayFrame,
        to current: GrayFrame,
        maximumShiftRatio: Double = 0.78
    ) -> ShiftComparison? {
        guard previous.width == current.width,
              previous.height == current.height,
              previous.width >= 8,
              previous.height >= 16 else { return nil }

        let minimumShift = max(1, previous.height / 120)
        let maximumShift = min(
            previous.height - 8,
            max(minimumShift, Int(Double(previous.height) * maximumShiftRatio))
        )

        var candidates: [(shift: Int, score: Double)] = []
        candidates.reserveCapacity(maximumShift - minimumShift + 1)

        for shift in minimumShift...maximumShift {
            let score = comparisonScore(
                previous: previous,
                current: current,
                shift: shift
            )
            if score.isFinite {
                candidates.append((shift, score))
            }
        }

        return ShiftComparison(candidates: candidates, frameHeight: previous.height)
    }

    /// Refines a coarse scroll estimate in a narrow window. Callers can supply
    /// frames that retain the source image's full vertical resolution while
    /// reducing only the horizontal resolution. This removes the several-pixel
    /// rounding error introduced by the fast aspect-ratio thumbnail pass.
    static func refineDownwardShift(
        from previous: GrayFrame,
        to current: GrayFrame,
        around estimatedRows: Int,
        searchRadius: Int
    ) -> ShiftEstimate? {
        guard previous.width == current.width,
              previous.height == current.height,
              previous.width >= 8,
              previous.height >= 16,
              estimatedRows > 0,
              searchRadius >= 0 else { return nil }

        let minimumShift = max(1, estimatedRows - searchRadius)
        let maximumShift = min(previous.height - 8, estimatedRows + searchRadius)
        guard minimumShift <= maximumShift else { return nil }

        var candidates: [(shift: Int, score: Double)] = []
        candidates.reserveCapacity(maximumShift - minimumShift + 1)
        for shift in minimumShift...maximumShift {
            let score = refinementScore(
                previous: previous,
                current: current,
                shift: shift
            )
            if score.isFinite {
                candidates.append((shift, score))
            }
        }

        return ShiftComparison(candidates: candidates, frameHeight: previous.height)
            .estimate()
    }

    /// A narrow fine-alignment pass does not need the exhaustive scorer used
    /// to discover an unknown scroll distance. Sample a distributed grid once
    /// per candidate, retain only textured tiles that clearly moved, and use a
    /// robust consensus across them. On full-height iPhone frames this cuts the
    /// fine pass by roughly an order of magnitude while preserving one-row
    /// vertical accuracy around text baselines.
    private static func refinementScore(
        previous: GrayFrame,
        current: GrayFrame,
        shift: Int
    ) -> Double {
        let overlapHeight = previous.height - shift
        guard overlapHeight >= 24 else { return .infinity }

        let tileWidth = max(8, previous.width / 6)
        let tileHeight = max(24, min(64, overlapHeight / 10))
        let horizontalStride = max(2, previous.width / 24)
        let verticalStride = overlapHeight > 240 ? 2 : 1
        var movingTileScores: [Double] = []
        var comparableTileCount = 0

        for top in stride(from: 1, to: overlapHeight - 1, by: tileHeight) {
            let bottom = min(overlapHeight - 1, top + tileHeight)
            guard bottom - top >= 8 else { continue }

            for left in stride(from: 1, to: previous.width - 1, by: tileWidth) {
                let right = min(previous.width - 1, left + tileWidth)
                guard right - left >= 4 else { continue }

                var movedIntensityDifference = 0.0
                var movedEdgeDifference = 0.0
                var stationaryIntensityDifference = 0.0
                var stationaryEdgeDifference = 0.0
                var sampleCount = 0
                var texturedSamples = 0

                for y in stride(from: top, to: bottom, by: verticalStride) {
                    let previousY = y + shift
                    for x in stride(from: left, to: right, by: horizontalStride) {
                        let oldValue = Int(previous[x, previousY])
                        let stationaryValue = Int(previous[x, y])
                        let newValue = Int(current[x, y])
                        let oldEdge = edgeStrength(previous, x: x, y: previousY)
                        let stationaryEdge = edgeStrength(previous, x: x, y: y)
                        let newEdge = edgeStrength(current, x: x, y: y)

                        movedIntensityDifference += Double(abs(oldValue - newValue))
                        movedEdgeDifference += Double(abs(oldEdge - newEdge))
                        stationaryIntensityDifference += Double(abs(stationaryValue - newValue))
                        stationaryEdgeDifference += Double(abs(stationaryEdge - newEdge))
                        sampleCount += 1
                        if max(oldEdge, newEdge) >= 12 { texturedSamples += 1 }
                    }
                }

                guard sampleCount > 0,
                      texturedSamples >= max(3, sampleCount / 40) else { continue }
                comparableTileCount += 1
                let moved = (
                    movedIntensityDifference / Double(sampleCount) * 0.72
                ) + (
                    movedEdgeDifference / Double(sampleCount) * 0.28
                )
                let stationary = (
                    stationaryIntensityDifference / Double(sampleCount) * 0.72
                ) + (
                    stationaryEdgeDifference / Double(sampleCount) * 0.28
                )

                // Viewport-fixed controls match at zero movement; animated
                // media may match neither position. Only tiles that distinctly
                // support this displacement get a vote.
                let improvement = stationary - moved
                if improvement >= max(1.4, stationary * 0.10) {
                    movingTileScores.append(moved)
                }
            }
        }

        guard comparableTileCount >= 6,
              movingTileScores.count >= 4 else { return .infinity }
        let supportRatio = Double(movingTileScores.count) / Double(comparableTileCount)
        guard supportRatio >= 0.24 else { return .infinity }
        movingTileScores.sort()

        let keptCount = max(4, Int(ceil(Double(movingTileScores.count) * 0.78)))
        let kept = movingTileScores.prefix(keptCount)
        let mean = kept.reduce(0, +) / Double(keptCount)
        let median = kept[kept.index(kept.startIndex, offsetBy: keptCount / 2)]
        let weakSupportPenalty = max(0, 0.45 - supportRatio) * 10
        return (mean * 0.68) + (median * 0.32) + weakSupportPenalty
    }

    fileprivate static func chooseEstimate(
        from comparison: ShiftComparison,
        preferredShiftRows: Int?
    ) -> ShiftEstimate? {
        let candidates = comparison.candidates
        guard let rawBest = candidates.min(by: { $0.score < $1.score }) else {
            return nil
        }
        let best: (shift: Int, score: Double)
        if let preferredShiftRows, preferredShiftRows > 0 {
            let preferred = Double(preferredShiftRows)
            best = candidates.min { lhs, rhs in
                adjustedScore(lhs, preferred: preferred)
                    < adjustedScore(rhs, preferred: preferred)
            } ?? rawBest
        } else {
            best = rawBest
        }

        let separatedScores = candidates
            .filter { abs($0.shift - best.shift) > max(2, comparison.frameHeight / 80) }
            .map(\.score)
        let runnerUp = separatedScores.min() ?? best.score + 1
        let relativeGap = max(0, runnerUp - best.score) / max(runnerUp, 0.001)
        let absoluteQuality = max(0, min(1, 1 - (best.score / 38)))
        let confidence = min(1, (relativeGap * 0.55) + (absoluteQuality * 0.45))

        guard best.score < 45, confidence >= 0.18 else {
            return nil
        }

        return ShiftEstimate(rows: best.shift, score: best.score, confidence: confidence)
    }

    private static func adjustedScore(
        _ candidate: (shift: Int, score: Double),
        preferred: Double
    ) -> Double {
        let deviation = abs(Double(candidate.shift) - preferred) / max(preferred, 1)
        let continuityPenalty = min(0.35, deviation * 0.18)
        return candidate.score * (1 + continuityPenalty)
    }

    static func meanAbsoluteDifference(_ lhs: GrayFrame, _ rhs: GrayFrame) -> Double {
        guard lhs.width == rhs.width,
              lhs.height == rhs.height,
              !lhs.pixels.isEmpty else { return .infinity }

        var total = 0
        for index in lhs.pixels.indices {
            total += abs(Int(lhs.pixels[index]) - Int(rhs.pixels[index]))
        }
        return Double(total) / Double(lhs.pixels.count)
    }

    private static func comparisonScore(
        previous: GrayFrame,
        current: GrayFrame,
        shift: Int
    ) -> Double {
        let regional = regionConsensusScore(
            previous: previous,
            current: current,
            shift: shift
        )
        let global = globalComparisonScore(
            previous: previous,
            current: current,
            shift: shift
        )
        guard regional.isFinite, global.isFinite else { return .infinity }

        // Regional consensus survives dynamic ad/video areas; the global term
        // prevents repeated product-card patterns from winning at the wrong offset.
        return (regional * 0.80) + (global * 0.20)
    }

    private static func regionConsensusScore(
        previous: GrayFrame,
        current: GrayFrame,
        shift: Int
    ) -> Double {
        let overlapHeight = previous.height - shift
        guard overlapHeight >= 8 else { return .infinity }

        let tileWidth = max(8, min(14, previous.width / 4))
        let tileHeight = max(8, min(14, overlapHeight / 5))
        var movingTileScores: [Double] = []
        var comparableTileCount = 0

        for top in stride(from: 1, to: overlapHeight - 1, by: tileHeight) {
            let bottom = min(overlapHeight - 1, top + tileHeight)
            guard bottom - top >= 4 else { continue }

            for left in stride(from: 1, to: previous.width - 1, by: tileWidth) {
                let right = min(previous.width - 1, left + tileWidth)
                guard right - left >= 4 else { continue }

                var allPixelDifference = 0.0
                var salientIntensityDifference = 0.0
                var salientEdgeDifference = 0.0
                var stationaryPixelDifference = 0.0
                var stationaryEdgeDifference = 0.0
                var sampleCount = 0
                var salientCount = 0

                for y in top..<bottom {
                    let previousY = y + shift
                    for x in left..<right {
                        let oldValue = Int(previous[x, previousY])
                        let stationaryValue = Int(previous[x, y])
                        let newValue = Int(current[x, y])
                        let oldEdge = edgeStrength(previous, x: x, y: previousY)
                        let stationaryEdge = edgeStrength(previous, x: x, y: y)
                        let newEdge = edgeStrength(current, x: x, y: y)
                        let difference = abs(oldValue - newValue)

                        allPixelDifference += Double(difference)
                        stationaryPixelDifference += Double(abs(stationaryValue - newValue))
                        stationaryEdgeDifference += Double(abs(stationaryEdge - newEdge))
                        sampleCount += 1

                        if max(oldEdge, newEdge) >= 14 {
                            salientIntensityDifference += Double(difference)
                            salientEdgeDifference += Double(abs(oldEdge - newEdge))
                            salientCount += 1
                        }
                    }
                }

                guard sampleCount > 0,
                      salientCount >= max(3, sampleCount / 50) else { continue }

                let allPixels = allPixelDifference / Double(sampleCount)
                let intensity = salientIntensityDifference / Double(salientCount)
                let edges = salientEdgeDifference / Double(salientCount)
                let candidateScore = (allPixels * 0.62) + (intensity * 0.23) + (edges * 0.15)
                let stationaryScore = (
                    stationaryPixelDifference / Double(sampleCount) * 0.82
                ) + (
                    stationaryEdgeDifference / Double(sampleCount) * 0.18
                )
                comparableTileCount += 1

                // A viewport-fixed coupon strip or tab bar matches best at the
                // same screen position. It is not evidence of page movement and
                // must not vote for a tiny false scroll distance.
                let improvement = stationaryScore - candidateScore
                if improvement >= max(1.8, stationaryScore * 0.12) {
                    movingTileScores.append(candidateScore)
                }
            }
        }

        guard comparableTileCount >= 6,
              movingTileScores.count >= 4 else { return .infinity }
        let supportRatio = Double(movingTileScores.count) / Double(comparableTileCount)
        guard supportRatio >= 0.28 else { return .infinity }
        movingTileScores.sort()

        // Ads, videos, carousels, and timers can change while the page scrolls.
        // Keep the strongest three quarters of the tiles that actually support
        // this displacement, without allowing a tiny fixed region to dominate.
        let keptCount = max(4, Int(ceil(Double(movingTileScores.count) * 0.75)))
        let kept = movingTileScores.prefix(keptCount)
        let mean = kept.reduce(0, +) / Double(keptCount)
        let median = kept[kept.index(kept.startIndex, offsetBy: keptCount / 2)]
        let overlapRatio = Double(overlapHeight) / Double(previous.height)
        let smallOverlapPenalty = max(0, 0.3 - overlapRatio) * 8
        let weakSupportPenalty = max(0, 0.45 - supportRatio) * 12
        return (mean * 0.68) + (median * 0.32) + smallOverlapPenalty + weakSupportPenalty
    }

    private static func globalComparisonScore(
        previous: GrayFrame,
        current: GrayFrame,
        shift: Int
    ) -> Double {
        let overlapHeight = previous.height - shift
        guard overlapHeight >= 8 else { return .infinity }

        let horizontalStride = previous.width > 48 ? 2 : 1
        let verticalStride = overlapHeight > 96 ? 2 : 1
        var intensityDifference = 0.0
        var edgeDifference = 0.0
        var allPixelDifference = 0.0
        var salientSamples = 0
        var allSamples = 0

        for y in stride(from: 1, to: overlapHeight - 1, by: verticalStride) {
            let previousY = y + shift
            for x in stride(from: 1, to: previous.width - 1, by: horizontalStride) {
                let oldValue = Int(previous[x, previousY])
                let newValue = Int(current[x, y])
                let oldEdge = edgeStrength(previous, x: x, y: previousY)
                let newEdge = edgeStrength(current, x: x, y: y)
                let difference = abs(oldValue - newValue)
                allPixelDifference += Double(difference)
                allSamples += 1

                if max(oldEdge, newEdge) >= 14 {
                    intensityDifference += Double(difference)
                    edgeDifference += Double(abs(oldEdge - newEdge))
                    salientSamples += 1
                }
            }
        }

        guard allSamples > 0,
              salientSamples >= max(12, allSamples / 80) else {
            return .infinity
        }

        let allPixels = allPixelDifference / Double(allSamples)
        let intensity = intensityDifference / Double(salientSamples)
        let edges = edgeDifference / Double(salientSamples)
        let texturePenalty = salientSamples < allSamples / 30 ? 8.0 : 0.0
        return (allPixels * 0.72) + (intensity * 0.18) + (edges * 0.10) + texturePenalty
    }

    private static func edgeStrength(_ frame: GrayFrame, x: Int, y: Int) -> Int {
        Int(frame.edges[y * frame.width + x])
    }
}
