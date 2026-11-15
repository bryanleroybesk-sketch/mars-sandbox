import bpy, bmesh, math, json, sys, random
import numpy as np
from mathutils import Vector, Euler, noise

D = '/tmp/claude-0/-home-user-mars-sandbox/eda22a4b-fb0b-53b5-8c75-12a0626db0dd/scratchpad/blender/'
argv = sys.argv[sys.argv.index('--') + 1:]
F0, F1, W, H, SAMPLES = int(argv[0]), int(argv[1]), int(argv[2]), int(argv[3]), int(argv[4])
OUT = argv[5]
TOTAL = 144

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
try:
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
except Exception:
    pass
sc.cycles.max_bounces = 8
sc.cycles.transmission_bounces = 8
sc.cycles.glossy_bounces = 4
sc.cycles.diffuse_bounces = 3
sc.cycles.transparent_max_bounces = 8
sc.cycles.caustics_reflective = False
sc.cycles.caustics_refractive = False
sc.render.resolution_x, sc.render.resolution_y = W, H
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = 'JPEG'
sc.render.image_settings.quality = 88
sc.view_settings.view_transform = 'Standard'
sc.render.film_transparent = False

# ---------- helpers ----------
def smooth(t):
    t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)
def ease_io(t):
    t = max(0.0, min(1.0, t)); return 4 * t ** 3 if t < .5 else 1 - (-2 * t + 2) ** 3 / 2
def ease_out(t):
    t = max(0.0, min(1.0, t)); return 1 - (1 - t) ** 3
def ease_in(t):
    t = max(0.0, min(1.0, t)); return t ** 3
def lerp(a, b, t): return a + (b - a) * t

# ---------- world & floor ----------
world = bpy.data.worlds.new('W'); sc.world = world; world.use_nodes = True
bg = world.node_tree.nodes['Background']
bg.inputs[0].default_value = (0.93, 0.93, 0.92, 1); bg.inputs[1].default_value = 0.85

bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
floor = bpy.context.object
fm = bpy.data.materials.new('floor'); fm.use_nodes = True
fm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.93, 0.93, 0.92, 1)
fm.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 1.0
floor.data.materials.append(fm)

# reflection cards: dark flags give the glass contrast; invisible to camera
def card(loc, rot, size):
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object; o.scale = size
    m = bpy.data.materials.new('flag'); m.use_nodes = True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.01, 0.01, 0.01, 1)
    m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.5
    o.data.materials.append(m)
    o.visible_camera = False; o.visible_shadow = False
card((-7.5, -3.5, 3.2), (math.radians(90), 0, math.radians(-62)), (2.6, 7, 1))
card((7.5, -2.0, 2.6), (math.radians(90), 0, math.radians(68)), (2.2, 7, 1))
card((0, 6.5, 6.0), (math.radians(-90), 0, 0), (9, 4, 1))
card((-2.5, -3.0, 7.5), (0, 0, 0), (3.0, 1.6, 1))
card((3.5, -5.5, 0.4), (math.radians(90), 0, math.radians(15)), (2.0, 1.4, 1))

def area(loc, energy, size, target=(0, 0, 1.5), color=(1, 1, 1)):
    d = bpy.data.lights.new('a', 'AREA'); d.energy = energy; d.size = size; d.color = color
    o = bpy.data.objects.new('a', d); sc.collection.objects.link(o); o.location = loc
    direction = Vector(target) - Vector(loc)
    o.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
area((-5.5, -6.5, 8.5), 1500, 7)
area((7.5, 3.5, 5.5), 900, 5)
area((0, -8, 2.5), 250, 8)

# ---------- materials ----------
def principled(mat):
    return mat.node_tree.nodes['Principled BSDF']

