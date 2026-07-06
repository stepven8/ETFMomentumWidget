import Foundation
import Testing
@testable import ETFMomentumCore

@Test func weightedRegressionMatchesKnownFixture() {
    let prices = (0...25).map { Foundation.exp(Foundation.log(1.0) + 0.01 * Double($0)) }
    let scored = MomentumMath.score(priceSeries: prices, lookbackDays: 25)
    #expect(abs(scored.annRet - (Foundation.exp(0.01 * 250) - 1)) < 1e-10)
    #expect(abs(scored.r2 - 1) < 1e-10)
    #expect(abs(scored.score - scored.annRet) < 1e-10)
}

@Test func movingAverageUsesTrailingCloseWindow() {
    let lines = (1...6).map { value in
        KLine(date: fixtureNow, open: Double(value), close: Double(value), high: Double(value), low: Double(value), volume: 1_000)
    }
    let ma3 = MomentumMath.movingAverage(for: lines, period: 3)

    #expect(ma3[0] == nil)
    #expect(ma3[1] == nil)
    #expect(ma3[2] == 2)
    #expect(ma3[3] == 3)
    #expect(ma3[5] == 5)
}

@Test func dailyPctChangeIsCalculatedFromPreviousClose() {
    let lines = [
        KLine(date: fixtureNow, open: 10, close: 10, high: 10, low: 10, volume: 1_000),
        KLine(date: fixtureNow, open: 10, close: 11, high: 11, low: 10, volume: 1_000),
        KLine(date: fixtureNow, open: 11, close: 10.45, high: 11, low: 10.4, volume: 1_000)
    ]

    let updated = MomentumMath.withDailyPctChange(lines)

    #expect(updated[0].pctChange == 0)
    #expect(abs(updated[1].pctChange - 10) < 0.0000000001)
    #expect(abs(updated[2].pctChange - -5) < 0.0000000001)
}

@Test func rankingEnginePreservesSourceOrderingAndFilters() async {
    let config = StrategyConfig(
        lookbackDays: 25,
        loss: 0.97,
        enableVolumeCheck: true,
        volumeLookback: 5,
        volumeThreshold: 2,
        volumeReturnLimit: 1,
        useShortMomentumFilter: true,
        shortLookbackDays: 10,
        shortMomentumThreshold: 0,
        enableProfitProtection: true,
        profitProtectionLookback: 1,
        profitProtectionThreshold: 0.05,
        enablePremiumFilter: true,
        premiumThreshold: 0.20
    )
    let provider = FixtureProvider()
    let engine = RankingEngine(config: config, provider: provider, now: { fixtureNow })
    let snapshot = await engine.rank(etfs: FixtureProvider.etfs, includeFiltered: true)
    let included = snapshot.included

    #expect(included.map(\.etf.code) == ["510300.XSHG", "159915.XSHE"])
    #expect(included[0].score > included[1].score)
    #expect(snapshot.metrics.first { $0.etf.code == "588080.XSHG" }?.filterReason == .shortMomentumWeak)
    #expect(snapshot.metrics.first { $0.etf.code == "513100.XSHG" }?.filterReason == .premiumExceeded)
    #expect(snapshot.metrics.first { $0.etf.code == "510500.XSHG" }?.filterReason == .recentLossExceeded)
}

@Test func scoreThresholdUsesStrictInequality() async {
    let provider = FixtureProvider()
    let baseEngine = RankingEngine(config: StrategyConfig(enableVolumeCheck: false, useShortMomentumFilter: false, enableProfitProtection: false, enablePremiumFilter: false), provider: provider, now: { fixtureNow })
    let metric = await baseEngine.calculate(etf: FixtureProvider.etfs[0])
    var config = StrategyConfig(enableVolumeCheck: false, useShortMomentumFilter: false, enableProfitProtection: false, enablePremiumFilter: false)
    config.minScoreThreshold = metric.score
    config.maxScoreThreshold = 100
    let strictMin = await RankingEngine(config: config, provider: provider, now: { fixtureNow }).calculate(etf: FixtureProvider.etfs[0])
    #expect(strictMin.filterReason == .scoreOutOfRange)

    config.minScoreThreshold = -100
    config.maxScoreThreshold = metric.score
    let strictMax = await RankingEngine(config: config, provider: provider, now: { fixtureNow }).calculate(etf: FixtureProvider.etfs[0])
    #expect(strictMax.filterReason == .scoreOutOfRange)
}

