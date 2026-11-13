"""General rigged-FBX -> sprite renderer (numpy, CPU). Multi-mesh, multi-texture,
skinned or rigid (node-attached) meshes."""
import assimp_py as a, numpy as np, os, re
from PIL import Image

def _qmat(q):
    x, y, z, w = q
    n = np.sqrt(w*w+x*x+y*y+z*z) or 1; w, x, y, z = w/n, x/n, y/n, z/n
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])

def _slerp(q0, q1, t):
    d = np.dot(q0, q1)
    if d < 0: q1 = -q1; d = -d
    if d > 0.9995: q = q0+t*(q1-q0); return q/np.linalg.norm(q)
    th = np.arccos(d); return (np.sin((1-t)*th)*q0+np.sin(t*th)*q1)/np.sin(th)

def _sample(times, vals, t, rot=False):
    if len(times) == 1 or t <= times[0]: return vals[0]
    if t >= times[-1]: return vals[-1]
    i = np.searchsorted(times, t)-1; f = (t-times[i])/(times[i+1]-times[i])
    return _slerp(vals[i], vals[i+1], f) if rot else vals[i]+(vals[i+1]-vals[i])*f

class Model:
    def __init__(self, path, texdir, texmap=None, tint=None):
        try: s = a.import_file(path, a.Process_Triangulate | a.Process_LimitBoneWeights | a.Process_GenSmoothNormals)
        except RuntimeError: s = a.import_file(path, 0)
        self.s = s
        self.nodes = {}; self.mesh_owner = {}
        def walk(n, parent):
            self.nodes[n.name] = (parent, np.array(n.transformation, dtype=np.float64))
            for mi in (n.mesh_indices or []): self.mesh_owner[mi] = n.name
            for c in n.children: walk(c, n.name)
        walk(s.root_node, None); self.order = list(self.nodes)
        self.texs = []
        texfiles = {os.path.basename(f).lower(): os.path.join(texdir, f) for f in os.listdir(texdir)} if os.path.isdir(texdir) else {}
        for mi, mt in enumerate(s.materials):
            t = None
            name = (texmap or {}).get(mt.get('NAME'))
            if name is None:
                tl = (mt.get('TEXTURES') or {}).get(1)
                if tl:
                    b = re.split(r'[\\/]', tl[0])[-1].lower()
                    name = texfiles.get(b)
                    if name is None:  # fuzzy: longest common key
                        stem = os.path.splitext(b)[0]
                        best = max(texfiles, key=lambda k: sum(1 for w in re.findall('[a-z]+', stem) if w in k), default=None)
                        name = texfiles[best] if best else None
            if name:
                im = Image.open(name).convert('RGBA'); im.thumbnail((1024, 1024))
                t = np.asarray(im, dtype=np.float64)/255.0
            else:
                c = mt.get('COLOR_DIFFUSE') or [0.6, 0.6, 0.6]
                t = np.ones((2, 2, 4)); t[..., :3] = c[:3]
            self.texs.append(t)
        self.parts = []
        for mi, m in enumerate(s.meshes):
            V = np.array(m.vertices, dtype=np.float64).reshape(-1, 3)
            N = np.array(m.normals, dtype=np.float64).reshape(-1, 3)
            F = np.array(m.indices).reshape(-1, 3)
            if m.texcoords:
                uv = np.array(m.texcoords[0], dtype=np.float64); UV = uv.reshape(len(V), -1)[:, :2]
            else: UV = np.zeros((len(V), 2))
            bones = []; W = np.zeros((len(V), 4)); I = np.zeros((len(V), 4), dtype=int); cnt = np.zeros(len(V), dtype=int)
            for bi, b in enumerate(m.bones or []):
                bones.append((b.name, np.array(b.offset_matrix, dtype=np.float64)))
                if b.num_weights:
                    for vid, w in zip(np.array(b.weight_vertex_ids), np.array(b.weights)):
                        k = cnt[vid]
                        if k < 4: W[vid, k] = w; I[vid, k] = bi; cnt[vid] += 1
            skinned = bool(bones) and W.sum() > 0
            if skinned: W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
            self.parts.append(dict(V=V, N=N, F=F, UV=UV, mat=m.material_index, bones=bones, W=W, I=I, skinned=skinned, owner=self.mesh_owner.get(mi)))
        self.anims = {an.name: an for an in s.animations}

    def chans(self, anim):
        out = {}
        if anim is None: return out
        for c in anim.channels:
            out[c.node_name] = (np.array(c.position_key_times), np.array(c.position_key_values).reshape(-1, 3),
                                np.array(c.rotation_key_times), np.array(c.rotation_key_values).reshape(-1, 4),
                                np.array(c.scaling_key_times), np.array(c.scaling_key_values).reshape(-1, 3))
        return out

    def globals(self, ch, t, override=None):
        G = {}
        for name in self.order:
            parent, L = self.nodes[name]
            if override and name in override: L = override[name]
            elif name in ch:
                pt, pv, rt, rv, st, sv = ch[name]
                L = np.eye(4); L[:3, :3] = _qmat(_sample(rt, rv, t, True))*_sample(st, sv, t); L[:3, 3] = _sample(pt, pv, t)
            G[name] = L if parent is None else G[parent] @ L
        return G

    def pose(self, ch, t, override=None, G=None):
        if G is None: G = self.globals(ch, t, override)
        Ps, Ns, Fs, UVs, Ms = [], [], [], [], []; off = 0
        for p in self.parts:
            V, N = p['V'], p['N']; Vh = np.c_[V, np.ones(len(V))]
            if p['skinned']:
                M = np.stack([G[n] @ o for n, o in p['bones']])
                P = np.zeros((len(V), 3)); NN = np.zeros((len(V), 3))
                for k in range(4):
                    Mk = M[p['I'][:, k]]; w = p['W'][:, k:k+1]
                    P += w*np.einsum('nij,nj->ni', Mk, Vh)[:, :3]; NN += w*np.einsum('nij,nj->ni', Mk[:, :3, :3], N)
            else:
                M = G.get(p['owner'], np.eye(4)); P = (Vh @ M.T)[:, :3]; NN = N @ M[:3, :3].T
            NN /= np.maximum(np.linalg.norm(NN, axis=1, keepdims=True), 1e-9)
            Ps.append(P); Ns.append(NN); Fs.append(p['F']+off); UVs.append(p['UV']); Ms.append(np.full(len(p['F']), p['mat'])); off += len(V)
        return np.vstack(Ps), np.vstack(Ns), np.vstack(Fs), np.vstack(UVs), np.concatenate(Ms), G

