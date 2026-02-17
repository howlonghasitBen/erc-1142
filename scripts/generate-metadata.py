#!/usr/bin/env python3
"""Generate/update ERC-721 metadata JSON files from cardData.json.

Incremental: only writes files whose content has actually changed.
Output: cog-works/public/data/metadata/<index>.json (0-indexed)
Also writes metadata/index.json mapping card names → metadata file indices.

Usage: python3 generate-metadata.py [--force]
  --force  Rewrite all files regardless of changes
"""
import json, os, sys, re, hashlib

CARD_DATA = os.path.expanduser("~/Projects/cog-works/public/data/cardData.json")
OUT_DIR = os.path.expanduser("~/Projects/cog-works/public/data/metadata")
FORCE = "--force" in sys.argv

os.makedirs(OUT_DIR, exist_ok=True)

cards = json.load(open(CARD_DATA))
index_map = {}
written = 0
skipped = 0
total = len(cards)


def build_metadata(card, idx):
    """Build a standard ERC-721 metadata dict from a cardData entry."""
    name = card.get("name", f"Card_{idx}")
    meta = {
        "name": name,
        "description": card.get("flavorText") or "A Whirlpool card",
        "image": card.get("image", ""),
        "external_url": "https://howlonghasitben.github.io/cog-works/",
        "attributes": [],
        "properties": {},
    }
    attrs = meta["attributes"]
    props = meta["properties"]

    # ── Standard attributes ──
    if card.get("type"):
        attrs.append({"trait_type": "Type", "value": card["type"]})
    if card.get("rarity"):
        attrs.append({"trait_type": "Rarity", "value": card["rarity"]})
    if card.get("level"):
        attrs.append({"trait_type": "Level", "value": str(card["level"])})
    if card.get("subtitle"):
        attrs.append({"trait_type": "Move", "value": card["subtitle"]})
    if card.get("artist"):
        attrs.append({"trait_type": "Artist", "value": card["artist"]})

    # ── Numeric stats ──
    for stat_key, display in [("hp", "HP"), ("manaCost", "Mana Cost"), ("crit", "Crit")]:
        stat = card.get(stat_key)
        if stat and isinstance(stat, dict) and stat.get("value"):
            attrs.append({"trait_type": display, "value": str(stat["value"])})
            # Include stat orb gradient
            if stat.get("color"):
                attrs.append({"trait_type": f"{display} Gradient", "value": stat["color"]})

    # ── Theme / gradient values ──
    theme = card.get("theme")
    if theme and isinstance(theme, dict):
        # Top-level card background
        if theme.get("background"):
            attrs.append({"trait_type": "Card Background", "value": theme["background"]})

        # Nested section gradients
        section_labels = {
            "header": "Header",
            "imageArea": "Image Area",
            "typeSection": "Type Section",
            "flavorText": "Flavor Text",
            "bottomSection": "Bottom Section",
            "stat": "Stat",
            "rarity": "Rarity Badge",
        }
        for key, label in section_labels.items():
            section = theme.get(key)
            if not section or not isinstance(section, dict):
                continue
            if section.get("background"):
                attrs.append({"trait_type": f"{label} Background", "value": section["background"]})
            if section.get("color"):
                attrs.append({"trait_type": f"{label} Color", "value": section["color"]})
            if section.get("border"):
                attrs.append({"trait_type": f"{label} Border", "value": section["border"]})
            if section.get("accentColor"):
                attrs.append({"trait_type": f"{label} Accent", "value": section["accentColor"]})

        # Store full theme object in properties for programmatic access
        props["theme"] = theme

    # Remove empty properties
    if not props:
        del meta["properties"]

    return meta


def serialize(meta):
    """Compact JSON serialization."""
    return json.dumps(meta, separators=(",", ":"), ensure_ascii=False)


for i, card in enumerate(cards):
    name = card.get("name", f"Card_{i}")
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    index_map[name] = {"index": i, "slug": slug}

    meta = build_metadata(card, i)
    new_content = serialize(meta)

    out_path = os.path.join(OUT_DIR, f"{i}.json")

    # Check if file exists and content matches
    if not FORCE and os.path.exists(out_path):
        with open(out_path, "r") as f:
            existing = f.read()
        if existing == new_content:
            skipped += 1
            continue

    with open(out_path, "w") as f:
        f.write(new_content)
    written += 1

# Clean up stale metadata files (indices >= total cards)
stale = 0
for fname in os.listdir(OUT_DIR):
    if fname == "index.json":
        continue
    if fname.endswith(".json"):
        try:
            idx = int(fname.replace(".json", ""))
            if idx >= total:
                os.remove(os.path.join(OUT_DIR, fname))
                stale += 1
        except ValueError:
            pass

# Write index (always, it's small)
with open(os.path.join(OUT_DIR, "index.json"), "w") as f:
    json.dump(index_map, f, indent=2)

print(f"Metadata: {total} cards — {written} written, {skipped} unchanged, {stale} stale removed")
