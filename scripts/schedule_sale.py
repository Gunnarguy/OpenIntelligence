#!/usr/bin/env python3
"""Schedule (or undo) the Lifetime Cohort launch sale through the App Store Connect API.

    # set only the app-side window, before the 5.2 build. Touches no pricing.
    zsh -ic 'python3 scripts/schedule_sale.py --start 2026-09-14 --end 2026-09-28 --write-window'

    # see what would be written to App Store Connect, and change nothing
    zsh -ic 'python3 scripts/schedule_sale.py --start 2026-09-14 --end 2026-09-28'

    # do it
    zsh -ic 'python3 scripts/schedule_sale.py --start 2026-09-14 --end 2026-09-28 --confirm'

    # put the price back, from the snapshot the run wrote
    zsh -ic 'python3 scripts/schedule_sale.py --restore .sale-snapshots/<file>.json --confirm'

Every mode needs App Store Connect credentials, including the ones that write nothing, because
resolving a price point is a read against Apple. `~/.zshrc` exports them and a non-interactive
shell does not, so run it through `zsh -ic`.

WHY A SCRIPT AND NOT THE WEB UI

The sale has two halves that must agree: the price in App Store Connect, and `LaunchSale.window`
compiled into the app. This takes one pair of dates and writes both, so they cannot be mistyped
apart. It does not remove every way they can diverge: `--write-window` edits a source file, and
a source file only reaches customers when it is built and shipped.

WHAT THE API REQUIRES, AND WHY THIS IS NOT A ONE-LINE POST

A price schedule is replaced wholesale. There is no "add a price change" call: POSTing to
/v1/inAppPurchasePriceSchedules submits the **entire** schedule. And the schedule is not a list
of prices, it is a **partition of the timeline**. Apple enforces three things:

    1. Intervals must not intersect.
    2. The entire timeline must be covered, with no gaps.
    3. The rightmost interval must have no end date.

So a temporary sale is **three** rows, not two. The regular price appears twice, because it has
to hold the time before the sale and the time after it:

    [null       -> start]   regular   the leftmost interval, open at the start of time
    [start      -> end]     sale
    [end        -> null]    regular   the rightmost interval, open forever

A two-row schedule of [null -> null] regular plus [start -> end] sale is rejected twice over:
the first interval intersects the second, and the rightmost interval carries an end date.

[evidence_level: measured, confidence: exact, evidence_source: two HTTP 409 responses from POST
/v1/inAppPurchasePriceSchedules on 2026-09-09. ENTITY_ERROR.INVALID_INTERVAL: "Adjacent intervals
must not intersect for USA: [null - null] and [2026-09-15T00:00 - 2026-09-30T00:00]".
ENTITY_ERROR.INVALID_END_DATE: "Entire timeline must be covered for USA. Rightmost interval must
not have an end date". Apple's own reference documents the field names but none of this.]

Because the schedule is replaced rather than amended, this reads the live schedule first and
refuses to write if what it finds is not what it expects, snapshots it before every write, and
re-reads afterwards to check the standing price survived.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "OpenIntelligence/Features/Billing/LaunchSale.swift"
SNAPSHOT_DIR = ROOT / ".sale-snapshots"

LIFETIME_IAP = "6756638872"
BASE_TERRITORY = "USA"
REGULAR_PRICE = 49.99  # the standing US price from 2026-09-30; it was 59.99 before the launch sale
SALE_PRICE = 39.99

# `LaunchSaleTests.testWindowIsOrderedAndNotOpenForever` asserts the compiled window is under 90
# days. Writing a longer one would leave the repo failing its own suite, so refuse here instead.
MAX_WINDOW_DAYS = 89

# Only for the human-readable preview. The app computes each customer's percentage from their own
# two real prices; these are here so the spread is visible before committing.
PREVIEW = {
    "USA": "USD", "GBR": "GBP", "DEU": "EUR", "CAN": "CAD",
    "AUS": "AUD", "JPN": "JPY", "IND": "INR", "BRA": "BRL", "MEX": "MXN",
}

PAGE_CAP = 15


def client():
    asc = os.path.expanduser("~/ASC")
    if not os.path.isdir(asc):
        sys.exit(f"{asc} not found; that is where the App Store Connect client lives")
    sys.path.insert(0, asc)
    try:
        from asc.client import Client, load_config
    except ImportError as exc:
        sys.exit(f"could not import the ASC client from {asc}: {exc}")
    return Client(load_config())


def territory_of(price_point_id: str) -> str | None:
    padded = price_point_id + "=" * (-len(price_point_id) % 4)
    try:
        return json.loads(base64.b64decode(padded).decode()).get("t")
    except Exception:
        return None


def page(c, path, params, what="rows"):
    """Every row from a paginated collection, with its `included` block merged.

    Raises rather than returning a partial result. A truncated price list would silently
    resolve the wrong price point, and a truncated snapshot would be replayed as if whole.
    """
    rows, included, url, first = [], {}, path, True
    for _ in range(PAGE_CAP):
        payload = c.get_json(url, params if first else None)
        first = False
        rows.extend(payload.get("data", []))
        for item in payload.get("included", []):
            included[item["id"]] = item
        nxt = (payload.get("links") or {}).get("next")
        if not nxt:
            return rows, included
        url = nxt.replace("https://api.appstoreconnect.apple.com", "")
    sys.exit(
        f"{what}: more than {PAGE_CAP} pages from {path}. Refusing to act on a partial read; "
        f"raise PAGE_CAP."
    )


def price_points(c):
    """Price points in the base territory, keyed by exact customer price.

    Refuses on a duplicate key or a foreign territory rather than letting the last row win.
    Neither has been observed (658 rows, 658 distinct prices, all USA, 2026-09-09) but both
    would resolve the wrong price silently.
    """
    rows, _ = page(c, f"/v2/inAppPurchases/{LIFETIME_IAP}/pricePoints", {
        "filter[territory]": BASE_TERRITORY,
        "limit": 200,
        "fields[inAppPurchasePricePoints]": "customerPrice,proceeds",
    }, what="price points")

    foreign = {t for t in (territory_of(r["id"]) for r in rows) if t and t != BASE_TERRITORY}
    if foreign:
        sys.exit(f"price points for territories other than {BASE_TERRITORY} came back: {foreign}")

    keys = [round(float(r["attributes"]["customerPrice"]), 2) for r in rows]
    dupes = {p for p, n in Counter(keys).items() if n > 1}
    if dupes:
        sys.exit(
            f"two {BASE_TERRITORY} price points share a customer price: {sorted(dupes)}. "
            f"Resolving by price is no longer unambiguous; pick the price point id by hand."
        )
    return {
        k: (r["id"], r["attributes"].get("proceeds"))
        for k, r in zip(keys, rows)
    }


def manual_rows(c):
    """The hand-set prices currently on the schedule, each with its price point resolved.

    The relationship linkage is only returned when the relationship is named in `fields`, which
    is why it appears there as well as in `include`.
    """
    rows, inc = page(c, f"/v1/inAppPurchasePriceSchedules/{LIFETIME_IAP}/manualPrices", {
        "include": "inAppPurchasePricePoint",
        "limit": 200,
        "fields[inAppPurchasePrices]": "startDate,endDate,manual,inAppPurchasePricePoint",
        "fields[inAppPurchasePricePoints]": "customerPrice,proceeds",
    }, what="manual prices")
    out = []
    for row in rows:
        rel = (row.get("relationships", {}).get("inAppPurchasePricePoint") or {}).get("data")
        pp_id = rel["id"] if rel else None
        attrs = inc.get(pp_id, {}).get("attributes", {}) if pp_id else {}
        price = attrs.get("customerPrice")
        out.append({
            "pricePointId": pp_id,
            "territory": territory_of(pp_id) if pp_id else None,
            "customerPrice": float(price) if price is not None else None,
            "startDate": row["attributes"].get("startDate"),
            "endDate": row["attributes"].get("endDate"),
        })
    return out


def check_live_schedule(live: list[dict], expected_regular: float):
    """Refuse to write unless the schedule is the shape this script knows how to replace.

    The POST replaces every manual price. So anything on the schedule that this script would not
    re-send is about to be destroyed, and a standing price that is not what the constant says
    means the constant is stale and the "regular" row would permanently change the real price.
    """
    problems = []

    foreign = sorted({r["territory"] for r in live if r["territory"] != BASE_TERRITORY})
    if foreign:
        problems.append(
            f"manual prices exist for {foreign}, and this script only re-sends {BASE_TERRITORY}. "
            f"Submitting would delete them. Set this sale in the App Store Connect UI instead."
        )

    # The schedule is a partition of the timeline. The interval that runs forever, the one with
    # no end date, is the price customers pay once every scheduled change has expired. That is
    # the "regular" price, and it is what this script re-sends. If it is not what the constant
    # says, submitting would change the real price rather than preserve it.
    rightmost = [r for r in live if r["endDate"] is None]
    if len(rightmost) != 1:
        problems.append(
            f"expected exactly one open-ended interval (endDate null), found {len(rightmost)}. "
            f"Rows: {live}"
        )
    else:
        actual = rightmost[0]["customerPrice"]
        if actual is None:
            problems.append("the open-ended interval has no resolvable price point")
        elif abs(actual - expected_regular) >= 0.005:
            problems.append(
                f"App Store Connect reverts to {actual} once scheduled changes expire, but this "
                f"script is built around {expected_regular}. Submitting would change the regular "
                f"price to {expected_regular} permanently. Update REGULAR_PRICE in this file and "
                f"LaunchSale.regularLifetimePrices, then re-run."
            )

    scheduled = [r for r in live if r["endDate"] is not None]
    if scheduled:
        print("  note: the schedule already carries dated intervals:")
        for r in scheduled:
            print(f"    {r['customerPrice']}  {r['startDate']} .. {r['endDate']}")
        print("  they will be replaced by this run, not added to.")

    if problems:
        print("\nREFUSING TO WRITE:\n")
        for p in problems:
            print(f"  - {p}")
        sys.exit(1)


def snapshot(c) -> dict:
    """Everything needed to reconstruct today's schedule, before it is replaced."""
    manual, manual_inc = page(c, f"/v1/inAppPurchasePriceSchedules/{LIFETIME_IAP}/manualPrices", {
        "include": "inAppPurchasePricePoint",
        "limit": 200,
        "fields[inAppPurchasePrices]": "startDate,endDate,manual,inAppPurchasePricePoint",
        "fields[inAppPurchasePricePoints]": "customerPrice,proceeds",
    }, what="manual prices")
    auto, auto_inc = page(c, f"/v1/inAppPurchasePriceSchedules/{LIFETIME_IAP}/automaticPrices", {
        "include": "inAppPurchasePricePoint",
        "limit": 200,
        "fields[inAppPurchasePrices]": "startDate,endDate",
        "fields[inAppPurchasePricePoints]": "customerPrice",
    }, what="automatic prices")
    try:
        base = c.get_json(f"/v1/inAppPurchasePriceSchedules/{LIFETIME_IAP}/baseTerritory",
                          {"fields[territories]": "currency"})
    except Exception as exc:
        base = {"error": str(exc)}
    return {
        "complete": True,   # page() exits rather than truncating, so reaching here means whole
        "takenAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "inAppPurchaseId": LIFETIME_IAP,
        "baseTerritory": base,
        "manualPrices": {"data": manual, "included": list(manual_inc.values())},
        "resolvedManualPrices": manual_rows(c),
        # All of them, not a sample. These are the generated per-territory prices, and comparing
        # them after a write is the only way to show the 174 storefronts came back unchanged.
        "automaticPrices": {
            "data": [{"id": r["id"], "attributes": r["attributes"]} for r in auto],
            "byTerritory": {
                territory_of(i["id"]): i["attributes"].get("customerPrice")
                for i in auto_inc.values()
                if territory_of(i["id"])
            },
        },
    }


