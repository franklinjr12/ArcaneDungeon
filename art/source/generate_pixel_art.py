#!/usr/bin/env python3
"""Reproducible ArcaneDungeon reference-guided pixel art (Pillow source + Aseprite exports).
Observed reference: near-black navy grounds; worn gold/ochre trims; chunky silhouettes,
layered earth/steel/emerald/violet materials; small selective cyan/orange magical highlights.
PROPOSED sizes, not a finalized art bible. No game mechanics changed by these assets.
"""
from __future__ import annotations
from PIL import Image,ImageDraw
from pathlib import Path
import math,random,json
OUT=Path(__file__).resolve().parents[2]/"assets"/"pixel"
OUT.mkdir(parents=True,exist_ok=True)
SOURCES=Path(__file__).resolve().parent
random.seed(30226)
C={"void":"#0a101a","outline":"#10151b","deep":"#1c2631","stone":"#414c51","stone_mid":"#626b65",
   "stone_hi":"#929a87","gold_dark":"#6b441f","gold":"#c48a39","gold_lit":"#f4c16b",
   "parch":"#eee2b4","skin":"#e3ac77","skin_lo":"#ae7157","hair":"#52392b",
   "purple":"#463a73","purple_mid":"#785db1","purple_hi":"#b4a1f5",
   "blue":"#254b78","blue_lit":"#5391c1","cyan":"#79e0ef","ice":"#c2f4fc",
   "fire_dark":"#912c25","fire":"#e86b23","orange":"#ffaf39","yellow":"#ffe79a",
   "green_dark":"#254833","green":"#569c4a","green_hi":"#a5ce68",
   "red":"#a94643","red_hi":"#e69b68","brown":"#624b3d","brown_lit":"#a17c56"}
