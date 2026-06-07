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

@Test func appStoreRefreshTimesOutInsteadOfHanging() async {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ETFMomentumWidgetTests-\(UUID().uuidString)", isDirectory: true)
    let store = await AppStore(directory: directory)
    await MainActor.run {
        store.etfs = [FixtureProvider.etfs[0]]
    }

    let succeeded = await store.refresh(provider: HangingProvider(), timeoutSeconds: 1)

    #expect(succeeded == false)
}

private let fixtureNow = ISO8601DateFormatter().date(from: "2026-06-05T06:00:00Z")!

private final class FixtureProvider: MarketDataProvider, @unchecked Sendable {
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
