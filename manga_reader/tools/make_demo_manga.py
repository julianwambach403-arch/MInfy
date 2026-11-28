#!/usr/bin/env python3
"""Erzeugt einen kleinen Demo-Manga (eigene, einfache Zeichnungen) zum Testen des Lesers.

  python3 tools/make_demo_manga.py ZIELORDNER

Legt ZIELORDNER/Demo-Manga/Kapitel 01.cbz ... an (mit einer Doppelseite im Querformat).
Benötigt Pillow (pip install pillow).
"""
import io, random, sys, zipfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

W, H = 1000, 1450


def font(size):
    for f in ["DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "arial.ttf"]:
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def page(ch, n, wide=False, rng=None):
    w = W * 2 if wide else W
    img = Image.new("RGB", (w, H), (250, 250, 247))
    d = ImageDraw.Draw(img)
    m = 50
    # Panels (Reihen mit 1-3 Feldern)
    y = m
    rows = [rng.choice([280, 340, 420]) for _ in range(3)]
    rows.append(H - m - y - sum(rows) - 3 * 24)
    for rh in rows:
        if rh < 120:
            continue
        cols = rng.choice([1, 2, 2, 3])
        x = m
        cw = (w - 2 * m - (cols - 1) * 24) / cols
        for _ in range(cols):
            box = [x, y, x + cw, y + rh]
            d.rectangle(box, outline=(20, 20, 20), width=6)
            # einfache Motive: Kreise, Linien, Sprechblase
            for _ in range(rng.randint(1, 3)):
                r = rng.randint(30, int(min(cw, rh) / 3))
                cx = rng.uniform(box[0] + r + 10, box[2] - r - 10)
                cy = rng.uniform(box[1] + r + 10, box[3] - r - 10)
                d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(30, 30, 30), width=4,
                          fill=rng.choice([None, (200, 200, 200), (120, 120, 120)]))
            for k in range(0, int(cw), 18):
                if rng.random() < 0.15:
                    d.line([box[0] + k, box[3] - 8, box[0] + k + 40, box[3] - 60], fill=(60, 60, 60), width=2)
            bx, by = box[0] + 20, box[1] + 20
            d.rounded_rectangle([bx, by, bx + 190, by + 80], radius=35, fill="white", outline="black", width=3)
            d.text((bx + 22, by + 22), "Hallo!" if rng.random() < 0.5 else "...!", fill="black", font=font(30))
            x += cw + 24
        y += rh + 24
    label = f"Kap. {ch} – Seite {n}" + ("–%d (Doppelseite)" % (n + 1) if wide else "")
    d.text((w / 2, H - 22), label, fill=(80, 80, 80), font=font(26), anchor="ms")
    d.text((w / 2, H / 2), str(n), fill=(225, 80, 60), font=font(220), anchor="mm")
    return img


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "Manga") / "Demo-Manga"
    out.mkdir(parents=True, exist_ok=True)
    for ch in range(1, 4):
        rng = random.Random(ch)
        with zipfile.ZipFile(out / f"Kapitel {ch:02d}.cbz", "w", zipfile.ZIP_STORED) as z:
            n = 1
            i = 1
            while n <= 18:
                wide = ch == 1 and n == 9
                img = page(ch, n, wide, rng)
                buf = io.BytesIO()
                img.save(buf, "JPEG", quality=85)
                z.writestr(f"{i:03d}.jpg", buf.getvalue())
                n += 2 if wide else 1
                i += 1
    print("Demo-Manga erzeugt in", out)


if __name__ == "__main__":
    main()
