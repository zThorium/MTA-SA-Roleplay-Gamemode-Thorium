// Simulador cinematico de UN auto siguiendo una ruta, con la misma logica de control que rp_citizens
// (descarte de puntos, pathTrack, volante, velocidad objetivo en curvas). NO es la fisica de GTA: es un
// modelo de bicicleta con limite de volante segun la velocidad (como CCarCtrl::FindMaxSteerAngle de GTA SA) y
// limite de agarre lateral. Sirve para ver si la GEOMETRIA permite tomar una curva y si el control es estable;
// no sustituye la prueba en juego. Sin las ayudas "sobre rieles" (son parches de fisica de MTA).
const WHEELBASE = 2.8;       // m
const GRIP = 7.0;            // m/s2 de aceleracion lateral maxima antes de derrapar (subvirar)
const STEER_LAG = 0.12;      // s: el volante tarda en llegar a lo pedido
const TICK = 0.08;           // s: tick de IA (CFG.CAR_TICK)
const CRUISE = 50;           // km/h (CFG.CAR_SPEED)

const rad = d => d * Math.PI / 180, deg = r => r * 180 / Math.PI;
const hyp = Math.hypot;
function heading(dx, dy) { return deg(Math.atan2(-dx, dy)); }
function angleDiff(a, b) { let d = (a - b) % 360; if (d > 180) d -= 360; if (d < -180) d += 360; return d; }
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

function curveCap(turn, dist, lenF) {
  const inside = Math.max(turn >= 70 ? 8 : 10, CRUISE * (1 - turn / 115)) * (lenF || 1);
  return Math.sqrt(inside * inside + 60 * Math.max(0, dist - 2));
}

function pathTrack(trail, wp, x, y, speed, rz) {
  const pts = [];
  for (const t of trail) pts.push(t);
  for (let i = 0; i < Math.min(wp.length, 12); i++) pts.push(wp[i]);
  if (pts.length < 2) return null;
  let bi = 0, bt = 0, bd = Infinity;
  for (let i = 0; i < pts.length - 1; i++) {
    const ax = pts[i][0], ay = pts[i][1], sx = pts[i + 1][0] - ax, sy = pts[i + 1][1] - ay, l2 = sx * sx + sy * sy;
    const t = l2 > 0.01 ? clamp(((x - ax) * sx + (y - ay) * sy) / l2, 0, 1) : 0;
    const d = (x - (ax + sx * t)) ** 2 + (y - (ay + sy * t)) ** 2;
    if (d < bd) { bi = i; bt = t; bd = d; }
  }
  const ax = pts[bi][0], ay = pts[bi][1];
  const l0 = hyp(pts[bi + 1][0] - ax, pts[bi + 1][1] - ay) || 1;
  const ux = (pts[bi + 1][0] - ax) / l0, uy = (pts[bi + 1][1] - ay) / l0;
  const e = (x - ax) * -uy + (y - ay) * ux;
  let remain = 3 + speed * 0.1, i = bi, t = bt;
  while (i < pts.length - 2) {
    const seg = hyp(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]);
    const left = seg * (1 - t);
    if (remain <= left) break;
    remain -= left; i++; t = 0;
  }
  const vl = hyp(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) || 1;
  const pathHeading = heading((pts[i + 1][0] - pts[i][0]) / vl, (pts[i + 1][1] - pts[i][1]) / vl);
  const desired = pathHeading - deg(Math.atan(1.5 * e / (speed / 3.6 + 2)));
  return { diff: angleDiff(desired, rz), e };
}

function distToPolyline(poly, x, y) {
  let best = Infinity;
  for (let i = 0; i < poly.length - 1; i++) {
    const ax = poly[i][0], ay = poly[i][1], sx = poly[i + 1][0] - ax, sy = poly[i + 1][1] - ay, l2 = sx * sx + sy * sy;
    const t = l2 > 0.01 ? clamp(((x - ax) * sx + (y - ay) * sy) / l2, 0, 1) : 0;
    best = Math.min(best, hyp(x - (ax + sx * t), y - (ay + sy * t)));
  }
  return best;
}

