"""
Python re-implementation of the OpenIntelligence extractive-lookup decision path, for
reproducing the 2026-09-25 "1 lb" answer without a Swift toolchain.

THIS IS A PORT, NOT THE SWIFT CODE. Evidence from it is `inferred`: it shows what the Swift
logic computes if the port is faithful. Ported from, at b37ab4c:
  - SpecificationExtractor.swift: parseQueryEntities (1430-1511), extract (117-374),
    findCandidates (391-451), scoreCandidate (461-564), isMeasurementStyleQuery (566-568),
    isMeasurementKeyword (570-576), isMeasurementAnchorKeyword (578-581),
    measurementUnitMatchesQuery (583-615), looksLikeIndexReference (617-629),
    extractFromStructuredTables (1288-1403)
  - SpecificationDetector.swift: universalPatterns + detectSpecifications
  - RAGService.swift: highPrecisionLookupOverrideAnswer (17962-18012), specTableSniper
    (2527-2578), buildSpecSearchConcepts, stopWords (3616-3629)
  - EvidenceScoringPolicyService.swift: specSniperScore (311-365), precisionLockThreshold (82-84)

Known port limits: Python `re` stands in for ICU (NSRegularExpression); offsets are code points
rather than grapheme clusters (identical for the ASCII + '°' fixtures here); the two
state-mapping phases are not ported and the port asserts they would exit early.
"""
import re

# ---------------------------------------------------------------- SpecificationDetector
UNIVERSAL_PATTERNS = [
    ("Code", r"[A-Z]{2,}[-\s]?\d+[A-Z0-9-]*"),
    ("Standard", r"(?:ISO|ASTM|SAE|DIN|EN|ANSI|IEEE|IEC|BS|JIS|NF|UL)\s*[-:]?\s*\d+(?:[A-Z])?(?:[-.:]\d+)*"),
    ("Measurement", r"\b\d+(?:[.,]\d+)?\s*(?:(?:U\.?S\.?\s*)?(?:gal(?:lon)?s?|qt|qts?|L|mL|ml|oz|fl\.?\s*oz|kg|g|mg|µg|lb|lbs|psi|bar|kPa|MPa|Pa|Nm|N·m|ft-?lb|lb-?ft|in-?lb|V|kV|mV|A|mA|W|kW|MW|HP|hp|Hz|kHz|MHz|GHz|Ω|ohm|°[CF]|deg(?:rees?)?\s*[CF]|mm|cm|m|km|in|ft|yd|mi))\b"),
    ("Grade", r"\d+W-\d+"),
    ("PartNumber", r"(?-i:(?=[A-Z0-9.-]*\d)[A-Z0-9]{2,}[-\.][A-Z0-9]{2,}(?:[-\.][A-Z0-9]{2,})*)"),
    ("Percentage", r"\d+(?:[.,]\d+)?\s*%"),
    ("Range", r"\d+(?:[.,]\d+)?\s*[-–—to]\s*\d+(?:[.,]\d+)?"),
    ("Ratio", r"\d+\s*[:/]\s*\d+"),
]
COMPILED = [(c, re.compile(p, re.IGNORECASE)) for c, p in UNIVERSAL_PATTERNS]


def detect_specifications(text):
    results, seen = [], set()
    for category, rx in COMPILED:
        for m in rx.finditer(text):
            key = (m.start(), m.end())
            if key in seen:
                continue
            seen.add(key)
            results.append((category, m.group(0), m.start()))
    return results


# ---------------------------------------------------------------- query parsing
PARSE_STOPWORDS = {
    "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
    "what", "which", "who", "whom", "whose", "where", "when", "why", "how",
    "do", "does", "did", "will", "would", "could", "should", "can", "may",
    "this", "that", "these", "those", "it", "its",
    "for", "of", "in", "on", "at", "to", "from", "by", "with",
    "i", "me", "my", "you", "your", "we", "our", "they", "their",
    "kind", "type", "sort", "take", "use", "need", "require", "want",
}
ANCHOR_KEYWORDS = {"gas", "gasoline", "fuel", "tank", "capacity", "volume", "coolant", "oil"}
MEASUREMENT_KEYWORDS = {
    "capacity", "volume", "gallons", "gallon", "liters", "liter", "quarts", "quart",
    "weight", "length", "width", "height", "pressure", "temperature", "amount", "size",
}


