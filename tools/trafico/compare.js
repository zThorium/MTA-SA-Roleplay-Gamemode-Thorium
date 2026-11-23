#!/usr/bin/env bun
// Compara las pruebas del juego (/trafico_test) con el simulador offline para calibrarlo:
// cuantas maniobras coinciden (OK/FALLA), desvio maximo del juego frente al simulador y los desacuerdos.
//   bun tools/trafico/compare.js [--file telemetry.jsonl]
const fs = require('fs');
const path = require('path');
const { loadNetwork } = require('./lib/network');
const { planChain } = require('./lib/geometry');
const { buildChain } = require('./lib/chains');
const { simulate, distToPolyline } = require('./lib/sim');

const args = process.argv.slice(2);
const i = args.indexOf('--file');
const TEL_DIR = path.join(__dirname, '..', '..', 'resources', '[roleplay]', 'rp_citizens', 'telemetry');
let file = i >= 0 ? args[i + 1] : null;
if (!file && fs.existsSync(TEL_DIR)) { const l = fs.readdirSync(TEL_DIR).filter(x => x.endsWith('.jsonl')).sort(); if (l.length) file = path.join(TEL_DIR, l[l.length - 1]); }
if (!file || !fs.existsSync(file)) { console.log('No hay telemetria. Corre /trafico_test en el juego (admin) primero.'); process.exit(0); }

const net = loadNetwork();
const tests = [];
for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
  if (!line.trim()) continue;
  try { const ev = JSON.parse(line); let d = ev.d; if (Array.isArray(d)) d = d[0]; if (d && d.k === 'test') tests.push(d); } catch (e) { /* */ }
}
if (!tests.length) { console.log('El archivo no tiene pruebas (k="test").'); process.exit(0); }

let agree = 0, both = { ok: 0, fail: 0 }, gameFailSimOk = [], gameOkSimFail = [];
const rows = [];
for (const t of tests) {
  const chain = buildChain(net, t.A, t.B, t.C);
  const { wp } = planChain(net, chain);
  const sim = simulate(wp);
  // desviacion REAL: distancia de la trayectoria del juego a la ruta que planea el port JS
  // (independiente del "dev" que calcula el controlador dentro del juego)
  let devTrue = 0;
  for (const p of (t.traj || [])) devTrue = Math.max(devTrue, distToPolyline(wp, p[0], p[1]));
  const simOk = sim.ok, gameOk = !!t.ok;
  if (simOk === gameOk) { agree++; gameOk ? both.ok++ : both.fail++; }
  else if (gameOk) gameOkSimFail.push(t); else gameFailSimOk.push(t);
  rows.push({ m: `${t.A}>${t.B}>${t.C}`, game: gameOk ? 'OK' : t.why, sim: simOk ? 'OK' : sim.reason || 'desvio', devGame: t.maxDev, devTrue: +devTrue.toFixed(1), devSim: +sim.maxDev.toFixed(1), vB: t.vB });
}
console.log(`Pruebas: ${tests.length}. Coinciden simulador y juego: ${agree} (${(100 * agree / tests.length).toFixed(0)} %).`);
console.log(`  ambos OK: ${both.ok}, ambos fallan: ${both.fail}`);
console.log(`  el juego FALLA y el simulador no lo ve: ${gameFailSimOk.length}  (el simulador es demasiado optimista: falta fisica/obstaculos/semaforos)`);
console.log(`  el juego OK y el simulador falla: ${gameOkSimFail.length}  (el simulador es demasiado estricto o las ayudas del juego compensan)`);
console.log('\nmaniobra        juego            simulador   desvio: controlador / real vs ruta / simulador   vel en B');
for (const r of rows) console.log(r.m.padEnd(16) + String(r.game).padEnd(17) + String(r.sim).padEnd(12) + `${r.devGame} / ${r.devTrue} / ${r.devSim} m`.padEnd(30) + r.vB);
