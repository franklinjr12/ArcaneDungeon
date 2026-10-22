#!/usr/bin/env python3
"""Visual contact sheet for reviewing all reference-guided generated art in one file."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[2]
A=ROOT/"assets"/"pixel"
O=ROOT/"art"/"previews"
O.mkdir(parents=True,exist_ok=True)
W,H=1280,780
bg=Image.new("RGBA",(W,H),"#0b131c")
d=ImageDraw.Draw(bg)
GOLD="#c58b43"
MUTED="#b5c0c5"
CREAM="#e6ca92"
font=ImageFont.load_default()
def label(x,y,text,color=CREAM):
    d.text((x,y),text,font=font,fill=color)
def panel(x,y,w,h,title):
    d.rounded_rectangle((x,y,x+w,y+h),radius=3,fill="#0c1822",outline=GOLD,width=2)
    d.line((x+7,y+4,x+w-7,y+4),fill="#765531",width=1)
    label(x+14,y+13,title,CREAM)
def image(path):return Image.open(A/path).convert("RGBA")
def paste(im,x,y,scale=1,crop=None):
    if crop is not None:im=im.crop(crop)
    if scale!=1:im=im.resize((int(im.width*scale),int(im.height*scale)),Image.Resampling.NEAREST)
    bg.alpha_composite(im,(int(x),int(y)))
panel(9,9,1262,72,"ARCANE DUNGEON  /  PIXEL ART WORKSTREAM")
label(31,48,"Provisional owner-reference-inspired gameplay assets | editable source: art/aseprite | no gameplay changes",MUTED)
panel(9,89,832,323,"01  ANIMATED CLASSES + ENEMIES")
items=[("mage","MAGE",50,135),("pursuer","GOBLIN",185,135),("ranged","CULTIST",320,135),("flanker","FLANKER",455,135),("dummy","DUMMY",590,135)]
for name,title,x,y in items:
    im=image(name+"_sheet.png")
    paste(im,x,y,2.0,(0,0,48,56))
    label(x-1,y+127,title)
boss=image("boss_sheet.png")
paste(boss,665,165,1.4,(0,0,104,112))
label(698,331,"RUNE CHIMERA")
panel(850,89,421,323,"02  ENVIRONMENTS + TILES")
tiles=image("dungeon_tiles.png")
paste(tiles,884,143,1.4)
props=image("dungeon_props.png")
for i,name in enumerate(["TORCH","CRYSTAL","RUBBLE","MOSS"]):
    paste(props,878+i*93,283,1.5,(i*48,0,(i+1)*48,48))
    label(883+i*93,360,name)
panel(9,420,608,350,"03  SPELLS  /  VFX")
fx=image("spell_effects.png")
rows=["FIRE","WATER","LIGHTNING","ORBIT","HOSTILE","ARC","IMPACT","DODGE"]
for i,name in enumerate(rows):
    row=i//4; col=i%4
    xx=33+col*145; yy=461+row*145
    paste(fx,xx,yy,2.4,(3*32,i*32,4*32,(i+1)*32))
    label(xx+5,yy+88,name)
panel(625,420,646,350,"04  RUNES / HUD SYMBOLS")
icons=image("rune_icons.png")
paste(icons,664,459,2.1)
label(670,694,"10 equipped rune types + status, HP/MP, upgrades and controls")
bg.convert("RGB").save(O/"art_overview.png")
print("ART_OVERVIEW",O/"art_overview.png")
