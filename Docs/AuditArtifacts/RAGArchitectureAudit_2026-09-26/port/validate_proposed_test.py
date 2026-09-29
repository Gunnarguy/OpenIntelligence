import re
import extractor_port as P

# Mirror the PROPOSED Swift helper exactly: strip number and optional US qualifier, exact set lookup.
def proposed_unit(value):
    return re.sub(r"^\s*\d+(?:[.,]\d+)?\s*(?:u\.?s\.?\s*)?", "", value.lower()).strip()
PROPOSED_LIQUID = {"l", "liter", "liters", "gal", "gals", "gallon", "gallons", "qt", "qts", "quart", "quarts"}
P.unit_of = proposed_unit
P.LIQUID_UNITS_EXACT = PROPOSED_LIQUID

# The Swift test's fixtures, joined exactly as the multi-line literals with trailing "\" join them.
LEASE = ("16. NOTICE TO VACATE. Tenant must give Landlord written notice at least sixty (60) days "
         "before the end of the Term if Tenant intends to move out. If Tenant does not give timely "
         "notice, this Lease continues month to month and either party may end it with 60 days' "
         "written notice. Notice must be delivered to Landlord at the address in Section 2.")
CHART = ("Kestrel AF-620 Air Fryer - Cooking Chart\nFood | Amount | Temp | Time\n"
         "Frozen fries | 1 lb | 400°F | 15-18 min\nChicken wings | 1 lb | 380°F | 22-25 min\n"
         "Brussels sprouts | 1 lb | 375°F | 12-15 min\nSalmon fillets | 2 fillets | 390°F | 8-10 min\n"
         "Pull the basket out and shake it halfway through. Remove food with tongs; do not overfill the basket.")
SPECS = ("SPECIFICATIONS\nBasket capacity: 5.8 qt\nPower: 1700 W\nVoltage: 120 V\n"
         "Before first use, remove all packaging and wash the basket. Never pull the basket out while "
         "the fryer is running.")
TRUCK = "SPECIFICATIONS. Curb weight: 3,200 lb. Payload capacity: 1,500 lb. Tank size is on the fuel door."
def ch(content, name, page): return dict(name=name, page=page, structure=None, sim=0.70, content=content)
Q = "How much notice do I have to give before I move out?"
TESTS = [
  ("testNoticeQuestionDoesNotLockAWeightFromACookingChart", Q, [ch(LEASE, "Lease", 4), ch(CHART, "Fryer", 1)], None),
  ("testNoticeQuestionDoesNotLockALiquidCapacity", Q, [ch(LEASE, "Lease", 4), ch(SPECS, "Fryer", 2)], None),
  ("testFuelQuestionDoesNotLockAWeight", "How much fuel does the tank hold?", [ch(TRUCK, "Truck", 9)], None),
  ("testCapacityQuestionStillLocksItsLiquidValue", "How much food does the basket hold?", [ch(SPECS, "Fryer", 2)], "5.8 qt"),
]
for label, fx in [("CURRENT code", {}), ("A1 only", {"fix_expansion": True}), ("A2 only", {"fix_units": True}),
                  ("PROPOSED A1+A2", {"fix_expansion": True, "fix_units": True})]:
    print(f"== {label}")
    for name, q, chunks, expected in TESTS:
        res, _ = P.extract(q, chunks, **fx)
        span = res["value"] if res and res["confidence"] >= 0.82 else None
        conf = f"{res['confidence']:.4f}" if res else "failure"
        status = "PASS" if span == expected else "FAIL"
        print(f"   {status}  {name}: locked={span!r} (extractor: {res['value'] if res else None!r} {conf})")
# unit helper spot checks
for v in ["1 lb", "3,200 lb", "14.3 US gal", "14.3 U.S. gal", "4.5L", "4.5 L", "5.8 qt", "2 fl oz", "25 lb-ft", "5 mL"]:
    print(f"   unit({v!r}) = {proposed_unit(v)!r}  liquid={proposed_unit(v) in PROPOSED_LIQUID}")