def stone_material(name, base, rough, contour=False):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links
    bsdf = N['Principled BSDF']
    tc = N.new('ShaderNodeTexCoord')
    nz = N.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = 3; nz.inputs['Detail'].default_value = 14; nz.inputs['Roughness'].default_value = 0.65
    L.new(tc.outputs['Object'], nz.inputs['Vector'])
    ramp = N.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.35; ramp.color_ramp.elements[0].color = (base * 0.78, base * 0.78, base * 0.77, 1)
    ramp.color_ramp.elements[1].position = 0.65; ramp.color_ramp.elements[1].color = (base, base, base * 0.98, 1)
    L.new(nz.outputs['Fac'], ramp.inputs['Fac'])
    ao = N.new('ShaderNodeAmbientOcclusion'); ao.inputs['Distance'].default_value = 0.8; ao.samples = 4
    L.new(ramp.outputs['Color'], ao.inputs['Color'])
    col = ao.outputs['Color']
    if contour:
        gp = N.new('ShaderNodeNewGeometry')
        sep = N.new('ShaderNodeSeparateXYZ'); L.new(gp.outputs['Position'], sep.inputs['Vector'])
        mul = N.new('ShaderNodeMath'); mul.operation = 'MULTIPLY'; mul.inputs[1].default_value = 13.0
        L.new(sep.outputs['Z'], mul.inputs[0])
        fr = N.new('ShaderNodeMath'); fr.operation = 'FRACT'; L.new(mul.outputs[0], fr.inputs[0])
        sub = N.new('ShaderNodeMath'); sub.operation = 'SUBTRACT'; sub.inputs[1].default_value = 0.5; L.new(fr.outputs[0], sub.inputs[0])
        ab = N.new('ShaderNodeMath'); ab.operation = 'ABSOLUTE'; L.new(sub.outputs[0], ab.inputs[0])
        sm = N.new('ShaderNodeMapRange'); sm.inputs['From Min'].default_value = 0.455; sm.inputs['From Max'].default_value = 0.5
        sm.inputs['To Min'].default_value = 0.0; sm.inputs['To Max'].default_value = 0.85; L.new(ab.outputs[0], sm.inputs['Value'])
        gt = N.new('ShaderNodeMath'); gt.operation = 'SMOOTH_MAX' if False else 'GREATER_THAN'; gt.inputs[1].default_value = 0.035
        L.new(sep.outputs['Z'], gt.inputs[0])
        cm = N.new('ShaderNodeMath'); cm.operation = 'MULTIPLY'; L.new(sm.outputs['Result'], cm.inputs[0]); L.new(gt.outputs[0], cm.inputs[1])
        mx = N.new('ShaderNodeMix'); mx.data_type = 'RGBA'
        mx.inputs[7].default_value = (0.03, 0.03, 0.03, 1)
        L.new(cm.outputs[0], mx.inputs['Factor']); L.new(col, mx.inputs[6])
        mx2 = N.new('ShaderNodeMix'); mx2.data_type = 'RGBA'
        mx2.inputs[6].default_value = (0.93, 0.93, 0.92, 1)
        gt2 = N.new('ShaderNodeMath'); gt2.operation = 'GREATER_THAN'; gt2.inputs[1].default_value = 0.012; L.new(sep.outputs['Z'], gt2.inputs[0])
        L.new(gt2.outputs[0], mx2.inputs['Factor']); L.new(mx.outputs[2], mx2.inputs[7])
        col = mx2.outputs[2]
        trans = N.new('ShaderNodeBsdfTransparent'); mixs = N.new('ShaderNodeMixShader')
        L.new(gt2.outputs[0], mixs.inputs['Fac']); L.new(trans.outputs[0], mixs.inputs[1])
        contour_mix = mixs
    L.new(col, bsdf.inputs['Base Color'])
    bump = N.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = 1.1; bump.inputs['Distance'].default_value = 0.05
    nz2 = N.new('ShaderNodeTexNoise'); nz2.inputs['Scale'].default_value = 70; nz2.inputs['Detail'].default_value = 10
    L.new(tc.outputs['Object'], nz2.inputs['Vector']); L.new(nz2.outputs['Fac'], bump.inputs['Height']); L.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    bsdf.inputs['Roughness'].default_value = rough
    if contour:
        L.new(bsdf.outputs[0], contour_mix.inputs[2])
        outn = [n for n in N if n.bl_idname == 'ShaderNodeOutputMaterial'][0]
        L.new(contour_mix.outputs[0], outn.inputs['Surface'])
    return m

rock_mat = stone_material('rock', 0.66, 0.92)
terr_mat = stone_material('terrain', 0.88, 0.85, contour=True)

