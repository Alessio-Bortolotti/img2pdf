"""Genera l'icona di FotoPDF: icone adattive Android + legacy + PNG master."""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]  # cartella android/app/src/main/res
PREVIEW = sys.argv[2]  # cartella per le anteprime
S = 2048  # lavoro in alta risoluzione, poi riduco (antialias)

INDIGO_TOP = (63, 81, 181)
INDIGO_BOT = (40, 53, 147)
RED = (229, 57, 53)


def k(v):  # coordinate pensate su 1024
    return int(v * S / 1024)


def rounded(draw, box, r, fill):
    draw.rounded_rectangle([k(x) for x in box], radius=k(r), fill=fill)


def page_polygon(x, y, w, h, fold):
    return [(k(x), k(y)), (k(x + w - fold), k(y)), (k(x + w), k(y + fold)),
            (k(x + w), k(y + h)), (k(x), k(y + h))]


def shadow_layer(shape_fn, blur, offset, alpha):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    shape_fn(d, (0, 0, 0, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(k(blur)))
    shifted = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shifted.paste(layer, (0, k(offset)))
    return shifted


def gradient(box, c1, c2, vertical=False):
    x0, y0, x1, y1 = [k(v) for v in box]
    w, h = x1 - x0, y1 - y0
    g = Image.new("RGBA", (w, h))
    px = g.load()
    for yy in range(h):
        for xx in range(w):
            t = (yy / h) if vertical else ((xx / w) * 0.6 + (yy / h) * 0.4)
            px[xx, yy] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)
    return g, (x0, y0)


def foreground():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # --- Foto inclinata dietro la pagina
    card = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    cbox = (470, 250, 750, 590)
    rounded(cd, cbox, 22, (255, 255, 255, 255))
    g, pos = gradient((490, 270, 730, 530), (255, 183, 77), (229, 115, 115))
    mask = Image.new("L", g.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, g.size[0], g.size[1]], radius=k(10), fill=255)
    card.paste(g, pos, mask)
    cd.polygon([(k(490), k(530)), (k(570), k(430)), (k(620), k(480)),
                (k(670), k(420)), (k(730), k(500)), (k(730), k(530))], fill=(255, 255, 255, 210))
    cd.ellipse([k(675), k(300), k(715), k(340)], fill=(255, 245, 157, 255))
    card = card.rotate(-14, resample=Image.BICUBIC, center=(k(610), k(420)))
    sh = card.split()[3].point(lambda a: int(a * 0.35))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.putalpha(sh.filter(ImageFilter.GaussianBlur(k(14))))
    img.alpha_composite(shadow, (0, k(10)))
    img.alpha_composite(card)

    # --- Pagina PDF
    px, py, pw, ph, fold = 300, 300, 360, 450, 90
    poly = page_polygon(px, py, pw, ph, fold)
    img.alpha_composite(shadow_layer(lambda d, c: d.polygon(poly, fill=c), 16, 12, 110))
    d = ImageDraw.Draw(img)
    d.polygon(poly, fill=(255, 255, 255, 255))
    # angolo piegato
    d.polygon([(k(px + pw - fold), k(py)), (k(px + pw - fold), k(py + fold)),
               (k(px + pw), k(py + fold))], fill=(208, 212, 232, 255))
    # immagine nella pagina
    g, pos = gradient((px + 40, py + 120, px + pw - 40, py + 300), (79, 195, 247), (121, 134, 203))
    img.paste(g, pos)
    d.polygon([(k(px + 40), k(py + 300)), (k(px + 120), k(py + 200)), (k(px + 175), k(py + 255)),
               (k(px + 225), k(py + 215)), (k(px + pw - 40), k(py + 300))], fill=(255, 255, 255, 215))
    d.ellipse([k(px + 240), k(py + 140), k(px + 280), k(py + 180)], fill=(255, 245, 157, 255))
    # righe di testo
    for (x0, y, x1) in [(px + 40, py + 65, px + pw - fold - 30), (px + 150, py + 345, px + pw - 40),
                        (px + 150, py + 395, px + pw - 80)]:
        d.rounded_rectangle([k(x0), k(y - 11), k(x1), k(y + 11)], radius=k(11), fill=(221, 224, 238, 255))

    # --- Etichetta PDF
    bx, by, bw, bh = 255, 590, 190, 100
    img.alpha_composite(shadow_layer(
        lambda d2, c: d2.rounded_rectangle([k(bx), k(by), k(bx + bw), k(by + bh)], radius=k(20), fill=c),
        10, 8, 120))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([k(bx), k(by), k(bx + bw), k(by + bh)], radius=k(20), fill=RED + (255,))
    draw_pdf_text(d, bx, by, bw, bh, (255, 255, 255, 255))
    return img


