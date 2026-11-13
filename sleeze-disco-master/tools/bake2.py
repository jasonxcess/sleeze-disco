import gc; gc.disable()
import psx
import numpy as np, sys, os
from rig import *
from rt_test import src, load
from PIL import Image
k=sys.argv[1]; tg,rt=load(k)
ch=src.chans(src.anims['node|Strike_-_martial_arts_sequence_1'])
CLIPS={'idle':(0,24,3),'walk':(28,80,4),'punch':(224,244,2),'kick':(416,434,2),'throw':(264,284,2),'windup':(252,264,2)}
P0=tg.pose(None,0,G=tg.globals({},0))[0]; Hm=P0[:,1].max()-P0[:,1].min(); fl=P0[:,1].min()
u=Hm/112.0
SS=2; CW,CH=340,232; UW,U0,U1=95.2*u,fl-5*u,fl+125*u
def facing(G):
    v=G['CC_Base_L_Thigh'][:3,3]-G['CC_Base_R_Thigh'][:3,3]; return np.arctan2(v[2],v[0])
OFF=np.radians(30)
os.makedirs(f'frames_{k}',exist_ok=True)
for name,(a,b,st) in CLIPS.items():
    ts=list(range(a,b+1,st)); Gs=[src.globals(ch,t) for t in ts]
    yaw=(-facing(Gs[0]) if name=='kick' else -np.mean([facing(G) for G in Gs]))+OFF
    vw=view_yaw(yaw)
    for i,t in enumerate(ts):
        P,N,F,UV,MAT,_=tg.pose(None,0,G=rt.globals(ch,t))
        X=vw(P,N)[0]
        if name in ('walk','throw') or i==0:
            low=P[:,1]<np.percentile(P[:,1],3); ax=X[low].mean()
            if i==0: ax0=ax
        anc=ax if name in ('walk','throw') else ax0
        img=raster(tg,P,N,F,UV,MAT,(CH*SS,CW*SS),vw,(anc-UW,anc+UW,U0,U1),amb=0.45)
        Image.fromarray((img*255).astype('uint8'),'RGBA').resize((CW,CH),Image.LANCZOS).transpose(Image.FLIP_LEFT_RIGHT).save(f'frames_{k}/{name}_{i:02d}.png')
    print(k,name,len(ts),flush=True)
os._exit(0)
