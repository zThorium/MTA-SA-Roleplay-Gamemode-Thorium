// Renderizador a PNG sin dependencias (usa solo zlib de Node/Bun). Dibuja la red vial alrededor de un punto,
// la ruta planeada (amarillo), la trayectoria de un auto coloreada por velocidad y los nodos con su id.
const fs = require('fs');
const zlib = require('zlib');

// ---------- PNG ----------
function crc32(buf) {
  let c, crc = 0xffffffff;
  if (!crc32.table) { crc32.table = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crc32.table[n] = c >>> 0; } }
  for (let i = 0; i < buf.length; i++) crc = crc32.table[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function encodePNG(w, h, rgb) {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 3 + 1)] = 0; rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 6 })), chunk('IEND', Buffer.alloc(0))]);
}

// ---------- lienzo ----------
class Canvas {
  constructor(w, h, bg = [18, 20, 24]) {
    this.w = w; this.h = h; this.px = Buffer.alloc(w * h * 3);
    for (let i = 0; i < w * h; i++) { this.px[i * 3] = bg[0]; this.px[i * 3 + 1] = bg[1]; this.px[i * 3 + 2] = bg[2]; }
  }
  set(x, y, c, a = 1) {
    x = Math.round(x); y = Math.round(y);
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const i = (y * this.w + x) * 3;
    for (let k = 0; k < 3; k++) this.px[i + k] = Math.round(this.px[i + k] * (1 - a) + c[k] * a);
  }
  line(x0, y0, x1, y1, c, th = 1, a = 1) {
    const dx = x1 - x0, dy = y1 - y0, n = Math.max(1, Math.ceil(Math.hypot(dx, dy)));
    const r = (th - 1) / 2;
    for (let i = 0; i <= n; i++) {
      const x = x0 + dx * i / n, y = y0 + dy * i / n;
      if (th <= 1) this.set(x, y, c, a);
      else for (let oy = -Math.ceil(r); oy <= Math.ceil(r); oy++) for (let ox = -Math.ceil(r); ox <= Math.ceil(r); ox++) if (ox * ox + oy * oy <= r * r + 0.25) this.set(x + ox, y + oy, c, a);
    }
  }
  circle(cx, cy, r, c, fill = true) {
    for (let y = -r; y <= r; y++) for (let x = -r; x <= r; x++) {
      const d = x * x + y * y;
      if (fill ? d <= r * r : (d <= r * r && d >= (r - 1.2) * (r - 1.2))) this.set(cx + x, cy + y, c);
    }
  }
  rect(x, y, w, h, c) { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.set(x + i, y + j, c); }
  text(str, x, y, c, s = 1) {
    for (const ch of String(str)) {
      const g = FONT[ch] || FONT['?'];
      for (let r = 0; r < 5; r++) for (let q = 0; q < 3; q++) if (g[r] & (4 >> q)) this.rect(x + q * s, y + r * s, s, s, c);
      x += 4 * s;
    }
  }
  save(file) { fs.writeFileSync(file, encodePNG(this.w, this.h, this.px)); }
}

