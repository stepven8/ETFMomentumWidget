import Foundation

public enum RefreshError: Error {
    case timeout
}

@MainActor
public final class AppStore: ObservableObject {
    @Published public var config: StrategyConfig
    @Published public var etfs: [ETF]
    @Published public var snapshot: RankingSnapshot?

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL = AppStore.defaultDirectory()) {
        self.directory = directory
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.config = Self.load(StrategyConfig.self, from: directory.appendingPathComponent("config.json")) ?? StrategyConfig()
        self.etfs = Self.load([ETF].self, from: directory.appendingPathComponent("etfs.json")) ?? DefaultETFPool.items
        self.snapshot = Self.load(RankingSnapshot.self, from: directory.appendingPathComponent("snapshot.json"))
    }

    nonisolated public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ETFMomentumWidget", isDirectory: true)
    }

    nonisolated public static func cachedSnapshot(directory: URL = AppStore.defaultDirectory()) -> RankingSnapshot? {
        load(RankingSnapshot.self, from: directory.appendingPathComponent("snapshot.json"))
    }

    public func saveConfigAndPool() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(config).write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        try encoder.encode(etfs).write(to: directory.appendingPathComponent("etfs.json"), options: .atomic)
    }

    public func saveSnapshot(_ snapshot: RankingSnapshot) throws {
        self.snapshot = snapshot
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: directory.appendingPathComponent("snapshot.json"), options: .atomic)
    }

    public func refresh(provider: any MarketDataProvider = FallbackMarketDataProvider(), timeoutSeconds: UInt64 = 90) async -> Bool {
        do {
            let next = try await withThrowingTaskGroup(of: RankingSnapshot.self) { group in
                let config = config
                let etfs = etfs
                group.addTask {
                    let engine = RankingEngine(config: config, provider: provider)
                    return await engine.rank(etfs: etfs, includeFiltered: true)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                    throw RefreshError.timeout
                }
                guard let result = try await group.next() else { throw RefreshError.timeout }
                group.cancelAll()
                return result
            }
            try saveSnapshot(next)
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
