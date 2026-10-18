#!/usr/bin/env python3
"""Re-read the Lifetime regular prices from App Store Connect and report drift.

    zsh -ic 'python3 scripts/verify_sale_prices.py'

WHY THIS EXISTS

`LaunchSale.regularLifetimePrices` is a table of pre-sale prices compiled into the app. The
paywall shows a struck-through "was" figure from it, so a stale entry is a false claim about
money. Two things can make it stale:

  1. Apple recalculates its generated per-territory prices when tax rates or exchange rates
     move. Nothing in the repo notices.
  2. A permanent price change that nobody mirrored back into the Swift table.

From 5.7 it checks every territory, not a sample: a currency's price is not one amount
everywhere (on 2026-09-29, USD 59.99 in 22 territories and EUR 49.99 in Montenegro), so the app
keeps those territories' prices in `regularLifetimePriceExceptions` and this compares each of the
175 open-ended prices with what the app would show there.

Run this before scheduling any sale. Exit code 0 means the table matches App Store Connect.

Reads APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID and _API_KEY_PATH from the environment, which
~/.zshrc exports, so run it through `zsh -ic`. See Docs/ai/RUNBOOK.md.
"""

import base64
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT_TABLE = ROOT / "OpenIntelligence/Features/Billing/LaunchSale.swift"
LIFETIME_IAP = "6756638872"

# Kept for reference: the 28 territories the first version of this script mapped. From 5.7 every
# territory's currency is read from /v1/territories instead (`territory_currencies`).
TERRITORY_CURRENCY_SAMPLE = {
    "USA": "USD", "GBR": "GBP", "CAN": "CAD", "AUS": "AUD", "IND": "INR",
    "JPN": "JPY", "BRA": "BRL", "MEX": "MXN",
    "DEU": "EUR", "FRA": "EUR", "ITA": "EUR", "ESP": "EUR", "NLD": "EUR", "AUT": "EUR",
    "BEL": "EUR", "IRL": "EUR", "PRT": "EUR", "FIN": "EUR", "GRC": "EUR", "SVK": "EUR",
    "SVN": "EUR", "LTU": "EUR", "LVA": "EUR", "EST": "EUR", "LUX": "EUR", "CYP": "EUR",
    "MLT": "EUR", "HRV": "EUR",
}


def swift_table():
    """The currency -> price map as the app currently compiles it."""
    text = SWIFT_TABLE.read_text(encoding="utf-8")
    block = re.search(
        r"regularLifetimePrices:\s*\[String:\s*Decimal\]\s*=\s*\[(.*?)\]", text, re.S
    )
    if not block:
        sys.exit(f"could not find regularLifetimePrices in {SWIFT_TABLE}")
    return {
        m.group(1): float(m.group(2))
        for m in re.finditer(r'"([A-Z]{3})"\s*:\s*([0-9.]+)', block.group(1))
    }


def swift_exceptions():
    """territory -> (currency, price) as the app compiles `regularLifetimePriceExceptions` (5.7)."""
    text = SWIFT_TABLE.read_text(encoding="utf-8")
    block = re.search(r"regularLifetimePriceExceptions:[^=]*=\s*\[(.*?)\n\s*\]", text, re.S)
    if not block:
        return {}
    return {
        m.group(1): (m.group(2), float(m.group(3)))
        for m in re.finditer(r'"([A-Z]{3})"\s*:\s*\("([A-Z]{3})",\s*([0-9.]+)\)', block.group(1))
    }


def territory_currencies(client):
    """territory -> currency for every App Store territory (5.7)."""
    out, url, params = {}, "/v1/territories", {"limit": 200, "fields[territories]": "currency"}
    for _ in range(5):
        payload = client.get_json(url, params)
        for item in payload.get("data", []):
            out[item["id"]] = item["attributes"].get("currency")
        nxt = (payload.get("links") or {}).get("next")
        if not nxt:
            break
        url, params = nxt.replace("https://api.appstoreconnect.apple.com", ""), None
    return out


