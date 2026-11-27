// Port a JS de la generacion de rutas de rp_citizens/c_citizens.lua (computeTurnPoints, planSegment sin la
// comprobacion de colision, filletCorners). Si cambias la logica en el Lua, cambia tambien aqui.
// Cada punto de ruta: [x, y, z, giro, cruce, eje_semaforo, maniobra]  (igual que el Lua).
const STEP = 6;
const TUNE = { rMin: 0, rMinTurn: 45 };   // parametros de experimento (audit.js --rmin 7)
const FILLET_R = 8, FILLET_MIN_TURN = 55;

const deg = r => r * 180 / Math.PI;
const hyp = (a, b) => Math.hypot(a, b);

function dir(ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay, l = hyp(dx, dy);
  if (l < 0.01) return [0, 1, 0];
  return [dx / l, dy / l, l];
}

function laneInfo(net, a, b) {
  const l = net.links[a];
  if (l) for (let k = 0; k < l.length; k++) if (l[k] === b) return [net.lanes[a][k] ?? 1, net.offset[a][k] ?? 2.5];
  return [0, 2.5];
}
const canDrive = (net, a, b) => laneInfo(net, a, b)[0] > 0;
const isJunction = (net, n) => (net.links[n] || []).length >= 3;
function getLight(net, a, b) {
  const l = net.links[a];
  if (l && net.light[a]) for (let k = 0; k < l.length; k++) if (l[k] === b) return net.light[a][k] || 0;
  return 0;
}

function intersect(px, py, dx, dy, qx, qy, ex, ey) {
  const den = dx * ey - dy * ex;
  if (Math.abs(den) < 0.05) return null;
  const t = ((qx - px) * ey - (qy - py) * ex) / den;
  if (t < 0 || t > 30) return null;
  // tambien por delante de q en su direccion (si no, la Bezier se pasa del final de la curva y vuelve atras)
  if (((qx - px) * dy - (qy - py) * dx) / den < 0) return null;
  return [px + dx * t, py + dy * t];
}

// Salidas posibles de B viniendo de prev (sin el azar: todas, la mas recta primero)
function exitCandidates(net, node, prev) {
  const [d1x, d1y] = dir(net.x[prev], net.y[prev], net.x[node], net.y[node]);
  for (const limit of [-0.5, -0.75]) {
    const opts = [];
    for (const n of net.links[node] || []) {
      if (n !== prev && canDrive(net, node, n)) {
        const [d2x, d2y] = dir(net.x[node], net.y[node], net.x[n], net.y[n]);
        const dot = d1x * d2x + d1y * d2y;
        if (dot > limit) opts.push({ n, dot });
      }
    }
    if (opts.length) return opts.sort((a, b) => b.dot - a.dot).map(o => o.n);
  }
  return canDrive(net, node, prev) ? [prev] : [];
}

function computeTurnPoints(net, A, B, C, rScale) {
  const ax = net.x[A], ay = net.y[A], bx = net.x[B], by = net.y[B], bz = net.z[B], cx = net.x[C], cy = net.y[C];
  const [d1x, d1y, len1] = dir(ax, ay, bx, by);
  const [d2x, d2y, len2] = dir(bx, by, cx, cy);
  const off1 = laneInfo(net, A, B)[1], off2 = laneInfo(net, B, C)[1];
  const turn = deg(Math.acos(Math.max(-1, Math.min(1, d1x * d2x + d1y * d2y))));
  const leftTurn = (d1x * d2y - d1y * d2x) > 0.2;
  // TUNE.rMin: radio minimo de la curva para giros de >= 45 grados aunque el enlace sea mas corto (experimento)
  const floorR = (turn >= TUNE.rMinTurn) ? TUNE.rMin : 0;
  const cap1 = Math.max(len1 * 0.48, Math.min(len1 * 0.6, 8), floorR);
  const cap2 = Math.max(len2 * 0.48, Math.min(len2 * 0.6, 8), floorR);
  let R = Math.min((isJunction(net, B) ? (leftTurn ? 14 : 12) : 9) * (rScale || 1), cap1, cap2);
  if (C === A) R = Math.min(R, 4);
  const junction = isJunction(net, B) ? B : null;
  const ex = bx - d1x * R + d1y * off1, ey = by - d1y * R - d1x * off1;
  const xx = bx + d2x * R + d2y * off2, xy = by + d2y * R - d2x * off2;
  let axis = null;
  if (getLight(net, A, B) > 0) axis = Math.abs(d1x) > Math.abs(d1y) ? 'ew' : 'ns';
  const man = junction ? [d1x, d1y, d2x, d2y, turn] : null;
  const pts = [[ex, ey, bz, 0, junction, axis, man]];
  if (turn < 10) {
    pts.push([xx, xy, bz, 0, junction, null, man]);
  } else {
    let q = intersect(ex, ey, d1x, d1y, xx, xy, -d2x, -d2y);
    if (!q) q = [bx + (d1y * off1 + d2y * off2) / 2, by - (d1x * off1 + d2x * off2) / 2];
    const steps = Math.max(5, Math.ceil(turn / 10));
    for (let i = 1; i <= steps; i++) {
      const t = i / steps, u = 1 - t;
      pts.push([u * u * ex + 2 * u * t * q[0] + t * t * xx, u * u * ey + 2 * u * t * q[1] + t * t * xy, bz, turn, junction, null, man]);
    }
  }
  return { pts, turn, R, len1, len2 };
}

