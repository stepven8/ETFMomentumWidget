import Foundation

public struct RankingEngine: Sendable {
    public var config: StrategyConfig
    public var provider: any MarketDataProvider
    public var now: @Sendable () -> Date

    public init(config: StrategyConfig, provider: any MarketDataProvider, now: @escaping @Sendable () -> Date = Date.init) {
        self.config = config
        self.provider = provider
        self.now = now
    }

    public func rank(etfs: [ETF], includeFiltered: Bool = true) async -> RankingSnapshot {
        var output: [RankingMetric] = []
        for etf in etfs {
            guard etf.enabled else {
                if includeFiltered { output.append(RankingMetric(etf: etf, filterReason: .disabled)) }
                continue
            }
            let metric = await calculate(etf: etf)
            if includeFiltered || metric.filterReason == .included {
                output.append(metric)
            }
        }
        let included = output.filter { $0.filterReason == .included }.sorted { $0.score > $1.score }
        let filtered = output.filter { $0.filterReason != .included }
        return RankingSnapshot(generatedAt: now(), metrics: included + filtered)
    }

    public func calculate(etf: ETF) async -> RankingMetric {
        do {
            let quote = try await provider.quote(for: etf)
            if quote.paused {
                return RankingMetric(etf: named(etf, quote: quote), currentPrice: quote.lastPrice, pctChange: quote.pctChange, filterReason: .paused)
            }

            let lookback = max(config.lookbackDays, config.shortLookbackDays) + 20
            let prices = try await provider.dailyKLines(for: etf, limit: lookback)
            if prices.count < config.lookbackDays {
                return RankingMetric(etf: named(etf, quote: quote), currentPrice: quote.lastPrice, pctChange: quote.pctChange, filterReason: .insufficientData)
            }

            let closes = prices.map(\.close)
            let priceSeries = closes + [quote.lastPrice]

            if config.enableProfitProtection, checkProfitProtection(prices: prices, currentPrice: quote.lastPrice) {
                return RankingMetric(etf: named(etf, quote: quote), currentPrice: quote.lastPrice, pctChange: quote.pctChange, filterReason: .profitProtection, closes: priceSeries)
            }

            var premiumValue: Double?
            if config.enablePremiumFilter {
                let prevDate = await provider.previousTradingDate(beforeOrOn: now())
                let premium = try await provider.premiumInfo(for: etf, previousTradingDate: prevDate)
                premiumValue = premium.premium
                if let value = premium.premium, value > config.premiumThreshold {
                    return RankingMetric(etf: named(etf, quote: quote), currentPrice: quote.lastPrice, pctChange: quote.pctChange, filterReason: .premiumExceeded, premium: value, closes: priceSeries)
                }
            }

            var ratioValue: Double?
            if config.enableVolumeCheck {
                let ratio = try await volumeRatio(etf: etf, dailyPrices: prices)
                ratioValue = ratio
                if ratio != nil {
                    let annualized = MomentumMath.annualizedReturn(priceSeries: priceSeries, lookbackDays: config.lookbackDays)
                    if annualized > config.volumeReturnLimit {
                        return RankingMetric(etf: named(etf, quote: quote), annualizedReturns: annualized, currentPrice: quote.lastPrice, pctChange: quote.pctChange, filterReason: .volumeReturnExceeded, volumeRatio: ratio, premium: premiumValue, closes: priceSeries)
                    }
                }
            }

            let shortAnnualized: Double
            if priceSeries.count >= config.shortLookbackDays + 1 {
                let shortRet = priceSeries[priceSeries.count - 1] / priceSeries[priceSeries.count - (config.shortLookbackDays + 1)] - 1
                shortAnnualized = Foundation.pow(1 + shortRet, 250 / Double(config.shortLookbackDays)) - 1
            } else {
                shortAnnualized = 0
            }
            if config.useShortMomentumFilter && shortAnnualized < config.shortMomentumThreshold {
                return RankingMetric(etf: named(etf, quote: quote), currentPrice: quote.lastPrice, shortAnnualized: shortAnnualized, pctChange: quote.pctChange, filterReason: .shortMomentumWeak, volumeRatio: ratioValue, premium: premiumValue, closes: priceSeries)
            }

            let scored = MomentumMath.score(priceSeries: priceSeries, lookbackDays: config.lookbackDays)

            if priceSeries.count >= 4 {
                let day1 = priceSeries[priceSeries.count - 1] / priceSeries[priceSeries.count - 2]
                let day2 = priceSeries[priceSeries.count - 2] / priceSeries[priceSeries.count - 3]
                let day3 = priceSeries[priceSeries.count - 3] / priceSeries[priceSeries.count - 4]
                if min(day1, day2, day3) < config.loss {
                    return RankingMetric(etf: named(etf, quote: quote), annualizedReturns: scored.annRet, rSquared: scored.r2, score: scored.score, currentPrice: quote.lastPrice, shortAnnualized: shortAnnualized, pctChange: quote.pctChange, filterReason: .recentLossExceeded, volumeRatio: ratioValue, premium: premiumValue, closes: priceSeries)
                }
            }

            if !(config.minScoreThreshold < scored.score && scored.score < config.maxScoreThreshold) {
                return RankingMetric(etf: named(etf, quote: quote), annualizedReturns: scored.annRet, rSquared: scored.r2, score: scored.score, currentPrice: quote.lastPrice, shortAnnualized: shortAnnualized, pctChange: quote.pctChange, filterReason: .scoreOutOfRange, volumeRatio: ratioValue, premium: premiumValue, closes: priceSeries)
            }

            return RankingMetric(etf: named(etf, quote: quote), annualizedReturns: scored.annRet, rSquared: scored.r2, score: scored.score, currentPrice: quote.lastPrice, shortAnnualized: shortAnnualized, pctChange: quote.pctChange, filterReason: .included, volumeRatio: ratioValue, premium: premiumValue, closes: priceSeries)
        } catch {
            return RankingMetric(etf: etf, filterReason: .calculationError)
        }
    }

    private func named(_ etf: ETF, quote: Quote) -> ETF {
        ETF(code: etf.code, name: quote.name.isEmpty ? etf.name : quote.name, enabled: etf.enabled)
    }

    private func checkProfitProtection(prices: [KLine], currentPrice: Double) -> Bool {
        guard config.enableProfitProtection else { return false }
        let recent = prices.suffix(config.profitProtectionLookback)
        guard recent.count >= config.profitProtectionLookback else { return false }
        let maxHigh = recent.map(\.high).max() ?? 0
        return currentPrice <= maxHigh * (1 - config.profitProtectionThreshold)
    }

    private func volumeRatio(etf: ETF, dailyPrices: [KLine]) async throws -> Double? {
        let recent = dailyPrices.suffix(config.volumeLookback)
        guard recent.count >= config.volumeLookback else { return nil }
        let avgVol = recent.map(\.volume).reduce(0, +) / Double(recent.count)
        guard let currentVol = try await provider.minuteVolumeSumToday(for: etf, now: now()) else { return nil }
        let ratio = avgVol > 0 ? currentVol / avgVol : 0
        return ratio > config.volumeThreshold ? ratio : nil
    }
}
