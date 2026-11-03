#!/usr/bin/env python3
"""2.3.1 «Прокси+» icon: red server stack + white plus in a red circle on a black/dark-red glow.
Writes adaptive-icon vectors (foreground inside the 66 dp safe zone, background, monochrome),
legacy mipmaps mdpi..xxxhdpi (+round), in-app logo PNG, TV banner 320x180 and previews.
Usage: make-icons.py <android res dir> <flutter assets dir> <preview dir>"""
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFilter
RES, ASSETS, PREV = sys.argv[1:4]
# K keeps every point of the glyph within r = 31 of the centre (66 dp safe-zone circle is r = 33)
K, CX, CY = 0.083, 539.5, 514.0
f = lambda v: round(v, 2)
X = lambda x: f(54 + (x - CX) * K)
Y = lambda y: f(54 + (y - CY) * K)
S = lambda v: f(v * K)
BARS = [(282, 246, 726, 386), (282, 404, 726, 544), (282, 562, 726, 704)]
RX, DOT, DOTX = 30, 20, 343
PC, PR = (680, 665), 117
RED1, RED2, PLUS = "#F0333C", "#B5141E", "#E8121E"

def rrect(x0, y0, x1, y1, r):  # path data
    x0, y0, x1, y1, r = X(x0), Y(y0), X(x1), Y(y1), S(r)
    return (f"M{f(x0+r)},{y0} H{f(x1-r)} A{r},{r} 0 0 1 {x1},{f(y0+r)} V{f(y1-r)} "
            f"A{r},{r} 0 0 1 {f(x1-r)},{y1} H{f(x0+r)} A{r},{r} 0 0 1 {x0},{f(y1-r)} V{f(y0+r)} "
            f"A{r},{r} 0 0 1 {f(x0+r)},{y0} Z")
def circle(cx, cy, r):
    cx, cy, r = X(cx), Y(cy), S(r)
    return f"M{f(cx-r)},{cy} A{r},{r} 0 1 0 {f(cx+r)},{cy} A{r},{r} 0 1 0 {f(cx-r)},{cy} Z"
def plus():
    cx, cy = PC; w, l = 11, 65
    return rrect(cx-l, cy-w, cx+l, cy+w, w) + " " + rrect(cx-w, cy-l, cx+w, cy+l, w)
bars = " ".join(rrect(*b, RX) for b in BARS)
dots = " ".join(circle(DOTX, (b[1]+b[3])/2, DOT) for b in BARS)
# monochrome: no overlap tricks; the third bar stops before the badge
mbars = " ".join(rrect(*b, RX) for b in BARS[:2]) + " " + rrect(282, 562, 530, 704, RX)
ring = circle(*PC, PR + 14)  # dark gap between the stack and the plus badge
badge = circle(*PC, PR)

# ---- SVG master (also the in-app logo) ----
def svg(bg=True, size=108, mono=False):
    g = [] if not bg else [
        '<defs><radialGradient id="bg" cx="50%" cy="48%" r="60%"><stop offset="0" stop-color="#4A0A0E"/>'
        '<stop offset=".55" stop-color="#1A0406"/><stop offset="1" stop-color="#050505"/></radialGradient></defs>',
        '<rect width="108" height="108" fill="url(#bg)"/>']
    if mono:
        g += [f'<path fill="#fff" fill-rule="evenodd" d="{mbars} {dots}"/>',
              f'<path fill="#fff" fill-rule="evenodd" d="{badge} {plus()}"/>']
    else:
        g += ['<defs><linearGradient id="r" x1="0" y1="0" x2="1" y2="1">'
              f'<stop offset="0" stop-color="{RED1}"/><stop offset="1" stop-color="{RED2}"/></linearGradient></defs>',
              f'<path fill="url(#r)" d="{bars}"/>', f'<path fill="#fff" d="{dots}"/>',
              f'<path fill="{"#0B0203" if bg else "#000"}" d="{ring}"/>' if bg else '',
              f'<path fill="{PLUS}" d="{badge}"/>', f'<path fill="#fff" d="{plus()}"/>']
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 108 108">{"".join(g)}</svg>'

# ---- adaptive icon vectors ----
os.makedirs(f"{RES}/drawable", exist_ok=True)
A = 'xmlns:android="http://schemas.android.com/apk/res/android" xmlns:aapt="http://schemas.android.com/aapt"'
V = f'<vector {A} android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">'
grad = lambda: (f'<aapt:attr name="android:fillColor"><gradient android:type="linear" android:startX="{X(282)}" '
                f'android:startY="{Y(246)}" android:endX="{X(726)}" android:endY="{Y(704)}" '
                f'android:startColor="{RED1}" android:endColor="{RED2}"/></aapt:attr>')
open(f"{RES}/drawable/ic_launcher_fg.xml", "w").write(
    f'<?xml version="1.0" encoding="utf-8"?>\n<!-- 2.3.1 «Прокси+»: glyph inside the 66 dp safe zone (scripts/make-icons.py) -->\n{V}\n'
    f'  <path android:pathData="{bars}">{grad()}</path>\n'
    f'  <path android:fillColor="#FFFFFF" android:pathData="{dots}"/>\n'
    f'  <path android:fillColor="#0B0203" android:pathData="{ring}"/>\n'
    f'  <path android:fillColor="{PLUS}" android:pathData="{badge}"/>\n'
    f'  <path android:fillColor="#FFFFFF" android:pathData="{plus()}"/>\n</vector>\n')
