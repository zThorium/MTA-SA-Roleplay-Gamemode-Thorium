"""
rp_relojflores / tools/build_flower_clock.py

Modela en Blender el Reloj de Flores de Viña del Mar (Chile) y lo exporta para MTA con el addon DragonFF
(GPL, github.com/Parik27/DragonFF; no está en el repo). Pensado para PCs de bajos recursos (~8.600 triángulos de
cerca, 50 de lejos, TXD de ~0,6 MB):

  models/reloj_pasto.dff           loma con el césped NATIVO 'hedge2' (TXD union_las del juego, el mismo del bandejón
                                   de Unity: el cliente lo apunta con engineSetModelTXDID; no se reparte) + reloj_pasto.col
  models/reloj_flores.dff          esfera (campo rojo, centro rosado, borde de cineraria, solera), números de seto, eje,
                                   cantero "VIÑA DEL MAR" y focos (TXD propio)
  models/reloj_flores_flora.dff    matas de begonia en tarjetas cruzadas con alfa (objeto: como edificio saldría opaco)
  models/reloj_flores_lod.dff      LOD con la vista cenital del reloj en una textura de 128 px
  models/reloj_aguja_*.dff         agujas (origen = eje, apuntan a +Y = las 12, en el plano de la esfera)
  models/reloj_flores.txd          texturas propias con mipmaps, DXT1 opacas y DXT3 con alfa
  models/reloj_bounds.col          COL de solo límites para las piezas sin colisión (si no, desaparecen de cerca)
  tools/reloj_flores.blend         para retocar a mano (el pasto del juego queda como color plano);
                                   con --preview, vistas previas en la carpeta temporal (no van al repo)

Texturas de flores: RENDER cenital (Cycles) de plantas modeladas en 3D (begonias, hojas, alyssum, tagetes,
cineraria) en baldosas sin costuras; las matas son renders con fondo transparente. 512 px el rojo, el resto 256.

Luz (como los edificios de Rockstar; se crean con createBuilding y solo usan su prelight):
  - DÍA horneado con Cycles (cielo + sol + rebote, oclusión de contacto) y calibrado al bandejón vecino: ~77-178
    en el reloj y ~128-189 en el césped, con su tinte cálido (199, 178, 148). Nada de blanco quemado.
  - NOCHE = día × (0.21, 0.23, 0.30) más el abanico cálido de los tres focos y sus cristales encendidos
    (255, 240, 200), todo en el prelight: sin luces 2DFX.
  - Materiales con ambient 1, diffuse 1, specular 0.

Uso (Blender 4.2, sin ventana; lee el pasto de <GTA>/models/gta3.img para hornear y la vista previa):
  blender.exe --background --factory-startup --python build_flower_clock.py -- <carpeta que contiene DragonFF/> <ruta del recurso> [--preview] [--gta=<carpeta de GTA SA>]

Ejes: origen = centro del reloj a ras del suelo, +Y = hacia atrás (las 12); la esfera mira a -Y inclinada TILT grados.
Las medidas que usa el cliente (TILT, CENTER_Z, alturas de las agujas) se imprimen al final y deben coincidir con
shared/s_config.lua.
"""
import bpy, bmesh, math, os, sys, struct, tempfile
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DRAGON_PARENT = argv[0] if len(argv) > 0 else ""
RES = argv[1] if len(argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREVIEW = "--preview" in argv
TMP = tempfile.mkdtemp(prefix="reloj_flores_")

# ---------------------------------------------------------------- medidas (metros)
TILT = 8.0                      # inclinación de la loma y la esfera (grados; la parte de atrás más alta)
FRONT_Y = -5.0                  # borde delantero de la loma (en el plano)
FRONT_Z = 0.20                  # altura del borde delantero sobre el suelo
CENTER_Z = FRONT_Z - FRONT_Y * math.tan(math.radians(TILT))   # altura del centro de la esfera
R_FIELD = 3.95                  # campo de flores rojas
R_BORDER = 4.50                 # borde de matas claras
R_CURB = 4.68                   # solera de piedra
R_PINK = 1.00                   # centro rosado
R_NUM = 3.05                    # radio de los números
BED_Z = 0.13                    # altura de las flores sobre el plano
HAND_Z = {"hora": 0.44, "minuto": 0.51, "segundo": 0.57}       # alturas de las agujas sobre el plano
SIGN_Y, SIGN_W, SIGN_D, SIGN_TILT = 5.15, 7.8, 1.20, 22.0       # cantero "VIÑA DEL MAR"
MOUND_C, MOUND_A, MOUND_B = 0.9, 5.7, 6.0                       # loma: centro Y, semiejes X e Y (superelipse)
FLOWER_TILE = 1.0               # metros que cubre una baldosa de flores (512 px)
GROUND_Z = 0.06                 # pie del talud (justo sobre el suelo); de ahí sale el faldón que se funde

T = math.radians(TILT)
PLANE = Matrix.Translation((0, 0, CENTER_Z)) @ Matrix.Rotation(T, 4, "X")

def P(x, y, z=0.0):
    """Coordenadas del plano de la esfera -> coordenadas del modelo."""
    return PLANE @ Vector((x, y, z))

# ---------------------------------------------------------------- escena limpia + DragonFF
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
if DRAGON_PARENT:
    sys.path.insert(0, DRAGON_PARENT)
import DragonFF
DragonFF.register()
rng = np.random.default_rng(1909)

def srgb_to_lin(c):
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

# =====================================================================================================
# TEXTURAS RENDERIZADAS DE PLANTAS 3D
# =====================================================================================================
def rot(yaw, tilt):
    """Rz(yaw) · Rx(tilt) como matriz 3x3 de numpy."""
    cy, sy, ct, st = math.cos(yaw), math.sin(yaw), math.cos(tilt), math.sin(tilt)
    rz = np.array([[cy, -sy, 0], [sy, cy, 0], [0, 0, 1]])
    rx = np.array([[1, 0, 0], [0, ct, -st], [0, st, ct]])
    return rz @ rx

def proto_leaf(width=0.42, curl=0.22, droop=0.06):
    """Hoja de largo 1 hacia +Y en el plano XY: nervio central levantado, bordes caídos y punta curvada."""
    ts = [0.0, 0.2, 0.45, 0.7, 0.88, 1.0]
    V, F = [], []
    c, l, r = [], [], []
    for t in ts:
        w = width * math.sin(math.pi * min(t * 1.08, 1.0)) ** 0.75
        z = curl * t * t
        c.append(len(V)); V.append((0, t, z))
        if 0 < t < 1:
            l.append(len(V)); V.append((-w, t, z - droop * w / width))
            r.append(len(V)); V.append((w, t, z - droop * w / width))
        else:
            l.append(c[-1]); r.append(c[-1])
    for i in range(len(ts) - 1):
        for side, sgn in ((l, 1), (r, -1)):
            a, b, cc, d = c[i], side[i], side[i + 1], c[i + 1]
            tris = [(a, b, cc), (a, cc, d)] if sgn > 0 else [(a, cc, b), (a, d, cc)]
            for tri in tris:
                if len(set(tri)) == 3:
                    F.append(tri)
    return np.array(V, float), np.array(F, int), np.zeros(len(F), int)

def proto_flower(petals=5, rings=((1.0, 0.0, 0.0),), petal_w=0.55, cup=0.25, center=0.22):
    """Flor de radio 1 mirando a +Z. rings: (radio, altura, giro) de cada corona de pétalos (tagetes = varias).
    Parte 0 = pétalos, parte 1 = centro."""
    V, F, part = [], [], []
    for (rr, hz, rot0) in rings:
        for k in range(petals):
            a = rot0 + 2 * math.pi * k / petals
            da = math.pi / petals * petal_w * 1.6
            pts = [(0.0, 0.0), (0.40 * rr, -da), (0.80 * rr, -da * 0.85), (1.0 * rr, 0.0), (0.80 * rr, da * 0.85), (0.40 * rr, da)]
            base = len(V)
            for (rad, off) in pts:
                ang = a + off
                V.append((rad * math.cos(ang), rad * math.sin(ang), hz + cup * (rad / max(rr, 1e-6)) ** 2 * rr))
            for i in range(1, 5):
                F.append((base, base + i, base + i + 1)); part.append(0)
    base = len(V)
    zc = max(h for _, h, _ in rings) + cup * 0.25
    V.append((0, 0, zc + 0.05))
    for k in range(6):
        a = 2 * math.pi * k / 6
        V.append((center * math.cos(a), center * math.sin(a), zc))
    for k in range(6):
        F.append((base, base + 1 + k, base + 1 + (k + 1) % 6)); part.append(1)
    return np.array(V, float), np.array(F, int), np.array(part, int)

def proto_blade(width=0.06):
    """Brizna de pasto de largo 1 hacia +Y."""
    V = [(-width, 0, 0), (width, 0, 0), (-width * 0.5, 0.55, 0.02), (width * 0.5, 0.55, 0.02), (0, 1.0, 0.06)]
    F = [(0, 1, 3), (0, 3, 2), (2, 3, 4)]
    return np.array(V, float), np.array(F, int), np.zeros(3, int)

class Scatter:
    """Junta miles de instancias en una sola malla (numpy) con color por cara."""
    def __init__(self):
        self.V, self.F, self.C, self.n = [], [], [], 0

    def add(self, proto, pos, scale, yaw, tilt, colors):
        v, f, part = proto
        R = rot(yaw, tilt)
        vv = (v * scale) @ R.T + np.asarray(pos)
        self.V.append(vv)
        self.F.append(f + self.n)
        cols = np.array([colors[min(p, len(colors) - 1)] for p in part], float)
        self.C.append(cols)
        self.n += len(v)

    def mesh(self, name, mat):
        V = np.concatenate(self.V).astype(np.float32)
        Fa = np.concatenate(self.F).astype(np.int32)
        C = np.concatenate(self.C)
        me = bpy.data.meshes.new(name)
        me.vertices.add(len(V))
        me.vertices.foreach_set("co", V.ravel())
        me.loops.add(len(Fa) * 3)
        me.loops.foreach_set("vertex_index", Fa.ravel())
        me.polygons.add(len(Fa))
        me.polygons.foreach_set("loop_start", np.arange(0, len(Fa) * 3, 3, dtype=np.int32))
        me.update(calc_edges=True)
        attr = me.color_attributes.new("col", "FLOAT_COLOR", "FACE")
        rgba = np.concatenate([C, np.ones((len(C), 1))], axis=1).astype(np.float32)
        attr.data.foreach_set("color", rgba.ravel())
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        return ob

def plant_material(name, rough=0.55):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = "col"
    nt.links.new(a.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    return m

def flat_material(name, srgb, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*srgb_to_lin(srgb), 1)
    p.inputs["Roughness"].default_value = rough
    return m

def render_scene(name, objs, cam_loc, cam_rot, ortho, rx, ry, transparent=False, samples=40, sun_elev=58, sun_yaw=35, sky=0.9, denoise=True):
    """Renderiza objs en una escena aparte con cámara ortográfica; devuelve (h, w, 4) en orden de Blender (fila 0 abajo)."""
    scn = bpy.data.scenes.new(name)
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = samples
    scn.cycles.use_denoising = denoise         # sin albedo (materiales de emisión) el denoiser borra la textura
    scn.render.resolution_x, scn.render.resolution_y = rx, ry
    scn.render.resolution_percentage = 100
    scn.render.film_transparent = transparent
    scn.view_settings.view_transform = "Standard"
    scn.render.image_settings.file_format = "PNG"
    scn.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    w = bpy.data.worlds.new(name + "_sky")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62, 0.72, 0.92, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = sky
    scn.world = w
    sun = bpy.data.objects.new(name + "_sun", bpy.data.lights.new(name + "_sun", "SUN"))
    sun.data.energy = 3.4
    sun.data.angle = math.radians(12)
    sun.rotation_euler = (math.radians(90 - sun_elev), 0, math.radians(sun_yaw))
    scn.collection.objects.link(sun)
    cam = bpy.data.objects.new(name + "_cam", bpy.data.cameras.new(name + "_cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho
    cam.data.clip_end = 100
    cam.location = cam_loc
    cam.rotation_euler = cam_rot
    scn.collection.objects.link(cam)
    scn.camera = cam
    for o in objs:
        scn.collection.objects.link(o)
    path = os.path.join(TMP, name + ".png")
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=scn.name)
    img = bpy.data.images.load(path)
    arr = np.array(img.pixels[:], dtype=np.float32).reshape(ry, rx, 4)
    bpy.data.images.remove(img)
    for o in list(scn.collection.objects):
        if o not in objs:
            bpy.data.objects.remove(o)
    for o in objs:
        scn.collection.objects.unlink(o)
    bpy.data.scenes.remove(scn)
    return arr

def scatter_tile(sc, proto, n, tile, size, z, yaw=(0, 2 * math.pi), tilt=(0, 0.3), colors=None, margin=0.12, jitter=0.12):
    """Reparte n instancias en la baldosa [0, tile)² y repite las del borde al otro lado (sin costuras)."""
    for _ in range(n):
        x, y = rng.random() * tile, rng.random() * tile
        s = size[0] + rng.random() * (size[1] - size[0])
        zz = z[0] + rng.random() * (z[1] - z[0])
        yw = yaw[0] + rng.random() * (yaw[1] - yaw[0])
        tl = tilt[0] + rng.random() * (tilt[1] - tilt[0])
        base = colors[rng.integers(len(colors))]
        k = 1 - jitter + 2 * jitter * rng.random()
        cols = [tuple(np.clip(np.array(c) * (k if i == 0 else 1), 0, 1)) for i, c in enumerate(base)]
        for dx in (-tile, 0, tile):
            for dy in (-tile, 0, tile):
                px, py = x + dx, y + dy
                if -margin <= px <= tile + margin and -margin <= py <= tile + margin:
                    sc.add(proto, (px, py, zz), s, yw, tl, cols)

def lin(c):
    return tuple(srgb_to_lin(c))

def render_tile(name, layers, tile, res, target_lum, soil=(0.10, 0.08, 0.05)):
    """layers: lista de (proto, n, size, z, tilt, colors (sRGB; [pétalo, centro] o [hoja])). Devuelve sRGB (h, w, 3)."""
    sc = Scatter()
    for proto, n, size, z, tilt, colors in layers:
        cols = [[lin(c) for c in cc] for cc in colors]
        scatter_tile(sc, proto, n, tile, size, z, tilt=tilt, colors=cols)
    plants = sc.mesh(name + "_plants", plant_material(name + "_m"))
    bpy.ops.mesh.primitive_plane_add(size=tile * 1.6, location=(tile / 2, tile / 2, 0))
    ground = bpy.context.active_object
    scene.collection.objects.unlink(ground)
    ground.data.materials.append(flat_material(name + "_soil", soil))
    arr = render_scene(name, [plants, ground], (tile / 2, tile / 2, 3), (0, 0, 0), tile, res, res)
    bpy.data.objects.remove(plants)
    bpy.data.objects.remove(ground)
    rgb = arr[..., :3]
    lum = (rgb @ np.array((0.2126, 0.7152, 0.0722))).mean()
    rgb = np.clip(rgb * (target_lum / max(lum, 1e-4)), 0, 1)
    print(f"[reloj_flores] textura {name}: luminancia {lum:.3f} -> {target_lum}")
    return rgb

def render_clump(name, leaf_cols, flower_proto, flower_cols, n_leaf, n_flower, flower_size, w=0.36, h=0.18, res=(256, 128), leaf_shape=(0.70, 0.15)):
    """Mata vista de lado con fondo transparente para las tarjetas cruzadas. Devuelve RGBA (h, w, 4)."""
    sc = Scatter()
    leaf = proto_leaf(*leaf_shape)                # hojas redondeadas (begonia, cineraria), no lanzas
    rx, rz = w * 0.44, h * 0.62                    # mata baja y ancha (la tarjeta tiene el mismo 2:1 que la textura)
    for _ in range(n_leaf):
        d = rng.normal(size=3); d[2] = abs(d[2]) * 0.9 + 0.05; d /= np.linalg.norm(d)
        u = rng.random() ** 0.4
        pos = (d[0] * rx * u, d[1] * rx * u * 0.6, d[2] * rz * u)
        yw = math.atan2(-d[0], d[1] if abs(d[1]) > 1e-3 else 1e-3)
        c = [lin(np.array(leaf_cols[rng.integers(len(leaf_cols))]) * (0.85 + 0.3 * rng.random()))]
        sc.add(leaf, pos, 0.045 + 0.03 * rng.random(), yw, math.radians(10 + 45 * rng.random()), c)
    for _ in range(n_flower):
        d = rng.normal(size=3); d[2] = abs(d[2]) * 2.2 + 0.7; d /= np.linalg.norm(d)      # flores arriba
        u = 0.85 + 0.2 * rng.random()
        pos = (d[0] * rx * u, d[1] * rx * u * 0.6, d[2] * rz * u)
        yw = math.atan2(-d[0], d[1] if abs(d[1]) > 1e-3 else 1e-3)
        fc = flower_cols[rng.integers(len(flower_cols))]
        c = [lin(np.array(fc[0]) * (0.88 + 0.24 * rng.random())), lin(fc[1])]
        s = flower_size[0] + rng.random() * (flower_size[1] - flower_size[0])
        sc.add(flower_proto, pos, s, yw, -math.radians(8 + 30 * (1 - d[2])), c)
    plants = sc.mesh(name + "_plants", plant_material(name + "_m"))
    # cámara 30° por encima: se ven las caras de las flores, como al mirar el cantero de pie
    arr = render_scene(name, [plants], (0, -2 * math.cos(math.radians(30)), h * 0.42 + 2 * math.sin(math.radians(30))),
                       (math.radians(60), 0, 0), w, res[0], res[1], transparent=True,
                       sun_elev=50, sun_yaw=-20)
    bpy.data.objects.remove(plants)
    rgba = arr.copy()
    a = np.clip((rgba[..., 3] - 0.5) * 3 + 0.5, 0, 1)          # canto definido (alpha test del juego)
    rgba[..., 3] = a
    return rgba

LEAF = proto_leaf()
LEAF_SMALL = proto_leaf(0.5, 0.15)
BEGONIA = proto_flower(5, petal_w=0.62, cup=0.22, center=0.2)
ALYSSUM = proto_flower(5, petal_w=0.7, cup=0.1, center=0.25)
MARIGOLD = proto_flower(9, rings=((1.0, 0.0, 0.0), (0.75, 0.12, 0.35), (0.48, 0.24, 0.7)), petal_w=0.8, cup=0.3, center=0.15)
BLADE = proto_blade()

GREEN_DARK = [(0.10, 0.22, 0.06), (0.14, 0.28, 0.08), (0.08, 0.17, 0.05), (0.18, 0.30, 0.09)]
UP = (0, 0.35)                     # inclinación de flores mirando arriba

TEX = {}
# Campo rojo: begonias rojas sobre su follaje oscuro
TEX["rf_red"] = render_tile("rf_red", [
    (LEAF, 900, (0.030, 0.055), (0.00, 0.05), (0.1, 0.7), [[c] for c in GREEN_DARK]),
    (BEGONIA, 1500, (0.018, 0.028), (0.055, 0.085), UP,
     [[(0.86, 0.04, 0.06), (0.98, 0.80, 0.20)], [(0.74, 0.02, 0.05), (0.98, 0.80, 0.20)], [(0.93, 0.12, 0.10), (0.98, 0.80, 0.20)]]),
], FLOWER_TILE, 512, 0.24)
# Centro rosado: begonias rosadas
TEX["rf_pink"] = render_tile("rf_pink", [
    (LEAF, 900, (0.030, 0.055), (0.00, 0.05), (0.1, 0.7), [[c] for c in GREEN_DARK]),
    (BEGONIA, 1250, (0.018, 0.028), (0.055, 0.085), UP,
     [[(0.97, 0.45, 0.70), (0.98, 0.85, 0.30)], [(0.90, 0.28, 0.58), (0.98, 0.85, 0.30)], [(0.99, 0.62, 0.80), (0.98, 0.85, 0.30)]]),
], FLOWER_TILE, 256, 0.40)
# Borde: cineraria plateada con alyssum blanco
TEX["rf_border"] = render_tile("rf_border", [
    (LEAF, 1300, (0.035, 0.06), (0.00, 0.06), (0.1, 0.8), [[(0.68, 0.74, 0.66)], [(0.60, 0.66, 0.58)], [(0.74, 0.78, 0.70)]]),
    (ALYSSUM, 1400, (0.006, 0.010), (0.05, 0.08), UP, [[(0.98, 0.98, 0.95), (0.95, 0.85, 0.40)], [(0.96, 0.94, 0.86), (0.95, 0.85, 0.40)]]),
], FLOWER_TILE, 256, 0.62)
# Seto de los números: alternanthera verde lima muy tupida
TEX["rf_hedge"] = render_tile("rf_hedge", [
    (LEAF_SMALL, 4200, (0.016, 0.026), (0.00, 0.07), (0.2, 0.9),
     [[(0.50, 0.70, 0.12)], [(0.42, 0.62, 0.10)], [(0.58, 0.76, 0.16)], [(0.34, 0.52, 0.08)]]),
], FLOWER_TILE, 256, 0.48)
# Letras: tagetes amarillos
TEX["rf_yellow"] = render_tile("rf_yellow", [
    (LEAF, 800, (0.030, 0.050), (0.00, 0.05), (0.1, 0.7), [[c] for c in GREEN_DARK]),
    (MARIGOLD, 900, (0.020, 0.030), (0.055, 0.085), UP,
     [[(0.99, 0.84, 0.08), (0.90, 0.55, 0.05)], [(0.98, 0.72, 0.05), (0.85, 0.45, 0.04)], [(1.0, 0.90, 0.25), (0.90, 0.55, 0.05)]]),
], FLOWER_TILE, 256, 0.55)
# Fondo del letrero: follaje verde oscuro
TEX["rf_dark"] = render_tile("rf_dark", [
    (LEAF, 2200, (0.025, 0.045), (0.00, 0.06), (0.1, 0.8), [[(0.08, 0.20, 0.06)], [(0.11, 0.25, 0.07)], [(0.06, 0.15, 0.05)]]),
], FLOWER_TILE, 256, 0.13)

# Matas de las tarjetas (vista lateral, con alfa)
TEX["rf_clump_red"] = render_clump("rf_clump_red", [(0.16, 0.32, 0.09), (0.20, 0.38, 0.11)], BEGONIA,
                                   [[(0.86, 0.04, 0.06), (0.98, 0.8, 0.2)], [(0.74, 0.02, 0.05), (0.98, 0.8, 0.2)]], 90, 260, (0.024, 0.032))
TEX["rf_clump_pink"] = render_clump("rf_clump_pink", [(0.16, 0.32, 0.09), (0.20, 0.38, 0.11)], BEGONIA,
                                    [[(0.97, 0.45, 0.70), (0.98, 0.85, 0.3)], [(0.90, 0.28, 0.58), (0.98, 0.85, 0.3)]], 90, 260, (0.024, 0.032))

# Procedurales sencillas: piedra, pintura y metal (256 px)
def noise(passes, n=256):
    a = rng.random((n, n))
    for _ in range(passes):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5
    return (a - a.min()) / (a.max() - a.min() + 1e-9)

def fbm():
    a = 0.5 * noise(28) + 0.3 * noise(8) + 0.2 * noise(2)
    return (a - a.min()) / (a.max() - a.min())

def tint(base, amount):
    return np.array(base)[None, None, :] * amount[:, :, None]

f1, f2 = fbm(), fbm()
stone = tint((0.70, 0.67, 0.61), 0.82 + 0.25 * f1)
stone = stone * (1 - 0.18 * np.clip((f2 - 0.6) / 0.4, 0, 1))[..., None]
TEX["rf_stone"] = stone
TEX["rf_paint"] = tint((0.95, 0.95, 0.93), 0.94 + 0.06 * fbm())
TEX["rf_metal"] = tint((0.16, 0.17, 0.18), 0.8 + 0.3 * fbm())

IMAGES = {}
def make_image(name, arr):
    """arr (h, w, 3|4) sRGB en orden de Blender."""
    h, w = arr.shape[:2]
    if arr.shape[2] == 3:
        arr = np.concatenate([arr, np.ones((h, w, 1))], axis=2)
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(np.clip(arr, 0, 1).astype(np.float32).ravel())
    img.pack()
    IMAGES[name] = (img, arr)
    return img

for k, a in TEX.items():
    make_image(k, a)

# ---------------------------------------------------------------- pasto NATIVO del juego (no se reparte)
# El césped del bandejón de Unity es 'hedge2' (TXD union_las, el del suelo BTOLAND2_LAS 4821): una repetición cada ~1,4 m
# y prelight de día cálido ~(185, 170, 150). El DFF del pasto solo guarda el NOMBRE: el cliente lo apunta a ese TXD con
# engineSetModelTXDID. La imagen se lee del juego solo para hornear y para la vista previa; nunca va al TXD ni al .blend.
GTA_DIR = next((a.split("=", 1)[1] for a in argv if a.startswith("--gta=")), r"C:\Users\fabia\Documents\Gta San Andreas")
NATIVE_GRASS, NATIVE_GRASS_TXD = "hedge2", "union_las.txd"   # ojo: "sjmhoodlawn41" es una losa gris, no pasto

def game_texture(txd_file, tex_name):
    """RGB (h, w, 3) sRGB en orden de Blender, sacado de models/gta3.img; None si no está el juego."""
    try:
        from DragonFF.gtaLib import txd as gtxd_r
        with open(os.path.join(GTA_DIR, "models", "gta3.img"), "rb") as f:
            f.read(4)
            n = struct.unpack("<I", f.read(4))[0]
            for _ in range(n):
                off, s1, s2, nm = struct.unpack("<IHH24s", f.read(32))
                if nm.split(b"\0")[0].decode().lower() == txd_file:
                    f.seek(off * 2048)
                    data = f.read(max(s1, s2) * 2048)
                    break
            else:
                return None
        path = os.path.join(TMP, txd_file)
        open(path, "wb").write(data)
        t = gtxd_r.txd()
        t.load_file(path)
        for tn in t.native_textures:
            if tn.name.lower() == tex_name.lower():
                a = np.frombuffer(bytes(tn.to_rgba(0)), np.uint8).reshape(tn.height, tn.width, 4)
                return a[::-1, :, :3].astype(np.float32) / 255
    except Exception as e:
        print("[reloj_flores] no se pudo leer la textura del juego:", e)
    return None

GRASS_RGB = game_texture(NATIVE_GRASS_TXD, NATIVE_GRASS)
if GRASS_RGB is None:
    GRASS_RGB = np.ones((8, 8, 3), np.float32) * np.array((0.38, 0.40, 0.22), np.float32)
GRASS_MEAN = GRASS_RGB.reshape(-1, 3).mean(0)
GRASS_IMG = bpy.data.images.new(NATIVE_GRASS, GRASS_RGB.shape[1], GRASS_RGB.shape[0], alpha=True)
GRASS_IMG.pixels.foreach_set(np.concatenate([GRASS_RGB, np.ones(GRASS_RGB.shape[:2] + (1,), np.float32)], 2).ravel())
GRASS_TILE = 1.4                # metros por repetición, como el césped vecino

# ---------------------------------------------------------------- materiales (ambient 1, diffuse 1, specular 0)
def make_mat(name, image_name, alpha=False, image=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (1, 1, 1, 1)
    p.inputs["Roughness"].default_value = 0.85
    p.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image or IMAGES[image_name][0]
    nt.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    if alpha:
        nt.links.new(tex.outputs["Alpha"], p.inputs["Alpha"])
        m.blend_method = "CLIP"
    m.dff.ambient, m.dff.diffuse, m.dff.specular = 1.0, 1.0, 0.0
    return m

MAT = {k: make_mat(k, "rf_" + k) for k in ("red", "pink", "border", "hedge", "yellow", "dark", "stone", "paint", "metal")}
MAT["grass"] = make_mat("grass", None, image=GRASS_IMG)
for k in ("clump_red", "clump_pink"):
    MAT[k] = make_mat(k, "rf_" + k, alpha=True)
LAMP_GLASS = "paint"            # el cristal de los focos usa la pintura (encendido de noche)

# =====================================================================================================
# GEOMETRÍA
# =====================================================================================================
parts, flora_parts, grass_parts = [], [], []

def add_mesh(name, verts, faces, uvs, mat, smooth=True, collect=None, alphas=None):
    """verts: coordenadas del modelo; uvs: (u, v) por vértice; alphas: alfa de vértice opcional (atributo 'a')."""
    bm = bmesh.new()
    bv = [bm.verts.new(v) for v in verts]
    uvl = bm.loops.layers.uv.new("UVMap")
    for f in faces:
        try:
            face = bm.faces.new([bv[i] for i in f])
        except ValueError:
            continue
        face.smooth = smooth
        for loop, vi in zip(face.loops, f):        # los BMVert nuevos aún no tienen índice: va por posición
            loop[uvl].uv = uvs[vi]
    me = bpy.data.meshes.new(name)
    bm.verts.index_update()
    bm.to_mesh(me)
    bm.free()
    if alphas is not None:
        at = me.attributes.new("a", "FLOAT", "POINT")
        at.data.foreach_set("value", np.array(alphas, np.float32))
    obj = bpy.data.objects.new(name, me)
    scene.collection.objects.link(obj)
    obj.data.materials.append(MAT[mat])
    (parts if collect is None else collect).append(obj)
    return obj

def fix_normals(obj, up=True):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    if up:
        for f in bm.faces:
            if f.normal.z < 0:
                f.normal_flip()
    else:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()

def bump(x, y, amp, f=1.0, seed=0.0):
    return amp * (0.5 * math.sin(f * 2.1 * x + seed) * math.cos(f * 1.7 * y - seed)
                  + 0.3 * math.sin(f * 4.3 * x + 1.3 * y + seed * 2) + 0.2 * math.cos(f * 5.9 * y - 0.7 * x))

def annulus(name, r0, r1, mat, height, segs=96, rings=4, uv_scale=FLOWER_TILE, a0=0.0, a1=2 * math.pi):
    closed = abs((a1 - a0) - 2 * math.pi) < 1e-6
    n = segs if closed else segs + 1
    verts, uvs, faces = [], [], []
    for i in range(rings + 1):
        r = r0 + (r1 - r0) * i / rings
        for j in range(n):
            a = a0 + (a1 - a0) * j / segs
            x, y = r * math.cos(a), r * math.sin(a)
            verts.append(P(x, y, height(x, y, r, a)))
            uvs.append((x / uv_scale, y / uv_scale))
    for i in range(rings):
        for j in range(n if closed else n - 1):
            j2 = (j + 1) % n
            faces.append((i * n + j, i * n + j2, (i + 1) * n + j2, (i + 1) * n + j))
    obj = add_mesh(name, verts, faces, uvs, mat)
    fix_normals(obj)
    return obj

def disk(name, r, mat, height, segs=64, rings=6, uv_scale=FLOWER_TILE):
    verts, uvs, faces = [P(0, 0, height(0, 0, 0, 0))], [(0, 0)], []
    for i in range(1, rings + 1):
        rr = r * i / rings
        for j in range(segs):
            a = 2 * math.pi * j / segs
            x, y = rr * math.cos(a), rr * math.sin(a)
            verts.append(P(x, y, height(x, y, rr, a)))
            uvs.append((x / uv_scale, y / uv_scale))
    for j in range(segs):
        faces.append((0, 1 + j, 1 + (j + 1) % segs))
    for i in range(rings - 1):
        b0, b1 = 1 + i * segs, 1 + (i + 1) * segs
        for j in range(segs):
            j2 = (j + 1) % segs
            faces.append((b0 + j, b0 + j2, b1 + j2, b1 + j))
    obj = add_mesh(name, verts, faces, uvs, mat)
    fix_normals(obj)
    return obj

def tube_wall(name, r, z0, z1, mat, segs=96, uv_scale=0.8, rows=2):
    """Pared de cilindro perpendicular al plano (filas intermedias para el degradado del prelight)."""
    verts, uvs, faces = [], [], []
    for j in range(segs + 1):
        a = 2 * math.pi * j / segs
        x, y = abs(r) * math.cos(a), abs(r) * math.sin(a)
        for i in range(rows + 1):
            z = z0 + (z1 - z0) * i / rows
            verts.append(P(x, y, z))
            uvs.append((abs(r) * a / uv_scale, z / uv_scale))
    R1 = rows + 1
    for j in range(segs):
        for i in range(rows):
            a, b, c, d = j * R1 + i, (j + 1) * R1 + i, (j + 1) * R1 + i + 1, j * R1 + i + 1
            faces.append((a, b, c, d) if r > 0 else (d, c, b, a))
    return add_mesh(name, verts, faces, uvs, mat)

def cylinder_plane(name, x, y, r, z0, z1, mat, segs=16):
    verts, uvs, faces = [], [], []
    for j in range(segs):
        a = 2 * math.pi * j / segs
        for z in (z0, z1):
            verts.append(P(x + r * math.cos(a), y + r * math.sin(a), z))
            uvs.append((j / segs, z))
    for j in range(segs):
        j2 = (j + 1) % segs
        faces.append((2 * j, 2 * j2, 2 * j2 + 1, 2 * j + 1))
    faces.append(tuple(2 * j + 1 for j in range(segs)))
    faces.append(tuple(2 * j for j in reversed(range(segs))))
    obj = add_mesh(name, verts, faces, uvs, mat, smooth=True)
    fix_normals(obj, up=False)
    return obj

# ---------------------------------------------------------------- loma de pasto
def mound_edge(a):
    c, s = math.cos(a), math.sin(a)
    n = 3.2
    k = (abs(c) / MOUND_A) ** n + (abs(s) / MOUND_B) ** n
    rr = k ** (-1 / n)
    return rr * c, MOUND_C + rr * s

def outward(top):
    o = Vector((top.x, top.y - MOUND_C * math.cos(T), 0))
    return o.normalized() if o.length > 1e-6 else Vector((0, -1, 0))

MOUND_SEGS = 40                      # PCs de bajos recursos: lo justo para el degradado
GU = lambda w: (w.x / GRASS_TILE, w.y / GRASS_TILE)
verts, uvs, faces = [P(0, MOUND_C, -0.02)], [GU(P(0, MOUND_C))], []
RINGS = 4
for i in range(1, RINGS + 1):
    t = i / RINGS
    for j in range(MOUND_SEGS):
        ex, ey = mound_edge(2 * math.pi * j / MOUND_SEGS)
        w = P(ex * t, MOUND_C + (ey - MOUND_C) * t, -0.02)
        verts.append(w)
        uvs.append(GU(w))
for j in range(MOUND_SEGS):
    faces.append((0, 1 + j, 1 + (j + 1) % MOUND_SEGS))
for i in range(RINGS - 1):
    b0, b1 = 1 + i * MOUND_SEGS, 1 + (i + 1) * MOUND_SEGS
    for j in range(MOUND_SEGS):
        j2 = (j + 1) % MOUND_SEGS
        faces.append((b0 + j, b0 + j2, b1 + j2, b1 + j))
# Talud con hombro redondeado hasta el pie (GROUND_Z) y luego bajo tierra (tapa huecos si el suelo baja)
edge0 = 1 + (RINGS - 1) * MOUND_SEGS
TOPS = [verts[edge0 + j].copy() for j in range(MOUND_SEGS)]
def skirt_point(top, frac_run, frac_drop):
    drop = top.z - GROUND_Z
    run = 0.5 + max(drop, 0) * 1.9
    o = outward(top)
    return Vector((top.x + o.x * run * frac_run, top.y + o.y * run * frac_run, top.z - drop * frac_drop))
FOOT = [skirt_point(t, 1.0, 1.0) for t in TOPS]
rows = [[skirt_point(t, fr, fd) for t in TOPS] for fr, fd in ((0.45, 0.35), (1.0, 1.0))]
rows.append([Vector((f.x + outward(f).x * 0.35, f.y + outward(f).y * 0.35, -0.45)) for f in FOOT])
for k, row in enumerate(rows):
    b0 = edge0 if k == 0 else len(verts) - MOUND_SEGS
    for w in row:
        verts.append(w)
        uvs.append(GU(w))
    b1 = len(verts) - MOUND_SEGS
    for j in range(MOUND_SEGS):
        j2 = (j + 1) % MOUND_SEGS
        faces.append((b0 + j, b0 + j2, b1 + j2, b1 + j))
mound = add_mesh("mound", verts, faces, uvs, "grass", collect=grass_parts)   # modelo aparte: TXD del juego
fix_normals(mound)

# ---------------------------------------------------------------- esfera de flores
SEGS = 64
annulus("curb_top", R_BORDER, R_CURB, "stone", lambda x, y, r, a: 0.22, segs=SEGS, rings=1, uv_scale=0.8)
tube_wall("curb_out", R_CURB, -0.08, 0.22, "stone", segs=SEGS)
tube_wall("curb_in", -R_BORDER, 0.10, 0.22, "stone", segs=SEGS, rows=1)

def border_h(x, y, r, a):
    m = (r - R_FIELD) / (R_BORDER - R_FIELD)
    across = math.sin(math.pi * min(max(m, 0), 1)) ** 0.7
    along = 0.55 + 0.45 * abs(math.cos(a * 18))
    return 0.15 + 0.17 * across * along + bump(x, y, 0.015, 3)
annulus("border", R_FIELD - 0.02, R_BORDER + 0.02, "border", border_h, segs=SEGS * 3, rings=2)

def field_h(x, y, r, a):
    return BED_Z + 0.05 * (1 - r / R_FIELD) + bump(x, y, 0.035, 2.2, 0.7)
annulus("field", R_PINK - 0.02, R_FIELD, "red", field_h, segs=SEGS, rings=7)

def pink_h(x, y, r, a):
    return BED_Z + 0.07 + 0.14 * (1 - (r / R_PINK) ** 2) + bump(x, y, 0.02, 3)
disk("pink", R_PINK, "pink", pink_h, segs=32, rings=4)
annulus("hub_ring", 0.18, 0.42, "hedge", lambda x, y, r, a: BED_Z + 0.25 + 0.04 * math.sin(math.pi * (r - 0.18) / 0.24),
        segs=16, rings=1, uv_scale=0.6)

cylinder_plane("axle", 0, 0, 0.07, BED_Z + 0.15, HAND_Z["segundo"] + 0.06, "paint", 12)
cylinder_plane("cap", 0, 0, 0.15, HAND_Z["segundo"] + 0.05, HAND_Z["segundo"] + 0.10, "paint", 20)

# ---------------------------------------------------------------- textos (números y letrero)
FONT_PATHS = [r"C:\Windows\Fonts\segoeuib.ttf", r"C:\Windows\Fonts\arialbd.ttf"]
font = None
for fp in FONT_PATHS:
    if os.path.exists(fp):
        try:
            font = bpy.data.fonts.load(fp)
            break
        except Exception:
            pass

def text_mesh(label, size, extrude, bevel, mat, matrix, uv_scale=FLOWER_TILE, max_w=None):
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = label
    if font:
        cu.font = font
    cu.align_x, cu.align_y = "CENTER", "CENTER"
    cu.size = size
    cu.space_character = 1.05
    cu.resolution_u = 2               # curvas de las letras con pocos segmentos
    cu.extrude = extrude
    cu.bevel_depth = bevel
    cu.bevel_resolution = 1
    ob = bpy.data.objects.new("txt_" + label, cu)
    scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    if max_w and ob.dimensions.x > max_w:
        cu.size = size * max_w / ob.dimensions.x
        bpy.context.view_layer.update()
    dims = ob.dimensions.copy()
    for o in scene.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.active_object
    me = ob.data
    for v in me.vertices:
        v.co.z += extrude + bevel
    uvl = me.uv_layers[0] if len(me.uv_layers) else me.uv_layers.new(name="UVMap")   # la que se exporta
    # caja: la cara de arriba se proyecta desde arriba y los cantos de lado (sin estirar la textura)
    for poly in me.polygons:
        nx, ny, nz = poly.normal
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if abs(nz) > 0.6:
                uv = (co.x, co.y)
            elif abs(nx) > abs(ny):
                uv = (co.y, co.z)
            else:
                uv = (co.x, co.z)
            uvl.data[li].uv = (uv[0] / uv_scale + 0.37 * len(label), uv[1] / uv_scale)
    ob.matrix_world = matrix
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.data.materials.clear()
    ob.data.materials.append(MAT[mat])
    for poly in ob.data.polygons:
        poly.use_smooth = True
    parts.append(ob)
    return ob, dims

NUMBERS = []   # (x, y, medio ancho, medio alto) en el plano, para no tapar los números con matas
for n in range(1, 13):
    a = math.radians(90 - 30 * n)
    x, y = R_NUM * math.cos(a), R_NUM * math.sin(a)
    _, dims = text_mesh(str(n), 1.30, 0.09, 0.0, "hedge", PLANE @ Matrix.Translation((x, y, BED_Z - 0.05)), max_w=1.35)
    NUMBERS.append((x, y, dims.x / 2 + 0.12, dims.y / 2 + 0.12))

SIGN_FRONT = SIGN_Y - SIGN_D / 2
SIGN_L = SIGN_D / math.cos(math.radians(SIGN_TILT))
SIGN_FRAME = PLANE @ Matrix.Translation((0, SIGN_FRONT, 0.16)) @ Matrix.Rotation(math.radians(SIGN_TILT), 4, "X")

def S(x, y, z=0.0):
    return SIGN_FRAME @ Vector((x, y, z))

hw = SIGN_W / 2
rim = 0.10
top_out = [S(-hw - rim, -rim), S(hw + rim, -rim), S(hw + rim, SIGN_L + rim), S(-hw - rim, SIGN_L + rim)]
bottom = []
for p in top_out:
    inv = PLANE.inverted() @ p
    bottom.append(P(inv.x, inv.y, -0.10))
verts = top_out + [S(-hw - rim, -rim, 0.05), S(hw + rim, -rim, 0.05), S(hw + rim, SIGN_L + rim, 0.05),
                   S(-hw - rim, SIGN_L + rim, 0.05)] + bottom
uvs = [(v.x / 0.8, v.z / 0.8 + v.y / 0.8) for v in verts]
faces = [(8, 9, 1, 0), (9, 10, 2, 1), (10, 11, 3, 2), (11, 8, 0, 3),
         (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
sign_stone = add_mesh("sign_stone", verts, faces, uvs, "stone", smooth=False)
fix_normals(sign_stone, up=False)
# subdividir las paredes largas: el prelight vive en los vértices y sin cortes no hay degradado
bm = bmesh.new(); bm.from_mesh(sign_stone.data)
bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if e.calc_length() > 0.6], cuts=3, use_grid_fill=True)
bm.to_mesh(sign_stone.data); bm.free()

def sign_bed(name, y0, y1, mat, amp=0.03):
    vs, us, fs = [], [], []
    nx, ny = 16, 3
    for i in range(ny + 1):
        yy = y0 + (y1 - y0) * i / ny
        for j in range(nx + 1):
            xx = -hw + SIGN_W * j / nx
            vs.append(S(xx, yy, 0.03 + bump(xx, yy, amp, 2.5, 1.1)))
            us.append((xx / FLOWER_TILE, yy / FLOWER_TILE))
    for i in range(ny):
        for j in range(nx):
            a = i * (nx + 1) + j
            fs.append((a, a + 1, a + nx + 2, a + nx + 1))
    o = add_mesh(name, vs, fs, us, mat)
    fix_normals(o)
    return o
STRIP = 0.24
sign_bed("sign_front", 0, STRIP, "red")
sign_bed("sign_mid", STRIP, SIGN_L - STRIP, "dark", 0.02)
sign_bed("sign_back", SIGN_L - STRIP, SIGN_L, "red")
frame = [S(-hw - rim, -rim, 0.05), S(hw + rim, -rim, 0.05), S(hw + rim, SIGN_L + rim, 0.05), S(-hw - rim, SIGN_L + rim, 0.05),
         S(-hw, 0, 0.05), S(hw, 0, 0.05), S(hw, SIGN_L, 0.05), S(-hw, SIGN_L, 0.05)]
o = add_mesh("sign_frame", frame, [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)],
             [(v.x / 0.8, v.y / 0.8) for v in frame], "stone", smooth=False)
fix_normals(o)
text_mesh("VIÑA DEL MAR", 1.05, 0.06, 0.0, "yellow",
          SIGN_FRAME @ Matrix.Translation((0, SIGN_L / 2, 0.03)), uv_scale=0.6, max_w=SIGN_W - 0.6)

# ---------------------------------------------------------------- focos de suelo
LAMPS = []
for deg in (-122, -90, -58):
    a = math.radians(deg)
    x, y = (R_CURB + 0.55) * math.cos(a), (R_CURB + 0.55) * math.sin(a)
    cylinder_plane(f"lamp_post{deg}", x, y, 0.05, -0.05, 0.22, "metal", 8)
    yaw = math.atan2(-y, -x)
    M = PLANE @ Matrix.Translation((x, y, 0.30)) @ Matrix.Rotation(yaw - math.pi / 2, 4, "Z") @ Matrix.Rotation(math.radians(-35), 4, "X")
    bpy.ops.mesh.primitive_cube_add(size=1)
    box = bpy.context.active_object
    box.matrix_world = M @ Matrix.Diagonal((0.26, 0.20, 0.16, 1))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    box.data.materials.append(MAT["metal"])
    parts.append(box)
    bpy.ops.mesh.primitive_plane_add(size=1)
    glass = bpy.context.active_object
    glass.matrix_world = M @ Matrix.Translation((0, 0.101, 0)) @ Matrix.Rotation(math.radians(-90), 4, "X") @ Matrix.Diagonal((0.20, 0.12, 1, 1))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    glass.data.materials.append(MAT["paint"])
    for poly in glass.data.polygons:
        if poly.normal.dot(M.to_3x3() @ Vector((0, 1, 0))) < 0:
            poly.flip()
    parts.append(glass)
    LAMPS.append(M @ Vector((0, 0.15, 0)))

# ---------------------------------------------------------------- matas en tarjetas cruzadas (modelo flora)
def clump_cards(mat, positions, w, h, height_fn, sink=0.04):
    """Dos tarjetas cruzadas por mata, perpendiculares al plano y de doble cara (el juego no dibuja la de atrás)."""
    vs, us, fs, al = [], [], [], []
    for (x, y) in positions:
        yaw = rng.random() * math.pi
        s = 0.85 + 0.3 * rng.random()
        z0 = height_fn(x, y) - sink
        for k in range(2):
            a = yaw + k * math.pi / 2
            dx, dy = math.cos(a) * w * s / 2, math.sin(a) * w * s / 2
            quad = [P(x - dx, y - dy, z0), P(x + dx, y + dy, z0), P(x + dx, y + dy, z0 + h * s), P(x - dx, y - dy, z0 + h * s)]
            b = len(vs)
            vs += quad + quad                   # la cara de atrás necesita sus propios vértices
            us += [(0, 0), (1, 0), (1, 1), (0, 1)] * 2
            fs += [(b, b + 1, b + 2, b + 3), (b + 7, b + 6, b + 5, b + 4)]
    return add_mesh("cards_" + mat, vs, fs, us, mat, smooth=False, collect=flora_parts)

def jitter_grid(test, step):
    out = []
    for x in np.arange(-R_BORDER, R_BORDER, step):
        for y in np.arange(-R_BORDER, R_BORDER, step):
            px, py = x + (rng.random() - 0.5) * step * 0.8, y + (rng.random() - 0.5) * step * 0.8
            if test(px, py):
                out.append((px, py))
    return out

def free_of_numbers(x, y):
    for nx, ny, hx, hy in NUMBERS:
        if abs(x - nx) < hx and abs(y - ny) < hy:
            return False
    return True

red_pos = jitter_grid(lambda x, y: R_PINK + 0.15 < math.hypot(x, y) < R_FIELD - 0.18 and free_of_numbers(x, y), 0.46)
pink_pos = jitter_grid(lambda x, y: 0.5 < math.hypot(x, y) < R_PINK - 0.12, 0.40)
clump_cards("clump_red", red_pos, 0.30, 0.15, lambda x, y: field_h(x, y, math.hypot(x, y), 0))
clump_cards("clump_pink", pink_pos, 0.28, 0.14, lambda x, y: pink_h(x, y, math.hypot(x, y), 0))
print(f"[reloj_flores] matas: {len(red_pos)} rojas, {len(pink_pos)} rosadas (el borde lleva relieve propio, sin tarjetas)")

# ---------------------------------------------------------------- unir
def join(objs, name):
    for o in scene.objects:
        o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob

clock = join(parts, "reloj_flores")
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0005)
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))     # aristas duras por debajo de 35°, como los edificios
grass = join(grass_parts, "reloj_pasto")                        # TXD del juego: va en un modelo aparte
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
flora = join(flora_parts, "reloj_flores_flora")

