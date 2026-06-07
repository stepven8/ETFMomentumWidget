#!/usr/bin/env python3
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "Assets.xcassets" / "AppIcon.appiconset"
PREVIEW = ROOT / "Assets.xcassets" / "IconPreview.imageset"


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            continue
    return ImageFont.load_default()


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def draw_polyline(draw: ImageDraw.ImageDraw, points, fill, width: int):
    for a, b in zip(points, points[1:]):
        draw.line((a, b), fill=fill, width=width)
        r = max(2, width // 3)
        draw.ellipse((b[0] - r, b[1] - r, b[0] + r, b[1] + r), fill=fill)


def make_icon(size: int = 1024) -> Image.Image:
    scale = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Base shape
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    radius = int(190 * scale)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=(17, 22, 30, 255))

    # Subtle diagonal depth, kept concrete and low noise.
    for y in range(size):
        t = y / max(size - 1, 1)
        color = (
            int(20 + 11 * t),
            int(27 + 12 * t),
            int(38 + 16 * t),
            255,
        )
        draw.line((0, y, size, y), fill=color)

    # Inner chart panel
    panel = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(panel)
    margin = int(118 * scale)
    pdraw.rounded_rectangle(
        (margin, int(168 * scale), size - margin, int(744 * scale)),
        radius=int(58 * scale),
        fill=(34, 42, 55, 235),
        outline=(92, 109, 132, 110),
        width=max(2, int(3 * scale)),
    )

    # Grid
    grid_left = int(168 * scale)
    grid_right = int(856 * scale)
    grid_top = int(236 * scale)
    grid_bottom = int(675 * scale)
    for i in range(5):
        y = grid_top + (grid_bottom - grid_top) * i / 4
        pdraw.line((grid_left, y, grid_right, y), fill=(132, 149, 172, 45), width=max(1, int(2 * scale)))
    for i in range(4):
        x = grid_left + (grid_right - grid_left) * i / 3
        pdraw.line((x, grid_top, x, grid_bottom), fill=(132, 149, 172, 25), width=max(1, int(2 * scale)))

    # Candles
    candle_data = [
        (190, 610, 575, 640, False),
        (245, 565, 530, 610, True),
        (302, 538, 498, 585, True),
        (360, 510, 545, 572, False),
        (418, 472, 426, 518, True),
        (476, 430, 392, 465, True),
        (534, 385, 416, 448, False),
        (592, 350, 305, 390, True),
        (650, 322, 275, 360, True),
        (708, 292, 330, 352, False),
        (766, 250, 205, 292, True),
        (824, 215, 172, 245, True),
    ]
    candle_width = max(8, int(18 * scale))
    wick_width = max(3, int(5 * scale))
    for x, open_y, close_y, high_y, is_up in candle_data:
        x = int(x * scale)
        open_y = int(open_y * scale)
        close_y = int(close_y * scale)
        high_y = int(high_y * scale)
        low_y = int(max(open_y, close_y, high_y + int(75 * scale)))
        color = (255, 57, 67, 255) if is_up else (0, 204, 108, 255)
        pdraw.line((x, high_y, x, low_y), fill=color, width=wick_width)
        top = min(open_y, close_y)
        bottom = max(open_y, close_y)
        pdraw.rounded_rectangle(
            (x - candle_width // 2, top, x + candle_width // 2, bottom),
            radius=max(2, int(4 * scale)),
            fill=color,
        )

    # Momentum line
    points = [
        (178, 610),
        (252, 566),
        (322, 540),
        (404, 475),
        (488, 430),
        (560, 374),
        (642, 325),
        (730, 252),
        (846, 184),
    ]
    points = [(int(x * scale), int(y * scale)) for x, y in points]
    draw_polyline(pdraw, points, (120, 190, 255, 255), max(8, int(14 * scale)))

    # Lower ETF badge
    badge = (int(142 * scale), int(765 * scale), int(884 * scale), int(908 * scale))
    pdraw.rounded_rectangle(badge, radius=int(48 * scale), fill=(230, 237, 246, 245))
    pdraw.text((int(184 * scale), int(782 * scale)), "ETF", font=font(int(86 * scale)), fill=(17, 24, 35, 255))
    pdraw.text((int(418 * scale), int(802 * scale)), "MOM", font=font(int(48 * scale)), fill=(42, 71, 108, 255))
    pdraw.polygon(
        [
            (int(760 * scale), int(844 * scale)),
            (int(822 * scale), int(782 * scale)),
            (int(864 * scale), int(844 * scale)),
        ],
        fill=(255, 57, 67, 255),
    )

    base.alpha_composite(panel)

    # Soft top highlight and border
    hdraw = ImageDraw.Draw(base)
    hdraw.rounded_rectangle(
        (int(18 * scale), int(18 * scale), size - int(18 * scale), size - int(18 * scale)),
        radius=max(1, radius - int(18 * scale)),
        outline=(255, 255, 255, 42),
        width=max(2, int(5 * scale)),
    )

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle((0, 0, size, size), radius=radius, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(24 * scale)))
    image.alpha_composite(shadow, (0, int(10 * scale)))
    image.alpha_composite(base)
    image.putalpha(rounded_mask(size, radius))
    return image


def save_iconset(source: Image.Image) -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    images = []
    specs = [
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2),
    ]
    for point_size, scale in specs:
        pixels = point_size * scale
        filename = f"icon_{point_size}x{point_size}@{scale}x.png"
        source.resize((pixels, pixels), Image.Resampling.LANCZOS).save(ICONSET / filename)
        images.append({
            "idiom": "mac",
            "size": f"{point_size}x{point_size}",
            "scale": f"{scale}x",
            "filename": filename,
        })
    (ICONSET / "Contents.json").write_text(json.dumps({
        "images": images,
        "info": {"author": "xcode", "version": 1},
    }, ensure_ascii=False, indent=2) + "\n")

    source.save(PREVIEW / "icon-preview.png")
    (PREVIEW / "Contents.json").write_text(json.dumps({
        "images": [{
            "idiom": "universal",
            "filename": "icon-preview.png",
            "scale": "1x",
        }],
        "info": {"author": "xcode", "version": 1},
    }, ensure_ascii=False, indent=2) + "\n")


def main() -> None:
    source = make_icon()
    source.save(ROOT / "Assets.xcassets" / "AppIconSource.png")
    save_iconset(source)
    print(ICONSET)


if __name__ == "__main__":
    main()
