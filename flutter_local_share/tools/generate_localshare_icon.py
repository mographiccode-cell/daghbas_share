from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path
import math
import sys

S = 1024
im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
p = im.load()
for y in range(S):
    for x in range(S):
        t = 0.60 * x / S + 0.40 * (1 - y / S)
        p[x, y] = (int(8 + 10 * t), int(65 + 135 * t), int(170 + 80 * t), 255)

mask = Image.new('L', (S, S), 0)
md = ImageDraw.Draw(mask)
md.rounded_rectangle((28, 28, S - 28, S - 28), radius=190, fill=255)
im.putalpha(mask)

glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse((390, -110, 1180, 690), fill=(0, 225, 255, 55))
glow = glow.filter(ImageFilter.GaussianBlur(95))
im = Image.alpha_composite(im, glow)
D = ImageDraw.Draw(im)

orbit = (205, 160, 819, 850)
D.arc(orbit, 205, 337, fill=(72, 240, 255, 200), width=15)
D.arc(orbit, 18, 155, fill=(102, 244, 255, 145), width=9)
for ang in [205, 337, 18, 155]:
    a = math.radians(ang)
    x = (orbit[0] + orbit[2]) / 2 + (orbit[2] - orbit[0]) / 2 * math.cos(a)
    y = (orbit[1] + orbit[3]) / 2 + (orbit[3] - orbit[1]) / 2 * math.sin(a)
    D.ellipse((x - 18, y - 18, x + 18, y + 18), fill='white')
for ang in range(155, 201, 8):
    a = math.radians(ang)
    x = 512 + 307 * math.cos(a)
    y = 505 + 345 * math.sin(a)
    D.rounded_rectangle((x - 8, y - 8, x + 8, y + 8), radius=5, fill=(61, 219, 255, 190))
for ang in range(340, 376, 8):
    a = math.radians(ang % 360)
    x = 512 + 307 * math.cos(a)
    y = 505 + 345 * math.sin(a)
    D.rounded_rectangle((x - 8, y - 8, x + 8, y + 8), radius=5, fill=(61, 219, 255, 190))

D.ellipse((92, 693, 572, 767), fill=(0, 25, 80, 65))
D.rounded_rectangle((112, 362, 510, 674), radius=25, fill=(17, 30, 66), outline=(148, 214, 255), width=8)
D.rounded_rectangle((133, 386, 489, 645), radius=10, fill=(18, 110, 245))
D.polygon([(135, 575), (250, 475), (330, 500), (440, 386), (489, 386), (489, 645), (133, 645)], fill=(15, 75, 218, 170))
D.pieslice((150, 430, 425, 745), 205, 336, fill=(30, 170, 250, 120))
D.pieslice((202, 492, 430, 720), 205, 336, fill=(20, 100, 238, 170))
D.polygon([(88, 674), (536, 674), (583, 718), (50, 718)], fill=(158, 201, 238), outline=(210, 237, 255))
D.rounded_rectangle((260, 687, 365, 703), radius=8, fill=(72, 124, 185))

D.ellipse((674, 690, 917, 756), fill=(0, 25, 80, 70))
D.rounded_rectangle((685, 340, 890, 700), radius=50, fill=(18, 30, 54), outline=(140, 207, 255), width=8)
D.rounded_rectangle((704, 360, 871, 678), radius=38, fill=(24, 224, 207))
D.pieslice((682, 450, 948, 735), 150, 310, fill=(20, 164, 222, 110))
D.ellipse((777, 370, 789, 382), fill=(10, 27, 48))

D.polygon([(458, 454), (565, 454), (605, 494), (605, 625), (458, 625)], fill=(250, 254, 255), outline=(218, 240, 255))
D.polygon([(565, 454), (565, 495), (605, 495)], fill=(216, 239, 255))
for yy, w in [(530, 80), (559, 84), (588, 58)]:
    D.rounded_rectangle((485, yy, 485 + w, yy + 12), radius=6, fill=(106, 194, 239))

a = Image.new('RGBA', (S, S), (0, 0, 0, 0))
ad = ImageDraw.Draw(a)
pts = [(340, 525), (395, 470), (470, 440), (565, 440), (565, 404), (650, 484)]
ad.line(pts, fill=(255, 255, 255, 245), width=74, joint='curve')
ad.line(pts, fill=(58, 234, 218, 255), width=57, joint='curve')
ad.polygon([(565, 404), (665, 484), (565, 563)], fill=(255, 255, 255, 245))
ad.polygon([(577, 426), (643, 484), (577, 541)], fill=(58, 234, 218, 255))
pts2 = [(674, 592), (615, 646), (540, 675), (445, 675), (445, 713), (356, 630)]
ad.line(pts2, fill=(255, 255, 255, 245), width=74, joint='curve')
ad.line(pts2, fill=(48, 219, 235, 255), width=57, joint='curve')
ad.polygon([(445, 713), (343, 630), (445, 548)], fill=(255, 255, 255, 245))
ad.polygon([(433, 690), (367, 630), (433, 571)], fill=(48, 219, 235, 255))
g = a.filter(ImageFilter.GaussianBlur(12))
g.putalpha(g.getchannel('A').point(lambda v: int(v * 0.28)))
im = Image.alpha_composite(im, g)
im = Image.alpha_composite(im, a)

out = Path(sys.argv[1] if len(sys.argv) > 1 else 'localshare_icon.png')
im = im.resize((512, 512), Image.Resampling.LANCZOS)
im.save(out, optimize=True)
print(out, im.size)