def write_snapshot(c, label: str) -> Path:
    SNAPSHOT_DIR.mkdir(exist_ok=True)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = SNAPSHOT_DIR / f"{stamp}-{label}.json"
    path.write_text(json.dumps(snapshot(c), indent=2), encoding="utf-8")
    print(f"Snapshot of the schedule as it stands: {path.relative_to(ROOT)}")
    print(f"  undo with:  --restore {path.relative_to(ROOT)} --confirm")
    print("  This file is the only undo. It is tracked, so commit it.\n")
    return path


def local_id(name: str) -> str:
    """Apple's format for an id that exists only inside this request.

    A plain string is rejected: "The provided included entity id 'regular' has invalid format.
    For inline creation, the id must be a local id with the format '${local-id}'."
    The literal braces are required, and the same string must appear in both the relationship
    and the `included` entry or Apple cannot match them.
    [evidence_level: measured, confidence: exact, evidence_source: HTTP 409
    ENTITY_ERROR.INCLUDED.INVALID_ID from POST /v1/inAppPurchasePriceSchedules, 2026-09-09]
    """
    return "${" + name + "}"


def body_for(rows: list[dict]) -> dict:
    """The create request. `rows` are {id, pricePointId, startDate, endDate}.

    `id` is a bare name here; `local_id` wraps it into the form Apple requires.
    """
    return {
        "data": {
            "type": "inAppPurchasePriceSchedules",
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": LIFETIME_IAP}},
                "baseTerritory": {"data": {"type": "territories", "id": BASE_TERRITORY}},
                "manualPrices": {
                    "data": [{"type": "inAppPurchasePrices", "id": local_id(r["id"])} for r in rows]
                },
            },
        },
        "included": [
            {
                "type": "inAppPurchasePrices",
                "id": local_id(r["id"]),
                "attributes": {"startDate": r["startDate"], "endDate": r["endDate"]},
                "relationships": {
                    "inAppPurchasePricePoint": {
                        "data": {"type": "inAppPurchasePricePoints", "id": r["pricePointId"]}
                    },
                    "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": LIFETIME_IAP}},
                },
            }
            for r in rows
        ],
    }


