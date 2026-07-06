import Foundation
import SQLite3

public enum BacktestStoreError: Error, CustomStringConvertible {
    case openFailed(String)
    case sqlite(String)
    case missingRun
    case decodeFailed(String)

    public var description: String {
        switch self {
        case .openFailed(let message): return "数据库打开失败：\(message)"
        case .sqlite(let message): return "数据库错误：\(message)"
        case .missingRun: return "未找到回测记录"
        case .decodeFailed(let message): return "回测记录解析失败：\(message)"
        }
    }
}

public final class BacktestSQLiteStore: @unchecked Sendable {
    public let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "local.etf.momentum.backtest.sqlite")

    public init(directory: URL = AppStore.defaultDirectory()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("backtest.sqlite")
        encoder.outputFormatting = [.sortedKeys]
        try queue.sync {
            let database = try open()
            defer { sqlite3_close(database) }
            try migrate(database)
        }
    }

    public func summaries() throws -> [BacktestRunSummary] {
        try queue.sync {
            let database = try open()
            defer { sqlite3_close(database) }
            var statement: OpaquePointer?
            let sql = "SELECT summary_json FROM backtest_runs ORDER BY created_at DESC"
            try prepare(sql, database: database, statement: &statement)
            defer { sqlite3_finalize(statement) }
            var output: [BacktestRunSummary] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let data = Data((string(statement, column: 0) ?? "{}").utf8)
                output.append(try decoder.decode(BacktestRunSummary.self, from: data))
            }
            return output
        }
    }

    public func result(id: UUID) throws -> BacktestResult {
        try queue.sync {
            let database = try open()
            defer { sqlite3_close(database) }
            var statement: OpaquePointer?
            try prepare("SELECT result_json FROM backtest_runs WHERE id = ? LIMIT 1", database: database, statement: &statement)
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, to: statement, index: 1)
            guard sqlite3_step(statement) == SQLITE_ROW, let text = string(statement, column: 0) else {
                throw BacktestStoreError.missingRun
            }
            do {
                return try decoder.decode(BacktestResult.self, from: Data(text.utf8))
            } catch {
                throw BacktestStoreError.decodeFailed(error.localizedDescription)
            }
        }
    }

    public func save(result: BacktestResult) throws {
        try queue.sync {
            let database = try open()
            defer { sqlite3_close(database) }
            let summaryData = try encoder.encode(result.summary)
            let resultData = try encoder.encode(result)
            let sql = """
            INSERT OR REPLACE INTO backtest_runs
            (id, name, created_at, started_at, finished_at, start_date, end_date, period, status, total_return, benchmark_return, max_drawdown, summary_json, result_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            var statement: OpaquePointer?
            try prepare(sql, database: database, statement: &statement)
            defer { sqlite3_finalize(statement) }
            bind(result.summary.id.uuidString, to: statement, index: 1)
            bind(result.summary.name, to: statement, index: 2)
            bind(result.summary.createdAt, to: statement, index: 3)
            bind(result.summary.startedAt, to: statement, index: 4)
            bind(result.summary.finishedAt, to: statement, index: 5)
            bind(result.summary.startDate, to: statement, index: 6)
            bind(result.summary.endDate, to: statement, index: 7)
            bind(result.summary.period.rawValue, to: statement, index: 8)
            bind(result.summary.status.rawValue, to: statement, index: 9)
            sqlite3_bind_double(statement, 10, result.summary.totalReturn)
            sqlite3_bind_double(statement, 11, result.summary.benchmarkReturn)
            sqlite3_bind_double(statement, 12, result.summary.maxDrawdown)
            bind(String(data: summaryData, encoding: .utf8) ?? "{}", to: statement, index: 13)
            bind(String(data: resultData, encoding: .utf8) ?? "{}", to: statement, index: 14)
            try step(statement, database: database)
        }
    }

    public func deleteRun(id: UUID) throws {
        try queue.sync {
            let database = try open()
            defer { sqlite3_close(database) }
            var statement: OpaquePointer?
            try prepare("DELETE FROM backtest_runs WHERE id = ?", database: database, statement: &statement)
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, to: statement, index: 1)
            try step(statement, database: database)
        }
    }

    public func saveBars(_ bars: [KLine], symbol: String, period: String, source: String = "easy_tdx") throws {
        guard !bars.isEmpty else { return }
        try queue.sync {
            let database = try open()
            defer { sqlite3_close(database) }
            try execute("BEGIN IMMEDIATE", database: database)
            do {
                let sql = """
                INSERT OR REPLACE INTO backtest_bars
                (symbol, period, datetime, open, high, low, close, volume, amount, pct_change, source, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
                var statement: OpaquePointer?
                try prepare(sql, database: database, statement: &statement)
                defer { sqlite3_finalize(statement) }
                let updatedAt = Date()
                for bar in bars {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(symbol, to: statement, index: 1)
                    bind(period, to: statement, index: 2)
                    bind(bar.date, to: statement, index: 3)
                    sqlite3_bind_double(statement, 4, bar.open)
                    sqlite3_bind_double(statement, 5, bar.high)
                    sqlite3_bind_double(statement, 6, bar.low)
                    sqlite3_bind_double(statement, 7, bar.close)
                    sqlite3_bind_double(statement, 8, bar.volume)
                    sqlite3_bind_double(statement, 9, bar.amount)
                    sqlite3_bind_double(statement, 10, bar.pctChange)
                    bind(source, to: statement, index: 11)
                    bind(updatedAt, to: statement, index: 12)
                    try step(statement, database: database)
                }
                try execute("COMMIT", database: database)
            } catch {
                try? execute("ROLLBACK", database: database)
                throw error
            }
        }
    }

    public func bars(symbol: String, period: String, start: Date, end: Date) throws -> [KLine] {
        try queue.sync {
            let database = try open()
            defer { sqlite3_close(database) }
            let sql = """
            SELECT datetime, open, high, low, close, volume, amount, pct_change
            FROM backtest_bars
            WHERE symbol = ? AND period = ? AND datetime >= ? AND datetime <= ?
            ORDER BY datetime ASC
            """
            var statement: OpaquePointer?
            try prepare(sql, database: database, statement: &statement)
            defer { sqlite3_finalize(statement) }
            bind(symbol, to: statement, index: 1)
            bind(period, to: statement, index: 2)
            bind(start, to: statement, index: 3)
            bind(end, to: statement, index: 4)
            var output: [KLine] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                output.append(KLine(
                    date: date(statement, column: 0),
                    open: sqlite3_column_double(statement, 1),
                    close: sqlite3_column_double(statement, 4),
                    high: sqlite3_column_double(statement, 2),
                    low: sqlite3_column_double(statement, 3),
                    volume: sqlite3_column_double(statement, 5),
                    amount: sqlite3_column_double(statement, 6),
                    pctChange: sqlite3_column_double(statement, 7)
                ))
            }
            return output
        }
    }

    private func open() throws -> OpaquePointer? {
        var database: OpaquePointer?
        if sqlite3_open(url.path, &database) != SQLITE_OK {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw BacktestStoreError.openFailed(message)
        }
        return database
    }

    private func migrate(_ database: OpaquePointer?) throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS backtest_runs (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at REAL NOT NULL,
            started_at REAL,
            finished_at REAL,
            start_date REAL NOT NULL,
            end_date REAL NOT NULL,
            period TEXT NOT NULL,
            status TEXT NOT NULL,
            total_return REAL NOT NULL DEFAULT 0,
            benchmark_return REAL NOT NULL DEFAULT 0,
            max_drawdown REAL NOT NULL DEFAULT 0,
            summary_json TEXT NOT NULL,
            result_json TEXT NOT NULL
        )
        """, database: database)
        try execute("""
        CREATE TABLE IF NOT EXISTS backtest_bars (
            symbol TEXT NOT NULL,
            period TEXT NOT NULL,
            datetime REAL NOT NULL,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            volume REAL NOT NULL,
            amount REAL NOT NULL,
            pct_change REAL NOT NULL,
            source TEXT NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY(symbol, period, datetime)
        )
        """, database: database)
        try execute("CREATE INDEX IF NOT EXISTS idx_backtest_runs_created_at ON backtest_runs(created_at DESC)", database: database)
        try execute("CREATE INDEX IF NOT EXISTS idx_backtest_bars_lookup ON backtest_bars(symbol, period, datetime)", database: database)
    }

    private func prepare(_ sql: String, database: OpaquePointer?, statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BacktestStoreError.sqlite(errorMessage(database))
        }
    }

    private func execute(_ sql: String, database: OpaquePointer?) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw BacktestStoreError.sqlite(errorMessage(database))
        }
    }

    private func step(_ statement: OpaquePointer?, database: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw BacktestStoreError.sqlite(errorMessage(database))
        }
    }

    private func bind(_ value: String, to statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bind(_ value: Date?, to statement: OpaquePointer?, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
    }

    private func string(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: raw)
    }

    private func date(_ statement: OpaquePointer?, column: Int32) -> Date {
        Date(timeIntervalSince1970: sqlite3_column_double(statement, column))
    }

    private func errorMessage(_ database: OpaquePointer?) -> String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