@Test func currentPriceReplacesTodayDailyCloseInsteadOfDuplicatingIt() async {
    let provider = TodayKLineProvider()
    let engine = RankingEngine(
        config: StrategyConfig(maxScoreThreshold: 10_000, enableVolumeCheck: false, useShortMomentumFilter: false, enableProfitProtection: false, enablePremiumFilter: false),
        provider: provider,
        now: { fixtureNow }
    )

    let metric = await engine.calculate(etf: FixtureProvider.etfs[0])

    #expect(metric.filterReason == .included)
    #expect(metric.currentPrice == 13)
    #expect(metric.closes.count == 30)
    #expect(metric.closes.suffix(4).map { Double(round($0 * 1000) / 1000) } == [10, 11, 12, 13])
}

@Test func easyTDXQuoteMapsCLIJSON() async throws {
    let script = try makeEasyTDXScript()
    let provider = EasyTDXProvider(binaryPath: script.path)
    let quote = try await provider.quote(for: ETF(code: "510300.XSHG", name: "沪深300ETF华泰柏瑞"))

    #expect(quote.code == "510300.XSHG")
    #expect(quote.name == "沪深300ETF华泰柏瑞")
    #expect(quote.lastPrice == 4.905)
    #expect(abs(quote.pctChange - 1.1340206185567136) < 0.0000000001)
    #expect(quote.volume == 12345)
    #expect(quote.paused == false)
}

@Test func easyTDXDailyKLinesMapsCLIJSONAndCalculatesPctChange() async throws {
    let script = try makeEasyTDXScript()
    let provider = EasyTDXProvider(binaryPath: script.path)
    let lines = try await provider.dailyKLines(for: ETF(code: "510300.XSHG", name: "沪深300ETF华泰柏瑞"), limit: 3)

    #expect(lines.count == 3)
    #expect(lines[0].open == 4.8)
    #expect(lines[1].close == 4.95)
    #expect(lines[2].volume == 300)
    #expect(lines[2].amount == 3000)
    #expect(abs(lines[1].pctChange - 1.0204081632653061) < 0.0000000001)
    #expect(abs(lines[2].pctChange - -0.9090909090909091) < 0.0000000001)
}

@Test func easyTDXMinuteVolumeSumsTodayOnly() async throws {
    let script = try makeEasyTDXScript()
    let provider = EasyTDXProvider(binaryPath: script.path)
    let now = ISO8601DateFormatter().date(from: "2026-06-05T06:00:00Z")!
    let volume = try await provider.minuteVolumeSumToday(for: ETF(code: "159915.XSHE", name: "创业板ETF易方达"), now: now)

    #expect(volume == 700)
}

@Test func easyTDXThrowsForInvalidJSONAndNonZeroExit() async throws {
    let invalid = try makeExecutableScript(body: """
#!/bin/sh
printf 'not-json'
""")
    let failing = try makeExecutableScript(body: """
#!/bin/sh
echo 'tdx failed' >&2
exit 7
""")
    let etf = ETF(code: "510300.XSHG", name: "沪深300ETF华泰柏瑞")

    await #expect(throws: Error.self) {
        _ = try await EasyTDXProvider(binaryPath: invalid.path).quote(for: etf)
    }
    await #expect(throws: Error.self) {
        _ = try await EasyTDXProvider(binaryPath: failing.path).quote(for: etf)
    }
}

@Test func fallbackMarketDataProviderUsesEasyTDXAfterEarlierProvidersFail() async throws {
    let script = try makeEasyTDXScript()
    let fallback = FallbackMarketDataProvider(providers: [
        AlwaysFailingProvider(),
        EasyTDXProvider(binaryPath: script.path)
    ])
    let etf = ETF(code: "510300.XSHG", name: "沪深300ETF华泰柏瑞")

    let quote = try await fallback.quote(for: etf)
    let lines = try await fallback.dailyKLines(for: etf, limit: 3)

    #expect(quote.lastPrice == 4.905)
    #expect(lines.count == 3)
}