// fuente 3x5 (digitos, letras usadas en leyendas y signos)
const F = (a, b, c, d, e) => [a, b, c, d, e];
const FONT = {
  '0': F(7, 5, 5, 5, 7), '1': F(2, 6, 2, 2, 7), '2': F(7, 1, 7, 4, 7), '3': F(7, 1, 7, 1, 7), '4': F(5, 5, 7, 1, 1),
  '5': F(7, 4, 7, 1, 7), '6': F(7, 4, 7, 5, 7), '7': F(7, 1, 1, 1, 1), '8': F(7, 5, 7, 5, 7), '9': F(7, 5, 7, 1, 7),
  '-': F(0, 0, 7, 0, 0), '_': F(0, 0, 0, 0, 7), '.': F(0, 0, 0, 0, 2), ' ': F(0, 0, 0, 0, 0), '?': F(7, 1, 3, 0, 2), ',': F(0, 0, 0, 2, 4), '>': F(4, 2, 1, 2, 4),
  A: F(2, 5, 7, 5, 5), B: F(6, 5, 6, 5, 6), C: F(7, 4, 4, 4, 7), D: F(6, 5, 5, 5, 6), E: F(7, 4, 6, 4, 7), F: F(7, 4, 6, 4, 4),
  G: F(7, 4, 5, 5, 7), H: F(5, 5, 7, 5, 5), I: F(7, 2, 2, 2, 7), K: F(5, 5, 6, 5, 5), L: F(4, 4, 4, 4, 7), M: F(5, 7, 7, 5, 5),
  N: F(6, 5, 5, 5, 5), O: F(7, 5, 5, 5, 7), P: F(7, 5, 7, 4, 4), R: F(6, 5, 6, 5, 5), S: F(7, 4, 7, 1, 7), T: F(7, 2, 2, 2, 2),
  U: F(5, 5, 5, 5, 7), V: F(5, 5, 5, 5, 2), X: F(5, 5, 2, 5, 5), Y: F(5, 5, 2, 2, 2), Z: F(7, 1, 2, 4, 7), J: F(1, 1, 1, 5, 7), Q: F(7, 5, 5, 7, 1), W: F(5, 5, 7, 7, 5),
  '/': F(1, 1, 2, 4, 4), '(': F(2, 4, 4, 4, 2), ')': F(2, 1, 1, 1, 2), ':': F(0, 2, 0, 2, 0), '=': F(0, 7, 0, 7, 0), '<': F(1, 2, 4, 2, 1), '%': F(5, 1, 2, 4, 5),
};

// velocidad (km/h) -> color: azul (parado) -> verde (25) -> rojo (50+)
function speedColor(kmh) {
  const t = Math.max(0, Math.min(1, kmh / 55));
  if (t < 0.5) { const u = t / 0.5; return [Math.round(40 * (1 - u)), Math.round(120 + 135 * u), Math.round(255 * (1 - u) + 60 * u)]; }
  const u = (t - 0.5) / 0.5; return [Math.round(60 + 195 * u), Math.round(255 * (1 - u) + 60 * u), 60];
}