# ---------------------------------------------------------------- agujas
def hand(name, half_outline, thickness=0.045, discs=()):
    pts = [(x, y) for x, y in half_outline] + [(-x, y) for x, y in reversed(half_outline) if x > 1e-6]
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((x, y, 0)) for x, y in pts])
    for y0, r in discs:
        ring = [bm.verts.new((r * math.cos(2 * math.pi * k / 20), y0 + r * math.sin(2 * math.pi * k / 20), 0)) for k in range(20)]
        bm.faces.new(ring)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z += thickness
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
    uvl = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for loop in f.loops:
            loop[uvl].uv = (loop.vert.co.x / 0.5, loop.vert.co.y / 0.5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    ob.data.materials.append(MAT["paint"])
    for poly in ob.data.polygons:
        poly.use_smooth = False
    return ob

HANDS = {
    "hora": hand("reloj_aguja_hora", [(0, -0.62), (0.13, -0.56), (0.19, -0.42), (0.09, -0.26), (0.075, 0),
                                       (0.075, 1.42), (0.24, 1.62), (0.27, 1.80), (0.15, 1.92), (0.05, 2.02), (0, 2.25)],
                 discs=[(0, 0.22)]),
    "minuto": hand("reloj_aguja_minuto", [(0, -0.82), (0.11, -0.74), (0.13, -0.58), (0.06, -0.44), (0.055, 0),
                                           (0.05, 2.85), (0.17, 2.92), (0.06, 3.10), (0, 3.34)],
                   discs=[(0, 0.18)]),
    "segundo": hand("reloj_aguja_segundo", [(0, -0.98), (0.022, -0.9), (0.022, 0), (0.018, 3.2), (0, 3.52)],
                    thickness=0.035, discs=[(-0.78, 0.13), (0, 0.11)]),
}

# =====================================================================================================
# PRELIGHT (vertex paint horneado y calibrado al vecindario de Unity)
# =====================================================================================================
DAY_MIN, DAY_MAX = 0.30, 0.70          # ~77..178: como el bandejón (luces 175-200 cálidas, sombras 70-100)
GRASS_MIN, GRASS_MAX = 0.50, 0.74      # césped ~128..189 (hedge2 del bandejón: 166-199 al sol)
WARM = np.array((1.0, 0.92, 0.80))     # el prelight de día de esa manzana es cálido (199, 178, 148)
NIGHT_MUL = np.array((0.21, 0.23, 0.30))            # noche = día × esto: ~ (40, 45, 60) en las luces
NIGHT_LIT = np.array((1.0, 0.94, 0.78))             # ~ (255, 240, 200): cristales de los focos
OBJECT_DIM = 0.85                      # flora y agujas son objetos (algo de luz dinámica): prelight un poco más bajo

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 64
world = bpy.data.worlds.new("bake_sky")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.66, 0.85, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
sun = bpy.data.objects.new("bake_sun", bpy.data.lights.new("bake_sun", "SUN"))
sun.data.energy = 3.2
sun.data.angle = math.radians(6)
sun.rotation_euler = (math.radians(40), math.radians(15), math.radians(200))
scene.collection.objects.link(sun)
bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0.0))
ground = bpy.context.active_object
ground.name = "bake_ground"
gm = bpy.data.materials.new("bake_ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.10, 0.12, 0.05, 1)
ground.data.materials.append(gm)
BAKE_HELPERS = [sun, ground]

def put(attr, rgb, alpha=None):
    n = len(rgb)
    a = np.ones((n, 1)) if alpha is None else np.asarray(alpha, float).reshape(n, 1)
    rgba = np.concatenate([np.clip(rgb, 0, 1), a], axis=1).astype(np.float32)
    attr.data.foreach_set("color_srgb", rgba.ravel())

def loop_data(mesh):
    co = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    vi = np.empty(len(mesh.loops), dtype=np.int32)
    mesh.loops.foreach_get("vertex_index", vi)
    nrm = np.empty(len(mesh.loops) * 3, dtype=np.float32)
    mesh.corner_normals.foreach_get("vector", nrm)
    return co[vi], nrm.reshape(-1, 3), vi

def lamp_fan(pos, nrm):
    add = np.zeros(len(pos))
    for L in LAMPS:
        to = np.array(L) - pos
        dist = np.linalg.norm(to, axis=1) + 1e-6
        facing = np.clip((nrm * (to / dist[:, None])).sum(1), 0, 1) * 0.8 + 0.2
        add += facing / (1 + (dist / 3.4) ** 2)
    return np.clip(add, 0, 1)

def night_from(d, pos, nrm, lamps=True):
    """Noche: el día apagado y azulado; cerca de los focos, su abanico cálido (la luz va en el prelight, sin 2DFX)."""
    base = d * NIGHT_MUL[None, :]
    if not lamps:
        return base
    lit = lamp_fan(pos, nrm)[:, None] * 0.85
    return base * (1 - lit) + NIGHT_LIT[None, :] * lit * (0.45 + 0.4 * d / DAY_MAX)

def finish_prelight(obj, l, lo=DAY_MIN, hi=DAY_MAX, glow_mats=(), scale=1.0, lamps=True):
    mesh = obj.data
    day = mesh.color_attributes.get("day") or mesh.color_attributes.new("day", "BYTE_COLOR", "CORNER")
    night = mesh.color_attributes.get("night") or mesh.color_attributes.new("night", "BYTE_COLOR", "CORNER")
    pos, nrm, _ = loop_data(mesh)
    v = (lo + (hi - lo) * l) * scale
    d = v[:, None] * WARM[None, :]
    nt = night_from(d, pos, nrm, lamps)
    if glow_mats:
        glow = np.zeros(len(l), dtype=bool)
        for poly in mesh.polygons:
            if mesh.materials[poly.material_index].name in glow_mats:
                glow[list(poly.loop_indices)] = True
        nt[glow] = NIGHT_LIT
    put(day, d)
    put(night, nt)
    obj.dff.day_cols = True
    obj.dff.night_cols = True
    obj.dff.uv_map2 = False

def bake_raw(obj):
    """Luminancia horneada (cielo + sol + rebote) por esquina, sin normalizar."""
    mesh = obj.data
    mesh.color_attributes.new("day", "BYTE_COLOR", "CORNER")
    mesh.color_attributes.new("night", "BYTE_COLOR", "CORNER")
    mesh.color_attributes.active_color = mesh.color_attributes["day"]
    for o in scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"DIRECT", "INDIRECT"}, target="VERTEX_COLORS")
    n = len(mesh.loops)
    col = np.empty(n * 4, dtype=np.float32)
    mesh.color_attributes["day"].data.foreach_get("color", col)
    return col.reshape(n, 4)[:, :3] @ np.array((0.2126, 0.7152, 0.0722))

