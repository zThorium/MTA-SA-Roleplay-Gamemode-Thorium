#!/usr/bin/env bun
// Auditoria de geometria de TODA la red vial: para cada maniobra (A -> B -> C) genera la ruta como lo hace
// rp_citizens, mide el radio minimo, simula un auto y puntua la dificultad. Escribe out/audit.json,
// out/audit.md (los peores cruces) y out/img/*.png (los 12 peores).
//   bun tools/trafico/audit.js [--top 40] [--img 12] [--no-fillet] [--bbox x0,y0,x1,y1]
const fs = require('fs');
const path = require('path');
const { loadNetwork } = require('./lib/network');
const { planChain, minRadius, TUNE } = require('./lib/geometry');
const { buildChain, allManeuvers } = require('./lib/chains');
const { simulate } = require('./lib/sim');
const { renderScene } = require('./lib/render');

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : d; };
const TOP = +opt('top', 40), IMG = +opt('img', 12);
const noFillet = args.includes('--no-fillet');
const bbox = opt('bbox', null) ? opt('bbox').split(',').map(Number) : null;

if (opt('rmin', null)) TUNE.rMin = +opt('rmin');
const OUT = path.join(__dirname, opt('out', 'out'));
fs.mkdirSync(path.join(OUT, 'img'), { recursive: true });

const net = loadNetwork();
console.log(`Red: ${net.n} nodos. Cambios del editor aplicados: ${net.overrides.nodes} nodos, ${net.overrides.links} enlaces (${net.overrides.file || 'sin respaldo'})`);

const rows = [];
let count = 0;
const t0 = Date.now();
for (const [A, B, C] of allManeuvers(net)) {
  if (bbox && (net.x[B] < bbox[0] || net.x[B] > bbox[2] || net.y[B] < bbox[1] || net.y[B] > bbox[3])) continue;
  const chain = buildChain(net, A, B, C);
  const { wp, info } = planChain(net, chain, { fillet: !noFillet });
  if (wp.length < 4) continue;
  const raw = noFillet ? { wp } : planChain(net, chain, { fillet: false });
  // ventana: puntos a menos de 35 m del nodo B
  const win = (w) => { const idx = []; w.forEach((p, i) => { if (Math.hypot(p[0] - net.x[B], p[1] - net.y[B]) < 35) idx.push(i); }); return idx.length ? [idx[0], idx[idx.length - 1]] : [0, w.length - 1]; };
  const [i0, i1] = win(wp), [r0, r1] = win(raw.wp);
  const mr = minRadius(wp, i0, i1), mr0 = minRadius(raw.wp, r0, r1);
  const sim = simulate(wp, { trace: false });
  const man = info.find(m => m.node === B) || { turn: 0, len1: 0, len2: 0, R: 0 };
  let score = 0;
  if (mr.r < 4.0) score += 100; else if (mr.r < 4.5) score += 70; else if (mr.r < 6) score += 20;
  if (!sim.ok) score += sim.reason === 'perdido' ? 90 : sim.reason === 'no_llego' ? 60 : 40 + Math.min(40, sim.maxDev * 6);
  if (Math.min(man.len1, man.len2) < 4 && man.turn >= 30) score += 15;
  rows.push({
    A, B, C, x: +net.x[B].toFixed(1), y: +net.y[B].toFixed(1), turn: +man.turn.toFixed(0),
    len1: +man.len1.toFixed(1), len2: +man.len2.toFixed(1), R: +man.R.toFixed(1),
    minR: +(isFinite(mr.r) ? mr.r : 999).toFixed(1), minR0: +(isFinite(mr0.r) ? mr0.r : 999).toFixed(1),
    sim: sim.ok ? 'ok' : (sim.reason || 'desvio'), dev: +sim.maxDev.toFixed(1), vmin: +sim.minSpeed.toFixed(0), score: Math.round(score),
  });
  count++;
}
console.log(`${count} maniobras analizadas en ${((Date.now() - t0) / 1000).toFixed(1)} s`);

fs.writeFileSync(path.join(OUT, 'audit.json'), JSON.stringify(rows));

