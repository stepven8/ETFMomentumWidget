import Foundation

public enum RefreshError: Error {
    case timeout
}

public struct RefreshCommitValidation: Sendable {
    public var canCommit: Bool
    public var message: String?

    public init(canCommit: Bool, message: String? = nil) {
        self.canCommit = canCommit
        self.message = message
    }
}

private actor RefreshResultBox {
    private var didResume = false
    private let continuation: CheckedContinuation<RankingSnapshot?, Never>

    init(_ continuation: CheckedContinuation<RankingSnapshot?, Never>) {
        self.continuation = continuation
    }

    func resume(_ snapshot: RankingSnapshot?) {
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: snapshot)
    }
}

@MainActor
public final class AppStore: ObservableObject {
    @Published public var config: StrategyConfig
    @Published public var etfs: [ETF]
    @Published public var snapshot: RankingSnapshot?
    @Published public var isRefreshing = false
    @Published public var refreshMessage: String?

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

    public func saveConfigAndPool(applyToSnapshot: Bool = true) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(config).write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        try encoder.encode(etfs).write(to: directory.appendingPathComponent("etfs.json"), options: .atomic)
        if applyToSnapshot {
            applyCurrentPoolToSnapshot()
        }
    }

    public func saveSnapshot(_ snapshot: RankingSnapshot) throws {
        self.snapshot = snapshot
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: directory.appendingPathComponent("snapshot.json"), options: .atomic)
    }

    public func applyCurrentPoolToSnapshot() {
        guard let snapshot else { return }

        let poolByCode = Dictionary(uniqueKeysWithValues: etfs.map { ($0.code, $0) })
        var metricsByCode = Dictionary(uniqueKeysWithValues: snapshot.metrics.map { ($0.etf.code, $0) })
        var next: [RankingMetric] = []
        next.reserveCapacity(etfs.count)

        for etf in etfs {
            if etf.enabled, var metric = metricsByCode.removeValue(forKey: etf.code) {
                metric.etf = ETF(code: etf.code, name: metric.etf.name.isEmpty ? etf.name : metric.etf.name, enabled: true)
                if metric.filterReason == .disabled {
                    metric.filterReason = .pendingRefresh
                }
                next.append(metric)
            } else if etf.enabled {
                next.append(RankingMetric(etf: etf, filterReason: .pendingRefresh))
            } else {
                let previous = metricsByCode.removeValue(forKey: etf.code)
                next.append(disabledMetric(for: etf, previous: previous))
            }
        }

        for metric in snapshot.metrics where poolByCode[metric.etf.code] == nil {
            next.append(metric)
        }

        let included = next.filter { $0.filterReason == .included }.sorted { $0.score > $1.score }
        let filtered = next.filter { $0.filterReason != .included }
        self.snapshot = RankingSnapshot(generatedAt: snapshot.generatedAt, metrics: included + filtered)
        try? encoder.encode(self.snapshot).write(to: directory.appendingPathComponent("snapshot.json"), options: .atomic)
    }

    private func disabledMetric(for etf: ETF, previous: RankingMetric? = nil) -> RankingMetric {
        let displayName: String
        if let previousName = previous?.etf.name, !previousName.isEmpty {
            displayName = previousName
        } else {
            displayName = etf.name
        }
        return RankingMetric(
            etf: ETF(code: etf.code, name: displayName, enabled: false),
            currentPrice: previous?.currentPrice ?? 0,
            pctChange: previous?.pctChange ?? 0,
            filterReason: .disabled
        )
    }

    public func refresh(provider: (any MarketDataProvider)? = nil, timeoutSeconds: UInt64 = 90) async -> Bool {
        isRefreshing = true
        refreshMessage = "正在更新动量排行..."
        defer { isRefreshing = false }

        let config = config
        let etfs = etfs
        let provider = provider ?? FallbackMarketDataProvider(enableEasyTDX: config.enableEasyTDXProvider)
        let next = await withCheckedContinuation { continuation in
            let box = RefreshResultBox(continuation)
            let rankingTask = Task.detached(priority: .userInitiated) {
                let engine = RankingEngine(config: config, provider: provider)
                return await engine.rank(etfs: etfs, includeFiltered: true)
            }
            Task {
                let snapshot = await rankingTask.value
                await box.resume(snapshot)
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                rankingTask.cancel()
                await box.resume(nil)
            }
        }

        guard let next else {
            refreshMessage = "更新失败：刷新超过 \(timeoutSeconds) 秒仍未完成，已停止本次更新并保留原有数据。请检查网络或减少 ETF 数量后重试。"
            return false
        }

        let validation = commitValidation(snapshot: next, for: etfs)
        guard validation.canCommit else {
            refreshMessage = validation.message ?? "更新失败：数据不完整，已保留原有数据。"
            return false
        }
        do {
            try saveSnapshot(next)
            refreshMessage = "更新完成 \(next.generatedAt.formatted(date: .omitted, time: .standard))"
            return true
        } catch {
            refreshMessage = "更新失败：无法保存排行数据，\(error.localizedDescription)。已保留原有数据。"
            return false
        }
    }

    private func canCommit(snapshot: RankingSnapshot, for etfs: [ETF]) -> Bool {
        commitValidation(snapshot: snapshot, for: etfs).canCommit
    }

    public func commitValidation(snapshot: RankingSnapshot, for etfs: [ETF]) -> RefreshCommitValidation {
        let expectedCodes = Set(etfs.map(\.code))
        let metricsByCode = Dictionary(grouping: snapshot.metrics, by: { $0.etf.code })

        guard !expectedCodes.isEmpty else { return RefreshCommitValidation(canCommit: true) }
        let missingCodes = expectedCodes.subtracting(Set(metricsByCode.keys))
        if !missingCodes.isEmpty {
            let text = missingCodes.sorted().prefix(5).joined(separator: "、")
            return RefreshCommitValidation(
                canCommit: false,
                message: "更新失败：缺少 \(missingCodes.count) 只 ETF 的计算结果（\(text)），已保留原有数据。"
            )
        }

        for etf in etfs {
            guard let matches = metricsByCode[etf.code], matches.count == 1, let metric = matches.first else {
                return RefreshCommitValidation(
                    canCommit: false,
                    message: "更新失败：\(etf.name) \(etf.code) 的计算结果重复或缺失，已保留原有数据。"
                )
            }
            if metric.filterReason == .calculationError || metric.filterReason == .pendingRefresh || metric.filterReason == .insufficientData {
                return RefreshCommitValidation(
                    canCommit: false,
                    message: refreshFailureMessage(for: metric)
                )
            }
            if etf.enabled && metric.currentPrice <= 0 {
                return RefreshCommitValidation(
                    canCommit: false,
                    message: "更新失败：\(displayName(for: metric)) 当前价格无效（\(metric.currentPrice.formatted(.number.precision(.fractionLength(3))))），已保留原有数据。"
                )
            }
            if etf.enabled && metric.etf.enabled == false {
                return RefreshCommitValidation(
                    canCommit: false,
                    message: "更新失败：\(displayName(for: metric)) 本应启用但结果被标记为未启用，已保留原有数据。"
                )
            }
        }

        return RefreshCommitValidation(canCommit: true)
    }

    private func refreshFailureMessage(for metric: RankingMetric) -> String {
        var message = "更新失败：\(displayName(for: metric)) \(metric.filterReason.rawValue)"
        if let diagnostic = metric.diagnosticMessage, !diagnostic.isEmpty {
            message += "，原因：\(diagnostic)"
        }
        message += "。已保留原有数据。"
        return message
    }

    private func displayName(for metric: RankingMetric) -> String {
        let name = metric.etf.name.isEmpty ? "ETF" : metric.etf.name
        return "\(name) \(metric.etf.code)"
    }

    nonisolated private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
