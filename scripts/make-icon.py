#!/usr/bin/env python3
"""Рисует иконку SinMinions (1024×1024 PNG): зелёный призрак Moth в стиле терминала на тёмном скруглённом квадрате.

Запуск: python3 scripts/make-icon.py [путь/к/AppIcon.png]
"""
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 4  # суперсэмплинг для сглаживания
N = 1024 * S


def cubic(p0, p1, p2, p3, steps=48):
    points = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        points.append((
            u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1],
        ))
    return points


def body():
    """Контур из index.html репозитория summary (SVG 48×56)."""
    pts = [(4, 24)]
    segments = [
        ((4, 12.954), (13.163, 4), (24, 4)),
        ((34.837, 4), (44, 12.954), (44, 24)),
        None,  # вертикаль до (44, 44)
        ((44, 44), (40, 40), (36, 44)),
        ((32, 48), (28, 44), (24, 44)),
        ((20, 44), (16, 48), (12, 44)),
        ((8, 40), (4, 44), (4, 44)),
    ]
    for seg in segments:
        if seg is None:
            pts.append((44, 44))
        else:
            pts += cubic(pts[-1], *seg)
    return pts


def main(out):
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    pad = 100 * S
    top, bottom = (18, 28, 16), (8, 12, 7)
    gradient = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(gradient)
    for y in range(N):
        k = y / (N - 1)
        gd.line([(0, y), (N, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * k) for i in range(3)) + (255,))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([pad, pad, N - pad, N - pad], radius=185 * S, fill=255)
    img.paste(gradient, (0, 0), mask)

    draw = ImageDraw.Draw(img)
    k = 11.5 * S  # масштаб рисунка 48×56
    ox = (N - 48 * k) / 2
    oy = (N - 48 * k) / 2 - 1 * k

    def at(p):
        return (ox + p[0] * k, oy + p[1] * k)

    outline = [at(p) for p in body()]
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(outline, fill=(92, 245, 66, 150))
    glow = glow.filter(ImageFilter.GaussianBlur(40 * S))
    glow.putalpha(ImageChops.multiply(glow.getchannel("A"), mask))
    img.alpha_composite(glow)
    draw = ImageDraw.Draw(img)
    draw.polygon(outline, fill=(26, 58, 18, 255))
    draw.line(outline + [outline[0]], fill=(58, 138, 40, 255), width=round(1.5 * k), joint="curve")
    for cx, cy in ((17, 24), (31, 24)):
        draw.ellipse([at((cx - 3, cy - 3.5)), at((cx + 3, cy + 3.5))], fill=(92, 245, 66, 255))
    for cx, cy in ((18.2, 22.5), (32.2, 22.5)):
        draw.ellipse([at((cx - 1, cy - 1)), at((cx + 1, cy + 1))], fill=(207, 255, 202, 255))

    img.resize((1024, 1024), Image.LANCZOS).save(out)
    print("Сохранено:", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Resources/AppIcon.png")
