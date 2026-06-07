import ETFMomentumCore
import AppKit
import SwiftUI

struct ETFDetailView: View {
    let etf: ETF
    @State private var klines: [KLine] = []
    @State private var selectedIndex: Int?
    @State private var visibleStart = 0
    @State private var visibleCount = 260
    @State private var isLoading = false

    private var selectedKLine: KLine? {
        guard let selectedIndex, klines.indices.contains(selectedIndex) else { return nil }
        return klines[selectedIndex]
    }

    private var visibleRangeText: String {
        guard !klines.isEmpty else { return "无数据" }
        let safeStart = min(max(visibleStart, 0), max(klines.count - 1, 0))
        let safeEnd = min(safeStart + max(visibleCount, 1), klines.count)
        return "\(safeEnd - safeStart)/\(klines.count) 根"
    }

    var body: some View {
        ScrollView {
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
                ChartPanel(title: "日 K 线", subtitle: "K 线 / 十字轴") {
                    VStack(spacing: 8) {
                        ChartZoomBar(
                            visibleText: visibleRangeText,
                            canZoomIn: visibleCount > minVisibleCount,
                            canZoomOut: visibleCount < klines.count,
                            zoomIn: { zoom(by: 0.72) },
                            zoomOut: { zoom(by: 1.38) },
                            reset: { resetZoom() }
                        )
                        CandleChart(
                            klines: klines,
                            selectedIndex: $selectedIndex,
                            visibleStart: $visibleStart,
                            visibleCount: $visibleCount
                        )
                        .frame(minHeight: 360)
                    }
                }
                ChartPanel(title: "成交量", subtitle: "红涨绿跌") {
                    VolumeChart(
                        klines: Array(klines[visibleRange]),
                        selectedIndex: localSelectedIndex,
                        globalStart: visibleRange.lowerBound,
                        onSelect: selectVisibleIndex,
                        onZoom: zoomByScroll
                    )
                    .frame(height: 120)
                }
                ChartPanel(title: "MACD", subtitle: "DIF / DEA / 柱") {
                    MACDChart(
                        points: Array(MomentumMath.macd(for: klines)[visibleRange]),
                        selectedIndex: localSelectedIndex,
                        dates: Array(klines[visibleRange].map(\.date)),
                        globalStart: visibleRange.lowerBound,
                        onSelect: selectVisibleIndex,
                        onZoom: zoomByScroll
                    )
                    .frame(height: 120)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            }
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
                visibleStart = 0
                visibleCount = lines.count
            }
        } catch {
            await MainActor.run {
                klines = []
                selectedIndex = nil
                visibleStart = 0
                visibleCount = 0
            }
        }
    }

    private var minVisibleCount: Int { min(30, max(klines.count, 1)) }

    private var visibleRange: Range<Int> {
        guard !klines.isEmpty else { return 0..<0 }
        let start = min(max(visibleStart, 0), max(klines.count - 1, 0))
        let end = min(start + max(visibleCount, 1), klines.count)
        return start..<end
    }

    private var localSelectedIndex: Int? {
        guard let selectedIndex, visibleRange.contains(selectedIndex) else { return nil }
        return selectedIndex - visibleRange.lowerBound
    }

    private func zoom(by factor: Double) {
        guard !klines.isEmpty else { return }
        let oldCount = max(visibleCount, minVisibleCount)
        let newCount = min(max(Int((Double(oldCount) * factor).rounded()), minVisibleCount), klines.count)
        guard newCount != oldCount else { return }
        let center = selectedIndex ?? min(visibleStart + oldCount / 2, klines.count - 1)
        visibleCount = newCount
        visibleStart = min(max(center - newCount / 2, 0), max(klines.count - newCount, 0))
    }

    private func zoomByScroll(_ delta: CGFloat) {
        guard abs(delta) >= 0.5 else { return }
        zoom(by: delta > 0 ? 0.88 : 1.12)
    }

    private func selectVisibleIndex(_ localIndex: Int) {
        guard !klines.isEmpty else { return }
        selectedIndex = min(max(visibleRange.lowerBound + localIndex, 0), klines.count - 1)
    }

    private func resetZoom() {
        visibleStart = 0
        visibleCount = klines.count
        selectedIndex = klines.isEmpty ? nil : klines.count - 1
    }
}

