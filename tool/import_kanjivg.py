#!/usr/bin/env python3
"""Download KanjiVG and emit stroke JSON for kanji in this app's dataset.

Re-run this script to refresh stroke data after a KanjiVG release. Application
code does not need to change when the dataset is updated.

Usage (from the repository root):

    python tool/import_kanjivg.py
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

KANJIVG_RELEASE = "r20250816"
KANJIVG_ZIP_NAME = "kanjivg-20250816-main.zip"
KANJIVG_ZIP_URL = (
    "https://github.com/KanjiVG/kanjivg/releases/download/"
    f"{KANJIVG_RELEASE}/{KANJIVG_ZIP_NAME}"
)
KANJIVG_COPYING_URL = (
    "https://raw.githubusercontent.com/KanjiVG/kanjivg/master/COPYING"
)
KANJIVG_SITE = "https://kanjivg.tagaini.net"
KANJIVG_LICENSE = "Creative Commons Attribution-Share Alike 3.0"

SVG_NS = "http://www.w3.org/2000/svg"
PATH_TAG = f"{{{SVG_NS}}}path"
TEXT_TAG = f"{{{SVG_NS}}}text"
SVG_TAG = f"{{{SVG_NS}}}svg"
G_TAG = f"{{{SVG_NS}}}g"

CHARACTER_RE = re.compile(r"character:\s*'(.+?)'")
DOCTYPE_RE = re.compile(r"<!DOCTYPE[\s\S]*?\]>\s*", re.MULTILINE)
STROKE_ID_RE = re.compile(r"-s(\d+)$")
MATRIX_RE = re.compile(
    r"matrix\(\s*([-\d.eE]+)\s+([-\d.eE]+)\s+([-\d.eE]+)\s+"
    r"([-\d.eE]+)\s+([-\d.eE]+)\s+([-\d.eE]+)\s*\)"
)
TRANSLATE_RE = re.compile(
    r"translate\(\s*([-\d.eE]+)(?:\s*[,\s]\s*([-\d.eE]+))?\s*\)"
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def unicode_hex(character: str) -> str:
    return f"{ord(character):05x}"


def read_dataset_characters(data_path: Path) -> list[str]:
    text = data_path.read_text(encoding="utf-8")
    characters: list[str] = []
    seen: set[str] = set()
    for match in CHARACTER_RE.finditer(text):
        glyph = match.group(1)
        if glyph in seen:
            continue
        seen.add(glyph)
        characters.append(glyph)
    return characters


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "5-Minute-Kanji"})
    with urllib.request.urlopen(request) as response:
        dest.write_bytes(response.read())
    print(f"Saved {dest} ({dest.stat().st_size} bytes)")


def strip_doctype(svg_text: str) -> str:
    return DOCTYPE_RE.sub("", svg_text, count=1)


def parse_viewbox(root: ET.Element) -> list[float]:
    raw = root.get("viewBox") or root.get("viewbox") or "0 0 109 109"
    parts = [float(part) for part in raw.replace(",", " ").split() if part]
    if len(parts) != 4:
        return [0.0, 0.0, 109.0, 109.0]
    return parts


def stroke_sort_key(path: ET.Element) -> int:
    match = STROKE_ID_RE.search(path.get("id") or "")
    if match:
        return int(match.group(1))
    return 10_000


def parse_number_position(transform: str | None) -> list[float] | None:
    if not transform:
        return None
    matrix = MATRIX_RE.search(transform)
    if matrix:
        return [round(float(matrix.group(5)), 2), round(float(matrix.group(6)), 2)]
    translate = TRANSLATE_RE.search(transform)
    if translate:
        x = round(float(translate.group(1)), 2)
        y = round(float(translate.group(2) or 0.0), 2)
        return [x, y]
    return None


def extract_stroke_data(svg_text: str, character: str) -> dict:
    xml = strip_doctype(svg_text)
    root = ET.fromstring(xml)
    if root.tag != SVG_TAG:
        svg = root.find(f".//{SVG_TAG}")
        if svg is None:
            raise ValueError("SVG root not found")
        root = svg

    hex_id = unicode_hex(character)
    stroke_paths_group = None
    stroke_numbers_group = None
    for group in root.iter(G_TAG):
        group_id = group.get("id") or ""
        if group_id.startswith("kvg:StrokePaths"):
            stroke_paths_group = group
        elif group_id.startswith("kvg:StrokeNumbers"):
            stroke_numbers_group = group

    search_root = stroke_paths_group if stroke_paths_group is not None else root
    paths = [node for node in search_root.iter(PATH_TAG) if node.get("d")]
    paths.sort(key=stroke_sort_key)
    if not paths:
        raise ValueError("no stroke paths")

    numbers: dict[int, list[float]] = {}
    if stroke_numbers_group is not None:
        for text_node in stroke_numbers_group.iter(TEXT_TAG):
            label = "".join(text_node.itertext()).strip()
            if not label.isdigit():
                continue
            position = parse_number_position(text_node.get("transform"))
            if position is None:
                continue
            numbers[int(label)] = position

    strokes = []
    for index, path in enumerate(paths, start=1):
        entry: dict = {"d": path.get("d", "").strip()}
        if index in numbers:
            entry["number"] = numbers[index]
        strokes.append(entry)

    return {
        "character": character,
        "unicode": hex_id,
        "viewBox": parse_viewbox(root),
        "strokes": strokes,
    }


def find_svg_in_zip(archive: zipfile.ZipFile, hex_id: str) -> str | None:
    suffix = f"/{hex_id}.svg"
    exact = f"{hex_id}.svg"
    for name in archive.namelist():
        normalized = name.replace("\\", "/")
        if normalized.endswith(suffix) or normalized == exact:
            if "/" in normalized and not normalized.rsplit("/", 1)[0].endswith("kanji"):
                continue
            return name
    for name in archive.namelist():
        if name.replace("\\", "/").endswith(f"{hex_id}.svg"):
            return name
    return None


def write_source_markdown(
    path: Path,
    *,
    imported: int,
    missing: list[str],
) -> None:
    missing_lines = (
        "\n".join(f"- {glyph} (U+{ord(glyph):04X})" for glyph in missing)
        if missing
        else "None."
    )
    path.write_text(
        f"""# KanjiVG stroke data

