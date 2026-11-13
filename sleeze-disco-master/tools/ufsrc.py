import numpy as np
class UfbxSrc:
    """Mixamo motion source read from an npz baked by fbx2npz.py (world matrices per frame @30fps)."""
    def __init__(self, path):
        d=np.load(path); self.names=list(d['names']); self.rest=d['rest']; self.fr=d['frames']
        self.nframes=len(self.fr); self.anims={}
    def chans(self,a): return None
    def globals(self,ch,t):
        if isinstance(ch,str) and ch=='rest': return dict(zip(self.names,self.rest))
        t=min(max(t,0),self.nframes-1); i=int(t); f=t-i; j=min(i+1,self.nframes-1)
        A=self.fr[i]; B=self.fr[j]
        if f>0:  # position lerp only on translation; rotations: pick nearest (30fps is dense)
            M=(A if f<0.5 else B).copy(); M[:,:3,3]=A[:,:3,3]*(1-f)+B[:,:3,3]*f
        else: M=A
        return dict(zip(self.names,M))
