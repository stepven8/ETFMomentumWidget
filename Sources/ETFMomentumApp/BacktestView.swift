import AppKit
import ETFMomentumCore
import SwiftUI

struct BacktestView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedTab: ContentView.Panel
    @StateObject private var model = BacktestViewModel()
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var period: BacktestPeriod = .oneMinute
    @State private var initialCapital = 300_000.0
    @State private var selectedRunID: UUID?
    @State private var deleteCandidate: BacktestRunSummary?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    selectedTab = .ranking
                } label: {
                    Label("返回排行", systemImage: "sidebar.left")
                }
                .buttonStyle(.bordered)
                Text("回测分析")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.sidebarBackground)
            Divider().overlay(Color.rowBorder)

            HSplitView {
                recordsPane
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)
                detailPane
                    .frame(minWidth: 720)
            }
        }
        .background(Color.appBackground)
        .task {
            await model.load()
            selectedRunID = model.summaries.first?.id
            if let selectedRunID {
                await model.select(id: selectedRunID)
            }
        }
        .confirmationDialog("确认删除回测记录？", isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            if let deleteCandidate {
                Button("删除 \(deleteCandidate.name)", role: .destructive) {
                    Task {
                        await model.delete(id: deleteCandidate.id)
                        if selectedRunID == deleteCandidate.id {
                            selectedRunID = model.summaries.first?.id
                            if let selectedRunID {
                                await model.select(id: selectedRunID)
                            }
                        }
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除该次回测结果，不删除回测专用分钟 K 线缓存。")
        }
    }

    private var recordsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("回测记录")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(model.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(model.statusText.contains("失败") ? Color.warningText : Color.textSecondary)
                    .lineLimit(3)
            }

            backtestControls

            if model.isRunning || model.progressFraction > 0 {
                progressPanel
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.summaries) { summary in
                        BacktestRunRow(summary: summary, isSelected: selectedRunID == summary.id) {
                            deleteCandidate = summary
                        }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedRunID = summary.id
                                Task { await model.select(id: summary.id) }
                            }
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    deleteCandidate = summary
                                }
                            }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(18)
        .background(Color.sidebarBackground)
    }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: model.progressFraction)
                .progressViewStyle(.linear)
            HStack {
                Text(model.progressDetail.isEmpty ? "正在准备..." : model.progressDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                Spacer()
                Text(model.progressFraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
            }
            if !model.logs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.logs.suffix(4), id: \.self) { log in
                        Text(log)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.rowBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.rowBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var backtestControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            paddedDatePicker("开始", selection: $startDate)
            paddedDatePicker("结束", selection: $endDate)
            Picker("周期", selection: $period) {
                ForEach(BacktestPeriod.allCases) { period in
                    Text(period.displayName).tag(period)
                }
            }
            HStack {
                Text("资金")
                TextField("初始资金", value: $initialCapital, format: .number)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button {
                    Task { await runBacktest() }
                } label: {
                    Label(model.isRunning ? "运行中" : "新建回测", systemImage: "play.fill")
                }
                .disabled(model.isRunning)
                Button {
                    model.cancel()
                } label: {
                    Label("取消", systemImage: "xmark")
                }
                .disabled(!model.isRunning)
            }
            .buttonStyle(.bordered)
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(Color.textPrimary)
        .padding(12)
        .background(Color.rowBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.rowBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func paddedDatePicker(_ title: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 32, alignment: .leading)
            DatePicker("", selection: selection, displayedComponents: .date)
                .labelsHidden()
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 172, alignment: .leading)
                .padding(.leading, 8)
                .padding(.trailing, 16)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let result = model.selectedResult {
                    BacktestDetailView(result: result, export: {
                        model.export(result: result)
                    })
                } else {
                    ContentUnavailableView("暂无回测记录", systemImage: "chart.xyaxis.line", description: Text("设置日期和周期后点击新建回测。"))
                        .frame(maxWidth: .infinity, minHeight: 520)
                }
            }
            .padding(20)
        }
        .background(Color.appBackground)
    }

    private func runBacktest() async {
        let name = "ETF 动量 \(period.displayName) \(Date().formatted(date: .numeric, time: .shortened))"
        let config = BacktestConfig(
            name: name,
            startDate: dayStart(min(startDate, endDate)),
            endDate: dayEnd(max(startDate, endDate)),
            period: period,
            initialCapital: initialCapital,
            benchmark: ETF(code: "159919.XSHE", name: "沪深300ETF")
        )
        await model.run(strategyConfig: store.config, universe: store.etfs, config: config)
        selectedRunID = model.summaries.first?.id
        if let selectedRunID {
            await model.select(id: selectedRunID)
        }
    }

    private func dayStart(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar.startOfDay(for: date)
    }

    private func dayEnd(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}

