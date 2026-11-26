"""
rp_seatbelt / tools/gen_assets.py
Genera las imagenes propias del recurso (sintetizadas, sin material del juego):
  images/border.png    rojo en los bordes de la pantalla (choque leve sin cinturon)
  images/eyelid.png    negro con un hueco eliptico de borde suave (parpados al despertar)
Uso: python -I tools/gen_assets.py
"""
import math, os, struct, zlib

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


def border_png(size=512):
    def pixel(u, v):
        d = math.hypot(u - 0.5, v - 0.5) / 0.7071
        a = max(0.0, min(1.0, (d - 0.55) / 0.45)) ** 1.6 * 0.85   # rojo solo en los bordes
        return (150, 10, 12, int(a * 255))

    write_png("border.png", size, pixel)


def eyelid_png(size=256):
    def pixel(u, v):
        d = math.hypot(u - 0.5, v - 0.5) * 2   # 0 centro, 1 borde
        a = max(0.0, min(1.0, (d - 0.55) / 0.45))
        return (0, 0, 0, int(a * 255))

    write_png("eyelid.png", size, pixel)


border_png()
eyelid_png()
print("generado en", os.path.normpath(ROOT))
