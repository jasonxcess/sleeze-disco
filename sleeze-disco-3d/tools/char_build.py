# Blender (4.3, headless) character builder for SLEEZE DISCO 3D arena.
# Usage: blender -b -noaudio --python char_build.py -- <char> <out.glb>
#   char = player | thug | vex | crowd
# Imports the rigged model, cleans/normalises it (meters, Z-up, feet on 0,
# facing -Y), retargets Mixamo clips onto it with a direction+frame
# retarget (rest-pose independent: works for T-pose, A-pose and the
# rigify-style Vex rig), and exports one .glb holding the skinned mesh
# and every clip as a named animation.
import bpy, sys, os, math
from mathutils import Vector, Matrix, Quaternion

A = sys.argv[sys.argv.index('--') + 1:]
CHAR, OUT = A[0], A[1]
AS = '/workspace/work/assets3d'
PRJ = '/workspace/projects/dfc1902b-fffb-4a06-a1df-d0807c5e9c75'
MX_OLD = PRJ + '/files/mixamo'
MX_NEW = PRJ + '/web/downloads/mixamo'
TEXOUT = '/workspace/work/sd3d/tex'
os.makedirs(TEXOUT, exist_ok=True)

def oldclip(prefix):
    for f in sorted(os.listdir(MX_OLD)):
        if f.startswith(prefix + '-'):
            return os.path.join(MX_OLD, f)
    raise Exception('no clip ' + prefix)

CLIPS_ALL = {
    'idle': (MX_NEW + '/fighting_idle.fbx', False),
    'walk': (MX_NEW + '/walking_inplace.fbx', False),
    'run': (MX_NEW + '/running_inplace.fbx', False),
    'sprint': (MX_NEW + '/fast_run_inplace.fbx', False),
    'jab': (MX_NEW + '/punching_jab.fbx', False),
    'cross': (MX_NEW + '/punching_cross.fbx', False),
    'kick': (oldclip('Kicking'), False),
    'block': (oldclip('Center Block'), False),
    'uppercut': (oldclip('Uppercut'), False),
    'hit_front': (MX_NEW + '/hit_reaction_front.fbx', False),
    'hit_head_l': (MX_NEW + '/head_hit.fbx', False),
    'hit_head_r': (MX_NEW + '/head_hit.fbx', True),      # mirrored copy
    'hit_back': (MX_NEW + '/receiving_uppercut.fbx', False),
    'knockdown': (MX_NEW + '/knocked_out.fbx', False),
    'getup': (oldclip('Getting Up'), False),
    'taunt': (MX_NEW + '/taunt_boxing.fbx', False),
    'spinflip': (oldclip('Spin Flip Kick'), False),
    'meialua': (oldclip('Meia Lua De Compasso'), False),
    'dance': (oldclip('Hip Hop Dancing'), False),
}
SETS = {
    'player': ['idle', 'walk', 'run', 'sprint', 'jab', 'cross', 'kick', 'block', 'uppercut', 'hit_front',
               'hit_head_l', 'hit_head_r', 'hit_back', 'knockdown', 'getup', 'taunt', 'spinflip', 'meialua'],
    'thug': ['idle', 'walk', 'run', 'jab', 'cross', 'kick', 'hit_front', 'hit_head_l', 'hit_head_r',
             'hit_back', 'knockdown', 'getup', 'taunt'],
    'vex': ['idle', 'walk', 'run', 'jab', 'kick', 'meialua', 'hit_front', 'hit_head_l', 'hit_head_r',
            'hit_back', 'knockdown', 'getup', 'taunt'],
    'crowd': ['dance'],
}

