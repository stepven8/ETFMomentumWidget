import CoreGraphics

public enum ChartGeometry {
    public static let priceAxisWidth: CGFloat = 54
    public static let dateAxisHeight: CGFloat = 24

    public static func plotRect(size: CGSize, reservesDateAxis: Bool, reservesPriceAxis: Bool = true) -> CGRect {
        let height = reservesDateAxis ? size.height - dateAxisHeight : size.height
        let width = reservesPriceAxis ? size.width - priceAxisWidth : size.width
        return CGRect(
            x: 0,
            y: 0,
            width: max(width, 1),
            height: max(height, 1)
        )
    }

    public static func indexForX(_ x: CGFloat, plotRect: CGRect, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard count > 1 else { return 0 }
        let candleWidth = max(plotRect.width / CGFloat(count), 1)
        let clampedX = min(max(x, plotRect.minX), plotRect.maxX - 0.001)
        let rawIndex = Int((clampedX - plotRect.minX) / candleWidth)
        return min(max(rawIndex, 0), count - 1)
    }

    public static func xForIndex(_ index: Int, plotRect: CGRect, count: Int) -> CGFloat? {
        guard count > 0 else { return nil }
        let clampedIndex = min(max(index, 0), count - 1)
        let candleWidth = plotRect.width / CGFloat(max(count, 1))
        return plotRect.minX + CGFloat(clampedIndex) * candleWidth + candleWidth / 2
    }

    public static func dateTickIndices(count: Int, plotWidth: CGFloat) -> [Int] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [0] }
        let targetCount = min(max(Int(plotWidth / 120), 5), 7)
        let tickCount = min(targetCount, count)
        let last = count - 1
        let indices = (0..<tickCount).map { tick in
            Int((Double(tick) * Double(last) / Double(tickCount - 1)).rounded())
        }
        return Array(Set(indices)).sorted()
    }

    public static func symmetricRange(values: [Double]) -> (min: Double, max: Double)? {
        guard let low = values.min(), let high = values.max() else { return nil }
        let maxAbs = max(abs(low), abs(high))
        guard maxAbs > 0 else { return nil }
        return (-maxAbs, maxAbs)
    }

    public static func pannedStart(
        currentStart: Int,
        visibleCount: Int,
        totalCount: Int,
        translationX: CGFloat,
        plotWidth: CGFloat
    ) -> Int {
        guard totalCount > 0, visibleCount > 0, visibleCount < totalCount, plotWidth > 0 else {
            return min(max(currentStart, 0), max(totalCount - visibleCount, 0))
        }
        let candleWidth = max(plotWidth / CGFloat(visibleCount), 1)
        let offset = Int((translationX / candleWidth).rounded())
        let maxStart = max(totalCount - visibleCount, 0)
        return min(max(currentStart - offset, 0), maxStart)
    }
}
