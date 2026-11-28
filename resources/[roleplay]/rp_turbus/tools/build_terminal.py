"""
rp_turbus / tools/build_terminal.py

Modela en Blender el Terminal Turbus de Unity Station (El Corona, Los Santos), al estilo del terminal de
Santiago: hall de vidrio con montantes blancos, losa de hormigón con franja verde y letreros «turbus»,
asientos verdes, isla central, boleterías y pantallas; marquesina en L de chapa oscura sobre pilares verdes,
andenes con solera amarilla y cajones pintados para los buses.

Exporta con el addon DragonFF (GPL, github.com/Parik27/DragonFF; no está en el repo):
  models/turbus_hall.dff      estructura del hall con texturas NATIVAS del juego (TXD railway_las)
  models/turbus_hall_x.dff    detalles del hall con texturas propias (turbus.txd)
  models/turbus_glass.dff     cristaleras (texturas propias con alpha; se dibuja al final)
  models/turbus_canopy.dff    andenes y marquesina con texturas NATIVAS (railway_las)
  models/turbus_canopy_x.dff  pilares, soleras, cajones, luces y letreros con texturas propias
  models/turbus_lod.dff       LOD para la distancia (turbus_lod.txd)
  models/turbus.txd, models/turbus_lod.txd   texturas propias (potencias de 2, con mipmaps)
  models/turbus_hall.col, models/turbus_canopy.col   colisión (cajas con superficie de SA)
  tools/terminal.blend        para retocar a mano (sin texturas de Rockstar dentro)

Texturas nativas: las piezas «nat» solo guardan el NOMBRE de la textura del juego (concretenewb256,
Bow_sub_walltiles, ws_corrugateddoor1...). En el juego el cliente apunta el modelo al TXD railway_las con
engineSetModelTXDID, así no se reparte material de Rockstar y el grano es idéntico al de la estación.

Luz horneada (prelight), calibrada con el suelo original BTOLAND2_LAS (día p90 ≈ 171,155,146):
  - Día: Cycles hornea cielo + sol + rebote (con el suelo original como molde) en colores de vértice;
    rango 75..200 gris cálido, sin blanco quemado. Las mallas van subdivididas (~2 m) para el degradado.
  - Noche: paredes gris azulado oscuro (≈ 40,45,60); vidrio, luminarias, pantallas y letreros encendidos
    (≈ 255,240,200); interior del hall y bajo la marquesina con luz de lámparas. Sin luces 2DFX (parpadean).

Uso (Blender 4.2, sin ventana):
  blender.exe --background --factory-startup --python build_terminal.py -- <carpeta que contiene DragonFF/> [<ruta del recurso>] [<carpeta ref>] [--quick]
<carpeta ref> (opcional) = DFF/TXD originales sacados con tools/extraer-img.ps1 (btoland2_las.dff,
uninstps_las01.dff, railway_las.txd, union_las.txd): sirven de molde para el horneado y para las vistas
previas (render_*.png en esa carpeta). Sin ella se hornea con un plano y las texturas nativas son grises.

Ejes: se modela en coordenadas del mundo de GTA y al exportar se resta ORIGIN (el objeto va en ORIGIN, rot 0).
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
QUICK = "--quick" in argv
argv = [a for a in argv if a != "--quick"]
DRAGON_PARENT = argv[0] if len(argv) > 0 else ""
RES = argv[1] if len(argv) > 1 and argv[1] else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = argv[2] if len(argv) > 2 else ""
if REF and not os.path.isdir(REF):
    REF = ""

# ---------------------------------------------------------------- medidas del sitio (sacadas del mapa original)
ORIGIN = Vector((1768.0, -1903.0, 12.58))   # posición del objeto en el juego (shared/s_config.lua)
G = 12.58          # baldosa original alrededor de la estación
LOT = 12.39        # asfalto del estacionamiento
FLOOR = 12.70      # piso del hall (12 cm sobre la baldosa, tapa el hueco del edificio quitado)
PLAT = 12.74       # andenes (36 cm sobre el asfalto, como un andén de buses)

HX0, HX1, HY0, HY1 = 1729.5, 1755.5, -1939.0, -1866.5     # caja de vidrio del hall
WALL_H = 8.0                                             # alto de las cristaleras
ROOF0, ROOF1 = FLOOR + WALL_H, FLOOR + WALL_H + 1.4      # losa del techo
ROOF_X0, ROOF_X1, ROOF_Y0, ROOF_Y1 = HX0 - 1.2, HX1 + 1.2, HY0 - 2.0, HY1 + 4.0
CAN0 = G + 6.4                                           # cara inferior de la marquesina
CAN1 = CAN0 + 0.45
CAN_E = (1755.5, 1782.0, -1940.0, -1893.0)               # brazo este (x0, x1, y0, y1)
CAN_N = (1755.5, 1811.0, -1893.0, -1864.5)               # brazo norte
EAST_BAYS = [-1900.0, -1908.0, -1916.0, -1924.0, -1932.0]   # centros (y) de los andenes 1..5
NORTH_BAYS = [1786.0, 1794.0, 1802.0]                       # centros (x) de los andenes 6..8

# ---------------------------------------------------------------- escena limpia + DragonFF
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
if DRAGON_PARENT:
    sys.path.insert(0, DRAGON_PARENT)
import DragonFF
DragonFF.register()
rng = np.random.default_rng(2026)

# ---------------------------------------------------------------- texturas propias (pequeñas, estilo SA)
def blur(a, passes):
    for _ in range(passes):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5
    return a

def noise(h, w, passes):
    a = blur(rng.random((h, w)), passes)
    return (a - a.min()) / (a.max() - a.min() + 1e-9)

def fbm(h, w):
    a = 0.5 * noise(h, w, 10) + 0.3 * noise(h, w, 4) + 0.2 * noise(h, w, 1)
    return (a - a.min()) / (a.max() - a.min())

def solid(h, w, rgb, var=0.05):
    n = fbm(h, w)[..., None]
    return np.clip(np.array(rgb)[None, None, :] * (1 - var + 2 * var * n), 0, 1)

IMAGES = {}

def make_image(name, rgb, alpha=None):
    """rgb: (h, w, 3) sRGB 0..1 (fila 0 = abajo, como Blender). Se guarda tal cual en el TXD."""
    h, w = rgb.shape[:2]
    a = np.ones((h, w, 1)) if alpha is None else alpha[..., None]
    img = bpy.data.images.new(name, w, h, alpha=alpha is not None)
    img.pixels.foreach_set(np.concatenate([np.clip(rgb, 0, 1), a], axis=2).astype(np.float32).ravel())
    img.pack()
    IMAGES[name] = img
    return img

GREEN = (0.42, 0.74, 0.20)        # verde Turbus
DGREEN = (0.13, 0.42, 0.16)
YELLOW = (0.96, 0.78, 0.12)

make_image("tb_green", solid(64, 64, GREEN, 0.04))
st = np.tile(blur(rng.random(64)[None, :], 2), (64, 1))[..., None]
make_image("tb_steel", np.clip(0.80 + 0.08 * (st - 0.5) + np.zeros((64, 64, 3)), 0, 1) * np.array((1.0, 1.0, 1.02)))
# cielo raso de listones grises (como el del terminal) con juntas oscuras
cl = np.full((128, 128, 3), 0.42) * np.array((1.0, 0.98, 0.95))
for y in range(0, 128, 16):
    cl[y:y + 3] *= 0.45
cl *= (0.92 + 0.16 * fbm(128, 128))[..., None]
make_image("tb_ceiling", cl)
lt = np.full((32, 32, 3), 0.97)
lt[:2], lt[-2:], lt[:, :2], lt[:, -2:] = 0.55, 0.55, 0.55, 0.55
make_image("tb_light", lt)
# asiento de plástico verde con brillo
sh = np.linspace(0.85, 1.12, 64)[:, None, None]
make_image("tb_seat", np.clip(np.array(DGREEN)[None, None, :] * 1.6 * sh * np.ones((64, 64, 3)), 0, 1))
leaf = fbm(128, 128)[..., None]
spots = (noise(128, 128, 1) > 0.62)[..., None]
make_image("tb_hedge", np.clip(np.array((0.16, 0.36, 0.10)) * (0.6 + 0.8 * leaf) + spots * 0.06, 0, 1))
grime = fbm(64, 64)[..., None]
make_image("tb_yellow", np.clip(np.array(YELLOW) * (0.88 + 0.14 * grime) - 0.06 * (grime > 0.8), 0, 1))
make_image("tb_black", solid(32, 32, (0.07, 0.075, 0.08), 0.1))
# vidrio: tinte verde-gris con un reflejo suave solo en el color; alpha parejo (0.58)
gy = np.linspace(0, 1, 64)[:, None]
gx = np.linspace(0, 1, 64)[None, :]
refl = 0.5 + 0.06 * (fbm(64, 64) - 0.5)   # sin patrón: un reflejo con dibujo se corta en cada panel
grgb = np.stack([0.30 + 0.0 * refl, 0.40 + 0.0 * refl, 0.42 + 0.0 * refl], axis=2) * (0.96 + 0.08 * refl[..., None])   # tinte verde-gris oscuro parejo
make_image("tb_glass", grgb, alpha=np.full_like(refl, 0.38))   # alpha parejo; el shader fx/glass.fx quita el corte por alfa de GTA
# LOD
make_image("tb_lod_roof", solid(16, 16, (0.62, 0.62, 0.60), 0.05))
lg = np.full((32, 32, 3), 0.22) * np.array((0.9, 1.0, 1.0))
lg[:, ::8] = 0.85
lg[::16] = 0.85
make_image("tb_lod_glass", lg)
make_image("tb_lod_dark", solid(16, 16, (0.20, 0.21, 0.22), 0.05))
make_image("tb_lod_green", solid(16, 16, GREEN, 0.02))

# ---------------------------------------------------------------- letreros (texto rasterizado con Workbench)
FONT_LOGO = r"C:\Windows\Fonts\ARLRDBD.TTF"     # redondeada, como el logo de Turbus
FONT_BOLD = r"C:\Windows\Fonts\segoeuib.ttf"
import tempfile
TMP = tempfile.mkdtemp(prefix="turbus_txt_")

def to_lin(c):
    c = np.array(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def text_image(name, w, h, bg, items):
    """items: (texto, cx, cy, alto, color, fuente, max_ancho) en fracciones de la imagen (0..1)."""
    sc = bpy.data.scenes.new("txt_" + name)
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "OBJECT"
    sc.display.render_aa = "16"
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x, sc.render.resolution_y = w * 2, h * 2
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    cam = bpy.data.objects.new("txtcam", bpy.data.cameras.new("txtcam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(w, h) / 100.0
    cam.location = (w / 200.0, h / 200.0, 10)
    sc.collection.objects.link(cam)
    sc.camera = cam
    me = bpy.data.meshes.new("txtbg")
    W, H = w / 100.0, h / 100.0
    me.from_pydata([(0, 0, 0), (W, 0, 0), (W, H, 0), (0, H, 0)], [], [(0, 1, 2, 3)])
    bgo = bpy.data.objects.new("txtbg", me)
    bgo.color = (*to_lin(bg), 1)
    sc.collection.objects.link(bgo)
    for text, cx, cy, th, col, fpath, maxw in items:
        cu = bpy.data.curves.new("t", "FONT")
        cu.body = text
        if os.path.exists(fpath):
            cu.font = bpy.data.fonts.load(fpath, check_existing=True)
        cu.align_x, cu.align_y = "CENTER", "CENTER"
        cu.size = 1.0
        ob = bpy.data.objects.new("t", cu)
        ob.color = (*to_lin(col), 1)
        sc.collection.objects.link(ob)
        dg = bpy.context.evaluated_depsgraph_get()
        dg.update()
        ev = ob.evaluated_get(dg)
        bb = [Vector(c) for c in ev.bound_box]
        tw = max(c.x for c in bb) - min(c.x for c in bb)
        tht = max(c.y for c in bb) - min(c.y for c in bb)
        s = min(th * H / max(tht, 1e-4), maxw * W / max(tw, 1e-4))
        cu.size = s
        ob.location = (cx * W, cy * H, 0.01)
    path = os.path.join(TMP, name + ".png")
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=sc.name)
    src = bpy.data.images.load(path)
    px = np.array(src.pixels[:], dtype=np.float32).reshape(h * 2, w * 2, 4)[..., :3]
    px = px.reshape(h, 2, w, 2, 3).mean(axis=(1, 3))         # reduce a la resolución final (suaviza bordes)
    bpy.data.images.remove(src)
    for o in list(sc.collection.objects):
        bpy.data.objects.remove(o)
    bpy.data.scenes.remove(sc)
    return make_image(name, px)

WHITE = (0.97, 0.97, 0.95)
text_image("tb_logo", 256, 64, GREEN, [("turbus", 0.5, 0.52, 0.62, WHITE, FONT_LOGO, 0.86)])
text_image("tb_logo_w", 256, 64, WHITE, [("turbus", 0.5, 0.52, 0.62, (0.36, 0.66, 0.16), FONT_LOGO, 0.86)])
text_image("tb_bolet", 256, 64, DGREEN, [("BOLETERÍA", 0.5, 0.5, 0.46, WHITE, FONT_BOLD, 0.88)])
text_image("tb_andenes", 256, 64, DGREEN, [("ANDENES  1 - 8  >", 0.5, 0.5, 0.42, WHITE, FONT_BOLD, 0.9)])
BOARD_ROWS = [("DESTINO", "SALE", "ANDÉN"), ("LAS VENTURAS", "08:30", "2"), ("SAN FIERRO", "09:15", "5"),
              ("ANGEL PINE", "10:00", "7"), ("BAYSIDE", "11:45", "1"), ("FORT CARSON", "12:20", "4")]
items = []
for i, (d, t, a) in enumerate(BOARD_ROWS):
    cy = 0.89 - i * 0.155
    col = (1.0, 0.80, 0.20) if i == 0 else (0.92, 0.95, 1.0)
    items += [(d, 0.30, cy, 0.10, col, FONT_BOLD, 0.52), (t, 0.70, cy, 0.10, col, FONT_BOLD, 0.2),
              (a, 0.90, cy, 0.10, col, FONT_BOLD, 0.14)]
text_image("tb_board", 256, 128, (0.04, 0.10, 0.24), items)
text_image("tb_nums", 256, 32, GREEN, [(str(i + 1), (i + 0.5) / 8, 0.5, 0.7, WHITE, FONT_BOLD, 0.1) for i in range(8)])

# ---------------------------------------------------------------- materiales
NATIVE_TXD = "railway_las"
# textura nativa -> (metros por repetición en u, en v, z donde empieza v (para muros con zócalo))
NATIVE = {
    "Bow_sub_walltiles":   (2.4, 2.4, 0.0),
    "concretenewb256":     (3.0, 3.0, 0.0),
    "Bow_Abattoir_Conc2":  (4.0, 4.0, 0.0),
    "lasunion7":         (4.0, 4.0, 0.0),
    "ws_corrugateddoor1":  (3.0, 3.0, 0.0),
    "newall1-1":           (4.0, 4.4, FLOOR),
}
ref_images = {}
if REF and os.path.exists(os.path.join(REF, NATIVE_TXD + ".txd")):
    bpy.ops.import_scene.dff(filepath=os.path.join(REF, NATIVE_TXD + ".txd"))
    for img in bpy.data.images:
        parts = img.name.split("/")
        if len(parts) >= 2 and parts[0] == NATIVE_TXD + ".txd" and parts[1] in NATIVE:
            ref_images[parts[1]] = img

def native_image(tex):
    if tex in ref_images:
        img = ref_images[tex]
        img.name = tex
        return img
    img = bpy.data.images.new(tex, 8, 8)
    img.pixels.foreach_set(np.full(8 * 8 * 4, 0.7, dtype=np.float32))
    return img

MAT, KIND, UVS, GLOW = {}, {}, {}, set()

def make_mat(key, image, kind, uv=(2.0, 2.0, 0.0), glow=False, col_surface=0):
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (1, 1, 1, 1)
    p.inputs["Roughness"].default_value = 0.8
    p.inputs["Metallic"].default_value = 0.0
    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    m.node_tree.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    if kind == "glass":
        m.node_tree.links.new(tex.outputs["Alpha"], p.inputs["Alpha"])
        m.blend_method = "BLEND"
    m["col_surface"] = col_surface
    # Propiedades de superficie de RenderWare como los edificios de SA: ambient 1 (recibe la luz ambiente del
    # timecyc), diffuse 1 y specular 0. DragonFF exporta 0.5/0.5/0.5 por defecto: con specular 0.5 las caras
    # brillan más o menos según desde dónde las mires.
    m.dff.ambient, m.dff.diffuse, m.dff.specular = 1.0, 1.0, 0.0
    MAT[key], KIND[key], UVS[key] = m, kind, uv
    if glow:
        GLOW.add(key)
    return m

for tex, uv in NATIVE.items():
    make_mat("n_" + tex, native_image(tex), "nat", uv)
for key, uv, glow in (("tb_green", (2, 2, 0), False), ("tb_steel", (1, 1, 0), False), ("tb_ceiling", (2.4, 2.4, 0), False),
                      ("tb_light", (1, 1, 0), True), ("tb_seat", (0.6, 0.6, 0), False), ("tb_hedge", (2, 2, 0), False),
                      ("tb_yellow", (1.5, 1.5, 0), False), ("tb_black", (1, 1, 0), False),
                      ("tb_logo", None, True), ("tb_logo_w", None, True), ("tb_bolet", None, True),
                      ("tb_andenes", None, True), ("tb_board", None, True), ("tb_nums", None, True)):
    make_mat(key, IMAGES[key], "x", uv, glow)
make_mat("tb_glass", IMAGES["tb_glass"], "glass", (3, 3, 0), glow=True)
for key in ("tb_lod_roof", "tb_lod_glass", "tb_lod_dark", "tb_lod_green"):
    make_mat(key, IMAGES[key], "lod", (8, 8, 0) if key != "tb_lod_glass" else (6, 8, FLOOR))
MAT_GLASS_LOD = "tb_lod_glass"

# ---------------------------------------------------------------- construcción (bmesh por pieza y tipo)
class Piece:
    """Una pieza del terminal (hall, canopy, lod). Cada cara va a la malla de su tipo de material:
    nat (texturas del juego), x (propias), glass (vidrio con alpha) o lod."""
    def __init__(self, name):
        self.name = name
        self.meshes = {}

    def _bm(self, kind):
        if kind not in self.meshes:
            bm = bmesh.new()
            self.meshes[kind] = (bm, bm.loops.layers.uv.new("UVMap"), [])
        return self.meshes[kind]

    def face(self, pts, mat, uvs=None):
        bm, uvl, mats = self._bm(KIND[mat])
        if mat not in mats:
            mats.append(mat)
        vs = [bm.verts.new(p) for p in pts]
        f = bm.faces.new(vs)
        f.material_index = mats.index(mat)
        n = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[0]))
        for i, loop in enumerate(f.loops):
            loop[uvl].uv = uvs[i] if uvs else planar_uv(Vector(pts[i]), n, mat)
        return f

    def quad(self, p0, p1, p2, p3, mat, cell=2.0, uvs=None):
        """Cuadrilátero subdividido en celdas de ~cell metros (para que la luz horneada tenga degradado).
        Orden antihorario visto desde fuera (la normal sale hacia quien mira)."""
        p0, p1, p2, p3 = map(Vector, (p0, p1, p2, p3))
        nu = max(1, round((p1 - p0).length / cell)) if cell else 1
        nv = max(1, round((p3 - p0).length / cell)) if cell else 1
        def P(i, j):
            a, b = i / nu, j / nv
            return (p0 * (1 - a) + p1 * a) * (1 - b) + (p3 * (1 - a) + p2 * a) * b
        def U(i, j):
            if not uvs:
                return None
            a, b = i / nu, j / nv
            q = [Vector(u) for u in uvs]
            return (q[0] * (1 - a) + q[1] * a) * (1 - b) + (q[3] * (1 - a) + q[2] * a) * b
        for i in range(nu):
            for j in range(nv):
                pts = [P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)]
                self.face(pts, mat, [U(i, j), U(i + 1, j), U(i + 1, j + 1), U(i, j + 1)] if uvs else None)

    def vquad(self, pa, pb, za, zb, n, mat, cell=2.0):
        """Cara vertical entre los puntos 2D pa y pb, de za a zb, mirando hacia la normal 2D n."""
        pa, pb, n = Vector((pa[0], pa[1], 0)), Vector((pb[0], pb[1], 0)), Vector((n[0], n[1], 0))
        if (pb - pa).dot(Vector((0, 0, 1)).cross(n)) < 0:
            pa, pb = pb, pa
        self.quad((pa.x, pa.y, za), (pb.x, pb.y, za), (pb.x, pb.y, zb), (pa.x, pa.y, zb), mat, cell)

    def box(self, x0, y0, z0, x1, y1, z1, mat, cell=2.0, mats=None, skip=()):
        """Caja alineada. mats: {"top","bottom","+x","-x","+y","-y"} -> material para esa cara."""
        mats = mats or {}
        F = {
            "top":    ((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)),
            "bottom": ((x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)),
            "-y":     ((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)),
            "+y":     ((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)),
            "-x":     ((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)),
            "+x":     ((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)),
        }
        for k, pts in F.items():
            if k not in skip:
                self.quad(*pts, mats.get(k, mat), cell)

    def cyl(self, a, b, r, mat, segs=10, caps=True):
        a, b = Vector(a), Vector(b)
        axis = (b - a).normalized()
        q = Vector((0, 0, 1)).rotation_difference(axis)
        su, sv, _ = UVS[mat] or (1, 1, 0)
        L = (b - a).length
        ring = [q @ Vector((math.cos(2 * math.pi * k / segs) * r, math.sin(2 * math.pi * k / segs) * r, 0)) for k in range(segs + 1)]
        for k in range(segs):
            u0, u1 = k / segs * 2 * math.pi * r / su, (k + 1) / segs * 2 * math.pi * r / su
            self.face([a + ring[k], a + ring[k + 1], b + ring[k + 1], b + ring[k]], mat,
                      [(u0, 0), (u1, 0), (u1, L / sv), (u0, L / sv)])
        if caps:
            self.face([b + ring[k] for k in range(segs)], mat, [(0.5 + 0.5 * math.cos(2 * math.pi * k / segs), 0.5 + 0.5 * math.sin(2 * math.pi * k / segs)) for k in range(segs)])
            self.face([a + ring[k] for k in reversed(range(segs))], mat, [(0.5, 0.5)] * segs)

    def sign(self, center, normal, w, h, mat, depth=0.12, side_mat="tb_green", both=True, u0=0.0, u1=1.0):
        """Letrero tipo caja: cara con la imagen completa (u0..u1) hacia `normal` (±x o ±y), y la trasera igual."""
        c = Vector(center)
        n = Vector((normal[0], normal[1], 0))
        t = Vector((-n.y, n.x, 0))                     # tangente: hacia la derecha de quien mira el letrero
        hw, hh, hd = w / 2, h / 2, depth / 2
        def corner(sx, sz, sd):
            return c + t * (sx * hw) + Vector((0, 0, sz * hh)) + n * (sd * hd)
        # frente (mirando a n): izquierda-abajo, derecha-abajo, derecha-arriba, izquierda-arriba (vistos desde fuera)
        self.face([corner(-1, -1, 1), corner(1, -1, 1), corner(1, 1, 1), corner(-1, 1, 1)], mat,
                  [(u0, 0), (u1, 0), (u1, 1), (u0, 1)])
        back = mat if both else side_mat
        self.face([corner(1, -1, -1), corner(-1, -1, -1), corner(-1, 1, -1), corner(1, 1, -1)], back,
                  [(u0, 0), (u1, 0), (u1, 1), (u0, 1)])
        for a, b in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
            self.face([corner(a[0], a[1], -1), corner(b[0], b[1], -1), corner(b[0], b[1], 1), corner(a[0], a[1], 1)], side_mat)

    def objects(self):
        out = {}
        for kind, (bm, uvl, mats) in self.meshes.items():
            me = bpy.data.meshes.new(f"{self.name}_{kind}")
            bm.to_mesh(me)
            bm.free()
            for m in mats:
                me.materials.append(MAT[m])
            ob = bpy.data.objects.new(f"{self.name}_{kind}", me)
            scene.collection.objects.link(ob)
            out[kind] = ob
        return out

def planar_uv(p, n, mat):
    su, sv, z0 = UVS[mat] or (1, 1, 0)
    ax = max(range(3), key=lambda i: abs(n[i]))
    if ax == 2:
        return (p.x / su, p.y / sv)
    if ax == 0:
        return (p.y / su, (p.z - z0) / sv)
    return (p.x / su, (p.z - z0) / sv)

# ---------------------------------------------------------------- colisión (cajas con superficie de SA)
SURF = {"pavement": 4, "glass": 46, "girder": 56, "plastic": 68, "hedge": 41, "wood": 43, "default": 0}
COLS = {}

def col_box(piece, x0, y0, z0, x1, y1, z1, surf="pavement"):
    coll = COLS.get(piece)
    if coll is None:
        coll = bpy.data.collections.new(f"turbus_{piece}")
        scene.collection.children.link(coll)
        coll.dff.type = "CMN"
        COLS[piece] = coll
    e = bpy.data.objects.new("ColBox", None)
    e.empty_display_type = "CUBE"
    e.empty_display_size = 1
    e.location = ((x0 + x1) / 2 - ORIGIN.x, (y0 + y1) / 2 - ORIGIN.y, (z0 + z1) / 2 - ORIGIN.z)
    e.scale = (abs(x1 - x0) / 2, abs(y1 - y0) / 2, abs(z1 - z0) / 2)
    e.dff.type = "COL"
    e.dff.col_material = SURF[surf]
    coll.objects.link(e)
    return e

# ================================================================ HALL
hall = Piece("turbus_hall")
z0 = FLOOR
# Losa del piso (tapa el hueco del edificio quitado) y explanada sur hacia los andenes del tren
hall.box(HX0 - 0.5, HY0 - 0.5, 11.9, HX1 + 0.5, HY1 + 3.5, FLOOR, "n_Bow_sub_walltiles", 2.0,
         mats={"-x": "n_concretenewb256", "+x": "n_concretenewb256", "-y": "n_concretenewb256", "+y": "n_concretenewb256"}, skip=("bottom",))
hall.box(HX0 - 3.0, HY0 - 4.6, 11.9, HX1 + 4.5, HY0 - 0.5, G + 0.08, "n_concretenewb256", 2.0, skip=("bottom",))
col_box("hall", HX0 - 0.5, HY0 - 0.5, 11.9, HX1 + 0.5, HY1 + 3.5, FLOOR)
col_box("hall", HX0 - 3.0, HY0 - 4.6, 11.9, HX1 + 4.5, HY0 - 0.5, G + 0.08)
# franjas verdes del piso (guía hacia boleterías y andenes)
for x in (1742.0, 1743.0):
    hall.quad((x, HY0 + 3.0, z0 + 0.03), (x + 0.25, HY0 + 3.0, z0 + 0.03), (x + 0.25, HY1 - 0.5, z0 + 0.03), (x, HY1 - 0.5, z0 + 0.03), "tb_green", 3.0)

# Techo: losa con cielo raso, franja verde y borde blanco
hall.box(ROOF_X0, ROOF_Y0, ROOF0, ROOF_X1, ROOF_Y1, ROOF1, "n_Bow_Abattoir_Conc2", 2.5,
         mats={"bottom": "tb_ceiling"}, skip=("-x", "+x", "-y", "+y"))
# el borde: franja verde abajo (0.6 m) y hormigón blanco arriba, en caras SEPARADAS (nunca superpuestas:
# dos caras en el mismo plano hacen z-fighting y de lejos «se mezclan» las texturas)
for (a, b, n) in (((ROOF_X0, ROOF_Y1), (ROOF_X1, ROOF_Y1), (0, 1)), ((ROOF_X1, ROOF_Y0), (ROOF_X0, ROOF_Y0), (0, -1)),
                  ((ROOF_X0, ROOF_Y0), (ROOF_X0, ROOF_Y1), (-1, 0)), ((ROOF_X1, ROOF_Y1), (ROOF_X1, ROOF_Y0), (1, 0))):
    hall.vquad(a, b, ROOF0, ROOF0 + 0.6, n, "tb_green", 2.0)
    hall.vquad(a, b, ROOF0 + 0.6, ROOF1, n, "n_lasunion7", 2.0)
col_box("hall", ROOF_X0, ROOF_Y0, ROOF0, ROOF_X1, ROOF_Y1, ROOF1, "default")
# luminarias lineales del cielo raso
for x in (1734.5, 1742.5, 1750.5):
    for y in np.arange(HY0 + 4.0, HY1 - 2.0, 8.0):
        hall.quad((x - 0.2, y + 3.0, ROOF0 - 0.05), (x + 0.2, y + 3.0, ROOF0 - 0.05), (x + 0.2, y, ROOF0 - 0.05), (x - 0.2, y, ROOF0 - 0.05), "tb_light", 0)

# Cristaleras con montantes: cada muro es una lista de puertas (inicio, fin) a lo largo del muro
DOOR_H = 3.0
MULL = 3.0

def glass_wall(p_start, p_end, outward, doors=(), solid=False):
    """Muro de vidrio (o macizo) de p_start a p_end. outward = normal hacia fuera. Puertas = (d0, d1) en
    metros desde p_start: hueco hasta DOOR_H con dintel de vidrio encima."""
    a, b = Vector((*p_start, 0)), Vector((*p_end, 0))
    L = (b - a).length
    t = (b - a).normalized()
    n = Vector((*outward, 0))
    def at(s, z, off=0.0):
        p = a + t * s + n * off
        return Vector((p.x, p.y, z))
    def face2(s0, s1, za, zb, off, normal, m, cell):
        hall.vquad(at(s0, 0, off), at(s1, 0, off), za, zb, normal, m, cell)
    # tramos de vidrio (o muro) entre puertas
    cuts = [0.0]
    for d0, d1 in doors:
        cuts += [d0, d1]
    cuts.append(L)
    segs = [(cuts[i], cuts[i + 1]) for i in range(0, len(cuts), 2)]
    mat = "n_newall1-1" if solid else "tb_glass"
    for s0, s1 in segs:
        if s1 - s0 < 0.01:
            continue
        if solid:
            face2(s0, s1, z0, ROOF0, 0.15, n, mat, 2.0)                       # cara exterior
            face2(s0, s1, z0, ROOF0, -0.15, -n, "n_lasunion7", 2.0)         # cara interior
        else:
            # vidrio del panel
            face2(s0, s1, z0 + 0.3, ROOF0, 0.0, n, mat, 3.0)
            # una sola cara: el modelo se dibuja por los dos lados (disable_backface_culling en el cliente)
            # zócalo de hormigón
            p0, p1 = at(s0, 0, -0.12), at(s1, 0, 0.12)
            hall.box(min(p0.x, p1.x), min(p0.y, p1.y), z0, max(p0.x, p1.x), max(p0.y, p1.y), z0 + 0.3, "n_concretenewb256", 2.0, skip=("bottom",))
        p0, p1 = at(s0, 0, -0.1), at(s1, 0, 0.1)
        col_box("hall", min(p0.x, p1.x), min(p0.y, p1.y), z0, max(p0.x, p1.x), max(p0.y, p1.y), ROOF0, "default" if solid else "glass")
    for d0, d1 in doors:
        if solid:
            face2(d0, d1, z0 + DOOR_H, ROOF0, 0.15, n, mat, 2.0)
            face2(d0, d1, z0 + DOOR_H, ROOF0, -0.15, -n, "n_lasunion7", 2.0)
            # dintel (mira hacia abajo) y jambas (miran hacia el hueco)
            pa, pb, pc, pd = at(d0, z0 + DOOR_H, -0.15), at(d1, z0 + DOOR_H, -0.15), at(d1, z0 + DOOR_H, 0.15), at(d0, z0 + DOOR_H, 0.15)
            nrm = (pb - pa).cross(pc - pa)
            hall.quad(*((pa, pb, pc, pd) if nrm.z < 0 else (pd, pc, pb, pa)), "n_lasunion7", 0)
            hall.vquad(at(d0, 0, 0.15), at(d0, 0, -0.15), z0, z0 + DOOR_H, t, "n_lasunion7", 0)
            hall.vquad(at(d1, 0, 0.15), at(d1, 0, -0.15), z0, z0 + DOOR_H, -t, "n_lasunion7", 0)
        else:
            face2(d0, d1, z0 + DOOR_H, ROOF0, 0.0, n, mat, 3.0)
            # (una sola cara, igual que los paneles)
        p0, p1 = at(d0, 0, -0.1), at(d1, 0, 0.1)
        col_box("hall", min(p0.x, p1.x), min(p0.y, p1.y), z0 + DOOR_H, max(p0.x, p1.x), max(p0.y, p1.y), ROOF0, "glass")
    if solid:
        return
    # montantes verticales cada MULL m (y en los bordes de las puertas), travesaños a 3 y 5.5 m
    stops = set(round(s, 2) for s in np.arange(0, L + 0.01, MULL))
    for d0, d1 in doors:
        stops |= {round(d0, 2), round(d1, 2)}
    for s in sorted(stops):
        p = at(min(max(s, 0.06), L - 0.06), 0)
        hall.box(p.x - 0.07, p.y - 0.07, z0 + 0.3, p.x + 0.07, p.y + 0.07, ROOF0, "tb_steel", 3.0, skip=("top", "bottom"))
    for zz in (DOOR_H, 5.5):
        p0, p1 = at(0, 0, -0.06), at(L, 0, 0.06)
        hall.box(min(p0.x, p1.x), min(p0.y, p1.y), z0 + zz - 0.06, max(p0.x, p1.x), max(p0.y, p1.y), z0 + zz + 0.06, "tb_steel", 3.0)

# norte (entrada principal, mira a la explanada y al punto de aparición), oeste (plaza), este (andenes), sur (tren)
glass_wall((HX0, HY1), (HX1, HY1), (0, 1), doors=[(5.5, 9.0), (17.0, 20.5)])
glass_wall((HX1, HY0), (HX0, HY0), (0, -1), doors=[(11.0, 15.0)], solid=True)
glass_wall((HX0, HY0), (HX0, HY1), (-1, 0), doors=[(28.0, 31.5), (45.0, 48.5)])
glass_wall((HX1, HY1), (HX1, HY0), (1, 0), doors=[(2.5, 6.0), (17.0, 20.5), (31.5, 35.0)])
# marquesina sobre la entrada norte: el techo ya vuela 4 m; letrero «turbus» sobre la losa
hall.sign((1742.5, HY1 + 3.6, ROOF1 + 1.15), (0, 1), 9.0, 2.25, "tb_logo", depth=0.3)
hall.box(1739.0, HY1 + 3.4, ROOF1, 1746.0, HY1 + 3.8, ROOF1 + 0.05, "tb_steel", 0, skip=("bottom",))
col_box("hall", 1738.0, HY1 + 3.45, ROOF1, 1747.0, HY1 + 3.75, ROOF1 + 2.3, "default")
hall.sign((ROOF_X1 - 0.4, -1890.0, ROOF1 + 1.15), (1, 0), 9.0, 2.25, "tb_logo", depth=0.3)
col_box("hall", ROOF_X1 - 0.55, -1894.5, ROOF1, ROOF_X1 - 0.25, -1885.5, ROOF1 + 2.3, "default")

# Pilares en V de hormigón claro (dos filas)
for x in (1736.0, 1749.0):
    for y in (-1871.0, -1885.5, -1899.0, -1912.5, -1927.0):
        for dy in (-2.4, 2.4):
            hall.cyl((x, y, z0), (x, y + dy, ROOF0), 0.2, "n_lasunion7", 10, caps=False)
        hall.cyl((x, y, z0), (x, y, z0 + 0.25), 0.42, "n_concretenewb256", 12)
        col_box("hall", x - 0.35, y - 0.35, z0, x + 0.35, y + 0.35, z0 + 2.6, "girder")

# Asientos verdes en filas (respaldo con respaldo), viga de acero y patas
SEAT_W = 0.56
def seat_row(x0, x1, y, facing):
    """Fila de asientos de x0 a x1 en y; facing = +1 miran al norte, -1 al sur."""
    n = int((x1 - x0) / SEAT_W)
    xs = x0 + (x1 - x0 - n * SEAT_W) / 2
    hall.box(xs, y - 0.06, z0 + 0.32, xs + n * SEAT_W, y + 0.06, z0 + 0.4, "tb_steel", 0)
    for leg in (xs + 0.3, xs + n * SEAT_W - 0.3):
        hall.box(leg - 0.04, y - 0.25, z0, leg + 0.04, y + 0.25, z0 + 0.36, "tb_steel", 0, skip=("bottom",))
    for k in range(n):
        sx0, sx1 = xs + k * SEAT_W + 0.03, xs + (k + 1) * SEAT_W - 0.03
        back = y - 0.24 * facing
        hall.box(sx0, min(y - 0.22 * facing, y + 0.24 * facing), z0 + 0.4, sx1, max(y - 0.22 * facing, y + 0.24 * facing), z0 + 0.46, "tb_seat", 0)
        # respaldo levemente inclinado
        b0 = back
        b1 = back - 0.08 * facing
        hall.face([(sx0, b0, z0 + 0.46), (sx1, b0, z0 + 0.46), (sx1, b1, z0 + 0.92), (sx0, b1, z0 + 0.92)] if facing < 0 else
                  [(sx1, b0, z0 + 0.46), (sx0, b0, z0 + 0.46), (sx0, b1, z0 + 0.92), (sx1, b1, z0 + 0.92)], "tb_seat")
        hall.face([(sx1, b0 - 0.04 * facing, z0 + 0.46), (sx0, b0 - 0.04 * facing, z0 + 0.46), (sx0, b1 - 0.04 * facing, z0 + 0.92), (sx1, b1 - 0.04 * facing, z0 + 0.92)] if facing < 0 else
                  [(sx0, b0 - 0.04 * facing, z0 + 0.46), (sx1, b0 - 0.04 * facing, z0 + 0.46), (sx1, b1 - 0.04 * facing, z0 + 0.92), (sx0, b1 - 0.04 * facing, z0 + 0.92)], "tb_seat")
    col_box("hall", xs, y - 0.3, z0, xs + n * SEAT_W, y + 0.3, z0 + 0.46, "plastic")

for yb in (-1876.0, -1881.0, -1917.0, -1922.0):         # bloques de dos filas respaldo con respaldo
    for (xa, xb) in ((1738.6, 1746.4), (1730.6, 1734.6), (1750.4, 1754.4)):
        seat_row(xa, xb, yb + 0.3, 1)
        seat_row(xa, xb, yb - 0.3, -1)

# Isla central: jardinera redonda con banca en anillo (como la del terminal)
IC = Vector((1742.5, -1899.0))
SEG = 20
for k in range(SEG):
    a0, a1 = 2 * math.pi * k / SEG, 2 * math.pi * (k + 1) / SEG
    def pt(r, a, z):
        return (IC.x + r * math.cos(a), IC.y + r * math.sin(a), z)
    # jardinera (muro blanco) y arbustos
    hall.face([pt(2.2, a0, z0), pt(2.2, a1, z0), pt(2.2, a1, z0 + 0.75), pt(2.2, a0, z0 + 0.75)], "n_lasunion7")
    hall.face([pt(2.2, a0, z0 + 0.75), pt(2.2, a1, z0 + 0.75), pt(1.95, a1, z0 + 0.75), pt(1.95, a0, z0 + 0.75)], "n_concretenewb256")
    hall.face([pt(1.95, a0, z0 + 0.75), pt(1.95, a1, z0 + 0.75), pt(0.0, a1, z0 + 1.35), pt(0.0, a0, z0 + 1.35)], "tb_hedge")
    # banca en anillo: asiento verde y frente
    hall.face([pt(3.0, a0, z0 + 0.45), pt(3.0, a1, z0 + 0.45), pt(2.2, a1, z0 + 0.45), pt(2.2, a0, z0 + 0.45)], "tb_seat")
    hall.face([pt(3.0, a0, z0), pt(3.0, a1, z0), pt(3.0, a1, z0 + 0.45), pt(3.0, a0, z0 + 0.45)], "tb_green")
col_box("hall", IC.x - 3.0, IC.y - 1.3, z0, IC.x + 3.0, IC.y + 1.3, z0 + 0.45, "plastic")
col_box("hall", IC.x - 1.3, IC.y - 3.0, z0, IC.x + 1.3, IC.y + 3.0, z0 + 0.45, "plastic")
col_box("hall", IC.x - 2.1, IC.y - 2.1, z0, IC.x + 2.1, IC.y + 2.1, z0 + 0.75, "default")
col_box("hall", IC.x - 1.6, IC.y - 1.6, z0 + 0.75, IC.x + 1.6, IC.y + 1.6, z0 + 1.3, "hedge")

# Pantallas de salidas colgadas (doble cara) con varillas al techo
for y in (-1888.0, -1910.5):
    hall.sign((1742.5, y, z0 + 4.6), (0, 1), 2.6, 1.3, "tb_board", depth=0.14, side_mat="tb_black")
    for dx in (-1.0, 1.0):
        hall.cyl((1742.5 + dx, y, z0 + 5.25), (1742.5 + dx, y, ROOF0), 0.02, "tb_steel", 4, caps=False)

# Boleterías contra el muro sur: mesón (frente verde, cubierta blanca), mampara de vidrio y letrero
for (xa, xb) in ((1731.0, 1739.8), (1745.2, 1754.0)):
    yb0, yb1 = HY0 + 1.8, HY0 + 2.6
    hall.box(xa, yb0, z0, xb, yb1, z0 + 1.05, "tb_green", 2.0, mats={"top": "n_lasunion7", "-y": "n_lasunion7"}, skip=("bottom",))
    hall.quad((xa, yb1 - 0.05, z0 + 1.05), (xb, yb1 - 0.05, z0 + 1.05), (xb, yb1 - 0.05, z0 + 2.5), (xa, yb1 - 0.05, z0 + 2.5), "tb_glass", 2.0)
    # (una sola cara: el vidrio se ve por los dos lados)
    hall.box(xa, yb1 - 0.1, z0 + 2.5, xb, yb1, z0 + 2.62, "tb_steel", 0)
    # paneles verdes y letrero «BOLETERÍA» en el muro
    hall.vquad((xa, HY0 + 0.20), (xb, HY0 + 0.20), z0 + 2.7, z0 + 3.9, (0, 1), "tb_green", 2.0)
    hall.sign(((xa + xb) / 2, HY0 + 0.30, z0 + 3.3), (0, 1), 3.6, 0.9, "tb_bolet", depth=0.08, both=False)
    col_box("hall", xa, yb0, z0, xb, yb1, z0 + 2.6, "wood")

# Mesón de informaciones junto a la entrada norte
hall.box(1740.5, HY1 - 3.2, z0, 1744.5, HY1 - 2.4, z0 + 1.1, "tb_green", 1.0, mats={"top": "n_lasunion7"}, skip=("bottom",))
col_box("hall", 1740.5, HY1 - 3.2, z0, 1744.5, HY1 - 2.4, z0 + 1.1, "wood")
# letreros «ANDENES» colgados frente a las puertas del este (mirando hacia dentro)
for y in (-1870.75, -1885.75):
    hall.sign((HX1 - 1.2, y, z0 + 3.6), (-1, 0), 2.8, 0.7, "tb_andenes", depth=0.08, both=False, side_mat="tb_black")
    hall.cyl((HX1 - 1.2, y - 1.0, z0 + 3.95), (HX1 - 1.2, y - 1.0, ROOF0), 0.02, "tb_steel", 4, caps=False)
    hall.cyl((HX1 - 1.2, y + 1.0, z0 + 3.95), (HX1 - 1.2, y + 1.0, ROOF0), 0.02, "tb_steel", 4, caps=False)

# ================================================================ MARQUESINA Y ANDENES
can = Piece("turbus_canopy")
# Andenes: losa de hormigón gris, línea podotáctil amarilla y solera amarilla hacia el asfalto
EAST_PLAT = (1769.0, 1774.3, -1938.5, -1885.6)
NORTH_PLAT = (1769.0, 1810.8, -1885.6, -1869.0)
for (x0, x1, y0, y1), skipf in ((EAST_PLAT, ("bottom", "+y")), (NORTH_PLAT, ("bottom",))):
    can.box(x0, y0, 12.2, x1, y1, PLAT, "n_Bow_Abattoir_Conc2", 2.0, skip=skipf,
            mats={"+x": "tb_yellow", "-y": "tb_yellow" if (y1 - y0) < 20 else "n_concretenewb256",
                  "-x": "n_concretenewb256", "+y": "n_concretenewb256"})
    col_box("canopy", x0, y0, 12.2, x1, y1, PLAT)
# franja amarilla en el borde (pintura) y podotáctil
can.quad((1773.6, -1938.5, PLAT + 0.03), (1774.3, -1938.5, PLAT + 0.03), (1774.3, -1885.6, PLAT + 0.03), (1773.6, -1885.6, PLAT + 0.03), "tb_yellow", 3.0)
can.quad((1773.6, -1885.6, PLAT + 0.03), (1810.8, -1885.6, PLAT + 0.03), (1810.8, -1884.9, PLAT + 0.03), (1773.6, -1884.9, PLAT + 0.03), "tb_yellow", 3.0)
can.quad((1772.7, -1938.0, PLAT + 0.032), (1773.1, -1938.0, PLAT + 0.032), (1773.1, -1884.0, PLAT + 0.032), (1772.7, -1884.0, PLAT + 0.032), "tb_yellow", 3.0)
can.quad((1773.1, -1884.4, PLAT + 0.032), (1810.3, -1884.4, PLAT + 0.032), (1810.3, -1884.0, PLAT + 0.032), (1773.1, -1884.0, PLAT + 0.032), "tb_yellow", 3.0)

# Cajones pintados en el asfalto y topes amarillos (como los del terminal)
ZL = LOT + 0.07     # el asfalto varía entre 12.38 y 12.41: la pintura va bien encima (z-fighting)
for y in [b + 4.0 for b in EAST_BAYS] + [EAST_BAYS[-1] - 4.0]:
    can.quad((1774.3, y - 0.08, ZL), (1787.0, y - 0.08, ZL), (1787.0, y + 0.08, ZL), (1774.3, y + 0.08, ZL), "tb_yellow", 3.0)
for y in EAST_BAYS:
    can.box(1775.0, y - 0.9, LOT, 1775.3, y + 0.9, LOT + 0.14, "tb_yellow", 0, skip=("bottom",))
    col_box("canopy", 1775.0, y - 0.9, LOT, 1775.3, y + 0.9, LOT + 0.14, "default")
for x in [b - 4.0 for b in NORTH_BAYS] + [NORTH_BAYS[-1] + 4.0]:
    can.quad((x - 0.08, -1898.0, ZL), (x + 0.08, -1898.0, ZL), (x + 0.08, -1885.6, ZL), (x - 0.08, -1885.6, ZL), "tb_yellow", 3.0)
for x in NORTH_BAYS:
    can.box(x - 0.9, -1886.6, LOT, x + 0.9, -1886.3, LOT + 0.14, "tb_yellow", 0, skip=("bottom",))
    col_box("canopy", x - 0.9, -1886.6, LOT, x + 0.9, -1886.3, LOT + 0.14, "default")

# Losa de la marquesina en L: chapa ondulada oscura por debajo, cubierta arriba, borde verde
# la cara -x de la marquesina queda en el plano de la cristalera este (x = HX1): se quita (z-fighting con el vidrio)
for (x0, x1, y0, y1), skipf in ((CAN_E, ("+y", "-x")), (CAN_N, ("-x",))):
    can.box(x0, y0, CAN0, x1, y1, CAN1, "n_Bow_Abattoir_Conc2", 2.5, skip=skipf,
            mats={"bottom": "n_ws_corrugateddoor1", "-x": "tb_green", "+x": "tb_green", "-y": "tb_green", "+y": "tb_green"})
    col_box("canopy", x0, y0, CAN0, x1, y1, CAN1, "default")
# viga de borde blanca (como la del terminal) en los bordes que dan a los buses
can.box(CAN_E[1] - 0.3, CAN_E[2], CAN0 - 0.5, CAN_E[1], CAN_E[3], CAN0, "tb_steel", 3.0, skip=("top",))
can.box(CAN_E[1], CAN_N[2], CAN0 - 0.5, CAN_N[1], CAN_N[2] + 0.3, CAN0, "tb_steel", 3.0, skip=("top",))
# Pilares verdes
PILLARS = [(1771.5, y) for y in (-1937.0, -1927.0, -1917.0, -1907.0, -1897.0)] + \
          [(x, -1883.8) for x in (1771.5, 1781.0, 1790.5, 1800.0, 1809.5)] + \
          [(x, -1870.0) for x in (1771.5, 1781.0, 1799.5, 1809.5)]
for (x, y) in PILLARS:
    base = PLAT
    can.cyl((x, y, base), (x, y, CAN0), 0.25, "tb_green", 12, caps=False)
    can.cyl((x, y, CAN0 - 0.6), (x, y, CAN0), 0.36, "tb_steel", 12, caps=False)
    col_box("canopy", x - 0.28, y - 0.28, base, x + 0.28, y + 0.28, CAN0, "girder")
# Luminarias bajo la marquesina (encendidas de noche) y parlantes en los pilares
for y in np.arange(-1936.0, -1894.0, 6.0):
    for x in (1764.0, 1777.0):
        can.quad((x - 1.5, y + 0.25, CAN0 - 0.05), (x + 1.5, y + 0.25, CAN0 - 0.05), (x + 1.5, y - 0.25, CAN0 - 0.05), (x - 1.5, y - 0.25, CAN0 - 0.05), "tb_light", 0)
for x in np.arange(1761.0, 1810.0, 6.0):
    for y in (-1889.0, -1876.0):
        can.quad((x - 0.25, y + 1.5, CAN0 - 0.05), (x + 0.25, y + 1.5, CAN0 - 0.05), (x + 0.25, y - 1.5, CAN0 - 0.05), (x - 0.25, y - 1.5, CAN0 - 0.05), "tb_light", 0)
for (x, y) in PILLARS[::2]:
    can.box(x - 0.15, y + 0.25, CAN0 - 1.3, x + 0.15, y + 0.45, CAN0 - 0.9, "tb_black", 0)
# Números de andén colgados del borde (doble cara, mirando a los buses)
for i, y in enumerate(EAST_BAYS):
    can.sign((CAN_E[1] - 0.15, y, CAN0 - 0.85), (1, 0), 0.8, 0.8, "tb_nums", depth=0.1, u0=i / 8, u1=(i + 1) / 8)
    can.cyl((CAN_E[1] - 0.15, y, CAN0 - 0.45), (CAN_E[1] - 0.15, y, CAN0), 0.03, "tb_steel", 4, caps=False)
for i, x in enumerate(NORTH_BAYS):
    k = 5 + i
    can.sign((x, CAN_N[2] + 0.15, CAN0 - 0.85), (0, -1), 0.8, 0.8, "tb_nums", depth=0.1, u0=k / 8, u1=(k + 1) / 8)
    can.cyl((x, CAN_N[2] + 0.15, CAN0 - 0.45), (x, CAN_N[2] + 0.15, CAN0), 0.03, "tb_steel", 4, caps=False)
# Letreros «turbus» sobre el borde de la marquesina, hacia la calle y el estacionamiento
can.sign((CAN_E[1] - 0.2, -1916.0, CAN1 + 0.75), (1, 0), 6.0, 1.5, "tb_logo_w", depth=0.2, side_mat="tb_green")
can.sign((1796.0, CAN_N[2] + 0.2, CAN1 + 0.75), (0, -1), 6.0, 1.5, "tb_logo_w", depth=0.2, side_mat="tb_green")
can.sign((1796.0, CAN_N[3] - 0.2, CAN1 + 0.75), (0, 1), 6.0, 1.5, "tb_logo", depth=0.2)
col_box("canopy", CAN_E[1] - 0.35, -1919.0, CAN1, CAN_E[1] - 0.05, -1913.0, CAN1 + 1.5, "default")

# Volumen de las piezas sin colisión propia (hall_x, glass, canopy_x, lod). GTA recorta cada modelo con los
# límites de su COL: sin este, heredan el COL del modelo base (un objeto de 1 m) y desaparecen de cerca.
# En el juego esas piezas tienen la colisión desactivada; la caja solo da los límites.
col_box("bounds", HX0 - 3.0, HY0 - 4.6, 11.9, CAN_N[1] + 0.5, ROOF_Y1 + 0.5, ROOF1 + 2.5, "default")

# ================================================================ LOD (cajas simples, visibles de lejos)
lod = Piece("turbus_lod")
lod.box(HX0, HY0, FLOOR, HX1, HY1, ROOF0, MAT_GLASS_LOD, 0, mats={"top": "tb_lod_roof"}, skip=("bottom",))
lod.box(ROOF_X0, ROOF_Y0, ROOF0, ROOF_X1, ROOF_Y1, ROOF1, "tb_lod_roof", 0,
        mats={"-x": "tb_lod_green", "+x": "tb_lod_green", "-y": "tb_lod_green", "+y": "tb_lod_green", "bottom": "tb_lod_dark"})
for (x0, x1, y0, y1) in (CAN_E, CAN_N):
    lod.box(x0, y0, CAN0, x1, y1, CAN1, "tb_lod_roof", 0,
            mats={"bottom": "tb_lod_dark", "-x": "tb_lod_green", "+x": "tb_lod_green", "-y": "tb_lod_green", "+y": "tb_lod_green"})

# ---------------------------------------------------------------- objetos finales
O = {}
for piece in (hall, can, lod):
    for kind, ob in piece.objects().items():
        O[f"{piece.name}_{kind}"] = ob
NAMES = {  # objeto -> archivo
    "turbus_hall_nat": "turbus_hall", "turbus_hall_x": "turbus_hall_x", "turbus_hall_glass": "turbus_glass",
    "turbus_canopy_nat": "turbus_canopy", "turbus_canopy_x": "turbus_canopy_x", "turbus_lod_lod": "turbus_lod",
}
for k, ob in O.items():
    ob.name = NAMES[k]
    ob.data.name = NAMES[k]
    for p in ob.data.polygons:
        p.use_smooth = False
print("[turbus] objetos:", {ob.name: len(ob.data.polygons) for ob in O.values()})

# ---------------------------------------------------------------- molde: suelo original para el horneado y las vistas
ref_objs = []
if REF:
    for name, pos in (("btoland2_las", (1745.203125, -1882.851563, 26.140625)), ("uninstps_las01", (1701.391, -1954.133, 10.398))):
        path = os.path.join(REF, name + ".dff")
        if not os.path.exists(path):
            continue
        before = set(bpy.data.objects)
        bpy.ops.import_scene.dff(filepath=path)
        for o in [o for o in bpy.data.objects if o not in before]:
            if o.parent is None:
                o.location = pos
            if o.type == "MESH":
                ref_objs.append(o)
            else:
                o.hide_render = True
    if os.path.exists(os.path.join(REF, "union_las.txd")):
        bpy.ops.import_scene.dff(filepath=os.path.join(REF, "union_las.txd"))
    bpy.context.view_layer.update()

# ---------------------------------------------------------------- luz horneada (prelight día y noche)
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16 if QUICK else 64
world = bpy.data.worlds.new("bake_sky")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.66, 0.85, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
sun = bpy.data.objects.new("bake_sun", bpy.data.lights.new("bake_sun", "SUN"))
sun.data.energy = 3.2
sun.data.angle = math.radians(6)
sun.rotation_euler = (math.radians(38), math.radians(12), math.radians(150))
scene.collection.objects.link(sun)
helpers = [sun]
if not ref_objs:
    bpy.ops.mesh.primitive_plane_add(size=400, location=(1755, -1900, G - 0.01))
    gp = bpy.context.active_object
    gm = bpy.data.materials.new("bake_ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.22, 0.18, 1)
    gp.data.materials.append(gm)
    helpers.append(gp)

def inside(c, box, zmax):
    return box[0] <= c.x <= box[1] and box[2] <= c.y <= box[3] and c.z <= zmax

HALL_BOX = (HX0 - 0.1, HX1 + 0.1, HY0 - 0.1, HY1 + 0.1)
REF_LUM = {}

def bake_prelight(obj, key):
    mesh = obj.data
    for a in list(mesh.color_attributes):
        mesh.color_attributes.remove(a)
    day = mesh.color_attributes.new("day", "BYTE_COLOR", "CORNER")
    night = mesh.color_attributes.new("night", "BYTE_COLOR", "CORNER")
    n = len(mesh.loops)
    glass = [o for o in O.values() if o.name == "turbus_glass"]
    if obj.name in ("turbus_glass", "turbus_lod"):
        lum = np.full(n, 0.8)
    else:
        mesh.color_attributes.active_color = day
        for g in glass + [O["turbus_lod_lod"]]:
            g.hide_render = True
        for o in scene.objects:
            o.select_set(o == obj)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"DIRECT", "INDIRECT"}, target="VERTEX_COLORS")
        col = np.empty(n * 4, dtype=np.float32)
        day.data.foreach_get("color", col)
        lum = col.reshape(n, 4)[:, :3] @ np.array((0.2126, 0.7152, 0.0722))
        if "ref" not in REF_LUM:
            REF_LUM["ref"] = float(np.percentile(lum, 96)) or 1.0
        lum = np.clip(lum / REF_LUM["ref"], 0, 1) ** 0.85
    # Día: 75..200 (gris cálido), como los bloques vecinos de Rockstar
    v = 0.30 + 0.48 * lum
    d = np.stack([v, v * 0.97, v * 0.92], axis=1)
    # máscaras por cara: interior del hall, bajo la marquesina, materiales que brillan
    lit_in = np.zeros(n, dtype=bool)
    under = np.zeros(n, dtype=bool)
    glow = np.zeros(n, dtype=bool)
    mw = obj.matrix_world
    for poly in mesh.polygons:
        c = mw @ poly.center
        idx = list(poly.loop_indices)
        if inside(c, HALL_BOX, ROOF0 - 0.05):
            lit_in[idx] = True
        if (inside(c, (CAN_E[0], CAN_E[1], CAN_E[2], CAN_E[3]), CAN0 - 0.05) or inside(c, (CAN_N[0], CAN_N[1], CAN_N[2], CAN_N[3]), CAN0 - 0.05)) and not lit_in[idx[0]]:
            under[idx] = True
        if mesh.materials[poly.material_index].name in GLOW:
            glow[idx] = True
    # interior del hall: luz artificial pareja, conservando la oclusión del horneado (rincones más oscuros)
    if lit_in.any() and obj.name != "turbus_glass":
        li = lum[lit_in]
        li = np.clip(li / (np.percentile(li, 95) or 1.0), 0, 1)
        vi = 0.46 + 0.22 * li
        d[lit_in] = np.maximum(d[lit_in], np.stack([vi, vi * 0.98, vi * 0.95], axis=1))
    d[glow] = np.maximum(d[glow], 0.70)                                     # letreros legibles a la sombra
    # Noche: gris azulado oscuro; el interior y bajo la marquesina, con luz de lámparas cálida
    nt = d * np.array((0.21, 0.23, 0.30))
    nt[lit_in] = np.maximum(nt[lit_in], d[lit_in] * np.array((0.95, 0.88, 0.70)))
    nt[under] = np.maximum(nt[under], d[under] * np.array((0.80, 0.74, 0.58)))
    nt[glow] = np.array((1.0, 0.94, 0.78))
    if obj.name == "turbus_glass":
        d[:] = np.array((0.62, 0.62, 0.62))
        nt[:] = np.array((0.85, 0.76, 0.56))
    if obj.name == "turbus_lod":
        nt[:] = d * np.array((0.30, 0.30, 0.34))
        for poly in mesh.polygons:
            if mesh.materials[poly.material_index].name == MAT_GLASS_LOD:
                nt[list(poly.loop_indices)] = np.array((0.9, 0.82, 0.6))
    def put(attr, rgb):
        rgba = np.concatenate([np.clip(rgb, 0, 1), np.ones((n, 1))], axis=1).astype(np.float32)
        attr.data.foreach_set("color_srgb", rgba.ravel())
    put(day, d)
    put(night, nt)
    obj.dff.day_cols = True
    obj.dff.night_cols = True
    obj.dff.uv_map2 = False
    print(f"[turbus] prelight {obj.name}: {n} esquinas")

for key in ("turbus_hall_nat", "turbus_hall_x", "turbus_canopy_nat", "turbus_canopy_x", "turbus_hall_glass", "turbus_lod_lod"):
    bake_prelight(O[key], key)
for h in helpers:
    bpy.data.objects.remove(h)
for g in O.values():
    g.hide_render = False

# ---------------------------------------------------------------- luces 2DFX de noche (como las farolas del juego)
def night_light(loc, rng_m=8.0, shadow=5.0):
    data = bpy.data.lights.new("2dfx_light", "POINT")
    data.color = (1.0, 0.92, 0.78)
    data.energy = 0
    ob = bpy.data.objects.new("2dfx_light", data)
    ob.location = Vector(loc)
    ob.dff.type = "2DFX"
    ob.dff.ext_2dfx.effect = "0"
    s = data.ext_2dfx
    s.alpha = 0.55
    s.corona_far_clip = 80.0
    s.point_light_range = rng_m
    s.corona_size = 0.0
    s.shadow_size = shadow
    s.shadow_color_multiplier = 40
    s.shadow_z_distance = 12
    s.corona_tex_name = "coronastar"
    s.shadow_tex_name = "shad_exp"
    s.flag1_without_corona = True
    s.flag1_at_day = False
    s.flag1_at_night = True
    scene.collection.objects.link(ob)
    return ob

# Sin luces 2DFX: GTA solo dibuja las manchas de luz de las más cercanas a la cámara y con fundido por distancia,
# así que al moverse de noche el piso (y el suelo original) se aclaraba y oscurecía (probado en juego). La luz de
# noche ya va horneada en el prelight. night_light() queda por si se quiere una luz puntual aislada.
LIGHTS = {}

# ---------------------------------------------------------------- vistas previas (con el suelo original), antes de mover al origen
def preview_materials(attr):
    """Material de vista previa como en el juego: textura × prelight × 1.6 (emisión), vidrio transparente."""
    saved = {}
    for m in list(bpy.data.materials):
        if not m.use_nodes:
            continue
        nt = m.node_tree
        tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image), None)
        if tex is None:
            continue
        saved[m.name] = [l for l in nt.links]
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = attr
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(tex.outputs["Color"], mul.inputs[6])
        nt.links.new(vc.outputs["Color"], mul.inputs[7])
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = 1.7
        nt.links.new(mul.outputs[2], em.inputs["Color"])
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(tex.outputs["Alpha"], mix.inputs["Fac"])
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
        for n2 in (vc, mul, em, tr, mix):
            n2["preview"] = True
    return saved

def restore_materials():
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        nt = m.node_tree
        for n2 in [n for n in nt.nodes if n.get("preview")]:
            nt.nodes.remove(n2)
        p = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
        if p and out:
            nt.links.new(p.outputs[0], out.inputs["Surface"])

def render_views():
    if not REF:
        return
    cam = bpy.data.objects.new("prev_cam", bpy.data.cameras.new("prev_cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.cycles.samples = 8
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    scene.view_settings.view_transform = "Standard"
    O["turbus_lod_lod"].hide_render = True
    # el suelo original tiene su prelight en "Col" (día) y "Col.001" (noche)
    shots = [("render_ne.png", (1830, -1830, 55), (1755, -1900, 14)), ("render_se.png", (1830, -1985, 45), (1755, -1900, 14)),
             ("render_nw.png", (1690, -1835, 40), (1745, -1895, 16)), ("render_spawn.png", (1742.9, -1850.0, 15.4), (1742.7, -1880.0, 15.0)),
             ("render_hall.png", (1734.0, -1872.0, 14.6), (1748.0, -1905.0, 13.6)), ("render_anden.png", (1770.0, -1890.5, 14.4), (1774.0, -1930.0, 14.0))]
    for mode, vattr, rattr, bg in (("dia", "day", "Col", (0.60, 0.72, 0.90)), ("noche", "night", "Col.001", (0.03, 0.04, 0.09))):
        world.node_tree.nodes["Background"].inputs["Color"].default_value = (*bg, 1)
        world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
        preview_materials(vattr)
        for o in ref_objs:
            for m in o.data.materials:
                if m and m.use_nodes:
                    for n2 in m.node_tree.nodes:
                        if n2.type == "VERTEX_COLOR" and n2.get("preview"):
                            n2.layer_name = rattr if rattr in o.data.color_attributes else o.data.color_attributes[0].name
        for name, loc, target in shots:
            if mode == "noche" and name not in ("render_ne.png", "render_hall.png"):
                continue
            cam.location = loc
            cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
            cam.data.lens = 18 if name in ("render_hall.png", "render_anden.png", "render_spawn.png") else 24
            scene.render.filepath = os.path.join(REF, mode + "_" + name)
            bpy.ops.render.render(write_still=True)
        restore_materials()
    bpy.data.objects.remove(cam)

render_views()

# ---------------------------------------------------------------- vidrio como primitivas 3D (no como modelo)
# GTA no garantiza el orden entre un objeto con alfa y los edificios: según la cámara el vidrio tapaba el interior o el
# interior lo borraba. El cliente dibuja estos triángulos cada cuadro con dxDrawPrimitive3D (después del mundo, con
# profundidad), así siempre queda encima del interior. Coordenadas del mundo.
def write_glass_data():
    gl = O["turbus_hall_glass"]
    mw = gl.matrix_world
    nums = []
    for p in gl.data.polygons:
        vs = [mw @ gl.data.vertices[i].co for i in p.vertices]
        for k in range(1, len(vs) - 1):
            for v in (vs[0], vs[k], vs[k + 1]):
                nums += ["%.2f" % v.x, "%.2f" % v.y, "%.2f" % v.z]
    path = os.path.join(RES, "client", "c_glass_data.lua")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generado por tools/build_terminal.py: triángulos del vidrio del terminal (x, y, z del mundo, de a 3 vértices).\n")
        f.write("-- No editar a mano: se regenera con el modelo.\n")
        f.write("TURBUS_GLASS = {\n")
        for i in range(0, len(nums), 18):
            f.write("    " + ", ".join(nums[i:i + 18]) + ",\n")
        f.write("}\n")
    print(f"[turbus] vidrio: {len(nums) // 9} triángulos -> {path}")

write_glass_data()

# ---------------------------------------------------------------- mover al origen del objeto y exportar
T = Matrix.Translation(-ORIGIN)
for ob in O.values():
    ob.data.transform(T)
for lights in LIGHTS.values():
    for l in lights:
        l.location = l.location - ORIGIN
for o in ref_objs:
    bpy.data.objects.remove(o)

models = os.path.join(RES, "models")
os.makedirs(models, exist_ok=True)

def drop_empty_image_nodes():
    for m in bpy.data.materials:
        if m.node_tree:
            for node in [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image is None]:
                m.node_tree.nodes.remove(node)

for key, file in NAMES.items():
    if key == "turbus_hall_glass":
        continue                        # el vidrio va como primitivas (c_glass_data.lua), no como DFF
    ob = O[key]
    sel = [ob] + LIGHTS.get(key, [])
    for o in scene.objects:
        o.select_set(o in sel)
    bpy.context.view_layer.objects.active = ob
    path = os.path.join(models, file + ".dff")
    bpy.ops.export_dff.scene(filepath=path, directory=models, only_selected=True, export_coll=False, export_version="0x36003")
    drop_empty_image_nodes()
    tri = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print(f"[turbus] {file}.dff: {os.path.getsize(path)} bytes, triángulos≈{tri}")

# ---------------------------------------------------------------- TXD propios con mipmaps (DragonFF los exporta sin ellos)
from DragonFF.ops import txd_exporter, col_exporter
from DragonFF.gtaLib import txd as txdlib
from DragonFF.gtaLib.dff import NativePlatformType

def make_native(image, name):
    w, h = image.size
    px = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]     # fila 0 = arriba en el TXD
    has_alpha = bool((px[..., 3] < 0.999).any())
    levels = []
    cur = px
    while True:
        rgba = np.clip(np.round(cur * 255), 0, 255).astype(np.uint8)
        levels.append(bytes(rgba[..., [2, 1, 0, 3]].ravel()))                    # BGRA
        if min(cur.shape[0], cur.shape[1]) <= 4:
            break
        cur = cur.reshape(cur.shape[0] // 2, 2, cur.shape[1] // 2, 2, 4).mean(axis=(1, 3))
    t = txdlib.TextureNative()
    t.platform_id = NativePlatformType.D3D9
    t.filter_mode = 0x06
    t.uv_addressing = 0b00010001
    t.name = name[:31]
    t.mask = ""
    fmt = txdlib.RasterFormat.RASTER_8888 if has_alpha else txdlib.RasterFormat.RASTER_888
    t.raster_format_flags = (fmt << 8) | 0x8000                                 # 0x8000 = con mipmaps
    t.d3d_format = txdlib.D3DFormat.D3D_8888 if has_alpha else txdlib.D3DFormat.D3D_888
    t.width, t.height, t.depth = w, h, 32
    t.num_levels = len(levels)
    t.raster_type = 4
    t.platform_properties = type("PlatformProperties", (), {"alpha": has_alpha, "cube_texture": False, "auto_mipmaps": False, "compressed": False})()
    t.palette = b""
    t.pixels = levels
    return t

def write_txd(path, objects):
    tx = txdlib.txd()
    tx.device_id = txdlib.DeviceType.DEVICE_D3D9
    used = {}
    for ob in objects:
        for m in ob.data.materials:
            for n2 in m.node_tree.nodes:
                if n2.type == "TEX_IMAGE" and n2.image and KIND.get(m.name) in ("x", "glass", "lod"):
                    used[n2.image.name] = n2.image
    tx.native_textures = [make_native(img, name) for name, img in sorted(used.items())]
    tx.write_file(path, 0x36003)
    print(f"[turbus] {os.path.basename(path)}: {len(used)} texturas, {os.path.getsize(path)} bytes")

write_txd(os.path.join(models, "turbus.txd"), [O["turbus_hall_x"], O["turbus_canopy_x"]])
write_txd(os.path.join(models, "turbus_lod.txd"), [O["turbus_lod_lod"]])

for piece, coll in COLS.items():
    path = os.path.join(models, f"turbus_{piece}.col")
    col_exporter.export_col({
        "file_name": path, "version": 3, "collection": coll, "apply_transformations": True,
        "only_selected": False, "clean_mesh": True, "export_face_groups": False,
    })
    if piece == "bounds":
        # Solo límites (para el recorte de dibujo), sin cajas: las piezas se crean como edificios
        # (createBuilding) y un edificio choca con su COL. COL3: numBoxes (uint16) en 74, flags (uint32) en 80
        # (bit 2 = «no vacío»).
        with open(path, "r+b") as f:
            f.seek(74); f.write(b"\x00\x00")
            f.seek(80); f.write(b"\x00\x00\x00\x00")
    print(f"[turbus] turbus_{piece}.col: {len(coll.objects)} cajas, {os.path.getsize(path)} bytes")

# ---------------------------------------------------------------- .blend sin material de Rockstar
for tex, img in list(ref_images.items()):
    for m in bpy.data.materials:
        if m.node_tree:
            for n2 in m.node_tree.nodes:
                if n2.type == "TEX_IMAGE" and n2.image == img:
                    ph = bpy.data.images.get(tex + "_ph") or bpy.data.images.new(tex + "_ph", 8, 8)
                    n2.image = ph
    bpy.data.images.remove(img)
for img in [i for i in bpy.data.images if ".txd/" in i.name]:
    bpy.data.images.remove(img)
for img in [i for i in bpy.data.images if i.users == 0]:
    bpy.data.images.remove(img)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(RES, "tools", "terminal.blend"), compress=True)
print("[turbus] listo")
