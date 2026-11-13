import bpy, sys
from PIL import Image, ImageDraw
A=sys.argv[sys.argv.index('--')+1:]; f=A[0]; out=A[1]; clips=A[2].split(',')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=f)
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
W=160;H=200
img=Image.new('RGB',(W*6,H*2*len(clips)),'black'); d=ImageDraw.Draw(img)
for ci,c in enumerate(clips):
    act=bpy.data.actions.get(c) or [a for a in bpy.data.actions if a.name.startswith(c)][0]
    arm.animation_data.action=act
    fr=act.frame_range
    for k in range(6):
        t=fr[0]+(fr[1]-fr[0])*k/5.0
        bpy.context.scene.frame_set(int(t))
        for row,(ax) in enumerate([(0,2),(1,2)]):
            ox=k*W+W/2; oy=(ci*2+row)*H+H-10
            for pb in arm.pose.bones:
                if pb.parent:
                    a=arm.matrix_world@pb.parent.head; b=arm.matrix_world@pb.head
                    col=(255,80,80) if 'L' in pb.name.replace('Left','L')[:6] and ('Left' in pb.name or '.L' in pb.name or pb.name.startswith('L_')) else (200,200,255)
                    d.line([(ox+a[ax[0]]*80,oy-a[ax[1]]*80),(ox+b[ax[0]]*80,oy-b[ax[1]]*80)],fill=col,width=2)
            d.text((k*W+3,(ci*2+row)*H+3),c+(' F' if row==0 else ' S'),fill='yellow')
img.save(out)
