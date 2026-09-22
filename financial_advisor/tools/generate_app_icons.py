"""Export the approved Tadbeer filled-wallet image without reinterpreting it.

Requires Pillow. Run: python tools/generate_app_icons.py
Standard color icons are exact resizes of the approved opaque artwork.
Platform variants use only resizing and edge padding. No cutout generation.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/source/tadbeer-filled-blue-teal-approved.png"
RESAMPLE = Image.Resampling.LANCZOS
EXPORTS = []
RES = "android/app/src/main/res"


def save(image, relative_path):
    target = ROOT / relative_path
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, optimize=True)
    EXPORTS.append({"path": relative_path, "size": image.width, "mode": image.mode})
    return image


def standard(source, relative_path, size):
    return save(source.resize((size, size), RESAMPLE), relative_path)


def edge_padding(source, border):
    """Extend existing edge pixels without introducing a different background."""
    w, h = source.size
    out = Image.new("RGB", (w + 2 * border, h + 2 * border))
    out.paste(source, (border, border))
    nearest = Image.Resampling.NEAREST
    out.paste(source.crop((0, 0, w, 1)).resize((w, border), nearest), (border, 0))
    out.paste(source.crop((0, h - 1, w, h)).resize((w, border), nearest), (border, h + border))
    out.paste(source.crop((0, 0, 1, h)).resize((border, h), nearest), (0, border))
    out.paste(source.crop((w - 1, 0, w, h)).resize((border, h), nearest), (w + border, border))
    for sx, sy, dx, dy in (
        (0, 0, 0, 0), (w - 1, 0, w + border, 0),
        (0, h - 1, 0, h + border), (w - 1, h - 1, w + border, h + border),
    ):
        out.paste(source.getpixel((sx, sy)), (dx, dy, dx + border, dy + border))
    return out


def export_catalog(source, relative):
    catalog = ROOT / relative
    entries = json.loads((catalog / "Contents.json").read_text(encoding="utf-8"))["images"]
    sizes = {}
    for entry in entries:
        size = round(float(entry["size"].split("x")[0]) * float(entry["scale"].rstrip("x")))
        filename = entry["filename"]
        assert filename not in sizes or sizes[filename] == size
        sizes[filename] = size
    for filename, size in sizes.items():
        standard(source, f"{relative}/{filename}", size)


def preview():
    sheet = Image.new("RGB", (1120, 560), "#E9E6DF")
    draw = ImageDraw.Draw(sheet)
    font_path = Path("C:/Windows/Fonts/segoeui.ttf")
    title_font = ImageFont.truetype(str(font_path), 27) if font_path.exists() else ImageFont.load_default()
    label_font = ImageFont.truetype(str(font_path), 18) if font_path.exists() else ImageFont.load_default()
    draw.text((32, 24), "Tadbeer / Filled wallet / Blue-to-teal", fill="#152C3F", font=title_font)
    samples = [
        ("Master / iOS", "assets/branding/tadbeer-icon-1024.png", "rounded"),
        ("Android adaptive", f"{RES}/drawable-xxxhdpi/ic_launcher_foreground.png", "circle"),
        ("Web PWA", "web/icons/Icon-512.png", "square"),
        ("Web maskable", "web/icons/Icon-maskable-512.png", "circle"),
    ]
    for index, (label, path, shape) in enumerate(samples):
        x, y, edge = 32 + index * 276, 90, 228
        icon = Image.open(ROOT / path).convert("RGBA")
        if label == "Android adaptive":
            # Central 72dp viewport in the 108dp adaptive layer.
            icon = icon.crop((72, 72, 360, 360))
            assert icon.getchannel("A").getextrema() == (255, 255)
        icon = icon.resize((edge, edge), RESAMPLE).convert("RGB")
        mask = Image.new("L", (edge, edge), 0)
        pen = ImageDraw.Draw(mask)
        if shape == "circle":
            pen.ellipse((0, 0, edge - 1, edge - 1), fill=255)
        elif shape == "rounded":
            pen.rounded_rectangle((0, 0, edge - 1, edge - 1), radius=48, fill=255)
        else:
            pen.rectangle((0, 0, edge - 1, edge - 1), fill=255)
        sheet.paste(icon, (x, y), mask)
        draw.text((x, y + edge + 18), label, fill="#152C3F", font=label_font)
    draw.text((32, 400), "Actual small exports: Android 48 / 72 / 96 px     Web favicon 16 / 32 / 48 px",
              fill="#152C3F", font=label_font)
    x = 32
    for path in [
        f"{RES}/mipmap-mdpi/ic_launcher.png", f"{RES}/mipmap-hdpi/ic_launcher.png",
        f"{RES}/mipmap-xhdpi/ic_launcher.png", "web/icons/favicon-16.png",
        "web/favicon.png", "web/icons/favicon-48.png",
    ]:
        im = Image.open(ROOT / path)
        sheet.paste(im, (x, 440))
        x += im.width + 26
    sheet.save(ROOT / "assets/branding/icon-preview.png", optimize=True)


def main():
    EXPORTS.clear()
    original = Image.open(SOURCE)
    assert original.width == original.height
    if original.mode == "RGBA":
        assert original.getchannel("A").getextrema() == (255, 255), "Approved source must be opaque."
    source = original.convert("RGB")
    standard(source, "assets/branding/tadbeer-icon-1024.png", 1024)
    for ratio in (1, 2, 3, 4):
        suffix = "" if ratio == 1 else f"{ratio}.0x/"
        standard(source, f"assets/branding/{suffix}tadbeer-logo.png", 64 * ratio)

    for density, legacy_size, layer_size in (
        ("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216),
        ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432),
    ):
        standard(source, f"{RES}/mipmap-{density}/ic_launcher.png", legacy_size)
        # Preserve every pixel of the approved color design within a 72dp square.
        # Transparent padding is outside the entire artwork, never inside the wallet.
        content_size = layer_size * 2 // 3
        offset = (layer_size - content_size) // 2
        artwork = source.resize((content_size, content_size), RESAMPLE).convert("RGBA")
        foreground = Image.new("RGBA", (layer_size, layer_size), (0, 0, 0, 0))
        foreground.alpha_composite(artwork, (offset, offset))
        assert foreground.crop((offset, offset, offset + content_size, offset + content_size)).getchannel("A").getextrema() == (255, 255)
        save(foreground, f"{RES}/drawable-{density}/ic_launcher_foreground.png")

    export_catalog(source, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    padded = edge_padding(source, round(source.width * 0.08))
    for size in (192, 512):
        standard(source, f"web/icons/Icon-{size}.png", size)
        standard(padded, f"web/icons/Icon-maskable-{size}.png", size)
    standard(source, "web/icons/apple-touch-icon.png", 180)
    standard(source, "web/favicon.png", 32)
    standard(source, "web/icons/favicon-16.png", 16)
    favicon = standard(source, "web/icons/favicon-48.png", 48)
    favicon.save(ROOT / "web/favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
    EXPORTS.append({"path": "web/favicon.ico", "sizes": [16, 32, 48], "mode": "ICO"})

    export_catalog(source, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
    windows_sizes = [16, 24, 32, 48, 64, 128, 256]
    source.save(ROOT / "windows/runner/resources/app_icon.ico",
                sizes=[(size, size) for size in windows_sizes])
    EXPORTS.append({"path": "windows/runner/resources/app_icon.ico", "sizes": windows_sizes, "mode": "ICO"})

    preview()
    manifest = {
        "design": "Tadbeer / approved filled wallet with blue-to-teal background",
        "source": str(SOURCE.relative_to(ROOT)).replace("\\", "/"),
        "background": "Approved image gradient; Android full-bleed gradient drawable",
        "android": {
            "background": f"{RES}/drawable/ic_launcher_background.xml",
            "monochrome": f"{RES}/drawable/ic_launcher_monochrome.xml",
            "artwork_viewport_dp": 72,
            "layer_size_dp": 108,
        },
        "exports": EXPORTS,
    }
    (ROOT / "assets/branding/icon-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Exported {len(EXPORTS)} image files using the approved opaque artwork.")
    print("Verified Android color artwork remains fully opaque, with padding only outside it.")


if __name__ == "__main__":
    main()