struct ChartZoomBar: View {
    let visibleText: String
    let canZoomIn: Bool
    let canZoomOut: Bool
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: zoomIn) { Image(systemName: "plus.magnifyingglass") }
                .help("放大")
                .disabled(!canZoomIn)
            Button(action: zoomOut) { Image(systemName: "minus.magnifyingglass") }
                .help("缩小")
                .disabled(!canZoomOut)
            Button(action: reset) { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                .help("显示全部")
            Text(visibleText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
    @Binding var visibleStart: Int
    @Binding var visibleCount: Int

    private var visibleRange: Range<Int> {
        guard !klines.isEmpty else { return 0..<0 }
        let start = min(max(visibleStart, 0), max(klines.count - 1, 0))
        let end = min(start + max(visibleCount, 1), klines.count)
        return start..<end
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let plotRect = ChartGeometry.plotRect(size: size, reservesDateAxis: true)
                guard !klines.isEmpty else {
                    drawEmptyState(context: context, size: size)
                    return
                }
                let range = visibleRange
                let visibleKLines = Array(klines[range])
                guard let minLow = visibleKLines.map(\.low).min(), let maxHigh = visibleKLines.map(\.high).max(), maxHigh > minLow else {
                    drawEmptyState(context: context, size: size)
                    return
                }
                drawGrid(context: context, size: size, plotRect: plotRect, minValue: minLow, maxValue: maxHigh)
                drawDateAxis(context: context, plotRect: plotRect, visibleKLines: visibleKLines, globalStart: range.lowerBound)
                let width = max(plotRect.width / CGFloat(max(visibleKLines.count, 1)), 2)
                for (localIndex, kline) in visibleKLines.enumerated() {
                    let index = range.lowerBound + localIndex
                    let x = plotRect.minX + CGFloat(localIndex) * width + width / 2
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
                drawMovingAverages(context: context, plotRect: plotRect, range: range, minValue: minLow, maxValue: maxHigh)
                drawSelection(context: context, plotRect: plotRect, count: visibleKLines.count, minValue: minLow, maxValue: maxHigh)
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
            .gesture(MagnificationGesture().onChanged { scale in
                updateZoom(scale: scale)
            })
            .background(ScrollWheelCaptureView { delta in
                updateZoom(scrollDelta: delta)
            })
        }
        .background(Color.chartBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func updateSelection(at x: CGFloat, size: CGSize) {
        let plotRect = ChartGeometry.plotRect(size: size, reservesDateAxis: true)
        guard let localIndex = ChartGeometry.indexForX(x, plotRect: plotRect, count: visibleRange.count) else { return }
        selectedIndex = min(visibleRange.lowerBound + localIndex, klines.count - 1)
    }

    private func updateZoom(scale: CGFloat) {
        guard !klines.isEmpty, scale > 0 else { return }
        let minCount = min(30, klines.count)
        let newCount = min(max(Int((Double(visibleCount) / Double(scale)).rounded()), minCount), klines.count)
        let center = selectedIndex ?? min(visibleStart + visibleCount / 2, klines.count - 1)
        visibleCount = newCount
        visibleStart = min(max(center - newCount / 2, 0), max(klines.count - newCount, 0))
    }

    private func updateZoom(scrollDelta: CGFloat) {
        guard abs(scrollDelta) >= 0.5 else { return }
        let factor = scrollDelta > 0 ? 0.88 : 1.12
        let scale = 1 / factor
        updateZoom(scale: scale)
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

    private func drawMovingAverages(context: GraphicsContext, plotRect: CGRect, range: Range<Int>, minValue: Double, maxValue: Double) {
        let specs: [(period: Int, color: Color)] = [
            (5, .ma5),
            (20, .ma20),
            (60, .ma60),
            (120, .ma120)
        ]
        for spec in specs {
            let values = MomentumMath.movingAverage(for: klines, period: spec.period)
            var path = Path()
            var hasPoint = false
            for globalIndex in range {
                guard let value = values[globalIndex] else { continue }
                let localIndex = globalIndex - range.lowerBound
                guard let x = ChartGeometry.xForIndex(localIndex, plotRect: plotRect, count: range.count) else { continue }
                let point = CGPoint(x: x, y: y(value, min: minValue, max: maxValue, plotRect: plotRect))
                if hasPoint {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    hasPoint = true
                }
            }
            context.stroke(path, with: .color(spec.color), lineWidth: 1.15)
        }
        drawMovingAverageLegend(context: context, plotRect: plotRect, range: range, specs: specs)
    }

    private func drawMovingAverageLegend(
        context: GraphicsContext,
        plotRect: CGRect,
        range: Range<Int>,
        specs: [(period: Int, color: Color)]
    ) {
        let selected = selectedIndex.flatMap { range.contains($0) ? $0 : nil } ?? max(range.upperBound - 1, range.lowerBound)
        var x = plotRect.minX + 8
        for spec in specs {
            let values = MomentumMath.movingAverage(for: klines, period: spec.period)
            let valueText = values.indices.contains(selected) ? values[selected]?.formatted(.number.precision(.fractionLength(3))) ?? "--" : "--"
            let text = Text("MA\(spec.period) \(valueText)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(spec.color)
            context.draw(text, at: CGPoint(x: x, y: plotRect.minY + 8), anchor: .topLeading)
            x += spec.period == 120 ? 86 : 78
        }
    }

    private func drawDateAxis(context: GraphicsContext, plotRect: CGRect, visibleKLines: [KLine], globalStart: Int) {
        var axis = Path()
        axis.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
        axis.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
        context.stroke(axis, with: .color(Color.gridLine.opacity(1.4)), lineWidth: 0.8)

        let indices = ChartGeometry.dateTickIndices(count: visibleKLines.count, plotWidth: plotRect.width)
        for localIndex in indices {
            guard let x = ChartGeometry.xForIndex(localIndex, plotRect: plotRect, count: visibleKLines.count) else { continue }
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: plotRect.maxY))
            tick.addLine(to: CGPoint(x: x, y: plotRect.maxY + 4))
            context.stroke(tick, with: .color(Color.gridLine), lineWidth: 0.7)
            let globalIndex = globalStart + localIndex
            let text = Text(formatDate(visibleKLines[localIndex].date, index: globalIndex))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
            let anchor: UnitPoint = localIndex == 0 ? .topLeading : (localIndex == visibleKLines.count - 1 ? .topTrailing : .top)
            context.draw(text, at: CGPoint(x: x, y: plotRect.maxY + 7), anchor: anchor)
        }
    }

    private func drawSelection(context: GraphicsContext, plotRect: CGRect, count: Int, minValue: Double, maxValue: Double) {
        guard let selectedIndex, visibleRange.contains(selectedIndex) else { return }
        let localIndex = selectedIndex - visibleRange.lowerBound
        guard let x = ChartGeometry.xForIndex(localIndex, plotRect: plotRect, count: count) else { return }
        var vertical = Path()
        vertical.move(to: CGPoint(x: x, y: plotRect.minY))
        vertical.addLine(to: CGPoint(x: x, y: plotRect.maxY))
        context.stroke(vertical, with: .color(Color.white.opacity(0.50)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        let close = klines[selectedIndex].close
        let closeY = y(close, min: minValue, max: maxValue, plotRect: plotRect)
        var horizontal = Path()
        horizontal.move(to: CGPoint(x: plotRect.minX, y: closeY))
        horizontal.addLine(to: CGPoint(x: plotRect.maxX, y: closeY))
        context.stroke(horizontal, with: .color(Color.white.opacity(0.38)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        let labelRect = CGRect(x: plotRect.maxX + 5, y: closeY - 10, width: 47, height: 20)
        context.fill(Path(roundedRect: labelRect, cornerRadius: 4), with: .color(Color.panelBackground.opacity(0.95)))
        context.stroke(Path(roundedRect: labelRect, cornerRadius: 4), with: .color(Color.white.opacity(0.18)), lineWidth: 0.7)
        let text = Text(close.formatted(.number.precision(.fractionLength(3))))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.textPrimary)
        context.draw(text, at: CGPoint(x: labelRect.midX, y: labelRect.midY + 1), anchor: .center)
    }

    private func drawMACD(context: GraphicsContext, plotRect: CGRect, points: [MACDPoint]) {
        guard points.count > 1 else { return }
        let allValues = points.flatMap { [$0.macd, $0.dif, $0.dea] }
        guard let minValue = allValues.min(), let maxValue = allValues.max(), maxValue != minValue else { return }
        let zeroY = macdY(0, min: minValue, max: maxValue, plotRect: plotRect)
        var zero = Path()
        zero.move(to: CGPoint(x: plotRect.minX, y: zeroY))
        zero.addLine(to: CGPoint(x: plotRect.maxX, y: zeroY))
        context.stroke(zero, with: .color(Color.gridLine), lineWidth: 0.7)

        let width = max(plotRect.width / CGFloat(points.count), 1)
        for (index, point) in points.enumerated() {
            let x = plotRect.minX + CGFloat(index) * width + width / 2
            let yValue = macdY(point.macd, min: minValue, max: maxValue, plotRect: plotRect)
            let rect = CGRect(x: x - width * 0.32, y: min(zeroY, yValue), width: max(width * 0.64, 1), height: max(abs(zeroY - yValue), 1))
            context.fill(Path(rect), with: .color((point.macd >= 0 ? Color.upRed : Color.downGreen).opacity(0.68)))
        }
        drawMACDLine(context: context, values: points.map(\.dif), color: .orange, plotRect: plotRect, minValue: minValue, maxValue: maxValue)
        drawMACDLine(context: context, values: points.map(\.dea), color: .cyan, plotRect: plotRect, minValue: minValue, maxValue: maxValue)
        let text = Text("MACD")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.textSecondary)
        context.draw(text, at: CGPoint(x: plotRect.minX + 5, y: plotRect.minY + 5), anchor: .topLeading)
    }

    private func drawMACDLine(context: GraphicsContext, values: [Double], color: Color, plotRect: CGRect, minValue: Double, maxValue: Double) {
        var path = Path()
        for (index, value) in values.enumerated() {
            guard let x = ChartGeometry.xForIndex(index, plotRect: plotRect, count: values.count) else { continue }
            let point = CGPoint(x: x, y: macdY(value, min: minValue, max: maxValue, plotRect: plotRect))
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        context.stroke(path, with: .color(color), lineWidth: 1.1)
    }

    private func macdY(_ value: Double, min: Double, max: Double, plotRect: CGRect) -> CGFloat {
        plotRect.maxY - CGFloat((value - min) / (max - min)) * plotRect.height
    }

    private func drawEmptyState(context: GraphicsContext, size: CGSize) {
        let text = Text("暂无 K 线数据")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.textSecondary)
        context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
    }

    private func formatDate(_ date: Date, index: Int) -> String {
        formatAxisDate(date, globalIndex: index, totalCount: klines.count)
    }
}

struct VolumeChart: View {
    let klines: [KLine]
    let selectedIndex: Int?
    let globalStart: Int
    let onSelect: (Int) -> Void
    let onZoom: (CGFloat) -> Void

    var body: some View {
        BarChart(
            values: klines.map(\.volume),
            colors: klines.map { $0.close >= $0.open ? Color.upRed : Color.downGreen },
            selectedIndex: selectedIndex,
            dates: klines.map(\.date),
            globalStart: globalStart,
            label: "成交量",
            onSelect: onSelect,
            onZoom: onZoom
        )
            .background(Color.chartBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct MACDChart: View {
    let points: [MACDPoint]
    let selectedIndex: Int?
    let dates: [Date]
    let globalStart: Int
    let onSelect: (Int) -> Void
    let onZoom: (CGFloat) -> Void

    var body: some View {
        GeometryReader { _ in
            BarChart(
                values: points.map(\.macd),
                colors: points.map { $0.macd >= 0 ? Color.upRed : Color.downGreen },
                selectedIndex: selectedIndex,
                dates: dates,
                globalStart: globalStart,
                label: "MACD",
                onSelect: onSelect,
                onZoom: onZoom
            )
                .overlay {
                    LineChart(values: points.map(\.dif), color: .orange, selectedIndex: nil, reservesDateAxis: true, reservesPriceAxis: true)
                    LineChart(values: points.map(\.dea), color: .cyan, selectedIndex: nil, reservesDateAxis: true, reservesPriceAxis: true)
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
    var dates: [Date] = []
    var globalStart: Int = 0
    var label: String? = nil
    var onSelect: ((Int) -> Void)? = nil
    var onZoom: ((CGFloat) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let plotRect = ChartGeometry.plotRect(size: size, reservesDateAxis: true)
                guard let maxValue = values.map(abs).max(), maxValue > 0 else {
                    drawEmptyState(context: context, size: size)
                    return
                }
                drawHorizontalGuide(context: context, plotRect: plotRect, allPositive: values.allSatisfy { $0 >= 0 })
                let zero = plotRect.midY
                let allPositive = values.allSatisfy { $0 >= 0 }
                let base = allPositive ? plotRect.maxY : zero
                let width = max(plotRect.width / CGFloat(max(values.count, 1)), 1)
                for (index, value) in values.enumerated() {
                    let h = CGFloat(abs(value) / maxValue) * (allPositive ? plotRect.height : plotRect.height / 2)
                    let y = value >= 0 ? base - h : base
                    let rect = CGRect(x: plotRect.minX + CGFloat(index) * width, y: y, width: max(width * 0.72, 1), height: max(h, 1))
                    context.fill(Path(rect), with: .color(colors[index].opacity(0.75)))
                }
                drawLabel(context: context, plotRect: plotRect)
                drawSelection(context: context, plotRect: plotRect, count: values.count)
                drawDateAxis(context: context, plotRect: plotRect)
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
            .background(ScrollWheelCaptureView { delta in
                onZoom?(delta)
            })
        }
    }

    private func updateSelection(at x: CGFloat, size: CGSize) {
        let plotRect = ChartGeometry.plotRect(size: size, reservesDateAxis: true)
        guard let index = ChartGeometry.indexForX(x, plotRect: plotRect, count: values.count) else { return }
        onSelect?(index)
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

    private func drawDateAxis(context: GraphicsContext, plotRect: CGRect) {
        guard !dates.isEmpty else { return }
        var axis = Path()
        axis.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
        axis.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
        context.stroke(axis, with: .color(Color.gridLine.opacity(1.4)), lineWidth: 0.8)

        let indices = ChartGeometry.dateTickIndices(count: dates.count, plotWidth: plotRect.width)
        for localIndex in indices {
            guard dates.indices.contains(localIndex),
                  let x = ChartGeometry.xForIndex(localIndex, plotRect: plotRect, count: dates.count) else { continue }
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: plotRect.maxY))
            tick.addLine(to: CGPoint(x: x, y: plotRect.maxY + 4))
            context.stroke(tick, with: .color(Color.gridLine), lineWidth: 0.7)
            let text = Text(formatAxisDate(dates[localIndex], globalIndex: globalStart + localIndex, totalCount: dates.count))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
            let anchor: UnitPoint = localIndex == 0 ? .topLeading : (localIndex == dates.count - 1 ? .topTrailing : .top)
            context.draw(text, at: CGPoint(x: x, y: plotRect.maxY + 7), anchor: anchor)
        }
    }

    private func drawLabel(context: GraphicsContext, plotRect: CGRect) {
        guard let label else { return }
        let text = Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.textSecondary)
        context.draw(text, at: CGPoint(x: plotRect.minX + 5, y: plotRect.minY + 5), anchor: .topLeading)
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
    var reservesDateAxis: Bool = false
    var reservesPriceAxis: Bool = false

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let plotRect = ChartGeometry.plotRect(size: size, reservesDateAxis: reservesDateAxis, reservesPriceAxis: reservesPriceAxis)
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

struct ScrollWheelCaptureView: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class ScrollWheelView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            onScroll?(event.scrollingDeltaY)
        }
    }
}

private func formatAxisDate(_ date: Date, globalIndex: Int, totalCount: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = globalIndex == 0 || globalIndex == totalCount - 1 ? "yyyy/MM" : "MM/dd"
    return formatter.string(from: date)
}

private func y(_ value: Double, min: Double, max: Double, plotRect: CGRect) -> CGFloat {
    plotRect.maxY - CGFloat((value - min) / (max - min)) * plotRect.height
}

private extension Color {
    static let chartBackground = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let gridLine = Color.white.opacity(0.10)
    static let ma5 = Color(red: 1.00, green: 0.82, blue: 0.24)
    static let ma20 = Color(red: 0.86, green: 0.48, blue: 1.00)
    static let ma60 = Color(red: 0.36, green: 0.76, blue: 1.00)
    static let ma120 = Color(red: 0.62, green: 0.84, blue: 0.78)
}
