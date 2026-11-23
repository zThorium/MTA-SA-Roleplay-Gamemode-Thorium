// Construye cadenas de nodos realistas alrededor de una maniobra A -> B -> C (con contexto de entrada y de salida),
// para generar la ruta y simularla como lo haria un auto de la poblacion.
const { dir, canDrive, exitCandidates } = require('./geometry');

const hyp = Math.hypot;

// el predecesor P de "node" (enlace P->node transitable) que mas sigue la direccion de entrada "wantDir"
function predecessor(net, node, wantDir, avoid) {
  let best = null, bestDot = -0.5;
  for (const p of net.links[node] || []) {
    if (avoid.has(p) || !canDrive(net, p, node)) continue;
    const [dx, dy] = dir(net.x[p], net.y[p], net.x[node], net.y[node]);
    const dot = dx * wantDir[0] + dy * wantDir[1];
    if (dot > bestDot) { bestDot = dot; best = p; }
  }
  return best;
}

function buildChain(net, A, B, C, backLen = 40, fwdLen = 45) {
  const chain = [A, B, C];
  const seen = new Set(chain);
  // hacia atras
  let acc = 0, first = A, next = B;
  while (acc < backLen && chain.length < 14) {
    const want = dir(net.x[first], net.y[first], net.x[next], net.y[next]);
    const p = predecessor(net, first, want, seen);
    if (p == null) break;
    acc += hyp(net.x[first] - net.x[p], net.y[first] - net.y[p]);
    chain.unshift(p); seen.add(p); next = first; first = p;
  }
  // hacia delante (la salida mas recta)
  acc = 0;
  let last = C, prev = B;
  while (acc < fwdLen && chain.length < 22) {
    const ex = exitCandidates(net, last, prev).filter(n => !seen.has(n));
    if (!ex.length) break;
    const n = ex[0];
    acc += hyp(net.x[n] - net.x[last], net.y[n] - net.y[last]);
    chain.push(n); seen.add(n); prev = last; last = n;
  }
  return chain;
}

// todas las maniobras (A, B, C) transitables de la red
function* allManeuvers(net) {
  for (let B = 1; B <= net.n; B++) {
    const l = net.links[B] || [];
    for (const A of l) {
      if (!canDrive(net, A, B)) continue;            // se entra por A -> B
      for (const C of exitCandidates(net, B, A)) {
        if (C === A) continue;                        // sin vueltas en U
        yield [A, B, C];
      }
    }
  }
}

module.exports = { buildChain, allManeuvers };
