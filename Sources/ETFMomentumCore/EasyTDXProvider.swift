import Foundation

public final class EasyTDXProvider: MarketDataProvider {
    private let binaryPath: String?
    private let timeoutSeconds: TimeInterval
    private let calendar: Calendar
    private let dateFormatter: DateFormatter
    private let dateTimeFormatter: DateFormatter
    private let premiumProvider: EastmoneyProvider

    public init(
        binaryPath: String? = nil,
        timeoutSeconds: TimeInterval = 8,
        premiumProvider: EastmoneyProvider = EastmoneyProvider(session: .etfMomentumNetValue)
    ) {
        self.binaryPath = binaryPath
        self.timeoutSeconds = timeoutSeconds
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        self.calendar = calendar
        self.dateFormatter = DateFormatter()
        self.dateFormatter.calendar = calendar
        self.dateFormatter.timeZone = calendar.timeZone
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
        self.dateTimeFormatter = DateFormatter()
        self.dateTimeFormatter.calendar = calendar
        self.dateTimeFormatter.timeZone = calendar.timeZone
        self.dateTimeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        self.premiumProvider = premiumProvider
    }

    public static var isAvailable: Bool {
        Self.resolveBinaryPath() != nil
    }

    public func quote(for etf: ETF) async throws -> Quote {
        let data = try run(arguments: ["quote", market(for: etf), etf.eastmoneyCode, "--output", "json"])
        guard let item = try JSONDecoder().decode([EasyTDXQuote].self, from: data).first else {
            throw MarketDataError.missingData
        }
        let price = item.close ?? 0
        let pctChange: Double
        if let preClose = item.preClose, preClose != 0 {
            pctChange = (price - preClose) / preClose * 100
        } else {
            pctChange = item.speedPct ?? 0
        }
        return Quote(
            code: etf.code,
            name: item.name?.isEmpty == false ? (item.name ?? etf.name) : etf.name,
            lastPrice: price,
            pctChange: pctChange,
            volume: item.vol ?? 0,
            paused: price <= 0
        )
    }

    public func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        let data = try run(arguments: ["kline", market(for: etf), etf.eastmoneyCode, "--period", "DAILY", "--count", String(limit), "--adjust", "QFQ", "--output", "json"])
        let decoded = try JSONDecoder().decode([EasyTDXKLine].self, from: data)
        let lines = decoded.compactMap(parseKLine)
        guard !lines.isEmpty else { throw MarketDataError.missingData }
        return MomentumMath.withDailyPctChange(lines)
    }

    public func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        let data = try run(arguments: ["kline", market(for: etf), etf.eastmoneyCode, "--period", "1MIN", "--count", "300", "--output", "json"])
        let decoded = try JSONDecoder().decode([EasyTDXKLine].self, from: data)
        let start = calendar.startOfDay(for: now)
        let sum = decoded.compactMap(parseKLine)
            .filter { $0.date >= start && $0.date <= now }
            .map(\.volume)
            .reduce(0, +)
        return sum > 0 ? sum : nil
    }

    public func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        try await premiumProvider.premiumInfo(for: etf, previousTradingDate: previousTradingDate)
    }

    public func previousTradingDate(beforeOrOn date: Date) async -> Date {
        await premiumProvider.previousTradingDate(beforeOrOn: date)
    }

    private func run(arguments: [String]) throws -> Data {
        guard let command = binaryPath ?? Self.resolveBinaryPath() else {
            throw EasyTDXError.binaryNotFound
        }

        let process = Process()
        if command.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        try process.run()

        let deadline = DispatchTime.now() + .milliseconds(Int(timeoutSeconds * 1000))
        if semaphore.wait(timeout: deadline) == .timedOut {
            process.terminate()
            throw EasyTDXError.timeout
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "easy-tdx failed"
            throw EasyTDXError.processFailed(message)
        }
        guard !data.isEmpty else { throw MarketDataError.missingData }
        return data
    }

    private func parseKLine(_ item: EasyTDXKLine) -> KLine? {
        guard let text = item.datetime,
              let open = item.open,
              let close = item.close,
              let high = item.high,
              let low = item.low else { return nil }
        let date = dateTimeFormatter.date(from: text) ?? dateFormatter.date(from: String(text.prefix(10)))
        guard let date else { return nil }
        return KLine(date: date, open: open, close: close, high: high, low: low, volume: item.vol ?? 0, amount: item.amount ?? 0)
    }

    private func market(for etf: ETF) -> String {
        etf.code.hasSuffix(".XSHG") ? "SH" : "SZ"
    }

    private static func resolveBinaryPath() -> String? {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["ETF_MOMENTUM_EASY_TDX_BIN"],
            "/Users/cai/代码/easy_tdx/.venv/bin/easy-tdx"
        ].compactMap { $0 }

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("easy-tdx").path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}

public enum EasyTDXError: Error, CustomStringConvertible {
    case binaryNotFound
    case timeout
    case processFailed(String)

    public var description: String {
        switch self {
        case .binaryNotFound:
            return "easy-tdx binary not found"
        case .timeout:
            return "easy-tdx timed out"
        case .processFailed(let message):
            return message
        }
    }
}

private struct EasyTDXQuote: Decodable {
    var name: String?
    var preClose: Double?
    var close: Double?
    var vol: Double?
    var speedPct: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case preClose = "pre_close"
        case close
        case vol
        case speedPct = "speed_pct"
    }
}

private struct EasyTDXKLine: Decodable {
    var datetime: String?
    var open: Double?
    var high: Double?
    var low: Double?
    var close: Double?
    var vol: Double?
    var amount: Double?
}
