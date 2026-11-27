// Carga la red vial de GTA SA, todo el mapa (c_nodes_veh.lua) y le aplica los cambios del editor /nodos
// (ultimo respaldo resources/[roleplay]/rp_citizens/backups/paths_*.txt, que es una copia de path_nodes/path_links).
// Todos los indices son de Lua (base 1); los arreglos JS tienen una posicion 0 vacia para no mezclarlos.
const fs = require('fs');
const path = require('path');

const RES = path.join(__dirname, '..', '..', '..', 'resources', '[roleplay]', 'rp_citizens');

function luaTable(src, name) {
  // la tabla puede ocupar varias lineas: se recorre hasta la llave que la cierra
  const start = src.indexOf('\n' + name + ' = {');
  if (start < 0) throw new Error('tabla no encontrada: ' + name);
  const open = src.indexOf('{', start);
  let depth = 0, i = open;
  for (; i < src.length; i++) { const c = src[i]; if (c === "{") depth++; else if (c === "}") { depth--; if (depth === 0) break; } }
  const text = src.slice(open, i + 1);
  // Lua admite comas finales ({1,2,}) y JSON no: se quitan
  return JSON.parse(text.split('{').join('[').split('}').join(']').replace(/,\s*\]/g, ']'));
}

function loadNetwork(opts = {}) {
  const src = '\n' + fs.readFileSync(path.join(RES, 'c_nodes_veh.lua'), 'utf8').split('\r\n').join('\n');
  const flat = luaTable(src, 'VEH_NODES');
  const net = {
    n: flat.length / 3,
    x: [0], y: [0], z: [0],
    links: [null], lanes: [null], offset: [null], light: [null],
    overrides: { nodes: 0, links: 0, file: null },
  };
  for (let i = 0; i < net.n; i++) { net.x.push(flat[i * 3]); net.y.push(flat[i * 3 + 1]); net.z.push(flat[i * 3 + 2]); }
  const L = luaTable(src, 'VEH_LINKS'), LN = luaTable(src, 'VEH_LANES'), OF = luaTable(src, 'VEH_OFFSET');
  let LT = null; try { LT = luaTable(src, 'VEH_LIGHT'); } catch (e) { /* sin semaforos */ }
  for (let i = 0; i < net.n; i++) {
    net.links.push(L[i] || []); net.lanes.push(LN[i] || []); net.offset.push(OF[i] || []); net.light.push(LT ? (LT[i] || []) : []);
  }
  if (opts.overrides !== false) applyOverrides(net);
  return net;
}

function applyOverrides(net) {
  const dir = path.join(RES, 'backups');
  if (!fs.existsSync(dir)) return;
  const files = fs.readdirSync(dir).filter(f => /^paths_.*\.txt$/.test(f)).sort();
  if (!files.length) return;
  const file = files[files.length - 1];
  net.overrides.file = file;
  const lines = fs.readFileSync(path.join(dir, file), 'utf8').split(/\r?\n/);
  const hasLink = (a, b) => (net.links[a] || []).includes(b);
  const addLink = (a, b) => {
    for (const [f, t] of [[a, b], [b, a]]) {
      net.links[f] = net.links[f] || []; net.lanes[f] = net.lanes[f] || []; net.offset[f] = net.offset[f] || []; net.light[f] = net.light[f] || [];
      if (!hasLink(f, t)) { net.links[f].push(t); net.lanes[f].push(1); net.offset[f].push(2.5); net.light[f].push(0); }
    }
  };
  const removeLink = (a, b) => {
    for (const [f, t] of [[a, b], [b, a]]) {
      const l = net.links[f]; if (!l) continue;
      for (let k = l.length - 1; k >= 0; k--) if (l[k] === t) { l.splice(k, 1); net.lanes[f].splice(k, 1); net.offset[f].splice(k, 1); net.light[f].splice(k, 1); }
    }
  };
  for (const line of lines) {
    const p = line.trim().split(/\s+/);
    if (p[0] === 'N' && p[1] === 'v') {
      const i = +p[2], x = +p[3], y = +p[4], z = +p[5], del = +p[6];
      while (net.n < i) { net.n++; net.x.push(0); net.y.push(0); net.z.push(-1000); net.links.push([]); net.lanes.push([]); net.offset.push([]); net.light.push([]); }
      if (del === 1) { for (const n of [...(net.links[i] || [])]) removeLink(i, n); net.links[i] = []; }
      else { net.x[i] = x; net.y[i] = y; net.z[i] = z; }
      net.overrides.nodes++;
    } else if (p[0] === 'L' && p[1] === 'v') {
      const a = +p[2], b = +p[3], removed = +p[4];
      if (removed) removeLink(a, b); else addLink(a, b);
      net.overrides.links++;
    }
  }
}

module.exports = { loadNetwork };
