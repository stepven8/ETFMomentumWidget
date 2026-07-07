import Foundation

public enum BacktestPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case oneMinute = "1MIN"
    case fiveMinute = "5MIN"
    case fifteenMinute = "15MIN"
    case thirtyMinute = "30MIN"
    case sixtyMinute = "60MIN"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .oneMinute: return "1 分钟"
        case .fiveMinute: return "5 分钟"
        case .fifteenMinute: return "15 分钟"
        case .thirtyMinute: return "30 分钟"
        case .sixtyMinute: return "60 分钟"
        }
    }

    public var minutes: Int {
        switch self {
        case .oneMinute: return 1
        case .fiveMinute: return 5
        case .fifteenMinute: return 15
        case .thirtyMinute: return 30
        case .sixtyMinute: return 60
        }
    }
}

public enum BacktestStatus: String, Codable, Sendable {
    case running = "运行中"
    case completed = "已完成"
    case failed = "失败"
    case cancelled = "已取消"
}

public struct BacktestConfig: Codable, Equatable, Sendable {
    public var name: String
    public var startDate: Date
    public var endDate: Date
    public var period: BacktestPeriod
    public var initialCapital: Double
    public var benchmark: ETF

    public init(
        name: String = "ETF 动量回测",
        startDate: Date,
        endDate: Date,
        period: BacktestPeriod = .oneMinute,
        initialCapital: Double = 300_000,
        benchmark: ETF = ETF(code: "159919.XSHE", name: "沪深300ETF")
    ) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.period = period
        self.initialCapital = initialCapital
        self.benchmark = benchmark
    }
}

public struct BacktestCostConfig: Codable, Equatable, Sendable {
    public var fundSlippage: Double
    public var fundCommission: Double
    public var minCommission: Double
    public var lotSize: Int

    public init(fundSlippage: Double = 0.0001, fundCommission: Double = 0.0002, minCommission: Double = 5, lotSize: Int = 100) {
        self.fundSlippage = fundSlippage
        self.fundCommission = fundCommission
        self.minCommission = minCommission
        self.lotSize = lotSize
    }
}

public struct BacktestRunSummary: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var startDate: Date
    public var endDate: Date
    public var period: BacktestPeriod
    public var initialCapital: Double
    public var benchmarkCode: String
    public var benchmarkName: String
    public var status: BacktestStatus
    public var totalReturn: Double
    public var benchmarkReturn: Double
    public var maxDrawdown: Double
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        startDate: Date,
        endDate: Date,
        period: BacktestPeriod,
        initialCapital: Double,
        benchmarkCode: String,
        benchmarkName: String,
        status: BacktestStatus = .running,
        totalReturn: Double = 0,
        benchmarkReturn: Double = 0,
        maxDrawdown: Double = 0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.startDate = startDate
        self.endDate = endDate
        self.period = period
        self.initialCapital = initialCapital
        self.benchmarkCode = benchmarkCode
        self.benchmarkName = benchmarkName
        self.status = status
        self.totalReturn = totalReturn
        self.benchmarkReturn = benchmarkReturn
        self.maxDrawdown = maxDrawdown
        self.errorMessage = errorMessage
    }
}

public struct BacktestMetrics: Codable, Equatable, Sendable {
    public var totalReturn: Double
    public var annualizedReturn: Double
    public var benchmarkReturn: Double
    public var excessReturn: Double
    public var maxDrawdown: Double
    public var sharpe: Double
    public var volatility: Double
    public var winRate: Double
    public var dailyWinRate: Double
    public var profitLossRatio: Double
    public var alpha: Double
    public var beta: Double
    public var informationRatio: Double
    public var sortino: Double
    public var profitableTradeCount: Int
    public var losingTradeCount: Int
    public var tradeCount: Int
    public var turnover: Double
    public var averageHoldingDays: Double