glass_mat = bpy.data.materials.new('crystal'); glass_mat.use_nodes = True
nt = glass_mat.node_tree; N = nt.nodes; L = nt.links
for n in list(N): N.remove(n)
out = N.new('ShaderNodeOutputMaterial')
gl = N.new('ShaderNodeBsdfPrincipled')
gl.inputs['Base Color'].default_value = (1, 1, 1, 1); gl.inputs['Roughness'].default_value = 0.025
gl.inputs['IOR'].default_value = 1.55; gl.inputs['Transmission Weight'].default_value = 1.0
tr = N.new('ShaderNodeBsdfTransparent')
lp = N.new('ShaderNodeLightPath'); mix = N.new('ShaderNodeMixShader')
L.new(lp.outputs['Is Shadow Ray'], mix.inputs['Fac']); L.new(gl.outputs[0], mix.inputs[1]); L.new(tr.outputs[0], mix.inputs[2])
L.new(mix.outputs[0], out.inputs[0])

# ---------- geometry builders ----------
rnd = random.Random(4)

def make_lump(radius, seed, sx=1, sy=1, sz=1):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=5, radius=1.0)
    off = Vector((seed * 3.7, seed * 1.3, seed * 2.1))
    for v in bm.verts:
        p = v.co.copy()
        n = noise.ridged_multi_fractal(p * 1.1 + off, 1.0, 2.1, 6, 1.0, 2.0)
        r = noise.turbulence(p * 4.0 + off, 4, False)
        d = 0.62 + 0.42 * n + 0.16 * r
        v.co = Vector((p.x * sx, p.y * sy, p.z * sz)) * d * radius
    for f in bm.faces: f.smooth = True
    me = bpy.data.meshes.new('lump'); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new('lump', me); sc.collection.objects.link(o); o.data.materials.append(rock_mat)
    return o

def make_crystal(length, radius, seed):
    r = random.Random(seed)
    bm = bmesh.new(); ring0, ring1 = [], []
    for i in range(6):
        a = i / 6 * math.tau + r.uniform(-0.08, 0.08)
        ring0.append(bm.verts.new((math.cos(a) * radius * r.uniform(.93, 1.07), math.sin(a) * radius * r.uniform(.93, 1.07), 0)))
        ring1.append(bm.verts.new((math.cos(a) * radius * r.uniform(.9, 1.0), math.sin(a) * radius * r.uniform(.9, 1.0), length * 0.74)))
    tip = bm.verts.new((r.uniform(-.03, .03) * radius, r.uniform(-.03, .03) * radius, length))
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i]))
        bm.faces.new((ring1[i], ring1[j], tip))
    bm.faces.new(list(reversed(ring0)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new('crystal'); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new('crystal', me); sc.collection.objects.link(o); o.data.materials.append(glass_mat)
    return o

# ---------- hero formation ----------
rig = bpy.data.objects.new('rig', None); sc.collection.objects.link(rig); rig.location = (0, 0, 2.2); rig.scale = (0.86, 0.86, 0.86)
frags = []

def add_frag(o, loc, rot, scale=1.0):
    o.parent = rig
    o.location = loc; o.rotation_euler = rot; o.scale = (scale,) * 3
    st = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 0.4), rnd.uniform(-0.4, 1))).normalized() * rnd.uniform(6.5, 11)
    frags.append(dict(o=o, fl=Vector(loc), fr=Vector(rot), fs=scale,
                      sl=Vector(loc) + st, sr=Vector((rnd.uniform(0, 6.28), rnd.uniform(0, 6.28), rnd.uniform(0, 6.28))),
                      delay=rnd.uniform(0, 12), delay2=rnd.uniform(0, 8),
                      out=(Vector((rnd.uniform(-1, 1), rnd.uniform(-1.2, -0.2), rnd.uniform(-0.2, 1))).normalized() * rnd.uniform(7, 12)),
                      spin=Vector((rnd.uniform(-2, 2), rnd.uniform(-2, 2), rnd.uniform(-2, 2)))))