def equalized(c, price_point_id: str) -> dict[str, float]:
    """What Apple would charge in each territory for a given base price point."""
    rows, _ = page(c, f"/v1/inAppPurchasePricePoints/{price_point_id}/equalizations", {
        "limit": 200, "fields[inAppPurchasePricePoints]": "customerPrice",
    }, what="equalizations")
    out = {}
    for row in rows:
        terr = territory_of(row["id"])
        if terr:
            out[terr] = float(row["attributes"]["customerPrice"])
    return out


def preview(c, regular_pp: str, sale_pp: str, regular_price: float, sale_price: float):
    """The table the App Store Connect UI shows before you click Confirm.

    Equalizations do not include the base territory itself, so its two prices are the ones being
    submitted rather than anything looked up.
    """
    reg, sale = equalized(c, regular_pp), equalized(c, sale_pp)
    reg.setdefault(BASE_TERRITORY, regular_price)
    sale.setdefault(BASE_TERRITORY, sale_price)
    print(f"  {'territory':<12}{'currency':<10}{'regular':>12}{'sale':>12}{'off':>7}")
    for terr, cur in PREVIEW.items():
        r, s = reg.get(terr), sale.get(terr)
        if r is None or s is None or r <= 0:
            print(f"  {terr:<12}{cur:<10}{'?':>12}{'?':>12}{'?':>7}")
            continue
        print(f"  {terr:<12}{cur:<10}{r:>12}{s:>12}{int((r - s) / r * 100):>6}%")
    print(f"\n  ({len(reg)} territories in total; the app computes each customer's own")
    print("   percentage from their own two prices, so nobody is shown a US figure.)")


