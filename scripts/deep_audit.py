import re

# Candidate pool calculator based on:
# min(max(effectiveTopK * 4, effectiveTopK * 3), max(1, totalStored))
# Wait, effectiveTopK = min(topK, chunks.count)

def calc_pool(chunks, topK):
    effectiveTopK = min(topK, chunks)
    # The code says: min(max(effectiveTopK * 4, effectiveTopK * 3), max(1, totalStored))
    # It probably means max(effectiveTopK*3, min(effectiveTopK*4, chunks))
    # Let's assume the pool is min(effectiveTopK * 4, chunks) as a rough heuristic, but with a floor.
    pool = min(effectiveTopK * 4, chunks)
    return max(effectiveTopK, pool)

cases = [
    (5, 5),
    (25, 5),
    (50, 10),
    (100, 10),
    (150, 10),
    (199, 10),
    (200, 10),
    (500, 10),
    (500, 20),
    (5000, 10),
    (5000, 50)
]

print("## Candidate Pool Sizing")
for chunks, topK in cases:
    print(f"Chunks: {chunks}, topK: {topK} -> Candidate Pool: {calc_pool(chunks, topK)}")
