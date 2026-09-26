from extractor_port import *

# Fictional fixture documents (the real ones are on the owner's Mac, not in this container).
LEASE_S16 = dict(name="Maple Court Lease.pdf", page=4, structure=None, content=(
    "16. NOTICE TO VACATE. Tenant must give Landlord written notice at least sixty (60) days "
    "before the end of the Term if Tenant intends to move out. If Tenant does not give timely "
    "notice, this Lease continues month to month and either party may end it with 60 days' "
    "written notice. Notice must be delivered to Landlord at the address in Section 2."))
LEASE_RENT = dict(name="Maple Court Lease.pdf", page=1, structure=None, content=(
    "4. RENT. Monthly rent is $1,850, due on the 1st. A late fee of 5% applies after the 5th "
    "day of the month. Rent paid by check must be dropped at the office."))
AIR_FRYER_P1 = dict(name="Kestrel AF-620 Air Fryer Manual.pdf", page=1, structure=None, content=(
    "Kestrel AF-620 Air Fryer - Cooking Chart\n"
    "Food | Amount | Temp | Time\n"
    "Frozen fries | 1 lb | 400°F | 15-18 min\n"
    "Chicken wings | 1 lb | 380°F | 22-25 min\n"
    "Brussels sprouts | 1 lb | 375°F | 12-15 min\n"
    "Salmon fillets | 2 fillets | 390°F | 8-10 min\n"
    "Pull the basket out and shake it halfway through. Remove food with tongs; "
    "do not overfill the basket."))
AIR_FRYER_SPECS = dict(name="Kestrel AF-620 Air Fryer Manual.pdf", page=2, structure=None, content=(
    "SPECIFICATIONS\nBasket capacity: 5.8 qt\nPower: 1700 W\nVoltage: 120 V\n"
    "Before first use, remove all packaging and wash the basket. Never pull the basket out "
    "while the fryer is running."))
GYM = dict(name="Iron Harbor Gym Contract.pdf", page=1, structure=None, content=(
    "MEMBERSHIP AGREEMENT. Monthly dues: $39.99. To cancel, give 30 days' written notice at "
    "the front desk. An annual fee of $49 is charged each March."))
INSURANCE = dict(name="Homeowners Declarations.pdf", page=1, structure=None, content=(
    "Policy Declarations. Dwelling coverage: $250,000. Deductible: $1,000. Personal property: "
    "$125,000. Policy period: 01/01/2026 to 01/01/2027."))
SYLLABUS = dict(name="HIST 210 Syllabus.docx", page=1, structure=None, content=(
    "Final paper: 3,000 words, due in Week 14. Late work loses 10% per day. Office hours: "
    "Tue/Thu 2-3 pm. Readings are due before class."))
LIBRARY = [LEASE_S16, LEASE_RENT, AIR_FRYER_P1, AIR_FRYER_SPECS, GYM, INSURANCE, SYLLABUS]

Q = "How much notice do I have to give before I move out?"
FIXES = {
    "current code (b37ab4c)": {},
    "fix A only (expansion needs an anchor)": {"fix_expansion": True},
    "fix B only (exact unit token)": {"fix_units": True},
    "fix A + fix B": {"fix_expansion": True, "fix_units": True},
}


def run(title, query, chunks, via_sniper=False):
    print("=" * 100)
    print(title)
    print(f"Q: {query}")
    if via_sniper:
        picked, words = spec_sniper(query, chunks)
        print(f"  sniper query words: {words}")
        for ch in picked:
            print(f"  sniper picked: {ch['name']} p.{ch['page']}  score={ch['sim']:.3f} hits={ch['sniper_hits']}")
        chunks = picked
    for label, fx in FIXES.items():
        answer, res, log = precision_lock(query, chunks, **fx)
        print(f"-- {label}")
        for line in log:
            print("   " + line)
        if res:
            print(f"   extractor returned {res['value']!r} conf={res['confidence']:.4f}")
        print(f"   => {'LOCKED (model skipped): ' + answer if answer else 'no lock -> question goes to the model'}")


# 1. The reported case, Deep Think path: sniper over every chunk, then the extractor.
run("REPORTED CASE via spec sniper (Deep Think / Maximum precision path)", Q, LIBRARY, via_sniper=True)

# 2. The minimal regression fixture: lease clause + a document with unrelated measurements.
for ch in (LEASE_S16, AIR_FRYER_P1):
    ch["sim"] = 0.70
run("MINIMAL FIXTURE: lease s16 + air fryer chart, passed straight to the extractor", Q, [LEASE_S16, AIR_FRYER_P1])

# 3. Why fix B alone is not enough: same question, the specs page is in the candidate set.
AIR_FRYER_SPECS["sim"] = 0.70
run("NOTICE QUESTION vs a page with a genuine liquid unit (5.8 qt)", Q, [LEASE_S16, AIR_FRYER_SPECS])

# Positive controls: what the extractor exists for must keep locking.
CAR = dict(name="Owner's Manual.pdf", page=312, structure=None, sim=0.80, content=(
    "ENGINE OIL. Oil capacity with filter change: 4.5 L (4.8 qt). Use SAE 0W-20 synthetic oil."))
run("CONTROL: car oil capacity (must still lock 4.5 L / 4.8 qt)", "How much oil does the engine take?", [CAR])
FRYER_CAP = dict(AIR_FRYER_SPECS, sim=0.80)
run("CONTROL: basket capacity (must still lock 5.8 qt)", "How much food does the basket hold?", [FRYER_CAP])

# Fix B's own defect: a capacity question with only a weight measurement nearby.
TRUCK = dict(name="Truck Manual.pdf", page=9, structure=None, sim=0.80, content=(
    "SPECIFICATIONS. Curb weight: 3,200 lb. Payload capacity: 1,500 lb. Fuel tank: 21 gallons."))
run("CONTROL: fuel question, weight + gallons nearby (must pick gallons, never lb)",
    "How much fuel does the tank hold?", [TRUCK])
TRUCK2 = dict(name="Truck Manual.pdf", page=9, structure=None, sim=0.80, content=(
    "SPECIFICATIONS. Curb weight: 3,200 lb. Payload capacity: 1,500 lb. Tank size is on the fuel door."))
run("CONTROL: fuel question, ONLY weights nearby (must not lock a weight)",
    "How much fuel does the tank hold?", [TRUCK2])