// opts: { center:[x,y], radius (m), scale (px/m), title, route (wp), traj (samples), nodes (ids a resaltar), marks:[{x,y,label,color}] }
function renderScene(net, opts) {
  const R = opts.radius || 45, S = opts.scale || 9;
  const W = Math.round(R * 2 * S), H = W;
  const cv = new Canvas(W, H);
  const [cx, cy] = opts.center;
  const X = x => (x - cx + R) * S, Y = y => H - (y - cy + R) * S;     // y del mundo crece al norte
  // cuadricula 10 m
  for (let g = Math.ceil((cx - R) / 10) * 10; g < cx + R; g += 10) cv.line(X(g), 0, X(g), H, [30, 33, 38]);
  for (let g = Math.ceil((cy - R) / 10) * 10; g < cy + R; g += 10) cv.line(0, Y(g), W, Y(g), [30, 33, 38]);
  // red: enlaces transitables (cada sentido con su desplazamiento de carril) y nodos
  const near = [];
  for (let i = 1; i <= net.n; i++) if (Math.abs(net.x[i] - cx) < R + 30 && Math.abs(net.y[i] - cy) < R + 30 && (net.links[i] || []).length) near.push(i);
  for (const a of near) {
    (net.links[a] || []).forEach((b, k) => {
      const lanes = net.lanes[a][k]; const off = net.offset[a][k] ?? 2.5;
      const ax = net.x[a], ay = net.y[a], bx = net.x[b], by = net.y[b];
      cv.line(X(ax), Y(ay), X(bx), Y(by), [48, 58, 80], 1);
      if (lanes > 0) {
        const l = Math.hypot(bx - ax, by - ay) || 1, dx = (bx - ax) / l, dy = (by - ay) / l;
        const ox = dy * off, oy = -dx * off;                                   // desplazamiento a la derecha
        cv.line(X(ax + ox), Y(ay + oy), X(bx + ox), Y(by + oy), [40, 110, 70], 1);
        // flecha de sentido en el centro del carril
        const mx = (ax + bx) / 2 + ox, my = (ay + by) / 2 + oy;
        cv.line(X(mx), Y(my), X(mx - dx * 1.5 + dy * 0.7), Y(my - dy * 1.5 - dx * 0.7), [60, 150, 95]);
        cv.line(X(mx), Y(my), X(mx - dx * 1.5 - dy * 0.7), Y(my - dy * 1.5 + dx * 0.7), [60, 150, 95]);
      }
    });
  }
  const hi = new Set(opts.nodes || []);
  for (const i of near) {
    if (Math.abs(net.x[i] - cx) > R || Math.abs(net.y[i] - cy) > R) continue;
    const c = hi.has(i) ? [255, 160, 40] : [90, 120, 200];
    cv.rect(Math.round(X(net.x[i])) - 2, Math.round(Y(net.y[i])) - 2, 5, 5, c);
    if (hi.has(i) || (net.links[i] || []).length >= 3) cv.text(i, Math.round(X(net.x[i])) + 4, Math.round(Y(net.y[i])) - 8, hi.has(i) ? [255, 200, 120] : [130, 150, 200]);
  }
  // ruta planeada (amarillo) con sus puntos
  if (opts.route) {
    for (let i = 0; i < opts.route.length - 1; i++) cv.line(X(opts.route[i][0]), Y(opts.route[i][1]), X(opts.route[i + 1][0]), Y(opts.route[i + 1][1]), [255, 215, 40], 2);
    for (const p of opts.route) cv.circle(Math.round(X(p[0])), Math.round(Y(p[1])), 2, p[3] > 15 ? [255, 120, 40] : [255, 245, 150]);
  }
  // trayectoria simulada o real, coloreada por velocidad
  if (opts.traj && opts.traj.length) {
    for (let i = 0; i < opts.traj.length - 1; i++) {
      const a = opts.traj[i], b = opts.traj[i + 1];
      cv.line(X(a.x), Y(a.y), X(b.x), Y(b.y), speedColor(a.v), 3);
    }
    cv.circle(Math.round(X(opts.traj[0].x)), Math.round(Y(opts.traj[0].y)), 5, [255, 255, 255], false);
  }
  // segunda trayectoria (p. ej. el simulador sobre la del juego): linea fina blanca
  if (opts.traj2 && opts.traj2.length) {
    for (let i = 0; i < opts.traj2.length - 1; i++) cv.line(X(opts.traj2[i].x), Y(opts.traj2[i].y), X(opts.traj2[i + 1].x), Y(opts.traj2[i + 1].y), [235, 235, 235], 1);
  }
  for (const m of opts.marks || []) {
    cv.line(X(m.x) - 7, Y(m.y) - 7, X(m.x) + 7, Y(m.y) + 7, m.color || [255, 60, 60], 2);
    cv.line(X(m.x) - 7, Y(m.y) + 7, X(m.x) + 7, Y(m.y) - 7, m.color || [255, 60, 60], 2);
    if (m.label) cv.text(m.label, Math.round(X(m.x)) + 9, Math.round(Y(m.y)) - 4, m.color || [255, 60, 60], 2);
  }
  // titulo y leyenda
  if (opts.title) { cv.rect(0, 0, W, 22, [10, 11, 14]); cv.text(String(opts.title).toUpperCase(), 6, 6, [230, 230, 230], 2); }
  const lg = [['RUTA', [255, 215, 40]], ['CARRIL', [40, 110, 70]], ['LENTO', speedColor(5)], ['MEDIO', speedColor(27)], ['RAPIDO', speedColor(55)]];
  let lx = 6; const ly = H - 14;
  for (const [t, c] of lg) { cv.rect(lx, ly, 10, 6, c); cv.text(t, lx + 13, ly, [200, 200, 200]); lx += 13 + t.length * 4 + 10; }
  cv.text('10 M = ' + Math.round(10 * S) + ' PX', W - 110, ly, [140, 140, 140]);
  return cv;
}

module.exports = { Canvas, renderScene, speedColor, encodePNG };
