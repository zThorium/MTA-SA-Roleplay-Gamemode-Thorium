"""
analizar_molde.py - mide un sitio del mapa original de GTA SA antes de modelar encima (skill mapeado-3d).

Importa en Blender los DFF originales en su posición del mundo (sacados con rp_turbus/tools/extraer-img.ps1 a la carpeta
<ref>, que es del scratchpad: material de Rockstar, nunca al repo) y deja en <ref>:
  - top_all.png / top_<modelo>.png   vista cenital con texturas (qué trae cada modelo, huellas, huecos)
  - persp.png                        vista en perspectiva
  - alturas.txt                      mapa ASCII de alturas a 1 m del SUELO, decodificado en tramos por fila:
                                     '_' hueco, '.' más bajo (asfalto), ',' suelo, 'h' seto/jardinera, 'W' muro
  - prelight.txt                     estadísticas de los colores de vértice (día/noche) del suelo y del edificio
  - txd_<nombre>.png                 hoja de contacto de cada TXD (los nombres engañan: mirar antes de usar)
  - molde.blend                      la escena, para reutilizar como molde

Uso:
  blender.exe --background --factory-startup --python analizar_molde.py -- <carpeta con DragonFF/> <ref> <config.json>
config.json:
  {
    "modelos": [["btoland2_las", 1745.203, -1882.852, 26.141], ["unmainstat_las", 1745.203, -1882.852, 26.141]],
    "suelo": "btoland2_las",                       # el modelo cuyo relieve se mide
    "txd": ["union_las", "railway_las"],
    "caja": [1680, 1816, -1948, -1828],            # x0, x1, y0, y1 del mapa de alturas y las vistas
    "niveles": [12.5, 13.0, 15.0]                  # cortes de altura para . , h W
  }
"""
import bpy, os, sys, json, math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
sys.path.insert(0, argv[0])
REF = argv[1]
CFG = json.load(open(argv[2], encoding="utf-8"))

bpy.ops.wm.read_factory_settings(use_empty=True)
import DragonFF
DragonFF.register()
scene = bpy.context.scene

# ---------------------------------------------------------------- importar en posición del mundo
for name, x, y, z in CFG["modelos"]:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.dff(filepath=os.path.join(REF, name + ".dff"))
    for o in [o for o in bpy.data.objects if o not in before]:
        if o.parent is None:
            o.location = (x, y, z)
        o["src"] = name
        if o.type != "MESH" or o.name.startswith("2dfx"):
            o.hide_render = True
bpy.context.view_layer.update()
# los TXD se importan DESPUÉS de los DFF (así se aplican a los materiales sin textura)
for t in CFG.get("txd", []):
    p = os.path.join(REF, t + ".txd")
    if os.path.exists(p):
        bpy.ops.import_scene.dff(filepath=p)

meshes = [o for o in bpy.data.objects if o.type == "MESH" and not o.hide_render]
for o in meshes:
    ws = np.array([tuple(o.matrix_world @ v.co) for v in o.data.vertices])
    texs = sorted({n.image.name for m in o.data.materials if m and m.use_nodes for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image})
    print("[molde]", o["src"], o.name, "min", ws.min(0).round(2), "max", ws.max(0).round(2), "tex", texs)

# ---------------------------------------------------------------- vistas
x0, x1, y0, y1 = CFG["caja"]
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.light = "STUDIO"
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.clip_end = 2000
cam.data.type = "ORTHO"
cam.data.ortho_scale = max(x1 - x0, y1 - y0)
cam.location = (cx, cy, 300)
cam.rotation_euler = (0, 0, 0)
scene.render.resolution_x = scene.render.resolution_y = 1400
for only in [None] + [m[0] for m in CFG["modelos"]]:
    for o in meshes:
        o.hide_render = only is not None and o["src"] != only
    scene.render.filepath = os.path.join(REF, "top_%s.png" % (only or "all"))
    bpy.ops.render.render(write_still=True)
for o in meshes:
    o.hide_render = False
cam.data.type = "PERSP"
cam.data.lens = 22
cam.location = (x1 + 20, y0 - 30, 45)
cam.rotation_euler = (Vector((cx, cy, 13)) - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
scene.render.filepath = os.path.join(REF, "persp.png")
bpy.ops.render.render(write_still=True)
print("[molde] escala cenital: %.2f px por metro, arriba = norte (+Y)" % (1400 / cam.data.ortho_scale if cam.data.type == "ORTHO" else 1400 / max(x1 - x0, y1 - y0)))

# ---------------------------------------------------------------- mapa de alturas ASCII del suelo
suelo = next(o for o in meshes if o["src"] == CFG["suelo"])
inv, mw = suelo.matrix_world.inverted(), suelo.matrix_world
down = (inv.to_3x3() @ Vector((0, 0, -1))).normalized()
lv = CFG.get("niveles", [12.5, 13.0, 15.0])
rows = []
for y in range(int(y1), int(y0), -2):
    row = ""
    for x in range(int(x0), int(x1)):
        ok, loc, _, _ = suelo.ray_cast(inv @ Vector((x + 0.5, y - 0.5, 200)), down)
        if not ok:
            row += "_"
            continue
        z = (mw @ loc).z
        row += "." if z < lv[0] else ("," if z < lv[1] else ("h" if z < lv[2] else "W"))
    # tramos que no son suelo normal, en coordenadas del mundo
    spans, prev, start = [], None, 0
    for i, c in enumerate(row + "#"):
        if c != prev:
            if prev not in (None, ","):
                spans.append("[%s x%d-%d]" % (prev, int(x0) + start, int(x0) + i - 1))
            prev, start = c, i
    rows.append("%6d %s" % (y, " ".join(spans)))
open(os.path.join(REF, "alturas.txt"), "w", encoding="utf-8").write("\n".join(rows))

# ---------------------------------------------------------------- prelight vecino (para calibrar el horneado)
lines = []
for o in meshes:
    for a in o.data.color_attributes:
        c = np.empty(len(a.data) * 4, dtype=np.float32)
        a.data.foreach_get("color_srgb", c)
        c = c.reshape(-1, 4)[:, :3] * 255
        lines.append("%s %s media %s p10 %s p90 %s" % (o["src"], a.name, c.mean(0).round(), np.percentile(c, 10, 0).round(), np.percentile(c, 90, 0).round()))
open(os.path.join(REF, "prelight.txt"), "w", encoding="utf-8").write("\n".join(lines))

# ---------------------------------------------------------------- hojas de contacto de los TXD
for t in CFG.get("txd", []):
    imgs = [i for i in bpy.data.images if i.name.startswith(t + ".txd/")]
    if not imgs:
        continue
    cell, cols = 160, 8
    rws = (len(imgs) + cols - 1) // cols
    sheet = np.ones((rws * cell, cols * cell, 4), dtype=np.float32)
    for k, im in enumerate(imgs):
        w, h = im.size
        px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
        ys = np.arange(cell - 6) * h // (cell - 6)
        xs = np.arange(cell - 6) * w // (cell - 6)
        r, c = divmod(k, cols)
        yb = sheet.shape[0] - (r + 1) * cell
        sheet[yb:yb + cell - 6, c * cell:c * cell + cell - 6] = px[ys][:, xs]
        print("[molde] %s celda fila %d col %d: %s (%dx%d)" % (t, r, c, im.name.split("/")[1], w, h))
    out = bpy.data.images.new("sheet_" + t, sheet.shape[1], sheet.shape[0], alpha=True)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = os.path.join(REF, "txd_%s.png" % t)
    out.file_format = "PNG"
    out.save()

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(REF, "molde.blend"))
print("[molde] listo:", REF)