def decode_territory(price_point_id):
    padded = price_point_id + "=" * (-len(price_point_id) % 4)
    try:
        return json.loads(base64.b64decode(padded).decode()).get("t")
    except Exception:
        return None


def regular_prices(client):
    """currency -> set of *regular* prices, ignoring any sale interval.

    A price schedule is a partition of the timeline, so a territory with a sale scheduled has
    three rows, not one. The regular price is the one in force once every scheduled change has
    expired: the interval with no end date. Comparing against all rows indiscriminately reports
    a live sale as drift, which is exactly when this check needs to be trustworthy.
    [evidence_level: measured, confidence: exact, evidence_source: the schedule written on
    2026-09-09 produced [null -> 09-15] 59.99, [09-15 -> 09-30] 39.99, [09-30 -> null] 59.99 in
    USA and the equivalent in all 174 generated territories]
    """
    by_currency = defaultdict(set)
    # territory -> the open-ended row's price
    tail = {}
    url = f"/v1/inAppPurchasePriceSchedules/{LIFETIME_IAP}/automaticPrices"
    params = {
        "include": "inAppPurchasePricePoint",
        "limit": 200,
        "fields[inAppPurchasePrices]": "startDate,endDate,inAppPurchasePricePoint",
        "fields[inAppPurchasePricePoints]": "customerPrice,proceeds,territory",
    }
    page = 0
    while url and page < 12:
        payload = client.get_json(url, params) if page == 0 else client.get_json(url)
        points = {
            item["id"]: item["attributes"]
            for item in payload.get("included", [])
            if item["type"] == "inAppPurchasePricePoints"
        }
        for row in payload.get("data", []):
            rel = (row.get("relationships", {}).get("inAppPurchasePricePoint") or {}).get("data")
            if not rel or rel["id"] not in points:
                continue
            if row["attributes"].get("endDate") is not None:
                continue        # a scheduled change, not the regular price
            territory = decode_territory(rel["id"])
            if territory:
                tail[territory] = float(points[rel["id"]]["customerPrice"])
        nxt = (payload.get("links") or {}).get("next")
        if not nxt:
            break
        url = nxt.replace("https://api.appstoreconnect.apple.com", "")
        params = None
        page += 1

    currencies = territory_currencies(client)
    for territory, price in tail.items():
        currency = currencies.get(territory)
        if currency:
            by_currency[currency].add(price)

    # USA is set by hand, so it is a manual price rather than a generated one. Same rule: the
    # open-ended interval is the regular price.
    manual = client.get_json(
        f"/v1/inAppPurchasePriceSchedules/{LIFETIME_IAP}/manualPrices",
        {
            "include": "inAppPurchasePricePoint",
            "limit": 200,
            "filter[territory]": "USA",
            "fields[inAppPurchasePrices]": "startDate,endDate,inAppPurchasePricePoint",
            "fields[inAppPurchasePricePoints]": "customerPrice",
        },
    )
    points = {
        item["id"]: item["attributes"]
        for item in manual.get("included", [])
        if item["type"] == "inAppPurchasePricePoints"
    }
    for row in manual.get("data", []):
        if row["attributes"].get("endDate") is not None:
            continue
        rel = (row.get("relationships", {}).get("inAppPurchasePricePoint") or {}).get("data")
        if rel and rel["id"] in points:
            by_currency["USD"].add(float(points[rel["id"]]["customerPrice"]))
            tail["USA"] = float(points[rel["id"]]["customerPrice"])
    return by_currency, tail, currencies


