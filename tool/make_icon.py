"""Penna.png (blue on white or transparent) -> assets/logo.png (transparent) + app_icon.ico."""
import sys
from PIL import Image

src, logo_out, ico_out = sys.argv[1:4]
# Flatten onto white first so a transparent source behaves like a white one.
img = Image.open(src).convert("RGBA")
img = Image.alpha_composite(Image.new("RGBA", img.size, "white"), img).convert("RGB")

# White -> transparent: the red channel is ~255 on paper and ~36 on ink.
r = img.split()[0]
lo, hi = r.getextrema()
alpha = r.point(lambda v: max(0, min(255, round((hi - v) * 255 / (hi - lo)))))
ink = min(img.resize((256, 256)).getdata(), key=lambda p: p[0])
glyph = Image.new("RGBA", img.size, ink + (0,))
glyph.putalpha(alpha)

# Trim the margin, then pad back to a square.
box = alpha.point(lambda v: 255 if v > 16 else 0).getbbox()
glyph = glyph.crop(box)
side = max(glyph.size)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.paste(glyph, ((side - glyph.width) // 2, (side - glyph.height) // 2))

square.resize((256, 256), Image.LANCZOS).save(logo_out)

# Icon: the feather at 92% on a transparent tile.
S = 1024
tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
inner = square.resize((int(S * 0.92),) * 2, Image.LANCZOS)
off = (S - inner.width) // 2
tile.alpha_composite(inner, (off, off))
tile.save(ico_out, sizes=[(n, n) for n in (16, 20, 24, 32, 40, 48, 64, 256)])
print("ink", ink, "bbox", box)