@Test func appStoreRefreshTimesOutInsteadOfHanging() async {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ETFMomentumWidgetTests-\(UUID().uuidString)", isDirectory: true)
    let store = await AppStore(directory: directory)
    let oldSnapshot = RankingSnapshot(generatedAt: fixtureNow, metrics: [
        RankingMetric(etf: FixtureProvider.etfs[0], score: 9, currentPrice: 2.1, filterReason: .included)
    ])
    await MainActor.run {
        store.etfs = [FixtureProvider.etfs[0]]
        try? store.saveSnapshot(oldSnapshot)
    }

    let succeeded = await store.refresh(provider: HangingProvider(), timeoutSeconds: 1)

    #expect(succeeded == false)
    #expect(await store.snapshot?.generatedAt == oldSnapshot.generatedAt)
    #expect(await store.snapshot?.included.first?.score == 9)
}

@Test func appStoreRefreshMessageUsesSnapshotGeneratedAt() async {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ETFMomentumWidgetTests-\(UUID().uuidString)", isDirectory: true)
    let store = await AppStore(directory: directory)
    await MainActor.run {
        store.etfs = [FixtureProvider.etfs[0]]
    }

    let succeeded = await store.refresh(provider: FixtureProvider())
    let snapshotDate = await store.snapshot?.generatedAt
    let message = await store.refreshMessage

    #expect(succeeded == true)
    #expect(snapshotDate != nil)
    if let snapshotDate {
        #expect(message?.contains(snapshotDate.formatted(date: .omitted, time: .standard)) == true)
    }
    #expect(await store.isRefreshing == false)
}

@Test func refreshFailureDoesNotOverwriteExistingSnapshot() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ETFMomentumWidgetTests-\(UUID().uuidString)", isDirectory: true)
    let store = await AppStore(directory: directory)
    let oldSnapshot = RankingSnapshot(generatedAt: fixtureNow, metrics: [
        RankingMetric(etf: FixtureProvider.etfs[0], score: 8, currentPrice: 2.2, pctChange: 1.1, filterReason: .included)
    ])

    try await MainActor.run {
        store.etfs = [FixtureProvider.etfs[0]]
        try store.saveSnapshot(oldSnapshot)
    }

    let succeeded = await store.refresh(provider: AlwaysFailingProvider(), timeoutSeconds: 1)
    let cached = AppStore.cachedSnapshot(directory: directory)

    #expect(succeeded == false)
    #expect(await store.snapshot?.generatedAt == oldSnapshot.generatedAt)
    #expect(await store.snapshot?.included.first?.score == 8)
    #expect(cached?.generatedAt == oldSnapshot.generatedAt)
    #expect(cached?.included.first?.score == 8)
}

@Test func incompleteDailyDataRefreshDoesNotOverwriteExistingSnapshot() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ETFMomentumWidgetTests-\(UUID().uuidString)", isDirectory: true)
    let store = await AppStore(directory: directory)
    let oldSnapshot = RankingSnapshot(generatedAt: fixtureNow, metrics: [
        RankingMetric(etf: FixtureProvider.etfs[0], score: 7, currentPrice: 2.3, pctChange: 1.2, filterReason: .included)
    ])

    try await MainActor.run {
        store.etfs = [FixtureProvider.etfs[0]]
        try store.saveSnapshot(oldSnapshot)
    }

    let succeeded = await store.refresh(provider: IncompleteDailyDataProvider(), timeoutSeconds: 1)

    #expect(succeeded == false)
    #expect(await store.snapshot?.generatedAt == oldSnapshot.generatedAt)
    #expect(await store.snapshot?.included.first?.score == 7)
}

@Test func savingSettingsRefreshFailureKeepsExistingSnapshotUntilSuccessfulRefresh() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ETFMomentumWidgetTests-\(UUID().uuidString)", isDirectory: true)
    let store = await AppStore(directory: directory)
    let oldSnapshot = RankingSnapshot(generatedAt: fixtureNow, metrics: [
        RankingMetric(etf: FixtureProvider.etfs[0], score: 6, currentPrice: 2.4, pctChange: 1.3, filterReason: .included)
    ])

    try await MainActor.run {
        store.etfs = [FixtureProvider.etfs[0], FixtureProvider.etfs[1]]
        try store.saveSnapshot(oldSnapshot)
        store.config.lookbackDays = 30
        try store.saveConfigAndPool(applyToSnapshot: false)
    }

    let succeeded = await store.refresh(provider: AlwaysFailingProvider(), timeoutSeconds: 1)

    #expect(succeeded == false)
    #expect(await store.snapshot?.generatedAt == oldSnapshot.generatedAt)
    #expect(await store.snapshot?.included.first?.score == 6)
    #expect(await store.snapshot?.metrics.count == 1)
}