@MainActor
final class BacktestViewModel: ObservableObject {
    @Published var summaries: [BacktestRunSummary] = []
    @Published var selectedResult: BacktestResult?
    @Published var statusText = "回测数据独立保存，不影响动量排行"
    @Published var isRunning = false
    @Published var progressFraction = 0.0
    @Published var progressDetail = ""
    @Published var logs: [String] = []

    private var task: Task<Void, Never>?
    private let sqliteStore: BacktestSQLiteStore?

    init() {
        sqliteStore = try? BacktestSQLiteStore()
    }

    func load() async {
        guard let sqliteStore else {
            statusText = "回测数据库初始化失败"
            return
        }
        do {
            summaries = try sqliteStore.summaries()
        } catch {
            statusText = "读取回测记录失败：\(error.localizedDescription)"
        }
    }

    func select(id: UUID) async {
        guard let sqliteStore else { return }
        do {
            selectedResult = try sqliteStore.result(id: id)
        } catch {
            statusText = "打开回测详情失败：\(error.localizedDescription)"
        }
    }

    func run(strategyConfig: StrategyConfig, universe: [ETF], config: BacktestConfig) async {
        guard let sqliteStore else {
            statusText = "回测数据库不可用"
            return
        }
        isRunning = true
        statusText = "准备回测..."
        progressFraction = 0
        progressDetail = "初始化回测数据库"
        logs = []
        task = Task {
            do {
                let dataProvider = EasyTDXBacktestDataProvider(store: sqliteStore)
                let engine = BacktestEngine(dataProvider: dataProvider)
                let result = try await engine.run(strategyConfig: strategyConfig, universe: universe, backtestConfig: config) { [weak self] progress in
                    await MainActor.run {
                        self?.statusText = progress.message
                        self?.progressDetail = progress.detail
                        self?.progressFraction = progress.fraction
                        self?.logs.append(progress.detail.isEmpty ? progress.message : "\(progress.message) · \(progress.detail)")
                        if (self?.logs.count ?? 0) > 80 {
                            self?.logs.removeFirst()
                        }
                    }
                }
                try sqliteStore.save(result: result)
                await MainActor.run {
                    selectedResult = result
                    statusText = "回测完成"
                    progressFraction = 1
                    progressDetail = "已生成回测记录"
                }
            } catch is CancellationError {
                await MainActor.run {
                    statusText = "回测已取消"
                    progressDetail = ""
                }
            } catch {
                await MainActor.run {
                    statusText = "回测失败：\(readable(error))"
                    progressDetail = readable(error)
                    logs.append(readable(error))
                }
            }
            await MainActor.run {
                isRunning = false
            }
            await load()
        }
        await task?.value
    }

    func cancel() {
        task?.cancel()
        statusText = "正在取消..."
    }

    func delete(id: UUID) async {
        guard let sqliteStore else { return }
        do {
            try sqliteStore.deleteRun(id: id)
            selectedResult = nil
            await load()
        } catch {
            statusText = "删除失败：\(error.localizedDescription)"
        }
    }

    func export(result: BacktestResult) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let target = url.appendingPathComponent(result.summary.name.replacingOccurrences(of: "/", with: "-"), isDirectory: true)
            do {
                try BacktestExporter.export(result: result, to: target)
                statusText = "已导出到 \(target.path)"
            } catch {
                statusText = "导出失败：\(error.localizedDescription)"
            }
        }
    }
}

private func readable(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return String(describing: error)
}

