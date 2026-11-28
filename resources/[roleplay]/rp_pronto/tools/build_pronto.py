"""
rp_pronto / tools/build_pronto.py

Modela en Blender la bencinera Copec con tienda Pronto Express de Idlewood (Los Santos), en el lugar de la
gasolinera original (laepetrol1a): tienda de fachada gris con cornisa roja, banda de lamas oscuras con el logo
«PRONTO express» y su mascota, vidriera con puerta de marco rojo, panel travertino con iconos, puerta de servicio,
interior recorrible (piso de baldosa, cielo raso con luminarias, mesón con cajas, barra de café, pantallas de
menú, barra junto a la ventana); túnel de lavado «LAVADO» al oeste (los cepillos del juego se quedan); techo de
surtidores Copec (blanco con franja roja y azul) con isla y pilares; tótem de precios; estacionamientos al sur
con el de movilidad reducida pintado de azul.

Exporta con el addon DragonFF (GPL, github.com/Parik27/DragonFF; no está en el repo):
  models/pronto_shop.dff       tienda y lavado con texturas NATIVAS (TXD barrio1_lae, el de la gasolinera)
  models/pronto_shop_x.dff     detalles con texturas propias (pronto.txd)
  models/pronto_canopy.dff     isla de surtidores (texturas nativas)
  models/pronto_canopy_x.dff   techo Copec, pilares, tótem, pintura de estacionamientos (texturas propias)
  models/pronto_lod.dff        LOD para la distancia (pronto_lod.txd)
  models/pronto.txd, models/pronto_lod.txd   texturas propias DXT1 con mipmaps
  models/pronto_shop.col, pronto_canopy.col, pronto_bounds.col
  client/c_glass_data.lua      triángulos del vidrio (se dibujan con dxDrawPrimitive3D, no son modelo)
  shared/s_props.lua           muebles nativos del interior (góndolas, refrigeradores, cajas, café)
  tools/pronto.blend           para retocar a mano (sin texturas de Rockstar dentro)

Uso (Blender 4.2, sin ventana):
  blender.exe --background --factory-startup --python build_pronto.py -- <carpeta con DragonFF/> [<recurso>] [<ref>] [--quick]
<ref> (opcional) = DFF/TXD originales sacados con tools/extraer-img.ps1 (laeroad24, laeroad38, carwashalphas_lae,
washgaspump, barrio1_lae.txd, ...) y, en <ref>/../props, los muebles nativos del interior. Sirven de molde para el
horneado y para las vistas previas (dia_*.png / noche_*.png en <ref>). Nada de eso va al repo.

Ejes: se modela en coordenadas del mundo de GTA y al exportar se resta ORIGIN (los modelos van en ORIGIN, rot 0).
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
PROPS_DIR = os.path.join(os.path.dirname(os.path.normpath(REF)), "props") if REF else ""

# ---------------------------------------------------------------- medidas del sitio (sacadas del mapa original)
ORIGIN = Vector((1921.0, -1776.0, 12.55))   # posición de los modelos en el juego (shared/s_config.lua)
PAD = 12.55        # losa de la tienda original (x 1913.7..1931.7, y -1787.4..-1762.4)
LOT = 12.38        # asfalto (pista de surtidores, carril del lavado, estacionamiento sur)
FLOOR = 12.63      # piso de la tienda (8 cm sobre la losa)

BX0, BX1, BY0, BY1 = 1914.4, 1927.9, -1785.8, -1766.6       # caja de la tienda (fachada principal en x = BX1)
WT = 0.2                                                   # grosor de muros
CEIL = FLOOR + 3.3                                         # cielo raso interior
GLASS_TOP = FLOOR + 2.75                                   # dintel de las vidrieras
STRIP0 = GLASS_TOP + 0.12                                  # franja roja bajo la banda
BAND0, BAND1 = STRIP0 + 0.08, STRIP0 + 0.08 + 1.2          # banda de lamas con el logo
ROOF = BAND1 + 0.17                                        # techo
CORN0, CORN1, CORN_OUT = BAND1, ROOF + 0.15, 1.8           # cornisa roja que vuela sobre la vereda
DOOR0, DOOR1 = -1777.3, -1775.45                           # puerta (y) en la fachada este
TRAV0, TRAV1 = -1775.2, -1770.4                            # panel travertino
NWIN0, NWIN1 = 1915.2, 1921.6                              # ventana norte (x)
ROOMX = 1921.85                                            # bodega/baño cerrado en la esquina NE (x ROOMX..BX1, y TRAV1..BY1)

BAY_X0, BAY_Y0, BAY_Y1 = 1907.95, -1781.0, -1771.6         # túnel de lavado (los cepillos del juego: x 1908.8..1913.6)
BAY_C0, BAY_C1 = 15.78, 16.28                              # losa del lavado (los cepillos llegan a 15.67)

CX0, CX1, CY0, CY1 = 1933.2, 1950.2, -1782.6, -1763.4     # techo de surtidores
CAN0, CAN1 = LOT + 4.95, LOT + 4.95 + 1.2                  # cara inferior / borde superior de la fascia
PUMP_X = 1941.656                                          # surtidores del juego (washgaspump, y -1767.3..-1778.5)
ISL = (PUMP_X - 1.1, PUMP_X + 1.1, -1782.0, -1764.0)
TOTEM = Vector((1953.2, -1764.4))                          # tótem de precios (donde estaba el letrero «Going»)

# ---------------------------------------------------------------- escena limpia + DragonFF
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
if DRAGON_PARENT:
    sys.path.insert(0, DRAGON_PARENT)
import DragonFF
DragonFF.register()
rng = np.random.default_rng(1977)

# ---------------------------------------------------------------- texturas propias (pequeñas, estilo SA)
def blur(a, passes, axis=None):
    for _ in range(passes):
        if axis is None:
            a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5
        else:
            a = (a + np.roll(a, 1, axis) + np.roll(a, -1, axis)) / 3
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

def make_image(name, rgb):
    """rgb: (h, w, 3) sRGB 0..1 (fila 0 = abajo, como Blender)."""
    h, w = rgb.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.pixels.foreach_set(np.concatenate([np.clip(rgb, 0, 1), np.ones((h, w, 1))], axis=2).astype(np.float32).ravel())
    img.pack()
    IMAGES[name] = img
    return img

RED = (0.80, 0.07, 0.10)          # rojo Pronto
NAVY = (0.12, 0.13, 0.19)         # lamas
CREAM = (0.97, 0.95, 0.89)
CBLUE = (0.06, 0.16, 0.45)        # azul Copec
WHITE = (0.94, 0.94, 0.93)

def lamas(h, w, period):
    """Lamas horizontales oscuras: cara de cada lama con degradado y junta en sombra."""
    rows = np.arange(h)
    ph = (rows % period) / period
    shade = np.where(ph < 0.14, 0.45, 0.82 + 0.38 * ph)
    a = np.array(NAVY)[None, None, :] * shade[:, None, None] * np.ones((h, w, 1))
    return np.clip(a * (0.95 + 0.1 * fbm(h, w)[..., None]), 0, 1)

make_image("px_lamas", lamas(64, 64, 16))                       # 0,6 m por repetición: 4 lamas
make_image("px_navy", solid(32, 32, NAVY, 0.06))
make_image("px_red", solid(32, 32, RED, 0.04))
make_image("px_white", solid(32, 32, WHITE, 0.03))
make_image("px_render", solid(128, 128, (0.34, 0.36, 0.40), 0.07))     # estuco gris azulado de los muros
make_image("px_wall_w", solid(64, 64, (0.90, 0.90, 0.88), 0.03))
st = np.tile(blur(rng.random(64)[None, :], 2), (64, 1))[..., None]
make_image("px_alu", np.clip(0.30 + 0.05 * (st - 0.5) + np.zeros((64, 64, 3)), 0, 1))
make_image("px_steel", np.clip(0.74 + 0.08 * (st - 0.5) + np.zeros((64, 64, 3)), 0, 1) * np.array((1.0, 1.0, 1.02)))
make_image("px_wood", np.clip(np.array((0.50, 0.34, 0.21)) * (0.85 + 0.3 * blur(rng.random((64, 64)), 6, axis=1)[..., None]), 0, 1))
# travertino: vetas horizontales y juntas de placas 1,2 x 0,6 m (128 px = 1,2 m)
vein = blur(rng.random((128, 128)), 30, axis=1)
vein = (vein - vein.min()) / (vein.max() - vein.min())
trav = np.array((0.84, 0.79, 0.69))[None, None, :] * (0.90 + 0.14 * vein[..., None]) * (0.97 + 0.06 * fbm(128, 128)[..., None])
trav[0], trav[64], trav[:, 0] = trav[0] * 0.72, trav[64] * 0.72, trav[:, 0] * 0.72
make_image("px_trav", trav)
# baldosa del piso 60 x 60 cm (128 px = 1,2 m) y cielo raso 60 x 60
def tiles(base, grout, var):
    t = np.array(base)[None, None, :] * np.ones((128, 128, 1))
    for i in range(2):
        for j in range(2):
            t[i * 64:(i + 1) * 64, j * 64:(j + 1) * 64] *= 1 + var * (rng.random() - 0.5)
    t *= (0.97 + 0.05 * fbm(128, 128))[..., None]
    for k in (0, 63, 64, 127):
        t[k] = grout
        t[:, k] = grout
    return np.clip(t, 0, 1)
make_image("px_floor", tiles((0.86, 0.85, 0.81), 0.58, 0.05))
make_image("px_ceiling", tiles((0.92, 0.92, 0.91), 0.70, 0.02))
lt = np.full((32, 32, 3), 0.98)
lt[:2], lt[-2:], lt[:, :2], lt[:, -2:] = 0.62, 0.62, 0.62, 0.62
make_image("px_light", lt)
dr = np.full((128, 64, 3), 0.21)
dr[:, :3], dr[:, -3:], dr[-3:] = 0.34, 0.34, 0.34
dr[56:64, 48:56] = 0.70                                            # manilla
make_image("px_door", dr * (0.95 + 0.1 * fbm(128, 64)[..., None]))
yy, xx = np.mgrid[0:64, 0:64]
make_image("px_yb", np.where((((xx + yy) // 16) % 2 == 0)[..., None], np.array((0.95, 0.76, 0.10)), np.array((0.08, 0.08, 0.08))) * np.ones((64, 64, 3)))
# Copec: fascia blanca con franja roja abajo y línea azul (64 px = 1,2 m de alto)
fas = np.array(WHITE)[None, None, :] * np.ones((64, 128, 1))
fas[:13] = RED
fas[13:16] = CBLUE
fas[-2:] = 0.72
make_image("px_fascia", fas * (0.97 + 0.05 * fbm(64, 128)[..., None]))

# ---------------------------------------------------------------- letreros: texto rasterizado con Workbench + dibujo numpy
FONT_PRONTO = r"C:\Windows\Fonts\GOTHIC.TTF"     # geométrica, como el logo de Pronto
FONT_BOLD = r"C:\Windows\Fonts\GOTHICB.TTF"
FONT_SCRIPT = r"C:\Windows\Fonts\segoescb.ttf"   # «express» manuscrita
FONT_UI = r"C:\Windows\Fonts\segoeuib.ttf"
FONT_LED = r"C:\Windows\Fonts\bahnschrift.ttf"
import tempfile
TMP = tempfile.mkdtemp(prefix="pronto_txt_")

def text_mask(w, h, items):
    """Máscara 0..1 (h, w) del texto en blanco sobre negro. items: (texto, cx, cy, alto, fuente, max_ancho) en
    fracciones de la imagen. Se rasteriza al doble y se reduce (bordes suaves)."""
    sc = bpy.data.scenes.new("txt")
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
    bgo.color = (0, 0, 0, 1)
    sc.collection.objects.link(bgo)
    for text, cx, cy, th, fpath, maxw in items:
        cu = bpy.data.curves.new("t", "FONT")
        cu.body = text
        if os.path.exists(fpath):
            cu.font = bpy.data.fonts.load(fpath, check_existing=True)
        cu.align_x, cu.align_y = "CENTER", "CENTER"
        cu.size = 1.0
        ob = bpy.data.objects.new("t", cu)
        ob.color = (1, 1, 1, 1)
        sc.collection.objects.link(ob)
        dg = bpy.context.evaluated_depsgraph_get()
        dg.update()
        bb = [Vector(c) for c in ob.evaluated_get(dg).bound_box]
        tw = max(c.x for c in bb) - min(c.x for c in bb)
        tht = max(c.y for c in bb) - min(c.y for c in bb)
        cu.size = min(th * H / max(tht, 1e-4), maxw * W / max(tw, 1e-4))
        ob.location = (cx * W, cy * H, 0.01)
    path = os.path.join(TMP, "m%d.png" % len(os.listdir(TMP)))
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=sc.name)
    src = bpy.data.images.load(path)
    px = np.array(src.pixels[:], dtype=np.float32).reshape(h * 2, w * 2, 4)[..., 0]
    bpy.data.images.remove(src)
    for o in list(sc.collection.objects):
        bpy.data.objects.remove(o)
    bpy.data.scenes.remove(sc)
    return px.reshape(h, 2, w, 2).mean(axis=(1, 3))

def paint(img, mask, color):
    m = np.clip(mask, 0, 1)[..., None]
    return img * (1 - m) + np.array(color)[None, None, :] * m

def write_text(img, items, color):
    h, w = img.shape[:2]
    return paint(img, text_mask(w, h, items), color)

def rbox(lx, ly, hw, hh, r):
    qx, qy = np.abs(lx) - (hw - r), np.abs(ly) - (hh - r)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r

def draw_mascot(img, cx, cy, s, ang=-9.0):
    """La mascota de Pronto: cuadrado rojo redondeado con ojos grandes, sonrisa y hoja verde, borde blanco."""
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    a = math.radians(ang)
    dx, dy = xx - cx, yy - cy
    lx = dx * math.cos(a) + dy * math.sin(a)
    ly = -dx * math.sin(a) + dy * math.cos(a)
    def disc(px_, py_, r):
        return np.clip(0.5 + r - np.hypot(lx - px_, ly - py_), 0, 1)
    def ellipse(px_, py_, ra, rb, rot):
        c, sn = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        u = (lx - px_) * c + (ly - py_) * sn
        v = -(lx - px_) * sn + (ly - py_) * c
        d = np.sqrt((u / ra) ** 2 + (v / rb) ** 2)
        return np.clip((1 - d) * min(ra, rb) + 0.5, 0, 1)
    leaf = (-0.40 * s, 0.60 * s, 0.24 * s, 0.11 * s, 35)
    img = paint(img, ellipse(leaf[0], leaf[1], leaf[2] + 0.05 * s, leaf[3] + 0.05 * s, leaf[4]), CREAM)
    img = paint(img, np.clip(0.5 - (rbox(lx, ly, 0.5 * s, 0.56 * s, 0.2 * s) - 0.05 * s), 0, 1), CREAM)
    img = paint(img, ellipse(*leaf), (0.30, 0.66, 0.18))
    body = np.clip(0.5 - rbox(lx, ly, 0.5 * s, 0.56 * s, 0.2 * s), 0, 1)
    grad = np.clip(0.5 + ly / (1.1 * s), 0, 1)[..., None]
    body_col = np.array(RED) * (0.9 + 0.25 * grad)
    img = img * (1 - body[..., None]) + body_col * body[..., None]
    for ex in (-0.18, 0.18):
        img = paint(img, disc(ex * s, 0.14 * s, 0.17 * s), (0.99, 0.99, 0.98))
        img = paint(img, disc(ex * s + 0.04 * s, 0.11 * s, 0.08 * s), (0.04, 0.04, 0.05))
        img = paint(img, disc(ex * s + 0.06 * s, 0.14 * s, 0.025 * s), (1, 1, 1))
    ring = np.clip(0.5 + 0.035 * s - np.abs(np.hypot(lx, ly + 0.02 * s) - 0.24 * s), 0, 1) * (ly < -0.15 * s)
    return paint(img, ring, (0.30, 0.02, 0.04))

# Logo de la banda: lamas + mascota + «PRONTO express» (512 x 128 = 4,8 x 1,2 m, misma densidad que px_lamas)
logo = lamas(128, 512, 16)
logo = draw_mascot(logo, 62, 64, 92)
logo = write_text(logo, [("PRONTO", 0.60, 0.62, 0.40, FONT_PRONTO, 0.66)], CREAM)
logo = write_text(logo, [("express", 0.50, 0.25, 0.30, FONT_SCRIPT, 0.30)], CREAM)
make_image("px_logo", logo)
# Logo compacto (tótem): mascota arriba y texto abajo
lg2 = np.array(NAVY)[None, None, :] * np.ones((128, 128, 1))
lg2 = draw_mascot(lg2, 64, 84, 52)
lg2 = write_text(lg2, [("PRONTO", 0.5, 0.30, 0.15, FONT_PRONTO, 0.86)], CREAM)
lg2 = write_text(lg2, [("express", 0.5, 0.13, 0.12, FONT_SCRIPT, 0.5)], CREAM)
make_image("px_logo2", lg2)
# Copec en la fascia: mismas franjas que px_fascia (256 x 64 = 4,8 x 1,2 m de alto... 4:1)
cop = np.array(WHITE)[None, None, :] * np.ones((64, 256, 1))
cop[:13] = RED
cop[13:16] = CBLUE
cop[-2:] = 0.72
cop = write_text(cop, [("COPEC", 0.5, 0.60, 0.50, FONT_BOLD, 0.62)], CBLUE)
make_image("px_copec", cop)
# panel Copec del tótem (cuadrado, fondo blanco)
copt = np.array(WHITE)[None, None, :] * np.ones((64, 128, 1))
copt[:10] = RED
copt[10:13] = CBLUE
copt = write_text(copt, [("COPEC", 0.5, 0.60, 0.46, FONT_BOLD, 0.84)], CBLUE)
make_image("px_copec_t", copt)
# precios del tótem (128 x 256): bencinas 93/95/97 y diésel, dígitos LED ámbar
tot = solid(256, 128, (0.04, 0.04, 0.05), 0.05)
tot = write_text(tot, [("PRECIOS $/L", 0.5, 0.93, 0.05, FONT_UI, 0.8)], (0.92, 0.92, 0.92))
for i, (lab, pr) in enumerate((("93", "1.289"), ("95", "1.329"), ("97", "1.389"), ("DIÉSEL", "1.059"))):
    cy = 0.77 - i * 0.215
    tot[int((cy - 0.10) * 256):int((cy - 0.095) * 256)] = 0.25
    tot = write_text(tot, [(lab, 0.20, cy, 0.075 if lab != "DIÉSEL" else 0.05, FONT_UI, 0.32)], (0.95, 0.95, 0.95))
    tot = write_text(tot, [(pr, 0.68, cy, 0.10, FONT_LED, 0.58)], (1.0, 0.55, 0.10))
make_image("px_totem", tot)
# pantallas de menú (512 x 128: tres pantallas)
men = np.zeros((128, 512, 3))
men[:, :170] = (0.24, 0.13, 0.07)
men[:, 170:342] = RED
men[:, 342:] = (0.10, 0.12, 0.30)
men[:, 168:172] = 0.03
men[:, 340:344] = 0.03
men = write_text(men, [("CAFÉ PRONTO", 0.166, 0.74, 0.14, FONT_BOLD, 0.30)], CREAM)
men = write_text(men, [("Americano · Latte · Capuccino", 0.166, 0.48, 0.07, FONT_UI, 0.30)], (0.95, 0.85, 0.65))
men = write_text(men, [("desde $1.290", 0.166, 0.22, 0.14, FONT_LED, 0.28)], (1.0, 0.80, 0.30))
men = write_text(men, [("COMPLETO", 0.5, 0.76, 0.14, FONT_BOLD, 0.30)], (1, 1, 1))
men = write_text(men, [("ITALIANO + BEBIDA", 0.5, 0.52, 0.08, FONT_UI, 0.30)], (1, 0.92, 0.85))
men = write_text(men, [("$2.490", 0.5, 0.24, 0.20, FONT_LED, 0.28)], (1, 1, 1))
men = write_text(men, [("PROMO 2x", 0.834, 0.76, 0.14, FONT_BOLD, 0.30)], (1.0, 0.85, 0.20))
men = write_text(men, [("BEBIDAS 500 ml", 0.834, 0.52, 0.08, FONT_UI, 0.30)], (0.9, 0.92, 1.0))
men = write_text(men, [("$1.500", 0.834, 0.24, 0.20, FONT_LED, 0.28)], (1, 1, 1))
make_image("px_menu", men)
# banda interior (512 x 64)
ban = np.array(RED)[None, None, :] * np.ones((64, 512, 1))
ban[:6] = (0.55, 0.04, 0.06)
ban = write_text(ban, [("Todo lo que buscas y a tu ritmo", 0.44, 0.55, 0.50, FONT_PRONTO, 0.70)], (1, 1, 1))
ban = write_text(ban, [("PRONTO", 0.90, 0.55, 0.40, FONT_PRONTO, 0.14)], CREAM)
make_image("px_banner", ban)
# frente del mesón (256 x 64): blanco con franja roja arriba
cnt = np.array(WHITE)[None, None, :] * np.ones((64, 256, 1))
cnt[-12:] = RED
cnt = write_text(cnt, [("PRONTO", 0.5, 0.42, 0.34, FONT_PRONTO, 0.4)], RED)
make_image("px_counter", cnt * (0.97 + 0.05 * fbm(64, 256)[..., None]))
# iconos redondos del panel travertino (128 x 64): baño y 24 horas, blanco sobre rojo
ico = np.array(RED)[None, None, :] * np.ones((64, 128, 1))
ico = write_text(ico, [("WC", 0.25, 0.5, 0.40, FONT_BOLD, 0.34)], (1, 1, 1))
ico = write_text(ico, [("24", 0.75, 0.60, 0.36, FONT_BOLD, 0.30)], (1, 1, 1))
ico = write_text(ico, [("HORAS", 0.75, 0.28, 0.12, FONT_UI, 0.30)], (1, 1, 1))
make_image("px_icons", ico)
# letrero del lavado (256 x 64)
lav = np.array(RED)[None, None, :] * np.ones((64, 256, 1))
lav = write_text(lav, [("LAVADO", 0.42, 0.52, 0.56, FONT_BOLD, 0.60)], (1, 1, 1))
lav[:, 200:] = WHITE
lav = write_text(lav, [("COPEC", 0.89, 0.5, 0.22, FONT_BOLD, 0.19)], CBLUE)
make_image("px_lavado", lav)
# afiches de la vidriera (256 x 128: dos afiches)
pos = np.zeros((128, 256, 3))
pos[:, :128] = (0.98, 0.84, 0.18)
pos[:, 128:] = RED
pos[:, 126:130] = 0.95
pos = write_text(pos, [("$990", 0.25, 0.62, 0.30, FONT_LED, 0.44)], RED)
pos = write_text(pos, [("CAFÉ + MEDIALUNA", 0.25, 0.30, 0.08, FONT_UI, 0.44)], (0.15, 0.10, 0.05))
pos = write_text(pos, [("COMPLETO", 0.75, 0.72, 0.12, FONT_BOLD, 0.44)], (1, 1, 1))
pos = write_text(pos, [("$1.990", 0.75, 0.42, 0.22, FONT_LED, 0.44)], (1.0, 0.92, 0.30))
pos = write_text(pos, [("solo en Pronto", 0.75, 0.16, 0.08, FONT_SCRIPT, 0.40)], (1, 1, 1))
make_image("px_poster", pos)
# estacionamiento de movilidad reducida (128 x 128): azul con el símbolo en blanco
acc = np.array((0.10, 0.28, 0.62))[None, None, :] * np.ones((128, 128, 1))
yy, xx = np.mgrid[0:128, 0:128] + 0.5
ring = np.clip(0.5 + 4 - np.abs(np.hypot(xx - 58, yy - 46) - 24), 0, 1)
gap = (xx > 58) & (yy > 46)
sym = np.maximum(ring * ~gap, np.clip(0.5 + 9 - np.hypot(xx - 60, yy - 100), 0, 1))
sym = np.maximum(sym, ((np.abs(xx - 60) < 5) & (yy > 50) & (yy < 88)).astype(float))
sym = np.maximum(sym, ((yy > 50) & (yy < 58) & (xx > 60) & (xx < 88)).astype(float))
sym = np.maximum(sym, ((np.abs(xx - 86) < 4) & (yy > 24) & (yy < 58)).astype(float))
acc = paint(acc, sym, (0.96, 0.96, 0.96))
make_image("px_access", acc)
make_image("px_blue", solid(16, 16, (0.10, 0.28, 0.62), 0.04))
# LOD
make_image("px_lod_wall", solid(16, 16, (0.34, 0.36, 0.40), 0.05))
lg = np.full((32, 32, 3), 0.18) * np.array((0.9, 1.0, 1.05))
lg[:, ::8] = 0.32
make_image("px_lod_glass", lg)
make_image("px_lod_navy", solid(16, 16, NAVY, 0.03))
make_image("px_lod_red", solid(16, 16, RED, 0.03))
make_image("px_lod_white", solid(16, 16, WHITE, 0.03))
make_image("px_lod_roof", solid(16, 16, (0.55, 0.55, 0.53), 0.05))

# ---------------------------------------------------------------- materiales
NATIVE_TXD = "barrio1_lae"           # el de la gasolinera original; lo usa también laeroad24 (5489), que se queda
NATIVE = {                           # textura -> (m por repetición u, v, z de inicio de v)
    "roof06L256":         (10.0, 10.0, 0.0),
    "concretenewgery256": (3.0, 3.0, 0.0),
    "gen_chrome":         (1.0, 1.0, 0.0),
    "metpat64":           (1.0, 1.0, 0.0),
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

def make_mat(key, image, kind, uv=(2.0, 2.0, 0.0), glow=False):
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (1, 1, 1, 1)
    p.inputs["Roughness"].default_value = 0.8
    p.inputs["Metallic"].default_value = 0.0
    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    m.node_tree.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    # ambient 1, diffuse 1, specular 0 como los edificios de SA (DragonFF trae 0.5/0.5/0.5: brillo según el ángulo)
    m.dff.ambient, m.dff.diffuse, m.dff.specular = 1.0, 1.0, 0.0
    MAT[key], KIND[key], UVS[key] = m, kind, uv
    if glow:
        GLOW.add(key)
    return m

for tex, uv in NATIVE.items():
    make_mat("n_" + tex, native_image(tex), "nat", uv)
X_MATS = {   # clave -> (uv, brilla de noche)
    "px_lamas": ((2.0, 0.6, BAND0), False), "px_navy": ((1, 1, 0), False), "px_red": ((1, 1, 0), False),
    "px_white": ((1, 1, 0), False), "px_render": ((3.0, 3.0, 0), False), "px_wall_w": ((2, 2, 0), False),
    "px_alu": ((1, 1, 0), False), "px_steel": ((1, 1, 0), False), "px_wood": ((1.2, 1.2, 0), False),
    "px_trav": ((1.2, 1.2, FLOOR), False), "px_floor": ((1.2, 1.2, 0), False), "px_ceiling": ((1.2, 1.2, 0), False),
    "px_light": ((1, 1, 0), True), "px_door": ((1, 1, 0), False), "px_yb": ((0.6, 0.6, 0), False),
    "px_fascia": ((4.0, 1.3, CAN0 - 0.1), True), "px_logo": (None, True), "px_logo2": (None, True),
    "px_copec": (None, True), "px_copec_t": (None, True), "px_totem": (None, True), "px_menu": (None, True),
    "px_banner": (None, False), "px_counter": (None, False), "px_icons": (None, False), "px_lavado": (None, True),
    "px_poster": (None, True), "px_access": (None, False), "px_blue": ((1, 1, 0), False),
}
for key, (uv, glow) in X_MATS.items():
    make_mat(key, IMAGES[key], "x", uv, glow)
GLASS_MAT = make_mat("px_glass_dummy", IMAGES["px_white"], "glass", (3, 3, 0))
for key in ("px_lod_wall", "px_lod_glass", "px_lod_navy", "px_lod_red", "px_lod_white", "px_lod_roof"):
    make_mat(key, IMAGES[key], "lod", (8, 8, 0) if key != "px_lod_glass" else (4, 4, FLOOR))

# ---------------------------------------------------------------- construcción (bmesh por pieza y tipo)
class Piece:
    """Una pieza (shop, canopy, lod). Cada cara va a la malla de su tipo de material:
    nat (texturas del juego), x (propias), glass (vidrio: va a primitivas 3D) o lod."""
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
        """Cuadrilátero subdividido en celdas de ~cell metros (degradado de la luz horneada).
        Orden antihorario visto desde fuera."""
        p0, p1, p2, p3 = map(Vector, (p0, p1, p2, p3))
        nu = max(1, round((p1 - p0).length / cell)) if cell else 1
        nv = max(1, round((p3 - p0).length / cell)) if cell else 1
        def P(i, j):
            a, b = i / nu, j / nv
            return (p0 * (1 - a) + p1 * a) * (1 - b) + (p3 * (1 - a) + p2 * a) * b
        def U(i, j):
            a, b = i / nu, j / nv
            q = [Vector(u) for u in uvs]
            return (q[0] * (1 - a) + q[1] * a) * (1 - b) + (q[3] * (1 - a) + q[2] * a) * b
        for i in range(nu):
            for j in range(nv):
                pts = [P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)]
                self.face(pts, mat, [U(i, j), U(i + 1, j), U(i + 1, j + 1), U(i, j + 1)] if uvs else None)

    def vstrip(self, pa, pb, za, zb, n, parts, cell=2.0):
        """Cara vertical de pa a pb (2D), de za a zb, mirando a n, partida en tramos
        parts = [(s0, s1, mat, (u0, u1, v0, v1) o None)], s en metros desde la IZQUIERDA vista desde fuera."""
        pa, pb, n = Vector((pa[0], pa[1], 0)), Vector((pb[0], pb[1], 0)), Vector((n[0], n[1], 0))
        if (pb - pa).dot(Vector((0, 0, 1)).cross(n)) < 0:
            pa, pb = pb, pa
        t = (pb - pa).normalized()
        for s0, s1, mat, uv in parts:
            A, B = pa + t * s0, pa + t * s1
            uvs = [(uv[0], uv[2]), (uv[1], uv[2]), (uv[1], uv[3]), (uv[0], uv[3])] if uv else None
            self.quad((A.x, A.y, za), (B.x, B.y, za), (B.x, B.y, zb), (A.x, A.y, zb), mat, cell if not uv else 0, uvs)

    def vquad(self, pa, pb, za, zb, n, mat, cell=2.0):
        L = (Vector(pb) - Vector(pa)).length
        self.vstrip(pa, pb, za, zb, n, [(0.0, L, mat, None)], cell)

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

    def hquad(self, x0, y0, x1, y1, z, mat, down=False, cell=2.0, uvs=None):
        pts = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
        if down:
            pts = pts[::-1]
            uvs = uvs[::-1] if uvs else None
        self.quad(*pts, mat, cell, uvs)

    def cyl(self, a, b, r, mat, segs=10, caps=True):
        a, b = Vector(a), Vector(b)
        q = Vector((0, 0, 1)).rotation_difference((b - a).normalized())
        su, sv, _ = UVS[mat] or (1, 1, 0)
        L = (b - a).length
        ring = [q @ Vector((math.cos(2 * math.pi * k / segs) * r, math.sin(2 * math.pi * k / segs) * r, 0)) for k in range(segs + 1)]
        for k in range(segs):
            u0, u1 = k / segs * 2 * math.pi * r / su, (k + 1) / segs * 2 * math.pi * r / su
            self.face([a + ring[k], a + ring[k + 1], b + ring[k + 1], b + ring[k]], mat, [(u0, 0), (u1, 0), (u1, L / sv), (u0, L / sv)])
        if caps:
            self.face([b + ring[k] for k in range(segs)], mat, [(0.5, 0.5)] * segs)
            self.face([a + ring[k] for k in reversed(range(segs))], mat, [(0.5, 0.5)] * segs)

    def sign(self, center, normal, w, h, mat, depth=0.12, side_mat="px_navy", both=True, u0=0.0, u1=1.0, back_mat=None):
        """Letrero tipo caja: la imagen (u0..u1) hacia `normal` (±x o ±y) y, si both, también atrás."""
        c, n = Vector(center), Vector((normal[0], normal[1], 0))
        t = Vector((-n.y, n.x, 0))
        hw, hh, hd = w / 2, h / 2, depth / 2
        def corner(sx, sz, sd):
            return c + t * (sx * hw) + Vector((0, 0, sz * hh)) + n * (sd * hd)
        self.face([corner(-1, -1, 1), corner(1, -1, 1), corner(1, 1, 1), corner(-1, 1, 1)], mat, [(u0, 0), (u1, 0), (u1, 1), (u0, 1)])
        back = mat if both else (back_mat or side_mat)
        self.face([corner(1, -1, -1), corner(-1, -1, -1), corner(-1, 1, -1), corner(1, 1, -1)], back, [(u0, 0), (u1, 0), (u1, 1), (u0, 1)])
        for a, b in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
            self.face([corner(a[0], a[1], -1), corner(b[0], b[1], -1), corner(b[0], b[1], 1), corner(a[0], a[1], 1)], side_mat)

    def disc(self, center, normal, r, mat, u0, u1, segs=16, depth=0.04, rim="px_red"):
        """Icono redondo: disco con la textura (región u0..u1 x 0..1, círculo inscrito) y canto."""
        c, n = Vector(center), Vector((normal[0], normal[1], 0))
        t = Vector((-n.y, n.x, 0))
        up = Vector((0, 0, 1))
        front, back, uvs = [], [], []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            off = t * (math.cos(a) * r) + up * (math.sin(a) * r)
            front.append(c + n * depth + off)
            back.append(c + off)
            uvs.append(((u0 + u1) / 2 + (u1 - u0) / 2 * math.cos(a), 0.5 + 0.5 * math.sin(a)))
        self.face(front, mat, uvs)
        for k in range(segs):
            k2 = (k + 1) % segs
            self.face([back[k], back[k2], front[k2], front[k]], rim)

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
SURF = {"pavement": 4, "glass": 46, "girder": 56, "plastic": 68, "wood": 43, "default": 0}
COLS = {}

def col_box(piece, x0, y0, z0, x1, y1, z1, surf="default"):
    coll = COLS.get(piece)
    if coll is None:
        coll = bpy.data.collections.new(f"pronto_{piece}")
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

# ================================================================ TIENDA
shop = Piece("pronto_shop")
z0 = FLOOR
IX0, IX1, IY0, IY1 = BX0 + WT, BX1 - WT, BY0 + WT, BY1 - WT       # caras interiores de los muros

# Losa del piso: baldosa dentro, canto de hormigón (8 cm sobre la losa original)
shop.box(BX0, BY0, PAD - 0.15, BX1, BY1, FLOOR, "px_floor", 2.0, mats={k: "n_concretenewgery256" for k in ("-x", "+x", "-y", "+y")}, skip=("bottom",))
col_box("shop", BX0, BY0, PAD - 0.15, BX1, BY1, FLOOR, "pavement")
# Techo: cielo raso abajo, cubierta del juego arriba
shop.box(BX0, BY0, CEIL, BX1, BY1, ROOF, "n_roof06L256", 3.0, mats={"bottom": "px_ceiling"}, skip=("-x", "+x", "-y", "+y"))
col_box("shop", BX0, BY0, CEIL, BX1, BY1, ROOF)

# Muros. Oeste entero (tapa las dos esquinas oeste), sur hasta la esquina SE, este macizo en el tramo travertino+bodega.
# Las caras que quedan en el mismo plano que otra se saltan (z-fighting).
WALLX = {"-x": "px_render", "+x": "px_wall_w", "-y": "px_render", "+y": "px_render"}
shop.box(BX0, BY0, z0, BX0 + WT, BY1, ROOF, "px_render", 2.0, mats=WALLX, skip=("top", "bottom"))
col_box("shop", BX0, BY0, z0, BX0 + WT, BY1, ROOF)
shop.box(BX0 + WT, BY0, z0, BX1, BY0 + WT, ROOF, "px_render", 2.0, mats={"+y": "px_wall_w"}, skip=("top", "bottom", "-x"))
col_box("shop", BX0 + WT, BY0, z0, BX1, BY0 + WT, ROOF)
# norte: macizo a los lados de la ventana
for (xa, xb, sk) in ((BX0 + WT, NWIN0, ("top", "bottom", "-x")), (NWIN1, BX1 - WT, ("top", "bottom", "+x"))):
    shop.box(xa, BY1 - WT, z0, xb, BY1, ROOF, "px_render", 2.0, mats={"-y": "px_wall_w", "-x": "px_alu", "+x": "px_alu"}, skip=sk)
    col_box("shop", xa, BY1 - WT, z0, xb, BY1, ROOF)
# este macizo (travertino + bodega): la cara interior solo frente a la tienda
shop.box(BX1 - WT, TRAV0, z0, BX1, BY1, ROOF, "px_render", 2.0, mats={"-y": "px_alu"}, skip=("top", "bottom", "-x"))
shop.vquad((IX1, TRAV0), (IX1, TRAV1 - 0.15), z0, CEIL, (-1, 0), "px_wall_w")
col_box("shop", BX1 - WT, TRAV0, z0, BX1, BY1, ROOF)
# bodega y baño (cerrados): muros interiores
shop.box(ROOMX, TRAV1 - 0.15, z0, IX1, TRAV1, CEIL, "px_wall_w", 2.0, skip=("top", "bottom", "+y", "+x"))
shop.box(ROOMX, TRAV1, z0, ROOMX + 0.15, IY1, CEIL, "px_wall_w", 2.0, skip=("top", "bottom", "+x", "-y", "+y"))
col_box("shop", ROOMX, TRAV1 - 0.15, z0, BX1, BY1, CEIL)

# Vidrieras: montantes de aluminio, zócalo, dintel; el vidrio es una sola cara (va a primitivas 3D)
GLASS_FACES = []

def glazing(p_start, p_end, outward, mull, door=None):
    """Vidriera de p_start a p_end en el plano exterior del muro (retranqueada 10 cm). door = (s0, s1) hueco."""
    a, b = Vector((*p_start, 0)), Vector((*p_end, 0))
    L = (b - a).length
    t = (b - a).normalized()
    n = Vector((*outward, 0))
    gp = lambda s, off=-0.10: a + t * s + n * off
    cuts = [(0.0, L)] if not door else [(0.0, door[0]), (door[1], L)]
    for s0, s1 in cuts:
        if s1 - s0 < 0.05:
            continue
        p0, p1 = gp(s0), gp(s1)
        GLASS_FACES.append(((p0.x, p0.y), (p1.x, p1.y), z0 + 0.12, GLASS_TOP, (n.x, n.y)))
        q0, q1 = gp(s0, -0.16), gp(s1, -0.04)
        col_box("shop", min(q0.x, q1.x), min(q0.y, q1.y), z0, max(q0.x, q1.x), max(q0.y, q1.y), GLASS_TOP, "glass")
        # zócalo de aluminio
        shop.box(min(q0.x, q1.x), min(q0.y, q1.y), z0, max(q0.x, q1.x), max(q0.y, q1.y), z0 + 0.12, "px_alu", 0, skip=("bottom",))
    if door:
        p0, p1 = gp(door[0]), gp(door[1])
        GLASS_FACES.append(((p0.x, p0.y), (p1.x, p1.y), z0 + 2.45, GLASS_TOP, (n.x, n.y)))
        q0, q1 = gp(door[0], -0.16), gp(door[1], -0.04)
        col_box("shop", min(q0.x, q1.x), min(q0.y, q1.y), z0 + 2.4, max(q0.x, q1.x), max(q0.y, q1.y), GLASS_TOP, "glass")
        # marco rojo de la puerta: jambas y travesaño
        for s in (door[0], door[1]):
            c = gp(s)
            shop.box(c.x - 0.07, c.y - 0.07, z0, c.x + 0.07, c.y + 0.07, z0 + 2.45, "px_red", 0, skip=("bottom",))
        r0, r1 = gp(door[0], -0.07), gp(door[1], 0.07)
        shop.box(min(r0.x, r1.x), min(r0.y, r1.y), z0 + 2.33, max(r0.x, r1.x), max(r0.y, r1.y), z0 + 2.45, "px_red", 0)
    # montantes
    stops = set(round(s, 2) for s in np.linspace(0, L, max(2, round(L / mull)) + 1))
    if door:
        stops = {s for s in stops if not (door[0] - 0.3 < s < door[1] + 0.3)}
    for s in sorted(stops):
        c = gp(min(max(s, 0.05), L - 0.05))
        shop.box(c.x - 0.05, c.y - 0.05, z0 + 0.12, c.x + 0.05, c.y + 0.05, GLASS_TOP, "px_alu", 0, skip=("top", "bottom"))
    # dintel macizo sobre la vidriera (de GLASS_TOP al techo): cara interior blanca, cara inferior de aluminio
    q0, q1 = a + n * (-WT), b
    shop.box(min(q0.x, q1.x), min(q0.y, q1.y), GLASS_TOP, max(q0.x, q1.x), max(q0.y, q1.y), ROOF, "px_render", 0,
             mats={"bottom": "px_alu", ("-x" if outward[0] > 0 else "+x" if outward[0] < 0 else "-y" if outward[1] > 0 else "+y"): "px_wall_w"},
             skip=("top", "-y", "+y") if outward[0] else ("top", "-x", "+x"))
    col_box("shop", min(q0.x, q1.x), min(q0.y, q1.y), GLASS_TOP, max(q0.x, q1.x), max(q0.y, q1.y), ROOF)

glazing((BX1, BY0 + WT), (BX1, TRAV0), (1, 0), 1.7, door=(DOOR0 - (BY0 + WT), DOOR1 - (BY0 + WT)))
glazing((NWIN0, BY1), (NWIN1, BY1), (0, 1), 1.6)

# Fachada este: panel travertino con iconos, puerta de servicio
shop.box(BX1, TRAV0, z0, BX1 + 0.06, TRAV1, STRIP0, "px_trav", 1.2, skip=("bottom", "top", "-x"))
shop.disc((BX1 + 0.06, -1774.35, z0 + 1.95), (1, 0), 0.34, "px_icons", 0.0, 0.5)
shop.disc((BX1 + 0.06, -1774.35, z0 + 1.15), (1, 0), 0.34, "px_icons", 0.5, 1.0)
shop.vstrip((BX1 + 0.03, -1768.9), (BX1 + 0.03, -1767.85), z0, z0 + 2.2, (1, 0), [(0, 1.05, "px_door", (0, 1, 0, 1))])
shop.box(BX1, -1769.0, z0 + 2.2, BX1 + 0.05, -1767.75, z0 + 2.3, "px_alu", 0, skip=("-x",))
# cajas de luz en el muro sur (hacia el estacionamiento): café y completo
for (xc, u0, u1) in ((1918.2, 0.0, 0.5), (1920.0, 0.5, 1.0)):
    shop.sign((xc, BY0 - 0.08, z0 + 1.75), (0, -1), 1.5, 1.5, "px_poster", depth=0.16, both=False, side_mat="px_alu", back_mat="px_alu", u0=u0, u1=u1)
col_box("shop", 1917.4, BY0 - 0.16, z0 + 1.0, 1920.8, BY0, z0 + 2.5)
# afiches pegados por dentro de la vidriera (miran a la calle; atrás blanco)
for (yc, u0, u1) in ((-1784.73, 0.0, 0.5), (-1781.27, 0.5, 1.0), (-1779.53, 0.0, 0.5)):   # centrados en los paneles
    shop.sign((BX1 - 0.13, yc, z0 + 1.55), (1, 0), 0.85, 0.85, "px_poster", depth=0.01, both=False, side_mat="px_white", u0=u0, u1=u1)

# Franja roja, banda de lamas con el logo y cornisa roja (este, norte y sur)
BAND_E = (BY0 - 0.3, BY1 + 0.3)
shop.box(BX1, BAND_E[0], STRIP0, BX1 + 0.3, BAND_E[1], BAND0, "px_red", 2.0, skip=("-x", "top"))
shop.box(BX1, BAND_E[0], BAND0, BX1 + 0.3, BAND_E[1], BAND1, "px_lamas", 2.0, mats={"bottom": "px_navy"}, skip=("-x", "top", "+x", "bottom"))
LW = 4.8                                         # el logo (512 x 128) mide 4,8 x 1,2 m
# vista desde el este, la izquierda es el SUR (y menor): s = y - BAND_E[0]
s_logo = (-1781.0) - BAND_E[0]
shop.vstrip((BX1 + 0.3, BAND_E[0]), (BX1 + 0.3, BAND_E[1]), BAND0, BAND1, (1, 0),
            [(0.0, s_logo, "px_lamas", None), (s_logo, s_logo + LW, "px_logo", (0, 1, 0, 1)),
             (s_logo + LW, BAND_E[1] - BAND_E[0], "px_lamas", None)])
for (ya, yb, nrm) in ((BY1, BY1 + 0.3, (0, 1)), (BY0 - 0.3, BY0, (0, -1))):
    # bandas norte y sur: de la esquina oeste a la banda este
    shop.box(BX0, ya, STRIP0, BX1, yb, BAND0, "px_red", 2.0, skip=("+x", "top", "-y" if nrm[1] > 0 else "+y"))
    shop.box(BX0, ya, BAND0, BX1, yb, BAND1, "px_lamas", 2.0, mats={"top": "px_navy"},
             skip=("+x", "bottom", "-y" if nrm[1] > 0 else "+y", "+y" if nrm[1] > 0 else "-y"))
    yf = yb if nrm[1] > 0 else ya
    L = BX1 - BX0
    # vista desde el norte la izquierda es el ESTE; desde el sur, el OESTE
    s_l = 0.6 if nrm[1] > 0 else L - LW - 0.6
    shop.vstrip((BX0, yf), (BX1, yf), BAND0, BAND1, nrm,
                [(0.0, s_l, "px_lamas", None), (s_l, s_l + LW, "px_logo", (0, 1, 0, 1)), (s_l + LW, L, "px_lamas", None)])
    col_box("shop", BX0, ya, STRIP0, BX1, yb, BAND1)
# cornisa roja que vuela sobre la vereda; por debajo blanca con luminarias lineales
shop.box(BX1, BAND_E[0], CORN0, BX1 + CORN_OUT, BAND_E[1], CORN1, "px_red", 2.0, mats={"top": "n_roof06L256", "bottom": "px_white"}, skip=("-x",))
shop.vquad((BX1, BAND_E[0]), (BX1, BAND_E[1]), ROOF, CORN1, (-1, 0), "px_red")
col_box("shop", BX1, BAND_E[0], STRIP0, BX1 + CORN_OUT, BAND_E[1], CORN1)
for y in np.arange(BY0 + 0.6, BY1 - 0.5, 3.2):
    shop.hquad(BX1 + 0.95, y, BX1 + 1.15, y + 2.4, CORN0 - 0.05, "px_light", down=True, cell=0)
# equipos de clima en la cubierta
for (x, y) in ((1917.6, -1771.0), (1917.6, -1781.5)):
    shop.box(x - 0.8, y - 0.55, ROOF, x + 0.8, y + 0.55, ROOF + 1.0, "n_gen_chrome", 1.0, skip=("bottom",))
    col_box("shop", x - 0.8, y - 0.55, ROOF, x + 0.8, y + 0.55, ROOF + 1.0)

# ---------------------------------------------------------------- interior
# luminarias del cielo raso (paneles 60 x 60 cada 2,4 m)
for x in np.arange(IX0 + 1.5, IX1 - 0.5, 2.4):
    for y in np.arange(IY0 + 1.2, IY1 - 0.5, 2.4):
        if x > ROOMX - 0.3 and y > TRAV1 - 0.3:
            continue
        shop.hquad(x - 0.3, y - 0.3, x + 0.3, y + 0.3, CEIL - 0.03, "px_light", down=True, cell=0)
# banda roja sobre los refrigeradores del muro sur
shop.vstrip((IX0 + 0.4, IY0 + 0.03), (IX0 + 9.9, IY0 + 0.03), z0 + 2.4, z0 + 3.0, (0, 1),
            [(0, 2.35, "px_red", None), (2.35, 7.15, "px_banner", (0, 1, 0, 1)), (7.15, 9.5, "px_red", None)])
# mesón de cajas (frente blanco con franja roja) y cubierta de madera
CNT = (1917.35, 1918.3, -1780.6, -1773.0)
shop.box(CNT[0], CNT[2], z0, CNT[1], CNT[3], z0 + 1.0, "px_white", 1.0, skip=("bottom", "top", "+x"))
shop.vstrip((CNT[1], CNT[2]), (CNT[1], CNT[3]), z0, z0 + 1.0, (1, 0),
            [(0, 3.8, "px_counter", (0, 1, 0, 1)), (3.8, 7.6, "px_counter", (0, 1, 0, 1))])
shop.box(CNT[0] - 0.05, CNT[2] - 0.05, z0 + 1.0, CNT[1] + 0.08, CNT[3] + 0.05, z0 + 1.05, "px_wood", 1.0)
col_box("shop", CNT[0], CNT[2], z0, CNT[1] + 0.08, CNT[3], z0 + 1.05, "wood")
# barra de atrás (café) contra el muro oeste y pantallas de menú encima
shop.box(IX0, -1780.6, z0, IX0 + 0.75, -1772.6, z0 + 0.9, "px_navy", 1.0, mats={"top": "px_steel"}, skip=("bottom", "-x"))
col_box("shop", IX0, -1780.6, z0, IX0 + 0.75, -1772.6, z0 + 0.95, "wood")
for i, yc in enumerate((-1778.55, -1776.8, -1775.05)):       # tres pantallas (cada una un tercio de px_menu)
    shop.sign((IX0 + 0.04, yc, z0 + 2.35), (1, 0), 1.6, 1.2, "px_menu", depth=0.06, both=False, side_mat="px_navy",
              back_mat="px_navy", u0=i / 3, u1=(i + 1) / 3)
# estación de café para clientes contra la bodega
shop.box(1922.4, TRAV1 - 0.75, z0, 1925.4, TRAV1 - 0.15, z0 + 0.92, "px_red", 1.0, mats={"top": "px_steel"}, skip=("bottom", "+y"))
col_box("shop", 1922.4, TRAV1 - 0.75, z0, 1925.4, TRAV1 - 0.15, z0 + 0.95, "wood")
# barra con taburetes junto a la ventana norte
shop.box(NWIN0 + 0.2, IY1 - 0.45, z0 + 1.0, NWIN1 - 0.2, IY1, z0 + 1.05, "px_wood", 1.0)
shop.box(NWIN0 + 0.2, IY1 - 0.08, z0, NWIN1 - 0.2, IY1, z0 + 1.0, "px_navy", 1.0, skip=("bottom", "top", "+y"))
col_box("shop", NWIN0 + 0.2, IY1 - 0.45, z0 + 0.95, NWIN1 - 0.2, IY1, z0 + 1.05, "wood")
for x in np.arange(NWIN0 + 0.8, NWIN1 - 0.5, 1.2):
    shop.cyl((x, IY1 - 0.85, z0), (x, IY1 - 0.85, z0 + 0.72), 0.03, "px_steel", 6, caps=False)
    shop.cyl((x, IY1 - 0.85, z0 + 0.72), (x, IY1 - 0.85, z0 + 0.78), 0.2, "px_red", 10)
    shop.cyl((x, IY1 - 0.85, z0), (x, IY1 - 0.85, z0 + 0.02), 0.18, "px_steel", 10)
# remates rojos de las góndolas
for (x, y0g, y1g) in ((1919.88, -1782.95, -1780.85), (1925.02, -1782.95, -1780.85), (1919.88, -1779.15, -1777.05), (1924.02, -1779.15, -1777.05)):
    shop.box(x, y0g, z0, x + 0.1, y1g, z0 + 1.45, "px_white", 1.0, skip=("bottom", "top"))
    shop.box(x, y0g, z0 + 1.45, x + 0.1, y1g, z0 + 1.75, "px_red", 1.0, skip=("bottom",))
    col_box("shop", x, y0g, z0, x + 0.1, y1g, z0 + 1.75, "plastic")

# ---------------------------------------------------------------- túnel de lavado (oeste): los cepillos del juego se quedan
shop.box(BAY_X0, BAY_Y0, LOT, BAY_X0 + 0.3, BAY_Y1, BAY_C0, "px_render", 2.0, skip=("top", "bottom"))
col_box("shop", BAY_X0, BAY_Y0, LOT, BAY_X0 + 0.3, BAY_Y1, BAY_C0)
shop.box(BAY_X0, BAY_Y0 - 0.2, BAY_C0, BX0, BAY_Y1 + 0.2, BAY_C1, "px_red", 2.0, mats={"top": "n_roof06L256", "bottom": "px_white"}, skip=("+x",))
col_box("shop", BAY_X0, BAY_Y0 - 0.2, BAY_C0, BX0, BAY_Y1 + 0.2, BAY_C1)
shop.quad((1909.8, -1780.5, LOT + 0.07), (1912.6, -1780.5, LOT + 0.07), (1912.6, -1772.2, LOT + 0.07), (1909.8, -1772.2, LOT + 0.07), "n_metpat64", 2.0)
for (y, nrm) in ((BAY_Y1 + 0.2, (0, 1)), (BAY_Y0 - 0.2, (0, -1))):
    shop.sign(((BAY_X0 + BX0) / 2, y - 0.1 * nrm[1], BAY_C1 + 0.42), nrm, 3.2, 0.8, "px_lavado", depth=0.12, both=False, side_mat="px_red", back_mat="px_red")
    col_box("shop", BAY_X0 + 1.0, y - 0.2 if nrm[1] > 0 else y, BAY_C1, BX0 - 1.0, y if nrm[1] > 0 else y + 0.2, BAY_C1 + 0.85)
for y in (-1779.0, -1775.6):
    shop.hquad(1910.6, y, 1911.9, y + 0.2, BAY_C0 - 0.05, "px_light", down=True, cell=0)
# puerta trasera (oeste, fuera del lavado)
shop.vstrip((BX0 - 0.03, -1784.6), (BX0 - 0.03, -1783.55), z0, z0 + 2.2, (-1, 0), [(0, 1.05, "px_door", (0, 1, 0, 1))])

# ---------------------------------------------------------------- estacionamientos al sur (4 cajones, el del este azul)
ZP = LOT + 0.07
for x in (1915.6, 1918.4, 1921.2, 1924.0, 1927.6):
    shop.quad((x - 0.06, -1792.6, ZP), (x + 0.06, -1792.6, ZP), (x + 0.06, -1787.5, ZP), (x - 0.06, -1787.5, ZP), "px_white", 3.0)
shop.hquad(1924.1, -1792.5, 1927.5, -1789.1, ZP + 0.005, "px_access", cell=0, uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
shop.hquad(1924.1, -1789.1, 1927.5, -1787.6, ZP + 0.005, "px_blue", cell=0)
for xc in (1917.0, 1919.8, 1922.6, 1925.8):
    shop.box(xc - 0.8, -1788.3, LOT, xc + 0.8, -1788.1, LOT + 0.12, "px_yb", 0, skip=("bottom",))
    col_box("shop", xc - 0.8, -1788.3, LOT, xc + 0.8, -1788.1, LOT + 0.12)
shop.cyl((1925.8, -1787.0, PAD), (1925.8, -1787.0, PAD + 2.4), 0.035, "n_gen_chrome", 6)
shop.sign((1925.8, -1787.04, PAD + 2.05), (0, -1), 0.45, 0.45, "px_access", depth=0.02, both=False, side_mat="px_steel", back_mat="px_steel")
col_box("shop", 1925.75, -1787.05, PAD, 1925.85, -1786.95, PAD + 2.3, "girder")

# ================================================================ TECHO DE SURTIDORES Y TÓTEM
can = Piece("pronto_canopy")
# isla de surtidores (los surtidores del juego quedan encima)
can.box(ISL[0], ISL[2], LOT, ISL[1], ISL[3], LOT + 0.17, "n_concretenewgery256", 1.0, mats={"-y": "px_yb", "+y": "px_yb"}, skip=("bottom",))
col_box("canopy", ISL[0], ISL[2], LOT, ISL[1], ISL[3], LOT + 0.17, "pavement")
# losa con fascia Copec (franja roja abajo, azul, blanco) y el logo en los cuatro lados
can.box(CX0, CY0, CAN0 - 0.1, CX1, CY1, CAN1, "n_concretenewgery256", 3.0, mats={"bottom": "px_white"}, skip=("-x", "+x", "-y", "+y"))
col_box("canopy", CX0, CY0, CAN0 - 0.1, CX1, CY1, CAN1)
for (pa, pb, nrm) in (((CX0, CY1), (CX1, CY1), (0, 1)), ((CX0, CY0), (CX1, CY0), (0, -1)),
                      ((CX1, CY0), (CX1, CY1), (1, 0)), ((CX0, CY0), (CX0, CY1), (-1, 0))):
    L = (Vector(pb) - Vector(pa)).length
    s = (L - LW) / 2
    can.vstrip(pa, pb, CAN0 - 0.1, CAN1, nrm, [(0, s, "px_fascia", None), (s, s + LW, "px_copec", (0, 1, 0, 1)), (s + LW, L, "px_fascia", None)])
# luminarias bajo la losa
for x in (1936.5, 1946.8):
    for y in np.arange(CY0 + 1.8, CY1 - 1.0, 3.6):
        can.hquad(x - 0.5, y - 0.5, x + 0.5, y + 0.5, CAN0 - 0.15, "px_light", down=True, cell=0)
for y in np.arange(CY0 + 2.6, CY1 - 1.5, 3.6):
    can.hquad(PUMP_X - 0.5, y - 0.5, PUMP_X + 0.5, y + 0.5, CAN0 - 0.15, "px_light", down=True, cell=0)
# pilares blancos con zócalo rojo, sobre los extremos de la isla
for y in (ISL[2] + 0.55, ISL[3] - 0.55):
    can.box(PUMP_X - 0.3, y - 0.3, LOT + 0.17, PUMP_X + 0.3, y + 0.3, LOT + 0.7, "px_red", 1.0, skip=("bottom",), mats={"top": "px_red"})
    can.box(PUMP_X - 0.27, y - 0.27, LOT + 0.7, PUMP_X + 0.27, y + 0.27, CAN0 - 0.1, "px_white", 2.0, skip=("bottom", "top"))
    col_box("canopy", PUMP_X - 0.3, y - 0.3, LOT, PUMP_X + 0.3, y + 0.3, CAN0, "girder")
# Tótem de precios (mira al norte y al sur): logo Copec, logo Pronto y precios
TX, TY = TOTEM.x, TOTEM.y
TB = PAD
can.box(TX - 0.9, TY - 0.25, TB, TX + 0.9, TY + 0.25, TB + 7.0, "px_navy", 2.0, skip=("bottom",))
col_box("canopy", TX - 0.9, TY - 0.25, TB, TX + 0.9, TY + 0.25, TB + 7.0, "default")
for nrm in ((0, 1), (0, -1)):
    yf = TY + 0.25 * nrm[1] + 0.03 * nrm[1]
    can.vstrip((TX - 0.8, yf), (TX + 0.8, yf), TB + 5.85, TB + 6.85, nrm, [(0, 1.6, "px_copec_t", (0, 1, 0, 1))], cell=0)
    can.vstrip((TX - 0.8, yf), (TX + 0.8, yf), TB + 4.1, TB + 5.7, nrm, [(0, 1.6, "px_logo2", (0, 1, 0, 1))], cell=0)
    can.vstrip((TX - 0.75, yf), (TX + 0.75, yf), TB + 1.0, TB + 3.95, nrm, [(0, 1.5, "px_totem", (0, 1, 0, 1))], cell=0)
can.box(TX - 1.0, TY - 0.35, TB, TX + 1.0, TY + 0.35, TB + 0.35, "n_concretenewgery256", 1.0, skip=("bottom",))

# Volumen de las piezas sin colisión propia (shop_x, canopy_x, lod): GTA recorta el dibujo con los límites del COL;
# sin este heredan el COL de 1 m del modelo base y desaparecen de cerca. En juego esas piezas no chocan.
col_box("bounds", BAY_X0 - 0.5, -1793.0, PAD - 0.3, CX1 + 2.5, CY1 + 1.5, TB + 7.2)

# ================================================================ LOD (cajas simples, visibles de lejos)
# Dos LOD, cada uno ligado a su pieza (tienda / techo): GTA dibuja el LOD de una pieza cuando esa pieza queda fuera de
# cuadro, así que un LOD único colgado de la tienda aparecía sobre el techo de surtidores al mirarlo de cerca.
# Las cajas van 4 cm hacia dentro de las caras reales: nunca en el mismo plano que el modelo detallado.
E = 0.04
lod = Piece("pronto_lod")
lodc = Piece("pronto_lodc")
lod.box(BX0 + E, BY0 + E, PAD, BX1 - E, BY1 - E, ROOF - E, "px_lod_wall", 0, mats={"+x": "px_lod_glass", "top": "px_lod_roof"}, skip=("bottom",))
lod.box(BX1, BY0 - 0.3 + E, BAND0 + E, BX1 + 0.3 - E, BY1 + 0.3 - E, BAND1, "px_lod_navy", 0, skip=("-x", "bottom", "top"))
lod.box(BX1, BY0 - 0.3 + E, CORN0 + E, BX1 + CORN_OUT - E, BY1 + 0.3 - E, CORN1 - E, "px_lod_red", 0, mats={"top": "px_lod_roof", "bottom": "px_lod_white"}, skip=("-x",))
lod.box(BAY_X0 + E, BAY_Y0 + E, LOT, BX0, BAY_Y1 - E, BAY_C1 - E, "px_lod_wall", 0, mats={"top": "px_lod_roof", "-y": "px_lod_red", "+y": "px_lod_red"}, skip=("bottom", "+x"))
lodc.box(CX0 + E, CY0 + E, CAN0 - 0.1 + E, CX1 - E, CY1 - E, CAN1 - E, "px_lod_white", 0, mats={"top": "px_lod_roof"})
for y in (ISL[2] + 0.55, ISL[3] - 0.55):                     # los dos pilares (no una pared a lo largo de la isla)
    lodc.box(PUMP_X - 0.25, y - 0.25, LOT, PUMP_X + 0.25, y + 0.25, CAN0 - 0.1 + E, "px_lod_white", 0, skip=("bottom", "top"))
lodc.box(TX - 0.9 + E, TY - 0.25 + E, TB, TX + 0.9 - E, TY + 0.25 - E, TB + 7.0 - E, "px_lod_navy", 0, skip=("bottom",))

# ---------------------------------------------------------------- vidrio: caras sueltas (no van al DFF)
glass_piece = Piece("pronto_glass")
for (pa, pb, za, zb, nrm) in GLASS_FACES:
    glass_piece.vquad(pa, pb, za, zb, nrm, "px_glass_dummy", 3.0)

# ---------------------------------------------------------------- objetos finales
O = {}
for piece in (shop, can, lod, lodc, glass_piece):
    for kind, ob in piece.objects().items():
        O[f"{piece.name}_{kind}"] = ob
NAMES = {
    "pronto_shop_nat": "pronto_shop", "pronto_shop_x": "pronto_shop_x",
    "pronto_canopy_nat": "pronto_canopy", "pronto_canopy_x": "pronto_canopy_x",
    "pronto_lod_lod": "pronto_lod", "pronto_lodc_lod": "pronto_lod_canopy", "pronto_glass_glass": "pronto_glass",
}
for k, ob in O.items():
    ob.name = NAMES[k]
    ob.data.name = NAMES[k]
    for p in ob.data.polygons:
        p.use_smooth = False
print("[pronto] objetos:", {ob.name: len(ob.data.polygons) for ob in O.values()})

# ---------------------------------------------------------------- muebles nativos del interior (góndolas, refrigeradores...)
# (modelo, x, y, z, rotZ). El frente de estos modelos mira a -y local: rot 180 = mira al norte, 90 = al este.
PROPS = [
    (2012, 1917.0, -1785.05, z0, 180), (2012, 1920.0, -1785.05, z0, 180), (2012, 1923.0, -1785.05, z0, 180),   # refrigeradores abiertos (muro sur)
    (2452, 1925.69, -1785.21, z0, 180), (2443, 1926.71, -1785.22, z0, 180),                                      # refrigeradores de puertas
]
for i, m in enumerate((2541, 2543, 2539, 2546, 2548)):                     # góndola 1 (doble)
    PROPS.append((m, 1920.5 + i, -1782.4, z0, 0))
for i, m in enumerate((2548, 2546, 2541, 2543, 2539)):
    PROPS.append((m, 1920.5 + i, -1781.38, z0, 180))
for i, m in enumerate((2543, 2541, 2546, 2539)):                           # góndola 2 (doble)
    PROPS.append((m, 1920.5 + i, -1778.6, z0, 0))
for i, m in enumerate((2539, 2548, 2543, 2541)):
    PROPS.append((m, 1920.5 + i, -1777.58, z0, 180))
PROPS += [
    (2369, 1917.6, -1778.0, z0 + 1.05, 90), (2369, 1917.6, -1775.2, z0 + 1.05, 90),                            # cajas
    (2362, 1917.45, -1779.9, z0 + 1.05, 90),                                                                      # dulces junto a la caja
    (2500, 1914.75, -1779.4, z0 + 0.9, 90), (2500, 1914.75, -1777.6, z0 + 0.9, 90),                              # café (barra de atrás)
    (2500, 1923.3, TRAV1 - 0.27, z0 + 0.92, 0), (2500, 1924.2, TRAV1 - 0.27, z0 + 0.92, 0),                      # café para clientes
    (2429, 1925.15, TRAV1 + 0.05, z0 + 0.92, 0),                                                                  # vasos
    (2361, 1926.0, TRAV1 - 0.67, z0, 0),                                                                          # congelador de helados
    (1885, 1926.9, -1778.4, z0, 0),                                                                               # canastos
]

def write_props():
    path = os.path.join(RES, "shared", "s_props.lua")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generado por tools/build_pronto.py: muebles nativos del interior de la tienda { modelo, x, y, z, rotZ }.\n")
        f.write("-- Se regeneran con el modelo (el diseño del interior está en el script).\n")
        f.write("PRONTO_PROPS = {\n")
        for m, x, y, z, r in PROPS:
            f.write("    { %d, %.2f, %.2f, %.2f, %d },\n" % (m, x, y, z, r))
        f.write("}\n")
    print(f"[pronto] muebles: {len(PROPS)} -> {path}")

write_props()

# ---------------------------------------------------------------- molde: suelo original, surtidores, cepillos y muebles
ref_objs, preview_only, imported_all = [], [], []

def import_ref(path, pos, rz=0.0, bake=True):
    if not os.path.exists(path):
        return []
    before = set(bpy.data.objects)
    bpy.ops.import_scene.dff(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    imported_all.extend(new)
    for o in new:
        if o.parent is None:
            o.location = pos
            o.rotation_euler = (0, 0, math.radians(rz))
        if o.type == "MESH" and not o.name.startswith("2dfx"):
            (ref_objs if bake else preview_only).append(o)
        else:
            o.hide_render = True
    return new

if REF:
    import_ref(os.path.join(REF, "laeroad24.dff"), (1932.594, -1782.102, 12.5))
    import_ref(os.path.join(REF, "laeroad38.dff"), (1927.703, -1754.313, 12.461))
    import_ref(os.path.join(REF, "carwashalphas_lae.dff"), (1921.484, -1778.914, 18.578), bake=False)
    for y in (-1778.453, -1774.313, -1771.344, -1767.289):
        import_ref(os.path.join(REF, "washgaspump.dff"), (1941.656, y, 14.141), 90, bake=False)
    if PROPS_DIR and os.path.isdir(PROPS_DIR):
        import_ref(os.path.join(PROPS_DIR, "cj_ext_sprunk.dff"), (1928.734, -1772.445, 12.945), -90, bake=False)
        names = {2012: "shop_shelf13", 2452: "cj_ff_fridge2", 2443: "cj_ff_frige", 2541: "cj_ss_3_m", 2543: "cj_ss_4_m",
                 2539: "cj_ss_2_m", 2546: "cj_ss_7_m", 2548: "cj_ss_6_m", 2369: "cj_till", 2362: "cj_sweetie_tray_1",
                 2500: "cj_ff_coffee", 2429: "cj_ff_cup_disp", 2361: "cj_ice_fridge_1", 1885: "shop_baskets"}
        for m, x, y, z, r in PROPS:
            import_ref(os.path.join(PROPS_DIR, names[m] + ".dff"), (x, y, z), r, bake=False)
    for t in ("barrio1_lae", "lae2roads", "laeroads2s", "wshxrefpump"):
        if os.path.exists(os.path.join(REF, t + ".txd")):
            bpy.ops.import_scene.dff(filepath=os.path.join(REF, t + ".txd"))
    if PROPS_DIR and os.path.isdir(PROPS_DIR):
        for t in os.listdir(PROPS_DIR):
            if t.endswith(".txd"):
                bpy.ops.import_scene.dff(filepath=os.path.join(PROPS_DIR, t))
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
    bpy.ops.mesh.primitive_plane_add(size=300, location=(1925, -1776, LOT - 0.01))
    gp = bpy.context.active_object
    gm = bpy.data.materials.new("bake_ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.30, 0.30, 0.30, 1)
    gp.data.materials.append(gm)
    helpers.append(gp)

def inside(c, box, zmax):
    return box[0] <= c.x <= box[1] and box[2] <= c.y <= box[3] and c.z <= zmax

INT_BOX = (IX0 - 0.02, BX1 - 0.04, IY0 - 0.02, IY1 + 0.02)
UNDER = [((BX1 - 0.01, BX1 + CORN_OUT + 0.1, BY0 - 0.4, BY1 + 0.4), CORN0 - 0.02),          # vereda bajo la cornisa
         ((BAY_X0 + 0.29, BX0 + 0.01, BAY_Y0 - 0.2, BAY_Y1 + 0.2), BAY_C0 - 0.02),         # túnel de lavado
         ((CX0, CX1, CY0, CY1), CAN0 - 0.12)]                                               # techo de surtidores
REF_LUM = {}

def bake_prelight(obj):
    mesh = obj.data
    for a in list(mesh.color_attributes):
        mesh.color_attributes.remove(a)
    day = mesh.color_attributes.new("day", "BYTE_COLOR", "CORNER")
    night = mesh.color_attributes.new("night", "BYTE_COLOR", "CORNER")
    n = len(mesh.loops)
    if obj.name in ("pronto_glass", "pronto_lod", "pronto_lod_canopy"):
        lum = np.full(n, 0.8)
    else:
        mesh.color_attributes.active_color = day
        for g in (O["pronto_glass_glass"], O["pronto_lod_lod"], O["pronto_lodc_lod"]):
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
    # Día: ~77..199 en gris cálido, como el suelo y los edificios vecinos
    v = 0.30 + 0.48 * lum
    d = np.stack([v, v * 0.97, v * 0.92], axis=1)
    lit_in = np.zeros(n, dtype=bool)
    under = np.zeros(n, dtype=bool)
    glow = np.zeros(n, dtype=bool)
    mw = obj.matrix_world
    for poly in mesh.polygons:
        c = mw @ poly.center
        idx = list(poly.loop_indices)
        if inside(c, INT_BOX, CEIL + 0.01):
            lit_in[idx] = True
        elif any(inside(c, b, zm) for b, zm in UNDER):
            under[idx] = True
        if mesh.materials[poly.material_index].name in GLOW:
            glow[idx] = True
    # interior: luz de tienda pareja y clara, conservando la oclusión (rincones algo más oscuros)
    if lit_in.any() and obj.name not in ("pronto_glass", "pronto_lod", "pronto_lod_canopy"):
        li = lum[lit_in]
        li = np.clip(li / (np.percentile(li, 95) or 1.0), 0, 1)
        vi = 0.64 + 0.16 * li
        d[lit_in] = np.stack([vi, vi * 0.99, vi * 0.97], axis=1)
    if under.any():
        d[under] = np.maximum(d[under], np.array((0.42, 0.41, 0.39)))
    d[glow] = np.maximum(d[glow], 0.74)
    # Noche: gris azulado; interior, cornisa, lavado y techo de surtidores con luz cálida/blanca de lámparas
    nt = d * np.array((0.21, 0.23, 0.30))
    nt[lit_in] = d[lit_in] * np.array((0.62, 0.57, 0.48))      # luz de tienda cálida y contenida (no blanca)
    nt[under] = np.maximum(nt[under], d[under] * np.array((0.95, 0.93, 0.86)))
    nt[glow] = np.array((1.0, 0.96, 0.86))
    if obj.name.startswith("pronto_lod"):
        nt[:] = d * np.array((0.30, 0.30, 0.34))
        for poly in mesh.polygons:
            if mesh.materials[poly.material_index].name in ("px_lod_glass", "px_lod_white", "px_lod_red"):
                nt[list(poly.loop_indices)] = np.array((0.85, 0.80, 0.66))
    def put(attr, rgb):
        rgba = np.concatenate([np.clip(rgb, 0, 1), np.ones((n, 1))], axis=1).astype(np.float32)
        attr.data.foreach_set("color_srgb", rgba.ravel())
    put(day, d)
    put(night, nt)
    obj.dff.day_cols = True
    obj.dff.night_cols = True
    obj.dff.uv_map2 = False
    print(f"[pronto] prelight {obj.name}: {n} esquinas")

for o in preview_only:
    o.hide_render = True          # cepillos con alfa y muebles: fuera del horneado
for key in ("pronto_shop_nat", "pronto_shop_x", "pronto_canopy_nat", "pronto_canopy_x", "pronto_lod_lod", "pronto_lodc_lod"):
    bake_prelight(O[key])
for h in helpers:
    bpy.data.objects.remove(h)
for g in list(O.values()) + preview_only:
    g.hide_render = False

# ---------------------------------------------------------------- vistas previas (con el molde), antes de mover al origen
def preview_materials(attr):
    for m in list(bpy.data.materials):
        if not m.use_nodes:
            continue
        nt = m.node_tree
        tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image), None)
        if tex is None:
            continue
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

def glass_preview(night):
    """Vidrio de la vista previa: tinte translúcido como el de c_glass.lua."""
    m = O["pronto_glass_glass"].data.materials[0]
    nt = m.node_tree
    for n2 in [n for n in nt.nodes if n.get("preview")]:
        nt.nodes.remove(n2)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.10, 0.11, 0.13, 1) if night else (0.08, 0.12, 0.14, 1)
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = 0.27 if night else 0.40
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    for n2 in (em, tr, mix):
        n2["preview"] = True

def render_views():
    if not REF:
        return
    cam = bpy.data.objects.new("prev_cam", bpy.data.cameras.new("prev_cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.cycles.samples = 8
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    scene.view_settings.view_transform = "Standard"
    O["pronto_lod_lod"].hide_render = True
    O["pronto_lodc_lod"].hide_render = True
    shots = [("frente.png", (1937.5, -1781.5, 14.4), (1925.0, -1774.0, 14.6), 20),
             ("calle.png", (1968.0, -1748.0, 21.0), (1930.0, -1776.0, 14.0), 24),
             ("surtidores.png", (1957.0, -1792.0, 15.5), (1938.0, -1772.0, 15.0), 22),
             ("interior.png", (1926.9, -1784.6, 14.35), (1917.0, -1774.0, 13.6), 16),
             ("caja.png", (1925.5, -1776.4, 14.3), (1915.0, -1777.0, 14.0), 18),
             ("sur.png", (1921.0, -1803.0, 16.0), (1920.0, -1780.0, 14.0), 22),
             ("lavado.png", (1904.0, -1764.0, 15.0), (1913.0, -1778.0, 14.0), 22),
             ("cenital.png", (1930.0, -1775.0, 90.0), (1930.0, -1775.0, 0.0), 30)]
    for mode, vattr, rattr, bg in (("dia", "day", "Col", (0.60, 0.72, 0.90)), ("noche", "night", "Col.001", (0.03, 0.04, 0.09))):
        world.node_tree.nodes["Background"].inputs["Color"].default_value = (*bg, 1)
        world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
        preview_materials(vattr)
        glass_preview(mode == "noche")
        for o in ref_objs + preview_only:
            if o.type != "MESH":
                continue
            for m in o.data.materials:
                if m and m.use_nodes:
                    for n2 in m.node_tree.nodes:
                        if n2.type == "VERTEX_COLOR" and n2.get("preview"):
                            names = [a.name for a in o.data.color_attributes]
                            n2.layer_name = rattr if rattr in names else (names[0] if names else "")
        for name, loc, target, lens in shots:
            if mode == "noche" and name not in ("calle.png", "frente.png", "surtidores.png"):
                continue
            cam.location = loc
            cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
            if name == "cenital.png":
                cam.rotation_euler = (0, 0, 0)
            cam.data.lens = lens
            scene.render.filepath = os.path.join(REF, mode + "_" + name)
            bpy.ops.render.render(write_still=True)
        restore_materials()
    bpy.data.objects.remove(cam)

render_views()

# ---------------------------------------------------------------- vidrio como primitivas 3D (no como modelo)
def write_glass_data():
    gl = O["pronto_glass_glass"]
    mw = gl.matrix_world
    nums = []
    for p in gl.data.polygons:
        vs = [mw @ gl.data.vertices[i].co for i in p.vertices]
        for k in range(1, len(vs) - 1):
            for v in (vs[0], vs[k], vs[k + 1]):
                nums += ["%.2f" % v.x, "%.2f" % v.y, "%.2f" % v.z]
    path = os.path.join(RES, "client", "c_glass_data.lua")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generado por tools/build_pronto.py: triángulos del vidrio de la tienda (x, y, z del mundo, de a 3 vértices).\n")
        f.write("-- No editar a mano: se regenera con el modelo.\n")
        f.write("PRONTO_GLASS = {\n")
        for i in range(0, len(nums), 18):
            f.write("    " + ", ".join(nums[i:i + 18]) + ",\n")
        f.write("}\n")
    print(f"[pronto] vidrio: {len(nums) // 9} triángulos -> {path}")

write_glass_data()

# ---------------------------------------------------------------- mover al origen y exportar
T = Matrix.Translation(-ORIGIN)
for ob in O.values():
    ob.data.transform(T)
for o in imported_all:
    try:
        bpy.data.objects.remove(o)
    except ReferenceError:
        pass

models = os.path.join(RES, "models")
os.makedirs(models, exist_ok=True)

def drop_empty_image_nodes():
    for m in bpy.data.materials:
        if m.node_tree:
            for node in [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image is None]:
                m.node_tree.nodes.remove(node)

for key, file in NAMES.items():
    if key == "pronto_glass_glass":
        continue
    ob = O[key]
    for o in scene.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    path = os.path.join(models, file + ".dff")
    bpy.ops.export_dff.scene(filepath=path, directory=models, only_selected=True, export_coll=False, export_version="0x36003")
    drop_empty_image_nodes()
    tri = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print(f"[pronto] {file}.dff: {os.path.getsize(path)} bytes, triángulos≈{tri}")

# ---------------------------------------------------------------- TXD propios DXT1 con mipmaps (como rp_relojflores)
from DragonFF.ops import col_exporter
from DragonFF.gtaLib import txd as gtxd
from DragonFF.gtaLib.dff import NativePlatformType

def mip_chain(arr):
    levels = [arr]
    while levels[-1].shape[0] > 1 or levels[-1].shape[1] > 1:
        a = levels[-1]
        h, w = a.shape[:2]
        if h > 1 and w > 1:
            nxt = (a[0::2, 0::2] + a[1::2, 0::2] + a[0::2, 1::2] + a[1::2, 1::2]) / 4
        elif h > 1:
            nxt = (a[0::2] + a[1::2]) / 2
        else:
            nxt = (a[:, 0::2] + a[:, 1::2]) / 2
        levels.append(nxt)
    return levels

def to565(c):
    q = np.round(c * np.array((31, 63, 31))).astype(np.int64)
    return (q[..., 0] << 11) | (q[..., 1] << 5) | q[..., 2], q * np.array((255 / 31, 255 / 63, 255 / 31)) / 255

def dxt1_encode(img):
    """img (h, w, 3) sRGB 0..1, fila 0 ARRIBA."""
    h, w = img.shape[:2]
    ph, pw = max(4, (h + 3) // 4 * 4), max(4, (w + 3) // 4 * 4)
    if (ph, pw) != (h, w):
        img = np.pad(img, ((0, ph - h), (0, pw - w), (0, 0)), mode="edge")
    rgb = img.reshape(ph // 4, 4, pw // 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 3)
    mean = rgb.mean(1, keepdims=True)
    cen = rgb - mean
    cov = np.einsum("bki,bkj->bij", cen, cen)
    axis = np.ones((len(rgb), 3)) / math.sqrt(3)
    for _ in range(6):
        axis = np.einsum("bij,bj->bi", cov, axis)
        axis /= np.linalg.norm(axis, axis=1, keepdims=True) + 1e-9
    proj = np.einsum("bki,bi->bk", cen, axis)
    c0, p0 = to565(np.clip(mean[:, 0] + axis * proj.max(1, keepdims=True), 0, 1))
    c1, p1 = to565(np.clip(mean[:, 0] + axis * proj.min(1, keepdims=True), 0, 1))
    swap = c0 < c1
    c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
    p0, p1 = np.where(swap[:, None], p1, p0), np.where(swap[:, None], p0, p1)
    pal = np.stack([p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3], axis=1)
    idx = ((rgb[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(-1).argmin(-1)
    idx = np.where((c0 == c1)[:, None], 0, idx)
    bits = (idx.astype(np.uint64) << (2 * np.arange(16, dtype=np.uint64))).sum(1).astype(np.uint32)
    out = np.zeros(len(rgb), dtype=[("c0", "<u2"), ("c1", "<u2"), ("i", "<u4")])
    out["c0"], out["c1"], out["i"] = c0, c1, bits
    return out.tobytes()

def native_dxt1(name, image):
    w, h = image.size
    arr = np.array(image.pixels[:], dtype=np.float64).reshape(h, w, 4)[..., :3]
    levels = mip_chain(arr)
    tn = gtxd.TextureNative()
    tn.platform_id = NativePlatformType.D3D9
    tn.filter_mode = 0x06
    tn.uv_addressing = 0b00010001
    tn.name, tn.mask = name[:31], ""
    tn.raster_format_flags = (gtxd.RasterFormat.RASTER_565 << 8) | 0x8000
    tn.d3d_format = gtxd.D3DFormat.D3D_DXT1
    tn.width, tn.height, tn.depth = w, h, 16
    tn.num_levels = len(levels)
    tn.raster_type = 4
    tn.platform_properties = type("PP", (), {"alpha": False, "cube_texture": False, "auto_mipmaps": False, "compressed": True})()
    tn.palette = b""
    tn.pixels = [dxt1_encode(lv[::-1]) for lv in levels]          # TXD: fila 0 arriba
    return tn

def write_txd(path, objects):
    tx = gtxd.txd()
    tx.device_id = gtxd.DeviceType.DEVICE_D3D9
    used = {}
    for ob in objects:
        for m in ob.data.materials:
            for n2 in m.node_tree.nodes:
                if n2.type == "TEX_IMAGE" and n2.image and KIND.get(m.name) in ("x", "lod"):
                    used[n2.image.name] = n2.image
    tx.native_textures = [native_dxt1(name, img) for name, img in sorted(used.items())]
    tx.write_file(path, 0x36003)
    print(f"[pronto] {os.path.basename(path)}: {len(used)} texturas, {os.path.getsize(path)} bytes")

write_txd(os.path.join(models, "pronto.txd"), [O["pronto_shop_x"], O["pronto_canopy_x"]])
write_txd(os.path.join(models, "pronto_lod.txd"), [O["pronto_lod_lod"], O["pronto_lodc_lod"]])

for piece, coll in COLS.items():
    path = os.path.join(models, f"pronto_{piece}.col")
    col_exporter.export_col({
        "file_name": path, "version": 3, "collection": coll, "apply_transformations": True,
        "only_selected": False, "clean_mesh": True, "export_face_groups": False,
    })
    if piece == "bounds":
        # Solo límites (recorte de dibujo), sin cajas: COL3 numBoxes (uint16) en 74 y flags (uint32) en 80
        with open(path, "r+b") as f:
            f.seek(74); f.write(b"\x00\x00")
            f.seek(80); f.write(b"\x00\x00\x00\x00")
    print(f"[pronto] pronto_{piece}.col: {len(coll.objects)} cajas, {os.path.getsize(path)} bytes")

# ---------------------------------------------------------------- .blend sin material de Rockstar
for tex, img in list(ref_images.items()):
    for m in bpy.data.materials:
        if m.node_tree:
            for n2 in m.node_tree.nodes:
                if n2.type == "TEX_IMAGE" and n2.image == img:
                    n2.image = bpy.data.images.get(tex + "_ph") or bpy.data.images.new(tex + "_ph", 8, 8)
    bpy.data.images.remove(img)
for img in [i for i in bpy.data.images if ".txd/" in i.name]:
    bpy.data.images.remove(img)
for m in [m for m in bpy.data.materials if m.users == 0]:
    bpy.data.materials.remove(m)
for img in [i for i in bpy.data.images if i.users == 0]:
    bpy.data.images.remove(img)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(RES, "tools", "pronto.blend"), compress=True)
print("[pronto] listo")