@Test func klineCachePersistsDownloadedDataAndIgnoresEmptyWrites() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ETFMomentumWidgetTests-\(UUID().uuidString)", isDirectory: true)
    let cache = KLineCache(directory: directory)
    let etf = FixtureProvider.etfs[0]
    let lines = [
        KLine(date: fixtureNow, open: 1, close: 1.1, high: 1.2, low: 0.9, volume: 1_000)
    ]

    try cache.save(lines, etf: etf, limit: 260)
    try cache.save([], etf: etf, limit: 260)

    let cached = cache.load(etf: etf, limit: 260)
    #expect(cached == lines)
}

@Test func savingDisabledETFImmediatelyUpdatesCachedRanking() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ETFMomentumWidgetTests-\(UUID().uuidString)", isDirectory: true)
    let store = await AppStore(directory: directory)
    let enabled = ETF(code: "510300.XSHG", name: "沪深300ETF华泰柏瑞")
    let disabled = ETF(code: "159915.XSHE", name: "创业板ETF易方达", enabled: false)

    try await MainActor.run {
        store.etfs = [enabled, disabled]
        try store.saveSnapshot(RankingSnapshot(metrics: [
            RankingMetric(etf: enabled, score: 2, filterReason: .included),
            RankingMetric(etf: ETF(code: disabled.code, name: disabled.name), score: 3, filterReason: .included)
        ]))
        try store.saveConfigAndPool()
    }

    let snapshot = await store.snapshot
    #expect(snapshot?.included.map(\.etf.code) == ["510300.XSHG"])
    #expect(snapshot?.metrics.first { $0.etf.code == disabled.code }?.filterReason == .disabled)
}

@Test func disablingETFRemovesStaleRankAndScoreFromSnapshot() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ETFMomentumWidgetTests-\(UUID().uuidString)", isDirectory: true)
    let store = await AppStore(directory: directory)
    let etf = ETF(code: "513880.XSHG", name: "日经225ETF华安", enabled: false)

    try await MainActor.run {
        store.etfs = [etf]
        try store.saveSnapshot(RankingSnapshot(metrics: [
            RankingMetric(etf: ETF(code: etf.code, name: etf.name), annualizedReturns: 3.5, rSquared: 0.6, score: 2.3, currentPrice: 2.153, shortAnnualized: 1.6, pctChange: -2.97, filterReason: .included, closes: [1, 2])
        ]))
        try store.saveConfigAndPool()
    }

    let metric = await store.snapshot?.metrics.first { $0.etf.code == etf.code }
    #expect(metric?.filterReason == .disabled)
    #expect(metric?.score == 0)
    #expect(metric?.currentPrice == 2.153)
    #expect(metric?.pctChange == -2.97)
    #expect(metric?.closes.isEmpty == true)
    #expect(metric?.etf.enabled == false)
}

@Test func disabledETFRefreshesQuoteWithoutRunningStrategyCalculation() async {
    let etf = ETF(code: "513880.XSHG", name: "日经225ETF华安", enabled: false)
    let provider = DisabledQuoteProvider()
    let snapshot = await RankingEngine(config: StrategyConfig(), provider: provider, now: { fixtureNow }).rank(etfs: [etf], includeFiltered: true)

    let metric = snapshot.metrics.first
    #expect(metric?.filterReason == .disabled)
    #expect(metric?.currentPrice == 2.153)
    #expect(metric?.pctChange == -2.97)
    #expect(metric?.score == 0)
    #expect(metric?.closes.isEmpty == true)
    #expect(await provider.dailyKLineCalls() == 0)
}