struct BacktestRunRow: View {
    let summary: BacktestRunSummary
    let isSelected: Bool
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(summary.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.textSecondary)
                .help("删除回测记录")
                Text(summary.status.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(summary.status == .completed ? Color.textSecondary : Color.warningText)
            }
            HStack {
                Text(summary.period.displayName)
                Text(summary.startDate.formatted(date: .numeric, time: .omitted))
                Text("-")
                Text(summary.endDate.formatted(date: .numeric, time: .omitted))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.textSecondary)
            HStack(spacing: 12) {
                metric("收益", summary.totalReturn)
                metric("基准", summary.benchmarkReturn)
                metric("最大回撤", summary.maxDrawdown)
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.rowBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.rowBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ label: String, _ value: Double) -> some View {
        Text("\(label) \(value.formatted(.percent.precision(.fractionLength(2))))")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(value >= 0 ? Color.upRed : Color.downGreen)
    }
}

struct BacktestDetailView: View {
    let result: BacktestResult
    let export: () -> Void
    @State private var showTradeMarkers = true
    @State private var selectedSignalDate: Date?

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(result.summary.name)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(result.backtestConfig.startDate.formatted(date: .numeric, time: .omitted)) - \(result.backtestConfig.endDate.formatted(date: .numeric, time: .omitted)) · \(result.backtestConfig.period.displayName) · \(result.universe.count) 只标的")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Button(action: export) {
                    Label("导出", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }

            metricsGrid
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("收益曲线")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Toggle("买卖点", isOn: $showTradeMarkers)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                }
                EquityCurveChart(points: result.equityCurve, trades: result.trades, showTradeMarkers: showTradeMarkers)
                    .frame(height: 260)
            }
            .padding(10)
            .background(Color.panelBackground)
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.rowBorder, lineWidth: 1) }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            BacktestParameterPanel(result: result)
            BacktestTablePanel(title: "交易明细") {
                BacktestTradesTable(trades: result.trades)
            }
            BacktestTablePanel(title: "持仓快照") {
                BacktestPositionsTable(positions: Array(result.positions.suffix(80)))
            }
            BacktestTablePanel(title: "排名信号") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("日期", selection: signalDateSelection) {
                        ForEach(signalDates, id: \.timeIntervalSince1970) { date in
                            Text(date.formatted(date: .numeric, time: .omitted))
                                .tag(date.timeIntervalSince1970)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .leading)
                    BacktestSignalsTable(signals: selectedDaySignals)
                }
            }
            BacktestTablePanel(title: "回测日志") {
                BacktestLogView(logs: generatedLogs)
            }
        }
        .onAppear {
            if selectedSignalDate == nil {
                selectedSignalDate = signalDates.last
            }
        }
        .onChange(of: result.summary.id) { _, _ in
            selectedSignalDate = signalDates.last
            showTradeMarkers = true
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            card("总收益", result.metrics.totalReturn, .percent)
            card("年化", result.metrics.annualizedReturn, .percent)
            card("基准", result.metrics.benchmarkReturn, .percent)
            card("超额", result.metrics.excessReturn, .percent)
            card("最大回撤", result.metrics.maxDrawdown, .percent)
            card("夏普", result.metrics.sharpe, .number)
            card("波动率", result.metrics.volatility, .percent)
            card("交易次数", Double(result.metrics.tradeCount), .integer)
        }
    }

    private func card(_ title: String, _ value: Double, _ style: MetricStyle) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
            Text(format(value, style: style))
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(value >= 0 ? Color.upRed : Color.downGreen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.rowBackground)
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.rowBorder, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var signalDates: [Date] {
        Array(Set(result.signals.map { calendar.startOfDay(for: $0.date) })).sorted()
    }

    private var signalDateSelection: Binding<Double> {
        Binding(
            get: { (selectedSignalDate ?? signalDates.last ?? Date()).timeIntervalSince1970 },
            set: { selectedSignalDate = Date(timeIntervalSince1970: $0) }
        )
    }

    private var selectedDaySignals: [BacktestRankSignal] {
        guard let selected = selectedSignalDate ?? signalDates.last else { return Array(result.signals.suffix(120)) }
        return result.signals
            .filter { calendar.isDate($0.date, inSameDayAs: selected) }
            .sorted { lhs, rhs in
                switch (lhs.rank, rhs.rank) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.name < rhs.name
                }
            }
    }

    private var generatedLogs: [BacktestLogEntry] {
        let rankingLogs = signalDates.map { day in
            let logDate = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day) ?? day
            let daySignals = result.signals
                .filter { calendar.isDate($0.date, inSameDayAs: day) && $0.rank != nil }
                .sorted { ($0.rank ?? Int.max) < ($1.rank ?? Int.max) }
                .prefix(5)
                .map { "#\($0.rank ?? 0) \($0.name) \($0.code) score \($0.score.formatted(.number.precision(.fractionLength(4))))" }
                .joined(separator: "；")
            return BacktestLogEntry(date: logDate, text: "排名：\(daySignals.isEmpty ? "无入选标的" : daySignals)")
        }
        let tradeLogs = result.trades.map {
            BacktestLogEntry(date: $0.date, text: "\($0.side) \($0.name) \($0.code) \($0.filledAmount) 份，成交价 \($0.price.formatted(.number.precision(.fractionLength(3))))，\($0.reason)")
        }
        let datedLogs = (rankingLogs + tradeLogs).sorted { $0.date < $1.date }
        let legacyLogs = result.logs.enumerated().map { index, log in
            BacktestLogEntry(date: result.backtestConfig.endDate.addingTimeInterval(Double(index + 1)), text: log)
        }
        return datedLogs + legacyLogs
    }
}

