#!/usr/bin/env python3
"""Submit gate: reads a version's App Store Connect records and says whether it is ready to submit.

Read-only. It makes GET requests to App Store Connect and to the URLs the listing names, and changes nothing.
It exists because 5.8 was rejected on 2026-11-20 by an automated check (Guideline 3.1.2: auto-renewable
subscriptions, and no Terms of Use link in the description), about 15 hours after submission, for something a
script can read in a minute. Run it before every submission; a FAIL means do not submit.

Usage:
  zsh -ic 'python3 scripts/asc_submit_gate.py 5.9'           check both platforms, exit 1 on any FAIL
  zsh -ic 'python3 scripts/asc_submit_gate.py 5.9 --json'    the same, as JSON
  zsh -ic 'python3 scripts/asc_submit_gate.py 5.9 --save FILE'   also write what was read (no contact details)
  python3 scripts/asc_submit_gate.py --snapshot FILE         check a saved snapshot, no network (the tests use this)

`zsh -ic` because the key's three variables (APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID, _API_KEY_PATH) are exported
by ~/.zshrc. It prints no key material. Standard library only; the token is signed with /usr/bin/openssl.

Levels: FAIL blocks a submission. WARN is the owner's to read (a house rule, or something Apple accepted before).
INFO is a fact worth seeing. What the API cannot show is listed at the end of every run.

What each check is based on, with the date it was read:
- Terms of Use link: Apple's rejection of 5.8, 2026-11-20, "does not include a functional link to the Terms of Use
  (EULA) in the app metadata". A custom EULA set in App Store Connect satisfies it too.
- Text limits: description, What's New and review notes 4,000; keywords 100; promotional text 170; name and
  subtitle 30 (App Store Connect's field limits).
- Screenshots: "Screenshot specifications", developer.apple.com/help/app-store-connect, read 2026-11-20: at least
  one iPhone set, one 13-inch iPad set if the app runs on iPad, one Mac set for a Mac app.
- Age rating attributes: AgeRatingDeclaration.Attributes, developer.apple.com, read 2026-11-20. An unanswered
  question fails: Apple's news item of 2026-11-02 ("New age rating content descriptors") says the Shared Location and
  Dating and Relationships declarations must be provided when submitting an app update from 2026-11-16.
- Build commit: an Xcode Cloud run's number is the build number; its `sourceCommit` is read from
  /v1/ciProducts/{id}/buildRuns (the plain /v1/ciBuildRuns collection is not readable, measured 2026-11-20).
"""
import argparse, base64, datetime, json, os, re, subprocess, sys, time, urllib.error, urllib.parse, urllib.request

APP_ID = "6756559175"
API = "https://api.appstoreconnect.apple.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLATFORMS = ("IOS", "MAC_OS")
NAME = {"IOS": "iOS", "MAC_OS": "macOS", "APP": "app"}
SUBMITTABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
SUBMITTED = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "PROCESSING_FOR_DISTRIBUTION",
             "ACCEPTED", "READY_FOR_REVIEW"}
LIVE = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}
OPEN_SUBMISSION = {"WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"}
BAD_PRODUCT = {"MISSING_METADATA", "DEVELOPER_ACTION_NEEDED", "REJECTED"}
LIMITS = {"description": 4000, "whatsNew": 4000, "keywords": 100, "promotionalText": 170}
IPHONE_SETS = {"APP_IPHONE_67", "APP_IPHONE_65", "APP_IPHONE_61"}
IPAD_SETS = {"APP_IPAD_PRO_3GEN_129", "APP_IPAD_PRO_129"}
MAC_SETS = {"APP_DESKTOP"}
# Age rating attributes that are not content questions, so an empty one is not an unanswered question.
AGE_OPTIONAL = {"kidsAgeBand", "gracRatingClassificationNumber", "developerAgeRatingInfoUrl", "koreaAgeRatingOverride",
                "ageRatingOverride", "ageRatingOverrideV2"}
TERMS_WORDS = re.compile(r"terms of use|terms of service|eula|licen[sc]e agreement", re.I)
LINK = re.compile(r"(https?://[^\s)>\]]+|\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|me|org|net|app|io|dev)/[^\s)>\]]*)", re.I)
NOT_READABLE = [
    "App Privacy answers (the privacy labels): App Store Connect, App Privacy.",
    "The text of a rejection: App Store Connect, the submission's page. The API shows only the state.",
    "Whether an in-app purchase's review screenshot is still the right one.",
]


