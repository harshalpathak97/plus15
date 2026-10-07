"""Contact sheet + thumbnail strip for the exported Play deck.
   python3 scripts/sheet.py <dir with NN-*.png> <out.png> [thumb_width]"""
import sys, glob
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
tw = int(sys.argv[3]) if len(sys.argv) > 3 else 360
files = sorted(glob.glob(f"{src}/*.png"))
ims = [Image.open(f).convert("RGB") for f in files]
th = round(tw * ims[0].height / ims[0].width)
gap = max(6, tw // 24)
sheet = Image.new("RGB", (len(ims) * tw + (len(ims) + 1) * gap, th + 2 * gap), (214, 214, 210))
for i, im in enumerate(ims):
    sheet.paste(im.resize((tw, th), Image.LANCZOS), (gap + i * (tw + gap), gap))
sheet.save(out, optimize=True)
print(out, sheet.size)
