import ETFMomentumCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedETF: ETF?
    @State private var selectedTab: Panel = .ranking
    @State private var isRefreshing = false
    @State private var detailKLines: [KLine] = []

    enum Panel: String, CaseIterable {
        case ranking = "完整排行"
        case settings = "参数设置"
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if selectedTab == .settings {
                SettingsView()
            } else {
                detail
            }
        }
        .background(Color.appBackground)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $selectedTab) {
                ForEach(Panel.allCases, id: \.self) { panel in
                    Text(panel.rawValue).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            RankingList(selectedETF: $selectedETF)
        }
        .frame(minWidth: 390)
        .background(Color.sidebarBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ETF 动量排名")
                        .font(.system(size: 22, weight: .semibold))
                    Text(updatedText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    refresh()
                } label: {
                    Label(isRefreshing ? "更新中" : "手动更新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRefreshing)
            }
            TopFiveStrip(metrics: Array((store.snapshot?.included ?? []).prefix(5)))
        }
        .padding(16)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if let selectedETF {
                ETFDetailView(etf: selectedETF)
            } else if let first = store.snapshot?.included.first?.etf {
                ETFDetailView(etf: first)
            } else {
                ContentUnavailableView("暂无入选 ETF", systemImage: "chart.line.uptrend.xyaxis", description: Text("点击手动更新获取当前动量排行。"))
            }
        }
    }

    private var updatedText: String {
        guard let date = store.snapshot?.generatedAt else { return "尚未更新" }
        return "最后更新 \(date.formatted(date: .numeric, time: .standard))"
    }

    private func refresh() {
        isRefreshing = true
        Task {
            await store.refresh()
            await MainActor.run {
                isRefreshing = false
                selectedTab = .ranking
            }
        }
    }
}

struct RankingList: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedETF: ETF?

    var body: some View {
        List(selection: Binding(get: { selectedETF?.code }, set: { code in
            selectedETF = store.snapshot?.metrics.first { $0.etf.code == code }?.etf
        })) {
            Section("入选排行") {
                ForEach(Array((store.snapshot?.included ?? []).enumerated()), id: \.element.etf.code) { index, metric in
                    RankingRow(index: index + 1, metric: metric)
                        .tag(metric.etf.code)
                }
            }
            Section("过滤明细") {
                ForEach((store.snapshot?.metrics ?? []).filter { $0.filterReason != .included }) { metric in
                    RankingRow(index: nil, metric: metric)
                        .tag(metric.etf.code)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct RankingRow: View {
    var index: Int?
    var metric: RankingMetric

    var body: some View {
        HStack(spacing: 10) {
            Text(index.map(String.init) ?? "-")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 24)
                .foregroundStyle(index == nil ? .secondary : .primary)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(metric.etf.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(metric.etf.eastmoneyCode)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(metric.filterReason == .included ? "score \(metric.score.formatted(.number.precision(.fractionLength(4))))" : metric.filterReason.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(metric.currentPrice == 0 ? "-" : metric.currentPrice.formatted(.number.precision(.fractionLength(3))))
                    .font(.system(size: 12, design: .monospaced))
                Text(metric.pctChange.formatted(.number.precision(.fractionLength(2))) + "%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(metric.pctChange >= 0 ? Color.upRed : Color.downGreen)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TopFiveStrip: View {
    var metrics: [RankingMetric]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(metrics.enumerated()), id: \.element.etf.code) { index, metric in
                VStack(alignment: .leading, spacing: 3) {
                    Text("#\(index + 1) \(metric.etf.eastmoneyCode)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text(metric.score.formatted(.number.precision(.fractionLength(3))))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    Sparkline(values: metric.closes)
                        .frame(height: 22)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

extension Color {
    static let upRed = Color(red: 0.86, green: 0.15, blue: 0.18)
    static let downGreen = Color(red: 0.08, green: 0.58, blue: 0.30)
    static let appBackground = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let sidebarBackground = Color(red: 0.10, green: 0.11, blue: 0.13)
    static let panelBackground = Color(red: 0.15, green: 0.16, blue: 0.19)
}
