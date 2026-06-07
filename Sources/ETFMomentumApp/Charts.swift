import ETFMomentumCore
import SwiftUI

struct ETFDetailView: View {
    let etf: ETF
    @State private var klines: [KLine] = []
    @State private var selectedIndex: Int?
    @State private var isLoading = false

    private var selectedKLine: KLine? {
        guard let selectedIndex, klines.indices.contains(selectedIndex) else { return nil }
        return klines[selectedIndex]
    }

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

            if let selected = selectedKLine {
                CandleInfoBar(kline: selected)
                    .padding(.horizontal, 20)
            }

            VStack(spacing: 12) {
                ChartPanel(title: "日 K 线", subtitle: "最近一年") {
                    CandleChart(klines: klines, selectedIndex: $selectedIndex)
                        .frame(minHeight: 352)
                }
                ChartPanel(title: "成交量", subtitle: "红涨绿跌") {
                    VolumeChart(klines: klines, selectedIndex: selectedIndex)
                        .frame(height: 110)
                }
                ChartPanel(title: "MACD", subtitle: "DIF / DEA / MACD") {
                    MACDChart(points: MomentumMath.macd(for: klines), selectedIndex: selectedIndex)
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
                selectedIndex = lines.isEmpty ? nil : lines.count - 1
            }
        } catch {
            await MainActor.run {
                klines = []
                selectedIndex = nil
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
    @Binding var selectedIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let plotRect = ChartGeometry.plotRect(size: size, reservesDateAxis: true)
                guard !klines.isEmpty else {
                    drawEmptyState(context: context, size: size)
                    return
                }
                guard let minLow = klines.map(\.low).min(), let maxHigh = klines.map(\.high).max(), maxHigh > minLow else {
                    drawEmptyState(context: context, size: size)
                    return
                }
                drawGrid(context: context, size: size, plotRect: plotRect, minValue: minLow, maxValue: maxHigh)
                drawDateAxis(context: context, size: size, plotRect: plotRect)
                let width = max(plotRect.width / CGFloat(max(klines.count, 1)), 2)
                for (index, kline) in klines.enumerated() {
                    let x = plotRect.minX + CGFloat(index) * width + width / 2
                    let highY = y(kline.high, min: minLow, max: maxHigh, plotRect: plotRect)
                    let lowY = y(kline.low, min: minLow, max: maxHigh, plotRect: plotRect)
                    let openY = y(kline.open, min: minLow, max: maxHigh, plotRect: plotRect)
                    let closeY = y(kline.close, min: minLow, max: maxHigh, plotRect: plotRect)
                    let color = kline.close >= kline.open ? Color.upRed : Color.downGreen
                    var wick = Path()
                    wick.move(to: CGPoint(x: x, y: highY))
                    wick.addLine(to: CGPoint(x: x, y: lowY))
                    context.stroke(wick, with: .color(color), lineWidth: 1)
                    let bodyTop = min(openY, closeY)
                    let bodyHeight = max(abs(openY - closeY), 1)
                    let rect = CGRect(x: x - width * 0.35, y: bodyTop, width: max(width * 0.7, 1), height: bodyHeight)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(0.88)))
                    if index == selectedIndex {
                        context.stroke(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 2), with: .color(Color.white.opacity(0.82)), lineWidth: 1)
                    }
                }
                drawSelection(context: context, plotRect: plotRect, count: klines.count)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case let .active(location) = phase {
                    updateSelection(at: location.x, size: proxy.size)
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                updateSelection(at: value.location.x, size: proxy.size)
            })
        }
        .background(Color.chartBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func updateSelection(at x: CGFloat, size: CGSize) {
        let plotRect = ChartGeometry.plotRect(size: size, reservesDateAxis: true)
        selectedIndex = ChartGeometry.indexForX(x, plotRect: plotRect, count: klines.count)
    }

    private func y(_ value: Double, min: Double, max: Double, plotRect: CGRect) -> CGFloat {
        plotRect.maxY - CGFloat((value - min) / (max - min)) * plotRect.height
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, plotRect: CGRect, minValue: Double, maxValue: Double) {
        let formatter = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        for step in 0...4 {
            let fraction = CGFloat(step) / 4
            let y = plotRect.minY + fraction * plotRect.height
            var path = Path()
            path.move(to: CGPoint(x: plotRect.minX, y: y))
            path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.stroke(path, with: .color(Color.gridLine), lineWidth: 0.7)
            let value = maxValue - Double(fraction) * (maxValue - minValue)
            let text = Text(value.formatted(formatter))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
            context.draw(text, at: CGPoint(x: size.width - 24, y: y + 7), anchor: .center)
        }
    }

    private func drawDateAxis(context: GraphicsContext, size: CGSize, plotRect: CGRect) {
        var axis = Path()
        axis.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
        axis.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
        context.stroke(axis, with: .color(Color.gridLine.opacity(1.4)), lineWidth: 0.8)

        let indices = ChartGeometry.dateTickIndices(count: klines.count, plotWidth: plotRect.width)
        for index in indices {
            guard let x = ChartGeometry.xForIndex(index, plotRect: plotRect, count: klines.count) else { continue }
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: plotRect.maxY))
            tick.addLine(to: CGPoint(x: x, y: plotRect.maxY + 4))
            context.stroke(tick, with: .color(Color.gridLine), lineWidth: 0.7)
            let text = Text(formatDate(klines[index].date, index: index))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
            let anchor: UnitPoint = index == 0 ? .topLeading : (index == klines.count - 1 ? .topTrailing : .top)
            context.draw(text, at: CGPoint(x: x, y: plotRect.maxY + 7), anchor: anchor)
        }
    }

    private func drawSelection(context: GraphicsContext, plotRect: CGRect, count: Int) {
        guard let selectedIndex, let x = ChartGeometry.xForIndex(selectedIndex, plotRect: plotRect, count: count) else { return }
        var path = Path()
        path.move(to: CGPoint(x: x, y: plotRect.minY))
        path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
        context.stroke(path, with: .color(Color.white.opacity(0.48)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private func drawEmptyState(context: GraphicsContext, size: CGSize) {
        let text = Text("暂无 K 线数据")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.textSecondary)
        context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
    }

    private func formatDate(_ date: Date, index: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = index == 0 || index == klines.count - 1 ? "yyyy/MM" : "MM/dd"
        return formatter.string(from: date)
    }
}

struct VolumeChart: View {
    let klines: [KLine]
    let selectedIndex: Int?

    var body: some View {
        BarChart(values: klines.map(\.volume), colors: klines.map { $0.close >= $0.open ? Color.upRed : Color.downGreen }, selectedIndex: selectedIndex)
            .background(Color.chartBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct MACDChart: View {
    let points: [MACDPoint]
    let selectedIndex: Int?

    var body: some View {
        GeometryReader { _ in
            BarChart(values: points.map(\.macd), colors: points.map { $0.macd >= 0 ? Color.upRed : Color.downGreen }, selectedIndex: selectedIndex)
                .overlay {
                    LineChart(values: points.map(\.dif), color: .orange, selectedIndex: nil)
                    LineChart(values: points.map(\.dea), color: .cyan, selectedIndex: nil)
                }
        }
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct BarChart: View {
    let values: [Double]
    let colors: [Color]
    let selectedIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let plotRect = ChartGeometry.plotRect(size: size, reservesDateAxis: false)
                guard let maxValue = values.map(abs).max(), maxValue > 0 else {
                    drawEmptyState(context: context, size: size)
                    return
                }
                drawHorizontalGuide(context: context, plotRect: plotRect, allPositive: values.allSatisfy { $0 >= 0 })
                let zero = size.height / 2
                let allPositive = values.allSatisfy { $0 >= 0 }
                let base = allPositive ? size.height : zero
                let width = max(plotRect.width / CGFloat(max(values.count, 1)), 1)
                for (index, value) in values.enumerated() {
                    let h = CGFloat(abs(value) / maxValue) * (allPositive ? plotRect.height : plotRect.height / 2)
                    let y = value >= 0 ? base - h : base
                    let rect = CGRect(x: CGFloat(index) * width, y: y, width: max(width * 0.72, 1), height: max(h, 1))
                    context.fill(Path(rect), with: .color(colors[index].opacity(0.75)))
                }
                drawSelection(context: context, plotRect: plotRect, count: values.count)
            }
        }
    }

    private func drawHorizontalGuide(context: GraphicsContext, plotRect: CGRect, allPositive: Bool) {
        let y = allPositive ? plotRect.maxY : plotRect.midY
        var path = Path()
        path.move(to: CGPoint(x: plotRect.minX, y: y))
        path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        context.stroke(path, with: .color(Color.gridLine), lineWidth: 0.7)
    }

    private func drawSelection(context: GraphicsContext, plotRect: CGRect, count: Int) {
        guard let selectedIndex, let x = ChartGeometry.xForIndex(selectedIndex, plotRect: plotRect, count: count) else { return }
        var path = Path()
        path.move(to: CGPoint(x: x, y: plotRect.minY))
        path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
        context.stroke(path, with: .color(Color.white.opacity(0.36)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private func drawEmptyState(context: GraphicsContext, size: CGSize) {
        let text = Text("暂无数据")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.textSecondary)
        context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
    }
}

struct LineChart: View {
    let values: [Double]
    let color: Color
    var selectedIndex: Int? = nil

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let plotRect = ChartGeometry.plotRect(size: size, reservesDateAxis: false)
                guard values.count > 1, let minValue = values.min(), let maxValue = values.max(), maxValue != minValue else { return }
                var path = Path()
                for (index, value) in values.enumerated() {
                    let x = ChartGeometry.xForIndex(index, plotRect: plotRect, count: values.count) ?? 0
                    let y = plotRect.maxY - CGFloat((value - minValue) / (maxValue - minValue)) * plotRect.height
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(path, with: .color(color), lineWidth: 1.2)
                drawSelection(context: context, plotRect: plotRect, count: values.count)
            }
        }
    }

    private func drawSelection(context: GraphicsContext, plotRect: CGRect, count: Int) {
        guard let selectedIndex, let x = ChartGeometry.xForIndex(selectedIndex, plotRect: plotRect, count: count) else { return }
        var path = Path()
        path.move(to: CGPoint(x: x, y: plotRect.minY))
        path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
        context.stroke(path, with: .color(Color.white.opacity(0.30)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        let recent = Array(values.suffix(30))
        let isUp = (recent.last ?? 0) >= (recent.first ?? 0)
        LineChart(values: recent, color: isUp ? .upRed : .downGreen, selectedIndex: nil)
            .background(Color.chartBackground.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private extension Color {
    static let chartBackground = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let gridLine = Color.white.opacity(0.10)
}
