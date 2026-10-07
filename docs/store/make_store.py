from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
import pathlib; ROOT=str(pathlib.Path(__file__).resolve().parents[2])
RAW=f'{ROOT}/.context/store/raw'; OUT=f'{ROOT}/docs/store'
F=lambda w,s: ImageFont.truetype(f'{ROOT}/assets/fonts/Inter-{w}.ttf', s)
INK=(18,20,23); TEAL=(63,208,193); SOFT=(244,244,241); MUTED=(170,176,184)

def rounded(im, r):
    m=Image.new('L', im.size, 0); ImageDraw.Draw(m).rounded_rectangle([0,0,*im.size], r, fill=255)
    im=im.convert('RGBA'); im.putalpha(m); return im

def frame(raw, title, sub, name, H_SHOT=1440):
    W,H=1080,1920
    bg=Image.new('RGB',(W,H),INK)
    d=ImageDraw.Draw(bg)
    # subtle teal glow behind the phone
    glow=Image.new('RGBA',(W,H),(0,0,0,0)); gd=ImageDraw.Draw(glow)
    gd.ellipse([140,700,940,1700], fill=(11,124,116,90)); glow=glow.filter(ImageFilter.GaussianBlur(160))
    bg.paste(glow,(0,0),glow)
    d=ImageDraw.Draw(bg)
    d.rounded_rectangle([90,118,150,126],4,fill=TEAL)
    d.text((90,150), title, font=F(700,76), fill=(255,255,255))
    d.text((90,252), sub, font=F(500,38), fill=MUTED)
    shot=Image.open(f'{RAW}/{raw}.png').convert('RGB')
    shot=shot.crop((6,6,shot.width-6,shot.height-6))  # drop the emulator's edge flash
    w=int(shot.width*H_SHOT/shot.height); shot=shot.resize((w,H_SHOT), Image.LANCZOS)
    # bezel
    bez=Image.new('RGBA',(w+28,H_SHOT+28),(0,0,0,0)); ImageDraw.Draw(bez).rounded_rectangle([0,0,w+27,H_SHOT+27],62,fill=(42,46,52,255))
    x=(W-bez.width)//2; y=H-bez.height-60
    sh=Image.new('RGBA',(W,H),(0,0,0,0)); ImageDraw.Draw(sh).rounded_rectangle([x+10,y+30,x+bez.width-10,y+bez.height+20],70,fill=(0,0,0,150))
    sh=sh.filter(ImageFilter.GaussianBlur(30)); bg.paste(sh,(0,0),sh)
    bg.paste(bez,(x,y),bez); s=rounded(shot,50); bg.paste(s,(x+14,y+14),s)
    bg.save(f'{OUT}/{name}.png', optimize=True); print(name, os.path.getsize(f'{OUT}/{name}.png')//1024,'KB')

frames=[
 ('01-map',      "Calgary’s +15,\nfinally easy",        "", ),
]
specs=[
 ('01-map',"The +15, finally easy","16 km of indoor skywalks on one calm map"),
 ('03-navigation',"Turn-by-turn, indoors","Live guidance by named bridges and buildings"),
 ('02-route-options',"Every step spelled out","Step-free options and honest walk times"),
 ('06-ask',"Just ask","Coffee, food or a route, answered in seconds"),
 ('05-directory',"141 places, real hours","Shops, food and services, open now at a glance"),
 ('04-3d',"See it in 3D","Follow your walk through the skywalks"),
 ('07-dark',"Easy on the eyes","A dark mode for late nights downtown"),
]
for i,(raw,t,s) in enumerate(specs,1): frame(raw,t,s,f'phone-{i}')

# Feature graphic 1024x500
W,H=1024,500
fg=Image.new('RGB',(W,H),INK); d=ImageDraw.Draw(fg)
glow=Image.new('RGBA',(W,H),(0,0,0,0)); ImageDraw.Draw(glow).ellipse([560,-100,1180,600],fill=(11,124,116,110)); glow=glow.filter(ImageFilter.GaussianBlur(120)); fg.paste(glow,(0,0),glow)
mark=Image.open(f'{ROOT}/assets/icons/plus15_mark.png').convert('RGBA'); mw=150; mark=mark.resize((mw,int(mark.height*mw/mark.width)),Image.LANCZOS)
fg.paste(mark,(64,96),mark)
d=ImageDraw.Draw(fg)
d.text((64,226),"Calgary’s +15,",font=F(700,52),fill=(255,255,255))
d.text((64,288),"finally easy.",font=F(700,52),fill=TEAL)
d.text((64,372),"Indoor routes · 141 places · live hours",font=F(500,24),fill=MUTED)
shot=Image.open(f'{RAW}/03-navigation.png').convert('RGB').crop((6,6,1074,2394))
sw=300; shot=shot.resize((sw,int(shot.height*sw/shot.width)),Image.LANCZOS)
bez=Image.new('RGBA',(sw+16,shot.height+16),(0,0,0,0)); ImageDraw.Draw(bez).rounded_rectangle([0,0,sw+15,shot.height+15],34,fill=(42,46,52,255))
fg.paste(bez,(640,70),bez); s=rounded(shot,28); fg.paste(s,(648,78),s)
fg.save(f'{OUT}/feature-graphic.png',optimize=True); print('feature', os.path.getsize(f'{OUT}/feature-graphic.png')//1024,'KB')

# Icon 512
ic=Image.open(f'{ROOT}/assets/icons/plus15_logo.png').convert('RGB').resize((512,512),Image.LANCZOS)
ic.save(f'{OUT}/icon-512.png',optimize=True); print('icon', os.path.getsize(f'{OUT}/icon-512.png')//1024,'KB')
