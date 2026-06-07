import ETFMomentumCore
import Foundation

let sample = CommandLine.arguments.contains("--all") ? DefaultETFPool.items : Array(DefaultETFPool.items.prefix(10))
let config = StrategyConfig()
let engine = RankingEngine(config: config, provider: FallbackMarketDataProvider())
let snapshot = await engine.rank(etfs: sample, includeFiltered: true)

print("generated_at=\(snapshot.generatedAt)")
print("included_top5")
for (index, metric) in snapshot.included.prefix(5).enumerated() {
    print("\(index + 1). \(metric.etf.code) \(metric.etf.name) score=\(metric.score) ann=\(metric.annualizedReturns) r2=\(metric.rSquared) short=\(metric.shortAnnualized) price=\(metric.currentPrice)")
}
print("all_status")
for metric in snapshot.metrics {
    print("\(metric.etf.code) \(metric.etf.name) \(metric.filterReason.rawValue) score=\(metric.score)")
}
