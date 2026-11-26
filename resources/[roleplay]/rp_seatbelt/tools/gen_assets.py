"""
rp_seatbelt / tools/gen_assets.py
Genera las imagenes propias del recurso (sintetizadas, sin material del juego):
  images/scratch.png   rasgunos y sangre en los bordes de la pantalla (choque leve sin cinturon)
  images/eyelid.png    negro con un hueco eliptico de borde suave (parpados al despertar)
Uso: python -I tools/gen_assets.py
"""
import math, os, random, struct, zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def write_png(name, size, pixel):
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            row += bytes(pixel(x / size, y / size))
        rows.append(bytes(row))

    def chunk(tag, payload):
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.join(ROOT, "images"), exist_ok=True)
    with open(os.path.join(ROOT, "images", name), "wb") as f:
        f.write(png)


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def scratch_png(size=512):
    random.seed(11)
    lines = []   # rasgunos finos, en grupos de 3 (como un zarpazo), pegados a los bordes
    for _ in range(14):
        a = random.uniform(0, 2 * math.pi)
        r = random.uniform(0.80, 0.98)
        cx, cy = 0.5 + 0.5 * r * math.cos(a), 0.5 + 0.5 * r * math.sin(a)
        ang = a + math.pi / 2 + random.uniform(-0.6, 0.6)
        ln = random.uniform(0.06, 0.16)
        for k in range(3):
            ox, oy = math.cos(a) * k * 0.012, math.sin(a) * k * 0.012
            hx, hy = math.cos(ang) * ln / 2, math.sin(ang) * ln / 2
            lines.append((cx + ox - hx, cy + oy - hy, cx + ox + hx, cy + oy + hy, random.uniform(0.0025, 0.0045)))

    def pixel(u, v):
        d = math.hypot(u - 0.5, v - 0.5) / 0.7071
        a = max(0.0, min(1.0, (d - 0.62) / 0.38)) ** 1.8 * 0.75   # vineta rojiza suave
        for ax, ay, bx, by, w in lines:
            if min(ax, bx) - 0.02 < u < max(ax, bx) + 0.02 and min(ay, by) - 0.02 < v < max(ay, by) + 0.02:
                q = seg_dist(u, v, ax, ay, bx, by) / w
                if q < 1:
                    a = max(a, (1 - q) * 0.95)
        return (150, 10, 12, int(a * 255))

    write_png("scratch.png", size, pixel)


def eyelid_png(size=256):
    def pixel(u, v):
        d = math.hypot(u - 0.5, v - 0.5) * 2   # 0 centro, 1 borde
        a = max(0.0, min(1.0, (d - 0.55) / 0.45))
        return (0, 0, 0, int(a * 255))

    write_png("eyelid.png", size, pixel)


scratch_png()
eyelid_png()
print("generado en", os.path.normpath(ROOT))