def draw_pdf_text(d, bx, by, bw, bh, color):
    """Scritta 'PDF' disegnata a mano (niente dipendenza da font)."""
    t = 14  # spessore tratto
    lh = 56  # altezza lettere
    lw = 38  # larghezza lettere
    gap = 14
    total = 3 * lw + 2 * gap
    x = bx + (bw - total) / 2
    y = by + (bh - lh) / 2

    def bar(x0, y0, x1, y1):
        d.rounded_rectangle([k(x0), k(y0), k(x1), k(y1)], radius=k(t / 2), fill=color)

    # P
    bar(x, y, x + t, y + lh)
    d.rounded_rectangle([k(x), k(y), k(x + lw), k(y + lh * 0.58)], radius=k(16), outline=color, width=k(t))
    # D
    x2 = x + lw + gap
    bar(x2, y, x2 + t, y + lh)
    d.rounded_rectangle([k(x2), k(y), k(x2 + lw), k(y + lh)], radius=k(22), outline=color, width=k(t))
    # F
    x3 = x2 + lw + gap
    bar(x3, y, x3 + t, y + lh)
    bar(x3, y, x3 + lw, y + t)
    bar(x3, y + lh * 0.45, x3 + lw * 0.8, y + lh * 0.45 + t)


def monochrome():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    px, py, pw, ph, fold = 300, 300, 360, 450, 90
    d.polygon(page_polygon(px, py, pw, ph, fold), fill=(255, 255, 255, 255))
    clear = (0, 0, 0, 0)
    d.polygon([(k(px + pw - fold), k(py)), (k(px + pw - fold), k(py + fold)),
               (k(px + pw), k(py + fold))], fill=(255, 255, 255, 120))
    d.rectangle([k(px + 40), k(py + 120), k(px + pw - 40), k(py + 300)], fill=clear)
    d.polygon([(k(px + 40), k(py + 300)), (k(px + 120), k(py + 200)), (k(px + 175), k(py + 255)),
               (k(px + 225), k(py + 215)), (k(px + pw - 40), k(py + 300))], fill=(255, 255, 255, 255))
    bx, by, bw, bh = 255, 590, 190, 100
    d.rounded_rectangle([k(bx - 12), k(by - 12), k(bx + bw + 12), k(by + bh + 12)], radius=k(28), fill=clear)
    d.rounded_rectangle([k(bx), k(by), k(bx + bw), k(by + bh)], radius=k(20), fill=(255, 255, 255, 255))
    draw_pdf_text(d, bx, by, bw, bh, clear)
    return img


def background():
    g, _ = gradient((0, 0, 1024, 1024), INDIGO_TOP, INDIGO_BOT, vertical=True)
    return g


def legacy(fg, bg, shape="square"):
    base = bg.copy()
    base.alpha_composite(fg)
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    if shape == "round":
        md.ellipse([0, 0, S, S], fill=255)
    else:
        md.rounded_rectangle([0, 0, S, S], radius=k(220), fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)
    return out


def zoom(img, factor):
    """Ingrandisce il contenuto (per le icone legacy, senza safe zone adattiva)."""
    size = int(S * factor)
    big = img.resize((size, size), Image.LANCZOS)
    off = (size - S) // 2
    return big.crop((off, off, off + S, off + S))


def save(img, path, px):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((px, px), Image.LANCZOS).save(path)


fg = zoom(foreground(), 1.2)
bg = background()
mono = zoom(monochrome(), 1.2)

dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
fg_legacy = zoom(fg, 1.12)
for name, m in dens.items():
    save(legacy(fg_legacy, bg), f"{OUT}/mipmap-{name}/ic_launcher.png", int(48 * m))
    save(legacy(fg_legacy, bg, "round"), f"{OUT}/mipmap-{name}/ic_launcher_round.png", int(48 * m))
    save(fg, f"{OUT}/mipmap-{name}/ic_launcher_foreground.png", int(108 * m))
    save(bg, f"{OUT}/mipmap-{name}/ic_launcher_background.png", int(108 * m))
    save(mono, f"{OUT}/mipmap-{name}/ic_launcher_monochrome.png", int(108 * m))

adaptive = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""
os.makedirs(f"{OUT}/mipmap-anydpi-v26", exist_ok=True)
for n in ("ic_launcher", "ic_launcher_round"):
    with open(f"{OUT}/mipmap-anydpi-v26/{n}.xml", "w") as f:
        f.write(adaptive)

# Anteprime: icona master + come appare in un launcher (cerchio e squircle)
os.makedirs(PREVIEW, exist_ok=True)
legacy(fg_legacy, bg).resize((1024, 1024), Image.LANCZOS).save(f"{PREVIEW}/icon_1024.png")
sheet = Image.new("RGBA", (1100, 420), (245, 246, 250, 255))
circ = legacy(fg, bg, "round").resize((300, 300), Image.LANCZOS)
sq = legacy(fg, bg).resize((300, 300), Image.LANCZOS)
dark = Image.new("RGBA", (300, 300), (30, 30, 36, 255))
dm = Image.new("L", (S, S), 0)
ImageDraw.Draw(dm).ellipse([0, 0, S, S], fill=255)
mono_bg = Image.new("RGBA", (S, S), (60, 64, 80, 255))
mono_bg.alpha_composite(Image.composite(mono, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mono.split()[3]))
mono_c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
mono_c.paste(mono_bg, (0, 0), dm)
sheet.alpha_composite(circ, (60, 60))
sheet.alpha_composite(sq, (400, 60))
sheet.paste(Image.new("RGBA", (340, 420), (30, 30, 36, 255)), (760, 0))
sheet.alpha_composite(mono_c.resize((300, 300), Image.LANCZOS), (780, 60))
sheet.save(f"{PREVIEW}/icon_preview.png")
print("ok")
