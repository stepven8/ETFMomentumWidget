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
                        .foregroundStyle(Color.textPrimary)
                    Text(etf.code)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
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

            VStack(spacing: 12) {
                ChartPanel(title: "日 K 线", subtitle: "最近一年") {
                    CandleChart(klines: klines, selected: $selected)
                        .frame(minHeight: 352)
                }
                ChartPanel(title: "成交量", subtitle: "红涨绿跌") {
                    VolumeChart(klines: klines)
                        .frame(height: 110)
                }
                ChartPanel(title: "MACD", subtitle: "DIF / DEA / MACD") {
                    MACDChart(points: MomentumMath.macd(for: klines))
                        .frame(height: 118)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
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
        HStack(spacing: 14) {
            Text(kline.date.formatted(date: .numeric, time: .omitted))
            value("开", kline.open)
            value("高", kline.high)
            value("低", kline.low)
            value("收", kline.close)
            value("量", kline.volume)
            Text("涨跌 \(kline.pctChange.formatted(.number.precision(.fractionLength(2))))%")
                .foregroundStyle(kline.pctChange >= 0 ? Color.upRed : Color.downGreen)
        }
        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.rowBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func value(_ label: String, _ value: Double) -> some View {
        Text("\(label) \(value.formatted(.number.precision(.fractionLength(3))))")
    }
}

struct ChartPanel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
            content
        }
        .padding(10)
        .background(Color.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.rowBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CandleChart: View {
    let klines: [KLine]
    @Binding var selected: KLine?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard let minLow = klines.map(\.low).min(), let maxHigh = klines.map(\.high).max(), maxHigh > minLow else { return }
                drawGrid(context: context, size: size, minValue: minLow, maxValue: maxHigh)
                let plotWidth = size.width - 54
                let width = max(plotWidth / CGFloat(max(klines.count, 1)), 2)
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
                let usableWidth = max(proxy.size.width - 54, 1)
                let index = min(max(Int(value.location.x / max(usableWidth / CGFloat(klines.count), 1)), 0), klines.count - 1)
                selected = klines[index]
            })
        }
        .background(Color.chartBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func y(_ value: Double, min: Double, max: Double, height: CGFloat) -> CGFloat {
        height - CGFloat((value - min) / (max - min)) * height
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, minValue: Double, maxValue: Double) {
        let formatter = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        for step in 0...4 {
            let fraction = CGFloat(step) / 4
            let y = fraction * size.height
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width - 48, y: y))
            context.stroke(path, with: .color(Color.gridLine), lineWidth: 0.7)
            let value = maxValue - Double(fraction) * (maxValue - minValue)
            let text = Text(value.formatted(formatter))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
            context.draw(text, at: CGPoint(x: size.width - 24, y: y + 7), anchor: .center)
        }
    }
}

struct VolumeChart: View {
    let klines: [KLine]

    var body: some View {
        BarChart(values: klines.map(\.volume), colors: klines.map { $0.close >= $0.open ? Color.upRed : Color.downGreen })
            .background(Color.chartBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
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
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct BarChart: View {
    let values: [Double]
    let colors: [Color]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard let maxValue = values.map(abs).max(), maxValue > 0 else { return }
                drawHorizontalGuide(context: context, size: size, allPositive: values.allSatisfy { $0 >= 0 })
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

    private func drawHorizontalGuide(context: GraphicsContext, size: CGSize, allPositive: Bool) {
        let y = allPositive ? size.height : size.height / 2
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(path, with: .color(Color.gridLine), lineWidth: 0.7)
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
        let recent = Array(values.suffix(30))
        let isUp = (recent.last ?? 0) >= (recent.first ?? 0)
        LineChart(values: recent, color: isUp ? .upRed : .downGreen)
            .background(Color.chartBackground.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private extension Color {
    static let chartBackground = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let gridLine = Color.white.opacity(0.10)
}
