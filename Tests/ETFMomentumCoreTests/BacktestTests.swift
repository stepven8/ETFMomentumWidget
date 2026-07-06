import Foundation
import Testing
@testable import ETFMomentumCore

@Test func backtestStorePersistsRunSnapshotAndKeepsBarsAfterDeletingRun() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ETFMomentumBacktestTests-\(UUID().uuidString)", isDirectory: true)
    let store = try BacktestSQLiteStore(directory: directory)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let config = BacktestConfig(name: "fixture", startDate: start, endDate: start.addingTimeInterval(86_400), period: .oneMinute, initialCapital: 100_000)
    let summary = BacktestRunSummary(
        name: config.name,
        startDate: config.startDate,
        endDate: config.endDate,
        period: config.period,
        initialCapital: config.initialCapital,
        benchmarkCode: config.benchmark.code,
        benchmarkName: config.benchmark.name,
        status: .completed,
        totalReturn: 0.12,
        benchmarkReturn: 0.03,
        maxDrawdown: -0.02
    )
    let result = BacktestResult(
        summary: summary,
        strategyConfig: StrategyConfig(lookbackDays: 25, holdingsNum: 1, loss: 0.97),
        backtestConfig: config,
        costConfig: BacktestCostConfig(),
        universe: [ETF(code: "510300.XSHG", name: "沪深300ETF")],
        metrics: BacktestMetrics(totalReturn: 0.12, benchmarkReturn: 0.03, maxDrawdown: -0.02),
        equityCurve: [],
        orders: [],
        trades: [],
        positions: [],
        signals: [],
        logs: ["ok"]
    )
    let bars = [
        KLine(date: start, open: 1, close: 1.01, high: 1.02, low: 0.99, volume: 100, amount: 101)
    ]

    try store.saveBars(bars, symbol: "510300.XSHG", period: "1MIN")
    try store.save(result: result)

    #expect(try store.summaries().count == 1)
    let loaded = try store.result(id: summary.id)
    #expect(loaded.strategyConfig.loss == 0.97)
    #expect(loaded.summary.totalReturn == 0.12)

    try store.deleteRun(id: summary.id)
    #expect(try store.summaries().isEmpty)
    #expect(try store.bars(symbol: "510300.XSHG", period: "1MIN", start: start.addingTimeInterval(-1), end: start.addingTimeInterval(1)).count == 1)
}
