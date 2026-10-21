#!/usr/bin/env python3
"""Splits the icon sheets rendered by `icon_sheet` (WordCraft's code-drawn icons) into
macos/Resources/icons/<name>.png with real transparency (white/black render difference).
usage: gen_icons.py sheet-white.png sheet-black.png names.txt"""
import sys, pathlib
import numpy as np
from PIL import Image

white = np.asarray(Image.open(sys.argv[1]).convert("RGB"), dtype=np.float32)
black = np.asarray(Image.open(sys.argv[2]).convert("RGB"), dtype=np.float32)
names = pathlib.Path(sys.argv[3]).read_text().split()
alpha = 1.0 - (white - black).mean(axis=2) / 255.0
alpha = np.clip(alpha, 0, 1)
rgb = np.where(alpha[..., None] > 0.001, black / np.maximum(alpha[..., None], 0.001), 0)
rgb = np.clip(rgb, 0, 255)
rgba = np.dstack([rgb, alpha * 255]).astype(np.uint8)
cell, cols = 80, 20  # 40 pt @ 2x
out = pathlib.Path(__file__).resolve().parents[1] / "Resources/icons"
out.mkdir(parents=True, exist_ok=True)
for i, n in enumerate(names):
    x, y = (i % cols) * cell, (i // cols) * cell
    Image.fromarray(rgba[y:y + cell, x:x + cell], "RGBA").crop((8, 8, 72, 72)).save(out / f"{n}.png")
print(len(names), "icons ->", out)
