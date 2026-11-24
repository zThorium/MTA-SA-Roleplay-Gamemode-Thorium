#!/usr/bin/env bun
// Colector OPCIONAL de telemetria: recibe por HTTP lo que s_telemetry.lua reenvia (setting collector_url del
// meta.xml de rp_citizens, p. ej. http://127.0.0.1:22100/tel), lo guarda en out/collector.jsonl y mantiene
// estadisticas en memoria que se consultan con curl mientras juegas:
//   curl http://127.0.0.1:22100/stats      resumen (eventos, fallos por motivo, cruces con mas fallos)
//   curl http://127.0.0.1:22100/recent?n=5 ultimos eventos
//   curl http://127.0.0.1:22100/hot        nodos con mas fallos (para renderizarlos con view.js)
// Escucha solo en 127.0.0.1. Uso:  bun tools/trafico/collector.js [puerto=22100]
const fs = require('fs');
const path = require('path');
const http = require('http');

const PORT = +(process.argv[2] || 22100);
const OUT = path.join(__dirname, 'out');
fs.mkdirSync(OUT, { recursive: true });
const file = path.join(OUT, 'collector.jsonl');

const events = [];
const byWhy = {}, byNode = {};
let total = 0;

function ingest(line) {
  let ev; try { ev = JSON.parse(line); } catch (e) { return; }
  let d = ev.d; if (Array.isArray(d)) d = d[0];
  if (!d) return;
  total++;
  events.push({ ts: ev.ts, d });
  if (events.length > 500) events.shift();
  const why = d.k === 'test' ? ('test_' + (d.ok ? 'ok' : (d.why || 'falla'))) : (d.why || d.k);
  byWhy[why] = (byWhy[why] || 0) + 1;
  const node = d.k === 'test' ? d.B : d.node;
  if (node && (d.k === 'tel' || (d.k === 'test' && !d.ok))) byNode[node] = (byNode[node] || 0) + 1;
}

// reconstruye las estadisticas con lo ya guardado
if (fs.existsSync(file)) for (const l of fs.readFileSync(file, 'utf8').split('\n')) if (l.trim()) ingest(l);

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  const send = (obj, code = 200) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj, null, 1)); };
  if (req.method === 'POST') {
    let body = '';
    req.on('data', c => { body += c; if (body.length > 65536) req.destroy(); });
    req.on('end', () => { fs.appendFileSync(file, body.trim() + '\n'); ingest(body.trim()); send({ ok: true }); });
    return;
  }
  if (url.pathname === '/stats') return send({ total, porMotivo: byWhy, nodosConMasFallos: Object.entries(byNode).sort((a, b) => b[1] - a[1]).slice(0, 15) });
  if (url.pathname === '/hot') return send(Object.entries(byNode).sort((a, b) => b[1] - a[1]).slice(0, 30).map(([node, n]) => ({ node: +node, fallos: n })));
  if (url.pathname === '/recent') { const n = +(url.searchParams.get('n') || 5); return send(events.slice(-n)); }
  send({ rutas: ['POST /tel', 'GET /stats', 'GET /hot', 'GET /recent?n=5'] });
}).listen(PORT, '127.0.0.1', () => console.log(`Colector en http://127.0.0.1:${PORT}  (guarda en ${file})`));
