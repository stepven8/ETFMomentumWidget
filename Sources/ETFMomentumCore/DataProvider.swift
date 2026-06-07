import Foundation

public protocol MarketDataProvider: Sendable {
    func quote(for etf: ETF) async throws -> Quote
    func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine]
    func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double?
    func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo
    func previousTradingDate(beforeOrOn date: Date) async -> Date
}

public enum MarketDataError: Error {
    case malformedURL
    case invalidResponse
    case missingData
}

public extension URLSession {
    static let etfMomentum: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 25
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}

public final class EastmoneyProvider: MarketDataProvider {
    private let session: URLSession
    private let calendar: Calendar
    private let dateFormatter: DateFormatter

    public init(session: URLSession = .etfMomentum, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.session = session
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        self.calendar = calendar
        self.dateFormatter = DateFormatter()
        self.dateFormatter.calendar = calendar
        self.dateFormatter.timeZone = calendar.timeZone
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
    }

    public func quote(for etf: ETF) async throws -> Quote {
        let fields = "f12,f13,f14,f2,f3,f5"
        let urlString = "https://push2.eastmoney.com/api/qt/ulist.np/get?fltt=2&secids=\(etf.secid)&fields=\(fields)"
        guard let url = URL(string: urlString) else { throw MarketDataError.malformedURL }
        let (data, _) = try await session.data(from: url)
        let root = try JSONDecoder().decode(QuoteRoot.self, from: data)
        guard let item = root.data?.diff?.first else { throw MarketDataError.missingData }
        let price = item.f2.validNumber
        return Quote(
            code: etf.code,
            name: item.f14.isEmpty ? etf.name : item.f14,
            lastPrice: price,
            pctChange: item.f3.validNumber,
            volume: item.f5.validNumber,
            paused: price <= 0
        )
    }

    public func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        try await kLines(for: etf, klt: 101, limit: limit)
    }

    public func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        let lines = try await kLines(for: etf, klt: 1, limit: 300)
        let start = calendar.startOfDay(for: now)
        let sum = lines.filter { $0.date >= start && $0.date <= now }.map(\.volume).reduce(0, +)
        return sum > 0 ? sum : nil
    }

    public func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        let daily = try await dailyKLines(for: etf, limit: 10)
        let close = daily.last(where: { calendar.isDate($0.date, inSameDayAs: previousTradingDate) })?.close ?? daily.last?.close
        let nav = try await fetchNetValue(for: etf)
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

    private func kLines(for etf: ETF, klt: Int, limit: Int) async throws -> [KLine] {
        let fields1 = "f1,f2,f3,f4,f5,f6"
        let fields2 = "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61"
        let urlString = "https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=\(etf.secid)&fields1=\(fields1)&fields2=\(fields2)&klt=\(klt)&fqt=1&end=20500101&lmt=\(limit)"
        guard let url = URL(string: urlString) else { throw MarketDataError.malformedURL }
        let (data, _) = try await session.data(from: url)
        let root = try JSONDecoder().decode(KLineRoot.self, from: data)
        guard let raw = root.data?.klines else { throw MarketDataError.missingData }
        return raw.compactMap(parseKLine)
    }

    private func parseKLine(_ raw: String) -> KLine? {
        let parts = raw.split(separator: ",").map(String.init)
        guard parts.count >= 7 else { return nil }
        let dateText = String(parts[0].prefix(10))
        guard let date = dateFormatter.date(from: dateText),
              let open = Double(parts[1]),
              let close = Double(parts[2]),
              let high = Double(parts[3]),
              let low = Double(parts[4]),
              let volume = Double(parts[5]) else { return nil }
        let amount = Double(parts[6]) ?? 0
        let pct = parts.count > 8 ? (Double(parts[8]) ?? 0) : 0
        return KLine(date: date, open: open, close: close, high: high, low: low, volume: volume, amount: amount, pctChange: pct)
    }

    public func fetchNetValue(for etf: ETF) async throws -> Double? {
        let urlString = "https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=\(etf.eastmoneyCode)&page=1&per=1"
        guard let url = URL(string: urlString) else { throw MarketDataError.malformedURL }
        var request = URLRequest(url: url)
        request.setValue("https://fundf10.eastmoney.com/", forHTTPHeaderField: "Referer")
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        let pattern = #"<td class='tor bold'>([0-9.]+)</td>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return Double(html[range])
    }
}

private struct QuoteRoot: Decodable {
    var data: QuoteData?
}

private struct QuoteData: Decodable {
    var diff: [QuoteItem]?
}

private struct QuoteItem: Decodable {
    var f2: FlexibleDouble
    var f3: FlexibleDouble
    var f5: FlexibleDouble
    var f14: String
}

private struct KLineRoot: Decodable {
    var data: KLineData?
}

private struct KLineData: Decodable {
    var klines: [String]?
}

private enum FlexibleDouble: Decodable {
    case number(Double)
    case string(String)
    case missing

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .missing
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else {
            self = .missing
        }
    }

    var validNumber: Double {
        switch self {
        case .number(let value):
            return value
        case .string(let text):
            return Double(text) ?? 0
        case .missing:
            return 0
        }
    }
}
