from PIL import Image
import json, os, sys, glob
k,fd=sys.argv[1],sys.argv[2]
OLD=[('idle',9),('walk',14),('punch',11),('kick',10),('throw',11),('windup',7)]
NEW=[(n,len(glob.glob(f'{fd}/{n}_*.png'))) for n in ['hit','knock','getup','block','upper','taunt','hiphop','headspin','flair','spinback','sweep','armada','meialua','spinflip']]
NEW=[x for x in NEW if x[1]]
CW=440
fr=[]
for n,c in OLD+NEW:
    for i in range(c):
        im=Image.open(f'{fd}/{n}_{i:02d}.png')
        if im.width==340: p=Image.new('RGBA',(CW,232)); p.paste(im,(50,0)); im=p
        fr.append(im)
bb=None
for im in fr:
    b=im.getbbox()
    if b: bb=b if bb is None else (min(bb[0],b[0]),min(bb[1],b[1]),max(bb[2],b[2]),max(bb[3],b[3]))
x0,y0,x1,y1=bb; x0=max(0,x0-2);y0=max(0,y0-2);x1=min(CW,x1+2);y1=232
w,h=x1-x0,y1-y0; cols=16; rows=(len(fr)+cols-1)//cols
S=Image.new('RGBA',(cols*w,rows*h)); meta={'w':w,'h':h,'cols':cols,'clips':{}}; idx=0
for n,c in OLD+NEW: meta['clips'][n]=[idx,c]; idx+=c
for i,im in enumerate(fr): S.paste(im.crop((x0,y0,x1,y1)),((i%cols)*w,(i//cols)*h))
meta['groundY']=round(125/130*232-y0,1); meta['anchorX']=220-x0; meta['bodyH']=round(112/130*232,1)
S.quantize(colors=256,method=Image.FASTOCTREE,dither=Image.NONE).save(f'sheet2_{k}.png',optimize=True)
json.dump(meta,open(f'sheet2_{k}.json','w')); print(k,bb,w,h,S.size,len(fr),os.path.getsize(f'sheet2_{k}.png'))