// ---------- redondeo de esquinas (port de filletCorners) ----------
const wd = (a, b) => hyp(a[0] - b[0], a[1] - b[1]);
function backIdx(wp, i, d, lo) { let acc = 0, j = i; while (j > lo) { acc += wd(wp[j], wp[j - 1]); j--; if (acc >= d) return j; } return null; }
function fwdIdx(wp, i, d) { let acc = 0, k = i; while (k < wp.length - 1) { acc += wd(wp[k], wp[k + 1]); k++; if (acc >= d) return k; } return null; }
function turnAt(wp, i, jj, kk) {
  const ax = wp[i][0] - wp[jj][0], ay = wp[i][1] - wp[jj][1], bx = wp[kk][0] - wp[i][0], by = wp[kk][1] - wp[i][1];
  const la = hyp(ax, ay), lb = hyp(bx, by);
  if (la < 0.01 || lb < 0.01) return 0;
  return deg(Math.acos(Math.max(-1, Math.min(1, (ax * bx + ay * by) / (la * lb)))));
}
function unit(ax, ay, bx, by) { const dx = bx - ax, dy = by - ay, l = hyp(dx, dy); return l < 0.01 ? null : [dx / l, dy / l]; }

// from: indice (base 0) desde el que mirar
function filletCorners(wp, from) {
  const lo = Math.max(0, from);
  let i = lo + 1, done = 0, changed = 0;
  while (i < wp.length - 1 && done < 3) {
    const jj = backIdx(wp, i, 3, lo), kk = fwdIdx(wp, i, 3);
    if (jj != null && kk != null && turnAt(wp, i, jj, kk) >= FILLET_MIN_TURN) {
      let i1 = i, i2 = i, jj1 = jj, kk2 = kk, k = i + 1;
      while (k < wp.length - 1) {
        const j2 = backIdx(wp, k, 3, lo), k2 = fwdIdx(wp, k, 3);
        if (j2 != null && k2 != null && turnAt(wp, k, j2, k2) >= FILLET_MIN_TURN) { i2 = k; kk2 = k2; k++; } else break;
      }
      let ok = false;
      jj1 = backIdx(wp, i1, 9, lo) ?? jj1;
      kk2 = fwdIdx(wp, i2, 9) ?? kk2;
      const ax = wp[jj1][0], ay = wp[jj1][1], bx = wp[kk2][0], by = wp[kk2][1];
      let d1 = jj1 > lo ? unit(wp[jj1 - 1][0], wp[jj1 - 1][1], ax, ay) : null;
      if (!d1) d1 = unit(ax, ay, wp[i1][0], wp[i1][1]);
      let d2 = kk2 < wp.length - 1 ? unit(bx, by, wp[kk2 + 1][0], wp[kk2 + 1][1]) : null;
      if (!d2) d2 = unit(wp[i2][0], wp[i2][1], bx, by);
      let blocked = false;
      for (let q = jj1 + 1; q <= kk2 - 1; q++) if (wp[q][5]) { blocked = true; break; }
      if (d1 && d2 && !blocked) {
        const den = d1[0] * d2[1] - d1[1] * d2[0];
        if (Math.abs(den) > 0.1) {
          const t = ((bx - ax) * d2[1] - (by - ay) * d2[0]) / den;
          const u = ((bx - ax) * d1[1] - (by - ay) * d1[0]) / den;
          if (t > 0.5 && u < -0.5 && t < 40 && -u < 40) {
            const theta = Math.acos(Math.max(-1, Math.min(1, d1[0] * d2[0] + d1[1] * d2[1])));
            const L = Math.min(FILLET_R * Math.tan(theta / 2), t - 0.3, -u - 0.3);
            if (L >= 2 && theta > 0.5) {
              const cx = ax + d1[0] * t, cy = ay + d1[1] * t;
              const t1 = [cx - d1[0] * L, cy - d1[1] * L], t2 = [cx + d2[0] * L, cy + d2[1] * L];
              const z0 = wp[jj1][2], z1 = wp[kk2][2];
              const steps = Math.max(4, Math.ceil(deg(theta) / 12)), src = wp[i1], arc = [];
              for (let st = 0; st <= steps; st++) {
                const f = st / steps, g = 1 - f;
                arc.push([g * g * t1[0] + 2 * g * f * cx + f * f * t2[0], g * g * t1[1] + 2 * g * f * cy + f * f * t2[1], z0 + (z1 - z0) * f, deg(theta), src[4], null, src[6]]);
              }
              const tail = wp.slice(kk2);
              wp.length = jj1 + 1;
              arc.forEach(p => wp.push(p));
              tail.forEach(p => wp.push(p));
              i = jj1 + arc.length + 1; done++; changed++; ok = true;
            }
          }
        }
      }
      if (!ok) i = i2 + 1;
    } else i++;
  }
  return changed;
}