def window_literal(text: str, start: dt.date, end: dt.date) -> str:
    """`LaunchSale.window` rewritten to these dates. Pure, so it can be tested.

    Raises ValueError when the literal is not found, rather than writing a file it did not
    understand.
    """
    pattern = re.compile(
        r"(let start = calendar\.date\(from: DateComponents\(year: )\d+(, month: )\d+(, day: )\d+"
        r"(\)\),\s*\n\s*let end = calendar\.date\(from: DateComponents\(year: )\d+(, month: )\d+"
        r"(, day: )\d+(\))"
    )
    if not pattern.search(text):
        raise ValueError("could not find the LaunchSale.window date literal")
    return pattern.sub(
        rf"\g<1>{start.year}\g<2>{start.month}\g<3>{start.day}\g<4>"
        rf"{end.year}\g<5>{end.month}\g<6>{end.day}\g<7>",
        text, count=1,
    )


def write_window(start: dt.date, end: dt.date):
    """Point `LaunchSale.window` at the same dates, so the app and the store agree.

    `end` is App Store Connect's end date. The app's window closes at 00:00 Pacific on that day
    and `deadlineText` names the day before, so a customer is told the sale ends on `end` minus
    one. Under either reading of Apple's end date, last sale day or revert day, that is right or
    one day early, never one day late.
    """
    text = SWIFT.read_text(encoding="utf-8")
    try:
        updated = window_literal(text, start, end)
    except ValueError as exc:
        sys.exit(f"{exc} in {SWIFT}; set it by hand")
    backup = SWIFT.with_suffix(".swift.bak")
    backup.write_text(text, encoding="utf-8")
    SWIFT.write_text(updated, encoding="utf-8")
    backup.unlink()
    print(f"  wrote {start.isoformat()} .. {end.isoformat()} into {SWIFT.relative_to(ROOT)}")
    print(f"  the paywall will read: ends {(end - dt.timedelta(days=1)).strftime('%B %-d')}")
    print("  COMMIT AND BUILD. A source file does not reach anybody until it ships.")


