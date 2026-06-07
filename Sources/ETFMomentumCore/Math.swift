import Foundation

public enum MomentumMath {
    public static func withDailyPctChange(_ klines: [KLine]) -> [KLine] {
        guard !klines.isEmpty else { return [] }
        return klines.enumerated().map { index, kline in
            guard index > 0 else { return kline }
            let previousClose = klines[index - 1].close
            guard previousClose != 0 else { return kline }
            var updated = kline
            updated.pctChange = (kline.close / previousClose - 1) * 100
            return updated
        }
    }

    public static func annualizedReturn(priceSeries: [Double], lookbackDays: Int) -> Double {
        let recent = Array(priceSeries.suffix(lookbackDays + 1))
        let y = recent.map { Foundation.log($0) }
        let weights = linspace(start: 1, end: 2, count: y.count)
        let regression = weightedLinearRegression(y: y, weights: weights)
        return Foundation.exp(regression.slope * 250) - 1
    }

    public static func score(priceSeries: [Double], lookbackDays: Int) -> (annRet: Double, r2: Double, score: Double) {
        let recent = Array(priceSeries.suffix(lookbackDays + 1))
        let y = recent.map { Foundation.log($0) }
        let weights = linspace(start: 1, end: 2, count: y.count)
        let regression = weightedLinearRegression(y: y, weights: weights)
        let annRet = Foundation.exp(regression.slope * 250) - 1
        let mean = y.reduce(0, +) / Double(y.count)
        var ssRes = 0.0
        var ssTot = 0.0
        for i in y.indices {
            let x = Double(i)
            let fitted = regression.slope * x + regression.intercept
            ssRes += weights[i] * Foundation.pow(y[i] - fitted, 2)
            ssTot += weights[i] * Foundation.pow(y[i] - mean, 2)
        }
        let r2 = ssTot != 0 ? 1 - ssRes / ssTot : 0
        return (annRet, r2, annRet * r2)
    }

    public static func macd(for klines: [KLine]) -> [MACDPoint] {
        var ema12: Double?
        var ema26: Double?
        var dea: Double = 0
        return klines.map { kline in
            let close = kline.close
            ema12 = ema(previous: ema12, value: close, period: 12)
            ema26 = ema(previous: ema26, value: close, period: 26)
            let dif = (ema12 ?? close) - (ema26 ?? close)
            dea = dea == 0 ? dif : dea * (8.0 / 10.0) + dif * (2.0 / 10.0)
            return MACDPoint(date: kline.date, dif: dif, dea: dea, macd: (dif - dea) * 2)
        }
    }

    public static func movingAverage(for klines: [KLine], period: Int) -> [Double?] {
        guard period > 0 else { return Array(repeating: nil, count: klines.count) }
        var output: [Double?] = []
        output.reserveCapacity(klines.count)
        var sum = 0.0
        for index in klines.indices {
            sum += klines[index].close
            if index >= period {
                sum -= klines[index - period].close
            }
            output.append(index + 1 >= period ? sum / Double(period) : nil)
        }
        return output
    }

    private static func ema(previous: Double?, value: Double, period: Double) -> Double {
        guard let previous else { return value }
        let alpha = 2.0 / (period + 1.0)
        return value * alpha + previous * (1 - alpha)
    }

    public static func linspace(start: Double, end: Double, count: Int) -> [Double] {
        guard count > 1 else { return [start] }
        let step = (end - start) / Double(count - 1)
        return (0..<count).map { start + Double($0) * step }
    }

    public static func weightedLinearRegression(y: [Double], weights: [Double]) -> (slope: Double, intercept: Double) {
        precondition(y.count == weights.count)
        let x = (0..<y.count).map(Double.init)
        let sw = weights.reduce(0, +)
        let sx = zip(weights, x).map(*).reduce(0, +)
        let sy = zip(weights, y).map(*).reduce(0, +)
        let sxx = zip(weights, x).map { $0 * $1 * $1 }.reduce(0, +)
        let sxy = zip(weights.indices, weights).map { i, w in w * x[i] * y[i] }.reduce(0, +)
        let denominator = sw * sxx - sx * sx
        guard denominator != 0 else { return (0, y.first ?? 0) }
        let slope = (sw * sxy - sx * sy) / denominator
        let intercept = (sy - slope * sx) / sw
        return (slope, intercept)
    }
}