# ---------------------------------------------------------------- source roles
# role: (src bone, src child) on the Mixamo skeleton (prefix stripped)
def src_roles(mirror):
    L, R = ('Right', 'Left') if mirror else ('Left', 'Right')
    r = {'hipdir': ('Hips', 'Spine2'), 'spine0': ('Spine', 'Spine1'), 'spine1': ('Spine1', 'Spine2'),
         'spineAll': ('Spine', 'Spine2'), 'chest': ('Spine2', 'Neck'), 'neck': ('Neck', 'Head'),
         'head': ('Head', 'HeadTop_End')}
    for S, s in ((L, 'L'), (R, 'R')):
        r.update({s + 'clav': (S + 'Shoulder', S + 'Arm'), s + 'upper': (S + 'Arm', S + 'ForeArm'),
                  s + 'fore': (S + 'ForeArm', S + 'Hand'), s + 'hand': (S + 'Hand', S + 'HandMiddle1'),
                  s + 'thigh': (S + 'UpLeg', S + 'Leg'), s + 'calf': (S + 'Leg', S + 'Foot'),
                  s + 'foot': (S + 'Foot', S + 'ToeBase'), s + 'toe': (S + 'ToeBase', S + 'Toe_End')})
    r['_side_hip'] = (L + 'UpLeg', R + 'UpLeg')
    r['_side_sh'] = (L + 'Arm', R + 'Arm')
    r['_feet'] = (L + 'Foot', R + 'Foot')
    return r

# target maps: (bone, child or None(tail), role, side) side: None | 'sh' | 'hip'
def tmap_player():
    m = [('Hips', 'Spine2', 'hipdir', 'hip'), ('Spine', 'Spine1', 'spine0', 'sh'), ('Spine1', 'Spine2', 'spine1', 'sh'),
         ('Spine2', 'Neck', 'chest', 'sh'), ('Neck', 'Head', 'neck', 'sh'), ('Head', 'HeadTop_End', 'head', 'sh')]
    for S, s in (('Left', 'L'), ('Right', 'R')):
        m += [(S + 'Shoulder', S + 'Arm', s + 'clav', None), (S + 'Arm', S + 'ForeArm', s + 'upper', None),
              (S + 'ForeArm', S + 'Hand', s + 'fore', None), (S + 'Hand', None, s + 'hand', None),
              (S + 'UpLeg', S + 'Leg', s + 'thigh', None), (S + 'Leg', S + 'Foot', s + 'calf', None),
              (S + 'Foot', S + 'ToeBase', s + 'foot', None), (S + 'ToeBase', S + 'Toe_End', s + 'toe', None)]
    return m, dict(hip='Hips', sideL='LeftArm', sideR='RightArm', hipL='LeftUpLeg', hipR='RightUpLeg', footL='LeftFoot', footR='RightFoot')

def tmap_thug():
    m = [('hips', 'chest', 'hipdir', 'hip'), ('spine', 'chest', 'spineAll', 'sh'), ('chest', 'neck', 'chest', 'sh'),
         ('neck', 'head', 'neck', 'sh'), ('head', 'top', 'head', 'sh')]
    for s in 'LR':
        m += [(s + '_shoulder', s + '_arm', s + 'clav', None), (s + '_arm', s + '_elbow', s + 'upper', None),
              (s + '_elbow', s + '_wrist', s + 'fore', None), (s + '_wrist', s + '_middle1', s + 'hand', None),
              (s + '_leg', s + '_knee', s + 'thigh', None), (s + '_knee', s + '_ankle', s + 'calf', None),
              (s + '_ankle', s + '_toes', s + 'foot', None)]
    return m, dict(hip='hips', sideL='L_arm', sideR='R_arm', hipL='L_leg', hipR='R_leg', footL='L_ankle', footR='R_ankle')

def tmap_vex():
    m = [('root_hips', 'spine.003', 'hipdir', 'hip'), ('spine.001', 'spine.002', 'spine0', 'sh'),
         ('spine.002', 'spine.003', 'spine1', 'sh'), ('spine.003', 'neck', 'chest', 'sh'),
         ('neck', 'head', 'neck', 'sh'), ('head', None, 'head', 'sh')]
    for s in 'LR':
        m += [('shoulder.' + s, 'arm.' + s, s + 'clav', None), ('arm.' + s, 'forearm.' + s, s + 'upper', None),
              ('forearm.' + s, 'hand.' + s, s + 'fore', None), ('hand.' + s, None, s + 'hand', None),
              ('thighs.' + s, 'leg.' + s, s + 'thigh', None), ('leg.' + s, 'foot.' + s, s + 'calf', None),
              ('foot.' + s, None, s + 'foot', None)]
    return m, dict(hip='root_hips', sideL='arm.L', sideR='arm.R', hipL='thighs.L', hipR='thighs.R', footL='foot.L', footR='foot.R')