// ---------- ruta por una cadena de nodos (equivale a llamar a planSegment en cada cruce) ----------
// chain = [n0, n1, n2, ...]: el auto entra por n0->n1 y sigue por n2, n3...
// opts.fillet=false desactiva el redondeo (para medir cuanto aporta)
function planChain(net, chain, opts = {}) {
  const wp = [];
  const info = [];
  for (let k = 1; k < chain.length - 1; k++) {
    const A = chain[k - 1], B = chain[k], C = chain[k + 1];
    const m = computeTurnPoints(net, A, B, C);
    let sx, sy, sz;
    if (wp.length) {
      // igual que planSegment: en tramos cortos los arcos de dos nodos seguidos se solapan y el inicio de la
      // curva nueva queda detras del final de la anterior; esos puntos harian retroceder la ruta y se quitan
      [sx, sy, sz] = wp[wp.length - 1];
      const [ux, uy] = dir(net.x[A], net.y[A], net.x[B], net.y[B]);
      const last = wp[wp.length - 1];
      while (m.pts.length && (m.pts[0][0] - sx) * ux + (m.pts[0][1] - sy) * uy < 0.5) {
        const drop = m.pts.shift(), keep = m.pts[0] || last;
        keep[3] = Math.max(keep[3] || 0, drop[3] || 0);   // el giro sigue existiendo: no perder el freno de curva
        for (const f of [4, 5, 6]) if (drop[f] && !keep[f]) keep[f] = drop[f];
      }
      if (!m.pts.length) continue;
    }
    else {
      const [dx, dy] = dir(net.x[A], net.y[A], net.x[B], net.y[B]);
      const off = laneInfo(net, A, B)[1];
      sx = net.x[A] + dy * off; sy = net.y[A] - dx * off; sz = net.z[A];
    }
    const [ex, ey, ez] = m.pts[0];
    const len = hyp(ex - sx, ey - sy), n = Math.floor(len / STEP);
    for (let i = 1; i <= n - 1; i++) { const t = i / n; wp.push([sx + (ex - sx) * t, sy + (ey - sy) * t, sz + (ez - sz) * t, 0, null, null, null]); }
    const oldN = wp.length;
    m.pts.forEach(p => wp.push(p));
    if (opts.fillet !== false) {
      const from1 = Math.max(3, oldN > 1 ? ((backIdx(wp, oldN - 1, 18, 0) ?? 0) + 1) : 1);   // base 1 como el Lua
      filletCorners(wp, from1 - 1);
    }
    info.push({ node: B, turn: m.turn, R: m.R, len1: m.len1, len2: m.len2 });
  }
  return { wp, info };
}

// radio minimo de la poligonal en el tramo [d0, d1] de camino medido desde "from" (indice); remuestrea a >= 4 m (escala de un auto: ignora el ruido de puntos muy juntos)
function minRadius(wp, i0 = 0, i1 = wp.length - 1) {
  const pts = [];
  for (let i = i0; i <= i1; i++) {
    const p = wp[i];
    if (!pts.length || hyp(p[0] - pts[pts.length - 1][0], p[1] - pts[pts.length - 1][1]) >= 4) pts.push(p);
  }
  let r = Infinity, at = null;
  for (let i = 1; i < pts.length - 1; i++) {
    const a = pts[i - 1], b = pts[i], c = pts[i + 1];
    const ab = hyp(b[0] - a[0], b[1] - a[1]), bc = hyp(c[0] - b[0], c[1] - b[1]), ac = hyp(c[0] - a[0], c[1] - a[1]);
    const cross = Math.abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]));
    if (cross < 1e-6) continue;
    const R = ab * bc * ac / (2 * cross);
    if (R < r) { r = R; at = b; }
  }
  return { r, at };
}

module.exports = { TUNE, dir, laneInfo, canDrive, isJunction, exitCandidates, computeTurnPoints, filletCorners, planChain, minRadius, STEP };
