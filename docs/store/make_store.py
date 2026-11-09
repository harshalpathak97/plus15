"""Play phone screenshots (1080x1920) from raw emulator captures in .context/store/raw.

The feature graphic and icon are made elsewhere (the live feature graphic is v2 in the
1.0.3 release folder), so this script only frames the phone shots.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
import pathlib; ROOT=str(pathlib.Path(__file__).resolve().parents[2])
RAW=f'{ROOT}/.context/store/raw'; OUT=f'{ROOT}/docs/store'
F=lambda w,s: ImageFont.truetype(f'{ROOT}/assets/fonts/Inter-{w}.ttf', s)
INK=(18,20,23); TEAL=(11,124,116); BG=(244,244,241); MUTED=(88,94,102)

def rounded(im, r):
    m=Image.new('L', im.size, 0); ImageDraw.Draw(m).rounded_rectangle([0,0,*im.size], r, fill=255)
    im=im.convert('RGBA'); im.putalpha(m); return im

def frame(raw, title, sub, name, crop_h=None, H_SHOT=1440):
    W,H=1080,1920
    bg=Image.new('RGB',(W,H),BG)
    glow=Image.new('RGBA',(W,H),(0,0,0,0))
    ImageDraw.Draw(glow).ellipse([140,700,940,1700], fill=(63,208,193,70)); glow=glow.filter(ImageFilter.GaussianBlur(160))
    bg.paste(glow,(0,0),glow)
    d=ImageDraw.Draw(bg)
    d.rounded_rectangle([90,118,150,126],4,fill=TEAL)
    d.text((90,150), title, font=F(700,76), fill=INK)
    d.text((90,252), sub, font=F(500,38), fill=MUTED)
    shot=Image.open(f'{RAW}/{raw}.png').convert('RGB')
    if crop_h: shot=shot.crop((0,0,shot.width,crop_h))  # hide text below the fold
    w=int(shot.width*H_SHOT/shot.height); shot=shot.resize((w,H_SHOT), Image.LANCZOS)
    bez=Image.new('RGBA',(w+28,H_SHOT+28),(0,0,0,0)); ImageDraw.Draw(bez).rounded_rectangle([0,0,w+27,H_SHOT+27],62,fill=(42,46,52,255))
    x=(W-bez.width)//2; y=H-bez.height-60
    sh=Image.new('RGBA',(W,H),(0,0,0,0)); ImageDraw.Draw(sh).rounded_rectangle([x+10,y+30,x+bez.width-10,y+bez.height+20],70,fill=(0,0,0,70))
    sh=sh.filter(ImageFilter.GaussianBlur(30)); bg.paste(sh,(0,0),sh)
    bg.paste(bez,(x,y),bez); s=rounded(shot,50); bg.paste(s,(x+14,y+14),s)
    assert d.textlength(title, font=F(700,76))<=W-180 and d.textlength(sub, font=F(500,38))<=W-180, name
    bg.save(f'{OUT}/{name}.png', optimize=True); print(name, os.path.getsize(f'{OUT}/{name}.png')//1024,'KB')

# The first two carry the pitch: they're the only ones shown on Play search cards.
specs=[
 ('03-nav',"Skip the cold","Bankers Hall to The Bow, all indoors",1880),
 ('02-routes',"Every bridge named","Step by step, with step-free routes",None),
 ('04-nearest',"Find a way in","The nearest +15 entrance from the street",None),
 ('05-directory',"130+ places, real hours","Coffee, food and shops, open now",None),
 ('06-3d',"See it in 3D","16 km of skywalks, 15 feet up",None),
 ('01-map',"Calgary’s +15 map","109 buildings, 80 bridges, one calm map",None),
]
for f in pathlib.Path(OUT).glob('phone-*.png'): f.unlink()
for i,(raw,t,s,c) in enumerate(specs,1): frame(raw,t,s,f'phone-{i}',c)