def tokenize(q):
    return [t for t in re.split(r"[^0-9a-z]+", q.lower()) if len(t) >= 2 and t not in PARSE_STOPWORDS]


def parse_query_entities(query, fix_expansion=False):
    tokens = tokenize(query)
    primary, descriptive = [], []
    for t in tokens:
        has_digits = any(ch.isdigit() for ch in t)
        digit_count = sum(ch.isdigit() for ch in t)
        if has_digits and digit_count >= 3:
            primary.append(t)
        elif has_digits and len(t) <= 6:
            likely_word = all(ch.isalnum() for ch in t) and t[0].isalpha() and digit_count == 1
            (descriptive if likely_word else primary).append(t)
        else:
            descriptive.append(t)
    # line 1482 (current) vs the proposed guard
    quantity_word = "much" in tokens or "many" in tokens
    if fix_expansion:
        trigger = "capacity" in tokens or (quantity_word and any(t in ANCHOR_KEYWORDS for t in tokens))
    else:
        trigger = "capacity" in tokens or quantity_word
    if trigger:
        descriptive += ["liters", "quarts", "gallons", "capacity", "volume"]
    if "gas" in tokens:
        descriptive += ["fuel", "gasoline"]
    if "fuel" in tokens or "gasoline" in tokens:
        descriptive += ["gas"]
    if {"hold", "holds", "holding"} & set(tokens):
        descriptive += ["capacity", "volume"]
    if "car" in tokens:
        descriptive.append("vehicle")
    ordered_log = descriptive[:5]  # line 1502 logs prefix(5) of the ORDERED list
    return {
        "tokens": tokens,
        "keywords": set(primary + descriptive),
        "primary": primary,
        "descriptive": set(descriptive),  # line 1509: Array(Set(...)) -> order discarded
        "descriptive_ordered": descriptive,
        "log_1502": ordered_log,
    }


# ---------------------------------------------------------------- scoring
def unit_of(value):
    """Proposed helper: the unit token of a detected measurement, lowercased."""
    return re.sub(r"^\s*\d+(?:[.,]\d+)?\s*", "", value).strip().lower()


LIQUID_UNITS_EXACT = {"l", "liter", "liters", "litre", "litres", "gal", "gals", "gallon", "gallons",
                      "us gal", "u.s. gal", "us gallon", "us gallons", "qt", "qts", "quart", "quarts"}


def measurement_unit_matches(value, qe, fix_units=False):
    v = value.lower()
    d = qe["descriptive"]
    if d & {"gallons", "gallon", "capacity", "volume", "liters", "liter", "quarts", "quart"}:
        if fix_units:
            if unit_of(value) in LIQUID_UNITS_EXACT:
                return True
        elif any(u in v for u in ["us gal", "gal", "gallon", "gallons", "l)", " l", "liter", "liters", "qt", "quarts", "quart"]):
            return True
    if "weight" in d and any(u in v for u in ["kg", "lb", "lbs", "oz", "g "]):
        return True
    if d & {"length", "width", "height", "size"} and any(u in v for u in ["mm", "cm", " m", "in", "inch", "ft"]):
        return True
    if "pressure" in d and any(u in v for u in ["psi", "kpa", "bar"]):
        return True
    return False


def is_measurement_style(qe):
    return any(k in MEASUREMENT_KEYWORDS for k in qe["descriptive"])


def looks_like_index_reference(value):
    n = value.strip()
    if "\n" in n:
        return True
    if re.search(r"\b\d+-\d+\b", n):
        return True
    if re.search(r"\bvolume\s+\d+-\d+\b", n, re.IGNORECASE):
        return True
    return False