for h in HANDS.values():
    h.hide_render = True
# reloj y pasto se hornean juntos (uno hace sombra al otro); las matas con alfa también dan sombra de contacto
raw_clock, raw_grass = bake_raw(clock), bake_raw(grass)
REF_LO, REF_HI = np.percentile(raw_clock, 2), np.percentile(raw_clock, 96)    # UNA referencia para todas las piezas
def norm(raw):
    return np.clip((raw - REF_LO) / max(REF_HI - REF_LO, 1e-6), 0, 1) ** 0.85
finish_prelight(clock, norm(raw_clock), glow_mats=("paint",))
# el césped con su propia referencia: arriba de la loma queda como el césped vecino al sol
g_lo, g_hi = np.percentile(raw_grass, 2), np.percentile(raw_grass, 85)
finish_prelight(grass, np.clip((raw_grass - g_lo) / max(g_hi - g_lo, 1e-6), 0, 1) ** 0.7, GRASS_MIN, GRASS_MAX)

# Flora: tarjetas más oscuras en la base (oclusión) y claras arriba
fm = flora.data
pos, nrm, vi = loop_data(fm)
rel = np.array([(PLANE.inverted() @ Vector(p)).z for p in pos])
finish_prelight(flora, np.clip(0.55 + (rel - BED_Z) / 0.40, 0.45, 0.95), scale=OBJECT_DIM)

