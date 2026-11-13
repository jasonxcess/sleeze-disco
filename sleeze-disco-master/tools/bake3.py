import gc; gc.disable()
import psx
"""Bake Mixamo clips onto a rig. usage: bake3.py <rig> <clip>... ; clip specs in MIX below."""
import sys,os,glob,numpy as np
from rig import *
from rt_test import load_mix, TGT
from PIL import Image
D='mixnpz/'
MIX={ # name: (npz, n_out, start_frac, end_frac)
 'hit':('Head_Hit.npz',8,0,0.75),'knock':('Knocked_Down.npz',12,0,1),'getup':('Getting_Up.npz',16,0,1),
 'block':('Center_Block.npz',6,0,0.5),'upper':('Uppercut.npz',10,0,1),'taunt':('Taunt.npz',10,0,1),
 'hiphop':('Hip_Hop_Dancing.npz',24,0,1),'headspin':('Head_Spinning.npz',8,0,0.97),'flair':('Flair_(1).npz',10,0,0.97),
 'spinback':('Kicking.npz',14,0,1),'sweep':('Leg_Sweep.npz',12,0,1),'armada':('Armada.npz',12,0,1),'meialua':('Meia_Lua_De_Compasso.npz',12,0,1),'spinflip':('Spin_Flip_Kick.npz',12,0,1)}
k=sys.argv[1]; names=sys.argv[2:]
CW,CH,SS=440,232,2
os.makedirs(f'frames_{k}',exist_ok=True)
for name in names:
    g,n,a,b=MIX[name]; tg,ms,rt=load_mix(k,D+g); th=TGT[k][3]
    P0=tg.pose(None,0,G=tg.globals({},0))[0]; Hm=P0[:,1].max()-P0[:,1].min(); fl=P0[:,1].min(); u=Hm/112.0
    UW,U0,U1=95.2*u*CW/340,fl-5*u,fl+125*u
    G0=rt.globals(None,0); v=G0[th[1]][:3,3]-G0[th[2]][:3,3]; yaw=-np.arctan2(v[2],v[0])+np.radians(30); vw=view_yaw(yaw)
    N=ms.nframes; ts=np.linspace(a*(N-1),b*(N-1),n)
    for i,t in enumerate(ts):
        G=rt.globals(None,float(t)); P,Nn,F,UV,MAT,_=tg.pose(None,0,G=G)
        hip=G[th[0]][:3,3]; hx=vw(hip[None],np.zeros((1,3)))[0][0]
        img=raster(tg,P,Nn,F,UV,MAT,(CH*SS,CW*SS),vw,(hx-UW,hx+UW,U0,U1),amb=0.45)
        Image.fromarray((img*255).astype('uint8'),'RGBA').resize((CW,CH),Image.LANCZOS).transpose(Image.FLIP_LEFT_RIGHT).save(f'frames_{k}/{name}_{i:02d}.png')
    print(k,name,n,flush=True)
os._exit(0)