def ink(img):return ImageDraw.Draw(img)
def blank(w,h):return Image.new("RGBA",(w,h),(0,0,0,0))
def rect(d,b,c,outline=None):d.rectangle(tuple(map(int,b)),fill=c,outline=outline)
def poly(d,p,c,outline=None):d.polygon([(int(x),int(y)) for x,y in p],fill=c); d.line([(int(x),int(y)) for x,y in p+[p[0]]],fill=outline,width=1) if outline else None
def ell(d,b,c,outline=None):d.ellipse(tuple(map(int,b)),fill=c,outline=outline)
def line(d,p,c,w=1):d.line(p,fill=c,width=w)
def sprite(kind,pose,phase=0):
    w,h=(104,112) if kind=="boss" else (48,56)
    im=blank(w,h);d=ink(im)
    if pose=="dead":
        ell(d,[9 if kind!="boss" else 16,h-15,w-8,h-8],(0,0,0,115))
        if kind=="boss":
            for x,y,wid in [(13,83,19),(37,72,22),(64,85,19),(80,78,16)]:
                poly(d,[(x-4,y+19),(x,y),(x+wid,y-4),(x+wid+5,y+19)],C["stone"],C["outline"])
                line(d,[(x+2,y+6),(x+wid-2,y+7)],C["stone_hi"],2)
            poly(d,[(42,70),(56,74),(53,87),(43,87)],C["purple"],C["gold_dark"])
        else:
            poly(d,[(8,41),(15,34),(36,36),(43,45),(38,49),(10,48)],C["purple"] if kind in ["mage","ranged"] else C["stone"],C["outline"])
            ell(d,[16,31,33,42],C["skin"] if kind=="mage" else (C["green"] if kind=="pursuer" else C["stone_mid"]),C["outline"])
            line(d,[(21,36),(26,38)],C["outline"],2)
        return im
    if kind=="boss":
        j=phase%3
        ell(d,[18,92,87,103],(0,0,0,115))
        # asymmetric beast with crystalline crown, luminous rune core and claws
        poly(d,[(19,63),(9,75),(7,94),(19,92),(28,79),(28,50)],C["deep"],C["outline"])
        poly(d,[(82,58),(97,73),(98,92),(86,93),(78,81),(72,56)],C["stone"],C["outline"])
        poly(d,[(18,69),(13,89),(30,91),(37,66)],C["stone_mid"],C["outline"])
        poly(d,[(66,66),(78,91),(94,89),(87,72)],C["stone_mid"],C["outline"])
        for x in [17,84]:
            poly(d,[(x-8,90),(x-5,78),(x+8,76),(x+12,91)],C["stone_hi"],C["outline"])
            for off in [0,7,13]:rect(d,[x-5+off,84,x-4+off,87],C["stone"])
        poly(d,[(22,33),(32,18),(72,18),(83,31),(88,65),(76,82),(26,80),(16,64)],C["stone"],C["outline"])
        poly(d,[(31,32),(43,25),(72,29),(79,54),(68,70),(34,69),(25,57)],C["stone_mid"],C["deep"])
        for pts in [[(23,39),(28,21),(34,36),(43,9),(47,28)],[(68,28),(77,9),(83,35),(88,23),(88,45)]]:
            poly(d,pts,C["stone_hi"],C["outline"])
        for x,y in [(28,48),(67,45),(44,36),(75,66),(37,71)]:
            poly(d,[(x,y),(x+8,y-3),(x+12,y+4),(x+5,y+10)],C["stone_hi"],C["deep"])
            rect(d,[x+2,y+4,x+4,y+5],C["parch"])
        # rune core
        ell(d,[36,40,67,74],C["outline"])
        poly(d,[(51,41),(66,56),(51,71),(37,56)],C["gold_dark"],C["gold_lit"])
        poly(d,[(51,44),(60,56),(51,67),(43,56)],C["purple_hi"] if j==1 else C["cyan"],C["ice"])
        line(d,[(51,48),(51,65)],C["ice"],2)
        line(d,[(45,56),(58,56)],C["ice"],2)
        # grim face
        poly(d,[(35,25),(43,20),(62,21),(70,27),(62,38),(43,38)],C["deep"],C["outline"])
        for x in [42,59]:
            rect(d,[x,29,x+5,32],C["orange"] if j==2 else C["yellow"])
        line(d,[(47,36),(58,36)],C["gold"],2)
        # trailing glyph chips
        for i,(x,y) in enumerate([(11,45),(90,40),(39,10),(71,9),(8,63),(96,59)]):
            if (i+phase)%2==0:
                rect(d,[x,y,x+2,y+3],C["cyan"])
        return im
    walking=pose=="walk"; casting=pose=="cast"; struck=pose=="hurt"
    bob=[0,1,0,-1][phase%4]
    oy=bob
    ell(d,[10,47,38,52],(0,0,0,110))
    if kind=="mage":
        # leather boots, dark blue cloak folds, robe, gold piping
        stride=[-3,1,4,0][phase%4] if walking else 0
        poly(d,[(13,32+oy),(19,28+oy),(31,29+oy),(38,46+oy),(31,49+oy),(15,49+oy)],C["purple"],C["outline"])
        for x,sh in [(17,-stride),(29,stride)]:
            rect(d,[x+sh,41+oy,x+5+sh,48+oy],C["brown"],C["outline"])
            rect(d,[x+sh,46+oy,x+6+sh,49+oy],C["stone"])
        poly(d,[(15,27+oy),(23,24+oy),(30,26+oy),(36,44+oy),(13,44+oy)],C["blue"],C["outline"])
        poly(d,[(18,28+oy),(27,28+oy),(29,43+oy),(16,43+oy)],C["blue_lit"])
        poly(d,[(23,27+oy),(29,30+oy),(29,44+oy),(26,44+oy)],C["purple_mid"])
        line(d,[(20,29+oy),(18,43+oy)],C["gold"],1)
        rect(d,[17,36+oy,31,38+oy],C["gold_dark"])
        rect(d,[24,36+oy,27,38+oy],C["gold_lit"])
        # left hand and right staff
        poly(d,[(15,29+oy),(10,32+oy),(9,39+oy),(16,41+oy),(20,34+oy)],C["blue"],C["outline"])
        ell(d,[8,38+oy,13,42+oy],C["skin"],C["outline"])
        dx=5 if casting else 0
        poly(d,[(32,28+oy),(38+dx,31+oy),(40+dx,39+oy),(33,39+oy),(29,32+oy)],C["blue_lit"],C["outline"])
        ell(d,[36+dx,37+oy,41+dx,42+oy],C["skin"],C["outline"])
        # staff and enchantment
        line(d,[(40+dx,40+oy),(43+dx,13+oy)],C["outline"],4)
        line(d,[(41+dx,39+oy),(43+dx,14+oy)],C["gold"],2)
        poly(d,[(43+dx,9+oy),(47+dx,14+oy),(43+dx,19+oy),(39+dx,14+oy)],C["cyan"],C["ice"])
        if casting:
            for x,y in [(44+dx,6+oy),(37+dx,12+oy),(47+dx,22+oy)]:
                rect(d,[x,y,x+2,y+2],C["yellow"])
        # hood dark silhouette and violet fringe
        ell(d,[11,6+oy,35,30+oy],C["outline"])
        poly(d,[(12,17+oy),(17,6+oy),(28,5+oy),(36,17+oy),(32,29+oy),(12,29+oy)],C["purple"],C["outline"])
        poly(d,[(15,16+oy),(20,8+oy),(28,9+oy),(32,16+oy),(30,23+oy),(16,23+oy)],C["purple_mid"])
        ell(d,[17,15+oy,30,29+oy],C["skin_lo"])
        rect(d,[18,18+oy,29,26+oy],C["skin"])
        poly(d,[(16,17+oy),(21,12+oy),(26,13+oy),(31,17+oy),(26,18+oy)],C["hair"])
        for x in [20,27]:rect(d,[x,22+oy,x+1,23+oy],C["outline"])
        rect(d,[23,25+oy,25,25+oy],C["red_hi"])
        rect(d,[19,14+oy,28,14+oy],C["purple_hi"])
    elif kind=="pursuer":
        # snarling goblin with ragged bracers and axe
        stride=[-2,0,2,0][phase%4] if walking else 0
        for x,sgn in [(16,-1),(29,1)]:
            rect(d,[x+stride*sgn,40+oy,x+5+stride*sgn,48+oy],C["brown"],C["outline"])
        poly(d,[(14,28+oy),(32,28+oy),(36,42+oy),(12,43+oy)],C["brown"],C["outline"])
        rect(d,[17,33+oy,30,39+oy],C["green_dark"])
        line(d,[(14,33+oy),(31,34+oy)],C["gold_dark"],2)
        poly(d,[(15,28+oy),(9,30+oy),(8,37+oy),(15,39+oy),(18,33+oy)],C["green"],C["outline"])
        poly(d,[(31,29+oy),(39,30+oy),(40,38+oy),(33,39+oy)],C["green"],C["outline"])
        line(d,[(39,39+oy),(45,18+oy)],C["brown_lit"],3)
        poly(d,[(39,18+oy),(45,11+oy),(47,22+oy),(43,25+oy)],C["stone_mid"],C["outline"])
        poly(d,[(13,22+oy),(2,20+oy),(9,29+oy),(15,26+oy)],C["green"],C["outline"])
        poly(d,[(34,22+oy),(46,18+oy),(39,30+oy),(34,26+oy)],C["green"],C["outline"])
        ell(d,[11,9+oy,36,32+oy],C["outline"])
        ell(d,[13,12+oy,34,30+oy],C["green_dark"])
        ell(d,[16,15+oy,31,29+oy],C["green"])
        poly(d,[(14,12+oy),(19,4+oy),(31,7+oy),(36,15+oy),(24,13+oy)],C["brown"],C["outline"])
        for x in [18,29]:rect(d,[x,20+oy,x+3,21+oy],C["orange"])
        rect(d,[22,25+oy,28,27+oy],C["outline"])
        for x in [23,27]:rect(d,[x,25+oy,x,26+oy],C["parch"])
        for x,y in [(13,16+oy),(33,24+oy)]:rect(d,[x,y,x+2,y+2],C["green_hi"])
    elif kind=="ranged":
        # hooded cultist with charged bow / shadow orb
        stride=[-2,0,2,0][phase%4] if walking else 0
        for x,sgn in [(17,-1),(29,1)]:
            rect(d,[x+stride*sgn,41+oy,x+4+stride*sgn,48+oy],C["deep"],C["outline"])
        poly(d,[(15,26+oy),(32,26+oy),(38,45+oy),(31,49+oy),(14,48+oy),(9,44+oy)],C["purple"],C["outline"])
        poly(d,[(18,28+oy),(30,28+oy),(32,44+oy),(17,44+oy)],C["purple_mid"],C["deep"])
        rect(d,[19,32+oy,28,34+oy],C["gold_dark"])
        poly(d,[(13,29+oy),(6,33+oy),(9,39+oy),(17,38+oy)],C["purple_mid"],C["outline"])
        poly(d,[(32,29+oy),(41,31+oy),(41,38+oy),(33,39+oy)],C["purple_mid"],C["outline"])
        ell(d,[36,32+oy,43,39+oy],C["ice"],C["blue"])
        ell(d,[38,34+oy,42,38+oy],C["cyan"])
        ell(d,[10,4+oy,36,31+oy],C["outline"])
        poly(d,[(11,19+oy),(16,6+oy),(29,4+oy),(37,20+oy),(31,31+oy),(15,30+oy)],C["purple"],C["outline"])
        poly(d,[(18,16+oy),(30,16+oy),(33,27+oy),(15,27+oy)],C["deep"])
        for x in [19,29]:rect(d,[x,21+oy,x+3,22+oy],C["cyan"])
        rect(d,[21,26+oy,27,27+oy],C["gold_dark"])
        poly(d,[(14,12+oy),(21,7+oy),(30,12+oy)],C["purple_hi"])
    elif kind=="flanker":
        # wolf-like forest hunter (wolf silhouette, with vivid eyes)
        stride=[-3,0,3,0][phase%4] if walking else 0
        poly(d,[(9,28+oy),(24,22+oy),(37,29+oy),(38,41+oy),(16,43+oy)],C["deep"],C["outline"])
        poly(d,[(12,29+oy),(27,27+oy),(32,35+oy),(17,39+oy)],C["stone"])
        for x,sgn in [(13,1),(28,-1)]:
            rect(d,[x+stride*sgn,39+oy,x+7+stride*sgn,48+oy],C["stone"],C["outline"])
            rect(d,[x+stride*sgn,46+oy,x+9+stride*sgn,49+oy],C["deep"])
        poly(d,[(36,31+oy),(45,24+oy),(41,35+oy),(46,42+oy),(36,39+oy)],C["deep"],C["outline"])
        poly(d,[(10,15+oy),(12,3+oy),(22,13+oy),(27,13+oy),(34,3+oy),(36,16+oy),(40,25+oy),(30,32+oy),(16,31+oy),(6,25+oy)],C["deep"],C["outline"])
        poly(d,[(12,16+oy),(17,8+oy),(22,18+oy),(30,18+oy),(33,8+oy),(35,19+oy),(31,28+oy),(17,28+oy)],C["stone"])
        poly(d,[(18,23+oy),(29,23+oy),(24,31+oy)],C["stone_hi"],C["outline"])
        for x in [16,30]:rect(d,[x,20+oy,x+3,21+oy],C["yellow"])
        rect(d,[22,27+oy,25,29+oy],C["outline"])
        for x,y in [(11,24+oy),(34,25+oy)]:rect(d,[x,y,x+1,y+2],C["stone_hi"])
    elif kind=="dummy":
        ell(d,[10,7+oy,37,34+oy],C["brown"],C["outline"])
        rect(d,[21,29+oy,26,49+oy],C["brown_lit"],C["outline"])
        ell(d,[13,10+oy,33,32+oy],C["parch"],C["gold_dark"])
        for radius,col in [(8,C["fire_dark"]),(5,C["gold"]),(2,C["fire_dark"])]:
            ell(d,[23-radius,21+oy-radius,23+radius,21+oy+radius],col)
        line(d,[(14,40+oy),(34,40+oy)],C["brown"],3)
    if struck:
        shade=Image.new("RGBA",(w,h),(255,240,215,55))
        im=Image.alpha_composite(im,shade)
    return im