Stroke-order assets in `assets/kanji/strokes/` are derived from [KanjiVG]({KANJIVG_SITE}).

| Field | Value |
| --- | --- |
| Source | KanjiVG |
| Release | `{KANJIVG_RELEASE}` |
| Archive | `{KANJIVG_ZIP_NAME}` |
| Download | {KANJIVG_ZIP_URL} |
| License | {KANJIVG_LICENSE} |
| Copyright | © 2009–2026 Ulrich Apel |
| Imported kanji | {imported} |
| Missing kanji | {len(missing)} |

The JSON files are an adaptation of the KanjiVG SVG stroke paths for the kanji
currently included in this app. They are **not** the full KanjiVG repository.

To refresh the data after a new KanjiVG release, update the constants at the
top of `tool/import_kanjivg.py` if needed and run:

```
python tool/import_kanjivg.py
```

Missing from this KanjiVG release:

{missing_lines}

See `third_party/kanjivg/` for the license text and attribution notice.
""",
        encoding="utf-8",
    )


def write_notice(path: Path) -> None:
    path.write_text(
        f"""KanjiVG
Copyright © 2009-2026 Ulrich Apel

This product includes stroke-order data derived from KanjiVG
({KANJIVG_SITE}), released under the {KANJIVG_LICENSE} license.

The JSON files in assets/kanji/strokes/ are an adaptation of KanjiVG SVG
data and are therefore also licensed under CC BY-SA 3.0.

Full license text: COPYING
""",
        encoding="utf-8",
    )


def main() -> int:
    root = repo_root()
    data_path = root / "lib" / "data" / "hardcoded_kanji_data.dart"
    output_dir = root / "assets" / "kanji" / "strokes"
    source_md = root / "assets" / "kanji" / "SOURCE.md"
    third_party = root / "third_party" / "kanjivg"
    cache_dir = root / "tool" / ".cache"
    zip_path = cache_dir / KANJIVG_ZIP_NAME
    copying_path = third_party / "COPYING"

    characters = read_dataset_characters(data_path)
    if not characters:
        print("No kanji characters found in hardcoded_kanji_data.dart", file=sys.stderr)
        return 1
    print(f"Dataset contains {len(characters)} unique kanji")

    if not zip_path.exists():
        download(KANJIVG_ZIP_URL, zip_path)
    else:
        print(f"Using cached archive {zip_path}")

    if not copying_path.exists():
        download(KANJIVG_COPYING_URL, copying_path)
    write_notice(third_party / "NOTICE")

    output_dir.mkdir(parents=True, exist_ok=True)
    for stale in output_dir.glob("*.json"):
        stale.unlink()

    imported = 0
    missing: list[str] = []
    with zipfile.ZipFile(zip_path) as archive:
        for glyph in characters:
            hex_id = unicode_hex(glyph)
            member = find_svg_in_zip(archive, hex_id)
            if member is None:
                print(f"MISSING  {glyph}  {hex_id}.svg")
                missing.append(glyph)
                continue
            svg_text = archive.read(member).decode("utf-8")
            try:
                payload = extract_stroke_data(svg_text, glyph)
            except Exception as error:  # noqa: BLE001 - report and continue
                print(f"FAILED   {glyph}  {hex_id}.svg  ({error})")
                missing.append(glyph)
                continue
            dest = output_dir / f"{hex_id}.json"
            dest.write_text(
                json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
                encoding="utf-8",
            )
            imported += 1

    write_source_markdown(source_md, imported=imported, missing=missing)
    print(f"Wrote {imported} stroke files to {output_dir}")
    if missing:
        print(f"{len(missing)} kanji missing from KanjiVG:")
        for glyph in missing:
            print(f"  {glyph} U+{ord(glyph):04X}")
    else:
        print("All dataset kanji have KanjiVG stroke data.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
