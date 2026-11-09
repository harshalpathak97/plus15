"""Play phone screenshots (1080x1920) from raw emulator captures in .context/store/raw,
each shown in a Pixel 11 Pro (front: thin even bezels, centered punch-hole camera,
power and volume keys on the right edge).

The feature graphic and icon are made elsewhere (the live feature graphic is v2 in the
1.0.3 release folder), so this script only frames the phone shots.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
import pathlib; ROOT=str(pathlib.Path(__file__).resolve().parents[2])
RAW=f'{ROOT}/.context/store/raw'; OUT=f'{ROOT}/docs/store'
F=lambda w,s: ImageFont.truetype(f'{ROOT}/assets/fonts/Inter-{w}.ttf', s)
INK=(18,20,23); TEAL=(11,124,116); BG=(244,244,241); MUTED=(88,94,102)
SS=3  # supersampling for smooth device edges

def pixel_phone(shot, screen_h):
    """The capture inside a Pixel 11 Pro front, as an RGBA image (with room for the keys)."""
    sw=round(shot.width*screen_h/shot.height); sh=screen_h
    bez=round(sw*0.028); rim=round(sw*0.012)          # black glass border, metal rim
    bw,bh=sw+2*(bez+rim), sh+2*(bez+rim)
    keys=round(sw*0.012)                               # keys stand proud of the right edge
    W,H=(bw+keys)*SS, bh*SS
    im=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(im)
    r_body=round(bw*0.115)*SS
    # power key (upper) and volume rocker (below), right edge, like the Pixel 10/11 Pro
    for top,length in ((0.205,0.075),(0.31,0.15)):
        d.rounded_rectangle([bw*SS-keys*SS, round(bh*top)*SS, W, round(bh*(top+length))*SS],
                            radius=keys*SS, fill=(58,61,66,255))
    # metal frame with a soft highlight, then the black glass
    d.rounded_rectangle([0,0,bw*SS-1,H-1], radius=r_body, fill=(70,73,78,255))
    d.rounded_rectangle([SS,SS,bw*SS-1-SS,H-1-SS], radius=r_body-SS, fill=(118,122,128,255))
    d.rounded_rectangle([rim*SS//2,rim*SS//2,bw*SS-1-rim*SS//2,H-1-rim*SS//2], radius=r_body-rim*SS//2, fill=(52,55,60,255))
    d.rounded_rectangle([rim*SS,rim*SS,bw*SS-1-rim*SS,H-1-rim*SS], radius=r_body-rim*SS, fill=(9,10,12,255))
    im=im.resize((bw+keys,bh),Image.LANCZOS)
    # screen, rounded to sit inside the glass, with the centered punch-hole camera
    scr=shot.convert('RGB').resize((sw,sh),Image.LANCZOS).convert('RGBA')
    m=Image.new('L',(sw*SS,sh*SS),0); md=ImageDraw.Draw(m)
    md.rounded_rectangle([0,0,sw*SS-1,sh*SS-1],radius=round(sw*0.085)*SS,fill=255)
    cam_r=round(sw*0.021); cx,cy=sw//2, round(sw*0.046)
    md.ellipse([(cx-cam_r)*SS,(cy-cam_r)*SS,(cx+cam_r)*SS,(cy+cam_r)*SS],fill=0)
    scr.putalpha(m.resize((sw,sh),Image.LANCZOS))
    im.alpha_composite(scr,(bez+rim,bez+rim))
    # a faint lens ring in the hole, so it reads as a camera, not a dot
    lens=Image.new('RGBA',((2*cam_r)*SS,(2*cam_r)*SS),(0,0,0,0)); ld=ImageDraw.Draw(lens)
    ld.ellipse([0,0,2*cam_r*SS-1,2*cam_r*SS-1],fill=(6,7,9,255))
    ld.ellipse([cam_r*SS*0.45,cam_r*SS*0.45,cam_r*SS*1.55,cam_r*SS*1.55],fill=(22,26,34,255))
    im.alpha_composite(lens.resize((2*cam_r,2*cam_r),Image.LANCZOS),(bez+rim+cx-cam_r,bez+rim+cy-cam_r))
    return im

def frame(raw, title, sub, name, blank_from=None, H_SHOT=1440):
    W,H=1080,1920
    bg=Image.new('RGB',(W,H),BG)
    glow=Image.new('RGBA',(W,H),(0,0,0,0))
    ImageDraw.Draw(glow).ellipse([140,700,940,1700], fill=(63,208,193,70)); glow=glow.filter(ImageFilter.GaussianBlur(160))
    bg.paste(glow,(0,0),glow)
    d=ImageDraw.Draw(bg)
    d.rounded_rectangle([90,118,150,126],4,fill=TEAL)
    d.text((90,150), title, font=F(700,76), fill=INK)
    d.text((90,252), sub, font=F(500,38), fill=MUTED)
    assert d.textlength(title, font=F(700,76))<=W-180 and d.textlength(sub, font=F(500,38))<=W-180, name
    shot=Image.open(f'{RAW}/{raw}.png').convert('RGB')
    if blank_from:  # clear list rows below the fold, keeping the tab bar and true screen size
        ImageDraw.Draw(shot).rectangle([0,blank_from,shot.width,2159],fill=shot.getpixel((540,blank_from-12)))
    phone=pixel_phone(shot, H_SHOT)
    x=(W-phone.width)//2; y=H-phone.height-50
    sh=Image.new('RGBA',(W,H),(0,0,0,0))
    ImageDraw.Draw(sh).rounded_rectangle([x+16,y+36,x+phone.width-16,y+phone.height+24],80,fill=(0,0,0,80))
    sh=sh.filter(ImageFilter.GaussianBlur(34)); bg.paste(sh,(0,0),sh)
    bg.paste(phone,(x,y),phone)
    bg.save(f'{OUT}/{name}.png', optimize=True); print(name, os.path.getsize(f'{OUT}/{name}.png')//1024,'KB')

# The first two carry the pitch: they're the only ones shown on Play search cards.
specs=[
 ('03-nav',"Skip the cold","Bankers Hall to The Bow, all indoors",1880),
 ('02-routes',"Every bridge named","Step by step, with step-free routes",None),
 ('04-nearest',"Find a way in","The nearest +15 entrance from the street",None),
 ('05-directory',"130+ places, real hours","Coffee, food and shops, open now",None),
 ('07-ask',"Just ask","Coffee, food or a route, with one-tap directions",None),
 ('06-3d',"See it in 3D","16 km of skywalks, 15 feet up",None),
 ('01-map',"Calgary’s +15 map","109 buildings, 80 bridges, one calm map",None),
]
if __name__=='__main__':
    for f in pathlib.Path(OUT).glob('phone-*.png'): f.unlink()
    for i,(raw,t,s,c) in enumerate(specs,1): frame(raw,t,s,f'phone-{i}',c)
