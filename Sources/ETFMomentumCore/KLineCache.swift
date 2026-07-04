import Foundation

public struct KLineCache: Sendable {
    public var directory: URL

    public init(directory: URL = AppStore.defaultDirectory()) {
        self.directory = directory
    }

    public func load(etf: ETF, limit: Int) -> [KLine] {
        let url = fileURL(etf: etf, limit: limit)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([KLine].self, from: data)) ?? []
    }

    public func save(_ klines: [KLine], etf: ETF, limit: Int) throws {
        guard !klines.isEmpty else { return }
        let url = fileURL(etf: etf, limit: limit)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(klines).write(to: url, options: .atomic)
    }

    private func fileURL(etf: ETF, limit: Int) -> URL {
        directory
            .appendingPathComponent("klines", isDirectory: true)
            .appendingPathComponent("\(safeFileName(etf.code))-\(limit).json")
    }

    private func safeFileName(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        .map(String.init)
        .joined()
    }
}
