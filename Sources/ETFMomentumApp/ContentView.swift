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
        .preferredColorScheme(.dark)
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
        .frame(minWidth: 430)
        .background(Color.sidebarBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ETF 动量排名")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(updatedText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
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
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) {
                SectionHeader(title: "入选排行")
                ForEach(Array((store.snapshot?.included ?? []).enumerated()), id: \.element.etf.code) { index, metric in
                    RankingRow(index: index + 1, metric: metric, isSelected: selectedETF?.code == metric.etf.code)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedETF = metric.etf
                        }
                }
                SectionHeader(title: "过滤明细")
                ForEach((store.snapshot?.metrics ?? []).filter { $0.filterReason != .included }) { metric in
                    RankingRow(index: nil, metric: metric, isSelected: selectedETF?.code == metric.etf.code)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedETF = metric.etf
                        }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
        .background(Color.sidebarBackground)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.textSecondary)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

struct RankingRow: View {
    var index: Int?
    var metric: RankingMetric
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(index.map(String.init) ?? "-")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .frame(width: 26)
                .foregroundStyle(index == nil ? Color.textMuted : Color.textPrimary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(metric.etf.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(metric.etf.eastmoneyCode)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                }
                Text(metric.filterReason == .included ? "score \(metric.score.formatted(.number.precision(.fractionLength(4))))" : metric.filterReason.rawValue)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(metric.filterReason == .included ? Color.textSecondary : Color.warningText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(metric.currentPrice == 0 ? "-" : metric.currentPrice.formatted(.number.precision(.fractionLength(3))))
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                Text(metric.pctChange.formatted(.number.precision(.fractionLength(2))) + "%")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(metric.pctChange >= 0 ? Color.upRed : Color.downGreen)
            }
            .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isSelected ? Color.selectedRow : Color.rowBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.focusBorder : Color.rowBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct TopFiveStrip: View {
    var metrics: [RankingMetric]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(metrics.enumerated()), id: \.element.etf.code) { index, metric in
                VStack(alignment: .leading, spacing: 5) {
                    Text("#\(index + 1) \(metric.etf.eastmoneyCode)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                    Text(metric.score.formatted(.number.precision(.fractionLength(3))))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                    Sparkline(values: metric.closes)
                        .frame(height: 22)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.rowBorder, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

extension Color {
    static let upRed = Color(red: 1.00, green: 0.23, blue: 0.26)
    static let downGreen = Color(red: 0.00, green: 0.78, blue: 0.42)
    static let appBackground = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let sidebarBackground = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let panelBackground = Color(red: 0.14, green: 0.15, blue: 0.18)
    static let cardBackground = Color(red: 0.17, green: 0.18, blue: 0.22)
    static let rowBackground = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let selectedRow = Color(red: 0.21, green: 0.25, blue: 0.31)
    static let rowBorder = Color.white.opacity(0.07)
    static let focusBorder = Color(red: 0.55, green: 0.68, blue: 0.86)
    static let textPrimary = Color(red: 0.95, green: 0.97, blue: 1.00)
    static let textSecondary = Color(red: 0.70, green: 0.75, blue: 0.82)
    static let textMuted = Color(red: 0.49, green: 0.54, blue: 0.62)
    static let warningText = Color(red: 0.98, green: 0.73, blue: 0.34)
}
