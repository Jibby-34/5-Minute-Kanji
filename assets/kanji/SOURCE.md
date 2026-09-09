# KanjiVG stroke data

Stroke-order assets in `assets/kanji/strokes/` are derived from [KanjiVG](https://kanjivg.tagaini.net).

| Field | Value |
| --- | --- |
| Source | KanjiVG |
| Release | `r20250816` |
| Archive | `kanjivg-20250816-main.zip` |
| Download | https://github.com/KanjiVG/kanjivg/releases/download/r20250816/kanjivg-20250816-main.zip |
| License | Creative Commons Attribution-Share Alike 3.0 |
| Copyright | © 2009–2026 Ulrich Apel |
| Imported kanji | 250 |
| Missing kanji | 0 |

The JSON files are an adaptation of the KanjiVG SVG stroke paths for the kanji
currently included in this app. They are **not** the full KanjiVG repository.

To refresh the data after a new KanjiVG release, update the constants at the
top of `tool/import_kanjivg.dart` if needed and run:

```
dart run tool/import_kanjivg.dart
```

A Python equivalent lives at `tool/import_kanjivg.py`.

Missing from this KanjiVG release:

None.

See `third_party/kanjivg/` for the license text and attribution notice.
