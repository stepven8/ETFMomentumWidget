import Foundation

public enum BacktestExportError: Error {
    case cannotCreateDirectory
}

public enum BacktestExporter {
    public static func export(result: BacktestResult, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result.metrics).write(to: directory.appendingPathComponent("metrics.json"), options: .atomic)
        try encoder.encode(result).write(to: directory.appendingPathComponent("backtest_result.json"), options: .atomic)
        try csv(headers: ["time", "code", "name", "side", "price", "amount", "commission", "reason", "status"], rows: result.trades.map {
            [$0.date.isoText, $0.code, $0.name, $0.side, text($0.price), "\($0.filledAmount)", text($0.commission), $0.reason, $0.status]
        }).write(to: directory.appendingPathComponent("trades.csv"), atomically: true, encoding: .utf8)
        try csv(headers: ["time", "total_value", "cash", "position_value", "strategy_return", "benchmark_return", "drawdown"], rows: result.equityCurve.map {
            [$0.date.isoText, text($0.totalValue), text($0.cash), text($0.positionValue), text($0.strategyReturn), text($0.benchmarkReturn), text($0.drawdown)]
        }).write(to: directory.appendingPathComponent("equity_curve.csv"), atomically: true, encoding: .utf8)
        try csv(headers: ["time", "code", "name", "amount", "price", "market_value", "cost_basis", "cash", "total_value"], rows: result.positions.map {
            [$0.date.isoText, $0.code, $0.name, "\($0.amount)", text($0.price), text($0.marketValue), text($0.costBasis), text($0.cash), text($0.totalValue)]
        }).write(to: directory.appendingPathComponent("positions.csv"), atomically: true, encoding: .utf8)
        try csv(headers: ["time", "rank", "code", "name", "score", "annualized_returns", "r_squared", "short_annualized", "current_price", "filter_reason"], rows: result.signals.map {
            [$0.date.isoText, $0.rank.map(String.init) ?? "", $0.code, $0.name, text($0.score), text($0.annualizedReturns), text($0.rSquared), text($0.shortAnnualized), text($0.currentPrice), $0.filterReason.rawValue]
        }).write(to: directory.appendingPathComponent("rank_signals.csv"), atomically: true, encoding: .utf8)
        try csv(headers: ["time", "code", "name", "side", "target_value", "price", "amount", "filled_amount", "commission", "reason", "status"], rows: result.orders.map {
            [$0.date.isoText, $0.code, $0.name, $0.side, text($0.targetValue), text($0.price), "\($0.amount)", "\($0.filledAmount)", text($0.commission), $0.reason, $0.status]
        }).write(to: directory.appendingPathComponent("orders.csv"), atomically: true, encoding: .utf8)
    }

    private static func csv(headers: [String], rows: [[String]]) -> String {
        ([headers] + rows).map { row in row.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func text(_ value: Double) -> String {
        String(format: "%.10f", value)
    }
}

private extension Date {
    var isoText: String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: self)
    }
}
