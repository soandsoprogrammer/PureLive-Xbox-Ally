"""Build compact, static emoticons from PureLive's assets/emo directory."""

import argparse
from io import BytesIO
import json
from pathlib import Path

from PIL import Image, ImageOps


def keys(platform, name, entry):
    if platform == "bilibili":
        return [entry.get("emoji") or name]
    if platform == "douyin":
        return [entry.get("display_name", "")]
    if platform == "douyu":
        return [name if name.startswith("[") and name.endswith("]") else f"[{name}]"]
    return [entry.get("sName", ""), entry.get("sEscape", "")]


def build(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    for platform in ("bilibili", "douyin", "douyu", "huya"):
        entries = json.loads((source / "json" / f"{platform}.json").read_text(encoding="utf-8"))
        table = {}
        images = {}
        blob = bytearray()
        for name, entry in (entries.items() if isinstance(entries, dict) else enumerate(entries)):
            filename = entry.get("local_file")
            if not filename:
                continue
            if filename not in images:
                with Image.open(source / "images" / platform / filename) as image:
                    frame = ImageOps.contain(image.convert("RGBA"), (48, 48), Image.Resampling.LANCZOS)
                    encoded = BytesIO()
                    frame.save(encoded, "WEBP", quality=80, method=6)
                data = encoded.getvalue()
                images[filename] = (len(blob), len(data))
                blob.extend(data)
            for code in keys(platform, name, entry):
                if code:
                    table.setdefault(code, images[filename])
        (destination / f"{platform}.json").write_text(
            json.dumps(table, ensure_ascii=False, sort_keys=True, separators=(",", ":")), encoding="utf-8"
        )
        (destination / f"{platform}.bin").write_bytes(blob)
        print(f"{platform}: {len(images)} images, {len(table)} codes, {len(blob)} bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="PureLive apps/pure_live/assets/emo directory")
    args = parser.parse_args()
    build(args.source, Path(__file__).parent / "assets/emotes")