# Agujas: blanco parejo, la cara de arriba más clara
for h in HANDS.values():
    pos, nrm, _ = loop_data(h.data)
    finish_prelight(h, 0.55 + 0.45 * np.clip(nrm[:, 2], 0, 1), scale=OBJECT_DIM)

# ---------------------------------------------------------------- colisión
# Malla de pasto (loma) y piedra (cantero): va en el modelo del pasto
col_coll = bpy.data.collections.new("reloj_pasto")
scene.collection.children.link(col_coll)
col_coll.dff.type = "CMN"

def col_mesh(name, verts, faces, surface):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    m = bpy.data.materials.new("col_" + name)
    m.dff.col_mat_index = surface
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob.dff.type = "COL"
    col_coll.objects.link(ob)
    return ob

CS = 24
cv, cf = [P(0, MOUND_C, BED_Z)], []
for j in range(CS):
    ex, ey = mound_edge(2 * math.pi * j / CS)
    cv.append(P(ex, ey, 0.0))
for j in range(CS):
    cf.append((0, 1 + j, 1 + (j + 1) % CS))
for j in range(CS):
    cv.append(skirt_point(cv[1 + j], 1.0, 1.0) - Vector((0, 0, 0.3)))
for j in range(CS):
    j2 = (j + 1) % CS
    cf.append((1 + j, 1 + j2, 1 + CS + j2, 1 + CS + j))
