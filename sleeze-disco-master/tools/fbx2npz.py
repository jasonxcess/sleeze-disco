import gc; gc.disable()
import ufbx, numpy as np, sys, os
f,out=sys.argv[1],sys.argv[2]
s=ufbx.load_file(f); st=s.anim_stacks
x=st[len(st)-1]; t0=x.time_begin; t1=x.time_end; a=x.anim
ns=list(s.nodes); nn=[q.name for q in ns]
def M(m):
    R=np.eye(4)
    for j,c in enumerate([m.c0,m.c1,m.c2,m.c3]): R[:3,j]=[c.x,c.y,c.z]
    return R
rest=np.stack([M(q.node_to_world) for q in ns])
n=int(round((t1-t0)*30))+1; fr=[]
for k in range(n):
    e=ufbx.evaluate_scene(s,a,t0+k/30.0)
    d={q.name:M(q.node_to_world) for q in e.nodes}
    fr.append(np.stack([d[q] for q in nn]))
np.savez(out,names=np.array(nn),rest=rest,frames=np.stack(fr))
print(os.path.basename(f),n,flush=True); os._exit(0)
