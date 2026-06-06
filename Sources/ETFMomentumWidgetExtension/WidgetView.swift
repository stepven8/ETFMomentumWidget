import ETFMomentumCore
import SwiftUI
import WidgetKit

public struct ETFMomentumEntry: TimelineEntry {
    public let date: Date
    public let snapshot: RankingSnapshot?

    public init(date: Date, snapshot: RankingSnapshot?) {
        self.date = date
        self.snapshot = snapshot
    }
}

public struct ETFMomentumProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> ETFMomentumEntry {
        ETFMomentumEntry(date: Date(), snapshot: RankingSnapshot(metrics: Array(DefaultETFPool.items.prefix(5)).enumerated().map { index, etf in
            RankingMetric(etf: etf, score: Double(5 - index) / 10, currentPrice: 1 + Double(index) / 10, pctChange: Double(index) - 2, filterReason: .included, closes: [1, 1.02, 1.03, 1.01, 1.04])
        }))
    }

    public func getSnapshot(in context: Context, completion: @escaping (ETFMomentumEntry) -> Void) {
        completion(ETFMomentumEntry(date: Date(), snapshot: AppStore.cachedSnapshot()))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<ETFMomentumEntry>) -> Void) {
        let entry = ETFMomentumEntry(date: Date(), snapshot: AppStore.cachedSnapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

public struct ETFMomentumWidgetView: View {
    public var entry: ETFMomentumEntry

    public init(entry: ETFMomentumEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ETF 动量 Top 5")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            let rows = Array((entry.snapshot?.included ?? []).prefix(5).enumerated())
            ForEach(rows, id: \.element.etf.code) { index, metric in
                HStack(spacing: 8) {
                    Text(String(index + 1))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(metric.etf.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Text(metric.etf.eastmoneyCode)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(metric.score.formatted(.number.precision(.fractionLength(3))))
                        .font(.system(size: 11, design: .monospaced))
                    Text(metric.pctChange.formatted(.number.precision(.fractionLength(1))) + "%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(metric.pctChange >= 0 ? Color.upRed : Color.downGreen)
                }
            }
            if (entry.snapshot?.included ?? []).isEmpty {
                Spacer()
                Text("打开主 App 手动更新")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .containerBackground(Color(red: 0.10, green: 0.11, blue: 0.13), for: .widget)
        .widgetURL(URL(string: "etfmomentum://rankings"))
    }
}

public struct ETFMomentumWidgetBundle: Widget {
    public let kind = "ETFMomentumWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ETFMomentumProvider()) { entry in
            ETFMomentumWidgetView(entry: entry)
        }
        .configurationDisplayName("ETF 动量排名")
        .description("显示当前动量排名前五的 ETF。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private extension Color {
    static let upRed = Color(red: 0.86, green: 0.15, blue: 0.18)
    static let downGreen = Color(red: 0.08, green: 0.58, blue: 0.30)
}