# ---------------------------------------------------------------- reading App Store Connect

def _b64(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _raw_signature(der):
    """An ECDSA signature as openssl writes it (DER: two integers) to the 64 raw bytes a JWT carries."""
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        length = der[i + 1]
        parts.append(der[i + 2:i + 2 + length].lstrip(b"\x00").rjust(32, b"\x00"))
        i += 2 + length
    return parts[0] + parts[1]


class Connect:
    def __init__(self):
        try:
            self.key_id = os.environ["APP_STORE_CONNECT_API_KEY_ID"]
            self.issuer = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
            self.key_path = os.path.expanduser(os.environ["APP_STORE_CONNECT_API_KEY_PATH"])
        except KeyError as e:
            sys.exit(f"{e.args[0]} is not set. Run this through zsh -ic '...' so ~/.zshrc exports it.")
        self._token, self._expires = None, 0

    def token(self):
        now = int(time.time())
        if self._token and now < self._expires - 60:
            return self._token
        head = _b64(json.dumps({"alg": "ES256", "kid": self.key_id, "typ": "JWT"}).encode())
        body = _b64(json.dumps({"iss": self.issuer, "exp": now + 900, "aud": "appstoreconnect-v1"}).encode())
        signing = f"{head}.{body}".encode()
        der = subprocess.run(["/usr/bin/openssl", "dgst", "-sha256", "-sign", self.key_path], input=signing,
                             capture_output=True, check=True, timeout=30).stdout
        self._token, self._expires = f"{head}.{body}.{_b64(_raw_signature(der))}", now + 900
        return self._token

    def get(self, path, params=None):
        url = path if path.startswith("http") else API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        last = None
        for attempt in range(4):
            request = urllib.request.Request(url, headers={"Authorization": "Bearer " + self.token(),
                                                           "Accept": "application/json"})
            try:
                with urllib.request.urlopen(request, timeout=120) as response:
                    return json.loads(response.read())
            except urllib.error.HTTPError as e:
                last = RuntimeError(f"HTTP {e.code} for {url.split('?')[0]}: {e.read().decode(errors='replace')[:300]}")
                if e.code not in (401, 429, 500, 502, 503, 504):
                    raise last from None
                self._token = None
            except OSError as e:
                last = e
            time.sleep(2 ** attempt)
        raise last or RuntimeError(f"no answer from {url.split('?')[0]}")

    def all(self, path, params=None):
        page = self.get(path, params)
        rows = list(page.get("data") or [])
        while page.get("links", {}).get("next"):
            page = self.get(page["links"]["next"])
            rows.extend(page.get("data") or [])
        return rows


def url_status(url):
    """The HTTP status a listing URL answers with after redirects; 0 when it does not answer."""
    if not url.lower().startswith("http"):
        url = "https://" + url
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Macintosh) submit-gate"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


def git(*args):
    try:
        r = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True, timeout=90)
        return r.stdout.strip() if r.returncode == 0 else None
    except Exception:
        return None


def read_file(*parts):
    path = os.path.join(ROOT, *parts)
    return open(path, encoding="utf-8").read().strip() if os.path.exists(path) else None


def tag_for(version):
    return "v" + version + (".0" if version.count(".") == 1 else "")


