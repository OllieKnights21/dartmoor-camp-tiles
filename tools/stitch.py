import sys, os, glob
from PIL import Image
T, z = sys.argv[1], sys.argv[2]; out=sys.argv[3]
xs=sorted(int(x) for x in os.listdir(f"{T}/{z}")); ys=set()
for x in xs: ys|={int(f[:-4]) for f in os.listdir(f"{T}/{z}/{x}")}
ys=sorted(ys); x0,y0=xs[0],ys[0]
im=Image.new("RGB",((xs[-1]-x0+1)*256,(ys[-1]-y0+1)*256),(40,0,40))
for x in xs:
    for f in os.listdir(f"{T}/{z}/{x}"):
        im.paste(Image.open(f"{T}/{z}/{x}/{f}").convert("RGB"),((x-x0)*256,(int(f[:-4])-y0)*256))
if len(sys.argv)>4: c=[int(v) for v in sys.argv[4].split(',')]; im=im.crop(c)
im.save(out); print(im.size)
