#!/usr/bin/env python3
"""Draw the Vesper app icon: an evening horizon on a dark field."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
image = Image.new("RGB", (SIZE, SIZE), "#14130f")
draw = ImageDraw.Draw(image, "RGBA")

# Warm sky.
for y in range(SIZE):
    t = y / SIZE
    if t < 0.42:
        color = (18, 20, 32)
    elif t < 0.62:
        blend = (t - 0.42) / 0.2
        color = (
            int(18 + blend * 150),
            int(20 + blend * 70),
            int(32 + blend * 28),
        )
    else:
        blend = min(1, (t - 0.62) / 0.25)
        color = (
            int(168 - blend * 40),
            int(90 - blend * 30),
            int(60 - blend * 20),
        )
    draw.line([(0, y), (SIZE, y)], fill=color)

# Ground.
draw.rectangle([0, 690, SIZE, SIZE], fill=(22, 16, 14))
# Ridge.
draw.polygon([(0, 720), (180, 640), (340, 700), (520, 590), (700, 680), (860, 610), (1024, 700), (1024, 1024), (0, 1024)], fill=(28, 20, 18))

# Sun.
sun = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sun_draw = ImageDraw.Draw(sun)
sun_draw.ellipse([392, 430, 632, 670], fill=(255, 206, 140, 230))
sun = sun.filter(ImageFilter.GaussianBlur(18))
image = Image.alpha_composite(image.convert("RGBA"), sun).convert("RGB")

# A few stars in the upper sky.
draw = ImageDraw.Draw(image)
for x, y, r in [(140, 120, 2), (260, 80, 1), (420, 150, 2), (610, 90, 1), (760, 140, 2), (880, 70, 1), (180, 200, 1)]:
    draw.ellipse([x - r, y - r, x + r, y + r], fill=(245, 236, 220))

out = Path(__file__).resolve().parents[1] / "macos" / "Support"
out.mkdir(parents=True, exist_ok=True)
png = out / "AppIcon.png"
image.save(png, "PNG")
print(png)
