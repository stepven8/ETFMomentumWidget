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

@Test func backtestHistoricalProviderFallsBackToDailyBarWhenMinuteDataIsMissing() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ETFMomentumBacktestTests-\(UUID().uuidString)", isDirectory: true)
    let store = try BacktestSQLiteStore(directory: directory)
    let dataProvider = EasyTDXBacktestDataProvider(store: store)
    let etf = ETF(code: "159919.XSHE", name: "沪深300ETF")
    let calendar = shanghaiCalendar()
    let januaryDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 14)))
    let januaryDaily = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)))
    let februaryMinute = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 4, hour: 9, minute: 32)))

    try store.saveBars([
        KLine(date: januaryDaily, open: 4.9, close: 5.1, high: 5.2, low: 4.8, volume: 1_000),
        KLine(date: februaryMinute, open: 5.2, close: 5.3, high: 5.3, low: 5.2, volume: 2_000)
    ], symbol: etf.code, period: "DAILY")
    try store.saveBars([
        KLine(date: februaryMinute, open: 5.2, close: 5.3, high: 5.3, low: 5.2, volume: 2_000)
    ], symbol: etf.code, period: "1MIN")

    let historical = BacktestHistoricalProvider(dataProvider: dataProvider, currentDate: januaryDay, period: .oneMinute)
    let quote = try await historical.quote(for: etf)
    let latest = try await dataProvider.latestBar(etf: etf, atOrBefore: januaryDay, period: .oneMinute)

    #expect(quote.lastPrice == 5.1)
    #expect(latest?.close == 5.1)
}

private func shanghaiCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    return calendar
}