open(f"{RES}/drawable/ic_launcher_bg.xml", "w").write(
    f'<?xml version="1.0" encoding="utf-8"?>\n{V}\n  <path android:pathData="M0,0h108v108h-108z">\n'
    '    <aapt:attr name="android:fillColor"><gradient android:type="radial" android:centerX="54" android:centerY="52" '
    'android:gradientRadius="66"><item android:offset="0" android:color="#FF4A0A0E"/>'
    '<item android:offset="0.55" android:color="#FF1A0406"/><item android:offset="1" android:color="#FF050505"/>'
    '</gradient></aapt:attr>\n  </path>\n</vector>\n')
open(f"{RES}/drawable/ic_launcher_mono.xml", "w").write(
    f'<?xml version="1.0" encoding="utf-8"?>\n<!-- themed icon (Android 13+): one colour, the badge is cut out of the stack -->\n{V}\n'
    f'  <path android:fillColor="#FFFFFFFF" android:fillType="evenOdd" android:pathData="{mbars} {dots}"/>\n'
    f'  <path android:fillColor="#FFFFFFFF" android:fillType="evenOdd" android:pathData="{badge} {plus()}"/>\n</vector>\n')
for n in ("ic_launcher", "ic_launcher_round"):
    open(f"{RES}/mipmap-anydpi-v26/{n}.xml", "w").write(
        '<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <background android:drawable="@drawable/ic_launcher_bg"/>\n  <foreground android:drawable="@drawable/ic_launcher_fg"/>\n'
        '  <monochrome android:drawable="@drawable/ic_launcher_mono"/>\n</adaptive-icon>\n')

# ---- raster via headless Chrome ----
tmp = tempfile.mkdtemp()
def render(markup, w, h, name):
    html = os.path.join(tmp, name + ".html")
    open(html, "w").write(f'<html><body style="margin:0;background:transparent">{markup}</body></html>')
    out = os.path.join(tmp, name + ".png")
    subprocess.run(["google-chrome", "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
                    "--default-background-color=00000000", f"--window-size={w},{h}", f"--screenshot={out}",
                    "file://" + html], check=True, capture_output=True)
    return Image.open(out).convert("RGBA")
full = render(svg(True, 1024), 1024, 1024, "full")
glyph = render(svg(False, 1024), 1024, 1024, "glyph")
mono = render(svg(False, 1024, mono=True), 1024, 1024, "mono")
def mask(size, kind):
    m = Image.new("L", (size * 4, size * 4), 0); d = ImageDraw.Draw(m)
    if kind == "circle": d.ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    else: d.rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=int(size * 4 * .3), fill=255)
    return m.resize((size, size), Image.LANCZOS)
def shaped(img, size, kind, inset=0.0):
    # legacy icons: crop the 72/108 visible part of the adaptive canvas
    c = int(1024 * (18 / 108)); v = img.crop((c, c, 1024 - c, 1024 - c)).resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0)); out.paste(v, (0, 0), mask(size, kind)); return out
for d, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    p = f"{RES}/mipmap-{d}"
    shaped(full, px, "squircle").save(f"{p}/ic_launcher.png")
    shaped(full, px, "circle").save(f"{p}/ic_launcher_round.png")
    fg = int(px * 108 / 72)
    for stale in ("ic_launcher_background.png", "ic_launcher_foreground.png"):
        if os.path.exists(f"{p}/{stale}"): os.remove(f"{p}/{stale}")
mono.resize((432, 432), Image.LANCZOS).save(f"{RES}/drawable-nodpi/ic_launcher_monochrome.png")
# ---- in-app logo (same glyph) ----
os.makedirs(ASSETS, exist_ok=True)
c = int(1024 * (21 / 108)); glyph.crop((c, c, 1024 - c, 1024 - c)).resize((512, 512), Image.LANCZOS).save(f"{ASSETS}/logo_server_plus.png")
open(f"{ASSETS}/logo_server_plus.svg", "w").write(svg(False, 108))
# ---- TV banner 320x180 (xhdpi) ----
bn = f'''<div style="width:320px;height:180px;display:flex;align-items:center;gap:14px;padding-left:26px;box-sizing:border-box;
background:radial-gradient(circle at 26% 50%,#4A0A0E 0,#1A0406 45%,#050505 85%);font-family:Roboto,'Noto Sans',sans-serif">
<div style="width:96px;height:96px">{svg(False, 96).replace('width="96" height="96"', 'width="96" height="96" style="transform:scale(1.45)"')}</div>
<div style="color:#fff;font-size:44px;font-weight:800;letter-spacing:-.5px">Прокси<span style="color:#F0333C">+</span></div></div>'''
render(bn, 320, 180, "banner").convert("RGB").save(f"{RES}/drawable-xhdpi/tv_banner.png")
# ---- previews: circle + squircle ----
os.makedirs(PREV, exist_ok=True)
sheet = Image.new("RGBA", (760, 400), (242, 242, 246, 255)); dk = Image.new("RGBA", (760, 400), (18, 18, 20, 255))
full_ad = full  # adaptive: launcher masks the full 108 canvas, keeps the central 72 visible
for i, k in enumerate(("circle", "squircle")):
    ic = shaped(full_ad, 300, k)
    sheet.paste(ic, (60 + i * 360, 50), ic); dk.paste(ic, (60 + i * 360, 50), ic)
sheet.save(f"{PREV}/icon_preview_light.png"); dk.save(f"{PREV}/icon_preview_dark.png")
m = shaped(mono.convert("RGBA"), 300, "circle"); th = Image.new("RGBA", (420, 400), (232, 222, 248, 255))
tint = Image.new("RGBA", (300, 300), (60, 30, 110, 255)); th.paste(tint, (60, 50), m.split()[3]); th.save(f"{PREV}/icon_preview_themed.png")
full.save(f"{PREV}/icon_1024.png")
print("ok")
