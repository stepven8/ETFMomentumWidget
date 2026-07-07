import ETFMomentumCore
import Foundation

if CommandLine.arguments.contains("--refresh-store") {
    let store = AppStore()
    let succeeded = await store.refresh()
    let message = store.refreshMessage ?? ""
    print("success=\(succeeded)")
    print("message=\(message)")
    if let snapshot = store.snapshot {
        print("generated_at=\(snapshot.generatedAt)")
        print("included_count=\(snapshot.included.count)")
    }
    exit(succeeded ? 0 : 1)
}

if let index = CommandLine.arguments.firstIndex(of: "--diagnose-etf"), CommandLine.arguments.indices.contains(index + 1) {
    let code = CommandLine.arguments[index + 1]
    let configured = AppStore().etfs.first { $0.code == code }
    let etf = configured ?? ETF(code: code, name: code)
    let config = AppStore().config
    let provider = FallbackMarketDataProvider(enableEasyTDX: config.enableEasyTDXProvider)
    print("diagnose=\(etf.code) \(etf.name) enabled=\(etf.enabled)")
    do {
        let quote = try await provider.quote(for: etf)
        print("quote price=\(quote.lastPrice) pct=\(quote.pctChange) paused=\(quote.paused) name=\(quote.name)")
    } catch {
        print("quote_error=\(error)")
    }
    do {
        let lines = try await provider.dailyKLines(for: etf, limit: max(config.lookbackDays, config.shortLookbackDays) + 20)
        print("daily_count=\(lines.count)")
        if let first = lines.first, let last = lines.last {
            print("daily_first=\(first.date) close=\(first.close)")
            print("daily_last=\(last.date) close=\(last.close)")
        }
    } catch {
        print("daily_error=\(error)")
    }
    let metric = await RankingEngine(config: config, provider: provider).calculate(etf: etf)
    print("metric_reason=\(metric.filterReason.rawValue)")
    print("metric_price=\(metric.currentPrice)")
    print("metric_score=\(metric.score)")
    let diagnostic = metric.diagnosticMessage ?? ""
    print("metric_diagnostic=\(diagnostic)")
    exit(0)
}

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