# rock body: lumps packed into an irregular, bottom-heavy mass
lumps = []
for i in range(13):
    t = i / 12
    z = lerp(-1.35, 0.55, rnd.random() ** 1.2)
    spread = lerp(0.55, 0.95, 1 - (z + 1.35) / 1.9) * (1.0 + 0.0)
    ang = rnd.uniform(0, math.tau); rad = rnd.uniform(0.05, 1) ** 0.7 * spread * (1.1 - 0.35 * (z + 1.35) / 1.9)
    pos = (math.cos(ang) * rad * 0.9 - 0.12, math.sin(ang) * rad * 0.7, z)
    r = rnd.uniform(0.78, 1.25) * (1.0 - 0.25 * (z + 1.35) / 1.9)
    lumps.append((pos, r))
for i, (pos, r) in enumerate(lumps):
    o = make_lump(r, i + 1, rnd.uniform(.7, 1.35), rnd.uniform(.7, 1.2), rnd.uniform(.6, 1.2))
    add_frag(o, pos, (rnd.uniform(0, 6.28), rnd.uniform(0, 6.28), rnd.uniform(0, 6.28)))

# crystal cluster growing out of the upper left
base = Vector((-0.75, 0.0, 0.0))
for i in range(10):
    a = rnd.uniform(0, math.tau); tilt = rnd.uniform(0.1, 0.8)
    L_ = rnd.uniform(1.8, 3.2) * (1.2 if i < 3 else 1.0); R_ = rnd.uniform(0.26, 0.48) * (L_ ** 0.3)
    c = make_crystal(L_, R_, 50 + i)
    dirv = Vector((math.sin(tilt) * math.cos(a) - 0.55, math.sin(tilt) * math.sin(a) * 0.6, math.cos(tilt)))
    dirv.normalize()
    rot = Vector((0, 0, 1)).rotation_difference(dirv).to_euler()
    jitter = Vector((rnd.uniform(-.28, .28), rnd.uniform(-.2, .2), rnd.uniform(-.12, .12)))
    add_frag(c, base + jitter, tuple(rot))

# hanging wires
wires = []
for x in (-0.95, -0.05, 1.05):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.011, depth=1, vertices=8)
    w = bpy.context.object; w.parent = rig
    wm = bpy.data.materials.new('wire'); wm.use_nodes = True
    principled(wm).inputs['Base Color'].default_value = (0.02, 0.02, 0.02, 1); principled(wm).inputs['Roughness'].default_value = 0.4
    w.data.materials.append(wm)
    wires.append((w, x))

# ---------- terrain with shape keys ----------
hz = np.load(D + 'heights.npz'); N_ = int(hz['N']); SIZE = float(hz['SIZE'])
cities = json.load(open(D + 'cities.json'))
HS = {'CHE': 0.62, 'THA': 0.85, 'ARE': 1.0}
gx = (np.arange(N_) / (N_ - 1) - 0.5) * SIZE; gy = (0.5 - np.arange(N_) / (N_ - 1)) * SIZE
X, Y = np.meshgrid(gx, gy)
verts = np.stack([X.ravel(), Y.ravel(), np.zeros(N_ * N_)], axis=1)
faces = []
for j in range(N_ - 1):
    r0 = j * N_
    for i in range(N_ - 1):
        a = r0 + i; faces.append((a, a + 1, a + 1 + N_, a + N_))
me = bpy.data.meshes.new('terrain'); me.from_pydata(verts.tolist(), [], faces); me.update()
terr = bpy.data.objects.new('terrain', me); sc.collection.objects.link(terr); terr.data.materials.append(terr_mat)
me.polygons.foreach_set('use_smooth', [True] * len(me.polygons))
terr.shape_key_add(name='Basis')
keys = {}
for code in ('CHE', 'THA', 'ARE'):
    k = terr.shape_key_add(name=code, from_mix=False)
    co = verts.copy(); co[:, 2] = hz[code].ravel() * HS[code]
    k.data.foreach_set('co', co.ravel()); keys[code] = k
    k.slider_min = 0; k.slider_max = 1

def height_at(code, x, y):
    i = int((x / SIZE + 0.5) * (N_ - 1)); j = int((0.5 - y / SIZE) * (N_ - 1))
    return float(hz[code][j, i]) * HS[code]

