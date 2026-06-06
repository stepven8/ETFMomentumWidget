#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import sys

import akshare as ak


def ok(payload):
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def fail(exc):
    print(json.dumps({"error": str(exc), "type": type(exc).__name__}, ensure_ascii=False), file=sys.stderr)
    sys.exit(2)


def to_float(value, default=0.0):
    try:
        if value is None or value == "":
            return default
        return float(value)
    except Exception:
        return default


def hist(symbol, limit):
    df = ak.fund_etf_hist_em(symbol=symbol, period="daily", adjust="qfq")
    rows = []
    for _, row in df.tail(limit).iterrows():
        rows.append({
            "date": str(row.get("日期")),
            "open": to_float(row.get("开盘")),
            "close": to_float(row.get("收盘")),
            "high": to_float(row.get("最高")),
            "low": to_float(row.get("最低")),
            "volume": to_float(row.get("成交量")),
            "amount": to_float(row.get("成交额")),
            "pctChange": to_float(row.get("涨跌幅")),
        })
    ok({"klines": rows})


def quote(symbol):
    df = ak.fund_etf_spot_em()
    row = df[df["代码"].astype(str) == symbol].head(1)
    if row.empty:
        raise RuntimeError(f"AKShare spot missing ETF {symbol}")
    r = row.iloc[0]
    ok({
        "code": symbol,
        "name": str(r.get("名称", "")),
        "lastPrice": to_float(r.get("最新价")),
        "pctChange": to_float(r.get("涨跌幅")),
        "volume": to_float(r.get("成交量")),
        "paused": to_float(r.get("最新价")) <= 0,
    })


def minute_volume(symbol):
    df = ak.fund_etf_hist_min_em(symbol=symbol, period="1", adjust="qfq")
    today = dt.date.today().isoformat()
    total = 0.0
    for _, row in df.iterrows():
        ts = str(row.get("时间", ""))
        if ts.startswith(today):
            total += to_float(row.get("成交量"))
    ok({"volume": total if total > 0 else None})


def nav(symbol):
    df = ak.fund_etf_fund_info_em(fund=symbol)
    if df.empty:
        ok({"netValue": None})
        return
    latest = df.tail(1).iloc[0]
    value = latest.get("单位净值") if "单位净值" in latest else latest.iloc[1]
    ok({"netValue": to_float(value, None)})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["hist", "quote", "minute-volume", "nav"])
    parser.add_argument("--symbol", required=True)
    parser.add_argument("--limit", type=int, default=260)
    args = parser.parse_args()
    try:
        if args.command == "hist":
            hist(args.symbol, args.limit)
        elif args.command == "quote":
            quote(args.symbol)
        elif args.command == "minute-volume":
            minute_volume(args.symbol)
        elif args.command == "nav":
            nav(args.symbol)
    except Exception as exc:
        fail(exc)


if __name__ == "__main__":
    main()
