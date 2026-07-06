import Foundation

public actor BacktestEngine {
    private let dataProvider: EasyTDXBacktestDataProvider
    private let costConfig: BacktestCostConfig
    private var calendar: Calendar

    public init(dataProvider: EasyTDXBacktestDataProvider, costConfig: BacktestCostConfig = BacktestCostConfig()) {
        self.dataProvider = dataProvider
        self.costConfig = costConfig
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        self.calendar = calendar
    }

    public func run(
        strategyConfig: StrategyConfig,
        universe: [ETF],
        backtestConfig: BacktestConfig,
        progress: (@Sendable (BacktestProgress) async -> Void)? = nil
    ) async throws -> BacktestResult {
        let enabledUniverse = universe.filter(\.enabled)
        let runID = UUID()
        let startedAt = Date()
        var summary = BacktestRunSummary(
            id: runID,
            name: backtestConfig.name,
            createdAt: startedAt,
            startedAt: startedAt,
            startDate: backtestConfig.startDate,
            endDate: backtestConfig.endDate,
            period: backtestConfig.period,
            initialCapital: backtestConfig.initialCapital,
            benchmarkCode: backtestConfig.benchmark.code,
            benchmarkName: backtestConfig.benchmark.name
        )

        await progress?(BacktestProgress(message: "检查并补充通达信回测数据", detail: "回测分钟 K 线写入独立数据库", fraction: 0.02))
        try await dataProvider.ensureData(etfs: enabledUniverse, benchmark: backtestConfig.benchmark, config: backtestConfig, progress: progress)
        let tradingDays = try await dataProvider.tradingDays(config: backtestConfig)
        guard !tradingDays.isEmpty else { throw MarketDataError.missingData }

        var cash = backtestConfig.initialCapital
        var positions: [String: SimPosition] = [:]
        var orders: [BacktestOrder] = []
        var trades: [BacktestTrade] = []
        var equity: [BacktestEquityPoint] = []
        var positionSnapshots: [BacktestPositionSnapshot] = []
        var signals: [BacktestRankSignal] = []
        var logs: [String] = []
        var benchmarkBase: Double?
        var peak = backtestConfig.initialCapital
        var rankingCache: [RankingMetric] = []

        for (dayIndex, day) in tradingDays.enumerated() {
            try Task.checkCancellation()
            let fraction = 0.70 + Double(dayIndex) / Double(max(tradingDays.count, 1)) * 0.28
            await progress?(BacktestProgress(message: "回测 \(day.formatted(date: .numeric, time: .omitted))", detail: "\(dayIndex + 1)/\(tradingDays.count) 个交易日", fraction: fraction))

            let protectionTime = time(on: day, hour: 11, minute: 0)
            if strategyConfig.enableProfitProtection {
                for code in Array(positions.keys) {
                    guard let etf = etf(for: code, universe: enabledUniverse, defensive: strategyConfig.defensiveETF),
                          try await isProfitProtectionTriggered(etf: etf, at: protectionTime, config: strategyConfig, period: backtestConfig.period) else { continue }
                    if let order = try await orderTargetValue(
                        etf: etf,
                        targetValue: 0,
                        at: protectionTime,
                        reason: "盈利保护",
                        minMoney: strategyConfig.minMoney,
                        cash: &cash,
                        positions: &positions,
                        period: backtestConfig.period
                    ) {
                        orders.append(order)
                        trades.append(order)
                    }
                }
            }

            let sellTime = time(on: day, hour: 14, minute: 0)
            let rankingProvider = BacktestHistoricalProvider(dataProvider: dataProvider, currentDate: sellTime, period: backtestConfig.period)
            let engine = RankingEngine(config: strategyConfig, provider: rankingProvider, now: { sellTime }, maxConcurrentCalculations: 4)
            let snapshot = await engine.rank(etfs: enabledUniverse, includeFiltered: true)
            rankingCache = snapshot.included
            let includedRankByCode = Dictionary(uniqueKeysWithValues: snapshot.included.enumerated().map { ($0.element.etf.code, $0.offset + 1) })
            signals.append(contentsOf: snapshot.metrics.map { metric in
                BacktestRankSignal(date: sellTime, rank: includedRankByCode[metric.etf.code], metric: metric)
            })
            let topFive = snapshot.included.prefix(5).enumerated().map { index, metric in
                "#\(index + 1) \(metric.etf.name) \(metric.etf.eastmoneyCode) score \(metric.score.formatted(.number.precision(.fractionLength(4))))"
            }.joined(separator: "；")
            logs.append("\(sellTime.formatted(date: .numeric, time: .shortened)) 排名计算：\(topFive.isEmpty ? "无入选标的" : topFive)")

            var targetETFs = Array(rankingCache.prefix(strategyConfig.holdingsNum).map(\.etf))
            if targetETFs.isEmpty, let defensive = etf(for: strategyConfig.defensiveETF, universe: enabledUniverse, defensive: strategyConfig.defensiveETF) {
                targetETFs = [defensive]
            }
            let targetCodes = Set(targetETFs.map(\.code))

            for code in Array(positions.keys) where !targetCodes.contains(code) {
                guard let etf = etf(for: code, universe: enabledUniverse, defensive: strategyConfig.defensiveETF) else { continue }
                if let order = try await orderTargetValue(
                    etf: etf,
                    targetValue: 0,
                    at: sellTime,
                    reason: "调仓卖出",
                    minMoney: strategyConfig.minMoney,
                    cash: &cash,
                    positions: &positions,
                    period: backtestConfig.period
                ) {
                    orders.append(order)
                    trades.append(order)
                }
            }

            let buyTime = time(on: day, hour: 14, minute: 1)
            if !targetETFs.isEmpty {
                let totalValue = try await portfolioValue(cash: cash, positions: positions, at: buyTime, period: backtestConfig.period)
                let valuePerETF = totalValue / Double(targetETFs.count)
                for etf in targetETFs {
                    let currentValue = try await positionValue(etf: etf, positions: positions, at: buyTime, period: backtestConfig.period)
                    if currentValue == 0 || abs(currentValue - valuePerETF) > valuePerETF * 0.05 {
                        if let order = try await orderTargetValue(
                            etf: etf,
                            targetValue: valuePerETF,
                            at: buyTime,
                            reason: "调仓买入",
                            minMoney: strategyConfig.minMoney,
                            cash: &cash,
                            positions: &positions,
                            period: backtestConfig.period
                        ) {
                            orders.append(order)
                            trades.append(order)
                        }
                    }
                }
            }

            let recordTime = time(on: day, hour: 15, minute: 0)
            let values = try await valuesForPositions(positions: positions, at: recordTime, period: backtestConfig.period)
            let positionValue = values.reduce(0) { $0 + $1.value }
            let totalValue = cash + positionValue
            peak = max(peak, totalValue)
            let drawdown = peak > 0 ? totalValue / peak - 1 : 0
            let benchmarkReturn = try await benchmarkReturn(config: backtestConfig, at: recordTime, base: &benchmarkBase)
            equity.append(BacktestEquityPoint(
                date: recordTime,
                totalValue: totalValue,
                cash: cash,
                positionValue: positionValue,
                strategyReturn: totalValue / backtestConfig.initialCapital - 1,
                benchmarkReturn: benchmarkReturn,
                drawdown: drawdown
            ))
            for (code, position) in positions {
                let price = values[code] ?? position.costBasis
                positionSnapshots.append(BacktestPositionSnapshot(
                    date: recordTime,
                    code: code,
                    name: position.name,
                    amount: position.amount,
                    price: price,
                    marketValue: Double(position.amount) * price,
                    costBasis: position.costBasis,
                    cash: cash,
                    totalValue: totalValue
                ))
            }
        }

        let metrics = calculateMetrics(config: backtestConfig, equity: equity, trades: trades)
        summary.status = .completed
        summary.finishedAt = Date()
        summary.totalReturn = metrics.totalReturn
        summary.benchmarkReturn = metrics.benchmarkReturn
        summary.maxDrawdown = metrics.maxDrawdown
        logs.append("回测完成：\(tradingDays.count) 个交易日，\(trades.count) 笔成交")
        return BacktestResult(
            summary: summary,
            strategyConfig: strategyConfig,
            backtestConfig: backtestConfig,
            costConfig: costConfig,
            universe: enabledUniverse,
            metrics: metrics,
            equityCurve: equity,
            orders: orders,
            trades: trades,
            positions: positionSnapshots,
            signals: signals,
            logs: logs
        )
    }

    private func orderTargetValue(etf: ETF, targetValue: Double, at date: Date, reason: String, minMoney: Double, cash: inout Double, positions: inout [String: SimPosition], period: BacktestPeriod) async throws -> BacktestOrder? {
        guard let bar = try await dataProvider.latestBar(etf: etf, atOrBefore: date, period: period), bar.close > 0 else { return nil }
        let buyPrice = bar.close * (1 + costConfig.fundSlippage / 2)
        let sellPrice = bar.close * (1 - costConfig.fundSlippage / 2)
        let currentAmount = positions[etf.code]?.amount ?? 0
        let targetAmount = roundedLot(Int(targetValue / bar.close))
        let diff = targetAmount - currentAmount
        guard diff != 0 else { return nil }
        if abs(Double(diff) * bar.close) < minMoney, targetValue > 0 {
            return nil
        }

        if diff > 0 {
            var buyAmount = diff
            var gross = Double(buyAmount) * buyPrice
            var commission = max(gross * costConfig.fundCommission, costConfig.minCommission)
            while buyAmount > 0 && cash < gross + commission {
                buyAmount -= costConfig.lotSize
                gross = Double(max(buyAmount, 0)) * buyPrice
                commission = max(gross * costConfig.fundCommission, costConfig.minCommission)
            }
            guard buyAmount > 0, cash >= gross + commission else { return nil }
            cash -= gross + commission
            let old = positions[etf.code]
            let newAmount = currentAmount + buyAmount
            let oldCost = old.map { Double($0.amount) * $0.costBasis } ?? 0
            let newCost = (oldCost + gross) / Double(max(newAmount, 1))
            positions[etf.code] = SimPosition(code: etf.code, name: etf.name, amount: newAmount, costBasis: newCost)
            return BacktestOrder(date: date, code: etf.code, name: etf.name, side: "买入", targetValue: targetValue, price: buyPrice, amount: buyAmount, filledAmount: buyAmount, commission: commission, reason: reason, status: buyAmount == diff ? "全部成交" : "资金约束成交")
        } else {
            let sellAmount = min(abs(diff), currentAmount)
            guard sellAmount > 0 else { return nil }
            let gross = Double(sellAmount) * sellPrice
            let commission = max(gross * costConfig.fundCommission, costConfig.minCommission)
            cash += gross - commission
            let remaining = currentAmount - sellAmount
            if remaining > 0, let old = positions[etf.code] {
                positions[etf.code] = SimPosition(code: etf.code, name: etf.name, amount: remaining, costBasis: old.costBasis)
            } else {
                positions.removeValue(forKey: etf.code)
            }
            return BacktestOrder(date: date, code: etf.code, name: etf.name, side: "卖出", targetValue: targetValue, price: sellPrice, amount: -sellAmount, filledAmount: sellAmount, commission: commission, reason: reason, status: "全部成交")
        }
    }

    private func roundedLot(_ amount: Int) -> Int {
        let lot = max(costConfig.lotSize, 1)
        let rounded = amount / lot * lot
        return rounded <= 0 && amount > 0 ? lot : rounded
    }

    private func isProfitProtectionTriggered(etf: ETF, at date: Date, config: StrategyConfig, period: BacktestPeriod) async throws -> Bool {
        let daily = try await dataProvider.dailyBars(etf: etf, upTo: date, lookback: config.profitProtectionLookback)
        guard daily.count >= config.profitProtectionLookback,
              let current = try await dataProvider.latestBar(etf: etf, atOrBefore: date, period: period) else { return false }
        let maxHigh = daily.map(\.high).max() ?? 0
        return current.close <= maxHigh * (1 - config.profitProtectionThreshold)
    }

    private func portfolioValue(cash: Double, positions: [String: SimPosition], at date: Date, period: BacktestPeriod) async throws -> Double {
        try await valuesForPositions(positions: positions, at: date, period: period).values.reduce(cash, +)
    }

    private func positionValue(etf: ETF, positions: [String: SimPosition], at date: Date, period: BacktestPeriod) async throws -> Double {
        guard let position = positions[etf.code],
              let bar = try await dataProvider.latestBar(etf: etf, atOrBefore: date, period: period) else { return 0 }
        return Double(position.amount) * bar.close
    }

    private func valuesForPositions(positions: [String: SimPosition], at date: Date, period: BacktestPeriod) async throws -> [String: Double] {
        var values: [String: Double] = [:]
        for position in positions.values {
            let etf = ETF(code: position.code, name: position.name)
            if let bar = try await dataProvider.latestBar(etf: etf, atOrBefore: date, period: period) {
                values[position.code] = Double(position.amount) * bar.close
            }
        }
        return values
    }

    private func benchmarkReturn(config: BacktestConfig, at date: Date, base: inout Double?) async throws -> Double {
        guard let bar = try await dataProvider.latestBar(etf: config.benchmark, atOrBefore: date, period: config.period) else { return 0 }
        if base == nil {
            base = bar.close
        }
        guard let base, base != 0 else { return 0 }
        return bar.close / base - 1
    }

    private func calculateMetrics(config: BacktestConfig, equity: [BacktestEquityPoint], trades: [BacktestTrade]) -> BacktestMetrics {
        guard let first = equity.first, let last = equity.last else {
            return BacktestMetrics()
        }
        let totalReturn = last.totalValue / config.initialCapital - 1
        let days = max(calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 1, 1)
        let annualized = pow(1 + totalReturn, 365.0 / Double(days)) - 1
        let returns = zip(equity.dropFirst(), equity).map { current, previous in
            previous.totalValue != 0 ? current.totalValue / previous.totalValue - 1 : 0
        }
        let avg = returns.isEmpty ? 0 : returns.reduce(0, +) / Double(returns.count)
        let variance = returns.isEmpty ? 0 : returns.map { pow($0 - avg, 2) }.reduce(0, +) / Double(returns.count)
        let volatility = sqrt(variance) * sqrt(250)
        let sharpe = volatility != 0 ? annualized / volatility : 0
        let sells = trades.filter { $0.side == "卖出" }
        let wins = sells.filter { $0.price > 0 }.count
        let turnover = trades.map { abs(Double($0.filledAmount) * $0.price) }.reduce(0, +) / max(config.initialCapital, 1)
        return BacktestMetrics(
            totalReturn: totalReturn,
            annualizedReturn: annualized,
            benchmarkReturn: last.benchmarkReturn,
            excessReturn: totalReturn - last.benchmarkReturn,
            maxDrawdown: equity.map(\.drawdown).min() ?? 0,
            sharpe: sharpe,
            volatility: volatility,
            winRate: sells.isEmpty ? 0 : Double(wins) / Double(sells.count),
            tradeCount: trades.count,
            turnover: turnover,
            averageHoldingDays: 0
        )
    }

    private func time(on day: Date, hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func etf(for code: String, universe: [ETF], defensive: String) -> ETF? {
        universe.first { $0.code == code } ?? (code == defensive ? ETF(code: code, name: "防御 ETF") : nil)
    }
}

private struct SimPosition: Sendable {
    var code: String
    var name: String
    var amount: Int
    var costBasis: Double
}