def scheduled_changes(client):
    """Any dated interval currently on the schedule, so the report can say a sale is running."""
    out = []
    manual = client.get_json(
        f"/v1/inAppPurchasePriceSchedules/{LIFETIME_IAP}/manualPrices",
        {
            "include": "inAppPurchasePricePoint",
            "limit": 200,
            "filter[territory]": "USA",
            "fields[inAppPurchasePrices]": "startDate,endDate,inAppPurchasePricePoint",
            "fields[inAppPurchasePricePoints]": "customerPrice",
        },
    )
    points = {
        i["id"]: i["attributes"] for i in manual.get("included", [])
        if i["type"] == "inAppPurchasePricePoints"
    }
    for row in manual.get("data", []):
        a = row["attributes"]
        if a.get("startDate") is None and a.get("endDate") is None:
            continue
        rel = (row.get("relationships", {}).get("inAppPurchasePricePoint") or {}).get("data")
        price = points.get(rel["id"], {}).get("customerPrice") if rel else "?"
        out.append((a.get("startDate"), a.get("endDate"), price))
    return sorted(out, key=lambda r: r[0] or "")


def main():
    asc = os.path.expanduser("~/ASC")
    if not os.path.isdir(asc):
        sys.exit(f"{asc} not found; that is where the App Store Connect client lives")
    sys.path.insert(0, asc)
    try:
        from asc.client import Client, load_config  # noqa: E402
    except ImportError as exc:
        sys.exit(f"could not import the ASC client from {asc}: {exc}")

    recorded = swift_table()
    exceptions = swift_exceptions()
    client = Client(load_config())
    live, tail, currencies = regular_prices(client)
    changes = scheduled_changes(client)

    problems = []

    # 1. Every territory: what the app would show as the regular price there against what it is (5.7).
    shown_ok = silent = 0
    for territory in sorted(tail):
        price, currency = tail[territory], currencies.get(territory)
        if territory in exceptions:
            ex_currency, ex_price = exceptions[territory]
            expected = ex_price if ex_currency == currency else None
        else:
            expected = recorded.get(currency)
        if expected is None:
            silent += 1
        elif abs(expected - price) < 0.005:
            shown_ok += 1
        else:
            problems.append(
                f"{territory} ({currency}): the app would show {expected}, App Store Connect says {price}. "
                f"Add it to LaunchSale.regularLifetimePriceExceptions or correct the table."
            )
    print(f"{len(tail)} territories: {shown_ok} match the app, {silent} have no recorded price (no banner there), "
          f"{len(tail) - shown_ok - silent} differ")

    # 2. Does the compiled table still match what Apple charges?
    print(f"{'currency':<10}{'in app':>12}{'App Store':>12}   status")
    for currency in sorted(set(recorded) | set(live)):
        in_app = recorded.get(currency)
        apple = sorted(live.get(currency, []))
        shown = apple[0] if len(apple) == 1 else (apple or ["-"])
        if in_app is None:
            status = "not in app (fine, no banner shown there)"
        elif not apple:
            status = "NOT FOUND in App Store Connect"
            problems.append(f"{currency}: recorded in the app but absent from App Store Connect")
        elif len(apple) == 1 and abs(in_app - apple[0]) < 0.005:
            status = "ok"
        elif in_app in apple:
            status = "ok where not listed as an exception (checked per territory above)"
        else:
            status = "DRIFTED"
            problems.append(
                f"{currency}: app says {in_app}, App Store Connect says {shown}. "
                f"Update LaunchSale.regularLifetimePrices before running a sale."
            )
        print(f"{currency:<10}{str(in_app if in_app is not None else '-'):>12}{str(shown):>12}   {status}")

    if changes:
        print()
        print("Scheduled price intervals on the USA schedule (the sale, if one is running):")
        for start, end, price in changes:
            print(f"  {price:>8}   {start or 'beginning':<12} -> {end or 'no end date'}")
        print("  The figures above compare the REGULAR price only, which is the interval with")
        print("  no end date. A running sale is not drift.")

    print()
    if problems:
        print("DRIFT FOUND. The paywall would misstate a saving:\n")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print("Every territory's regular price matches what the app would show there, or the app shows nothing. Before")
    print("it knows the country, a currency with an exception shows nothing and any other has one price everywhere.")
    print("This proves the struck-through price the paywall shows is current. Whether a sale")
    print("is running is the separate question answered by the interval list above.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
