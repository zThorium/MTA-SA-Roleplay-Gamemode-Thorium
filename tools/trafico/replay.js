#!/usr/bin/env bun
// Lee la telemetria del juego (telemetry/*.jsonl de rp_citizens, o el collector.jsonl) y dibuja lo que paso.
//   bun tools/trafico/replay.js                       resumen y lista de eventos
//   bun tools/trafico/replay.js --render last         imagen del ultimo fallo (tel)
//   bun tools/trafico/replay.js --render all          una imagen por cada fallo y cada prueba
//   bun tools/trafico/replay.js --render 3            el evento numero 3 de la lista
//   opciones: --file ruta.jsonl   --radius 30
// Los fallos (k="tel") se dibujan con la ruta que tenia el auto (amarillo) y su trayectoria real de los ultimos ~2 s
// (por velocidad). Las pruebas (k="test") con la trayectoria del juego (gruesa) y la del simulador (fina blanca).
const fs = require('fs');
const path = require('path');
const { loadNetwork } = require('./lib/network');
const { planChain } = require('./lib/geometry');
const { buildChain } = require('./lib/chains');
const { simulate } = require('./lib/sim');
const { renderScene } = require('./lib/render');

const args = process.argv.slice(2);
const val = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : d; };
const TEL_DIR = path.join(__dirname, '..', '..', 'resources', '[roleplay]', 'rp_citizens', 'telemetry');

function findFile() {
  const f = val('file', null);
  if (f) return f;
  if (fs.existsSync(TEL_DIR)) {
    const l = fs.readdirSync(TEL_DIR).filter(x => x.endsWith('.jsonl')).sort();
    if (l.length) return path.join(TEL_DIR, l[l.length - 1]);
  }
  const c = path.join(__dirname, 'out', 'collector.jsonl');
  return fs.existsSync(c) ? c : null;
}

function load(file) {
  const out = [];
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    try { const ev = JSON.parse(line); let d = ev.d; if (Array.isArray(d)) d = d[0]; if (d) out.push({ ts: ev.ts, d }); } catch (e) { /* linea cortada */ }
  }
  return out;
}

const file = findFile();
if (!file) { console.log('No hay telemetria todavia. Juega con /trafico_tel send activado (admin) o usa /trafico_test.'); process.exit(0); }
const events = load(file);
console.log(`Archivo: ${file}  (${events.length} eventos)`);
events.forEach((e, i) => {
  const d = e.d, t = new Date(e.ts * 1000).toTimeString().slice(0, 8);
  if (d.k === 'tel') console.log(`#${i + 1} ${t} FALLO ${d.why} modelo ${d.model}${d.bike ? ' (moto)' : ''} nodos ${d.prev}->${d.node} pos (${d.x}, ${d.y})`);
  else if (d.k === 'test') console.log(`#${i + 1} ${t} PRUEBA ${d.A}>${d.B}>${d.C} ${d.ok ? 'OK' : 'FALLA ' + d.why} desvio ${d.maxDev} m vel en B ${d.vB} km/h`);
});

const what = val('render', null);
if (!what) { console.log('\nPara dibujar: --render last | all | N'); process.exit(0); }
const net = loadNetwork();
fs.mkdirSync(path.join(__dirname, 'out', 'img'), { recursive: true });
const R = +val('radius', 30);

function renderTel(i, d) {
  const route = (d.route || []).map(p => [p[0], p[1], 0, p[2], null]);
  const traj = (d.samples || []).filter(s => s[10] || s[11]).map(s => ({ x: s[10], y: s[11], v: s[1] }));
  const last = traj[traj.length - 1] || { x: d.x, y: d.y };
  const cv = renderScene(net, {
    center: [last.x, last.y], radius: R, scale: 12, nodes: [d.prev, d.node].filter(Boolean), route, traj,
    marks: [{ x: last.x, y: last.y, label: 'DEV ' + (d.samples && d.samples.length ? d.samples[d.samples.length - 1][3] : '?') }],
    title: `FALLO ${d.why} ${d.prev}>${d.node} MODELO ${d.model}`,
  });
  const f = path.join(__dirname, 'out', 'img', `replay_${String(i + 1).padStart(3, '0')}_tel_${d.node}.png`);
  cv.save(f); console.log('Imagen: ' + f);
}

function renderTest(i, d) {
  const chain = buildChain(net, d.A, d.B, d.C);
  const { wp } = planChain(net, chain);
  const sim = simulate(wp, { trace: true });
  const traj = (d.traj || []).map(p => ({ x: p[0], y: p[1], v: p[2] }));
  const cv = renderScene(net, {
    center: [net.x[d.B], net.y[d.B]], radius: R + 10, scale: 10, nodes: [d.A, d.B, d.C], route: wp, traj, traj2: sim.samples,
    title: `PRUEBA ${d.A}>${d.B}>${d.C} JUEGO ${d.ok ? 'OK' : d.why}  SIM ${sim.ok ? 'OK' : sim.reason || 'DESVIO'}`,
  });
  const f = path.join(__dirname, 'out', 'img', `replay_${String(i + 1).padStart(3, '0')}_test_${d.A}_${d.B}_${d.C}.png`);
  cv.save(f); console.log('Imagen: ' + f);
}

const pick = [];
if (what === 'last') { for (let i = events.length - 1; i >= 0; i--) if (events[i].d.k === 'tel' || events[i].d.k === 'test') { pick.push(i); break; } }
else if (what === 'all') events.forEach((e, i) => { if (e.d.k === 'tel' || e.d.k === 'test') pick.push(i); });
else if (/^\d+$/.test(what)) pick.push(+what - 1);
for (const i of pick) { const d = events[i] && events[i].d; if (!d) continue; if (d.k === 'tel') renderTel(i, d); else if (d.k === 'test') renderTest(i, d); }