// ---------- resumen ----------
const bad = rows.filter(r => r.score >= 40);
const critR = rows.filter(r => r.minR < 4.5);
const fails = rows.filter(r => r.sim !== 'ok');
const fixedByFillet = rows.filter(r => r.minR0 < 4.5 && r.minR >= 4.5).length;
const byNode = new Map();
for (const r of rows) {
  const g = byNode.get(r.B) || { B: r.B, x: r.x, y: r.y, n: 0, worst: r, sum: 0, bad: 0 };
  g.n++; g.sum += r.score; if (r.score >= 40) g.bad++;
  if (r.score > g.worst.score) g.worst = r;
  byNode.set(r.B, g);
}
const hot = [...byNode.values()].filter(g => g.worst.score >= 40).sort((a, b) => b.worst.score - a.worst.score || b.bad - a.bad);

let md = `# Auditoria de geometria del trafico\n\n`;
md += `Generado por \`tools/trafico/audit.js\` (${new Date().toISOString().slice(0, 16).replace('T', ' ')}). Red: ${net.n} nodos; cambios del editor: ${net.overrides.nodes} nodos, ${net.overrides.links} enlaces (${net.overrides.file || 'ninguno'}).\n\n`;
md += `| Metrica | Valor |\n|---|---|\n`;
md += `| Maniobras analizadas | ${rows.length} |\n| Con radio minimo < 4.5 m (imposible para un auto) | ${critR.length} (${(100 * critR.length / rows.length).toFixed(1)} %) |\n`;
md += `| El simulador no las completa (desvio > 3 m, se pierde o no llega) | ${fails.length} (${(100 * fails.length / rows.length).toFixed(1)} %) |\n`;
md += `| Puntuacion >= 40 (problematicas) | ${bad.length} en ${hot.length} cruces |\n| Esquinas que el redondeo llevo de < 4.5 m a >= 4.5 m | ${fixedByFillet} |\n\n`;
md += `Puntuacion: radio < 4 m +100, < 4.5 m +70, < 6 m +20; simulador: se pierde +90, no llega +60, desvio > 3 m +40..80; tramo < 4 m con giro >= 30 grados +15.\n\n`;
md += `## Los ${Math.min(TOP, hot.length)} cruces mas problematicos\n\n| # | Nodo B | Posicion | Maniobras malas / total | Peor: A -> B -> C | Giro | Tramos | R usado | Radio min | Sim | Desvio max | Puntos |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
hot.slice(0, TOP).forEach((g, i) => {
  const w = g.worst;
  md += `| ${i + 1} | ${g.B} | (${g.x}, ${g.y}) | ${g.bad} / ${g.n} | ${w.A} -> ${w.B} -> ${w.C} | ${w.turn} | ${w.len1} / ${w.len2} m | ${w.R} | ${w.minR} m | ${w.sim} | ${w.dev} m | ${w.score} |\n`;
});
md += `\nVer uno: \`bun tools/trafico/view.js A B C\` (genera out/img/view_A_B_C.png con la ruta, la trayectoria simulada y la red).\n`;
fs.writeFileSync(path.join(OUT, 'audit.md'), md);

// ---------- imagenes de los peores ----------
hot.slice(0, IMG).forEach((g, i) => {
  const w = g.worst;
  const chain = buildChain(net, w.A, w.B, w.C);
  const { wp } = planChain(net, chain, { fillet: !noFillet });
  const sim = simulate(wp, { trace: true });
  const cv = renderScene(net, {
    center: [net.x[w.B], net.y[w.B]], radius: 40, scale: 10, nodes: [w.A, w.B, w.C], route: wp, traj: sim.samples,
    marks: sim.maxDevAt && sim.maxDev > 3 ? [{ x: sim.maxDevAt[0], y: sim.maxDevAt[1], label: sim.maxDev.toFixed(1) + 'M' }] : [],
    title: `${i + 1} NODO ${w.B}  ${w.A}>${w.B}>${w.C}  GIRO ${w.turn}  RADIO ${w.minR}  ${w.sim}`,
  });
  cv.save(path.join(OUT, 'img', `hot_${String(i + 1).padStart(2, '0')}_${w.A}_${w.B}_${w.C}.png`));
});
console.log(`Resumen: out/audit.md  (${hot.length} cruces problematicos; imagenes de los ${Math.min(IMG, hot.length)} peores en out/img/)`);
console.log(`Radio < 4.5 m: ${critR.length}; el simulador falla: ${fails.length}; redondeo de esquinas arreglo: ${fixedByFillet}`);
