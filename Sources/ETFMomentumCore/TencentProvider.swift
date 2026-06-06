import Foundation

public final class FallbackMarketDataProvider: MarketDataProvider {
    private let primary: any MarketDataProvider
    private let fallback: any MarketDataProvider

    public init(primary: any MarketDataProvider = EastmoneyProvider(), fallback: any MarketDataProvider = TencentProvider()) {
        self.primary = AKShareProvider.isEnabledByEnvironment ? AKShareProvider() : primary
        self.fallback = fallback
    }

    public func quote(for etf: ETF) async throws -> Quote {
        do { return try await primary.quote(for: etf) } catch { return try await fallback.quote(for: etf) }
    }

    public func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        do { return try await primary.dailyKLines(for: etf, limit: limit) } catch { return try await fallback.dailyKLines(for: etf, limit: limit) }
    }

    public func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        do {
            if let value = try await primary.minuteVolumeSumToday(for: etf, now: now) { return value }
        } catch {}
        return try await fallback.minuteVolumeSumToday(for: etf, now: now)
    }

    public func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        do { return try await primary.premiumInfo(for: etf, previousTradingDate: previousTradingDate) } catch { return try await fallback.premiumInfo(for: etf, previousTradingDate: previousTradingDate) }
    }

    public func previousTradingDate(beforeOrOn date: Date) async -> Date {
        await primary.previousTradingDate(beforeOrOn: date)
    }
}

public final class TencentProvider: MarketDataProvider {
    private let session: URLSession
    private let calendar: Calendar
    private let dateFormatter: DateFormatter
    private let navProvider: EastmoneyProvider

    public init(session: URLSession = .shared) {
        self.session = session
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        self.calendar = calendar
        self.dateFormatter = DateFormatter()
        self.dateFormatter.calendar = calendar
        self.dateFormatter.timeZone = calendar.timeZone
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
        self.navProvider = EastmoneyProvider(session: session)
    }

    public func quote(for etf: ETF) async throws -> Quote {
        let (quote, _) = try await quoteAndKLines(for: etf, limit: 2)
        return quote
    }

    public func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        let (_, lines) = try await quoteAndKLines(for: etf, limit: limit)
        return lines
    }

    public func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        let quote = try await quote(for: etf)
        return quote.volume > 0 ? quote.volume : nil
    }

    public func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        let daily = try await dailyKLines(for: etf, limit: 10)
        let close = daily.last(where: { calendar.isDate($0.date, inSameDayAs: previousTradingDate) })?.close ?? daily.last?.close
        let nav = try await navProvider.fetchNetValue(for: etf)
        guard let close, let nav, nav != 0 else {
            return PremiumInfo(premium: nil, price: close, netValue: nav)
        }
        return PremiumInfo(premium: (close - nav) / nav, price: close, netValue: nav)
    }

    public func previousTradingDate(beforeOrOn date: Date) async -> Date {
        var candidate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
        while calendar.isDateInWeekend(candidate) {
            candidate = calendar.date(byAdding: .day, value: -1, to: candidate) ?? candidate
        }
        return candidate
    }

    private func quoteAndKLines(for etf: ETF, limit: Int) async throws -> (Quote, [KLine]) {
        let symbol = tencentSymbol(for: etf)
        let urlString = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(symbol),day,,,\(limit),qfq"
        guard let url = URL(string: urlString) else { throw MarketDataError.malformedURL }
        let (data, _) = try await session.data(from: url)
        let root = try JSONDecoder().decode(TencentRoot.self, from: data)
        guard let stock = root.data[symbol] else { throw MarketDataError.missingData }
        let rawLines = stock.qfqday ?? stock.day ?? []
        let lines = rawLines.compactMap(parseKLine)
        let quote = parseQuote(stock.qt?[symbol], etf: etf, fallback: lines.last)
        return (quote, lines)
    }

    private func parseKLine(_ raw: [String]) -> KLine? {
        guard raw.count >= 6,
              let date = dateFormatter.date(from: raw[0]),
              let open = Double(raw[1]),
              let close = Double(raw[2]),
              let high = Double(raw[3]),
              let low = Double(raw[4]),
              let volume = Double(raw[5]) else { return nil }
        return KLine(date: date, open: open, close: close, high: high, low: low, volume: volume)
    }

    private func parseQuote(_ raw: [String]?, etf: ETF, fallback: KLine?) -> Quote {
        guard let raw, raw.count > 33 else {
            return Quote(code: etf.code, name: etf.name, lastPrice: fallback?.close ?? 0, pctChange: fallback?.pctChange ?? 0, volume: fallback?.volume ?? 0, paused: fallback == nil)
        }
        let name = raw.indices.contains(1) ? raw[1] : etf.name
        let last = Double(raw[3]) ?? fallback?.close ?? 0
        let pct = Double(raw[32]) ?? fallback?.pctChange ?? 0
        let volume = Double(raw[6]) ?? fallback?.volume ?? 0
        return Quote(code: etf.code, name: name.isEmpty ? etf.name : name, lastPrice: last, pctChange: pct, volume: volume, paused: last <= 0)
    }

    private func tencentSymbol(for etf: ETF) -> String {
        let prefix = etf.code.hasSuffix(".XSHG") ? "sh" : "sz"
        return prefix + etf.eastmoneyCode
    }
}

private struct TencentRoot: Decodable {
    var code: Int
    var msg: String
    var data: [String: TencentStock]
}

private struct TencentStock: Decodable {
    var qfqday: [[String]]?
    var day: [[String]]?
    var qt: [String: [String]]?
}