def find_candidates(content, chunk, keywords):
    lower = content.lower()
    is_table = chunk.get("structure") == "table" or ("|" in content and len(content.split("|")) >= 4)
    is_list = chunk.get("structure") == "list" or "•" in content or re.match(r"^\s*[-*]\s+", content) is not None
    out = []
    for category, value, pos in detect_specifications(content):
        nearest, matched = 10**9, []
        for kw in keywords:
            start = 0
            while True:
                i = lower.find(kw, start)
                if i < 0:
                    break
                dist = abs(i - pos)
                if dist < 100 and kw not in matched:
                    matched.append(kw)
                nearest = min(nearest, dist)
                start = i + len(kw)
        if nearest < 500:
            out.append(dict(value=value, category=category, chunk=chunk, pos=pos, prox=nearest,
                            matched=matched, table=is_table, list=is_list))
    return out


def score_candidate(c, qe, fix_units=False, explain=False):
    parts = {}
    ms = is_measurement_style(qe)
    p = c["prox"]
    parts["proximity"] = 0.25 if p < 50 else 0.20 if p < 100 else 0.15 if p < 200 else max(0, 0.10 - (p - 200) / 3000)
    parts["kw_ratio"] = len(c["matched"]) / max(1, len(qe["keywords"])) * 0.15
    parts["structure"] = 0.10 if c["table"] else (0.05 if c["list"] else 0)
    parts["chunk_rel"] = min(0.10, c["chunk"]["sim"] * 0.15)
    cat = c["category"]
    if cat == "Grade":
        parts["type"] = 0.10
    elif cat == "PartNumber":
        parts["type"] = 0.08
    elif cat in ("Code", "Standard"):
        parts["type"] = 0.06
    elif cat == "Measurement":
        v = c["value"].lower()
        dt = "km" in v or "mile" in v or "hour" in v or v.endswith(" m") or v.endswith("\nm") or v.endswith("\tm")
        parts["type"] = 0.01 if dt else 0.05
    else:
        parts["type"] = 0.02
    if ms:
        if cat == "Measurement":
            parts["measure_style"] = 0.12
            if measurement_unit_matches(c["value"], qe, fix_units):
                parts["unit_match"] = 0.22
            if any(k in ANCHOR_KEYWORDS for k in c["matched"]):
                parts["anchor"] = 0.10
        elif looks_like_index_reference(c["value"]):
            parts["index_ref"] = -0.20
    elif looks_like_index_reference(c["value"]):
        parts["index_ref"] = -0.10
    vl = c["value"].lower()
    if any(len(e) >= 3 and e in vl for e in qe["primary"]):
        parts["entity"] = 0.50
    elif qe["primary"]:
        parts["entity"] = -0.10
    if any(len(k) >= 4 and k in vl for k in qe["descriptive"]):
        parts["desc_contain"] = 0.10
    total = max(0.0, min(1.0, sum(parts.values())))
    return (total, parts) if explain else total


PART_RX = re.compile(r"(?-i:(?=[A-Z0-9.-]*\d)[A-Z0-9]{2,}[-\.][A-Z0-9]{2,}(?:[-\.][A-Z0-9]{2,})*)", re.IGNORECASE)


