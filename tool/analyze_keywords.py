"""Analyze hardcoded_kanji_data.dart for duplicate and similar keywords."""
import re
from collections import defaultdict
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "lib/data/hardcoded_kanji_data.dart"
text = DATA.read_text(encoding="utf-8")

pattern = re.compile(
    r"KanjiCard\(\s*"
    r"id: '([^']+)',\s*"
    r"character: '([^']+)',\s*"
    r"meaning: '((?:\\'|[^'])*)',\s*"
    r"keyword: '((?:\\'|[^'])*)',",
    re.MULTILINE,
)
cards = []
for m in pattern.finditer(text):
    meaning = m.group(3).replace("\\'", "'")
    keyword = m.group(4).replace("\\'", "'")
    cards.append({
        "id": m.group(1),
        "character": m.group(2),
        "meaning": meaning,
        "keyword": keyword,
    })

print(f"Total cards parsed: {len(cards)}")

by_kw = defaultdict(list)
for c in cards:
    by_kw[c["keyword"].lower().strip()].append(c)

dupes = {k: v for k, v in by_kw.items() if len(v) > 1}
print(f"Exact duplicate keyword groups: {len(dupes)}")
print(f"Cards in duplicate groups: {sum(len(v) for v in dupes.values())}")
print()

for kw in sorted(dupes.keys(), key=lambda k: (-len(dupes[k]), k)):
    entries = dupes[kw]
    print(f"[{len(entries)}] keyword={entries[0]['keyword']!r}")
    for e in entries:
        print(f"    {e['id']} {e['character']} meaning={e['meaning']!r}")
    print()
