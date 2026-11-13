# Blender: Night Dance Club Lowpoly -> club.glb for Godot 3.5 (Vita budget)
# - meters, pit dance floor moved to height 0, arena centre at origin
# - textures capped at 512 px, duplicate "Baked" materials merged
# - meshes joined per 12 m grid cell (draw-call budget) but kept as
#   separate objects so frustum culling + the LOD script still work
# - small props (bottles) in their own cell objects so they can be culled by distance
# - a simplified collision mesh "club-colonly" (room shell + prop boxes)
import bpy, bmesh, os, math
from mathutils import Vector
from PIL import Image
SRC = '/workspace/work/assets3d/night-dance-club-lowpoly-cb9f1e072674'
OUT = '/workspace/work/sd3d/glb/club.glb'
TEX = '/workspace/work/sd3d/tex'
os.makedirs(TEX, exist_ok=True)
SHIFT = Vector((-2.0, -2.0, 1.7))
CELL = 12.0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC + '/source/Club.fbx')
objs = [o for o in bpy.data.objects if o.type == 'MESH']
for o in list(bpy.data.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o)

def sel(lst):
    bpy.ops.object.select_all(action='DESELECT')
    for o in lst: o.select_set(True)
    bpy.context.view_layer.objects.active = lst[0]

# make single-user + apply transforms
sel(objs)
bpy.ops.object.make_single_user(object=True, obdata=True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in objs:
    o.data.transform(__import__('mathutils').Matrix.Translation(SHIFT))
    o.data.update()

# textures 512 cap
imgs = {}
for name in ('DJSet', 'Interior', 'Spotlight', 'Tile', 'neon'):
    im = Image.open('%s/textures/%s.png' % (SRC, name)).convert('RGB')
    if max(im.size) > 512:
        im = im.resize((512, int(512 * im.size[1] / im.size[0])), Image.LANCZOS)
    p = '%s/club_%s.png' % (TEX, name)
    im.save(p)
    img = bpy.data.images.load(p); img.pack(); imgs[name] = img

def mk(name, img=None, col=(1, 1, 1)):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
    b.inputs['Base Color'].default_value = (*col, 1); b.inputs['Roughness'].default_value = 0.85
    if img:
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = img
        nt.links.new(t.outputs['Color'], b.inputs['Base Color'])
    return m
NEW = {
    'Interior': mk('Interior', imgs['Interior']), 'Interior Baked': None,
    'DJSet': mk('DJSet', imgs['DJSet']), 'DJSet Baked': None,
    'SpotLight': mk('SpotLight', imgs['Spotlight']), 'Tile': mk('Tile', imgs['Tile']),
    'neon': mk('neon', imgs['neon']), 'Array': mk('Shell', None, (0.35, 0.33, 0.4)),
    'Glass': mk('Glass', None, (0.0, 0.04, 0.33)), 'TVScreen': mk('TVScreen', None, (0.12, 0.12, 0.12)),
    'Disco': mk('Disco', None, (1, 1, 1)), 'DiscoAura': mk('DiscoAura', None, (1.0, 0.43, 0.93)),
}
NEW['Interior Baked'] = NEW['Interior']; NEW['DJSet Baked'] = NEW['DJSet']
for o in objs:
    for i, s in enumerate(o.material_slots):
        if s.material and s.material.name in NEW:
            o.material_slots[i].material = NEW[s.material.name]
        elif s.material:
            base = s.material.name.split('.')[0]
            if base in NEW: o.material_slots[i].material = NEW[base]

# collision mesh: shell + boxes around furniture
col_me = bpy.data.meshes.new('club_col'); bm = bmesh.new()
shell = [o for o in objs if o.name.startswith('BaseRoom')][0]
bm.from_mesh(shell.data)
SOLID = ('BarChair', 'Table', 'Sofa', 'SingleSofa', 'RoomSofa', 'Slotmachine', 'Plant', 'Pillow')
for o in objs:
    if o.name.startswith(SOLID):
        vs = [v.co for v in o.data.vertices]
        mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        res = bmesh.ops.create_cube(bm, size=1.0)
        for v in res['verts']:
            v.co = Vector(((mn.x + mx.x) / 2 + v.co.x * (mx.x - mn.x), (mn.y + mx.y) / 2 + v.co.y * (mx.y - mn.y), (mn.z + mx.z) / 2 + v.co.z * (mx.z - mn.z)))
bm.to_mesh(col_me); bm.free()
col = bpy.data.objects.new('club-colonly', col_me); bpy.context.scene.collection.objects.link(col)

# Vita budget: halve the densest props (sofas, tables, slot machines, plants, disco ball)
DENSE = ('SingleSofa', 'Table', 'Slotmachine', 'Plant', 'Disco', 'RoomSofa', 'Pillow')
for o in objs:
    if o.name.startswith(DENSE):
        sel([o])
        mod = o.modifiers.new('dec', 'DECIMATE'); mod.ratio = 0.5
        bpy.ops.object.modifier_apply(modifier='dec')

# group visuals into cells
SMALL = ('Beer', 'Milk', 'Whiskey', 'WineRed', 'Winexanh', 'Vang')
groups = {}
for o in objs:
    if o is shell:
        continue
    c = sum((o.matrix_world @ Vector(b) for b in o.bound_box), Vector()) / 8
    if o.name.startswith('Disco'):
        key = 'disco'
    elif o.name.startswith('Hanging_SpotLight'):
        key = 'spot_%s' % o.name.split('_')[-1]   # one object each: hidden when the camera gets close
    else:
        kind = 'small' if o.name.startswith(SMALL) else 'props'
        key = '%s_%d_%d' % (kind, math.floor(c.x / CELL), math.floor(c.y / CELL))
    groups.setdefault(key, []).append(o)
for k, lst in groups.items():
    sel(lst); bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active; o.name = k
    # origin at bounds centre so Godot distance checks work
    sel([o]); bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
shell.name = 'shell'
tot = 0
for o in bpy.data.objects:
    if o.type == 'MESH' and o is not col:
        t = sum(len(p.vertices) - 2 for p in o.data.polygons); tot += t
        print('OBJ', o.name, t, [m.name for m in o.data.materials])
print('TOTAL tris', tot)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=False, export_yup=True,
                          export_animations=False, export_lights=False, export_cameras=False, export_apply=False)
print('WROTE', OUT, os.path.getsize(OUT))