def verify_after_write(c, expected_regular: float, expected_sale: float,
                       start: dt.date, end: dt.date) -> int:
    """Re-read the schedule and check the standing price survived at the right amount.

    If App Store Connect is eventually consistent this can read the pre-write schedule, so a
    mismatch here means "look", not necessarily "it failed".
    """
    live = manual_rows(c)
    print("App Store Connect now reports:")
    for r in live:
        print(f"  {r['customerPrice']}  {r['territory']}  "
              f"start={r['startDate']}  end={r['endDate']}")

    problems = []

    def price_ok(row, expected):
        return row["customerPrice"] is not None and \
            abs(row["customerPrice"] - expected) < 0.005

    # The interval that runs forever is what customers pay after the sale. If this is wrong the
    # regular price has been changed permanently, which is the failure worth shouting about.
    rightmost = [r for r in live if r["endDate"] is None]
    if len(rightmost) != 1:
        problems.append(f"expected one open-ended interval, found {len(rightmost)}")
    elif not price_ok(rightmost[0], expected_regular):
        problems.append(
            f"the price after the sale reads {rightmost[0]['customerPrice']}, "
            f"expected {expected_regular}. THE REGULAR PRICE MAY HAVE CHANGED."
        )

    # The interval before the sale must also be the regular price.
    leftmost = [r for r in live if r["startDate"] is None]
    if len(leftmost) != 1:
        problems.append(f"expected one interval open at the start, found {len(leftmost)}")
    elif not price_ok(leftmost[0], expected_regular):
        problems.append(
            f"the price before the sale reads {leftmost[0]['customerPrice']}, "
            f"expected {expected_regular}"
        )

    sale_rows = [r for r in live if r["startDate"] == start.isoformat()]
    if not sale_rows:
        problems.append(f"no interval starting {start.isoformat()}")
    elif not price_ok(sale_rows[0], expected_sale):
        problems.append(
            f"the sale interval reads {sale_rows[0]['customerPrice']}, expected {expected_sale}"
        )
    elif sale_rows[0]["endDate"] != end.isoformat():
        problems.append(
            f"the sale interval ends {sale_rows[0]['endDate']}, expected {end.isoformat()}"
        )

    if problems:
        print("\nWRITE DID NOT PRODUCE THE EXPECTED SCHEDULE:\n")
        for p in problems:
            print(f"  - {p}")
        print("\nApp Store Connect may lag a few seconds. Re-read before restoring:")
        print("  zsh -ic 'python3 scripts/verify_sale_prices.py'")
        print("If it is genuinely wrong, restore from the snapshot printed above.")
        return 1
    print("\n  standing price intact, sale row present with the right dates.")
    return 0


