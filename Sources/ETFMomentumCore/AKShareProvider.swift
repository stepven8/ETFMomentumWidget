import Foundation

public final class AKShareProvider: MarketDataProvider {
    private let pythonPath: String
    private let scriptPath: String
    private let calendar: Calendar
    private let dateFormatter: DateFormatter

    public init(
        pythonPath: String = ProcessInfo.processInfo.environment["ETF_MOMENTUM_PYTHON"] ?? "/usr/bin/python3",
        scriptPath: String? = ProcessInfo.processInfo.environment["ETF_MOMENTUM_AKSHARE_SCRIPT"]
    ) {
        self.pythonPath = pythonPath
        self.scriptPath = scriptPath ?? Self.defaultScriptPath()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        self.calendar = calendar
        self.dateFormatter = DateFormatter()
        self.dateFormatter.calendar = calendar
        self.dateFormatter.timeZone = calendar.timeZone
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
    }

    public static var isEnabledByEnvironment: Bool {
        ProcessInfo.processInfo.environment["ETF_MOMENTUM_USE_AKSHARE"] == "1"
    }

    public func quote(for etf: ETF) async throws -> Quote {
        let result = try run(command: "quote", etf: etf)
        let decoded = try JSONDecoder().decode(AKQuote.self, from: result)
        return Quote(code: etf.code, name: decoded.name.isEmpty ? etf.name : decoded.name, lastPrice: decoded.lastPrice, pctChange: decoded.pctChange, volume: decoded.volume, paused: decoded.paused)
    }

    public func dailyKLines(for etf: ETF, limit: Int) async throws -> [KLine] {
        let result = try run(command: "hist", etf: etf, extra: ["--limit", String(limit)])
        let decoded = try JSONDecoder().decode(AKKLines.self, from: result)
        return decoded.klines.compactMap { item in
            guard let date = dateFormatter.date(from: item.date) else { return nil }
            return KLine(date: date, open: item.open, close: item.close, high: item.high, low: item.low, volume: item.volume, amount: item.amount, pctChange: item.pctChange)
        }
    }

    public func minuteVolumeSumToday(for etf: ETF, now: Date) async throws -> Double? {
        let result = try run(command: "minute-volume", etf: etf)
        return try JSONDecoder().decode(AKVolume.self, from: result).volume
    }

    public func premiumInfo(for etf: ETF, previousTradingDate: Date) async throws -> PremiumInfo {
        let daily = try await dailyKLines(for: etf, limit: 10)
        let close = daily.last(where: { calendar.isDate($0.date, inSameDayAs: previousTradingDate) })?.close ?? daily.last?.close
        let result = try run(command: "nav", etf: etf)
        let nav = try JSONDecoder().decode(AKNav.self, from: result).netValue
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

    private func run(command: String, etf: ETF, extra: [String] = []) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, command, "--symbol", etf.eastmoneyCode] + extra
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "AKShare failed"
            throw AKShareError.processFailed(message)
        }
        return data
    }

    private static func defaultScriptPath() -> String {
        let cwd = FileManager.default.currentDirectoryPath
        let local = URL(fileURLWithPath: cwd).appendingPathComponent("Scripts/akshare_provider.py").path
        if FileManager.default.fileExists(atPath: local) {
            return local
        }
        return "/Users/cai/量化接口文档/ETFMomentumWidget/Scripts/akshare_provider.py"
    }
}

public enum AKShareError: Error, CustomStringConvertible {
    case processFailed(String)

    public var description: String {
        switch self {
        case .processFailed(let message): return message
        }
    }
}

private struct AKQuote: Decodable {
    var name: String
    var lastPrice: Double
    var pctChange: Double
    var volume: Double
    var paused: Bool
}

private struct AKKLines: Decodable {
    var klines: [AKKLine]
}

private struct AKKLine: Decodable {
    var date: String
    var open: Double
    var close: Double
    var high: Double
    var low: Double
    var volume: Double
    var amount: Double
    var pctChange: Double
}

private struct AKVolume: Decodable {
    var volume: Double?
}

private struct AKNav: Decodable {
    var netValue: Double?
}