def view_yaw(yaw, up='y'):
    c, sn = np.cos(yaw), np.sin(yaw)
    def v(P, N):
        if up == 'z':  # z-up -> y-up
            P = P[:, [0, 2, 1]] * np.array([1, 1, -1]); N = N[:, [0, 2, 1]] * np.array([1, 1, -1])
        return (P[:, 0]*c-P[:, 2]*sn, P[:, 1], P[:, 0]*sn+P[:, 2]*c, N[:, 0]*c-N[:, 2]*sn, N[:, 1], N[:, 0]*sn+N[:, 2]*c)
    return v

def raster(model, P, Nn, F, UV, MAT, size, view, bounds, rim=(0.9, 0.85, 1.0), amb=0.35, alpha_cut=0.4):
    Hpx, Wpx = size
    X, Y, Z, NX, NY, NZ = view(P, Nn)
    x0, x1, y0, y1 = bounds
    sx = (X-x0)/(x1-x0)*Wpx; sy = (y1-Y)/(y1-y0)*Hpx
    img = np.zeros((Hpx, Wpx, 4)); zb = np.full((Hpx, Wpx), -1e18)
    L = np.array([-0.4, 0.6, 0.7]); L /= np.linalg.norm(L)
    for fi, f in enumerate(F):
        tex = model.texs[MAT[fi]]; TH, TW = tex.shape[:2]
        xs, ys, zs = sx[f], sy[f], Z[f]
        mnx, mxx = int(max(0, np.floor(xs.min()))), int(min(Wpx-1, np.ceil(xs.max())))
        mny, mxy = int(max(0, np.floor(ys.min()))), int(min(Hpx-1, np.ceil(ys.max())))
        if mnx > mxx or mny > mxy: continue
        gx, gy = np.meshgrid(np.arange(mnx, mxx+1)+0.5, np.arange(mny, mxy+1)+0.5)
        d = (ys[1]-ys[2])*(xs[0]-xs[2])+(xs[2]-xs[1])*(ys[0]-ys[2])
        if abs(d) < 1e-12: continue
        w0 = ((ys[1]-ys[2])*(gx-xs[2])+(xs[2]-xs[1])*(gy-ys[2]))/d
        w1 = ((ys[2]-ys[0])*(gx-xs[2])+(xs[0]-xs[2])*(gy-ys[2]))/d
        w2 = 1-w0-w1
        ins = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not ins.any(): continue
        z = w0*zs[0]+w1*zs[1]+w2*zs[2]
        sub = zb[mny:mxy+1, mnx:mxx+1]; ok = ins & (z > sub)
        if not ok.any(): continue
        u = w0*UV[f[0], 0]+w1*UV[f[1], 0]+w2*UV[f[2], 0]; v = w0*UV[f[0], 1]+w1*UV[f[1], 1]+w2*UV[f[2], 1]
        tx = np.clip((u % 1)*TW, 0, TW-1).astype(int); ty = np.clip((1-(v % 1))*TH, 0, TH-1).astype(int)
        col = tex[ty, tx]
        ok = ok & (col[..., 3] > alpha_cut)
        if not ok.any(): continue
        nx = w0*NX[f[0]]+w1*NX[f[1]]+w2*NX[f[2]]; ny = w0*NY[f[0]]+w1*NY[f[1]]+w2*NY[f[2]]; nz = w0*NZ[f[0]]+w1*NZ[f[1]]+w2*NZ[f[2]]
        nl = np.sqrt(nx*nx+ny*ny+nz*nz)+1e-9; nx, ny, nz = nx/nl, ny/nl, nz/nl
        if np.mean(nz[ok]) < 0: nx, ny, nz = -nx, -ny, -nz  # two-sided
        diff = np.clip(nx*L[0]+ny*L[1]+nz*L[2], 0, 1)
        rimv = np.clip(1-np.abs(nz), 0, 1)**3*np.clip(-nx*0.7+ny*0.3+0.3, 0, 1)
        shade = col[..., :3]*(amb+0.85*diff)[..., None]+np.array(rim)[None, None, :]*rimv[..., None]*0.9
        sub[ok] = z[ok]
        tgt = img[mny:mxy+1, mnx:mxx+1]; tgt[ok, :3] = np.clip(shade[ok], 0, 1); tgt[ok, 3] = 1
    return img