// wpIn: ruta completa (se copia). opts: { speed0 (km/h), lenF, maxTime, trace }
function simulate(wpIn, opts = {}) {
  if (wpIn.length < 3) return { ok: false, reason: 'ruta_corta', samples: [], maxDev: 0 };
  // Tramo de aproximacion: el auto llega a la ruta ya en marcha por una recta (por defecto 40 m, como si viniera
  // de un tramo anterior). Sin esto, una esquina al principio de la cadena se tomaba desde parado a 50 km/h.
  const lead = [];
  const leadLen = opts.leadIn ?? 40;
  if (leadLen > 0) {
    const l0 = hyp(wpIn[1][0] - wpIn[0][0], wpIn[1][1] - wpIn[0][1]) || 1;
    const ux = (wpIn[1][0] - wpIn[0][0]) / l0, uy = (wpIn[1][1] - wpIn[0][1]) / l0;
    for (let d = leadLen; d >= 6; d -= 6) lead.push([wpIn[0][0] - ux * d, wpIn[0][1] - uy * d, wpIn[0][2], 0, null, null, null]);
  }
  const full = lead.concat(wpIn).map(p => p.slice());
  const wp = lead.concat(wpIn).map(p => p.slice());
  const lenF = opts.lenF || 1;
  // arranca sobre el primer punto, mirando al segundo
  let x = wp[0][0], y = wp[0][1], rz = heading(wp[1][0] - wp[0][0], wp[1][1] - wp[0][1]);
  let v = (opts.speed0 ?? CRUISE) / 3.6;                // m/s
  let steerOut = 0, delta = 0;
  const trail = [];
  let t = 0, tickAcc = TICK;                            // fuerza una decision en t=0
  let accel = 0, brake = 0, steerCmd = 0;
  const samples = [];
  let maxDev = 0, maxDevAt = null, minSpeed = 1e9, lastDev = 0, reason = null, passedFirst = false;
  const endPt = full[full.length - 1];
  const maxTime = opts.maxTime || 60;
  const dt = 0.02;
  let lastPassed = null, step = 0;
  while (t < maxTime) {
    if (tickAcc >= TICK) {
      tickAcc = 0;
      const speed = v * 3.6;
      const fx = -Math.sin(rad(rz)), fy = Math.cos(rad(rz));
      // ---- curva y distancia de mirada ----
      let curveSoon = false, cd = 0, clx = x, cly = y;
      for (let i = 0; i < Math.min(wp.length, 8); i++) {
        cd += hyp(wp[i][0] - clx, wp[i][1] - cly); clx = wp[i][0]; cly = wp[i][1];
        if (cd > 14) break;
        if (wp[i][3] > 40) { curveSoon = true; break; }
      }
      const justLeft = lastPassed && lastPassed[3] > 20 && wp[0][3] <= 20 && hyp(x - lastPassed[0], y - lastPassed[1]) < 12;
      const inCurve = curveSoon || wp[0][3] > 20 || justLeft;
      const lookahead = curveSoon ? (2.5 + speed * 0.05) : ((inCurve ? 3.5 : 6) + speed * (inCurve ? 0.06 : 0.1));
      // ---- descarte de puntos ----
      const pop = () => { const p = wp.shift(); lastPassed = p; trail.push(p); if (trail.length > 6) trail.shift(); };
      while (wp.length > 1 && (hyp(x - wp[0][0], y - wp[0][1]) < lookahead
        || ((wp[0][0] - x) * fx + (wp[0][1] - y) * fy < 0 && (wp[1][0] - x) * fx + (wp[1][1] - y) * fy > -2 && hyp(x - wp[0][0], y - wp[0][1]) < 12))) pop();
      while (wp.length > 1) {
        const a = wp[0], b = wp[1], sx = b[0] - a[0], sy = b[1] - a[1], l2 = sx * sx + sy * sy;
        const ahead = (a[0] - x) * fx + (a[1] - y) * fy;
        const passedAlong = l2 > 0.01 && ((x - a[0]) * sx + (y - a[1]) * sy) / l2 > 0;
        if (!(passedAlong && ahead < 2)) break;
        pop();
      }
      // ---- desviacion respecto de la poligonal (rastro + 4 siguientes) ----
      const chain = trail.concat(wp.slice(0, 4));
      let dev = Infinity;
      for (let i = 0; i < chain.length - 1; i++) {
        const ax = chain[i][0], ay = chain[i][1], sx = chain[i + 1][0] - ax, sy = chain[i + 1][1] - ay, l2 = sx * sx + sy * sy;
        const tt = l2 > 0.01 ? clamp(((x - ax) * sx + (y - ay) * sy) / l2, 0, 1) : 0;
        dev = Math.min(dev, hyp(x - (ax + sx * tt), y - (ay + sy * tt)));
      }
      if (!isFinite(dev)) dev = hyp(x - wp[0][0], y - wp[0][1]);
      lastDev = dev;
      // ---- rumbo deseado ----
      let diff = angleDiff(heading(wp[0][0] - x, wp[0][1] - y), rz);
      if (inCurve || dev > 1.5) { const tr = pathTrack(trail, wp, x, y, speed, rz); if (tr) diff = tr.diff; }
      // ---- velocidad objetivo ----
      let target = CRUISE, curveLimit = 999, dist = 0, lx = x, ly = y;
      for (let i = 0; i < Math.min(wp.length, 14); i++) {
        dist += hyp(wp[i][0] - lx, wp[i][1] - ly); lx = wp[i][0]; ly = wp[i][1];
        if (dist > 60) break;
        if (wp[i][3] > 15) curveLimit = Math.min(curveLimit, curveCap(wp[i][3], dist, lenF));
      }
      target = Math.min(target, curveLimit);
      if (Math.abs(diff) > 50) target = Math.min(target, 16); else if (Math.abs(diff) > 30) target = Math.min(target, 28);
      if (dev > 6) target = Math.min(target, 15); else if (dev > 3.5) target = Math.min(target, 28);
      // ---- volante ----
      const steer = diff / (inCurve ? ((curveSoon || wp[0][3] > 60) ? 12 : 18) : 25);
      steerOut = steerOut + (clamp(steer, -1, 1) - steerOut) * (inCurve ? 0.8 : 0.5);
      steerCmd = steerOut;
      // ---- pedales (pedalsFor) ----
      const err = target - speed;
      accel = 0; brake = 0;
      if (target === 0) brake = speed > 1 ? 1 : 0;
      else if (err > 1) accel = Math.min(1, 0.3 + err / 12);
      else if (err < (inCurve ? -3 : -6)) brake = Math.min(1, (-err - (inCurve ? 3 : 6)) / 15 + 0.2);
      if (opts.trace) samples.push({ t, x, y, rz, v: speed, steer: steerOut, dev, target, inCurve: inCurve ? 1 : 0 });
    }
    // ---- fisica cinematica ----
    const maxDelta = clamp(0.9 - (v / 50), 0.2, 0.7);
    const deltaCmd = steerCmd * maxDelta;
    delta += (deltaCmd - delta) * Math.min(1, dt / STEER_LAG);
    let omega = v / WHEELBASE * Math.tan(delta);                         // rad/s (+ = izquierda)
    const omegaMax = GRIP / Math.max(v, 1);
    omega = clamp(omega, -omegaMax, omegaMax);
    rz += deg(omega * dt);
    v = Math.max(0, v + (accel * 3.5 - brake * 7 - 0.15) * dt);
    x += -Math.sin(rad(rz)) * v * dt; y += Math.cos(rad(rz)) * v * dt;
    t += dt; tickAcc += dt;
    // metricas contra la ruta COMPLETA
    step++;
    minSpeed = Math.min(minSpeed, v * 3.6);
    if (step % 5 === 0) {   // 10 Hz alcanza para las metricas
      const dFull = distToPolyline(full, x, y);
      if (dFull > maxDev) { maxDev = dFull; maxDevAt = [x, y]; }
      if (dFull > 25) { reason = 'perdido'; break; }
    }
    if (hyp(x - endPt[0], y - endPt[1]) < 4) { passedFirst = true; break; }
  }
  const finished = passedFirst;
  if (!finished && !reason) reason = 'no_llego';
  return { ok: finished && maxDev <= 3.0, finished, reason, maxDev, maxDevAt, minSpeed, time: t, samples, lastDev };
}

module.exports = { simulate, distToPolyline, CRUISE };