def structured_tables(chunks, qe):
    best = None
    for ch in chunks:
        content = ch["content"]
        for m in PART_RX.finditer(content):
            pn = m.group(0)
            if "press" in pn.lower():
                continue
            if re.search(r"^\d{1,4}[-\.]\d{1,4}[-\.]\d{1,4}$", pn):
                continue
            if re.search(r"^\d{2,4}[-\.]\d{2,4}$", pn) and all(x.isdigit() or x in "-." for x in pn):
                continue
            before = content[max(0, m.start() - 120):m.start()].lower()
            after = content[m.end():m.end() + 60].lower()
            full = before + " " + after
            score = 0.0
            ent_pn = any(e in pn.lower() for e in qe["primary"])
            ent_ctx = any(e in full for e in qe["primary"])
            if ent_pn or ent_ctx:
                score += 0.50
            elif qe["primary"]:
                continue
            kic = [k for k in qe["descriptive"] if len(k) >= 3 and k in full]
            score += len(kic) * 0.15
            score += 0.30 if len(kic) >= 3 else (0.20 if len(kic) >= 2 else 0)
            if best is None or score > best[1]:
                best = (pn, score, ch, kic)
    if best and best[1] >= 0.55:
        has_digit = any(x.isdigit() for x in best[0])
        is_meas = bool(qe["descriptive"] & {"capacity", "volume", "liters", "gallons", "quarts", "size", "weight",
                                             "length", "width", "height", "diameter", "pressure", "temperature"})
        if is_meas and not has_digit:
            return None
        return dict(value=best[0], category="ProximityMatch", confidence=min(0.90, best[1] * 0.8 + 0.25),
                    chunk=best[2], note=f"keywords in context {best[3]}")
    return None


STATE_TERMS = ["solid", "flashing", "flash", "blink", "blinking", "steady", "pulsing", "rapid", "slow"]
STATE_COLORS = ["red", "green", "blue", "yellow", "amber", "orange", "purple", "white", "cyan", "magenta"]


def extract(query, chunks, fix_expansion=False, fix_units=False, verbose=True):
    log = []
    qe = parse_query_entities(query, fix_expansion)
    lower = query.lower()
    # Both state phases exit on these guards (SpecificationExtractor.swift:661-662, 721-722);
    # the port refuses to continue if a query would reach them.
    assert not any(re.search(rf"\b{c}\b", lower) for c in STATE_COLORS), "state phase not ported"
    assert not any(s in lower for s in STATE_TERMS), "state phase not ported"
    if not qe["keywords"]:
        return None, log
    log.append(f"[1502] Descriptive (ordered prefix 5): {qe['log_1502']}")
    log.append(f"       full descriptive set ({len(qe['descriptive'])}): {sorted(qe['descriptive'])}")
    log.append(f"       measurement-style query: {is_measurement_style(qe)}")
    st = structured_tables(chunks, qe)
    if st:
        log.append(f"Structured-table phase locked {st['value']!r} conf={st['confidence']:.2f} ({st['note']})")
        return st, log
    cands = []
    for ch in chunks:
        cands += find_candidates(ch["content"], ch, qe["keywords"])
    if not cands:
        log.append("noSpecsFound")
        return None, log
    scored = sorted(((c, score_candidate(c, qe, fix_units)) for c in cands), key=lambda x: -x[1])
    prefers = is_measurement_style(qe) and any(
        c["category"] == "Measurement" and measurement_unit_matches(c["value"], qe, fix_units) for c, _ in scored)
    has_grade = any(c["category"] == "Grade" for c, _ in scored)
    if prefers:
        rel = [(c, s) for c, s in scored if c["category"] == "Measurement" or measurement_unit_matches(c["value"], qe, fix_units)]
    elif has_grade:
        rel = [(c, s) for c, s in scored if c["category"] != "Code" or any(k in c["value"].lower() for k in qe["keywords"])]
    else:
        f = [(c, s) for c, s in scored if c["category"] != "Code" or c["matched"]]
        rel = f if f else scored
    if not rel:
        return None, log
    best, best_score = rel[0]
    for c, s in rel[:3]:
        _, parts = score_candidate(c, qe, fix_units, explain=True)
        log.append(f"Candidate {c['value']!r} ({c['category']}) score={s:.4f} from {c['chunk']['name']}  "
                   f"matched={c['matched']} parts={ {k: round(v, 4) for k, v in parts.items()} }")
    top = [(c, s) for c, s in rel if s >= best_score * 0.9]
    if len(top) > 1 and len({c["value"] for c, _ in top}) > 1:
        if not qe["primary"]:
            if len({c["category"] for c, _ in top}) != 1:
                log.append(f"ambiguousMultiple {sorted({c['value'] for c, _ in top})}")
                return None, log
        else:
            raise NotImplementedError("entity branch not exercised by these fixtures")
    if best_score < 0.65:
        log.append(f"lowConfidence {best_score:.4f} < 0.65")
        return None, log
    return dict(value=best["value"], category=best["category"], confidence=best_score, chunk=best["chunk"]), log


