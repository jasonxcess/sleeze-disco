"""PSX characters Shawn uploaded (Nov 12, 2026): psxm = PSXprop Male Character 02 (Mixamo rig FBX),
psxw = PSX Low Poly Woman (murilo.kleine, .blend only -> parsed with blender_asset_tracer)."""
import numpy as np, pathlib
from PIL import Image
from rig import Model
import rt_test

C = np.array([[1, 0, 0, 0], [0, 0, 1, 0], [0, -1, 0, 0], [0, 0, 0, 1]], float)  # z-up -> y-up

def m4(v): return np.array(v, float).reshape(4, 4).T

class BlendModel(Model):
    def __init__(self, path, tex):
        from blender_asset_tracer import blendfile
        bf = blendfile.open_cached(pathlib.Path(path))
        obs = {b.id_name: b for b in bf.blocks if b.code == b'OB'}
        arm_ob = obs[b'OBArmature']; mesh_ob = obs[b'OBCylinder']
        A = C @ m4(arm_ob.get(b'obmat'))
        self.nodes = {'ARM': (None, A)}; self.order = ['ARM']; amat = {}
        ar = [b for b in bf.blocks if b.code == b'AR'][0]
        def walk(bone, parent):
            while bone:
                n = bone.get(b'name').decode(); M = m4(bone.get(b'arm_mat')); amat[n] = M
                L = M if parent is None else np.linalg.inv(amat[parent]) @ M
                self.nodes[n] = ('ARM' if parent is None else parent, L); self.order.append(n)
                ch = bone.get_pointer((b'childbase', b'first'))
                if ch is None:  # leaf: add a tail node along bone Y
                    T = np.eye(4); T[1, 3] = bone.get(b'length'); self.nodes[n+'_tail'] = (n, T); self.order.append(n+'_tail')
                walk(ch, n)
                bone = bone.get_pointer(b'next')
        walk(ar.get_pointer((b'bonebase', b'first')), None)
        me = [b for b in bf.blocks if b.code == b'ME'][0]
        nv = me.get(b'totvert'); npo = me.get(b'totpoly'); nl = me.get(b'totloop')
        mv = me.get_pointer(b'mvert'); mp = me.get_pointer(b'mpoly'); ml = me.get_pointer(b'mloop'); mu = me.get_pointer(b'mloopuv'); dv = me.get_pointer(b'dvert')
        Vloc = np.array([mv.get(b'co', array_index=i) for i in range(nv)], float)
        Vw = (np.c_[Vloc, np.ones(nv)] @ (C @ m4(mesh_ob.get(b'obmat'))).T)[:, :3]
        lv = np.array([ml.get(b'v', array_index=i) for i in range(nl)])
        UV = np.array([mu.get(b'uv', array_index=i) for i in range(nl)], float)
        F = []
        for i in range(npo):
            s, n = mp.get(b'loopstart', array_index=i), mp.get(b'totloop', array_index=i)
            for k in range(1, n-1): F.append([s, s+k, s+k+1])
        F = np.array(F)
        names = []; dg = mesh_ob.get_pointer((b'defbase', b'first'))
        while dg: names.append(dg.get(b'name').decode()); dg = dg.get_pointer(b'next')
        Wv = np.zeros((nv, 4)); Iv = np.zeros((nv, 4), int)
        for vi in range(nv):
            tw = dv.get(b'totweight', array_index=vi); ad = dv.get(b'dw', array_index=vi)
            if not tw or not ad: continue
            blk = bf.dereference_pointer(ad)
            ws = sorted([(blk.get(b'weight', array_index=j), blk.get(b'def_nr', array_index=j)) for j in range(tw)], reverse=True)[:4]
            for k, (w, g) in enumerate(ws): Wv[vi, k] = w; Iv[vi, k] = g
        Wv /= np.maximum(Wv.sum(1, keepdims=True), 1e-9)
        bones = [(n, np.linalg.inv(A @ amat[n])) for n in names]
        V = Vw[lv]
        fn = np.cross(V[F[:, 1]]-V[F[:, 0]], V[F[:, 2]]-V[F[:, 0]])
        acc = np.zeros_like(Vw)
        for c in range(3): np.add.at(acc, lv[F[:, c]], fn)
        self.parts = [dict(V=V, N=acc[lv], F=F, UV=UV, mat=0, bones=bones, W=Wv[lv], I=Iv[lv], skinned=True, owner=None)]
        im = Image.open(tex).convert('RGBA'); im.thumbnail((1024, 1024))
        self.texs = [np.asarray(im, float)/255.0]; self.anims = {}

def P(n): return 'mixamorig:'+n
PM = [(P('Spine'), P('Spine1'), 'spineA'), (P('Spine1'), P('Spine2'), 'spineA'), (P('Spine2'), P('Neck'), 'chest'), (P('Neck'), P('Head'), 'neck')]
for S, s in [('L', 'Left'), ('R', 'Right')]:
    PM += [(P(s+'Shoulder'), P(s+'Arm'), f'{S}clav'), (P(s+'Arm'), P(s+'ForeArm'), f'{S}upper'), (P(s+'ForeArm'), P(s+'Hand'), f'{S}fore'),
           (P(s+'UpLeg'), P(s+'Leg'), f'{S}thigh'), (P(s+'Leg'), P(s+'Foot'), f'{S}calf'), (P(s+'Foot'), P(s+'ToeBase'), f'{S}foot')]
PW = [('spine.001', 'spine.002', 'spineA'), ('spine.002', 'spine.003', 'spineA'), ('spine.003', 'neck', 'chest'), ('neck', 'head', 'neck')]
for S in 'LR':
    PW += [(f'shoulder.{S}', f'arm.{S}', f'{S}clav'), (f'arm.{S}', f'forearm.{S}', f'{S}upper'), (f'forearm.{S}', f'hand.{S}', f'{S}fore'),
           (f'thighs.{S}', f'leg.{S}', f'{S}thigh'), (f'leg.{S}', f'foot.{S}', f'{S}calf'), (f'foot.{S}', f'foot.{S}_tail', f'{S}foot'), (f'hand.{S}', f'hand.{S}_tail', f'{S}hand')]
rt_test.TGT['psxm'] = ('psxm/source/Walking.fbx', 'psxm/textures', PM, (P('Hips'), P('LeftUpLeg'), P('RightUpLeg'), P('Spine2')))
rt_test.TGT['psxw'] = ('psxw/source/WOMAN 128 FINAL.blend', 'psxw/textures/WOMAN_2048.jpg', PW, ('spine.001', 'thighs.L', 'thighs.R', 'spine.003'))

_orig_model = rt_test.Model
def _model(p, t):
    return BlendModel(p, t) if p.endswith('.blend') else _orig_model(p, t)
rt_test.Model = _model
