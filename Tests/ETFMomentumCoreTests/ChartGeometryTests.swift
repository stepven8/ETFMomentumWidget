import CoreGraphics
import Testing
@testable import ETFMomentumCore

@Test func hoverIndexClampsToChartBounds() {
    let plotRect = CGRect(x: 0, y: 0, width: 100, height: 80)

    #expect(ChartGeometry.indexForX(-20, plotRect: plotRect, count: 10) == 0)
    #expect(ChartGeometry.indexForX(0, plotRect: plotRect, count: 10) == 0)
    #expect(ChartGeometry.indexForX(99.9, plotRect: plotRect, count: 10) == 9)
    #expect(ChartGeometry.indexForX(140, plotRect: plotRect, count: 10) == 9)
}

@Test func hoverIndexMapsMiddlePositionsToExpectedCandle() {
    let plotRect = CGRect(x: 0, y: 0, width: 100, height: 80)

    #expect(ChartGeometry.indexForX(10, plotRect: plotRect, count: 10) == 1)
    #expect(ChartGeometry.indexForX(49.9, plotRect: plotRect, count: 10) == 4)
    #expect(ChartGeometry.indexForX(50, plotRect: plotRect, count: 10) == 5)
}

@Test func hoverIndexHandlesEmptyAndSingleCandleData() {
    let plotRect = CGRect(x: 0, y: 0, width: 100, height: 80)

    #expect(ChartGeometry.indexForX(50, plotRect: plotRect, count: 0) == nil)
    #expect(ChartGeometry.indexForX(-100, plotRect: plotRect, count: 1) == 0)
    #expect(ChartGeometry.indexForX(100, plotRect: plotRect, count: 1) == 0)
}

@Test func xForIndexReturnsCandleCentersAndClamps() {
    let plotRect = CGRect(x: 0, y: 0, width: 100, height: 80)

    #expect(ChartGeometry.xForIndex(0, plotRect: plotRect, count: 10) == 5)
    #expect(ChartGeometry.xForIndex(9, plotRect: plotRect, count: 10) == 95)
    #expect(ChartGeometry.xForIndex(-5, plotRect: plotRect, count: 10) == 5)
    #expect(ChartGeometry.xForIndex(99, plotRect: plotRect, count: 10) == 95)
    #expect(ChartGeometry.xForIndex(0, plotRect: plotRect, count: 0) == nil)
}

@Test func dateTicksStayUniqueAndInsideDataBounds() {
    let ticks = ChartGeometry.dateTickIndices(count: 260, plotWidth: 700)

    #expect(ticks.count >= 5)
    #expect(ticks.count <= 7)
    #expect(ticks == Array(Set(ticks)).sorted())
    #expect(ticks.first == 0)
    #expect(ticks.last == 259)
}

@Test func plotRectReservesAxesWithoutCollapsing() {
    let rect = ChartGeometry.plotRect(size: CGSize(width: 400, height: 320), reservesDateAxis: true)

    #expect(rect.width == 346)
    #expect(rect.height == 296)
}

@Test func plotRectCanUseFullWidthForSparklines() {
    let rect = ChartGeometry.plotRect(size: CGSize(width: 48, height: 22), reservesDateAxis: false, reservesPriceAxis: false)

    #expect(rect.width == 48)
    #expect(rect.height == 22)
}

@Test func macdRangeUsesAllSeriesOnOneSymmetricAxis() {
    let range = ChartGeometry.symmetricRange(values: [-0.12, 0.08, 0.02, 0.15, -0.04, 0.03])

    #expect(range?.min == -0.15)
    #expect(range?.max == 0.15)
}

@Test func symmetricRangeRejectsEmptyOrFlatZeroValues() {
    #expect(ChartGeometry.symmetricRange(values: []) == nil)
    #expect(ChartGeometry.symmetricRange(values: [0, 0, 0]) == nil)
}

@Test func pannedStartMovesVisibleWindowWithDragDirection() {
    #expect(ChartGeometry.pannedStart(currentStart: 100, visibleCount: 50, totalCount: 260, translationX: -70, plotWidth: 700) == 105)
    #expect(ChartGeometry.pannedStart(currentStart: 100, visibleCount: 50, totalCount: 260, translationX: 70, plotWidth: 700) == 95)
}

@Test func pannedStartClampsToBothEnds() {
    #expect(ChartGeometry.pannedStart(currentStart: 3, visibleCount: 50, totalCount: 260, translationX: 700, plotWidth: 700) == 0)
    #expect(ChartGeometry.pannedStart(currentStart: 205, visibleCount: 50, totalCount: 260, translationX: -700, plotWidth: 700) == 210)
}

@Test func pannedStartDoesNotMoveWhenFullyZoomedOut() {
    #expect(ChartGeometry.pannedStart(currentStart: 0, visibleCount: 260, totalCount: 260, translationX: -700, plotWidth: 700) == 0)
}