col_mesh("col_mound", cv, cf, 9)                    # GRASS_SHORT_LUSH
sv = top_out + bottom
sf = [(0, 1, 2, 3), (4, 5, 1, 0), (5, 6, 2, 1), (6, 7, 3, 2), (7, 4, 0, 3)]
col_mesh("col_sign", sv, sf, 4)                     # PAVEMENT

# Solo límites (reloj, flora, agujas y LOD): sin él, la pieza hereda el COL de 1 m y desaparece de cerca
bounds_coll = bpy.data.collections.new("reloj_bounds")
scene.collection.children.link(bounds_coll)
bounds_coll.dff.type = "CMN"
be = bpy.data.objects.new("ColBox", None)
be.empty_display_type = "CUBE"
be.location = (0, 2.0, 1.5)
be.scale = (9.5, 11.0, 3.0)                         # min (-9.5, -9, -1.5), max (9.5, 13, 4.5)
be.dff.type = "COL"
bounds_coll.objects.link(be)

# =====================================================================================================
# EXPORTACIÓN
# =====================================================================================================
models = os.path.join(RES, "models")
os.makedirs(models, exist_ok=True)

def drop_empty_image_nodes():
    for m in bpy.data.materials:
        if m.node_tree:
            for node in [nd for nd in m.node_tree.nodes if nd.type == "TEX_IMAGE" and nd.image is None]:
                m.node_tree.nodes.remove(node)