private enum MetricStyle {
    case percent
    case number
    case integer
}

private func format(_ value: Double, style: MetricStyle) -> String {
    switch style {
    case .percent:
        return value.formatted(.percent.precision(.fractionLength(2)))
    case .number:
        return value.formatted(.number.precision(.fractionLength(2)))
    case .integer:
        return Int(value).formatted()
    }
}

struct BacktestParameterPanel: View {
    let result: BacktestResult

    var body: some View {
        BacktestTablePanel(title: "回测设置与策略参数") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                item("初始资金", result.backtestConfig.initialCapital.formatted(.number.precision(.fractionLength(0))))
                item("基准", "\(result.backtestConfig.benchmark.name) \(result.backtestConfig.benchmark.code)")
                item("周期", result.backtestConfig.period.displayName)
                item("lookback_days", "\(result.strategyConfig.lookbackDays)")
                item("holdings_num", "\(result.strategyConfig.holdingsNum)")
                item("loss", result.strategyConfig.loss.formatted(.number.precision(.fractionLength(4))))
                item("最低分", result.strategyConfig.minScoreThreshold.formatted(.number.precision(.fractionLength(4))))
                item("最高分", result.strategyConfig.maxScoreThreshold.formatted(.number.precision(.fractionLength(4))))
                item("标的数", "\(result.universe.count)")
            }
        }
    }

    private func item(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
        }
    }
}

struct BacktestTablePanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            content
        }
        .padding(12)
        .background(Color.panelBackground)
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.rowBorder, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct BacktestTradesTable: View {
    let trades: [BacktestTrade]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
            header(["时间", "标的", "方向", "价格", "数量", "佣金", "收益金额", "原因"])
            ForEach(displayRows.suffix(100)) { row in
                GridRow {
                    cell(row.trade.date.formatted(date: .numeric, time: .shortened))
                    securityCell(name: row.trade.name, code: row.trade.code)
                    cell(row.trade.side, color: row.trade.side == "买入" ? .upRed : .downGreen)
                    cell(row.trade.price.formatted(.number.precision(.fractionLength(3))))
                    cell("\(row.trade.filledAmount)")
                    cell(row.trade.commission.formatted(.number.precision(.fractionLength(2))))
                    cell(row.profit.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "-", color: (row.profit ?? 0) >= 0 ? .upRed : .downGreen)
                    cell(row.trade.reason)
                }
            }
        }
    }

    private var displayRows: [TradeDisplayRow] {
        var positions: [String: (amount: Int, cost: Double)] = [:]
        return trades.sorted { $0.date < $1.date }.map { trade in
            var profit: Double?
            if trade.side == "买入" {
                let old = positions[trade.code] ?? (0, 0)
                let newAmount = old.amount + trade.filledAmount
                let oldValue = Double(old.amount) * old.cost
                let newValue = Double(trade.filledAmount) * trade.price
                positions[trade.code] = (newAmount, newAmount > 0 ? (oldValue + newValue) / Double(newAmount) : trade.price)
            } else {
                let old = positions[trade.code] ?? (trade.filledAmount, trade.price)
                profit = (trade.price - old.cost) * Double(trade.filledAmount) - trade.commission
                let remaining = max(old.amount - trade.filledAmount, 0)
                positions[trade.code] = remaining > 0 ? (remaining, old.cost) : nil
            }
            return TradeDisplayRow(trade: trade, profit: profit)
        }
    }
}

