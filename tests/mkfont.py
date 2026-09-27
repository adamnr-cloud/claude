# Generate an 8x16 CP437 bitmap font table for gnumach from GNU Unifont.
import sys
from PIL import Image, ImageDraw, ImageFont
font = ImageFont.truetype('/usr/share/fonts/opentype/unifont/unifont.otf', 16)
# CP437 control-range pictographs, then the high half.
low = "\u0000☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼"
high = bytes(range(128, 256)).decode('cp437')
table = [low[i] if i < 32 else (chr(i) if i < 127 else ('⌂' if i == 127 else high[i-128])) for i in range(256)]
out = []
for i, ch in enumerate(table):
    img = Image.new('1', (8, 16), 0)
    d = ImageDraw.Draw(img)
    if ch != "\u0000":
        d.text((0, 14), ch, font=font, fill=1, anchor='ls')
    rows = []
    for y in range(16):
        b = 0
        for x in range(8):
            if img.getpixel((x, y)):
                b |= 0x80 >> x
        rows.append(b)
    out.append((i, ch, rows))
if len(sys.argv) > 1 and sys.argv[1] == 'show':
    for i, ch, rows in out:
        if i in map(ord, sys.argv[2]):
            print(hex(i))
            for r in rows: print(format(r, '08b').replace('0', '.').replace('1', '#'))
    sys.exit()
print("/* 8x16 glyphs for code page 437, rendered from GNU Unifont 15.1.")
print("   GNU Unifont is dual licensed under the SIL Open Font License 1.1 and the")
print("   GNU GPL version 2 or later with the GNU Font Embedding Exception.  */")
print()
print("static const unsigned char kdfb_font[256][16] = {")
for i, ch, rows in out:
    name = repr(ch) if i >= 32 else "ctrl %d" % i
    name = name.replace('*/', '* /')
    print("\t/* 0x%02x %s */ { %s }," % (i, name, ", ".join("0x%02x" % r for r in rows)))
print("};")
