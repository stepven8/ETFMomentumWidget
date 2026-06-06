import ETFMomentumCore
import SwiftUI

struct ETFDetailView: View {
    let etf: ETF
    @State private var klines: [KLine] = []
    @State private var selected: KLine?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(etf.name)
                        .font(.system(size: 24, weight: .semibold))
                    Text(etf.code)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            if let selected {
                CandleInfoBar(kline: selected)
                    .padding(.horizontal, 20)
            }

            VStack(spacing: 10) {
                CandleChart(klines: klines, selected: $selected)
                    .frame(minHeight: 360)
                VolumeChart(klines: klines)
                    .frame(height: 120)
                MACDChart(points: MomentumMath.macd(for: klines))
                    .frame(height: 120)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.appBackground)
        .task(id: etf.code) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let lines = try await FallbackMarketDataProvider().dailyKLines(for: etf, limit: 260)
            await MainActor.run {
                klines = lines
                selected = lines.last
            }
        } catch {
            await MainActor.run {
                klines = []
                selected = nil
            }
        }
    }
}

struct CandleInfoBar: View {
    let kline: KLine

    var body: some View {
        HStack(spacing: 18) {
            Text(kline.date.formatted(date: .numeric, time: .omitted))
            value("开", kline.open)
            value("高", kline.high)
            value("低", kline.low)
            value("收", kline.close)
            value("量", kline.volume)
            Text("涨跌 \(kline.pctChange.formatted(.number.precision(.fractionLength(2))))%")
                .foregroundStyle(kline.pctChange >= 0 ? Color.upRed : Color.downGreen)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(10)
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func value(_ label: String, _ value: Double) -> some View {
        Text("\(label) \(value.formatted(.number.precision(.fractionLength(3))))")
    }
}

struct CandleChart: View {
    let klines: [KLine]
    @Binding var selected: KLine?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard let minLow = klines.map(\.low).min(), let maxHigh = klines.map(\.high).max(), maxHigh > minLow else { return }
                let width = max(size.width / CGFloat(max(klines.count, 1)), 2)
                for (index, kline) in klines.enumerated() {
                    let x = CGFloat(index) * width + width / 2
                    let highY = y(kline.high, min: minLow, max: maxHigh, height: size.height)
                    let lowY = y(kline.low, min: minLow, max: maxHigh, height: size.height)
                    let openY = y(kline.open, min: minLow, max: maxHigh, height: size.height)
                    let closeY = y(kline.close, min: minLow, max: maxHigh, height: size.height)
                    let color = kline.close >= kline.open ? Color.upRed : Color.downGreen
                    var wick = Path()
                    wick.move(to: CGPoint(x: x, y: highY))
                    wick.addLine(to: CGPoint(x: x, y: lowY))
                    context.stroke(wick, with: .color(color), lineWidth: 1)
                    let bodyTop = min(openY, closeY)
                    let bodyHeight = max(abs(openY - closeY), 1)
                    let rect = CGRect(x: x - width * 0.35, y: bodyTop, width: max(width * 0.7, 1), height: bodyHeight)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(0.88)))
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !klines.isEmpty else { return }
                let index = min(max(Int(value.location.x / max(proxy.size.width / CGFloat(klines.count), 1)), 0), klines.count - 1)
                selected = klines[index]
            })
        }
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func y(_ value: Double, min: Double, max: Double, height: CGFloat) -> CGFloat {
        height - CGFloat((value - min) / (max - min)) * height
    }
}

struct VolumeChart: View {
    let klines: [KLine]

    var body: some View {
        BarChart(values: klines.map(\.volume), colors: klines.map { $0.close >= $0.open ? Color.upRed : Color.downGreen })
            .background(Color.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MACDChart: View {
    let points: [MACDPoint]

    var body: some View {
        GeometryReader { _ in
            BarChart(values: points.map(\.macd), colors: points.map { $0.macd >= 0 ? Color.upRed : Color.downGreen })
                .overlay {
                    LineChart(values: points.map(\.dif), color: .orange)
                    LineChart(values: points.map(\.dea), color: .cyan)
                }
        }
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct BarChart: View {
    let values: [Double]
    let colors: [Color]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard let maxValue = values.map(abs).max(), maxValue > 0 else { return }
                let zero = size.height / 2
                let allPositive = values.allSatisfy { $0 >= 0 }
                let base = allPositive ? size.height : zero
                let width = max(size.width / CGFloat(max(values.count, 1)), 1)
                for (index, value) in values.enumerated() {
                    let h = CGFloat(abs(value) / maxValue) * (allPositive ? size.height : size.height / 2)
                    let y = value >= 0 ? base - h : base
                    let rect = CGRect(x: CGFloat(index) * width, y: y, width: max(width * 0.72, 1), height: max(h, 1))
                    context.fill(Path(rect), with: .color(colors[index].opacity(0.75)))
                }
            }
        }
    }
}

struct LineChart: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                guard values.count > 1, let minValue = values.min(), let maxValue = values.max(), maxValue != minValue else { return }
                var path = Path()
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
                    let y = size.height - CGFloat((value - minValue) / (maxValue - minValue)) * size.height
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(path, with: .color(color), lineWidth: 1.2)
            }
        }
    }
}

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        LineChart(values: values.suffix(30).map { $0 }, color: values.last ?? 0 >= values.first ?? 0 ? .upRed : .downGreen)
    }
}
