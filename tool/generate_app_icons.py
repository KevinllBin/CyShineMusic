"""Export the six launcher palettes from the approved transparent logo."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageColor, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"
PREVIEWS = ROOT / "assets/app_icons"
PREVIEWS.mkdir(parents=True, exist_ok=True)
SOURCE_COLORS = ["#5B6EDB", "#7975D8", "#9B7ED4", "#D1AB62"]
PALETTES = {
    "classic": ("#FFFFFF", SOURCE_COLORS),
    "midnight": ("#151A2D", ["#8394FF", "#A294FA", "#C198F3", "#F0CC85"]),
    "sky": ("#E7F2FF", ["#2563EB", "#387AF4", "#6B9BF5", "#D8A35A"]),
    "lavender": ("#F1EBFF", ["#7153C1", "#8A6DD7", "#A889DE", "#BE9556"]),
    "mint": ("#E6F6F1", ["#1E8B78", "#38AA90", "#76BDA5", "#C8974A"]),
    "peach": ("#FFF0EE", ["#C96982", "#D98D9E", "#E5ACB4", "#C59445"]),
}
DENSITIES = [("mdpi", 108, 48), ("hdpi", 162, 72), ("xhdpi", 216, 96),
             ("xxhdpi", 324, 144), ("xxxhdpi", 432, 192)]
LANCZOS = Image.Resampling.LANCZOS
source = Image.open(ROOT / "logo_fg.png").convert("RGBA")
pixels = np.asarray(source)
base = np.array([ImageColor.getrgb(color) for color in SOURCE_COLORS], dtype=np.int32)
distances = ((pixels[:, :, None, :3].astype(np.int32) - base) ** 2).sum(axis=3)
color_index = distances.argmin(axis=2)
inset = round(source.width * 18 / 108)
viewport = (inset, inset, source.width - inset, source.height - inset)
mask = Image.new("L", (1024, 1024), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 1023, 1023), radius=236, fill=255)

for code, (background, colors) in PALETTES.items():
    if code == "classic":
        # The default source remains the project's approved launcher icon.
        Image.open(ROOT / "logo.png").resize((256, 256), LANCZOS).save(PREVIEWS / f"{code}.png")
        continue
    palette = np.array([ImageColor.getrgb(color) for color in colors], dtype=np.uint8)
    recolored = pixels.copy()
    recolored[:, :, :3] = palette[color_index]
    foreground = Image.fromarray(recolored)
    composite = Image.alpha_composite(Image.new("RGBA", source.size, background), foreground)
    visible = composite.crop(viewport).resize((1024, 1024), LANCZOS)
    visible.putalpha(mask)
    visible.resize((256, 256), LANCZOS).save(PREVIEWS / f"{code}.png")
    for density, layer_size, icon_size in DENSITIES:
        drawables = RES / f"drawable-{density}"
        mipmaps = RES / f"mipmap-{density}"
        drawables.mkdir(parents=True, exist_ok=True)
        mipmaps.mkdir(parents=True, exist_ok=True)
        foreground.resize((layer_size, layer_size), LANCZOS).save(drawables / f"ic_launcher_{code}_foreground.png")
        visible.resize((icon_size, icon_size), LANCZOS).save(mipmaps / f"ic_launcher_{code}.png")
    background_path = RES / "drawable" / f"ic_launcher_{code}_background.xml"
    background_path.parent.mkdir(parents=True, exist_ok=True)
    background_path.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="{background}" />
</shape>
''', encoding="utf-8")
    adaptive = RES / "mipmap-anydpi-v26" / f"ic_launcher_{code}.xml"
    adaptive.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_{code}_background" />
    <foreground android:drawable="@drawable/ic_launcher_{code}_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
''', encoding="utf-8")

print(f"Exported {len(PALETTES)} icon previews and five alternate Android launcher palettes.")