    enum CodingKeys: String, CodingKey {
        case totalReturn
        case annualizedReturn
        case benchmarkReturn
        case excessReturn
        case maxDrawdown
        case sharpe
        case volatility
        case winRate
        case dailyWinRate
        case profitLossRatio
        case alpha
        case beta
        case informationRatio
        case sortino
        case profitableTradeCount
        case losingTradeCount
        case tradeCount
        case turnover
        case averageHoldingDays
    }

    public init(totalReturn: Double = 0, annualizedReturn: Double = 0, benchmarkReturn: Double = 0, excessReturn: Double = 0, maxDrawdown: Double = 0, sharpe: Double = 0, volatility: Double = 0, winRate: Double = 0, dailyWinRate: Double = 0, profitLossRatio: Double = 0, alpha: Double = 0, beta: Double = 0, informationRatio: Double = 0, sortino: Double = 0, profitableTradeCount: Int = 0, losingTradeCount: Int = 0, tradeCount: Int = 0, turnover: Double = 0, averageHoldingDays: Double = 0) {
        self.totalReturn = totalReturn
        self.annualizedReturn = annualizedReturn
        self.benchmarkReturn = benchmarkReturn
        self.excessReturn = excessReturn
        self.maxDrawdown = maxDrawdown
        self.sharpe = sharpe
        self.volatility = volatility
        self.winRate = winRate
        self.dailyWinRate = dailyWinRate
        self.profitLossRatio = profitLossRatio
        self.alpha = alpha
        self.beta = beta
        self.informationRatio = informationRatio
        self.sortino = sortino
        self.profitableTradeCount = profitableTradeCount
        self.losingTradeCount = losingTradeCount
        self.tradeCount = tradeCount
        self.turnover = turnover
        self.averageHoldingDays = averageHoldingDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.totalReturn = try container.decodeIfPresent(Double.self, forKey: .totalReturn) ?? 0
        self.annualizedReturn = try container.decodeIfPresent(Double.self, forKey: .annualizedReturn) ?? 0
        self.benchmarkReturn = try container.decodeIfPresent(Double.self, forKey: .benchmarkReturn) ?? 0
        self.excessReturn = try container.decodeIfPresent(Double.self, forKey: .excessReturn) ?? 0
        self.maxDrawdown = try container.decodeIfPresent(Double.self, forKey: .maxDrawdown) ?? 0
        self.sharpe = try container.decodeIfPresent(Double.self, forKey: .sharpe) ?? 0
        self.volatility = try container.decodeIfPresent(Double.self, forKey: .volatility) ?? 0
        self.winRate = try container.decodeIfPresent(Double.self, forKey: .winRate) ?? 0
        self.dailyWinRate = try container.decodeIfPresent(Double.self, forKey: .dailyWinRate) ?? 0
        self.profitLossRatio = try container.decodeIfPresent(Double.self, forKey: .profitLossRatio) ?? 0
        self.alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 0
        self.beta = try container.decodeIfPresent(Double.self, forKey: .beta) ?? 0
        self.informationRatio = try container.decodeIfPresent(Double.self, forKey: .informationRatio) ?? 0
        self.sortino = try container.decodeIfPresent(Double.self, forKey: .sortino) ?? 0
        self.profitableTradeCount = try container.decodeIfPresent(Int.self, forKey: .profitableTradeCount) ?? 0
        self.losingTradeCount = try container.decodeIfPresent(Int.self, forKey: .losingTradeCount) ?? 0
        self.tradeCount = try container.decodeIfPresent(Int.self, forKey: .tradeCount) ?? 0
        self.turnover = try container.decodeIfPresent(Double.self, forKey: .turnover) ?? 0
        self.averageHoldingDays = try container.decodeIfPresent(Double.self, forKey: .averageHoldingDays) ?? 0
    }
}