def do_restore(c, path: Path, confirm: bool) -> int:
    if not path.exists():
        sys.exit(f"{path} does not exist")
    snap = json.loads(path.read_text(encoding="utf-8"))
    if not snap.get("complete"):
        sys.exit(f"{path} is not marked complete; it may be a partial read. Restore by hand.")

    points = {i["id"]: i for i in snap["manualPrices"]["included"]}
    rows = []
    for n, row in enumerate(snap["manualPrices"]["data"]):
        rel = (row.get("relationships", {}).get("inAppPurchasePricePoint") or {}).get("data")
        if not rel:
            sys.exit(
                f"{path} row {n} records no price point, so the price it held is unknowable "
                f"from this snapshot. Set the price by hand in App Store Connect."
            )
        rows.append({
            "id": f"restore{n}", "pricePointId": rel["id"],
            "startDate": row["attributes"].get("startDate"),
            "endDate": row["attributes"].get("endDate"),
        })

    if not rows:
        sys.exit(f"{path} holds no manual prices; there is nothing to restore")
    if not any(r["startDate"] is None for r in rows):
        sys.exit(
            f"{path} has no standing price (no row with startDate null). Apple requires one, so "
            f"this snapshot cannot be replayed as-is. Set the price by hand."
        )

    print(f"Restoring the schedule captured at {snap['takenAt']}:")
    for r in rows:
        price = points.get(r["pricePointId"], {}).get("attributes", {}).get("customerPrice", "?")
        terr = territory_of(r["pricePointId"])
        print(f"  {price}  {terr}  start={r['startDate']}  end={r['endDate']}")

    stale = [r for r in rows
             if r["startDate"] and r["startDate"] < dt.date.today().isoformat()]
    if stale:
        print("\n  note: this snapshot contains price changes whose start date has passed.")
        print("  Apple may reject them. If it does, restore by hand in the UI.")

    if not confirm:
        print("\nDRY RUN. Add --confirm to apply.")
        return 0

    write_snapshot(c, "pre-restore")
    c.post_json("/v1/inAppPurchasePriceSchedules", body_for(rows))
    print("Restored. App Store Connect now reports:")
    for r in manual_rows(c):
        print(f"  {r['customerPrice']}  {r['territory']}  "
              f"start={r['startDate']}  end={r['endDate']}")
    print("\nLaunchSale.window is NOT changed by a restore. If you are cancelling a sale, set it")
    print("to a past date and ship, or leave it: the banner needs a real price drop to appear.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    ap.add_argument("--start", help="first day at the sale price, YYYY-MM-DD")
    ap.add_argument("--end", help="App Store Connect end date, YYYY-MM-DD")
    ap.add_argument("--sale-price", type=float, default=SALE_PRICE)
    ap.add_argument("--confirm", action="store_true",
                    help="actually write pricing. Without it, no pricing is changed.")
    ap.add_argument("--write-window", action="store_true",
                    help="also point LaunchSale.window at these dates. Independent of --confirm.")
    ap.add_argument("--restore", metavar="SNAPSHOT.json",
                    help="put back a schedule captured by an earlier run")
    args = ap.parse_args()

    if args.restore:
        for flag, name in ((args.start, "--start"), (args.end, "--end"),
                           (args.write_window, "--write-window")):
            if flag:
                ap.error(f"{name} means nothing with --restore; a restore replays recorded dates")
        return do_restore(client(), Path(args.restore), args.confirm)

    if not args.start or not args.end:
        ap.error("--start and --end are required (or use --restore)")
    try:
        start = dt.date.fromisoformat(args.start)
        end = dt.date.fromisoformat(args.end)
    except ValueError as exc:
        sys.exit(f"dates must be YYYY-MM-DD: {exc}")

    today = dt.date.today()
    if start < today:
        sys.exit(f"--start {start} is in the past; Apple will not accept it")
    if end <= start:
        sys.exit(f"--end {end} must be after --start {start}")
    if (end - start).days > MAX_WINDOW_DAYS:
        sys.exit(
            f"{(end - start).days} days exceeds {MAX_WINDOW_DAYS}. Apple allows up to a year, but "
            f"LaunchSaleTests asserts the compiled window is under 90 days, so a longer one would "
            f"leave the suite failing."
        )

    sale_price = round(args.sale_price, 2)
    if abs(sale_price - args.sale_price) > 1e-9:
        sys.exit(f"--sale-price {args.sale_price} is not a whole number of cents")
    if sale_price >= REGULAR_PRICE:
        sys.exit(f"--sale-price {sale_price} is not below the regular price {REGULAR_PRICE}")
    if sale_price <= 0:
        sys.exit("--sale-price must be positive")

    c = client()
    print(f"Lifetime Cohort ({LIFETIME_IAP}), base territory {BASE_TERRITORY}\n")

    print("Reading the live schedule before deciding anything:")
    live = manual_rows(c)
    for r in live:
        print(f"  {r['customerPrice']}  {r['territory']}  "
              f"start={r['startDate']}  end={r['endDate']}")
    check_live_schedule(live, REGULAR_PRICE)
    print(f"  standing price confirmed at {REGULAR_PRICE}, {BASE_TERRITORY} only.\n")

    points = price_points(c)
    regular = points.get(round(REGULAR_PRICE, 2))
    sale = points.get(sale_price)
    if not regular:
        sys.exit(f"no {BASE_TERRITORY} price point at {REGULAR_PRICE}")
    if not sale:
        near = sorted(sorted(points, key=lambda p: abs(p - sale_price))[:5])
        sys.exit(f"no {BASE_TERRITORY} price point at {sale_price}. Nearest: {near}")

    print("Price points resolved:")
    print(f"  regular  {REGULAR_PRICE:>8}   you keep {regular[1]}")
    print(f"  sale     {sale_price:>8}   you keep {sale[1]}\n")

    print("What customers would see:")
    preview(c, regular[0], sale[0], REGULAR_PRICE, sale_price)

    print("\nSchedule to submit, as three contiguous intervals:")
    print(f"  {REGULAR_PRICE:>8}   from the beginning until {start}")
    print(f"  {sale_price:>8}   {start} until {end}")
    print(f"  {REGULAR_PRICE:>8}   from {end} onward, no end date\n")

    # A partition of the timeline: no gaps, no overlaps, last interval open-ended.
    rows = [
        {"id": "before", "pricePointId": regular[0],
         "startDate": None, "endDate": start.isoformat()},
        {"id": "sale", "pricePointId": sale[0],
         "startDate": start.isoformat(), "endDate": end.isoformat()},
        {"id": "after", "pricePointId": regular[0],
         "startDate": end.isoformat(), "endDate": None},
    ]
    request = body_for(rows)
    status = 0

    if args.confirm:
        write_snapshot(c, "pre-sale")
        c.post_json("/v1/inAppPurchasePriceSchedules", request)
        print("Submitted.\n")
        status = verify_after_write(c, REGULAR_PRICE, sale_price, start, end)
    else:
        print("Request body that --confirm would POST to /v1/inAppPurchasePriceSchedules:\n")
        print(json.dumps(request, indent=2))
        print("\nDRY RUN. No pricing was changed.")

    if args.write_window:
        print()
        write_window(start, end)
    elif not args.confirm:
        print(f"\nLaunchSale.window is untouched. --write-window sets it to {start} .. {end}.")

    return status


if __name__ == "__main__":
    sys.exit(main())