def export(objs, fname):
    for o in scene.objects:
        o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(models, fname)
    bpy.ops.export_dff.scene(filepath=path, directory=models, only_selected=True, export_coll=False,
                             export_version="0x36003")
    drop_empty_image_nodes()
    tri = sum(len(p.vertices) - 2 for o in objs if o.type == "MESH" for p in o.data.polygons)
    print(f"[reloj_flores] {fname}: {os.path.getsize(path)} bytes, triángulos≈{tri}")
    return tri

TRIS = export([clock], "reloj_flores.dff") + export([grass], "reloj_pasto.dff") + export([flora], "reloj_flores_flora.dff")
for key, h in HANDS.items():
    TRIS += export([h], f"reloj_aguja_{key}.dff")
print(f"[reloj_flores] total de cerca: {TRIS} triángulos")

# ---------------------------------------------------------------- vista con la luz horneada (LOD y previews)
def bake_view_materials(objs, strength):
    """Materiales de vista: textura × prelight de día (emisión), con el alfa de la textura."""
    done = set()
    for ob in objs:
        for m in ob.data.materials:
            if m.name in done:
                continue
            done.add(m.name)
            nt = m.node_tree
            tex = [nd for nd in nt.nodes if nd.type == "TEX_IMAGE"][0]
            vc = nt.nodes.new("ShaderNodeVertexColor")
            vc.layer_name = "day"
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(tex.outputs["Color"], mix.inputs["A"])
            nt.links.new(vc.outputs["Color"], mix.inputs["B"])
            em = nt.nodes.new("ShaderNodeEmission")
            em.inputs["Strength"].default_value = strength
            nt.links.new(mix.outputs["Result"], em.inputs["Color"])
            tr = nt.nodes.new("ShaderNodeBsdfTransparent")
            ms = nt.nodes.new("ShaderNodeMixShader")
            nt.links.new(tex.outputs["Alpha"], ms.inputs["Fac"])
            nt.links.new(tr.outputs["BSDF"], ms.inputs[1])
            nt.links.new(em.outputs["Emission"], ms.inputs[2])
            nt.links.new(ms.outputs["Shader"], nt.nodes["Material Output"].inputs["Surface"])
            m.blend_method = "BLEND"

