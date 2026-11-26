"""
rp_gym / tools/gen_assets.py
Genera los recursos propios del combate en el ring (sintetizados, sin material del juego):
  sounds/crowd_cheer.wav  ovacion corta del publico ("uoooh") al conectar un golpe
  sounds/crowd_loop.wav   murmullo del publico en bucle durante el combate
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


def voice(n, start, length, pitch, vowel_open):
    """Una voz del publico: diente de sierra con vibrato por dos formantes (vocal 'o'/'u')."""
    out = [0.0] * n
    f1, f2 = (500 + 250 * vowel_open), (900 + 300 * vowel_open)
    s1 = s2 = 0.0
    v1 = v2 = 0.0
    phase = 0.0
    for i in range(int(start * RATE), min(n, int((start + length) * RATE))):
        t = i / RATE - start
        env = max(0.0, math.sin(math.pi * min(1, t / length))) ** 1.5
        f = pitch * (1 + 0.25 * min(1, t / (length * 0.4))) * (1 + 0.012 * math.sin(2 * math.pi * 5.5 * t))
        phase = (phase + f / RATE) % 1
        x = (2 * phase - 1) * env
        # resonadores de dos polos (formantes)
        for fc, state in ((f1, 0), (f2, 1)):
            r = 0.985
            c = 2 * r * math.cos(2 * math.pi * fc / RATE)
            if state == 0:
                y = x + c * s1 - r * r * v1
                v1, s1 = s1, y
                a = y
            else:
                y = x + c * s2 - r * r * v2
                v2, s2 = s2, y
                b = y
        out[i] = a + 0.6 * b
    return out


def noise_band(n, lo, hi):
    out, lp1, lp2 = [], 0.0, 0.0
    a1, a2 = 1 - math.exp(-2 * math.pi * hi / RATE), 1 - math.exp(-2 * math.pi * lo / RATE)
    for _ in range(n):
        x = random.random() * 2 - 1
        lp1 += a1 * (x - lp1)
        lp2 += a2 * (lp1 - lp2)
        out.append(lp1 - lp2)
    return out


def mix(dst, src, gain):
    for i, v in enumerate(src):
        dst[i] += v * gain


def crowd_cheer():
    random.seed(11)
    n = int(RATE * 2.2)
    data = [0.0] * n
    for _ in range(26):
        mix(data, voice(n, random.uniform(0, 0.35), random.uniform(1.2, 1.8), random.uniform(110, 290), random.random()), 0.05)
    hiss = noise_band(n, 300, 2600)
    for i in range(n):
        t = i / RATE
        data[i] += hiss[i] * 0.9 * max(0.0, math.sin(math.pi * min(1, t / 2.2))) ** 1.2
    write_wav("crowd_cheer.wav", data)


def crowd_loop():
    random.seed(23)
    length = 6.0
    n = int(RATE * length)
    data = [0.0] * n
    for _ in range(18):
        mix(data, voice(n, random.uniform(0, length - 1.2), random.uniform(0.5, 1.1), random.uniform(100, 260), random.random()), 0.03)
    hiss = noise_band(n, 200, 1800)
    for i in range(n):
        data[i] += hiss[i] * 0.55
    # fundido cruzado del final sobre el principio para que el bucle no se note
    fade = int(RATE * 0.5)
    for i in range(fade):
        k = i / fade
        data[i] = data[i] * k + data[n - fade + i] * (1 - k)
    write_wav("crowd_loop.wav", data[:n - fade], 0.6)


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


crowd_cheer()
crowd_loop()
shutter()
blood_png()
print("generado en", os.path.normpath(ROOT))
