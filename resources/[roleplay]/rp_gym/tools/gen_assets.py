"""
rp_gym / tools/gen_assets.py
Genera los recursos propios del combate en el ring (sintetizados, sin material del juego):
  sounds/shutter.wav      obturador de camara (fotografos con flash)
  images/blood.png        sangre alrededor de la pantalla al recibir un golpe sin cubrirse
Uso: python -I tools/gen_assets.py
"""
import math, os, random, struct, wave, zlib

RATE = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def write_wav(name, data, gain=0.85):
    peak = max(abs(v) for v in data) or 1
    with wave.open(os.path.join(ROOT, "sounds", name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v / peak * gain * 32767)) for v in data))


def shutter():
    random.seed(5)
    n = int(RATE * 0.16)
    data = [0.0] * n
    for start, dur, amp in ((0.0, 0.004, 1.0), (0.055, 0.012, 0.7)):
        for i in range(int(start * RATE), int((start + dur * 4) * RATE)):
            t = i / RATE - start
            data[i] += (random.random() * 2 - 1) * amp * math.exp(-t / dur)
    write_wav("shutter.wav", data, 0.7)


def blood_png(size=512):
    random.seed(3)
    blobs = []
    for _ in range(70):   # manchas pegadas a los bordes
        a = random.uniform(0, 2 * math.pi)
        r = random.uniform(0.78, 1.05)
        blobs.append((0.5 + 0.5 * r * math.cos(a), 0.5 + 0.5 * r * math.sin(a), random.uniform(0.03, 0.11)))
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            u, v = x / size, y / size
            d = math.hypot(u - 0.5, v - 0.5) / 0.7071
            a = max(0.0, min(1.0, (d - 0.55) / 0.4)) ** 1.6
            for bx, by, br in blobs:
                q = math.hypot(u - bx, v - by) / br
                if q < 1:
                    a = max(a, (1 - q * q) * 0.95)
            shade = 70 + int(60 * (1 - a))
            row += bytes((shade + 40, 0, 0, int(a * 235)))
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag, payload):
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(os.path.join(ROOT, "images", "blood.png"), "wb") as f:
        f.write(png)


shutter()
blood_png()
print("generado en", os.path.normpath(ROOT))