# ---------------------------------------------------------------- helpers
def fresh():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path, use_anim=True, ignore_leaf_bones=False, automatic_bone_orientation=False)
    return [o for o in bpy.data.objects if o not in before]

def strip_prefix(arm):
    for b in arm.data.bones:
        if b.name.startswith('mixamorig:'):
            b.name = b.name[len('mixamorig:'):]

def select_only(objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]

def apply_all(objs):
    select_only(objs)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

def load_img(path, maxpx, name):
    from PIL import Image
    im = Image.open(path).convert('RGB')
    if max(im.size) > maxpx:
        im = im.resize((maxpx, maxpx) if im.size[0] == im.size[1] else (maxpx, int(maxpx * im.size[1] / im.size[0])), Image.LANCZOS)
    out = os.path.join(TEXOUT, name + '.png')
    im.save(out)
    img = bpy.data.images.load(out)
    img.pack()
    return img

def simple_mat(name, img):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
    bsdf.inputs['Roughness'].default_value = 0.9
    bsdf.inputs['Metallic'].default_value = 0.0
    if img:
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = img
        nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
    return m

# ---------------------------------------------------------------- load target
def load_target():
    fresh()
    if CHAR == 'player':
        objs = import_fbx(AS + '/psxm/source/Walking.fbx')
        arm = [o for o in objs if o.type == 'ARMATURE'][0]
        meshes = [o for o in objs if o.type == 'MESH']
        img = load_img(AS + '/psxm/textures/Male_Jacket.png', 256, 'sleeze_jacket')
        mat = simple_mat('Sleeze', img)
        for me in meshes:
            me.data.materials.clear(); me.data.materials.append(mat)
        strip_prefix(arm)
        tm = tmap_player()
        height = None
    elif CHAR in ('thug', 'crowd'):
        objs = import_fbx(AS + '/enemy1-ff6af2a6f63d/source/enemy1.fbx')
        for o in objs:
            if o.type == 'EMPTY':
                bpy.data.objects.remove(o)
        objs = [o for o in bpy.data.objects]
        arm = [o for o in objs if o.type == 'ARMATURE'][0]
        meshes = [o for o in objs if o.type == 'MESH']
        res = 128 if CHAR == 'crowd' else 256
        face = load_img(AS + '/enemy1-ff6af2a6f63d/textures/bivakfaceColor.png', res, 'thug_face%d' % res)
        body = load_img(AS + '/enemy1-ff6af2a6f63d/textures/body1Color2.png', res * 2 if CHAR != 'crowd' else res, 'thug_body%d' % res)
        for me in meshes:
            img = face if 'face' in me.name else body
            me.data.materials.clear(); me.data.materials.append(simple_mat('Thug_' + me.name, img))
        tm = tmap_thug()
        height = None
    elif CHAR == 'vex':
        bpy.ops.wm.open_mainfile(filepath=AS + '/psxw/source/WOMAN 128 FINAL.blend')
        for a in list(bpy.data.actions):
            bpy.data.actions.remove(a)
        objs = list(bpy.data.objects)
        for o in objs:
            if o.type not in ('ARMATURE', 'MESH'):
                bpy.data.objects.remove(o)
        objs = list(bpy.data.objects)
        arm = [o for o in objs if o.type == 'ARMATURE'][0]
        meshes = [o for o in objs if o.type == 'MESH']
        img = load_img(AS + '/psxw/textures/WOMAN_128.png', 128, 'vex_128')
        for me in meshes:
            me.data.materials.clear(); me.data.materials.append(simple_mat('Vex', img))
        # add a single root above spine.001 / hips.L / hips.R
        select_only([arm]); bpy.ops.object.mode_set(mode='EDIT')
        eb = arm.data.edit_bones
        r = eb.new('root_hips'); r.head = eb['spine.001'].head.copy(); r.tail = r.head + Vector((0, 0, 0.3))
        for n in ('spine.001', 'hips.L', 'hips.R'):
            eb[n].parent = r; eb[n].use_connect = False
        bpy.ops.object.mode_set(mode='OBJECT')
        tm = tmap_vex()
        height = 1.80
    for o in [arm] + meshes:
        o.animation_data_clear()
    # unparent-safe apply of all transforms (armature + meshes)
    for me in meshes:
        if me.parent != arm:
            mw = me.matrix_world.copy(); me.parent = arm; me.matrix_world = mw
    apply_all([arm] + meshes)
    if height:
        zs = [(me.matrix_world @ v.co).z for me in meshes for v in me.data.vertices]
        s = height / (max(zs) - min(zs))
        arm.scale = (s, s, s)
        apply_all([arm] + meshes)
    # feet on the floor, centred
    zs = [(me.matrix_world @ v.co).z for me in meshes for v in me.data.vertices]
    arm.location.z -= min(zs)
    hip = arm.data.bones[tm[1]['hip']].head_local
    arm.location.x -= hip.x; arm.location.y -= hip.y
    select_only([arm] + meshes); bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    # decimate heavy meshes (Vita budget)
    target_tris = {'player': 2000, 'thug': 3200, 'vex': 2000, 'crowd': 900}[CHAR]
    tris = sum(sum(len(p.vertices) - 2 for p in me.data.polygons) for me in meshes)
    if tris > target_tris:
        ratio = target_tris / tris
        for me in meshes:
            select_only([me])
            mod = me.modifiers.new('dec', 'DECIMATE'); mod.ratio = ratio
            # decimate must sit before the armature modifier to apply
            while me.modifiers[0] != mod:
                bpy.ops.object.modifier_move_up(modifier='dec')
            bpy.ops.object.modifier_apply(modifier='dec')
    # merge meshes into one (one draw call per material)
    if len(meshes) > 1:
        select_only(meshes); bpy.ops.object.join(); meshes = [bpy.context.view_layer.objects.active]
    meshes[0].name = CHAR + '_mesh'
    arm.name = CHAR + '_rig'
    tris = sum(len(p.vertices) - 2 for p in meshes[0].data.polygons)
    print('TARGET', CHAR, 'tris', tris, 'bones', len(arm.data.bones))
    return arm, meshes, tm

