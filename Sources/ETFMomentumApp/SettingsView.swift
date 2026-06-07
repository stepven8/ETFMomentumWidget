import AppKit
import ETFMomentumCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var saveMessage: String?
    @State private var pendingDelete: PendingETFDelete?

    private let strategyFileName = "纯五福七星ETF轮动策略（实测可行）"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                sourceSection
                settingsSection("排名参数") {
                    stepperRow("动量窗口 lookback_days", value: $store.config.lookbackDays, in: 5...120)
                    stepperRow("持仓数量 holdings_num", value: $store.config.holdingsNum, in: 1...10)
                    numberField("最低分", value: $store.config.minScoreThreshold)
                    numberField("最高分", value: $store.config.maxScoreThreshold)
                    numberField("近三日跌幅 loss", value: $store.config.loss)
                }
                settingsSection("成交量过滤") {
                    toggleRow("启用成交量过滤", isOn: $store.config.enableVolumeCheck)
                    stepperRow("成交量回看", value: $store.config.volumeLookback, in: 1...30)
                    numberField("量比阈值", value: $store.config.volumeThreshold)
                    numberField("年化收益上限", value: $store.config.volumeReturnLimit)
                }
                settingsSection("短期动量与保护") {
                    toggleRow("启用短期动量过滤", isOn: $store.config.useShortMomentumFilter)
                    stepperRow("短期窗口", value: $store.config.shortLookbackDays, in: 2...60)
                    numberField("短期年化阈值", value: $store.config.shortMomentumThreshold)
                    toggleRow("启用盈利保护", isOn: $store.config.enableProfitProtection)
                    stepperRow("盈利保护回看", value: $store.config.profitProtectionLookback, in: 1...20)
                    numberField("盈利保护阈值", value: $store.config.profitProtectionThreshold)
                }
                settingsSection("溢价过滤") {
                    toggleRow("启用溢价过滤", isOn: $store.config.enablePremiumFilter)
                    numberField("溢价阈值", value: $store.config.premiumThreshold)
                }
                settingsSection("ETF 股票池") {
                    ForEach(store.etfs.indices, id: \.self) { index in
                        etfRow(index: index)
                    }
                    Button {
                        store.etfs.append(ETF(code: "000000.XSHG", name: "新ETF"))
                    } label: {
                        Label("新增 ETF", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isRefreshing)
                    .padding(.top, 8)
                }
                HStack(spacing: 12) {
                    Button {
                        saveAndRefresh()
                    } label: {
                        Label(store.isRefreshing ? "保存并重算中" : "保存设置", systemImage: store.isRefreshing ? "arrow.clockwise" : "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isRefreshing)

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(saveMessage.contains("失败") ? Color.warningText : Color.textSecondary)
                    }
                }
            }
            .padding(24)
        }
        .background(Color.appBackground)
        .confirmationDialog("确认删除 ETF？", isPresented: deleteConfirmationPresented) {
            if let pendingDelete {
                Button("删除 \(pendingDelete.etf.name)", role: .destructive) {
                    deleteETF(pendingDelete)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let pendingDelete {
                Text("将从股票池删除 \(pendingDelete.etf.name)（\(pendingDelete.etf.code)）。删除后需要保存设置才会生效。")
            }
        }
    }

    private var sourceSection: some View {
        settingsSection("原版聚宽策略") {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("纯五福七星ETF轮动策略（实测可行）")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("原版策略源码已随 App 内置，点击右侧按钮打开。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    openBundledStrategyFile()
                } label: {
                    Label("打开源码 TXT", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
            }
            .frame(minHeight: 44)
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDelete = nil
                }
            }
        )
    }

    private func openBundledStrategyFile() {
        guard let fileURL = Bundle.main.url(forResource: strategyFileName, withExtension: "txt") else {
            saveMessage = "打开失败：App 内未找到原版策略源码"
            return
        }
        NSWorkspace.shared.open(fileURL)
    }

    private func saveAndRefresh() {
        saveMessage = "正在保存设置并重新计算排行..."
        Task {
            do {
                try store.saveConfigAndPool()
                let success = await store.refresh()
                await MainActor.run {
                    let timeText = store.snapshot?.generatedAt.formatted(date: .omitted, time: .standard) ?? Date().formatted(date: .omitted, time: .standard)
                    saveMessage = success
                        ? "保存完成，排行已重新计算 \(timeText)"
                        : "保存成功，但重新计算失败或超时"
                }
            } catch {
                await MainActor.run {
                    saveMessage = "保存失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func requestDeleteETF(at index: Int) {
        guard store.etfs.indices.contains(index) else { return }
        pendingDelete = PendingETFDelete(index: index, etf: store.etfs[index])
    }

    private func deleteETF(_ item: PendingETFDelete) {
        if store.etfs.indices.contains(item.index), store.etfs[item.index].code == item.etf.code {
            store.etfs.remove(at: item.index)
            saveMessage = "ETF 已删除，点击保存设置后生效"
            return
        }
        if let currentIndex = store.etfs.firstIndex(where: { $0.code == item.etf.code }) {
            store.etfs.remove(at: currentIndex)
            saveMessage = "ETF 已删除，点击保存设置后生效"
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.rowBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.rowBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: 180, alignment: .leading)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .disabled(store.isRefreshing)
        }
        .font(.system(size: 12.5, weight: .medium))
        .frame(height: 36)
        .overlay(alignment: .bottom) { rowDivider }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: 180, alignment: .leading)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 64, alignment: .trailing)
            }
            .frame(width: 130, alignment: .trailing)
            .disabled(store.isRefreshing)
        }
        .font(.system(size: 12.5, weight: .medium))
        .frame(height: 36)
        .overlay(alignment: .bottom) { rowDivider }
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: 180, alignment: .leading)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .frame(width: 120)
                .disabled(store.isRefreshing)
        }
        .font(.system(size: 12.5, weight: .medium))
        .frame(height: 36)
        .overlay(alignment: .bottom) { rowDivider }
    }

    private func etfRow(index: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle("", isOn: $store.etfs[index].enabled)
                .labelsHidden()
                .frame(width: 42, alignment: .leading)
                .disabled(store.isRefreshing)
            Text("代码")
                .frame(width: 30, alignment: .leading)
                .foregroundStyle(Color.textSecondary)
            TextField("代码", text: $store.etfs[index].code)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .frame(width: 130)
                .textFieldStyle(.roundedBorder)
                .disabled(store.isRefreshing)
            Text("名称")
                .frame(width: 30, alignment: .leading)
                .foregroundStyle(Color.textSecondary)
            TextField("名称", text: $store.etfs[index].name)
                .font(.system(size: 12.5, weight: .medium))
                .textFieldStyle(.roundedBorder)
                .disabled(store.isRefreshing)
            Button {
                requestDeleteETF(at: index)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.warningText)
            .help("删除 ETF")
            .disabled(store.isRefreshing)
        }
        .font(.system(size: 12.5, weight: .medium))
        .frame(height: 42)
        .overlay(alignment: .bottom) { rowDivider }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.rowBorder)
            .frame(height: 1)
    }

    private struct PendingETFDelete: Identifiable {
        let index: Int
        let etf: ETF

        var id: String { "\(index)-\(etf.code)" }
    }
}
