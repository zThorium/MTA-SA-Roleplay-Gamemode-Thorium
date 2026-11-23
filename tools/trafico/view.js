#!/usr/bin/env bun
// Dibuja una maniobra: ruta planeada, trayectoria simulada y red alrededor.
//   bun tools/trafico/view.js A B C            (nodos de la maniobra)
//   bun tools/trafico/view.js --pos X Y        (maniobra mas cercana a una posicion, p. ej. la del juego)
//   opciones: --radius 40  --scale 10  --no-fillet  --raw (sin simulador)
const fs = require('fs');
const path = require('path');
const { loadNetwork } = require('./lib/network');
const { planChain, minRadius } = require('./lib/geometry');
const { buildChain, allManeuvers } = require('./lib/chains');
const { simulate } = require('./lib/sim');
const { renderScene } = require('./lib/render');

const args = process.argv.slice(2);
const flag = k => args.includes('--' + k);
const val = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? +args[i + 1] : d; };
const net = loadNetwork();

let A, B, C;
if (flag('pos')) {
  const i = args.indexOf('--pos'); const px = +args[i + 1], py = +args[i + 2];
  let best = null, bd = Infinity;
  for (let n = 1; n <= net.n; n++) { if ((net.links[n] || []).length < 2) continue; const d = Math.hypot(net.x[n] - px, net.y[n] - py); if (d < bd) { bd = d; best = n; } }
  const list = [...allManeuvers(net)].filter(m => m[1] === best);
  console.log(`Nodo mas cercano a (${px}, ${py}): ${best} a ${bd.toFixed(1)} m. Maniobras: ${list.map(m => m.join('>')).join('  ')}`);
  if (!list.length) process.exit(1);
  [A, B, C] = list[0];
} else {
  const nums = args.filter(a => /^\d+$/.test(a)).map(Number);
  if (nums.length < 3) { console.log('Uso: view.js A B C  |  view.js --pos X Y'); process.exit(1); }
  [A, B, C] = nums;
}
const chain = buildChain(net, A, B, C);
const { wp, info } = planChain(net, chain, { fillet: !flag('no-fillet') });
const sim = flag('raw') ? { samples: [], ok: null, maxDev: 0 } : simulate(wp, { trace: true });
const mr = minRadius(wp);
const man = info.find(m => m.node === B);
console.log(`Cadena ${chain.join(' > ')}`);
console.log(`Giro ${man.turn.toFixed(0)} grados, tramos ${man.len1.toFixed(1)} / ${man.len2.toFixed(1)} m, R usado ${man.R.toFixed(1)} m, radio minimo de la ruta ${mr.r.toFixed(1)} m`);
console.log(`Simulador: ${sim.ok === null ? '-' : sim.ok ? 'OK' : 'FALLA (' + sim.reason + ')'}  desvio max ${sim.maxDev.toFixed(1)} m  vel min ${sim.minSpeed ? sim.minSpeed.toFixed(0) : '-'} km/h`);
const cv = renderScene(net, {
  center: [net.x[B], net.y[B]], radius: val('radius', 40), scale: val('scale', 10), nodes: [A, B, C], route: wp, traj: sim.samples,
  marks: sim.maxDevAt && sim.maxDev > 3 ? [{ x: sim.maxDevAt[0], y: sim.maxDevAt[1], label: sim.maxDev.toFixed(1) + 'M' }] : [],
  title: `NODO ${B}  ${A}>${B}>${C}  GIRO ${man.turn.toFixed(0)}  RADIO ${mr.r.toFixed(1)}  ${sim.ok === null ? '' : sim.ok ? 'OK' : sim.reason}`,
});
fs.mkdirSync(path.join(__dirname, 'out', 'img'), { recursive: true });
const file = path.join(__dirname, 'out', 'img', `view_${A}_${B}_${C}${flag('no-fillet') ? '_sin_redondeo' : ''}.png`);
cv.save(file);
console.log('Imagen: ' + file);