public struct BacktestEquityPoint: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(date.timeIntervalSince1970)" }
    public var date: Date
    public var totalValue: Double
    public var cash: Double
    public var positionValue: Double
    public var strategyReturn: Double
    public var benchmarkReturn: Double
    public var drawdown: Double

    public init(date: Date, totalValue: Double, cash: Double, positionValue: Double, strategyReturn: Double, benchmarkReturn: Double, drawdown: Double) {
        self.date = date
        self.totalValue = totalValue
        self.cash = cash
        self.positionValue = positionValue
        self.strategyReturn = strategyReturn
        self.benchmarkReturn = benchmarkReturn
        self.drawdown = drawdown
    }
}

public struct BacktestOrder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var code: String
    public var name: String
    public var side: String
    public var targetValue: Double
    public var price: Double
    public var amount: Int
    public var filledAmount: Int
    public var commission: Double
    public var reason: String
    public var status: String

    public init(id: UUID = UUID(), date: Date, code: String, name: String, side: String, targetValue: Double, price: Double, amount: Int, filledAmount: Int, commission: Double, reason: String, status: String) {
        self.id = id
        self.date = date
        self.code = code
        self.name = name
        self.side = side
        self.targetValue = targetValue
        self.price = price
        self.amount = amount
        self.filledAmount = filledAmount
        self.commission = commission
        self.reason = reason
        self.status = status
    }
}

public typealias BacktestTrade = BacktestOrder

public struct BacktestPositionSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(date.timeIntervalSince1970)-\(code)" }
    public var date: Date
    public var code: String
    public var name: String
    public var amount: Int
    public var price: Double
    public var marketValue: Double
    public var costBasis: Double
    public var cash: Double
    public var totalValue: Double

    public init(date: Date, code: String, name: String, amount: Int, price: Double, marketValue: Double, costBasis: Double, cash: Double, totalValue: Double) {
        self.date = date
        self.code = code
        self.name = name
        self.amount = amount
        self.price = price
        self.marketValue = marketValue
        self.costBasis = costBasis
        self.cash = cash
        self.totalValue = totalValue
    }
}

public struct BacktestRankSignal: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(date.timeIntervalSince1970)-\(code)" }
    public var date: Date
    public var rank: Int?
    public var code: String
    public var name: String
    public var score: Double
    public var annualizedReturns: Double
    public var rSquared: Double
    public var shortAnnualized: Double
    public var currentPrice: Double
    public var filterReason: FilterReason

    public init(date: Date, rank: Int?, metric: RankingMetric) {
        self.date = date
        self.rank = rank
        self.code = metric.etf.code
        self.name = metric.etf.name
        self.score = metric.score
        self.annualizedReturns = metric.annualizedReturns
        self.rSquared = metric.rSquared
        self.shortAnnualized = metric.shortAnnualized
        self.currentPrice = metric.currentPrice
        self.filterReason = metric.filterReason
    }
}

public struct BacktestResult: Codable, Equatable, Sendable {
    public var summary: BacktestRunSummary
    public var strategyConfig: StrategyConfig
    public var backtestConfig: BacktestConfig
    public var costConfig: BacktestCostConfig
    public var universe: [ETF]
    public var metrics: BacktestMetrics
    public var equityCurve: [BacktestEquityPoint]
    public var orders: [BacktestOrder]
    public var trades: [BacktestTrade]
    public var positions: [BacktestPositionSnapshot]
    public var signals: [BacktestRankSignal]
    public var logs: [String]

    public init(summary: BacktestRunSummary, strategyConfig: StrategyConfig, backtestConfig: BacktestConfig, costConfig: BacktestCostConfig, universe: [ETF], metrics: BacktestMetrics, equityCurve: [BacktestEquityPoint], orders: [BacktestOrder], trades: [BacktestTrade], positions: [BacktestPositionSnapshot], signals: [BacktestRankSignal], logs: [String]) {
        self.summary = summary
        self.strategyConfig = strategyConfig
        self.backtestConfig = backtestConfig
        self.costConfig = costConfig
        self.universe = universe
        self.metrics = metrics
        self.equityCurve = equityCurve
        self.orders = orders
        self.trades = trades
        self.positions = positions
        self.signals = signals
        self.logs = logs
    }
}
