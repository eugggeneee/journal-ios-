#!/usr/bin/env python3
"""Раскладывает вложения-скриншоты из xcresult по понятным именам и собирает общие листы.

Использование: collect_screenshots.py <папка_экспорта> <папка_результата>
"""
import json
import os
import re
import shutil
import sys

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)

clean_re = re.compile(r"_\d+_[0-9A-Fa-f-]{36}(\.\w+)$")
copied = []

manifest = os.path.join(src, "manifest.json")
if os.path.exists(manifest):
    with open(manifest, encoding="utf-8") as fh:
        data = json.load(fh)
    for test in data:
        for att in test.get("attachments", []):
            exported = att.get("exportedFileName")
            if not exported:
                continue
            name = att.get("suggestedHumanReadableName") or exported
            name = clean_re.sub(r"\1", name)
            if not name.lower().endswith(".png"):
                name += ".png"
            from_path = os.path.join(src, exported)
            if os.path.exists(from_path):
                shutil.copy(from_path, os.path.join(dst, name))
                copied.append(name)
else:
    for f in sorted(os.listdir(src)):
        if f.lower().endswith(".png"):
            shutil.copy(os.path.join(src, f), os.path.join(dst, f))
            copied.append(f)

print(f"Скриншотов: {len(copied)}")
for n in sorted(copied):
    print(" ", n)

try:
    from PIL import Image
except ImportError:
    print("Pillow не установлен — общие листы пропущены")
    sys.exit(0)


def sheet(suffix, out_name):
    files = sorted(f for f in os.listdir(dst) if f.endswith(f"-{suffix}.png") and not f.startswith("contact"))
    if not files:
        return
    thumbs = []
    for f in files:
        im = Image.open(os.path.join(dst, f)).convert("RGB")
        w = 320
        h = int(im.height * w / im.width)
        thumbs.append(im.resize((w, h), Image.LANCZOS))
    cols = 5
    gap = 16
    rows = [thumbs[i:i + cols] for i in range(0, len(thumbs), cols)]
    width = cols * 320 + (cols + 1) * gap
    height = sum(max(t.height for t in r) for r in rows) + (len(rows) + 1) * gap
    canvas = Image.new("RGB", (width, height), (28, 28, 30) if suffix == "dark" else (229, 229, 234))
    y = gap
    for r in rows:
        x = gap
        for t in r:
            canvas.paste(t, (x, y))
            x += 320 + gap
        y += max(t.height for t in r) + gap
    canvas.save(os.path.join(dst, out_name))
    print("Лист:", out_name)


sheet("light", "contact-sheet-light.png")
sheet("dark", "contact-sheet-dark.png")
