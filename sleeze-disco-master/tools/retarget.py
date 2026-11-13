import numpy as np
from rig import Model

def rot_between(a, b):
    a = a/np.linalg.norm(a); b = b/np.linalg.norm(b); v = np.cross(a, b); c = np.dot(a, b)
    if c < -0.9999:
        ax = np.cross(a, [1, 0, 0]);
        if np.linalg.norm(ax) < 1e-6: ax = np.cross(a, [0, 1, 0])
        ax /= np.linalg.norm(ax); return 2*np.outer(ax, ax)-np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3)+vx+vx@vx*(1/(1+c))

def frame(l, r, up):
    x = l-r; x /= np.linalg.norm(x); y = up-np.dot(up, x)*x; y /= np.linalg.norm(y); z = np.cross(x, y)
    return np.stack([x, y, z], 1)

def split(M):
    s = np.linalg.norm(M[:3, :3], axis=0); return M[:3, :3]/s, s

SRC_ROLES = {  # role: (bone, child)
 'spineA': ('CC_Base_Waist', 'CC_Base_Spine02'), 'chest': ('CC_Base_Spine02', 'CC_Base_NeckTwist01'), 'neck': ('CC_Base_NeckTwist01', 'CC_Base_Head'),
}
for S in 'LR':
    SRC_ROLES.update({f'{S}clav': (f'CC_Base_{S}_Clavicle', f'CC_Base_{S}_Upperarm'), f'{S}upper': (f'CC_Base_{S}_Upperarm', f'CC_Base_{S}_Forearm'),
      f'{S}fore': (f'CC_Base_{S}_Forearm', f'CC_Base_{S}_Hand'), f'{S}hand': (f'CC_Base_{S}_Hand', f'CC_Base_{S}_Mid1'),
      f'{S}thigh': (f'CC_Base_{S}_Thigh', f'CC_Base_{S}_Calf'), f'{S}calf': (f'CC_Base_{S}_Calf', f'CC_Base_{S}_Foot'), f'{S}foot': (f'CC_Base_{S}_Foot', f'CC_Base_{S}_ToeBase')})
SRC_HIP = ('CC_Base_Hip', 'CC_Base_L_Thigh', 'CC_Base_R_Thigh', 'CC_Base_Spine02')

class Retarget:
    def __init__(self, src: Model, src_rest_t, src_rest_anim, tgt: Model, tmap, thip, roles=None, shi=None, feet=None, floor='min'):
        """tmap: list of (target bone, target child, role); thip: (hipbone, Lthigh, Rthigh, chest)"""
        self.src, self.tgt, self.tmap, self.thip = src, tgt, tmap, thip
        self.roles = roles or SRC_ROLES; self.shi = shi or SRC_HIP; self.feet = feet or ('CC_Base_L_Foot', 'CC_Base_R_Foot'); self.floor = floor
        Gs = src.globals(src.chans(src.anims[src_rest_anim]) if src_rest_anim else 'rest', src_rest_t)
        Gt = tgt.globals({}, 0)
        self.Gt_rest = Gt
        p = lambda G, n: G[n][:3, 3]
        self.src_floor = min(p(Gs, self.feet[0])[1], p(Gs, self.feet[1])[1])
        self.src_hip_h = p(Gs, self.shi[0])[1]-self.src_floor
        lt, rt = thip[1], thip[2]
        foot = [b for b, c, r in tmap if r == 'Lfoot'][0]
        self.tgt_hip_h = p(Gt, thip[0])[1]-p(Gt, foot)[1]
        self.ratio = self.tgt_hip_h/self.src_hip_h
        self.foot_off = p(Gt, foot)[1] - p(Gt, thip[0])[1]
        self.Ft_rest = frame(p(Gt, lt), p(Gt, rt), p(Gt, thip[3])-p(Gt, thip[0]))
        self.Rt_hip_rest, _ = split(Gt[thip[0]])
        # child offsets in bone-local (rest)
        self.off = {}
        for b, c, r in tmap:
            self.off[b] = (np.linalg.inv(Gt[b]) @ np.r_[p(Gt, c), 1])[:3]

    def globals(self, ch, t):
        Gs = self.src.globals(ch, t); p = lambda n: Gs[n][:3, 3]
        dirs = {r: p(c)-p(b) for r, (b, c) in self.roles.items()}
        SH = self.shi
        Fs = frame(p(SH[1]), p(SH[2]), p(SH[3])-p(SH[0]))
        hip = p(SH[0]); footy = min(p(self.feet[0])[1], p(self.feet[1])[1]) if self.floor == 'min' else self.src_floor
        tgt = self.tgt; G = {}; bmap = {b: r for b, c, r in self.tmap}
        for name in tgt.order:
            parent, L = tgt.nodes[name]
            M = L if parent is None else G[parent] @ L
            if name == self.thip[0]:
                R, sc = split(M)
                Rn = Fs @ self.Ft_rest.T @ split(self.Gt_rest[name])[0]
                M = M.copy(); M[:3, :3] = Rn*sc
                M[:3, 3] = np.array([hip[0]*self.ratio, (hip[1]-footy)*self.ratio + (self.Gt_rest[name][1, 3]-self.tgt_hip_h) , hip[2]*self.ratio])
            elif name in bmap:
                R, sc = split(M)
                cur = R @ (self.off[name]*sc)
                Rn = rot_between(cur, dirs[bmap[name]]) @ R
                M = M.copy(); M[:3, :3] = Rn*sc
            G[name] = M
        return G
