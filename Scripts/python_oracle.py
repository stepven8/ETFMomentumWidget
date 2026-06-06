#!/usr/bin/env python3
import json
import math
import numpy as np


def annualized(price_series, lookback_days):
    recent = price_series[-(lookback_days + 1):]
    y = np.log(recent)
    x = np.arange(len(y))
    weights = np.linspace(1, 2, len(y))
    slope, _ = np.polyfit(x, y, 1, w=weights)
    return math.exp(slope * 250) - 1


def score(price_series, lookback_days):
    recent_y = np.log(price_series[-(lookback_days + 1):])
    x = np.arange(len(recent_y))
    weights = np.linspace(1, 2, len(recent_y))
    slope, intercept = np.polyfit(x, recent_y, 1, w=weights)
    ann_ret = math.exp(slope * 250) - 1
    ss_res = np.sum(weights * (recent_y - (slope * x + intercept)) ** 2)
    ss_tot = np.sum(weights * (recent_y - np.mean(recent_y)) ** 2)
    r2 = 1 - ss_res / ss_tot if ss_tot != 0 else 0
    return {"annualized_returns": ann_ret, "r_squared": r2, "score": ann_ret * r2}


def main():
    prices = [math.exp(0.01 * i) for i in range(26)]
    result = score(prices, 25)
    expected = math.exp(0.01 * 250) - 1
    assert abs(result["annualized_returns"] - expected) < 1e-10
    assert abs(result["r_squared"] - 1) < 1e-10
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
