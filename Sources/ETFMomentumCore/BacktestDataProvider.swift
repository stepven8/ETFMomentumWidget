import Foundation

public actor EasyTDXBacktestDataProvider {
    private let provider: EasyTDXProvider
    private let store: BacktestSQLiteStore
    private let calendar: Calendar

    public init(provider: EasyTDXProvider = EasyTDXProvider(timeoutSeconds: 12), store: BacktestSQLiteStore) {
        self.provider = provider
        self.store = store
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        self.calendar = calendar
    }

    public func ensureData(etfs: [ETF], benchmark: ETF, config: BacktestConfig, progress: (@Sendable (BacktestProgress) async -> Void)? = nil) async throws {
        var symbols = etfs
        if !symbols.contains(where: { $0.code == benchmark.code }) {
            symbols.append(benchmark)
        }
        if !symbols.contains(where: { $0.code == "511880.XSHG" }) {
            symbols.append(ETF(code: "511880.XSHG", name: "银华日利"))
        }

        let dailyStart = calendar.date(byAdding: .day, value: -180, to: config.startDate) ?? config.startDate
        var usableCount = 0
        for (index, etf) in symbols.enumerated() {
            try Task.checkCancellation()
            let baseProgress = Double(index) / Double(max(symbols.count, 1))
            do {
                await progress?(BacktestProgress(message: "补充 \(etf.eastmoneyCode) 日线", detail: "\(index + 1)/\(symbols.count) \(etf.name)", fraction: baseProgress))
                let dailyStatus = try await fetchAndStore(etf: etf, period: "DAILY", count: 900, start: dailyStart, end: config.endDate, adjust: "QFQ", barTime: nil)
                if dailyStatus == .cached {
                    await progress?(BacktestProgress(message: "已缓存 \(etf.eastmoneyCode) 日线", detail: "\(index + 1)/\(symbols.count) \(etf.name)", fraction: baseProgress + 0.25 / Double(max(symbols.count, 1))))
                }
                await progress?(BacktestProgress(message: "补充 \(etf.eastmoneyCode) \(config.period.displayName) K线", detail: "\(index + 1)/\(symbols.count) \(etf.name)", fraction: baseProgress + 0.5 / Double(max(symbols.count, 1))))
                let minuteCount = max(1200, estimatedMinuteCount(start: config.startDate, end: config.endDate, period: config.period) + 300)
                let minuteStatus = try await fetchAndStore(etf: etf, period: config.period.rawValue, count: minuteCount, start: config.startDate, end: config.endDate, adjust: nil, barTime: "end")
                if minuteStatus == .cached {
                    await progress?(BacktestProgress(message: "已缓存 \(etf.eastmoneyCode) \(config.period.displayName) K线", detail: "\(index + 1)/\(symbols.count) \(etf.name)", fraction: baseProgress + 0.75 / Double(max(symbols.count, 1))))
                }
                usableCount += 1
            } catch {
                if etf.code == benchmark.code {
                    throw error
                }
                await progress?(BacktestProgress(message: "跳过 \(etf.eastmoneyCode)", detail: readable(error), fraction: Double(index + 1) / Double(max(symbols.count, 1))))
            }
        }
        guard usableCount > 0 else { throw MarketDataError.missingData }
    }

    public func dailyBars(etf: ETF, upTo date: Date, lookback: Int) throws -> [KLine] {
        let start = calendar.date(byAdding: .day, value: -max(lookback * 3, 90), to: date) ?? date
        return try Array(store.bars(symbol: etf.code, period: "DAILY", start: start, end: date).suffix(lookback))
    }

    public func minuteBars(etf: ETF, config: BacktestConfig) throws -> [KLine] {
        try store.bars(symbol: etf.code, period: config.period.rawValue, start: config.startDate, end: endOfDay(config.endDate))
    }

    public func latestBar(etf: ETF, atOrBefore date: Date, period: BacktestPeriod) throws -> KLine? {
        let start = calendar.date(byAdding: .day, value: -7, to: date) ?? date
        if let minuteBar = try store.bars(symbol: etf.code, period: period.rawValue, start: start, end: date).last {
            return minuteBar
        }
        return try latestDailyBar(etf: etf, atOrBefore: date)
    }

    public func minuteVolume(etf: ETF, on day: Date, through date: Date, period: BacktestPeriod) throws -> Double? {
        let start = calendar.startOfDay(for: day)
        let sum = try store.bars(symbol: etf.code, period: period.rawValue, start: start, end: date).map(\.volume).reduce(0, +)
        return sum > 0 ? sum : nil
    }

    public func tradingDays(config: BacktestConfig) throws -> [Date] {
        let bars = try store.bars(symbol: config.benchmark.code, period: "DAILY", start: config.startDate, end: config.endDate)
        return bars.map { calendar.startOfDay(for: $0.date) }
    }

    private func latestDailyBar(etf: ETF, atOrBefore date: Date) throws -> KLine? {
        let start = calendar.date(byAdding: .day, value: -14, to: date) ?? date
        let end = endOfDay(date)
        return try store.bars(symbol: etf.code, period: "DAILY", start: start, end: end).last
    }

    private func fetchAndStore(etf: ETF, period: String, count: Int, start: Date, end: Date, adjust: String?, barTime: String?) async throws -> CacheFillStatus {
        let existing = try store.bars(symbol: etf.code, period: period, start: start, end: endOfDay(end))
        if hasSufficientCache(existing, period: period, start: start, end: end) {
            return .cached
        }
        var all: [KLine] = []
        var offset = 0
        let pageSize = min(max(count, 1), 800)
        while offset < count {
            try Task.checkCancellation()
            let page = try await provider.kLines(for: etf, period: period, count: pageSize, startOffset: offset, adjust: adjust, barTime: barTime)
            if page.isEmpty { break }
            all.append(contentsOf: page)
            if let earliest = page.map(\.date).min(), earliest <= start {
                break
            }
            offset += pageSize
            if page.count < pageSize { break }
        }
        let filtered = all
            .filter { $0.date >= start && $0.date <= endOfDay(end) }
            .sorted { $0.date < $1.date }
        try store.saveBars(filtered, symbol: etf.code, period: period)
        return .downloaded
    }

    private func estimatedMinuteCount(start: Date, end: Date, period: BacktestPeriod) -> Int {
        let days = max(calendar.dateComponents([.day], from: start, to: end).day ?? 1, 1)
        return Int(Double(days) / 7.0 * 5.0 * 240.0 / Double(period.minutes))
    }

    private func endOfDay(_ date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private func hasSufficientCache(_ bars: [KLine], period: String, start: Date, end: Date) -> Bool {
        guard !bars.isEmpty else { return false }
        if period == "DAILY" {
            let startDay = calendar.startOfDay(for: start)
            let endDay = calendar.startOfDay(for: end)
            let days = Set(bars.map { calendar.startOfDay(for: $0.date) })
            guard let firstDay = days.min(), let lastDay = days.max() else { return false }
            let toleratedStart = calendar.date(byAdding: .day, value: 14, to: startDay) ?? startDay
            let toleratedEnd = calendar.date(byAdding: .day, value: -7, to: endDay) ?? endDay
            return firstDay <= toleratedStart && lastDay >= toleratedEnd
        }

        let grouped = Dictionary(grouping: bars) { calendar.startOfDay(for: $0.date) }
        let expectedDays = tradingWeekdays(start: start, end: end)
        guard !expectedDays.isEmpty else { return true }
        let minimumBars = max(180 / max(BacktestPeriod(rawValue: period)?.minutes ?? 1, 1), 3)
        for day in expectedDays {
            guard let dayBars = grouped[day], dayBars.count >= minimumBars else {
                return false
            }
        }
        return true
    }

    private func tradingWeekdays(start: Date, end: Date) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while cursor <= endDay {
            if !calendar.isDateInWeekend(cursor) {
                days.append(cursor)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? endDay.addingTimeInterval(86_400)
        }
        return days
    }
}

private enum CacheFillStatus {
    case cached
    case downloaded
}

public struct BacktestProgress: Codable, Equatable, Sendable {
    public var message: String
    public var detail: String
    public var fraction: Double

    public init(message: String, detail: String = "", fraction: Double = 0) {
        self.message = message
        self.detail = detail
        self.fraction = min(max(fraction, 0), 1)
    }
}

private func readable(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return String(describing: error)
}

public struct BacktestHistoricalProvider: MarketDataProvider {
    public var dataProvider: EasyTDXBacktestDataProvider
    public var currentDate: Date
    public var period: BacktestPeriod

    public init(dataProvider: EasyTDXBacktestDataProvider, currentDate: Date, period: BacktestPeriod) {
        self.dataProvider = dataProvider
        self.currentDate = currentDate
        self.period = period
    }

    public func quote(for etf: ETF) async throws -> Quote {
        guard let bar = try await dataProvider.latestBar(etf: etf, atOrBefore: currentDate, period: period) else {
            throw MarketDataError.missingData
        }
        return Quote(code: etf.code, name: etf.name, lastPrice: bar.close, pctChange: bar.pctChange, volume: bar.volume, paused: bar.close <= 0)
    }

    public func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        let bars = try await dataProvider.dailyBars(etf: etf, upTo: currentDate, lookback: limit)
        guard !bars.isEmpty else { throw MarketDataError.missingData }
        return MomentumMath.withDailyPctChange(bars)
    }

    public func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        try await dataProvider.minuteVolume(etf: etf, on: now, through: currentDate, period: period)
    }

    public func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        PremiumInfo(premium: nil, price: nil, netValue: nil)
    }

    public func previousTradingDate(beforeOrOn date: Date) async -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
    }
}
