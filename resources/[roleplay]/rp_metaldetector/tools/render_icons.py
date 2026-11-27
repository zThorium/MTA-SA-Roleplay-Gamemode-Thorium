"""
rp_metaldetector / tools/render_icons.py

Renderiza los iconos de la tienda (images/detectors/detector_<n>.png, 256x256, fondo transparente)
a partir de tools/detector.blend (lo guarda build_detector.py). No necesita DragonFF.

Uso: blender.exe --background "<recurso>/tools/detector.blend" --python render_icons.py -- <ruta del recurso>
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RES = argv[0] if argv else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RES, "tools"))
from detector_tiers import TIERS, FIXED, srgb_to_lin

scene = bpy.context.scene
det = bpy.data.objects["metal_detector"]

# Quitar cámaras y luces de pasadas anteriores
for o in [o for o in scene.objects if o.type in ("CAMERA", "LIGHT")]:
    bpy.data.objects.remove(o)

# Encuadre: caja del modelo vista de lado (3/4), cámara ortográfica que la abarca entera
corners = [det.matrix_world @ Vector(c) for c in det.bound_box]
lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
center = (lo + hi) / 2
size = (hi - lo).length

view = Vector((1.0, -0.18, 0.22)).normalized()     # de lado, un poco por delante y desde arriba
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
cam.location = center + view * 3
cam.rotation_mode = "QUATERNION"
cam.rotation_quaternion = (center - cam.location).to_track_quat("-Z", "Y")
scene.camera = cam
# Girar la cámara sobre su eje para que el detector quede en diagonal (llena más el cuadrado)
bpy.context.view_layer.update()
cam.rotation_quaternion = cam.rotation_quaternion @ Matrix.Rotation(math.radians(-12), 4, "Z").to_quaternion()
bpy.context.view_layer.update()
# Encuadre ajustado: vértices en el espacio de la cámara, centrado y escala ortográfica al tamaño real
inv = cam.matrix_world.inverted()
pts = [inv @ (det.matrix_world @ v.co) for v in det.data.vertices]
minx, maxx = min(p.x for p in pts), max(p.x for p in pts)
miny, maxy = min(p.y for p in pts), max(p.y for p in pts)
cam.location = cam.matrix_world @ Vector(((minx + maxx) / 2, (miny + maxy) / 2, 0))
cam_data.ortho_scale = max(maxx - minx, maxy - miny) * 1.06

for loc, energy in ((view * 3 + Vector((0, -1.5, 2)), 250), (Vector((-2, 1, 1)), 90), (Vector((0, 2, -1)), 60),
                    (-view * 3 + Vector((0, 0, 1)), 450)):    # la última, de contra: marca la silueta
    ld = bpy.data.lights.new("l", "AREA"); ld.energy = energy; ld.size = 2.5
    lo_ = bpy.data.objects.new("l", ld); lo_.location = center + loc; scene.collection.objects.link(lo_)
    lo_.rotation_mode = "QUATERNION"; lo_.rotation_quaternion = (center - lo_.location).to_track_quat("-Z", "Y")

scene.render.engine = "CYCLES"
scene.cycles.samples = 64
scene.cycles.device = "CPU"
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = 256
scene.view_settings.view_transform = "Standard"     # colores fieles (Filmic/AgX los lava)
if not scene.world:
    scene.world = bpy.data.worlds.new("w")
scene.world.color = (0.05, 0.05, 0.06)

mats = {m.name.replace("md_", ""): m for m in bpy.data.materials if m.name.startswith("md_")}
icons = os.path.join(RES, "images", "detectors")
os.makedirs(icons, exist_ok=True)
for n, t in TIERS.items():
    cols = dict(FIXED, body=t["body"], accent=t["accent"], shaft=t["shaft"])
    for key, c in cols.items():
        if key in mats:
            mats[key].node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*srgb_to_lin(c), 1)
    mats["shaft"].node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.9 if n == 5 else 0.6
    scene.render.filepath = os.path.join(icons, f"detector_{n}.png")
    bpy.ops.render.render(write_still=True)
    print(f"[iconos] {scene.render.filepath}")
print("[iconos] listo")