def precision_lock(query, chunks, **fixes):
    """highPrecisionLookupOverrideAnswer for an extractive-first intent: threshold 0.82."""
    res, log = extract(query, chunks, **fixes)
    if res and res["confidence"] >= 0.82:
        cite = f"[{res['chunk']['name']}, p.{res['chunk']['page']}]"
        if res["category"] == "Measurement":
            return f"{res['value']}. {cite}", res, log
        return f"{res['value']} {cite}", res, log
    return None, res, log


# ---------------------------------------------------------------- spec sniper
RAG_STOPWORDS = set("""a an the is are was were be been being have has had do does did will would could should
may might must shall can need dare ought used to of in for on with at by from as into through during before after
above below between under again further then once here there when where why how all each few more most other some
such no nor not only own same so than too very just also now what which who whom this that these those am it its i
me my myself we our ours ourselves you your yours he him his she her hers they them their""".split())
CROSS_REF = ["given in", "refer to", "see page", "found in", "listed in", "shown in", "specified in", "provided in"]
ALIAS = {
    "gas": ["gasoline", "fuel"], "gasoline": ["gas", "fuel"], "fuel": ["gas", "gasoline"],
    "gallon": ["gal", "gallon", "gallons", "galon", "galons", "us gal"],
    "gallons": ["gal", "gallon", "gallons", "galon", "galons", "us gal"],
    "gal": ["gal", "gallon", "gallons", "galon", "galons", "us gal"],
    "capacity": ["capacity", "capacities", "volume"], "capacities": ["capacity", "capacities", "volume"],
    "hold": ["capacity", "capacities", "volume"], "holds": ["capacity", "capacities", "volume"],
    "holding": ["capacity", "capacities", "volume"], "vehicle": ["car"], "car": ["vehicle"],
}
SNIPER_MEAS = re.compile(r"\d+(?:\.\d+)?\s*(?:L|qt|gal|ml|mL|mg|g|kg|lb|oz|psi|kPa|bar|mm|cm|km|in|ft|yd|V|A|W|kW|mA|Ah|kWh|Hz|MHz|GHz|%|cc|cu)\b", re.IGNORECASE)


def spec_sniper(query, all_chunks):
    words = [w for w in re.split(r"[^0-9a-z]+", query.lower()) if len(w) > 2 and w not in (RAG_STOPWORDS | {"many", "much"})]
    concepts, seen = [], set()
    for w in words:
        if w in seen:
            continue
        seen.add(w)
        concepts.append([a for a in set([w] + ALIAS.get(w, [])) if len(a) > 1])
    if len(concepts) < 2:
        return [], words
    scored = []
    for ch in all_chunks:
        c, cl = ch["content"], ch["content"].lower()
        hits = [al for al in concepts if any(a in cl for a in al)]
        if len(hits) < min(2, len(concepts)) or not re.search(r"\d", c):
            continue
        s = 0.60 + len(hits) / max(1, len(concepts)) * 0.15
        if ch.get("structure") == "table":
            s += 0.10
        if "|" in c and len(c.split("|")) >= 4:
            s += 0.08
        if SNIPER_MEAS.search(c):
            s += 0.08
        if len([ln for ln in c.split("\n") if (":" in ln or "\t" in ln) and re.search(r"\d", ln)]) >= 2:
            s += 0.05
        if any(x in cl for x in CROSS_REF) and "page" in cl:
            s -= 0.20
        scored.append((ch, s, len(hits), [al[0] for al in hits]))
    scored.sort(key=lambda x: (-round(x[1], 2), -x[2]))
    return [dict(ch, sim=s, sniper_hits=h) for ch, s, _, h in scored[:3]], words
