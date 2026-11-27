"""
rp_train / tools/build_metro_pole.py

Modela en Blender el poste de metro de las estaciones (estilo Metro de Santiago: aro plateado con tres
rombos rojos facetados, horquilla oscura, poste gris y letrero con el nombre de la estación debajo) y
exporta, con el addon DragonFF (GPL, github.com/Parik27/DragonFF; no está en el repo):
  - models/metro_pole_<nodo>.dff  (uno por estación, con su nombre en el letrero; nodos de TRAIN.STATION_NAMES)
  - models/metro_pole.txd         (texturas de 128 px compartidas: pintura, acero, rojo, letrero, reflejo)
  - models/metro_pole.col         (colisión compartida: poste, letrero y logo)
  - tools/metro_pole.blend        (para retocar a mano)

Cómo se integra con el entorno de GTA SA (los objetos del mapa no reciben luz en tiempo real; su luz va
"horneada" en los colores de vértice, el prelight):
  - Prelight de DÍA: Cycles hornea la luz de cielo + sol + rebote del suelo (oclusión, contacto bajo el
    letrero y la horquilla) en colores de vértice, normalizados al rango de los objetos del juego.
  - Prelight de NOCHE: el resto se oscurece y el logo y las letras quedan claros (retroiluminados).
  - Luz 2DFX de noche (como las farolas del juego): ilumina el suelo y a quien pasa cerca.
  - Sin env map: en los objetos de MTA el reflejo de entorno deja la textura en blanco (probado en juego).

Uso (Blender 4.2, sin ventana):
  blender.exe --background --factory-startup --python build_metro_pole.py -- <carpeta que contiene DragonFF/> <ruta del recurso>

Ejes del modelo: origen = pie del poste a ras del suelo, +Z arriba. El letrero y el logo están en el
plano XZ y se leen igual por las dos caras (±Y), así que da igual hacia dónde se gire.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DRAGON_PARENT = argv[0] if len(argv) > 0 else ""
RES = argv[1] if len(argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Nodo de la estación (TRAIN.STATION_NAMES de shared/s_config.lua) -> texto del letrero
STATIONS = {
    331: "UNITY",
    371: "MARKET",
    597: "CRANBERRY",
    823: "YELLOW BELL",
    59:  "SOBELL",
    107: "LINDEN",
}

# ---------------------------------------------------------------- escena limpia + DragonFF
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
if DRAGON_PARENT:
    sys.path.insert(0, DRAGON_PARENT)
import DragonFF
DragonFF.register()

# ---------------------------------------------------------------- texturas (128 px, como las del juego)
rng = np.random.default_rng(1337)
TEX = 128

def noise(passes, n=TEX):
    """Ruido suave que se repite sin costuras (el desenfoque usa np.roll, que da la vuelta)."""
    a = rng.random((n, n))
    for _ in range(passes):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5
    return (a - a.min()) / (a.max() - a.min() + 1e-9)

def fbm():
    a = 0.5 * noise(14) + 0.3 * noise(5) + 0.2 * noise(1)
    return (a - a.min()) / (a.max() - a.min())

def streaks(n=TEX, vertical=True, passes=3):
    """Vetas en una dirección (acero cepillado, chorreones)."""
    line = rng.random(n)
    for _ in range(passes):
        line = (line + np.roll(line, 1) + np.roll(line, -1)) / 3
    line = (line - line.min()) / (line.max() - line.min() + 1e-9)
    return np.tile(line, (n, 1)) if vertical else np.tile(line[:, None], (1, n))

def make_image(name, rgb):
    """rgb: array (n, n, 3) en sRGB 0..1. Se guarda tal cual en el TXD."""
    n = rgb.shape[0]
    img = bpy.data.images.new(name, n, n, alpha=False)
    px = np.concatenate([np.clip(rgb, 0, 1), np.ones((n, n, 1))], axis=2).astype(np.float32)
    img.pixels.foreach_set(px.ravel())
    img.pack()
    return img

def tint(base, amount):
    return np.array(base)[None, None, :] * amount[:, :, None]

# Pintura gris oscura del poste y la horquilla: variación, rayas claras y algo de óxido
f1, f2 = fbm(), fbm()
paint = tint((0.23, 0.24, 0.26), 0.80 + 0.32 * f1)
rust = np.clip((f2 - 0.78) / 0.22, 0, 1)[:, :, None] * 0.45
paint = paint * (1 - rust) + np.array((0.33, 0.22, 0.15)) * rust
scr = rng.random((TEX, TEX)) < 0.004
paint[scr] = paint[scr] * 1.7
IMG_PAINT = make_image("mp_paint", paint)

# Acero cepillado del aro (vetas horizontales) con mugre suave
steel = tint((0.74, 0.75, 0.76), (0.86 + 0.16 * streaks(vertical=False, passes=1)) * (0.88 + 0.16 * fbm()))
IMG_STEEL = make_image("mp_steel", steel)

# Rojo del logo: esmalte con poca variación
IMG_RED = make_image("mp_red", tint((0.82, 0.07, 0.14), 0.90 + 0.13 * fbm()))

# Letrero: gris azulado con chorreones verticales y bordes de mugre del ruido
plate = tint((0.23, 0.26, 0.30), (0.84 + 0.24 * fbm()) * (0.93 + 0.09 * streaks(vertical=True)))
IMG_PLATE = make_image("mp_plate", plate)


# ---------------------------------------------------------------- materiales
# Con textura: Base Color blanco (DragonFF escribe 255 * Base Color en el DFF y el color va en la textura).
# Sin metálico: no existe en GTA y el horneado de luz difusa lo daría negro.
def make_mat(name, color=(1, 1, 1), image=None, rough=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = 0.0
    m.diffuse_color = (*color, 1)
    if image:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        m.node_tree.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    return m

MAT = {
    "pole":   make_mat("mp_pole",   image=IMG_PAINT, rough=0.6),
    "cradle": make_mat("mp_cradle", image=IMG_PAINT, rough=0.5),
    "plate":  make_mat("mp_plate",  image=IMG_PLATE, rough=0.7),
    "ring":   make_mat("mp_ring",   image=IMG_STEEL, rough=0.3),
    "red":    make_mat("mp_red",    image=IMG_RED,   rough=0.35),
    "letter": make_mat("mp_letter", color=(0.93, 0.93, 0.90), rough=0.4),
}
GLOW = {"mp_red", "mp_letter"}      # retroiluminados de noche

# ---------------------------------------------------------------- utilidades de modelado
parts = []

def finish(obj, mat, smooth=True):
    obj.data.materials.clear()
    obj.data.materials.append(MAT[mat])
    for poly in obj.data.polygons:
        poly.use_smooth = smooth
    parts.append(obj)
    return obj

def mesh_obj(name, bm, mat, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    scene.collection.objects.link(obj)
    return finish(obj, mat, smooth)

def cylinder(a, b, radius, mat, verts=16):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=d.length, location=(a + b) / 2)
    obj = bpy.context.active_object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return finish(obj, mat)

def box(center, size, mat, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width, mod.segments, mod.limit_method = bevel, 1, "NONE"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, mat, smooth=False)

def sphere(center, radius, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=radius, location=center)
    return finish(bpy.context.active_object, mat)

def ellipse_ring(name, cz, rx, rz, half_w, half_d, mat, a0=0.0, a1=2 * math.pi, segs=48, sides=8):
    """Tubo que sigue una elipse en el plano XZ (centro (0, 0, cz)). Sección elíptica: half_w hacia fuera
    del aro y half_d de fondo (eje Y). Entre a0 y a1 (radianes); si no da la vuelta completa, con tapas."""
    closed = abs((a1 - a0) - 2 * math.pi) < 1e-6
    n = segs if closed else segs + 1
    bm = bmesh.new()
    rings = []
    for i in range(n):
        t = a0 + (a1 - a0) * i / segs
        px, pz = rx * math.cos(t), rz * math.sin(t)
        nx, nz = math.cos(t) / rx, math.sin(t) / rz            # normal de la elipse
        l = math.hypot(nx, nz); nx, nz = nx / l, nz / l
        ring = []
        for j in range(sides):
            a = 2 * math.pi * j / sides
            w, d = half_w * math.cos(a), half_d * math.sin(a)
            ring.append(bm.verts.new((px + nx * w, d, cz + pz + nz * w)))
        rings.append(ring)
    for i in range(n if closed else n - 1):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for j in range(sides):
            bm.faces.new((r0[j], r0[(j + 1) % sides], r1[(j + 1) % sides], r1[j]))
    if not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, mat)

def diamond(name, cx, cz, half_w, half_h, half_d, bulge, mat):
    """Rombo facetado (como el logo real): canto de grosor 2 * half_d y cada cara levantada en una punta
    central (bulge), que da cuatro facetas con luz distinta."""
    pts = [(cx + half_w, cz), (cx, cz + half_h), (cx - half_w, cz), (cx, cz - half_h)]
    bm = bmesh.new()
    front = [bm.verts.new((x, -half_d, z)) for x, z in pts]
    back = [bm.verts.new((x, half_d, z)) for x, z in pts]
    tip_f = bm.verts.new((cx, -half_d - bulge, cz))
    tip_b = bm.verts.new((cx, half_d + bulge, cz))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((front[i], front[j], tip_f))
        bm.faces.new((back[j], back[i], tip_b))
        bm.faces.new((front[j], front[i], back[i], back[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, mat, smooth=False)

# ---------------------------------------------------------------- geometría común (metros)
LOGO_Z = 3.80                       # centro del aro
RING_RX, RING_RZ = 0.62, 0.50       # aro plateado (algo más ancho que alto, como el real)
CRADLE_RX, CRADLE_RZ = 0.78, 0.66   # horquilla oscura (media elipse por debajo del aro)
POLE_TOP = LOGO_Z - CRADLE_RZ       # el poste llega al fondo de la horquilla
PLATE_Z, PLATE_W, PLATE_H, PLATE_D = 2.05, 1.55, 0.62, 0.20   # el poste queda dentro del letrero

# Pie (placa con pernos) y poste
cylinder((0, 0, 0), (0, 0, 0.05), 0.20, "pole", 16)
cylinder((0, 0, 0.05), (0, 0, 0.13), 0.11, "cradle", 16)
for k in range(4):
    a = math.radians(45 + 90 * k)
    cylinder((math.cos(a) * 0.15, math.sin(a) * 0.15, 0.05), (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.08), 0.018, "cradle", 6)
cylinder((0, 0, 0.13), (0, 0, POLE_TOP + 0.04), 0.075, "pole", 16)
# Abrazaderas del letrero
for dz in (-PLATE_H / 2 - 0.05, PLATE_H / 2 + 0.05):
    cylinder((0, 0, PLATE_Z + dz - 0.03), (0, 0, PLATE_Z + dz + 0.03), 0.095, "cradle", 16)

# Letrero (el texto se añade por estación)
box((0, 0, PLATE_Z), (PLATE_W, PLATE_D, PLATE_H), "plate", bevel=0.02)

# Horquilla: media elipse por debajo, con los ejes que la unen al aro y remates en las puntas
ellipse_ring("cradle", LOGO_Z, CRADLE_RX, CRADLE_RZ, 0.035, 0.05, "cradle", math.pi, 2 * math.pi, segs=28, sides=8)
for s in (-1, 1):
    cylinder((s * (RING_RX - 0.02), 0, LOGO_Z), (s * (CRADLE_RX + 0.05), 0, LOGO_Z), 0.03, "cradle", 8)
    sphere((s * (CRADLE_RX + 0.07), 0, LOGO_Z), 0.045, "cradle")

# Aro plateado (banda: más fondo que grosor, como el del logo)
ellipse_ring("ring", LOGO_Z, RING_RX, RING_RZ, 0.06, 0.095, "ring", segs=48, sides=8)

# Tres rombos rojos facetados que se tocan por las puntas
for i, cx in enumerate((-0.31, 0.0, 0.31)):
    diamond(f"diamond{i}", cx, LOGO_Z, 0.165, 0.285, 0.05 if i != 1 else 0.055, 0.035, "red")

# Unir lo común en un objeto y proyectar UV de caja (las texturas son ruido que se repite)
for o in scene.objects:
    o.select_set(o in parts)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
base = bpy.context.active_object
base.name = "metro_pole_base"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.cube_project(cube_size=0.8)
bpy.ops.object.mode_set(mode="OBJECT")

# ---------------------------------------------------------------- texto del letrero
# Fuentes estáticas (Bahnschrift es variable y sus contornos solapados rompen letras como D y E)
FONT_PATHS = [r"C:\Windows\Fonts\segoeuib.ttf", r"C:\Windows\Fonts\arialbd.ttf"]
font = None
for fp in FONT_PATHS:
    if os.path.exists(fp):
        try:
            font = bpy.data.fonts.load(fp)
            break
        except Exception:
            pass

TEXT_MAX_W, TEXT_MAX_H = PLATE_W - 0.25, 0.20

def make_text(label):
    """Letras blancas planas en las dos caras del letrero (la de atrás girada para leerse bien)."""
    sides = []
    for face in (-1, 1):
        cu = bpy.data.curves.new(f"txt_{face}", "FONT")
        cu.body = label
        if font:
            cu.font = font
        cu.align_x, cu.align_y = "CENTER", "CENTER"
        cu.space_character = 1.12
        cu.size = 1.0
        cu.resolution_u = 2           # pocas subdivisiones en las curvas de las letras (ligero para el juego)
        cu.extrude = 0.0              # letras planas pegadas al letrero (una sola cara hacia fuera)
        ob = bpy.data.objects.new(f"txt_{face}", cu)
        scene.collection.objects.link(ob)
        bpy.context.view_layer.update()
        w, h = ob.dimensions.x, ob.dimensions.y
        cu.size = min(TEXT_MAX_W / w, TEXT_MAX_H / h) if w > 0 and h > 0 else 0.2
        # El texto nace en XY mirando a +Z: se pone de pie mirando a -Y (face -1) o a +Y (face 1)
        ob.rotation_euler = (math.radians(90), 0, 0 if face == -1 else math.radians(180))
        ob.location = (0, face * (PLATE_D / 2 + 0.003), PLATE_Z)
        for o in scene.objects:
            o.select_set(o == ob)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.convert(target="MESH")
        ob = bpy.context.active_object
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        ob.data.materials.clear()
        ob.data.materials.append(MAT["letter"])
        for poly in ob.data.polygons:
            poly.use_smooth = False
        sides.append(ob)
    return sides

# ---------------------------------------------------------------- luz horneada (prelight)
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 96
world = bpy.data.worlds.new("bake_sky")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.66, 0.85, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.1
sun = bpy.data.objects.new("bake_sun", bpy.data.lights.new("bake_sun", "SUN"))
sun.data.energy = 3.0
sun.data.angle = math.radians(8)
sun.rotation_euler = (math.radians(35), math.radians(20), math.radians(90))   # alto y de lado: las dos caras parejas
scene.collection.objects.link(sun)
bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "bake_ground"
gm = bpy.data.materials.new("bake_ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.30, 0.29, 0.27, 1)
ground.data.materials.append(gm)
BAKE_HELPERS = [sun, ground]

def bake_prelight(obj):
    """Día: luz difusa horneada (sin el color del material), normalizada al rango del juego.
    Noche: lo mismo apagado y azulado, con el logo y las letras claros."""
    mesh = obj.data
    day = mesh.color_attributes.new("day", "BYTE_COLOR", "CORNER")
    night = mesh.color_attributes.new("night", "BYTE_COLOR", "CORNER")
    mesh.color_attributes.active_color = day
    for o in scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"DIRECT", "INDIRECT"}, target="VERTEX_COLORS")

    n = len(mesh.loops)
    col = np.empty(n * 4, dtype=np.float32)
    day.data.foreach_get("color", col)
    col = col.reshape(n, 4)[:, :3]
    lum = col @ np.array((0.2126, 0.7152, 0.0722))
    ref = np.percentile(lum, 97) or 1.0
    l = np.clip(lum / ref, 0, 1) ** 0.85
    v = 0.24 + 0.76 * l                                    # rango típico del prelight de SA (nada negro)
    d = np.stack([v, v * 0.985, v * 0.955], axis=1)        # luz de día levemente cálida
    nt = d * np.array((0.36, 0.38, 0.46))                  # noche: apagado y azulado

    glow = np.zeros(n, dtype=bool)
    for poly in mesh.polygons:
        if mesh.materials[poly.material_index].name in GLOW:
            glow[list(poly.loop_indices)] = True
    nt[glow] = np.array((0.95, 0.93, 0.90))               # logo y letras retroiluminados

    def put(attr, rgb):
        rgba = np.concatenate([np.clip(rgb, 0, 1), np.ones((n, 1))], axis=1).astype(np.float32)
        attr.data.foreach_set("color_srgb", rgba.ravel())
    put(day, d)
    put(night, nt)
    obj.dff.day_cols = True
    obj.dff.night_cols = True
    obj.dff.uv_map2 = False

# ---------------------------------------------------------------- luz 2DFX de noche (como las farolas)
def make_night_light():
    data = bpy.data.lights.new("2dfx_light", "POINT")
    data.color = (1.0, 0.93, 0.82)
    data.energy = 0                                        # no cuenta para ningún horneado
    obj = bpy.data.objects.new("2dfx_light", data)
    obj.location = (0, 0, LOGO_Z - RING_RZ - 0.25)         # bajo el aro, encima del letrero
    obj.dff.type = "2DFX"
    obj.dff.ext_2dfx.effect = "0"
    s = data.ext_2dfx
    s.alpha = 0.6
    s.corona_far_clip = 60.0
    s.point_light_range = 6.0
    s.corona_size = 0.0
    s.shadow_size = 3.5                                    # mancha de luz en el suelo
    s.shadow_color_multiplier = 45
    s.shadow_z_distance = 12
    s.corona_tex_name = "coronastar"
    s.shadow_tex_name = "shad_exp"
    s.flag1_without_corona = True
    s.flag1_at_day = False
    s.flag1_at_night = True
    scene.collection.objects.link(obj)
    return obj

# ---------------------------------------------------------------- colisión compartida
col_coll = bpy.data.collections.new("metro_pole")
scene.collection.children.link(col_coll)
col_coll.dff.type = "CMN"

def col_box(center, half):
    e = bpy.data.objects.new("ColBox", None)
    e.empty_display_type = "CUBE"
    e.empty_display_size = 1
    e.location = center
    e.scale = half                    # DragonFF: min = location - scale, max = location + scale
    e.dff.type = "COL"
    col_coll.objects.link(e)
    return e

col_box((0, 0, POLE_TOP / 2), (0.09, 0.09, POLE_TOP / 2))
col_box((0, 0, PLATE_Z), (PLATE_W / 2, PLATE_D / 2 + 0.01, PLATE_H / 2))
col_box((0, 0, LOGO_Z - 0.06), (CRADLE_RX + 0.1, 0.09, CRADLE_RZ - 0.02))

# ---------------------------------------------------------------- exportación
models = os.path.join(RES, "models")
os.makedirs(models, exist_ok=True)

def drop_empty_image_nodes():
    """El exportador crea un nodo de imagen vacío en cada material: se quitan (memoria del proyecto)."""
    for m in bpy.data.materials:
        if m.node_tree:
            for node in [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image is None]:
                m.node_tree.nodes.remove(node)

light = make_night_light()
last = None
for node, label in STATIONS.items():
    # copia del poste + texto de esta estación, unidos en un solo objeto
    pole = base.copy()
    pole.data = base.data.copy()
    scene.collection.objects.link(pole)
    texts = make_text(label)
    for o in scene.objects:
        o.select_set(o == pole or o in texts)
    bpy.context.view_layer.objects.active = pole
    bpy.ops.object.join()
    pole = bpy.context.active_object
    pole.name = f"metro_pole_{node}"
    base.hide_render = True
    pole.hide_render = False             # la copia hereda el hide_render de la base
    if last:
        last.hide_render = True
    bake_prelight(pole)
    tri = sum(len(p.vertices) - 2 for p in pole.data.polygons)
    for o in scene.objects:
        o.select_set(o == pole or o == light)
    bpy.context.view_layer.objects.active = pole
    path = os.path.join(models, f"metro_pole_{node}.dff")
    bpy.ops.export_dff.scene(filepath=path, directory=models, only_selected=True, export_coll=False,
                             export_version="0x36003")
    drop_empty_image_nodes()
    print(f"[metro_pole] {label}: {path} ({os.path.getsize(path)} bytes, triángulos≈{tri})")
    if last:
        bpy.data.objects.remove(last)    # el .blend se queda solo con el último como referencia
    last = pole
base.hide_set(True)
last.hide_render = False
for h in BAKE_HELPERS:
    bpy.data.objects.remove(h)

from DragonFF.ops import txd_exporter, col_exporter
txd_exporter.txd_exporter.mass_export = False
txd_exporter.txd_exporter.only_used_textures = True
txd_exporter.txd_exporter.version = 0x36003
txd_exporter.txd_exporter.path = models
txd_path = os.path.join(models, "metro_pole.txd")
txd_exporter.txd_exporter.export_txd(txd_path)
print(f"[metro_pole] TXD {txd_path} ({os.path.getsize(txd_path)} bytes)")

col_path = os.path.join(models, "metro_pole.col")
col_exporter.export_col({
    "file_name": col_path, "version": 3, "collection": col_coll, "apply_transformations": True,
    "only_selected": False, "clean_mesh": True, "export_face_groups": False,
})
print(f"[metro_pole] COL {col_path} ({os.path.getsize(col_path)} bytes)")

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(RES, "tools", "metro_pole.blend"))
print("[metro_pole] listo")