# ---------------------------------------------------------------- retarget
def retarget(arm, tm, clipname, path, mirror):
    tmap, tinfo = tm
    objs = import_fbx(path)
    src = [o for o in objs if o.type == 'ARMATURE'][0]
    for o in objs:
        if o is not src:
            bpy.data.objects.remove(o)
    strip_prefix(src)
    act = src.animation_data.action
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    roles = src_roles(mirror)
    SW = src.matrix_world
    MIR = Matrix.Scale(-1, 4, Vector((1, 0, 0))) if mirror else Matrix.Identity(4)

    def srest(n):
        return MIR @ SW @ src.data.bones[n].head_local
    sfloor = min(srest(roles['_feet'][0]).z, srest(roles['_feet'][1]).z)
    shiph = srest('Hips').z - sfloor
    B = arm.data.bones
    tfoot = min(B[tinfo['footL']].head_local.z, B[tinfo['footR']].head_local.z)
    thiph = B[tinfo['hip']].head_local.z - tfoot
    ratio = thiph / shiph

    order = []
    def walk(b):
        order.append(b)
        for c in b.children:
            walk(c)
    for b in B:
        if b.parent is None:
            walk(b)
    tm_by = {e[0]: e for e in tmap}
    # rest-local offsets
    off, side_local = {}, {}
    for name, child, role, side in tmap:
        b = B[name]
        rest = b.matrix_local
        tgt = B[child].head_local if child else b.tail_local
        off[name] = (rest.inverted() @ tgt) if True else None
        if side == 'sh':
            v = B[tinfo['sideL']].head_local - B[tinfo['sideR']].head_local
            side_local[name] = rest.to_3x3().inverted() @ v
        elif side == 'hip':
            v = B[tinfo['hipL']].head_local - B[tinfo['hipR']].head_local
            side_local[name] = rest.to_3x3().inverted() @ v

    newact = bpy.data.actions.new(clipname)
    newact.use_fake_user = True
    arm.animation_data_create(); arm.animation_data.action = newact
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    prevq = {}
    sc = bpy.context.scene
    sc.render.fps = 30
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        P = {pb.name: MIR @ SW @ pb.head for pb in src.pose.bones}
        def sdir(role):
            a, c = roles[role]
            return P[c] - P[a]
        sside_sh = P[roles['_side_sh'][0]] - P[roles['_side_sh'][1]]
        sside_hip = P[roles['_side_hip'][0]] - P[roles['_side_hip'][1]]
        M = {}
        for b in order:
            rest = b.matrix_local
            if b.parent:
                M0 = M[b.parent.name] @ b.parent.matrix_local.inverted() @ rest
            else:
                M0 = rest.copy()
            Mn = M0
            if b.name in tm_by:
                _, child, role, side = tm_by[b.name]
                R = M0.to_3x3().normalized()
                loc = M0.to_translation()
                d_want = sdir(role)
                if d_want.length > 1e-6:
                    d_cur = R @ off[b.name].normalized()
                    if side:
                        s_cur = R @ side_local[b.name]
                        s_want = sside_sh if side == 'sh' else sside_hip
                        def frame(d, s):
                            x = d.normalized(); y = (s - s.dot(x) * x)
                            if y.length < 1e-6: return None
                            y.normalize(); z = x.cross(y)
                            return Matrix((x, y, z)).transposed()
                        Fc, Fw = frame(d_cur, s_cur), frame(d_want, s_want)
                        if Fc and Fw:
                            Rd = Fw @ Fc.transposed()
                        else:
                            Rd = d_cur.rotation_difference(d_want).to_matrix()
                    else:
                        Rd = d_cur.rotation_difference(d_want).to_matrix()
                    R = Rd @ R
                if b.name == tinfo['hip']:
                    h = P['Hips']
                    loc = Vector((h.x * ratio, h.y * ratio, tfoot + (h.z - sfloor) * ratio))
                Mn = Matrix.Translation(loc) @ R.to_4x4()
            M[b.name] = Mn
            if b.parent:
                basis = (b.parent.matrix_local.inverted() @ rest).inverted() @ M[b.parent.name].inverted() @ Mn
            else:
                basis = rest.inverted() @ Mn
            pb = arm.pose.bones[b.name]
            q = basis.to_quaternion()
            if b.name in prevq and prevq[b.name].dot(q) < 0:
                q.negate()
            prevq[b.name] = q
            pb.rotation_quaternion = q
            pb.location = basis.to_translation() if b.name == tinfo['hip'] else Vector((0, 0, 0))
            pb.scale = (1, 1, 1)
            pb.keyframe_insert('rotation_quaternion', frame=f - f0)
            pb.keyframe_insert('location', frame=f - f0)
    # loop clips: copy first key to the end so cycles close
    bpy.data.objects.remove(src)
    bpy.data.actions.remove(act)
    print('CLIP', clipname, f1 - f0 + 1, 'frames')
    return newact

arm, meshes, tm = load_target()
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
acts = []
for cn in SETS[CHAR]:
    path, mir = CLIPS_ALL[cn]
    acts.append(retarget(arm, tm, cn, path, mir))
# put every action on its own NLA track so the exporter sees them all
arm.animation_data.action = None
for a in acts:
    tr = arm.animation_data.nla_tracks.new(); tr.name = a.name
    tr.strips.new(a.name, 0, a)
    tr.mute = True
bpy.context.scene.frame_set(0)
select_only([arm] + meshes)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='ACTIONS',
                          export_force_sampling=True, export_frame_step=1,
                          export_skins=True, export_all_influences=False,
                          export_def_bones=False, export_apply=False,
                          export_image_format='AUTO', export_yup=True,
                          export_morph=False, export_lights=False, export_cameras=False)
print('WROTE', OUT, os.path.getsize(OUT))