private struct TradeDisplayRow: Identifiable {
    var id: UUID { trade.id }
    let trade: BacktestTrade
    let profit: Double?
}

struct BacktestPositionsTable: View {
    let positions: [BacktestPositionSnapshot]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
            header(["时间", "标的", "数量", "价格", "市值", "总资产"])
            ForEach(positions) { item in
                GridRow {
                    cell(item.date.formatted(date: .numeric, time: .shortened))
                    securityCell(name: item.name, code: item.code)
                    cell("\(item.amount)")
                    cell(item.price.formatted(.number.precision(.fractionLength(3))))
                    cell(item.marketValue.formatted(.number.precision(.fractionLength(0))))
                    cell(item.totalValue.formatted(.number.precision(.fractionLength(0))))
                }
            }
        }
    }
}

struct BacktestSignalsTable: View {
    let signals: [BacktestRankSignal]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
            header(["时间", "排名", "标的", "score", "年化", "R²", "原因"])
            ForEach(signals) { signal in
                GridRow {
                    cell(signal.date.formatted(date: .numeric, time: .shortened))
                    cell(signal.rank.map(String.init) ?? "-")
                    securityCell(name: signal.name, code: signal.code)
                    cell(signal.score.formatted(.number.precision(.fractionLength(4))))
                    cell(signal.annualizedReturns.formatted(.percent.precision(.fractionLength(2))))
                    cell(signal.rSquared.formatted(.number.precision(.fractionLength(3))))
                    cell(signal.filterReason.rawValue)
                }
            }
        }
    }
}

struct BacktestLogView: View {
    let logs: [BacktestLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if logs.isEmpty {
                Text("暂无日志")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(Array(logs.suffix(220).enumerated()), id: \.offset) { _, log in
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(log.date.formatted(date: .numeric, time: .shortened))  \(log.text)")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                            .overlay(Color.rowBorder)
                    }
                }
            }
        }
    }
}

struct BacktestLogEntry: Equatable {
    let date: Date
    let text: String
}

@ViewBuilder
private func header(_ titles: [String]) -> some View {
    GridRow {
        ForEach(titles, id: \.self) { title in
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
        }
    }
    Divider()
        .gridCellColumns(titles.count)
}

private func cell(_ text: String, color: Color = Color.textPrimary) -> some View {
    Text(text)
        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
        .foregroundStyle(color)
        .lineLimit(1)
}

private func securityCell(name: String, code: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
        Text(name.isEmpty ? code : name)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
        if !name.isEmpty {
            Text(code)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
    }
}

struct EquityCurveChart: View {
    let points: [BacktestEquityPoint]
    let trades: [BacktestTrade]
    let showTradeMarkers: Bool

    private var strategyColor: Color {
        Color(red: 0.20, green: 0.62, blue: 1.00)
    }

    private var benchmarkColor: Color {
        Color(red: 0.72, green: 0.76, blue: 0.82)
    }