# city crystal markers + thin pins
markers = {}
for code in ('CHE', 'THA', 'ARE'):
    cx, cy = cities[code]; z = height_at(code, cx, cy)
    e = bpy.data.objects.new('city', None); sc.collection.objects.link(e); e.location = (cx, cy, z)
    for i in range(7):
        a = rnd.uniform(0, math.tau); tilt = rnd.uniform(0.0, 0.5); L_ = rnd.uniform(0.45, 0.95) * (1.3 if i == 0 else 1)
        c = make_crystal(L_, rnd.uniform(0.07, 0.13), 200 + i)
        c.parent = e
        dirv = Vector((math.sin(tilt) * math.cos(a), math.sin(tilt) * math.sin(a), math.cos(tilt)))
        c.rotation_euler = Vector((0, 0, 1)).rotation_difference(dirv).to_euler()
        c.location = (rnd.uniform(-.07, .07), rnd.uniform(-.07, .07), -0.03)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.009, depth=1, vertices=8)
    pin = bpy.context.object; pin.parent = e; pin.location = (0, 0, 3.6); pin.scale = (1, 1, 6.2)
    pm = bpy.data.materials.new('pin'); pm.use_nodes = True
    principled(pm).inputs['Base Color'].default_value = (0.02, 0.02, 0.02, 1); pin.data.materials.append(pm)
    markers[code] = e

# ---------- camera ----------
cam_d = bpy.data.cameras.new('cam'); cam_d.lens = 38
cam = bpy.data.objects.new('cam', cam_d); sc.collection.objects.link(cam); sc.camera = cam
def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()

# ---------- timeline ----------
def state(f):
    # hero assembly 0-36, hold to 46, shatter 48-70
    for fr in frags:
        o = fr['o']
        ta = ease_io((f - fr['delay']) / 30.0)
        ts = ease_in((f - 48 - fr['delay2']) / 20.0)
        loc = fr['sl'].lerp(fr['fl'], ta)
        rot = Vector(fr['sr']).lerp(fr['fr'], ta)
        sca = fr['fs']
        if f >= 48:
            loc = fr['fl'] + fr['out'] * ts; rot = fr['fr'] + fr['spin'] * ts * 2.0; sca = fr['fs'] * (1 - smooth(ts * 1.1))
        o.location = loc; o.rotation_euler = Euler(rot, 'XYZ'); o.scale = (max(sca, 1e-4),) * 3
        o.hide_render = (sca < 0.01)
    rig.rotation_euler = (0, 0, math.radians(lerp(-14, 12, min(f, 70) / 70.0)))
    wk = 1 - smooth((f - 44) / 8.0)
    for w, x in wires:
        zt = 9.0; zb = 0.55
        w.scale = (1, 1, max((zt - zb), 1e-3)); w.location = (x, 0.1, (zt + zb) / 2 - 0.0)
        w.hide_render = wk < 0.02
        if wk >= 0.02:
            w.scale = (wk, wk, zt - zb)
    # terrain keys
    kc = smooth((f - 54) / 26.0) * (1 - smooth((f - 90) / 18.0))
    kt = smooth((f - 90) / 18.0) * (1 - smooth((f - 118) / 16.0))
    ka = smooth((f - 118) / 16.0)
    keys['CHE'].value, keys['THA'].value, keys['ARE'].value = kc, kt, ka
    for code, kv in (('CHE', kc), ('THA', kt), ('ARE', ka)):
        m = markers[code]; s = smooth((kv - 0.88) / 0.12)
        m.scale = (max(s, 1e-4),) * 3; m.hide_render = s < 0.01
    terr.rotation_euler = (0, 0, math.radians(lerp(-16, 16, max(0, min(1, (f - 60) / 84.0)))))
    # camera
    tcam = smooth((f - 42) / 30.0)
    pos = Vector((lerp(0.0, 0.0, tcam), lerp(-12.6, -4.3, tcam), lerp(3.0, 3.9, tcam)))
    tgt = Vector((0, 0, lerp(2.0, 0.45, tcam)))
    # slow dolly later
    pos.y += lerp(0, -0.4, smooth((f - 100) / 44.0))
    cam.location = pos; aim(cam, tgt)
    cam_d.shift_x = -0.16

F = TOTAL
import os
os.makedirs(OUT, exist_ok=True)
for f in range(F0, F1 + 1):
    state(f)
    sc.frame_set(1)
    sc.render.filepath = os.path.join(OUT, 'f%03d.jpg' % f)
    bpy.ops.render.render(write_still=True)
    print('rendered', f, flush=True)
