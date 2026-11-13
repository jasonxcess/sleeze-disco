import numpy as np, sys
import os
from rig import *
from retarget import Retarget
from PIL import Image
GANG='watch-this-shadow-gangster-2013c587bbda/source/BLURY GANGSTER.fbx'
src=Model(GANG,'watch-this-shadow-gangster-2013c587bbda/textures')
E1=[('spine','chest','spineA'),('chest','neck','chest'),('neck','head','neck')]
for S in 'LR': E1+=[(f'{S}_shoulder',f'{S}_arm',f'{S}clav'),(f'{S}_arm',f'{S}_elbow',f'{S}upper'),(f'{S}_elbow',f'{S}_wrist',f'{S}fore'),(f'{S}_wrist',f'{S}_middle1',f'{S}hand'),(f'{S}_leg',f'{S}_knee',f'{S}thigh'),(f'{S}_knee',f'{S}_ankle',f'{S}calf'),(f'{S}_ankle',f'{S}_toes',f'{S}foot')]
RD=[('Bip001 Spine','Bip001 Spine2','spineA'),('Bip001 Spine1','Bip001 Spine2','spineA'),('Bip001 Spine2','Bip001 Spine3','chest'),('Bip001 Spine3','Bip001 Spine4','chest'),('Bip001 Spine4','Bip001 Neck','chest'),('Bip001 Neck','Bip001 Neck1','neck'),('Bip001 Neck1','Bip001 Head','neck')]
for S in 'LR': RD+=[(f'Bip001 {S} Clavicle',f'Bip001 {S} UpperArm',f'{S}clav'),(f'Bip001 {S} UpperArm',f'Bip001 {S} Forearm',f'{S}upper'),(f'Bip001 {S} Forearm',f'Bip001 {S} Hand',f'{S}fore'),(f'Bip001 {S} Hand',f'Bip001 {S} Finger2',f'{S}hand'),(f'Bip001 {S} Thigh',f'Bip001 {S} Calf',f'{S}thigh'),(f'Bip001 {S} Calf',f'Bip001 {S} Foot',f'{S}calf'),(f'Bip001 {S} Foot',f'Bip001 {S} Toe0',f'{S}foot')]
TGT={'e1':('enemy1-ff6af2a6f63d/source/enemy1.fbx','enemy1-ff6af2a6f63d/textures',E1,('hips','L_leg','R_leg','chest')),
     'rd':('raised-dead-2504446f7695/source/Raised dead Avatar Copy.fbx','raised-dead-2504446f7695/textures',RD,('Bip001 Pelvis','Bip001 L Thigh','Bip001 R Thigh','Bip001 Spine2'))}
def load(k):
    p,t,mp,hp=TGT[k]; tg=Model(p,t); return tg, Retarget(src,0,'node|0_T-Pose',tg,mp,hp)
if __name__=='__main__':
    k=sys.argv[1]; tg,rt=load(k)
    ch=src.chans(src.anims['node|Strike_-_martial_arts_sequence_1'])
    tiles=[]
    for t in [0,232,428,276]:
        Gs=src.globals(ch,t); v=Gs['CC_Base_L_Thigh'][:3,3]-Gs['CC_Base_R_Thigh'][:3,3]; yaw=-np.arctan2(v[2],v[0])+np.radians(30)
        for mdl,G in [(src,Gs),(tg,rt.globals(ch,t))]:
            P,N,F,UV,MAT,_=mdl.pose(None,0,G=G)
            vw=view_yaw(yaw); X,Y,*_=vw(P,N); cx=(X.min()+X.max())/2; h=Y.max()-Y.min(); y0=Y.min()
            img=raster(mdl,P,N,F,UV,MAT,(200,150),vw,(cx-h*0.4,cx+h*0.4,y0-h*0.05,y0+h*1.02))
            tiles.append(Image.fromarray((img*255).astype('uint8'),'RGBA').transpose(Image.FLIP_LEFT_RIGHT))
    S=Image.new('RGBA',(150*8,200),(60,60,75,255))
    for i,tl in enumerate(tiles): S.alpha_composite(tl,(i*150,0))
    S.save(f'rt_{k}.png')
GG=[('CC_Base_Waist','CC_Base_Spine02','spineA'),('CC_Base_Spine02','CC_Base_NeckTwist01','chest'),('CC_Base_NeckTwist01','CC_Base_Head','neck')]
for S in 'LR': GG+=[(f'CC_Base_{S}_Clavicle',f'CC_Base_{S}_Upperarm',f'{S}clav'),(f'CC_Base_{S}_Upperarm',f'CC_Base_{S}_Forearm',f'{S}upper'),(f'CC_Base_{S}_Forearm',f'CC_Base_{S}_Hand',f'{S}fore'),(f'CC_Base_{S}_Hand',f'CC_Base_{S}_Mid1',f'{S}hand'),(f'CC_Base_{S}_Thigh',f'CC_Base_{S}_Calf',f'{S}thigh'),(f'CC_Base_{S}_Calf',f'CC_Base_{S}_Foot',f'{S}calf'),(f'CC_Base_{S}_Foot',f'CC_Base_{S}_ToeBase',f'{S}foot')]
TGT['gang']=(GANG,'watch-this-shadow-gangster-2013c587bbda/textures',GG,('CC_Base_Hip','CC_Base_L_Thigh','CC_Base_R_Thigh','CC_Base_Spine02'))
def load_mix(k, srcpath):
    from mixsrc import mixamo_roles
    from ufsrc import UfbxSrc
    p,t,mp,hp=TGT[k]; tg=src if k=='gang' else Model(p,t)
    ms=UfbxSrc(srcpath); roles,hip,feet=mixamo_roles()
    return tg, ms, Retarget(ms,0,None,tg,mp,hp,roles,hip,feet,floor='rest')