@Test func reenabledETFWaitsForRefreshInsteadOfShowingCalculationError() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ETFMomentumWidgetTests-\(UUID().uuidString)", isDirectory: true)
    let store = await AppStore(directory: directory)
    let enabled = ETF(code: "513880.XSHG", name: "日经225ETF华安", enabled: true)
    let disabled = ETF(code: "513520.XSHG", name: "日经ETF华夏", enabled: false)

    try await MainActor.run {
        store.etfs = [enabled, disabled]
        try store.saveSnapshot(RankingSnapshot(metrics: [
            RankingMetric(etf: enabled, score: 2, filterReason: .included),
            RankingMetric(etf: disabled, filterReason: .disabled)
        ]))
        store.etfs[1].enabled = true
        try store.saveConfigAndPool()
    }

    let snapshot = await store.snapshot
    #expect(snapshot?.metrics.first { $0.etf.code == disabled.code }?.filterReason == .pendingRefresh)
}

@Test func rankingContinuesWhenOptionalPremiumAndVolumeDataFail() async {
    let config = StrategyConfig(
        enableVolumeCheck: true,
        useShortMomentumFilter: false,
        enableProfitProtection: false,
        enablePremiumFilter: true
    )
    let provider = OptionalDataFailingProvider()
    let metric = await RankingEngine(config: config, provider: provider, now: { fixtureNow }).calculate(etf: FixtureProvider.etfs[0])

    #expect(metric.filterReason == .included)
    #expect(metric.score > 0)
}

private let fixtureNow = ISO8601DateFormatter().date(from: "2026-06-05T06:00:00Z")!

private class FixtureProvider: MarketDataProvider, @unchecked Sendable {
    static let etfs = [
        ETF(code: "510300.XSHG", name: "沪深300ETF华泰柏瑞"),
        ETF(code: "159915.XSHE", name: "创业板ETF易方达"),
        ETF(code: "588080.XSHG", name: "科创50ETF易方达"),
        ETF(code: "513100.XSHG", name: "纳指ETF国泰"),
        ETF(code: "510500.XSHG", name: "中证500ETF南方")
    ]

    func quote(for etf: ETF) async throws -> Quote {
        let prices = try await dailyKLines(for: etf, limit: 45)
        let last = latestPrice(etf: etf, fallback: prices.last?.close ?? 1)
        return Quote(code: etf.code, name: etf.name, lastPrice: last, pctChange: 1.2)
    }

    func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        let slope: Double
        switch etf.code {
        case "510300.XSHG": slope = 0.008
        case "159915.XSHE": slope = 0.004
        case "588080.XSHG": slope = -0.001
        case "513100.XSHG": slope = 0.010
        case "510500.XSHG": slope = 0.007
        default: slope = 0.002
        }
        return makeKLines(days: limit, slope: slope, lossTail: etf.code == "510500.XSHG")
    }

    func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        100
    }

    func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        if etf.code == "513100.XSHG" {
            return PremiumInfo(premium: 0.25, price: 1.25, netValue: 1.0)
        }
        return PremiumInfo(premium: 0.01, price: 1.01, netValue: 1.0)
    }

    func previousTradingDate(beforeOrOn date: Date) async -> Date {
        date.addingTimeInterval(-86_400)
    }

    private func latestPrice(etf: ETF, fallback: Double) -> Double {
        if etf.code == "510500.XSHG" {
            return fallback * 0.965
        }
        return fallback * 1.002
    }

    private func makeKLines(days: Int, slope: Double, lossTail: Bool) -> [KLine] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(byAdding: .day, value: -days, to: fixtureNow) ?? fixtureNow
        return (0..<days).map { i in
            let close = Foundation.exp(Foundation.log(1.0) + slope * Double(i))
            let adjustedClose = lossTail && i == days - 1 ? close * 1.05 : close
            let date = calendar.date(byAdding: .day, value: i, to: start) ?? start
            return KLine(date: date, open: adjustedClose * 0.995, close: adjustedClose, high: adjustedClose * 1.01, low: adjustedClose * 0.99, volume: 1_000)
        }
    }
}

private final class HangingProvider: MarketDataProvider, @unchecked Sendable {
    func quote(for etf: ETF) async throws -> Quote {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return Quote(code: etf.code, name: etf.name, lastPrice: 1, pctChange: 0)
    }

    func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        []
    }

    func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        nil
    }

    func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        PremiumInfo(premium: nil, price: nil, netValue: nil)
    }

    func previousTradingDate(beforeOrOn date: Date) async -> Date {
        date
    }
}

private final class OptionalDataFailingProvider: FixtureProvider, @unchecked Sendable {
    override func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        throw MarketDataError.missingData
    }

    override func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        throw MarketDataError.missingData
    }
}

