import Foundation

public struct StrategyConfig: Codable, Equatable, Sendable {
    public var lookbackDays: Int
    public var holdingsNum: Int
    public var defensiveETF: String
    public var minMoney: Double
    public var stopLoss: Double
    public var loss: Double
    public var minScoreThreshold: Double
    public var maxScoreThreshold: Double
    public var enableVolumeCheck: Bool
    public var volumeLookback: Int
    public var volumeThreshold: Double
    public var volumeReturnLimit: Double
    public var useShortMomentumFilter: Bool
    public var shortLookbackDays: Int
    public var shortMomentumThreshold: Double
    public var enableProfitProtection: Bool
    public var profitProtectionLookback: Int
    public var profitProtectionThreshold: Double
    public var profitProtectionCheckTimes: [String]
    public var enablePremiumFilter: Bool
    public var premiumThreshold: Double

    public init(
        lookbackDays: Int = 25,
        holdingsNum: Int = 1,
        defensiveETF: String = "511880.XSHG",
        minMoney: Double = 5000,
        stopLoss: Double = 0.95,
        loss: Double = 0.97,
        minScoreThreshold: Double = 0,
        maxScoreThreshold: Double = 100.0,
        enableVolumeCheck: Bool = true,
        volumeLookback: Int = 5,
        volumeThreshold: Double = 2,
        volumeReturnLimit: Double = 1,
        useShortMomentumFilter: Bool = true,
        shortLookbackDays: Int = 10,
        shortMomentumThreshold: Double = 0.0,
        enableProfitProtection: Bool = true,
        profitProtectionLookback: Int = 1,
        profitProtectionThreshold: Double = 0.05,
        profitProtectionCheckTimes: [String] = ["11:00"],
        enablePremiumFilter: Bool = true,
        premiumThreshold: Double = 0.20
    ) {
        self.lookbackDays = lookbackDays
        self.holdingsNum = holdingsNum
        self.defensiveETF = defensiveETF
        self.minMoney = minMoney
        self.stopLoss = stopLoss
        self.loss = loss
        self.minScoreThreshold = minScoreThreshold
        self.maxScoreThreshold = maxScoreThreshold
        self.enableVolumeCheck = enableVolumeCheck
        self.volumeLookback = volumeLookback
        self.volumeThreshold = volumeThreshold
        self.volumeReturnLimit = volumeReturnLimit
        self.useShortMomentumFilter = useShortMomentumFilter
        self.shortLookbackDays = shortLookbackDays
        self.shortMomentumThreshold = shortMomentumThreshold
        self.enableProfitProtection = enableProfitProtection
        self.profitProtectionLookback = profitProtectionLookback
        self.profitProtectionThreshold = profitProtectionThreshold
        self.profitProtectionCheckTimes = profitProtectionCheckTimes
        self.enablePremiumFilter = enablePremiumFilter
        self.premiumThreshold = premiumThreshold
    }
}

public struct ETF: Codable, Identifiable, Hashable, Sendable {
    public var id: String { code }
    public var code: String
    public var name: String
    public var enabled: Bool

    public init(code: String, name: String, enabled: Bool = true) {
        self.code = code
        self.name = name
        self.enabled = enabled
    }

    public var eastmoneyCode: String {
        String(code.prefix(6))
    }

    public var secid: String {
        code.hasSuffix(".XSHG") ? "1.\(eastmoneyCode)" : "0.\(eastmoneyCode)"
    }
}

public struct KLine: Codable, Hashable, Sendable {
    public var date: Date
    public var open: Double
    public var close: Double
    public var high: Double
    public var low: Double
    public var volume: Double
    public var amount: Double
    public var pctChange: Double

    public init(date: Date, open: Double, close: Double, high: Double, low: Double, volume: Double, amount: Double = 0, pctChange: Double = 0) {
        self.date = date
        self.open = open
        self.close = close
        self.high = high
        self.low = low
        self.volume = volume
        self.amount = amount
        self.pctChange = pctChange
    }
}

public struct Quote: Codable, Sendable {
    public var code: String
    public var name: String
    public var lastPrice: Double
    public var pctChange: Double
    public var volume: Double
    public var paused: Bool

    public init(code: String, name: String, lastPrice: Double, pctChange: Double, volume: Double = 0, paused: Bool = false) {
        self.code = code
        self.name = name
        self.lastPrice = lastPrice
        self.pctChange = pctChange
        self.volume = volume
        self.paused = paused
    }
}

public struct PremiumInfo: Codable, Sendable {
    public var premium: Double?
    public var price: Double?
    public var netValue: Double?

    public init(premium: Double?, price: Double?, netValue: Double?) {
        self.premium = premium
        self.price = price
        self.netValue = netValue
    }
}

public enum FilterReason: String, Codable, Sendable {
    case included = "入选"
    case disabled = "未启用"
    case paused = "停牌"
    case insufficientData = "日线数据不足"
    case profitProtection = "盈利保护触发"
    case premiumExceeded = "溢价超限"
    case volumeReturnExceeded = "成交量异常且年化过高"
    case shortMomentumWeak = "短期动量不足"
    case recentLossExceeded = "近三日单日跌幅超限"
    case scoreOutOfRange = "分数阈值外"
    case pendingRefresh = "等待重新计算"
    case calculationError = "计算异常"
}

public struct RankingMetric: Codable, Identifiable, Sendable {
    public var id: String { etf.code }
    public var etf: ETF
    public var annualizedReturns: Double
    public var rSquared: Double
    public var score: Double
    public var currentPrice: Double
    public var shortAnnualized: Double
    public var pctChange: Double
    public var filterReason: FilterReason
    public var volumeRatio: Double?
    public var premium: Double?
    public var closes: [Double]

    public init(etf: ETF, annualizedReturns: Double = 0, rSquared: Double = 0, score: Double = 0, currentPrice: Double = 0, shortAnnualized: Double = 0, pctChange: Double = 0, filterReason: FilterReason, volumeRatio: Double? = nil, premium: Double? = nil, closes: [Double] = []) {
        self.etf = etf
        self.annualizedReturns = annualizedReturns
        self.rSquared = rSquared
        self.score = score
        self.currentPrice = currentPrice
        self.shortAnnualized = shortAnnualized
        self.pctChange = pctChange
        self.filterReason = filterReason
        self.volumeRatio = volumeRatio
        self.premium = premium
        self.closes = closes
    }
}

public struct RankingSnapshot: Codable, Sendable {
    public var generatedAt: Date
    public var metrics: [RankingMetric]

    public init(generatedAt: Date = Date(), metrics: [RankingMetric]) {
        self.generatedAt = generatedAt
        self.metrics = metrics
    }

    public var included: [RankingMetric] {
        metrics.filter { $0.filterReason == .included }.sorted { $0.score > $1.score }
    }
}

public struct MACDPoint: Identifiable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var dif: Double
    public var dea: Double
    public var macd: Double
}