def tileset():
    im=blank(32*8,32*3)
    for index in range(24):
        d=ImageDraw.Draw(im)
        x0=(index%8)*32;y0=(index//8)*32
        rand=random.Random(7100+index)
        iswall=8<=index<16
        isextra=index>=16
        base="#18262d" if iswall else ("#263e36" if isextra else "#263239")
        d.rectangle((x0,y0,x0+31,y0+31),fill=base)
        if iswall:
            for by in range(0,32,10):
                xshift=rand.choice([-5,0,5])
                for bx in range(-14,32,21):
                    l=x0+bx+xshift
                    d.rectangle((l,y0+by,l+18,y0+by+8),fill=rand.choice(["#354345","#495451","#56625a"]))
                    d.line((l,y0+by,l+18,y0+by),fill="#76816f",width=1)
                    d.line((l,y0+by+8,l+18,y0+by+8),fill="#111d25")
            d.line((x0,y0+31,x0+31,y0+31),fill=C["outline"],width=2)
            if index%4==1:
                for i in range(5):
                    xx=x0+rand.randrange(2,30);yy=y0+rand.randrange(2,27)
                    d.point((xx,yy),fill=C["green"])
        else:
            for py in range(-6,42,12):
                px=-rand.randrange(5,20)
                while px<36:
                    w=rand.randrange(11,24)
                    px0=x0+px;py0=y0+py
                    col=rand.choice(["#28393d","#304043","#354640","#3b4643","#45504a"] if not isextra else ["#2e4a3d","#35573c","#345849","#436143"])
                    d.rectangle((px0,py0,px0+w,py0+9),fill=col,outline="#1c2c33")
                    d.line((px0+1,py0+1,px0+w-2,py0+1),fill="#617063" if not isextra else "#678058")
                    px+=w+2
            for i in range(18):
                xx=x0+rand.randrange(0,32);yy=y0+rand.randrange(0,32)
                d.point((xx,yy),fill=rand.choice(["#69826a","#818c76","#1b2b32","#182528"]))
            if index%3==0:
                for i in range(3):
                    xx=x0+rand.randrange(6,27);yy=y0+rand.randrange(6,27)
                    d.point((xx,yy),fill=C["green_hi"])
    im.save(OUT/"dungeon_tiles.png")
    return im

def icons():
    names=["fire","water","lightning","projectile","burst","orb","homing","split","pierce","on_hit",
           "health","mana","rune","coin","dodge","wet","burning","charged","damage","door","shop","book","staff","shield"]
    im=blank(32*8,32*3)
    for i,name in enumerate(names):
        x=(i%8)*32;y=(i//8)*32
        tile=blank(32,32);d=ink(tile)
        ell(d,[3,3,28,28],C["void"],C["gold_dark"])
        for a,b in [([4,4,8,4],C["gold"]),([23,27,27,27],C["gold_lit"])]:rect(d,a,b)
        if name in ["fire","burning"]:
            poly(d,[(16,5),(10,16),(13,16),(9,25),(20,23),(24,15),(20,15)],C["fire"],C["outline"])
            poly(d,[(17,10),(14,18),(18,17),(16,24),(21,18)],C["yellow"])
        elif name in ["water","wet"]:
            poly(d,[(17,5),(8,20),(10,25),(16,28),(24,24),(23,18)],C["blue_lit"],C["ice"])
            ell(d,[12,18,17,23],C["cyan"])
        elif name in ["lightning","charged"]:
            poly(d,[(19,3),(9,18),(16,17),(12,28),(25,12),(18,13)],C["yellow"],C["outline"])
            line(d,[(17,7),(12,17),(20,15)],C["ice"])
        elif name=="health":
            poly(d,[(15,27),(6,19),(6,12),(11,9),(16,13),(20,9),(26,12),(26,19)],C["red"],C["outline"])
            rect(d,[11,14,19,17],C["red_hi"])
        elif name=="coin":
            ell(d,[7,6,25,25],C["gold_dark"],C["gold_lit"])
            ell(d,[10,9,22,22],C["gold"],C["gold_lit"])
            line(d,[(16,11),(16,20)],C["parch"],2)
        elif name=="orb":
            ell(d,[8,8,24,24],C["purple_mid"],C["purple_hi"])
            ell(d,[12,11,18,17],C["ice"])
        elif name in ["rune","book","on_hit"]:
            poly(d,[(7,8),(23,7),(24,25),(9,25)],C["purple"],C["gold"])
            line(d,[(11,12),(19,12),(16,20),(12,18)],C["cyan"],2)
        elif name=="projectile":
            poly(d,[(7,18),(22,7),(25,14),(12,24)],C["cyan"],C["blue"])
            line(d,[(6,26),(12,22)],C["ice"],2)
        elif name=="burst":
            for k in range(8):
                a=math.tau*k/8
                line(d,[(16+int(5*math.cos(a)),16+int(5*math.sin(a))),(16+int(12*math.cos(a)),16+int(12*math.sin(a)))],C["orange"],2)
            ell(d,[12,12,20,20],C["yellow"])
        elif name in ["homing","dodge"]:
            d.arc((5,5,26,26),25,300,fill=C["cyan"],width=3)
            poly(d,[(23,7),(28,13),(20,13)],C["ice"])
        elif name=="split":
            line(d,[(7,25),(17,14)],C["cyan"],3)
            line(d,[(17,14),(9,7)],C["cyan"],3)
            line(d,[(17,14),(25,7)],C["cyan"],3)
            for xx,yy in [(9,7),(25,7),(7,25)]:ell(d,[xx-2,yy-2,xx+2,yy+2],C["ice"])
        elif name in ["pierce","damage"]:
            poly(d,[(8,24),(23,7),(25,11),(13,27)],C["stone_hi"],C["outline"])
            line(d,[(8,22),(14,28)],C["gold"],2)
        elif name in ["door","shop"]:
            d.rectangle((10,6,23,26),fill=C["brown"],outline=C["gold_lit"])
            d.rectangle((14,8,20,25),fill=C["deep"],outline=C["gold_dark"])
            ell(d,[18,17,19,19],C["gold_lit"])
        elif name=="staff":
            line(d,[(8,27),(21,8)],C["gold"],3)
            poly(d,[(22,5),(26,9),(22,15),(18,9)],C["cyan"],C["ice"])
        elif name=="shield":
            poly(d,[(16,5),(26,9),(24,21),(16,27),(8,22),(6,9)],C["blue"],C["gold"])
            line(d,[(16,8),(16,23)],C["ice"],2)
        # paste individual
        im.alpha_composite(tile,(x,y))
    im.save(OUT/"rune_icons.png")
    (SOURCES/"icons_manifest.json").write_text(json.dumps({"cell":[32,32],"columns":8,"names":names},indent=2)+"\n")
    return im

def effects():
    ids=["fire","water","lightning","orb","enemy","arc","impact","dodge"]
    sheet=blank(32*8,32*8)
    rand=random.Random(9523)
    for row,kind in enumerate(ids):
        for frame in range(8):
            tile=blank(32,32);d=ink(tile)
            t=frame/8
            if kind in ["fire","water","lightning","enemy","orb"]:
                main={"fire":C["fire"],"water":C["blue_lit"],"lightning":C["yellow"],"enemy":C["purple_mid"],"orb":C["purple_hi"]}[kind]
                bright={"fire":C["yellow"],"water":C["ice"],"lightning":C["ice"],"enemy":C["cyan"],"orb":C["cyan"]}[kind]
                if kind=="fire":
                    for k in range(4):
                        x=9+rand.randrange(0,14); y=9+rand.randrange(0,14)
                        poly(d,[(x,y+7),(x-3,y),(x+2,y-7),(x+5,y+4)],main,C["outline"])
                    ell(d,[10,12,24,24],bright,main)
                    ell(d,[13,14,18,19],C["parch"])
                elif kind=="water":
                    poly(d,[(19,3),(10,14),(8,23),(16,27),(24,20),(22,10)],main,C["outline"])
                    poly(d,[(18,8),(14,19),(17,23),(21,19)],bright)
                    ell(d,[18,13,20,15],C["ice"])
                elif kind=="lightning":
                    for k in range(3):
                        off=(frame+k)%4-2
                        poly(d,[(16+off,4),(10+off,15),(16+off,16),(13+off,27),(24+off,13),(18+off,13)],main,C["outline"])
                    line(d,[(18,7),(14,15),(18,15)],bright,2)
                elif kind=="orb":
                    ell(d,[7,7,25,25],main,C["outline"])
                    ell(d,[11,11,21,21],bright,C["ice"])
                    for k in range(4):
                        a=(frame+k*2)*math.tau/8
                        x=16+int(math.cos(a)*12);y=16+int(math.sin(a)*12)
                        rect(d,[x,y,x+1,y+1],C["gold_lit"])
                else:
                    ell(d,[8,8,23,23],main,C["outline"])
                    ell(d,[12,11,18,17],bright)
            elif kind in ["arc","impact","dodge"]:
                radius=4+frame*2
                col=C["cyan"] if kind=="arc" else (C["orange"] if kind=="impact" else C["ice"])
                d.arc((16-radius,16-radius,16+radius,16+radius),0,345,fill=col,width=2)
                for k in range(7):
                    a=rand.random()*math.tau
                    rr=radius+rand.randrange(0,7)
                    xx=16+int(math.cos(a)*rr);yy=16+int(math.sin(a)*rr)
                    if 0<=xx<32 and 0<=yy<32:rect(d,[xx,yy,xx+1,yy+1],col)
            sheet.alpha_composite(tile,(frame*32,row*32))
    sheet.save(OUT/"spell_effects.png")
    (SOURCES/"effects_manifest.json").write_text(json.dumps({"cell":[32,32],"columns":8,"rows":ids,"frames":8,"fps":12},indent=2)+"\n")

def panel():
    for stem,w,h in [("panel_frame",32,32),("button_frame",32,24)]:
        im=blank(w,h);d=ink(im)
        d.rectangle((0,0,w-1,h-1),fill=C["void"],outline=C["gold_dark"],width=1)
        d.rectangle((2,2,w-3,h-3),outline=C["gold"],width=1)
        d.rectangle((4,4,w-5,h-5),outline=C["deep"])
        for x in [0,w-5]:
            d.rectangle((x,0,x+4,4),fill=C["gold_dark"],outline=C["gold_lit"])
            d.rectangle((x,h-5,x+4,h-1),fill=C["gold_dark"],outline=C["gold_lit"])
        for x,y in [(6,5),(w-7,5),(6,h-6),(w-7,h-6)]:
            d.point((x,y),fill=C["parch"])
        im.save(OUT/(stem+".png"))

def main_menu():
    # Illustrated castle backdrop at 640x360, scaled 2× crisp for the UI.
    rng=random.Random(691)
    im=Image.new("RGB",(640,360),C["void"]);d=ink(im)
    for y in range(360):
        shade=int(12+15*y/360)
        d.line((0,y,639,y),fill=(7+shade//3,12+shade//2,24+shade))
    # crescent moon, point stars
    d.ellipse((504,48,551,95),fill="#d9e9ce")
    d.ellipse((512,42,556,85),fill="#132535")
    for i in range(150):
        x=rng.randrange(640);y=rng.randrange(190)
        c=rng.choice(["#293e4d","#314754","#516172"])
        d.point((x,y),fill=c)
    for layer,col,level in [(0,"#142d30",242),(1,"#1b3834",280),(2,"#233e37",321)]:
        pts=[(-10,360),(-10,level)]
        for x in range(0,651,20):
            pts.append((x,level+rng.randint(-17,17)))
        pts.extend([(650,360)])
        d.polygon(pts,fill=col)
    # ruin towers and arched magical gate
    def tower(x,w,top):
        d.rectangle((x,top,x+w,310),fill="#263039",outline="#111b22")
        for cx in range(x-2,x+w+6,12):
            d.rectangle((cx,top-7,cx+7,top+1),fill="#34434a",outline="#111a21")
        for y in range(top+10,308,14):
            for j in range(x+(7 if y%28 else 0),x+w,19):
                d.line((j,y,j+7,y),fill="#52605b")
        d.rectangle((x+w//3,top+33,x+w//3+8,top+54),fill="#0c1b2c")
    tower(106,64,158);tower(475,60,150)
    d.rectangle((160,228,477,318),fill="#28373a",outline="#171c23",width=3)
    for x in range(167,469,27):d.line((x,230,x,318),fill="#3e4a4a")
    for y in range(239,319,19):d.line((159,y,478,y),fill="#1a272e")
    d.ellipse((275,198,365,302),fill="#171e2d",outline=C["gold_dark"],width=5)
    d.rectangle((275,246,365,310),fill="#171e2d")
    d.ellipse((290,215,350,292),fill="#225770")
    d.rectangle((291,253,349,308),fill="#225770")
    for i in range(150):
        x=rng.randint(292,347);y=rng.randint(223,306)
        if (x-320)**2/31**2+(y-262)**2/48**2<=1:
            d.point((x,y),fill=rng.choice(["#3a8fa0","#68bcc7","#22475c"]))
    for i in range(100):
        x=rng.randrange(640);y=rng.randrange(299,358)
        d.point((x,y),fill=rng.choice(["#557052","#344f44","#1f3232"]))
    # subtle warm lanterns
    for x,y in [(170,205),(469,205),(207,285),(434,286)]:
        d.rectangle((x-3,y-10,x+3,y+5),fill=C["gold_dark"])
        d.ellipse((x-4,y-8,x+4,y),fill=C["orange"])
        d.point((x,y-5),fill=C["parch"])
    im.resize((1280,720),Image.Resampling.NEAREST).save(OUT/"menu_background.png")


def props():
    """Eight 48×48 noninteractive environmental decoration sprites."""
    atlas=blank(8*48,48)
    names=["brazier","crystal","rubble","moss","torch","altar","fern","runestone"]
    for idx,name in enumerate(names):
        im=blank(48,48);d=ink(im)
        if name=="brazier":
            ell(d,[9,40,40,46],(0,0,0,100))
            poly(d,[(15,25),(32,25),(36,32),(32,39),(16,39),(12,32)],C["gold_dark"],C["outline"])
            rect(d,[17,29,30,31],C["gold"])
            for x in [17,30]:line(d,[(x,38),(x-2,44)],C["stone_mid"],3)
            poly(d,[(19,26),(17,16),(23,5),(26,17),(30,10),(33,23),(27,28)],C["fire"],C["outline"])
            poly(d,[(22,25),(22,17),(26,12),(28,25)],C["yellow"])
        elif name=="crystal":
            ell(d,[4,38,44,44],(0,0,0,95))
            for x,y,w,h in [(9,19,13,23),(23,5,16,35),(30,24,11,17)]:
                poly(d,[(x,y+h),(x-2,y+8),(x+w//2,y),(x+w+2,y+9),(x+w,y+h)],C["blue"],C["outline"])
                poly(d,[(x+w//2,y+2),(x+w,y+10),(x+w-2,y+h-2),(x+w//2,y+h)],C["cyan"])
                line(d,[(x+w//2,y+3),(x+3,y+10)],C["ice"])
        elif name=="rubble":
            for a in [(5,30,25,41),(20,20,39,39),(9,18,22,29),(28,33,42,43)]:
                rect(d,a,C["stone"],C["outline"])
                line(d,[(a[0]+2,a[1]+2),(a[2]-3,a[1]+2)],C["stone_hi"])
        elif name=="moss":
            for i,(x,y) in enumerate([(14,36),(22,30),(32,37),(12,26),(28,22)]):
                ell(d,[x-10,y-9,x+11,y+7],C["green_dark"],C["outline"])
                ell(d,[x-7,y-8,x+6,y+2],C["green"])
                rect(d,[x-1,y-6,x+1,y-4],C["green_hi"])
        elif name=="torch":
            rect(d,[21,21,27,46],C["brown_lit"],C["outline"])
            rect(d,[17,24,31,28],C["gold_dark"],C["gold"])
            poly(d,[(22,24),(18,16),(24,2),(28,17),(32,12),(29,26)],C["fire"],C["outline"])
            poly(d,[(24,19),(23,11),(27,7),(27,22)],C["yellow"])
        elif name=="altar":
            ell(d,[5,39,42,45],(0,0,0,90))
            rect(d,[7,27,41,39],C["stone"],C["outline"])
            rect(d,[11,23,37,27],C["gold_dark"],C["gold"])
            rect(d,[16,34,33,36],C["stone_hi"])
            poly(d,[(24,4),(35,17),(24,30),(13,17)],C["purple"],C["gold"])
            poly(d,[(24,9),(31,17),(24,25),(18,17)],C["cyan"],C["ice"])
        elif name=="fern":
            line(d,[(24,43),(23,13)],C["green_hi"],2)
            for y in [17,23,29,35]:
                poly(d,[(22,y),(6,y-10),(11,y+1),(23,y+6)],C["green"],C["green_dark"])
                poly(d,[(24,y),(40,y-11),(38,y+2),(24,y+5)],C["green_hi"],C["green_dark"])
        elif name=="runestone":
            ell(d,[8,40,39,45],(0,0,0,90))
            poly(d,[(14,42),(11,13),(20,4),(35,13),(37,41)],C["stone"],C["outline"])
            poly(d,[(19,13),(30,13),(33,34),(18,37)],C["stone_mid"],C["deep"])
            line(d,[(25,15),(23,29),(30,25)],C["cyan"],2)
            rect(d,[26,20,29,23],C["ice"])
        atlas.alpha_composite(im,(idx*48,0))
    atlas.save(OUT/"dungeon_props.png")
    (SOURCES/"props_manifest.json").write_text(json.dumps({"cell":[48,48],"columns":8,"names":names,"interactive":False},indent=2)+"\n")

def save():
    tileset();icons();effects();panel();main_menu();props()
    registry={}
    for kind in ["mage","pursuer","ranged","flanker","boss","dummy"]:
        frames=[("idle",i) for i in range(2)]+[("walk",i) for i in range(4)]+[("cast",i) for i in range(2)]+[("hurt",0),("dead",0)]
        size=(104,112) if kind=="boss" else (48,56)
        strip=blank(size[0]*len(frames),size[1])
        for i,(pose,index) in enumerate(frames): strip.alpha_composite(sprite(kind,pose,index),(size[0]*i,0))
        strip.save(OUT/(kind+"_sheet.png"))
        registry[kind]={"file":kind+"_sheet.png","frame":size,"frames":len(frames),
            "tags":{"idle":[0,1],"walk":[2,5],"cast":[6,7],"hurt":[8,8],"dead":[9,9]},
            "anchor":[size[0]//2,size[1]-7],"fps":9}
    (SOURCES/"sprites_manifest.json").write_text(json.dumps(registry,indent=2)+"\n")
    print("GENERATED",len(list(OUT.glob("*.png"))),"PNGS", " -> ", OUT)
if __name__=="__main__":save()
