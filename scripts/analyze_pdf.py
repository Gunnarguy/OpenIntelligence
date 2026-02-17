#!/usr/bin/env python3
"""Analyze the Kia Sportage PDF to understand what the raw text layer contains."""
import PyPDF2
import sys
import json
from collections import Counter

pdf = "/Users/gunnarhostetler/Documents/Library/User Manuals/Mik | Kia Sportage X-Pro/2024-sportage.pdf"

with open(pdf, "rb") as f:
    reader = PyPDF2.PdfReader(f)
    total_pages = len(reader.pages)
    print(f"Total pages: {total_pages}")

    # Stats
    total_chars = 0
    total_cjk = 0
    empty_pages = 0
    cjk_char_counter = Counter()
    pages_with_images_only = []

    # Sample specific pages
    sample_pages = [0, 1, 2, 5, 10, 15, 20, 30, 50, 100, 200, 300, 400, 500]

    for pg in sample_pages:
        if pg >= total_pages:
            continue
        text = reader.pages[pg].extract_text() or ""
        total_chars += len(text)

        if len(text.strip()) < 10:
            empty_pages += 1
            pages_with_images_only.append(pg + 1)

        # Count CJK
        for c in text:
            cp = ord(c)
            if 0x4E00 <= cp <= 0x9FFF or 0x3400 <= cp <= 0x4DBF:
                total_cjk += 1
                cjk_char_counter[c] += 1

        print(f"\n{'='*60}")
        print(f"PAGE {pg+1} ({len(text)} chars)")
        print(f"{'='*60}")
        # Show first 600 chars
        preview = text[:600]
        # Highlight CJK chars
        print(preview)

        # Show CJK chars on this page
        page_cjk = [
            c for c in text if 0x4E00 <= ord(c) <= 0x9FFF or 0x3400 <= ord(c) <= 0x4DBF
        ]
        if page_cjk:
            unique = set(page_cjk)
            print(f"\n  >>> {len(page_cjk)} CJK chars, {len(unique)} unique: {unique}")
            print(f"  >>> Unicode: {[f'U+{ord(c):04X}' for c in unique]}")
            # Show context around each CJK char
            for uc in list(unique)[:3]:
                idx = text.find(uc)
                if idx >= 0:
                    ctx_start = max(0, idx - 20)
                    ctx_end = min(len(text), idx + 30)
                    print(f"  >>> Context: ...{repr(text[ctx_start:ctx_end])}...")

    # Now do a full scan of ALL pages for stats
    print(f"\n\n{'='*60}")
    print("FULL DOCUMENT SCAN")
    print(f"{'='*60}")

    all_cjk = Counter()
    full_text_len = 0
    truly_empty = 0
    very_short = 0

    for pg in range(total_pages):
        text = reader.pages[pg].extract_text() or ""
        full_text_len += len(text)
        stripped = text.strip()
        if len(stripped) == 0:
            truly_empty += 1
        elif len(stripped) < 50:
            very_short += 1
        for c in text:
            cp = ord(c)
            if 0x4E00 <= cp <= 0x9FFF or 0x3400 <= cp <= 0x4DBF:
                all_cjk[c] += 1

    print(f"Total text length: {full_text_len:,} chars")
    print(f"Truly empty pages (0 text): {truly_empty}")
    print(f"Very short pages (<50 chars): {very_short}")
    print(f"Total CJK characters across all pages: {sum(all_cjk.values())}")
    print(f"Unique CJK characters: {len(all_cjk)}")
    print(f"Most common CJK:")
    for char, count in all_cjk.most_common(10):
        print(f"  '{char}' (U+{ord(char):04X}): {count} occurrences")