for hlp in BAKE_HELPERS:
    bpy.data.objects.remove(hlp)
VIEW = 1.0 / DAY_MAX            # en la vista, el prelight más alto se ve como luz plena
bake_view_materials([clock, grass, flora] + list(HANDS.values()), VIEW)

# ---------------------------------------------------------------- LOD: vista cenital en una textura + malla simple
# Se renderiza solo el reloj (sin el pasto del juego, que no se reparte) sobre el tono medio del pasto.
allv = [v.co for o in (clock, grass) for v in o.data.vertices]
xs, ys = [v.x for v in allv], [v.y for v in allv]
LOD_CX, LOD_CY = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
LOD_S = max(max(xs) - min(xs), max(ys) - min(ys)) + 0.5
scene.collection.objects.unlink(clock)
lod_img = render_scene("rf_lod", [clock], (LOD_CX, LOD_CY, 20), (0, 0, 0), LOD_S, 128, 128, transparent=True, samples=24, sky=0.0, denoise=False)
scene.collection.objects.link(clock)
grass_bg = GRASS_MEAN * WARM * GRASS_MAX * 0.95 * VIEW
lod_rgb = lod_img[..., :3] * lod_img[..., 3:4] + grass_bg[None, None, :] * (1 - lod_img[..., 3:4])
LOD_DAY = 0.62
make_image("rf_lod", np.clip(lod_rgb * DAY_MAX / LOD_DAY, 0, 1))   # en juego: textura × LOD_DAY = lo que se ve de cerca
MAT["lod"] = make_mat("lod", "rf_lod")

lv, lf = [], []
LS = 16
lv.append(P(0, MOUND_C, 0.10))
for j in range(LS):
    ex, ey = mound_edge(2 * math.pi * j / LS)
    lv.append(P(ex, ey, 0.0))
for j in range(LS):
    lv.append(skirt_point(lv[1 + j], 1.0, 1.0))
for j in range(LS):
    lf.append((0, 1 + j, 1 + (j + 1) % LS))
for j in range(LS):
    j2 = (j + 1) % LS
    lf.append((1 + j, 1 + j2, 1 + LS + j2, 1 + LS + j))
sv0 = len(lv)
lv += [S(-hw - rim, -rim, 0.05), S(hw + rim, -rim, 0.05), S(hw + rim, SIGN_L + rim, 0.05), S(-hw - rim, SIGN_L + rim, 0.05)]
lf.append((sv0, sv0 + 1, sv0 + 2, sv0 + 3))
luv = [((v.x - LOD_CX) / LOD_S + 0.5, (v.y - LOD_CY) / LOD_S + 0.5) for v in lv]
lod = add_mesh("reloj_flores_lod", lv, lf, luv, "lod", smooth=True, collect=[])
fix_normals(lod)
finish_prelight(lod, np.ones(len(lod.data.loops)), LOD_DAY, LOD_DAY, lamps=False)
export([lod], "reloj_flores_lod.dff")

# ---------------------------------------------------------------- TXD con mipmaps y compresión DXT
def mip_chain(arr, alpha):
    """arr sRGB (h, w, 4) en orden de Blender. Promedio 2x2 (premultiplicado si hay alfa) y alfa con la misma cobertura."""
    levels = [arr]
    cov0 = (arr[..., 3] > 0.5).mean() if alpha else None
    while levels[-1].shape[0] > 1 or levels[-1].shape[1] > 1:
        a = levels[-1]
        h, w = a.shape[:2]
        a = a[: max(h - h % 2, 1), : max(w - w % 2, 1)]
        if h > 1 and w > 1:
            if alpha:
                pm = a[..., :3] * a[..., 3:4]
                s = (pm[0::2, 0::2] + pm[1::2, 0::2] + pm[0::2, 1::2] + pm[1::2, 1::2]) / 4
                al = (a[0::2, 0::2, 3] + a[1::2, 0::2, 3] + a[0::2, 1::2, 3] + a[1::2, 1::2, 3]) / 4
                rgb = s / np.maximum(al[..., None], 1e-4)
                lo, hi = 0.0, 4.0                       # escala del alfa que conserva la cobertura del nivel 0
                for _ in range(16):
                    mid = (lo + hi) / 2
                    if (np.clip(al * mid, 0, 1) > 0.5).mean() < cov0: lo = mid
                    else: hi = mid
                al = np.clip(al * (lo + hi) / 2, 0, 1)
                nxt = np.concatenate([rgb, al[..., None]], axis=2)
            else:
                nxt = (a[0::2, 0::2] + a[1::2, 0::2] + a[0::2, 1::2] + a[1::2, 1::2]) / 4
        else:
            nxt = a.reshape(1, 1, 4) if a.size == 4 else a.mean(axis=(0, 1), keepdims=True)
        levels.append(nxt)
    return levels

