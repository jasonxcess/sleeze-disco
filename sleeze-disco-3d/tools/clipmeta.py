import bpy, sys, json
A=sys.argv[sys.argv.index('--')+1:]; f=A[0]; char=A[1]; out=A[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=f)
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
names={'player':dict(hip='Hips',lf='LeftFoot',rf='RightFoot',lh='LeftHand',rh='RightHand'),
 'thug':dict(hip='hips',lf='L_ankle',rf='R_ankle',lh='L_wrist',rh='R_wrist'),
 'crowd':dict(hip='hips',lf='L_ankle',rf='R_ankle',lh='L_wrist',rh='R_wrist'),
 'vex':dict(hip='root_hips',lf='foot.L',rf='foot.R',lh='hand.L',rh='hand.R')}[char]
fps=30.0
res={}
sc=bpy.context.scene
for act in bpy.data.actions:
    arm.animation_data.action=act
    a,b=int(act.frame_range[0]),int(act.frame_range[1])
    P=[]
    for fr in range(a,b+1):
        sc.frame_set(fr)
        P.append({k:(arm.matrix_world@arm.pose.bones[v].head).copy() for k,v in names.items()})
    name=act.name.rsplit('_'+char+'_rig',1)[0]
    ent={'len':(b-a)/fps}
    if name in ('walk','run','sprint'):
        vs=[]
        for k in ('lf','rf'):
            zs=[p[k].z for p in P]; zmin=min(zs)
            for i in range(1,len(P)):
                if P[i][k].z < zmin+0.03 and P[i-1][k].z < zmin+0.03:
                    vs.append(abs(P[i][k].y-P[i-1][k].y)*fps)
        vs.sort(); ent['speed']=vs[len(vs)//2] if vs else 0
    else:
        best=None
        for k in ('lh','rh','lf','rf'):
            reach=[-(p[k].y-p['hip'].y) for p in P]  # forward = -Y
            m=max(reach); i=reach.index(m)
            if best is None or m>best[0]: best=(m,i,k,reach)
        m,i,k,reach=best
        s=i
        while s>0 and reach[s-1]>=0.8*m: s-=1
        e=i
        while e<len(reach)-1 and reach[e+1]>=0.8*m: e+=1
        ent.update(limb=k,contact=i/fps,active=[s/fps,(e+1)/fps],reach=round(m,3))
    res[name]=ent
json.dump(res,open(out,'w'),indent=1)
print(json.dumps(res))