    private var drawdownColor: Color {
        Color(red: 1.00, green: 0.35, blue: 0.35)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                legendItem("策略", color: strategyColor)
                legendItem("基准", color: benchmarkColor)
                legendItem("回撤", color: drawdownColor)
                if showTradeMarkers {
                    legendItem("买入", color: .upRed)
                    legendItem("卖出", color: .downGreen)
                }
            }
            GeometryReader { proxy in
                Canvas { context, size in
                    let rect = CGRect(x: 46, y: 14, width: max(size.width - 70, 10), height: max(size.height - 44, 10))
                    guard !points.isEmpty else {
                        let text = Text("暂无收益曲线")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                        context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
                        return
                    }
                    let values = points.flatMap { [$0.strategyReturn, $0.benchmarkReturn, $0.drawdown] }
                    let rawMin = values.min() ?? -0.1
                    let rawMax = values.max() ?? 0.1
                    let padding = max((rawMax - rawMin) * 0.08, 0.01)
                    let minValue = rawMin - padding
                    let maxValue = rawMax + padding
                    drawGrid(context: context, rect: rect, min: minValue, max: maxValue)
                    drawDateAxis(context: context, rect: rect)
                    if points.count == 1 {
                        let point = CGPoint(x: rect.midX, y: y(for: points[0].strategyReturn, rect: rect, min: minValue, max: maxValue))
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(strategyColor))
                        context.draw(Text("仅 1 个权益点").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.textSecondary), at: CGPoint(x: rect.midX, y: rect.midY + 18), anchor: .top)
                        return
                    }
                    drawLine(context: context, rect: rect, values: points.map(\.strategyReturn), min: minValue, max: maxValue, color: strategyColor)
                    drawLine(context: context, rect: rect, values: points.map(\.benchmarkReturn), min: minValue, max: maxValue, color: benchmarkColor)
                    drawLine(context: context, rect: rect, values: points.map(\.drawdown), min: minValue, max: maxValue, color: drawdownColor)
                    if showTradeMarkers {
                        drawTradeMarkers(context: context, rect: rect, min: minValue, max: maxValue)
                    }
                }
            }
        }
    }

    private func legendItem(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func drawGrid(context: GraphicsContext, rect: CGRect, min: Double, max: Double) {
        for i in 0...4 {
            let y = rect.minY + CGFloat(i) / 4 * rect.height
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(path, with: .color(Color.white.opacity(0.10)), lineWidth: 0.7)
            let value = max - Double(i) / 4 * (max - min)
            context.draw(Text(value.formatted(.percent.precision(.fractionLength(1)))).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.textSecondary), at: CGPoint(x: rect.minX - 8, y: y), anchor: .trailing)
        }
    }

    private func drawLine(context: GraphicsContext, rect: CGRect, values: [Double], min minValue: Double, max maxValue: Double, color: Color) {
        guard maxValue != minValue else { return }
        var path = Path()
        for index in values.indices {
            let x = rect.minX + CGFloat(index) / CGFloat(Swift.max(values.count - 1, 1)) * rect.width
            let y = rect.maxY - CGFloat((values[index] - minValue) / (maxValue - minValue)) * rect.height
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }

    private func drawDateAxis(context: GraphicsContext, rect: CGRect) {
        guard !points.isEmpty else { return }
        let indexes = Array(Set([0, points.count / 2, max(points.count - 1, 0)])).sorted()
        for index in indexes {
            let x = rect.minX + CGFloat(index) / CGFloat(Swift.max(points.count - 1, 1)) * rect.width
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: rect.maxY))
            tick.addLine(to: CGPoint(x: x, y: rect.maxY + 4))
            context.stroke(tick, with: .color(Color.white.opacity(0.16)), lineWidth: 0.8)
            let label = points[index].date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
            context.draw(Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.textSecondary), at: CGPoint(x: x, y: rect.maxY + 8), anchor: .top)
        }
    }

    private func drawTradeMarkers(context: GraphicsContext, rect: CGRect, min minValue: Double, max maxValue: Double) {
        for trade in trades {
            guard let index = nearestPointIndex(to: trade.date) else { continue }
            let x = rect.minX + CGFloat(index) / CGFloat(Swift.max(points.count - 1, 1)) * rect.width
            let y = y(for: points[index].strategyReturn, rect: rect, min: minValue, max: maxValue)
            let color: Color = trade.side == "买入" ? .upRed : .downGreen
            context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(color))
            context.stroke(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(Color.panelBackground), lineWidth: 1.2)
            context.draw(Text(trade.side == "买入" ? "买" : "卖").font(.system(size: 9, weight: .bold)).foregroundStyle(color), at: CGPoint(x: x, y: y - 9), anchor: .bottom)
        }
    }

    private func nearestPointIndex(to date: Date) -> Int? {
        guard !points.isEmpty else { return nil }
        return points.indices.min { lhs, rhs in
            abs(points[lhs].date.timeIntervalSince(date)) < abs(points[rhs].date.timeIntervalSince(date))
        }
    }

    private func y(for value: Double, rect: CGRect, min minValue: Double, max maxValue: Double) -> CGFloat {
        guard maxValue != minValue else { return rect.midY }
        return rect.maxY - CGFloat((value - minValue) / (maxValue - minValue)) * rect.height
    }
}