def to565(c):
    q = np.round(c * np.array((31, 63, 31))).astype(np.int64)
    return (q[..., 0] << 11) | (q[..., 1] << 5) | q[..., 2], q * np.array((255 / 31, 255 / 63, 255 / 31)) / 255

def dxt_encode(img, with_alpha):
    """img (h, w, 4) sRGB 0..1, fila 0 ARRIBA. DXT1 (opaco) o DXT3 (alfa explícito de 4 bits)."""
    h, w = img.shape[:2]
    ph, pw = max(4, (h + 3) // 4 * 4), max(4, (w + 3) // 4 * 4)
    if (ph, pw) != (h, w):
        img = np.pad(img, ((0, ph - h), (0, pw - w), (0, 0)), mode="edge")
    b = img.reshape(ph // 4, 4, pw // 4, 4, 4).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 4)
    rgb = b[..., :3]
    # extremos: eje principal de cada bloque (mejor que min/max de luminancia)
    mean = rgb.mean(1, keepdims=True)
    cen = rgb - mean
    cov = np.einsum("bki,bkj->bij", cen, cen)
    axis = np.ones((len(b), 3)) / math.sqrt(3)
    for _ in range(6):
        axis = np.einsum("bij,bj->bi", cov, axis)
        axis /= np.linalg.norm(axis, axis=1, keepdims=True) + 1e-9
    proj = np.einsum("bki,bi->bk", cen, axis)
    cmax = mean[:, 0] + axis * proj.max(1, keepdims=True)
    cmin = mean[:, 0] + axis * proj.min(1, keepdims=True)
    c0, p0 = to565(np.clip(cmax, 0, 1))
    c1, p1 = to565(np.clip(cmin, 0, 1))
    swap = c0 < c1
    c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
    p0, p1 = np.where(swap[:, None], p1, p0), np.where(swap[:, None], p0, p1)
    pal = np.stack([p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3], axis=1)
    d = ((rgb[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(-1)
    idx = d.argmin(-1)
    idx = np.where((c0 == c1)[:, None], 0, idx)
    bits = (idx.astype(np.uint64) << (2 * np.arange(16, dtype=np.uint64))).sum(1).astype(np.uint32)
    color = np.zeros(len(b), dtype=[("c0", "<u2"), ("c1", "<u2"), ("i", "<u4")])
    color["c0"], color["c1"], color["i"] = c0, c1, bits
    if not with_alpha:
        return color.tobytes()
    a4 = np.round(b[..., 3] * 15).astype(np.uint64)
    abits = (a4 << (4 * np.arange(16, dtype=np.uint64))).sum(1)
    out = np.zeros(len(b), dtype=[("a", "<u8"), ("c0", "<u2"), ("c1", "<u2"), ("i", "<u4")])
    out["a"], out["c0"], out["c1"], out["i"] = abits, c0, c1, bits
    return out.tobytes()

from DragonFF.gtaLib import txd as gtxd
from DragonFF.gtaLib.dff import NativePlatformType

def native(name, arr, with_alpha):
    levels = mip_chain(arr, with_alpha)
    tn = gtxd.TextureNative()
    tn.platform_id = NativePlatformType.D3D9
    tn.filter_mode = 0x06                    # trilineal con mipmaps
    tn.uv_addressing = 0b00010001            # repetir en U y V
    tn.name, tn.mask = name, ""
    fmt = gtxd.RasterFormat.RASTER_4444 if with_alpha else gtxd.RasterFormat.RASTER_565
    tn.raster_format_flags = (fmt << 8) | 0x8000          # 0x8000 = tiene mipmaps
    tn.d3d_format = gtxd.D3DFormat.D3D_DXT3 if with_alpha else gtxd.D3DFormat.D3D_DXT1
    tn.width, tn.height = arr.shape[1], arr.shape[0]
    tn.depth = 16
    tn.num_levels = len(levels)
    tn.raster_type = 4
    tn.platform_properties = type("PP", (), {"alpha": with_alpha, "cube_texture": False,
                                             "auto_mipmaps": False, "compressed": True})()
    tn.palette = b""
    tn.pixels = [dxt_encode(lv[::-1].astype(np.float64), with_alpha) for lv in levels]   # TXD: fila 0 arriba
    return tn

ALPHA_TEX = {"rf_clump_red", "rf_clump_pink"}
t = gtxd.txd()
t.device_id = gtxd.DeviceType.DEVICE_D3D9
t.native_textures = [native(n, a if a.shape[2] == 4 else np.concatenate([a, np.ones(a.shape[:2] + (1,))], 2), n in ALPHA_TEX)
                     for n, (_, a) in IMAGES.items()]
txd_path = os.path.join(models, "reloj_flores.txd")
t.write_file(txd_path, 0x36003)
print(f"[reloj_flores] TXD {txd_path} ({os.path.getsize(txd_path)} bytes, {len(t.native_textures)} texturas DXT con mipmaps)")

from DragonFF.ops import col_exporter
def export_col(coll, fname):
    path = os.path.join(models, fname)
    col_exporter.export_col({
        "file_name": path, "version": 3, "collection": coll, "apply_transformations": True,
        "only_selected": False, "clean_mesh": True, "export_face_groups": False,
    })
    return path

col_path = export_col(col_coll, "reloj_pasto.col")
print(f"[reloj_flores] COL {col_path} ({os.path.getsize(col_path)} bytes)")
# Solo límites: se exporta la caja y se deja en 0 el número de cajas (byte 74) y los flags (byte 80) del COL3
bpath = export_col(bounds_coll, "reloj_bounds.col")
data = bytearray(open(bpath, "rb").read())
assert data[:4] == b"COL3", "se esperaba COL3"
data[74:76] = b"\0\0"
data[80:84] = b"\0\0\0\0"
open(bpath, "wb").write(data)
print(f"[reloj_flores] COL de límites {bpath} ({len(data)} bytes)")

# Agujas a las 10:10:30 para el .blend y la vista previa
def place_hand(obj, deg_cw, key):
    obj.matrix_world = PLANE @ Matrix.Translation((0, 0, HAND_Z[key])) @ Matrix.Rotation(-math.radians(deg_cw), 4, "Z")
    obj.hide_render = False
place_hand(HANDS["hora"], (10 + 10 / 60) * 30, "hora")
place_hand(HANDS["minuto"], 10 * 6, "minuto")
place_hand(HANDS["segundo"], 30 * 6, "segundo")
col_coll.hide_render = True
bounds_coll.hide_render = True
lod.hide_render = True

# ---------------------------------------------------------------- vistas previas (textura × prelight de día)
if PREVIEW:
    bpy.ops.mesh.primitive_plane_add(size=120, location=(0, 0, 0.0))
    g = bpy.context.active_object
    for loop in g.data.uv_layers[0].data:
        loop.uv = (loop.uv.x * 120 / GRASS_TILE, loop.uv.y * 120 / GRASS_TILE)
    gm = bpy.data.materials.new("prev_ground"); gm.use_nodes = True
    gnt = gm.node_tree
    gt = gnt.nodes.new("ShaderNodeTexImage"); gt.image = GRASS_IMG
    ge = gnt.nodes.new("ShaderNodeEmission"); ge.inputs["Strength"].default_value = 0.70 * VIEW   # prelight del bandejón
    gnt.links.new(gt.outputs["Color"], ge.inputs["Color"])
    gnt.links.new(ge.outputs["Emission"], gnt.nodes["Material Output"].inputs["Surface"])
    g.data.materials.append(gm)
    objs = [clock, grass, flora, g] + list(HANDS.values())
    for o in objs:
        if o.name in scene.collection.objects:
            scene.collection.objects.unlink(o)
    for name, loc, rotd, lens in (("preview", (0, -17, 3.2), (80, 0, 0), 30),
                                  ("preview_aire", (11, -14, 11), (53, 0, 38), 30),
                                  ("preview_cerca", (1.6, -6.2, 1.9), (68, 0, 8), 35)):
        scn = bpy.data.scenes.new(name)
        scn.render.engine = "CYCLES"; scn.cycles.samples = 24; scn.cycles.use_denoising = False
        scn.render.resolution_x, scn.render.resolution_y = 1280, 720
        scn.view_settings.view_transform = "Standard"
        w = bpy.data.worlds.new(name); w.use_nodes = True
        w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.68, 0.9, 1)
        scn.world = w
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        cam.location = loc
        cam.rotation_euler = tuple(math.radians(a) for a in rotd)
        cam.data.lens = lens
        scn.collection.objects.link(cam)
        for o in objs:
            scn.collection.objects.link(o)
        scn.camera = cam
        scn.render.filepath = os.path.join(TMP, name + ".png")       # fuera del repo: muestran el pasto del juego
        bpy.ops.render.render(write_still=True, scene=scn.name)
        print(f"[reloj_flores] vista previa {scn.render.filepath}")
        bpy.data.scenes.remove(scn)
    for o in (clock, grass, flora) + tuple(HANDS.values()):
        if o.name not in scene.collection.objects:
            scene.collection.objects.link(o)

# El .blend del repo no lleva texturas de Rockstar: el pasto queda como un color plano con el mismo nombre
GRASS_IMG.scale(8, 8)
GRASS_IMG.pixels.foreach_set(np.tile(np.array((*GRASS_MEAN, 1.0), np.float32), 64))
GRASS_IMG.pack()
lod.location.x = 40                      # en el .blend, al lado
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(RES, "tools", "reloj_flores.blend"))

print(f"[reloj_flores] TILT={TILT} CENTER_Z={CENTER_Z:.4f} HAND_Z={HAND_Z}")
print("[reloj_flores] listo")