private final class TodayKLineProvider: MarketDataProvider, @unchecked Sendable {
    func quote(for etf: ETF) async throws -> Quote {
        Quote(code: etf.code, name: etf.name, lastPrice: 13, pctChange: 0)
    }

    func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: fixtureNow)) ?? fixtureNow
        return (0..<30).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: start) ?? start
            let close: Double
            switch index {
            case 26: close = 10
            case 27: close = 11
            case 28: close = 12
            case 29: close = 99
            default: close = Double(index + 1)
            }
            return KLine(date: date, open: close, close: close, high: close, low: close, volume: 1_000)
        }
    }

    func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        nil
    }

    func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        PremiumInfo(premium: nil, price: nil, netValue: nil)
    }

    func previousTradingDate(beforeOrOn date: Date) async -> Date {
        date
    }
}

private final class AlwaysFailingProvider: MarketDataProvider, @unchecked Sendable {
    func quote(for etf: ETF) async throws -> Quote {
        throw MarketDataError.missingData
    }

    func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        throw MarketDataError.missingData
    }

    func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        throw MarketDataError.missingData
    }

    func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        throw MarketDataError.missingData
    }

    func previousTradingDate(beforeOrOn date: Date) async -> Date {
        date
    }
}

private final class IncompleteDailyDataProvider: MarketDataProvider, @unchecked Sendable {
    func quote(for etf: ETF) async throws -> Quote {
        Quote(code: etf.code, name: etf.name, lastPrice: 1, pctChange: 0)
    }

    func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        []
    }

    func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        nil
    }

    func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        PremiumInfo(premium: nil, price: nil, netValue: nil)
    }

    func previousTradingDate(beforeOrOn date: Date) async -> Date {
        date
    }
}

private actor CallCounter {
    private var value = 0

    func increment() {
        value += 1
    }

    func count() -> Int {
        value
    }
}

private final class DisabledQuoteProvider: MarketDataProvider, @unchecked Sendable {
    private let counter = CallCounter()

    func dailyKLineCalls() async -> Int {
        await counter.count()
    }

    func quote(for etf: ETF) async throws -> Quote {
        Quote(code: etf.code, name: etf.name, lastPrice: 2.153, pctChange: -2.97)
    }

    func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        await counter.increment()
        return []
    }

    func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        nil
    }

    func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        PremiumInfo(premium: nil, price: nil, netValue: nil)
    }

    func previousTradingDate(beforeOrOn date: Date) async -> Date {
        date
    }
}

private func makeEasyTDXScript() throws -> URL {
    try makeExecutableScript(body: """
#!/bin/sh
if [ "$1" = "quote" ]; then
  printf '[{"name":"沪深300ETF华泰柏瑞","pre_close":4.85,"close":4.905,"vol":12345,"speed_pct":9.9}]'
  exit 0
fi

if [ "$1" = "kline" ] && [ "$5" = "DAILY" ]; then
  printf '[{"datetime":"2026-06-03T15:00:00.000","open":4.8,"high":4.95,"low":4.75,"close":4.9,"vol":100,"amount":1000},{"datetime":"2026-06-04T15:00:00.000","open":4.9,"high":5.0,"low":4.88,"close":4.95,"vol":200,"amount":2000},{"datetime":"2026-06-05T15:00:00.000","open":4.95,"high":4.98,"low":4.88,"close":4.905,"vol":300,"amount":3000}]'
  exit 0
fi

if [ "$1" = "kline" ] && [ "$5" = "1MIN" ]; then
  printf '[{"datetime":"2026-06-04T14:59:00.000","open":4.8,"high":4.8,"low":4.8,"close":4.8,"vol":999,"amount":999},{"datetime":"2026-06-05T09:31:00.000","open":4.9,"high":4.9,"low":4.9,"close":4.9,"vol":300,"amount":3000},{"datetime":"2026-06-05T13:59:00.000","open":4.91,"high":4.91,"low":4.91,"close":4.91,"vol":400,"amount":4000},{"datetime":"2026-06-05T14:30:00.000","open":4.92,"high":4.92,"low":4.92,"close":4.92,"vol":500,"amount":5000}]'
  exit 0
fi

echo "unexpected args: $*" >&2
exit 2
""")
}

private func makeExecutableScript(body: String) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ETFMomentumEasyTDXTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("easy-tdx")
    try body.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}
