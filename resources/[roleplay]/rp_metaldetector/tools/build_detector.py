"""
rp_metaldetector / tools/build_detector.py

Modela en Blender el detector de metales (inspirado en un detector de playa real: bobina con
radios, vara telescópica, caja de control con pantalla LCD, empuñadura de espuma y apoyabrazos)
y exporta, con el addon DragonFF (GPL, github.com/Parik27/DragonFF; no está en el repo):
  - models/detector_<n>.dff  (n = 1..5, misma malla con los colores de cada nivel, detector_tiers.py)
  - models/detector.txd      (textura de la pantalla, compartida)
  - tools/detector.blend     (para retocar a mano y para render_icons.py)

Uso (Blender 4.2, sin ventana):
  blender.exe --background --factory-startup --python build_detector.py -- <carpeta que contiene DragonFF/> <ruta del recurso>
Después, los iconos de la tienda:
  blender.exe --background "<recurso>/tools/detector.blend" --python render_icons.py -- <ruta del recurso>

Ejes del modelo: origen = centro de la empuñadura (donde va la mano). +Y = hacia delante (hacia la
bobina), +Z = arriba, +X = derecha. La bobina queda a ~1,05 m de la mano, abajo y delante.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DRAGON_PARENT = argv[0] if len(argv) > 0 else ""
RES = argv[1] if len(argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RES, "tools"))
from detector_tiers import TIERS, FIXED, srgb_to_lin   # colores por nivel (compartidos con render_icons.py)

# ---------------------------------------------------------------- escena limpia + DragonFF
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
if DRAGON_PARENT:
    sys.path.insert(0, DRAGON_PARENT)
import DragonFF                      # registra Object.dff, Material.dff y los operadores de exportación
DragonFF.register()

# ---------------------------------------------------------------- materiales
def make_mat(name, color, rough=0.5, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*srgb_to_lin(color), 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*srgb_to_lin(color), 1)
    return m

MAT = {
    "body":   make_mat("md_body", TIERS[1]["body"], 0.35),
    "accent": make_mat("md_accent", TIERS[1]["accent"], 0.4),
    "shaft":  make_mat("md_shaft", TIERS[1]["shaft"], 0.3, 0.6),
    "black":  make_mat("md_black", (0.035, 0.035, 0.04), 0.6),
    "foam":   make_mat("md_foam", (0.06, 0.06, 0.065), 0.9),
    "knob":   make_mat("md_knob", (0.12, 0.12, 0.13), 0.5),
}

# Pantalla LCD con textura propia (se exporta al TXD)
SCREEN_W, SCREEN_H = 64, 32
img = bpy.data.images.new("md_screen", SCREEN_W, SCREEN_H, alpha=False)
px = []
for y in range(SCREEN_H):
    for x in range(SCREEN_W):
        r, g, b = 0.08, 0.30, 0.62                     # fondo azul LCD
        if 3 <= y <= 5 and 4 <= x < 60: r, g, b = 0.55, 0.85, 1.0          # barra de señal (abajo)
        if 3 <= y <= 5 and 4 + (x - 4) % 6 >= 4 + 4 and 4 <= x < 60: r, g, b = 0.08, 0.30, 0.62
        if 12 <= y <= 26 and 6 <= x <= 26:             # números grandes (dos dígitos de 7 segmentos aprox.)
            lx = (x - 6) % 11
            seg = (lx in (0, 1, 8, 9)) or (y in (12, 13, 19, 20, 25, 26) and lx < 10)
            if seg and lx < 10: r, g, b = 0.80, 0.95, 1.0
        if 22 <= y <= 26 and 34 <= x <= 58 and (x // 3) % 2 == 0: r, g, b = 0.6, 0.9, 1.0   # escala
        if 12 <= y <= 18 and 34 <= x <= 58 and y == 15: r, g, b = 0.6, 0.9, 1.0
        if x in (0, SCREEN_W - 1) or y in (0, SCREEN_H - 1): r, g, b = 0.03, 0.08, 0.18
        px += [r, g, b, 1.0]
img.pixels = px
img.pack()
m = make_mat("md_screen", (1, 1, 1), 0.2)
nt = m.node_tree
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
tex.interpolation = "Closest"
nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
p = nt.nodes["Principled BSDF"]
p.inputs["Emission Color"].default_value = (0.2, 0.5, 1.0, 1)
p.inputs["Emission Strength"].default_value = 0.6
MAT["screen"] = m

# ---------------------------------------------------------------- utilidades de modelado
parts = []

def finish(obj, mat, smooth=True):
    obj.data.materials.clear()
    obj.data.materials.append(MAT[mat])
    if smooth:
        for poly in obj.data.polygons:
            poly.use_smooth = True
    parts.append(obj)
    return obj

def cylinder_between(a, b, radius, mat, verts=16, caps=True):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=d.length,
                                        end_fill_type="NGON" if caps else "NOTHING", location=(a + b) / 2)
    obj = bpy.context.active_object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return finish(obj, mat)

def box(center, size, mat, bevel=0.0, rot=(0, 0, 0), segments=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "NONE"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, mat)

def apply_all(obj):
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)

# ---------------------------------------------------------------- geometría
GRIP = Vector((0, 0, 0))
ELBOW = Vector((0, 0.115, -0.05))           # donde la vara baja hacia la bobina
COIL = Vector((0, 0.62, -0.88))             # centro de la bobina (a ras del suelo con el brazo bajo)
CUFF = Vector((0, -0.27, 0.085))            # apoyabrazos
R_TUBE = 0.0125

# Vara superior: apoyabrazos -> empuñadura -> codo
cylinder_between(CUFF + Vector((0, 0.03, -0.035)), GRIP + Vector((0, -0.09, 0.012)), R_TUBE, "shaft")
cylinder_between(GRIP + Vector((0, -0.09, 0.012)), ELBOW, R_TUBE, "shaft")

# Empuñadura de espuma con dos aros de acento
cylinder_between(GRIP + Vector((0, -0.075, 0.010)), GRIP + Vector((0, 0.06, -0.008)), 0.021, "foam", 20)
for t in (-0.085, 0.068):
    c = GRIP + Vector((0, t, 0.011 if t < 0 else -0.009))
    cylinder_between(c - Vector((0, 0.008, 0)), c + Vector((0, 0.008, 0)), 0.0235, "accent", 20)

# Caja de control (cuerpo) bajo el codo, con la pantalla mirando arriba-atrás
box_c = ELBOW + Vector((0, 0.02, -0.035))
box_rot = (math.radians(-28), 0, 0)
body = box(box_c, (0.085, 0.15, 0.065), "body", bevel=0.018, rot=box_rot, segments=4)
# Morro redondeado de la caja (como el del detector de referencia)
bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=0.045, location=box_c + Vector((0, 0.06, -0.035)))
nose = bpy.context.active_object
nose.scale = (0.95, 0.8, 0.7)
bpy.ops.object.transform_apply(scale=True)
finish(nose, "body")

# Pantalla (plano con UV completo) y botones
rot = Matrix.Rotation(math.radians(-28), 4, "X")
up = rot @ Vector((0, 0, 1))
fwd = rot @ Vector((0, 1, 0))
scr_c = box_c + up * 0.0335 + fwd * -0.02
bpy.ops.mesh.primitive_plane_add(size=1, location=scr_c, rotation=(math.radians(-28), 0, 0))
scr = bpy.context.active_object
scr.scale = (0.062, 0.05, 1)
bpy.ops.object.transform_apply(scale=True)
finish(scr, "screen", smooth=False)
for i, bx in enumerate((-0.022, 0, 0.022)):
    bc = box_c + up * 0.034 + fwd * 0.04 + Vector((bx, 0, 0))
    cylinder_between(bc - up * 0.002, bc + up * 0.006, 0.0075, "accent" if i == 1 else "knob", 12)

# Vara inferior telescópica: tramo grueso, seguro giratorio y tramo fino
lower_a = ELBOW + (COIL - ELBOW).normalized() * 0.02
lower_mid = ELBOW + (COIL - ELBOW) * 0.45
lower_b = COIL + Vector((0, -0.03, 0.075))
cylinder_between(lower_a, lower_mid, R_TUBE, "shaft")
cylinder_between(lower_mid - (COIL - ELBOW).normalized() * 0.02, lower_mid + (COIL - ELBOW).normalized() * 0.03, 0.0175, "knob", 16)
cylinder_between(lower_mid, lower_b, R_TUBE * 0.8, "shaft")

# Horquilla de la bobina
fork_top = lower_b
cylinder_between(fork_top, COIL + Vector((0, 0, 0.022)), 0.011, "black", 12)
cylinder_between(COIL + Vector((-0.022, 0, 0.022)), COIL + Vector((0.022, 0, 0.022)), 0.010, "knob", 12)

# Bobina: elipse con 4 ventanas (como la de referencia)
bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=1, depth=0.022, location=COIL)
coil = bpy.context.active_object
coil.scale = (0.125, 0.145, 1)
bpy.ops.object.transform_apply(scale=True)
bev = coil.modifiers.new("bevel", "BEVEL"); bev.width = 0.006; bev.segments = 2; bev.limit_method = "ANGLE"
apply_all(coil)
for ang in (45, 135, 225, 315):
    a = math.radians(ang)
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.032, depth=0.06,
                                        location=COIL + Vector((math.cos(a) * 0.062, math.sin(a) * 0.074, 0)))
    hole = bpy.context.active_object
    hole.scale = (1, 1.15, 1)
    boo = coil.modifiers.new("hole", "BOOLEAN"); boo.operation = "DIFFERENCE"; boo.object = hole
    bpy.context.view_layer.objects.active = coil
    bpy.ops.object.modifier_apply(modifier=boo.name)
    bpy.data.objects.remove(hole)
finish(coil, "black")

# Apoyabrazos: media caña en el color del cuerpo y correa negra
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.052, depth=0.11, end_fill_type="NOTHING",
                                    location=CUFF, rotation=(math.radians(90), 0, 0))
cuff = bpy.context.active_object
bm = bmesh.new(); bm.from_mesh(cuff.data)
for v in [v for v in bm.verts if (cuff.matrix_world @ v.co).z > CUFF.z + 0.012]:
    bm.verts.remove(v)
bm.to_mesh(cuff.data); bm.free()
sol = cuff.modifiers.new("solid", "SOLIDIFY"); sol.thickness = 0.006
apply_all(cuff)
finish(cuff, "body")
box(CUFF + Vector((0, 0.0, 0.02)), (0.11, 0.035, 0.006), "black", bevel=0.002)

# ---------------------------------------------------------------- unir en un solo objeto
for o in bpy.context.scene.objects:
    o.select_set(o in parts)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
det = bpy.context.active_object
det.name = "metal_detector"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))

# UV para todo (la pantalla ya trae la suya del plano); prelight blanco-grisáceo de día y de noche
mesh = det.data
for name, val in (("day", 0.85), ("night", 0.55)):
    attr = mesh.color_attributes.new(name, "BYTE_COLOR", "CORNER")
    for d in attr.data:
        d.color = (val, val, val, 1.0)
det.dff.day_cols = True
det.dff.night_cols = True
det.dff.uv_map2 = False

tri = sum(len(p.vertices) - 2 for p in mesh.polygons)
print(f"[detector] vértices={len(mesh.vertices)} triángulos≈{tri} materiales={len(mesh.materials)}")

# ---------------------------------------------------------------- exportación
models = os.path.join(RES, "models")
os.makedirs(models, exist_ok=True)

def set_colors(tier, linear):
    """DragonFF escribe en el DFF el Base Color tal cual (255 * valor): para exportar va en sRGB
    (el color que pinta GTA); en el .blend queda en lineal para Cycles."""
    cols = dict(FIXED, body=tier["body"], accent=tier["accent"], shaft=tier["shaft"])
    for key, c in cols.items():
        v = srgb_to_lin(c) if linear else tuple(c)
        MAT[key].node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*v, 1)
        MAT[key].diffuse_color = (*v, 1)

def drop_empty_image_nodes():
    """El exportador abre PrincipledBSDFWrapper con is_readonly=False y crea un nodo de imagen vacío
    enlazado al Base Color de cada material: se quitan (si no, el render sale rosa y el TXD falla)."""
    for m in bpy.data.materials:
        if not m.node_tree:
            continue
        for node in [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image is None]:
            m.node_tree.nodes.remove(node)

for n, t in TIERS.items():
    MAT["shaft"].node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.9 if n == 5 else 0.6
    set_colors(t, linear=False)
    for o in scene.objects: o.select_set(o == det)
    bpy.context.view_layer.objects.active = det
    path = os.path.join(models, f"detector_{n}.dff")
    bpy.ops.export_dff.scene(filepath=path, directory=models, only_selected=True, export_coll=False,
                             export_version="0x36003")
    drop_empty_image_nodes()
    print(f"[detector] DFF {path} ({os.path.getsize(path)} bytes)")
set_colors(TIERS[4], linear=True)   # el .blend queda con los colores del de referencia (amarillo)

from DragonFF.ops import txd_exporter
txd_exporter.txd_exporter.mass_export = False
txd_exporter.txd_exporter.only_used_textures = True
txd_exporter.txd_exporter.version = 0x36003
txd_exporter.txd_exporter.path = models
txd_exporter.txd_exporter.export_txd(os.path.join(models, "detector.txd"))
print("[detector] TXD", os.path.getsize(os.path.join(models, "detector.txd")), "bytes")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(RES, "tools", "detector.blend"))
print("[detector] listo")
