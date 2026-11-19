"""Normalize product silhouettes to the same canvas without changing proportions.

Run with Pillow installed. Source URLs are recorded in Docs/HeadphoneArtSources.json.
"""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "AAAPJ002/Assets.xcassets"
for folder in sorted(ASSETS.glob("AirPods*.imageset")):
    metadata = json.loads((folder / "Contents.json").read_text())
    filename = metadata["images"][0]["filename"]
    path = folder / filename
    image = Image.open(path).convert("RGBA")
    # Ignore almost-transparent shadows when measuring the visible subject.
    bounds = image.getchannel("A").point(lambda alpha: 255 if alpha >= 16 else 0).getbbox()
    if bounds is None:
        raise ValueError(f"Empty product image: {path}")
    subject = image.crop(bounds)
    scale = 664 / max(subject.size)
    subject = subject.resize((round(subject.width * scale), round(subject.height * scale)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (800, 800))
    canvas.alpha_composite(subject, ((800 - subject.width) // 2, (800 - subject.height) // 2))
    canvas.save(path, optimize=True)
    print(folder.stem, bounds, subject.size)