def collect(version, app=APP_ID, tag=None):
    """Everything the checks need, as plain data. Contact details and notes are reduced to booleans and lengths."""
    c = Connect()
    snap = {"version": version, "app": app, "collected": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
            "platforms": {}, "urls": {}}

    groups = []
    for group in c.all(f"/v1/apps/{app}/subscriptionGroups", {"limit": 50}):
        subs = c.all(f"/v1/subscriptionGroups/{group['id']}/subscriptions", {"limit": 50})
        groups.append({"name": group["attributes"].get("referenceName"),
                       "subscriptions": [{"productId": s["attributes"].get("productId"), "state": s["attributes"].get("state")}
                                         for s in subs]})
    snap["subscription_groups"] = groups
    snap["purchases"] = [{"productId": p["attributes"].get("productId"), "state": p["attributes"].get("state")}
                         for p in c.all(f"/v1/apps/{app}/inAppPurchasesV2", {"limit": 50})]
    snap["custom_eula"] = bool(c.get(f"/v1/apps/{app}/endUserLicenseAgreement").get("data"))

    infos = []
    for info in c.all(f"/v1/apps/{app}/appInfos", {"limit": 10}):
        a = info["attributes"]
        age = (c.get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration").get("data") or {}).get("attributes") or {}
        locs = [{"locale": l["attributes"].get("locale"), "name": l["attributes"].get("name") or "",
                 "subtitle": l["attributes"].get("subtitle") or "", "privacyPolicyUrl": l["attributes"].get("privacyPolicyUrl")}
                for l in c.all(f"/v1/appInfos/{info['id']}/appInfoLocalizations", {"limit": 50})]
        infos.append({"state": a.get("state") or a.get("appStoreState"), "ageRating": a.get("appStoreAgeRating"),
                      "ageUnanswered": sorted(k for k, v in age.items() if v is None and k not in AGE_OPTIONAL),
                      "ageOverride": age.get("ageRatingOverrideV2"), "localizations": locs})
    snap["app_infos"] = infos

    product = (c.get(f"/v1/apps/{app}/ciProduct").get("data") or {}).get("id")
    runs = {}
    if product:
        page = c.get(f"/v1/ciProducts/{product}/buildRuns",
                     {"sort": "-number", "limit": 50, "fields[ciBuildRuns]": "number,sourceCommit,completionStatus"})
        for run in page.get("data") or []:
            runs[str(run["attributes"].get("number"))] = run

    review_file = read_file("fastlane", "review_notes", f"{version}.txt")
    for record in c.all(f"/v1/apps/{app}/appStoreVersions", {"filter[versionString]": version, "limit": 10}):
        a, vid = record["attributes"], record["id"]
        entry = {"state": a.get("appVersionState") or a.get("appStoreState"), "releaseType": a.get("releaseType"),
                 "copyright": bool(a.get("copyright")), "build": None, "localizations": [], "review": None, "submissions": []}
        build = c.get(f"/v1/appStoreVersions/{vid}/build").get("data")
        if build:
            b = build["attributes"]
            entry["build"] = {"version": b.get("version"), "processingState": b.get("processingState"),
                              "expired": b.get("expired"), "usesNonExemptEncryption": b.get("usesNonExemptEncryption"),
                              "commit": None}
            run = runs.get(str(b.get("version")))
            if run:
                made = {x["id"] for x in c.all(f"/v1/ciBuildRuns/{run['id']}/builds", {"limit": 20})}
                if build["id"] in made:
                    entry["build"]["commit"] = (run["attributes"].get("sourceCommit") or {}).get("commitSha")
        for loc in c.all(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", {"limit": 50}):
            la = loc["attributes"]
            page = c.get(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets",
                         {"include": "appScreenshots", "limit": 50})
            state_of = {i["id"]: (i["attributes"].get("assetDeliveryState") or {}).get("state")
                        for i in page.get("included") or []}
            sets = []
            for s in page.get("data") or []:
                ids = [x["id"] for x in (s["relationships"]["appScreenshots"].get("data") or [])]
                sets.append({"type": s["attributes"].get("screenshotDisplayType"), "count": len(ids),
                             "states": sorted({str(state_of.get(i)) for i in ids})})
            entry["localizations"].append({"locale": la.get("locale"), "description": la.get("description") or "",
                                           "whatsNew": la.get("whatsNew") or "", "keywords": la.get("keywords") or "",
                                           "promotionalText": la.get("promotionalText") or "",
                                           "supportUrl": la.get("supportUrl"), "marketingUrl": la.get("marketingUrl"),
                                           "screenshotSets": sets})
        detail = (c.get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data") or {}).get("attributes")
        if detail:
            notes = detail.get("notes") or ""
            entry["review"] = {
                "contact": all(detail.get(k) for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")),
                "notesLength": len(notes), "demoRequired": bool(detail.get("demoAccountRequired")),
                "demoSet": bool(detail.get("demoAccountName") and detail.get("demoAccountPassword")),
                "notesHoldFile": None if review_file is None else review_file in notes}
        snap["platforms"][a["platform"]] = entry

    for s in c.all(f"/v1/apps/{app}/reviewSubmissions",
                   {"limit": 20, "filter[state]": "READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"}):
        platform = s["attributes"].get("platform")
        if platform in snap["platforms"]:
            snap["platforms"][platform]["submissions"].append(s["attributes"].get("state"))

    tag = tag or tag_for(version)
    snap["repo"] = {"tag": tag, "tagCommit": git("rev-parse", "-q", "--verify", tag + "^{commit}"),
                    "description": read_file("fastlane", "metadata", "en-US", "description.txt"),
                    "keywords": read_file("fastlane", "metadata", "en-US", "keywords.txt")}

    urls = set()
    for info in infos:
        urls.update(l["privacyPolicyUrl"] for l in info["localizations"] if l["privacyPolicyUrl"])
    for entry in snap["platforms"].values():
        for loc in entry["localizations"]:
            urls.update(u for u in (loc["supportUrl"], loc["marketingUrl"]) if u)
            urls.update(terms_links(loc["description"]))
    snap["urls"] = {u: url_status(u) for u in sorted(urls)}
    return snap


# ---------------------------------------------------------------- the checks, a pure function of the snapshot

def terms_links(description):
    """Links on a line of the description that names the Terms of Use or EULA."""
    found = []
    for line in description.splitlines():
        if TERMS_WORDS.search(line):
            found.extend(m.group(1).rstrip(".,;") for m in LINK.finditer(line))
    return found


def counts_without_percent(text):
    """Lines that give a result as "N of M" with no percentage beside it (the owner's rule, 2026-11-20)."""
    return [line.strip() for line in text.splitlines() if re.search(r"\b\d+ of \d+\b", line) and "%" not in line]


def check(snap):
    """Returns a list of {level, scope, check, detail}. Reads nothing but the snapshot."""
    out = []

    def add(level, scope, name, detail):
        out.append({"level": level, "scope": scope, "check": name, "detail": detail})

    urls = snap.get("urls", {})

    def url_check(scope, name, url, required=True):
        if not url:
            if required:
                add("FAIL", scope, name, "not set")
            return
        status = urls.get(url)
        if status == 200:
            add("PASS", scope, name, f"{url} answers 200")
        else:
            add("FAIL", scope, name, f"{url} answers {status if status else 'nothing'}")

    version = snap["version"]
    platforms = snap.get("platforms", {})
    has_subscriptions = any(g["subscriptions"] for g in snap.get("subscription_groups", []))

    # App-wide.
    for product in [s for g in snap.get("subscription_groups", []) for s in g["subscriptions"]] + snap.get("purchases", []):
        if product["state"] in BAD_PRODUCT:
            add("FAIL", "APP", "product-state", f"{product['productId']} is {product['state']}")
    if not any(o["check"] == "product-state" for o in out):
        count = sum(len(g["subscriptions"]) for g in snap.get("subscription_groups", [])) + len(snap.get("purchases", []))
        add("PASS", "APP", "product-state", f"{count} subscriptions and purchases, none missing metadata or rejected")

    infos = snap.get("app_infos", [])
    editable = next((i for i in infos if i["state"] not in LIVE), None) or (infos[0] if infos else None)
    live = next((i for i in infos if i["state"] in LIVE), None)
    if not editable:
        add("FAIL", "APP", "app-info", "no app info record")
    else:
        for loc in editable["localizations"]:
            url_check("APP", f"privacy-policy-url[{loc['locale']}]", loc["privacyPolicyUrl"])
            for field in ("name", "subtitle"):
                if len(loc[field]) > 30:
                    add("FAIL", "APP", f"{field}-length[{loc['locale']}]", f"{len(loc[field])} characters, limit 30")
        if editable["ageUnanswered"]:
            add("FAIL", "APP", "age-rating-questions",
                "unanswered: " + ", ".join(editable["ageUnanswered"]) + ". Apple, 2026-11-02: from 2026-11-16 these declarations "
                "must be provided when submitting an app update, and by 2027-01-12 for every app (App Store Connect, App "
                "Information, Age Rating)")
        else:
            add("PASS", "APP", "age-rating-questions", "every content question is answered")
        if live and live is not editable and live["ageRating"] != editable["ageRating"]:
            add("INFO", "APP", "age-rating-change",
                f"live is {live['ageRating']} (override {live['ageOverride']}), this version computes {editable['ageRating']} "
                f"(override {editable['ageOverride']})")

    builds = {p: (e["build"] or {}).get("version") for p, e in platforms.items()}
    commits = {p: (e["build"] or {}).get("commit") for p, e in platforms.items()}
    for platform in PLATFORMS:
        if platform not in platforms:
            add("FAIL", platform, "version-record", f"no {version} record")
    if len(platforms) > 1:
        if len(set(builds.values())) == 1 and None not in builds.values():
            add("PASS", "APP", "same-build", f"build {next(iter(builds.values()))} on every platform")
        else:
            add("FAIL", "APP", "same-build", ", ".join(f"{NAME.get(p, p)} {b}" for p, b in sorted(builds.items())))

    repo = snap.get("repo", {})
    known = {c for c in commits.values() if c}
    if not known:
        add("WARN", "APP", "build-commit", "no Xcode Cloud run found for the attached build, so its commit is unknown")
    elif len(known) > 1:
        add("FAIL", "APP", "build-commit", "the platforms' builds come from different commits: " + ", ".join(sorted(c[:8] for c in known)))
    elif repo.get("tagCommit"):
        commit = next(iter(known))
        if commit == repo["tagCommit"]:
            add("PASS", "APP", "build-commit", f"tag {repo['tag']} and the build are both {commit[:8]}")
        else:
            add("FAIL", "APP", "build-commit", f"tag {repo['tag']} is {repo['tagCommit'][:8]}, the build is {commit[:8]}")
    else:
        add("WARN", "APP", "build-commit", f"the build is {next(iter(known))[:8]}; tag {repo.get('tag')} does not exist yet, put it there")

    # Per platform.
    for platform, e in sorted(platforms.items()):
        state = e["state"]
        if state in SUBMITTABLE:
            add("PASS", platform, "state", f"{state}, can be submitted")
            if any(s in OPEN_SUBMISSION for s in e["submissions"]):
                add("FAIL", platform, "open-submission", "a submission is already " + ", ".join(e["submissions"]))
        elif state in SUBMITTED or state in LIVE:
            add("INFO", platform, "state", f"{state}: already submitted, the checks below describe what Apple has")
        else:
            add("WARN", platform, "state", f"{state}")
        if e["submissions"] and "UNRESOLVED_ISSUES" in e["submissions"]:
            add("FAIL", platform, "unresolved-issues", "the submission has unresolved issues; read the message in App Store Connect")

        b = e["build"]
        if not b:
            add("FAIL", platform, "build", "no build attached")
        else:
            problems = []
            if b["processingState"] != "VALID":
                problems.append(f"processing state {b['processingState']}")
            if b["expired"]:
                problems.append("expired")
            if b["usesNonExemptEncryption"] is None:
                problems.append("export compliance not answered")
            add("FAIL" if problems else "PASS", platform, "build",
                f"build {b['version']}: " + (", ".join(problems) if problems else "valid, not expired, export compliance answered"))

        if not e["copyright"]:
            add("FAIL", platform, "copyright", "not set")
        if not e["localizations"]:
            add("FAIL", platform, "localizations", "none")
        for loc in e["localizations"]:
            tag = f"[{loc['locale']}]"
            for field, limit in LIMITS.items():
                length = len(loc[field])
                if length > limit:
                    add("FAIL", platform, f"{field}-length{tag}", f"{length} characters, limit {limit}")
                elif length == 0 and field != "promotionalText":
                    add("FAIL", platform, f"{field}-length{tag}", "empty")
                else:
                    add("PASS", platform, f"{field}-length{tag}", f"{length} of {limit}")

            if has_subscriptions:
                links = terms_links(loc["description"])
                if snap.get("custom_eula"):
                    add("PASS", platform, f"terms-link{tag}", "a custom EULA is set in App Store Connect")
                elif not links:
                    add("FAIL", platform, f"terms-link{tag}",
                        "the app sells auto-renewable subscriptions and the description has no Terms of Use (EULA) link "
                        "(Guideline 3.1.2; this rejected 5.8 on 2026-11-20)")
                else:
                    dead = [u for u in links if urls.get(u) != 200]
                    if dead:
                        add("FAIL", platform, f"terms-link{tag}", "does not answer 200: " + ", ".join(dead))
                    else:
                        add("PASS", platform, f"terms-link{tag}", links[0] + " answers 200")
            else:
                add("PASS", platform, f"terms-link{tag}", "no auto-renewable subscriptions, so no link is required")

            url_check(platform, f"support-url{tag}", loc["supportUrl"])
            url_check(platform, f"marketing-url{tag}", loc["marketingUrl"], required=False)

            types = {s["type"]: s for s in loc["screenshotSets"]}
            need = [("Mac", MAC_SETS)] if platform == "MAC_OS" else [("iPhone", IPHONE_SETS), ("13-inch iPad", IPAD_SETS)]
            for label, wanted in need:
                have = [types[t] for t in wanted if t in types and types[t]["count"] > 0]
                if not have:
                    add("FAIL", platform, f"screenshots-{label.split()[-1].lower()}{tag}", f"no {label} screenshots")
            bad = [s for s in loc["screenshotSets"] if s["count"] > 10 or [x for x in s["states"] if x != "COMPLETE"]]
            if bad:
                add("FAIL", platform, f"screenshots{tag}",
                    "; ".join(f"{s['type']} has {s['count']}, states {', '.join(s['states'])}" for s in bad))
            elif not any(o["scope"] == platform and o["check"].startswith("screenshots-") and tag in o["check"] for o in out):
                add("PASS", platform, f"screenshots{tag}",
                    ", ".join(f"{s['type']} {s['count']}" for s in sorted(loc["screenshotSets"], key=lambda s: s["type"])) + ", all uploaded")

            if "\u2014" in loc["description"] + loc["whatsNew"] + loc["promotionalText"]:
                add("WARN", platform, f"em-dash{tag}", "the copy holds an em dash (house rule: none)")
            plain = counts_without_percent(loc["whatsNew"])
            if plain:
                add("WARN", platform, f"percentages{tag}",
                    f"{len(plain)} What's New lines give a count with no percentage (house rule, 2026-11-20), first: {plain[0][:90]}")
            if loc["locale"] == "en-US":
                for field in ("description", "keywords"):
                    local = repo.get(field)
                    if local is not None and local != loc[field].strip():
                        add("WARN", platform, f"repo-{field}", f"fastlane/metadata/en-US/{field}.txt differs from App Store Connect")

        r = e["review"]
        if not r:
            add("FAIL", platform, "review-detail", "no App Review information")
        else:
            problems = []
            if not r["contact"]:
                problems.append("contact name, phone or email missing")
            if r["notesLength"] > 4000:
                problems.append(f"notes are {r['notesLength']} characters, limit 4000")
            if r["demoRequired"] and not r["demoSet"]:
                problems.append("a demo account is required and not filled in")
            add("FAIL" if problems else "PASS", platform, "review-detail",
                ", ".join(problems) if problems else f"contact set, notes {r['notesLength']} of 4000")
            if r["notesHoldFile"] is False:
                add("WARN", platform, "review-notes-file", f"the notes do not hold fastlane/review_notes/{version}.txt")
    return out


# ---------------------------------------------------------------- output

def render(snap, results):
    order = {"FAIL": 0, "WARN": 1, "INFO": 2, "PASS": 3}
    counts = {level: sum(1 for r in results if r["level"] == level) for level in order}
    lines = [f"{snap['version']}: {counts['FAIL']} FAIL, {counts['WARN']} WARN, {counts['PASS']} PASS "
             f"(read {snap.get('collected', 'from a snapshot')})",
             "do not submit" if counts["FAIL"] else "nothing here blocks a submission", ""]
    for r in sorted(results, key=lambda r: (order[r["level"]], r["scope"], r["check"])):
        lines.append(f"{r['level']:<5} {NAME.get(r['scope'], r['scope']):<6} {r['check']:<32} {r['detail']}")
    lines += ["", "Not readable through the API, check by hand:"] + ["  - " + n for n in NOT_READABLE]
    lines.append("  - From April 2027 iPhone Duo screenshots are required for apps built with the iOS 27.1 SDK or later "
                 "(Apple's screenshot specifications, read 2026-11-20).")
    return "\n".join(lines)


def main():
    p = argparse.ArgumentParser(description="Read-only check that an App Store version is ready to submit.")
    p.add_argument("version", nargs="?")
    p.add_argument("--app", default=APP_ID)
    p.add_argument("--tag", help="the git tag the build should match (default v<version>.0)")
    p.add_argument("--snapshot", help="check a saved snapshot instead of reading App Store Connect")
    p.add_argument("--save", help="write the snapshot that was read to this file")
    p.add_argument("--json", action="store_true")
    a = p.parse_args()
    if a.snapshot:
        snap = json.load(open(a.snapshot, encoding="utf-8"))
    elif a.version:
        snap = collect(a.version, a.app, a.tag)
    else:
        p.error("give a version, or --snapshot FILE")
    if a.save:
        with open(a.save, "w", encoding="utf-8") as f:
            json.dump(snap, f, indent=2, ensure_ascii=False)
    results = check(snap)
    print(json.dumps({"version": snap["version"], "results": results}, indent=2, ensure_ascii=False) if a.json
          else render(snap, results))
    sys.exit(1 if any(r["level"] == "FAIL" for r in results) else 0)


if __name__ == "__main__":
    main()
