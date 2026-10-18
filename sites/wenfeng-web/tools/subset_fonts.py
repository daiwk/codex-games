#!/usr/bin/env python3
"""Rebuild the game's Chinese font subsets with fontTools.

Cache the official Noto CJK regular OTF files below, or pass --sans / --serif:
https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf
https://raw.githubusercontent.com/notofonts/noto-cjk/main/Serif/OTF/SimplifiedChinese/NotoSerifCJKsc-Regular.otf

The full fonts remain in .cache; only the small Wenfeng subsets are game assets.
Existing Unicode coverage is retained when rebuilding. Original font copyright
and OFL metadata remain in each subset; the accompanying licenses stay unchanged.
"""

import argparse
import json
from pathlib import Path
import unicodedata

from fontTools import subset
from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[1]
FONT_DIR = ROOT / "godot/assets/fonts"
CACHE_DIR = ROOT / ".cache/fonts"
ASCII = set(range(0x20, 0x7F))
WEB_SUFFIXES = {".html", ".js", ".mjs", ".css", ".gd"}


def unicode_cmap(font):
    return set().union(*(table.cmap for table in font["cmap"].tables if table.isUnicode()))


def source_characters():
    files = sorted((ROOT / "godot/scripts").rglob("*.gd"))
    files += sorted(path for path in (ROOT / "web").rglob("*")
                    if path.is_file() and path.suffix in WEB_SUFFIXES)
    characters = {ord(character) for path in files
                  for character in path.read_text(encoding="utf-8")
                  if character.isprintable()}
    return files, characters


def is_han(codepoint):
    # Unicode names include CJK extension and compatibility ideographs as well.
    return "CJK" in unicodedata.name(chr(codepoint), "") and "IDEOGRAPH" in unicodedata.name(chr(codepoint), "")


def describe(codepoints):
    return [{"codepoint": f"U+{value:04X}", "character": chr(value),
             "name": unicodedata.name(chr(value), "UNNAMED")}
            for value in sorted(codepoints)]


def rename_subset(font, family):
    # Modified OFL fonts get their own family and PostScript names.
    postscript_name = family.replace(" ", "") + "-Regular"
    names = {1: family, 2: "Regular", 3: postscript_name + ":1.0",
             4: family + " Regular", 6: postscript_name, 16: family, 17: "Regular"}
    table = font["name"]
    for record in list(table.names):
        if record.nameID in names:
            table.setName(names[record.nameID], record.nameID,
                          record.platformID, record.platEncID, record.langID)
    for name_id, value in names.items():
        table.setName(value, name_id, 3, 1, 0x409)
    if "CFF " in font:
        cff = font["CFF "].cff
        cff.fontNames = [postscript_name]
        for top in cff.topDictIndex:
            top.FamilyName = family
            top.FullName = family + " Regular"


def coverage(path, required, source, old=None):
    with TTFont(path, recalcTimestamp=False) as font:
        cmap = unicode_cmap(font)
    missing = required - cmap
    if missing:
        raise RuntimeError(f"{path.name} lacks required characters: {describe(missing)}")
    return {"file": str(path.relative_to(ROOT)), "bytes": path.stat().st_size,
            "cmap_codepoints": len(cmap), "source_han": len({c for c in source if is_han(c)}),
            "missing_han": describe({c for c in source - cmap if is_han(c)}),
            "old_cmap_retained": len(old) if old is not None else None,
            "missing_source_symbols": describe(source - cmap)}


def rebuild(source_path, destination, family, characters):
    if not source_path.is_file():
        raise FileNotFoundError(f"Full Noto font not found: {source_path}. See this script's docstring or pass --sans / --serif.")
    with TTFont(destination, recalcTimestamp=False) as current:
        old = unicode_cmap(current)
    required = old | ASCII | {value for value in characters if is_han(value)}
    with TTFont(source_path, recalcTimestamp=False) as font:
        available = unicode_cmap(font)
        if required - available:
            raise RuntimeError(f"{source_path.name} cannot retain all required characters: {describe(required - available)}")
        options = subset.Options()
        options.layout_features = ["*"]
        options.name_IDs = ["*"]
        options.name_languages = ["*"]
        options.name_legacy = True
        options.notdef_glyph = True
        options.notdef_outline = True
        options.recommended_glyphs = True
        subsetter = subset.Subsetter(options=options)
        subsetter.populate(unicodes=(required | characters) & available)
        subsetter.subset(font)
        rename_subset(font, family)
        temporary = destination.with_suffix(".otf.tmp")
        try:
            font.save(temporary)
            # Verify before replacing the working font asset.
            coverage(temporary, required, characters, old)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
    return coverage(destination, required, characters, old)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sans", type=Path, default=CACHE_DIR / "NotoSansCJKsc-Regular.otf")
    parser.add_argument("--serif", type=Path, default=CACHE_DIR / "NotoSerifCJKsc-Regular.otf")
    parser.add_argument("--check", action="store_true", help="Check existing subsets without rewriting them or opening full source fonts")
    args = parser.parse_args()
    files, characters = source_characters()
    required = ASCII | {value for value in characters if is_han(value)}
    report = {"source_files": len(files), "source_characters": len(characters), "fonts": []}
    for label, source in [("Sans", args.sans), ("Serif", args.serif)]:
        destination = FONT_DIR / f"Wenfeng{label}.otf"
        result = (coverage(destination, required, characters) if args.check
                  else rebuild(source.expanduser().resolve(), destination, f"Wenfeng {label}", characters))
        report["fonts"].append(result)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
