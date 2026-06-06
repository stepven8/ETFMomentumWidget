import ETFMomentumCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section("排名参数") {
                Stepper("动量窗口 lookback_days: \(store.config.lookbackDays)", value: $store.config.lookbackDays, in: 5...120)
                Stepper("持仓数量 holdings_num: \(store.config.holdingsNum)", value: $store.config.holdingsNum, in: 1...10)
                numberField("最低分", value: $store.config.minScoreThreshold)
                numberField("最高分", value: $store.config.maxScoreThreshold)
                numberField("近三日跌幅 loss", value: $store.config.loss)
            }
            Section("成交量过滤") {
                Toggle("启用成交量过滤", isOn: $store.config.enableVolumeCheck)
                Stepper("成交量回看: \(store.config.volumeLookback)", value: $store.config.volumeLookback, in: 1...30)
                numberField("量比阈值", value: $store.config.volumeThreshold)
                numberField("年化收益上限", value: $store.config.volumeReturnLimit)
            }
            Section("短期动量与保护") {
                Toggle("启用短期动量过滤", isOn: $store.config.useShortMomentumFilter)
                Stepper("短期窗口: \(store.config.shortLookbackDays)", value: $store.config.shortLookbackDays, in: 2...60)
                numberField("短期年化阈值", value: $store.config.shortMomentumThreshold)
                Toggle("启用盈利保护", isOn: $store.config.enableProfitProtection)
                Stepper("盈利保护回看: \(store.config.profitProtectionLookback)", value: $store.config.profitProtectionLookback, in: 1...20)
                numberField("盈利保护阈值", value: $store.config.profitProtectionThreshold)
            }
            Section("溢价过滤") {
                Toggle("启用溢价过滤", isOn: $store.config.enablePremiumFilter)
                numberField("溢价阈值", value: $store.config.premiumThreshold)
            }
            Section("ETF 股票池") {
                ForEach($store.etfs) { $etf in
                    HStack {
                        Toggle("", isOn: $etf.enabled)
                            .labelsHidden()
                        TextField("代码", text: $etf.code)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 130)
                        TextField("名称", text: $etf.name)
                    }
                }
                Button {
                    store.etfs.append(ETF(code: "000000.XSHG", name: "新ETF"))
                } label: {
                    Label("新增 ETF", systemImage: "plus")
                }
            }
            Button {
                try? store.saveConfigAndPool()
            } label: {
                Label("保存设置", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
        .formStyle(.grouped)
        .padding()
        .background(Color.appBackground)
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
        }
    }
}
