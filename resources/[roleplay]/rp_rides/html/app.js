/*
    rp_rides / app.js
    App Vroom: mapa (canvas) con pan/zoom, seleccion de destino, animacion de
    busqueda de conductores y de la busqueda A* de la ruta, y las pantallas de
    pasajero, conductor y calificacion. Lua llama a window.RP.*.
*/
(function () {
    'use strict';

    // Debe coincidir con s_config.lua
    var CFG = { BASE_FARE: 25, PER_KM: 18, ROUTE_FACTOR: 1.3, MIN_FARE: 25, MAX_FARE: 900, MAX_TIP: 500,
        MIN_X: -100, MAX_X: 3000, MIN_Y: -2900, MAX_Y: -600 };
    var MAP_IMG = 'http://mta/rp_hud/images/map.png';
    var MAP_PX = 1536;             // el radar cubre -3000..3000 en 1536 px
    var TIPS = [0, 10, 25, 50, 100];

    var $ = function (id) { return document.getElementById(id); };
    var canvas = $('map'), ctx = canvas.getContext('2d');
    var sheet = $('sheet'), label = $('map-label');

    function send(name) {
        var args = Array.prototype.slice.call(arguments, 1).map(function (a) { return String(a); });
        if (window.mta && mta.triggerEvent) mta.triggerEvent.apply(mta, ['rp:rides:ui:' + name].concat(args));
        else console.log('[vroom] ' + name, args);
    }
    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function money(n) { return '$' + Math.round(n || 0).toLocaleString('es-CL'); }
    function dist(ax, ay, bx, by) { return Math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by)); }
    function km(m) { return m >= 1000 ? (m / 1000).toFixed(1) + ' km' : Math.round(m) + ' m'; }
    function fare(x1, y1, x2, y2) {
        var f = Math.floor(CFG.BASE_FARE + dist(x1, y1, x2, y2) * CFG.ROUTE_FACTOR / 1000 * CFG.PER_KM + 0.5);
        return Math.max(CFG.MIN_FARE, Math.min(CFG.MAX_FARE, f));
    }
    function inMap(x, y) { return x >= CFG.MIN_X && x <= CFG.MAX_X && y >= CFG.MIN_Y && y <= CFG.MAX_Y; }
    function now() { return performance.now(); }

    // ------------------------------------------------------------
    // Estado
    // ------------------------------------------------------------
    var S = { ride: false, driver: {}, driving: false, rate: false, money: 0 };
    var ui = {
        tab: 'ride', interactive: true, pick: false, dest: null,
        stars: 5, tip: 0, customTip: '', offers: {}, searchId: null, searchStart: 0, lastKey: ''
    };
    var me = { x: 1480, y: -1700, rot: 0, sx: null, sy: null, has: false };
    var car = null;                 // { x, y, remaining, mode, sx, sy, heading }

    // ------------------------------------------------------------
    // Grafo vial (indices de Lua, base 1)
    // ------------------------------------------------------------
    var G = null;
    function at(container, i) {
        if (!container) return null;
        if (Array.isArray(container)) return container[i - 1];
        return container[i] || container[String(i)] || null;
    }
    function nx(i) { return G.nodes[(i - 1) * 3]; }
    function ny(i) { return G.nodes[(i - 1) * 3 + 1]; }
    function linksOf(i) { var l = at(G.links, i); return Array.isArray(l) ? l : (l ? Object.keys(l).map(function (k) { return l[k]; }) : []); }
    function laneOf(a, k) { var l = at(G.lanes, a); var v = l ? (Array.isArray(l) ? l[k] : l[k + 1]) : null; return v == null ? 1 : v; }

    function nearestNode(x, y, maxD) {
        if (!G) return null;
        var best = null, bd = (maxD || 1e9) * (maxD || 1e9);
        for (var i = 1; i <= G.count; i++) {
            if (!linksOf(i).length) continue;
            var dx = nx(i) - x, dy = ny(i) - y, d = dx * dx + dy * dy;
            if (d < bd) { bd = d; best = i; }
        }
        return best;
    }

    // A* con registro del orden de expansion (para la animacion)
    function astarTrace(start, goal) {
        var order = [], cost = {}, parent = {}, closed = {};
        var heap = [];
        function push(n, f) {
            heap.push([n, f]); var i = heap.length - 1;
            while (i > 0) { var p = (i - 1) >> 1; if (heap[p][1] <= heap[i][1]) break; var t = heap[p]; heap[p] = heap[i]; heap[i] = t; i = p; }
        }
        function pop() {
            var top = heap[0], last = heap.pop();
            if (heap.length) {
                heap[0] = last; var i = 0;
                for (;;) {
                    var l = i * 2 + 1, r = l + 1, m = i;
                    if (l < heap.length && heap[l][1] < heap[m][1]) m = l;
                    if (r < heap.length && heap[r][1] < heap[m][1]) m = r;
                    if (m === i) break; var t = heap[m]; heap[m] = heap[i]; heap[i] = t; i = m;
                }
            }
            return top[0];
        }
        var gx = nx(goal), gy = ny(goal);
        cost[start] = 0; push(start, 0);
        while (heap.length && order.length < 6000) {
            var cur = pop();
            if (closed[cur]) continue;
            closed[cur] = true;
            order.push(cur);
            if (cur === goal) break;
            var cx = nx(cur), cy = ny(cur), ls = linksOf(cur);
            for (var k = 0; k < ls.length; k++) {
                var n = ls[k];
                if (closed[n] || laneOf(cur, k) <= 0) continue;
                var g = cost[cur] + dist(cx, cy, nx(n), ny(n));
                if (cost[n] == null || g < cost[n]) { cost[n] = g; parent[n] = cur; push(n, g + dist(nx(n), ny(n), gx, gy)); }
            }
        }
        return { order: order, parent: parent };
    }

    // ------------------------------------------------------------
    // Mapa
    // ------------------------------------------------------------
    var mapImg = new Image(), mapReady = false, roadLayer = null;
    mapImg.onload = function () { mapReady = true; };
    mapImg.onerror = function () { mapReady = false; buildRoadLayer(); };
    mapImg.src = MAP_IMG;

    var view = { cx: toMap(1480, -1700)[0], cy: toMap(1480, -1700)[1], z: 1.2, follow: true, fit: null };
    var W = 0, H = 0, DPR = 1;

    function toMap(x, y) { return [(x + 3000) / 6000 * MAP_PX, (3000 - y) / 6000 * MAP_PX]; }
    function fromMap(mx, my) { return [mx / MAP_PX * 6000 - 3000, 3000 - my / MAP_PX * 6000]; }
    function toScreen(x, y) { var m = toMap(x, y); return [(m[0] - view.cx) * view.z + W / 2, (m[1] - view.cy) * view.z + H / 2]; }
    function fromScreen(sx, sy) { return fromMap((sx - W / 2) / view.z + view.cx, (sy - H / 2) / view.z + view.cy); }

    // Si no hay imagen del mapa se dibuja la red vial como fondo
    function buildRoadLayer() {
        if (!G || roadLayer) return;
        var size = 2048, k = size / MAP_PX;
        var c = document.createElement('canvas'); c.width = c.height = size;
        var g = c.getContext('2d');
        g.fillStyle = '#0c1820'; g.fillRect(0, 0, size, size);
        g.strokeStyle = '#2b3a46'; g.lineWidth = 1.6; g.lineCap = 'round';
        g.beginPath();
        for (var i = 1; i <= G.count; i++) {
            var a = toMap(nx(i), ny(i)), ls = linksOf(i);
            for (var j = 0; j < ls.length; j++) {
                if (ls[j] < i && laneOf(i, j) > 0) continue;   // cada tramo una vez
                var b = toMap(nx(ls[j]), ny(ls[j]));
                g.moveTo(a[0] * k, a[1] * k); g.lineTo(b[0] * k, b[1] * k);
            }
        }
        g.stroke();
        roadLayer = { canvas: c, k: k };
    }

    function resize() {
        DPR = window.devicePixelRatio || 1;
        var w = canvas.clientWidth, h = canvas.clientHeight;
        if (w !== W || h !== H || canvas.width !== Math.round(w * DPR)) {
            W = w; H = h; canvas.width = Math.round(w * DPR); canvas.height = Math.round(h * DPR);
        }
    }

    // ------------------------------------------------------------
    // Ruta y animacion A*
    // ------------------------------------------------------------
    var route = null;   // { pts: [[x,y]...], length, kind, explore: {...}|null, t0, revealMs }

    function setRoute(nodes, animate, kind) {
        if (!nodes || nodes.length < 2 || !G) { route = null; return; }
        var pts = nodes.map(function (i) { return [nx(i), ny(i)]; });
        var len = 0;
        for (var i = 1; i < pts.length; i++) len += dist(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1]);
        var explore = null;
        if (animate) {
            var tr = astarTrace(nodes[0], nodes[nodes.length - 1]);
            explore = { order: tr.order, parent: tr.parent, ms: Math.max(1100, Math.min(3000, tr.order.length * 2.2)) };
        }
        route = { pts: pts, length: len, kind: kind || 'ride', explore: explore, t0: now(), revealMs: animate ? 900 : 0 };
        view.follow = true;
        if (animate) {
            // Encuadra todo el recorrido (y lo explorado) mientras dura la animacion
            var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
            pts.forEach(function (p) { var m = toMap(p[0], p[1]); x0 = Math.min(x0, m[0]); y0 = Math.min(y0, m[1]); x1 = Math.max(x1, m[0]); y1 = Math.max(y1, m[1]); });
            var z = Math.min((W || 290) / Math.max(20, (x1 - x0) * 1.35), (H || 260) / Math.max(20, (y1 - y0) * 1.35));
            view.fit = { cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, z: Math.max(0.35, Math.min(3, z)), back: view.z,
                until: now() + explore.ms + route.revealMs + 1800 };
        }
    }

    function routeColor(kind, a) { return kind === 'pickup' ? 'rgba(245,165,36,' + a + ')' : 'rgba(47,210,122,' + a + ')'; }

    function drawRoute(t) {
        if (!route) return;
        var r = route, el = t - r.t0, ex = r.explore;
        var exploreMs = ex ? ex.ms : 0;

        // 1) Nodos explorados por A* (aparecen en orden, luego se desvanecen)
        if (ex) {
            var fade = el < exploreMs + r.revealMs ? 1 : Math.max(0, 1 - (el - exploreMs - r.revealMs) / 900);
            if (fade > 0) {
                var n = Math.min(ex.order.length, Math.floor(ex.order.length * Math.min(1, el / exploreMs)));
                ctx.lineWidth = 1.4; ctx.strokeStyle = 'rgba(90,200,255,' + (0.38 * fade) + ')';
                ctx.beginPath();
                for (var i = 1; i < n; i++) {
                    var node = ex.order[i], p = ex.parent[node];
                    if (!p) continue;
                    var a = toScreen(nx(p), ny(p)), b = toScreen(nx(node), ny(node));
                    ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
                }
                ctx.stroke();
                if (el < exploreMs) {   // frontera
                    ctx.fillStyle = 'rgba(160,235,255,0.95)';
                    for (var f = Math.max(0, n - 30); f < n; f++) {
                        var q = toScreen(nx(ex.order[f]), ny(ex.order[f]));
                        ctx.beginPath(); ctx.arc(q[0], q[1], 1.2 + (f - n + 30) / 14, 0, Math.PI * 2); ctx.fill();
                    }
                }
                if (el < exploreMs + r.revealMs) {
                    label.className = 'map-label show';
                    label.textContent = el < exploreMs
                        ? 'Calculando ruta optima (A*) · ' + n + ' nodos explorados'
                        : 'Ruta encontrada · ' + km(r.length) + ' · ' + ex.order.length + ' nodos explorados';
                }
            }
        }

        // 2) La ruta se revela de A a B
        if (el < exploreMs) return;
        var prog = r.revealMs ? Math.min(1, (el - exploreMs) / r.revealMs) : 1;
        var target = r.length * prog, acc = 0;
        var screen = [toScreen(r.pts[0][0], r.pts[0][1])];
        for (var k = 1; k < r.pts.length && acc < target; k++) {
            var p0 = r.pts[k - 1], p1 = r.pts[k], d = dist(p0[0], p0[1], p1[0], p1[1]);
            if (acc + d > target) {
                var u = (target - acc) / d;
                screen.push(toScreen(p0[0] + (p1[0] - p0[0]) * u, p0[1] + (p1[1] - p0[1]) * u));
            } else screen.push(toScreen(p1[0], p1[1]));
            acc += d;
        }
        ctx.lineJoin = ctx.lineCap = 'round';
        [[9, routeColor(r.kind, 0.22)], [4, routeColor(r.kind, 1)]].forEach(function (s) {
            ctx.lineWidth = s[0]; ctx.strokeStyle = s[1]; ctx.beginPath();
            screen.forEach(function (p, i) { if (i) ctx.lineTo(p[0], p[1]); else ctx.moveTo(p[0], p[1]); });
            ctx.stroke();
        });
        // brillo que recorre la ruta terminada
        if (prog >= 1 && screen.length > 1) {
            var cyc = ((t / 2600) % 1) * r.length, a2 = 0;
            for (var m = 1; m < r.pts.length; m++) {
                var s0 = r.pts[m - 1], s1 = r.pts[m], dd = dist(s0[0], s0[1], s1[0], s1[1]);
                if (a2 + dd >= cyc) {
                    var v = (cyc - a2) / (dd || 1), g = toScreen(s0[0] + (s1[0] - s0[0]) * v, s0[1] + (s1[1] - s0[1]) * v);
                    ctx.fillStyle = 'rgba(255,255,255,0.9)'; ctx.beginPath(); ctx.arc(g[0], g[1], 2.6, 0, Math.PI * 2); ctx.fill();
                    break;
                }
                a2 += dd;
            }
        }
    }

    // ------------------------------------------------------------
    // Marcadores
    // ------------------------------------------------------------
    function pin(x, y, color, letter, ghost) {
        var p = toScreen(x, y);
        ctx.save();
        ctx.globalAlpha = ghost ? 0.7 : 1;
        ctx.fillStyle = 'rgba(0,0,0,0.35)';
        ctx.beginPath(); ctx.ellipse(p[0], p[1] + 1, 5, 2, 0, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.moveTo(p[0], p[1]);
        ctx.bezierCurveTo(p[0] - 3, p[1] - 8, p[0] - 10, p[1] - 12, p[0] - 10, p[1] - 20);
        ctx.arc(p[0], p[1] - 20, 10, Math.PI, 0);
        ctx.bezierCurveTo(p[0] + 10, p[1] - 12, p[0] + 3, p[1] - 8, p[0], p[1]);
        ctx.fill();
        ctx.fillStyle = '#0d0f12'; ctx.font = 'bold 11px sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillText(letter, p[0], p[1] - 20);
        ctx.restore();
    }

    function drawMe() {
        if (!me.has) return;
        var p = toScreen(me.sx, me.sy), ang = -me.rot * Math.PI / 180;
        ctx.save(); ctx.translate(p[0], p[1]);
        var grd = ctx.createRadialGradient(0, 0, 0, 0, 0, 22);
        grd.addColorStop(0, 'rgba(74,168,255,0.35)'); grd.addColorStop(1, 'rgba(74,168,255,0)');
        ctx.fillStyle = grd; ctx.beginPath(); ctx.arc(0, 0, 22, 0, Math.PI * 2); ctx.fill();
        ctx.rotate(ang);
        ctx.fillStyle = 'rgba(74,168,255,0.35)';
        ctx.beginPath(); ctx.moveTo(0, 0); ctx.arc(0, 0, 18, -Math.PI / 2 - 0.45, -Math.PI / 2 + 0.45); ctx.fill();
        ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(0, 0, 6.5, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#4aa8ff'; ctx.beginPath(); ctx.arc(0, 0, 4.5, 0, Math.PI * 2); ctx.fill();
        ctx.restore();
    }

    function drawCar() {
        if (!car || car.sx == null) return;
        var p = toScreen(car.sx, car.sy);
        ctx.save(); ctx.translate(p[0], p[1]); ctx.rotate(car.heading || 0);
        ctx.fillStyle = 'rgba(0,0,0,0.4)'; roundRect(-6, -10, 13, 21, 4); ctx.fill();
        ctx.fillStyle = '#f4f6f8'; roundRect(-6.5, -11, 13, 21, 4); ctx.fill();
        ctx.fillStyle = '#15181d'; roundRect(-4.5, -6, 9, 6, 2); ctx.fill();
        ctx.fillStyle = '#2fd27a'; ctx.fillRect(-4.5, -10.5, 9, 2);
        ctx.restore();
    }
    function roundRect(x, y, w, h, r) {
        ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
        ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
    }

    // Radar mientras se buscan conductores
    function drawSearch(t, x, y) {
        var p = toScreen(x, y);
        ctx.save(); ctx.translate(p[0], p[1]);
        for (var i = 0; i < 3; i++) {
            var k = ((t / 1800) + i / 3) % 1;
            ctx.strokeStyle = 'rgba(47,210,122,' + (0.6 * (1 - k)) + ')'; ctx.lineWidth = 2;
            ctx.beginPath(); ctx.arc(0, 0, 8 + k * 70, 0, Math.PI * 2); ctx.stroke();
        }
        var a = (t / 900) % (Math.PI * 2);
        var g = ctx.createRadialGradient(0, 0, 0, 0, 0, 78);
        g.addColorStop(0, 'rgba(47,210,122,0.35)'); g.addColorStop(1, 'rgba(47,210,122,0)');
        ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(0, 0); ctx.arc(0, 0, 78, a, a + 0.7); ctx.closePath(); ctx.fill();
        ctx.restore();
    }

    // ------------------------------------------------------------
    // Bucle de dibujo
    // ------------------------------------------------------------
    function frame() {
        var t = now();
        resize();
        if (W > 0 && H > 0) {
            // Suavizado de posiciones
            if (me.has) {
                if (me.sx == null) { me.sx = me.x; me.sy = me.y; }
                me.sx += (me.x - me.sx) * 0.12; me.sy += (me.y - me.sy) * 0.12;
            }
            if (car) {
                if (car.sx == null) { car.sx = car.x; car.sy = car.y; }
                var dx = car.x - car.sx, dy = car.y - car.sy;
                if (dx * dx + dy * dy > 0.04) car.heading = Math.atan2(dx, dy);
                car.sx += dx * 0.12; car.sy += dy * 0.12;
            }
            // Encuadre de la ruta durante la animacion; despues vuelve al zoom anterior
            if (view.fit && view.follow) {
                var fit = view.fit, fz = t < fit.until ? fit.z : fit.back;
                view.z += (fz - view.z) * 0.08;
                if (t >= fit.until && Math.abs(view.z - fit.back) < 0.01) { view.z = fit.back; view.fit = null; }
            }
            if (view.fit && view.follow && t < view.fit.until) {
                view.cx += (view.fit.cx - view.cx) * 0.08; view.cy += (view.fit.cy - view.cy) * 0.08;
            } else if (view.follow) {
                var fx = me.sx, fy = me.sy;
                if (car && car.sx != null && (!S.ride || S.ride.state !== 'riding' || !me.has)) { fx = car.sx; fy = car.sy; }
                if (S.ride && S.ride.state === 'searching' && S.ride.pickup) { fx = S.ride.pickup[0]; fy = S.ride.pickup[1]; }
                if (fx != null) {
                    var m = toMap(fx, fy);
                    view.cx += (m[0] - view.cx) * 0.08; view.cy += (m[1] - view.cy) * 0.08;
                }
            }

            ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
            ctx.fillStyle = '#0a1a24'; ctx.fillRect(0, 0, W, H);
            if (mapReady) {
                ctx.setTransform(DPR * view.z, 0, 0, DPR * view.z, DPR * (W / 2 - view.cx * view.z), DPR * (H / 2 - view.cy * view.z));
                ctx.imageSmoothingEnabled = view.z < 2;
                ctx.drawImage(mapImg, 0, 0);
            } else if (roadLayer) {
                var k = roadLayer.k;
                ctx.setTransform(DPR * view.z / k, 0, 0, DPR * view.z / k, DPR * (W / 2 - view.cx * view.z), DPR * (H / 2 - view.cy * view.z));
                ctx.drawImage(roadLayer.canvas, 0, 0);
            }
            ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
            ctx.fillStyle = 'rgba(8,12,16,0.18)'; ctx.fillRect(0, 0, W, H);

            if (label.dataset.fixed !== '1') label.className = 'map-label';
            drawRoute(t);

            var ride = S.ride, drv = S.driving;
            if (ride && ride.state === 'searching' && ride.pickup) drawSearch(t, ride.pickup[0], ride.pickup[1]);
            if (ride && ride.state !== 'riding' && ride.pickup) pin(ride.pickup[0], ride.pickup[1], '#4aa8ff', 'A');
            if (drv && drv.state !== 'riding' && drv.pickup) pin(drv.pickup[0], drv.pickup[1], '#f5a524', 'A');
            var dest = (ride && ride.dest) || (drv && drv.dest) || null;
            if (dest) pin(dest[0], dest[1], '#2fd27a', 'B');
            if (ui.dest && (!dest || ui.dest[0] !== dest[0] || ui.dest[1] !== dest[1])) pin(ui.dest[0], ui.dest[1], '#2fd27a', 'B', true);
            drawCar();
            drawMe();
        }
        requestAnimationFrame(frame);
    }

    // ------------------------------------------------------------
    // Interaccion con el mapa
    // ------------------------------------------------------------
    var drag = null;
    canvas.addEventListener('mousedown', function (e) {
        if (!ui.interactive) return;
        drag = { x: e.clientX, y: e.clientY, cx: view.cx, cy: view.cy, moved: false };
    });
    window.addEventListener('mousemove', function (e) {
        if (!drag) return;
        var dx = e.clientX - drag.x, dy = e.clientY - drag.y;
        if (Math.abs(dx) + Math.abs(dy) > 4) drag.moved = true;
        if (drag.moved) { view.follow = false; view.fit = null; view.cx = drag.cx - dx / view.z; view.cy = drag.cy - dy / view.z; }
    });
    window.addEventListener('mouseup', function (e) {
        if (!drag) return;
        var d = drag; drag = null;
        if (d.moved) return;
        var r = canvas.getBoundingClientRect();
        mapClick(e.clientX - r.left, e.clientY - r.top);
    });
    canvas.addEventListener('wheel', function (e) {
        if (!ui.interactive) return;
        e.preventDefault();
        var r = canvas.getBoundingClientRect();
        zoomAt(e.deltaY < 0 ? 1.25 : 0.8, e.clientX - r.left, e.clientY - r.top);
    }, { passive: false });

    function zoomAt(f, sx, sy) {
        var before = fromScreen(sx, sy);
        view.fit = null;
        view.z = Math.max(0.35, Math.min(6, view.z * f));
        if (!view.follow) {
            var m = toMap(before[0], before[1]);
            view.cx = m[0] - (sx - W / 2) / view.z; view.cy = m[1] - (sy - H / 2) / view.z;
        }
    }
    $('zoom-in').onclick = function () { zoomAt(1.4, W / 2, H / 2); };
    $('zoom-out').onclick = function () { zoomAt(1 / 1.4, W / 2, H / 2); };
    $('recenter').onclick = function () { view.follow = true; };

    function canPickDest() {
        if (ui.tab !== 'ride' || S.rate) return false;
        var r = S.ride;
        return !r || ui.pick || !r.dest;
    }

    function mapClick(sx, sy) {
        if (!canPickDest()) return;
        var w = fromScreen(sx, sy);
        if (!inMap(w[0], w[1])) return flash('Vroom solo opera dentro de Los Santos.');
        var n = nearestNode(w[0], w[1], 60);   // se ajusta a la calle mas cercana
        if (n) w = [nx(n), ny(n)];
        if (me.has && dist(me.x, me.y, w[0], w[1]) < 60) return flash('Ese destino esta demasiado cerca.');
        ui.dest = [Math.round(w[0] * 10) / 10, Math.round(w[1] * 10) / 10];
        render(true);
    }

    var flashTimer = null;
    function flash(text) {
        label.textContent = text; label.className = 'map-label show'; label.dataset.fixed = '1';
        clearTimeout(flashTimer);
        flashTimer = setTimeout(function () { label.dataset.fixed = ''; }, 2200);
    }

    // ------------------------------------------------------------
    // Pantallas
    // ------------------------------------------------------------
    function stars(r) {
        var full = Math.round(r || 0), s = '';
        for (var i = 1; i <= 5; i++) s += i <= full ? '★' : '☆';
        return s;
    }
    function driverCard(d) {
        if (!d) return '';
        var rating = d.isNew ? 'Nuevo' : '<span class="stars-inline">★</span> ' + Number(d.rating || 0).toFixed(1);
        return '<div class="card"><div class="avatar' + (d.ai ? ' ai' : '') + '">' + esc((d.name || '?').charAt(0)) + '</div>' +
            '<div style="flex:1"><b>' + esc(d.name) + (d.ai ? ' <span class="tag">IA</span>' : '') + '</b>' +
            '<small>' + rating + ' · ' + esc(d.vehicle || '') + '</small></div>' +
            (d.plate ? '<div class="tag" style="color:var(--text);background:var(--surface);padding:5px 8px;border-radius:8px">' + esc(d.plate) + '</div>' : '') +
            '</div>';
    }
    function places(a, b) {
        return '<div class="place"><div><i class="a"></i>' + (a ? 'Punto de recogida' : 'Tu ubicacion') + '</div>' +
            '<div><i class="b"></i>' + (b ? 'Destino marcado · ' + km(dist(a ? a[0] : me.x, a ? a[1] : me.y, b[0], b[1])) : '<span class="muted">Destino sin elegir</span>') + '</div></div>';
    }
    function remainingTo(x, y) {
        if (car && car.remaining) return car.remaining;
        return me.has ? dist(me.x, me.y, x, y) : 0;
    }

    function ridePassenger() {
        var r = S.ride;
        if (S.rate) return rateScreen();

        if (!r) {
            var h = '<h2>¿A donde vamos?</h2>';
            if (ui.dest) {
                var f = me.has ? fare(me.x, me.y, ui.dest[0], ui.dest[1]) : 0;
                h += places(null, ui.dest) +
                    '<div class="row between"><span class="muted">Tarifa estimada<br>Se cobra del banco al llegar</span><span class="price">' + money(f) + '</span></div>' +
                    '<button class="btn primary" data-act="request">Pedir Vroom</button>' +
                    '<button class="btn ghost" data-act="clearDest">Quitar destino</button>';
            } else {
                h += '<p class="muted">Toca el mapa para marcar tu destino, o pide el viaje y eligelo cuando subas.</p>' +
                    '<button class="btn primary" data-act="request">Pedir sin destino</button>';
            }
            return h;
        }

        if (r.state === 'searching') {
            return '<span class="tag">Buscando conductores</span>' +
                '<div class="row between"><h2>Buscando tu Vroom</h2><div class="dots"><span></span><span></span><span></span></div></div>' +
                '<div class="progress"><i id="search-bar"></i></div>' +
                '<p class="muted">Avisamos a los conductores cercanos. Los mejor calificados ven tu pedido primero. Si nadie lo toma, te enviamos un conductor de Vroom.</p>' +
                places(r.pickup, r.dest) +
                '<button class="btn danger" data-act="cancel">Cancelar</button>';
        }
        if (r.state === 'ai_spawning') {
            return '<span class="tag">Asignando</span><div class="row between"><h2>Te asignamos un conductor</h2><div class="dots"><span></span><span></span><span></span></div></div>' +
                '<p class="muted">No habia conductores libres: un auto Vroom va camino a buscarte.</p>' +
                '<button class="btn danger" data-act="cancel">Cancelar</button>';
        }
        if (r.state === 'assigned') {
            var rem = r.pickup ? remainingTo(r.pickup[0], r.pickup[1]) : 0;
            return '<span class="tag warn">En camino</span><div class="row between"><h2>Tu conductor va a buscarte</h2><span class="price" id="live-rem">' + km(rem) + '</span></div>' +
                driverCard(r.driver) + places(r.pickup, r.dest) +
                '<button class="btn danger" data-act="cancel">Cancelar viaje</button>';
        }
        if (r.state === 'arrived') {
            return '<span class="tag">Llego tu conductor</span><h2>Subete al auto</h2>' + driverCard(r.driver) +
                '<p class="muted">Sube a un asiento de pasajero (G). Te espera un par de minutos.</p>' +
                '<button class="btn danger" data-act="cancel">Cancelar viaje</button>';
        }
        if (r.state === 'riding') {
            if (!r.dest || ui.pick) {
                var h2 = '<span class="tag">En el auto</span><h2>Elige tu destino</h2>';
                if (ui.dest && me.has) {
                    h2 += places(null, ui.dest) +
                        '<div class="row between"><span class="muted">Tarifa estimada</span><span class="price">' + money(fare(r.pickup[0], r.pickup[1], ui.dest[0], ui.dest[1])) + '</span></div>' +
                        '<button class="btn primary" data-act="confirmDest">Ir a este destino</button>';
                } else {
                    h2 += '<p class="muted">Toca el mapa para marcar a donde quieres ir.</p>';
                }
                return h2;
            }
            var left = remainingTo(r.dest[0], r.dest[1]);
            return '<span class="tag">En viaje</span><div class="row between"><div><div class="muted">Restante</div><div class="big" id="live-rem">' + km(left) + '</div></div>' +
                '<div style="text-align:right"><div class="muted">Tarifa</div><div class="price">' + money(r.fare) + '</div></div></div>' +
                driverCard(r.driver) +
                '<button class="btn ghost" data-act="changeDest">Cambiar destino</button>' +
                (r.driver && !r.driver.ai ? '<p class="muted">Para terminar el viaje, bajate del auto al llegar.</p>' : '<p class="muted">El conductor te deja en tu destino.</p>');
        }
        return '<p class="muted">...</p>';
    }

    function rateScreen() {
        var p = S.rate, h = '<div class="rate" style="display:flex;flex-direction:column;gap:10px">' +
            '<span class="tag">Viaje terminado · ' + money(p.fare) + '</span>' +
            '<h2>¿Que tal tu viaje con ' + esc(p.name) + '?</h2><div class="stars">';
        for (var i = 1; i <= 5; i++) h += '<button type="button" data-star="' + i + '" class="' + (i <= ui.stars ? 'on' : '') + '">★</button>';
        h += '</div>';
        if (!p.ai) {
            h += '<div class="muted">¿Agregar propina? Va completa al conductor.</div><div class="chips">';
            TIPS.forEach(function (t) {
                h += '<button type="button" data-tip="' + t + '" class="' + (ui.customTip === '' && ui.tip === t ? 'on' : '') + '">' + (t ? money(t) : 'Sin propina') + '</button>';
            });
            h += '</div><input class="tip" id="tip-input" type="number" min="0" max="' + CFG.MAX_TIP + '" placeholder="Otra $" value="' + esc(ui.customTip) + '">';
        } else {
            h += '<div class="muted">Los conductores de Vroom no reciben propina.</div>';
        }
        h += '<button class="btn primary" data-act="rate">Enviar calificacion' + (!p.ai && currentTip() > 0 ? ' + ' + money(currentTip()) : '') + '</button></div>';
        return h;
    }
    function currentTip() {
        if (S.rate && S.rate.ai) return 0;
        var t = ui.customTip !== '' ? Math.floor(Number(ui.customTip) || 0) : ui.tip;
        return Math.max(0, Math.min(CFG.MAX_TIP, t));
    }

    function driverScreen() {
        var d = S.driver || {}, h = '';
        h += '<div class="stats">' +
            '<div><b>' + (d.isNew ? 'Nuevo' : '★ ' + Number(d.rating || 0).toFixed(1)) + '</b><small>' + (d.ratings || 0) + ' calificaciones</small></div>' +
            '<div><b>' + (d.rides || 0) + '</b><small>viajes</small></div>' +
            '<div><b>' + money(d.earnings) + '</b><small>ganado</small></div></div>';
        h += '<div class="toggle"><div><b style="font-size:14px">' + (d.onDuty ? 'Conectado' : 'Desconectado') + '</b>' +
            '<div class="muted">' + (d.onDuty ? 'Recibiendo pedidos' : 'Sube a un auto y conectate') + '</div></div>' +
            '<button type="button" class="switch' + (d.onDuty ? ' on' : '') + '" data-act="duty"></button></div>';

        var trip = S.driving;
        if (trip) {
            var steps = { assigned: ['Recoge a ' + esc(trip.passenger), 'Sigue la ruta naranja hasta el punto A.'],
                arrived: ['Esperando a ' + esc(trip.passenger), 'Tu pasajero se esta subiendo.'],
                riding: ['Lleva a ' + esc(trip.passenger), trip.dest ? 'Sigue la ruta verde hasta el punto B.' : 'El pasajero esta eligiendo el destino.'] };
            var s = steps[trip.state] || [esc(trip.state), ''];
            var target = trip.state === 'riding' ? trip.dest : trip.pickup;
            h += '<div class="offer"><div class="row between"><span class="tag' + (trip.state === 'riding' ? '' : ' warn') + '">Viaje actual</span>' +
                (trip.fare ? '<span class="price">' + money(Math.floor(trip.fare * 0.8)) + '</span>' : '') + '</div>' +
                '<b>' + s[0] + '</b><span class="muted">' + s[1] + (target && me.has ? ' · ' + km(dist(me.x, me.y, target[0], target[1])) : '') + '</span>' +
                (trip.state !== 'riding' ? '<button class="btn danger small" data-act="driverCancel">Cancelar viaje</button>' : '') + '</div>';
            return h;
        }

        if (d.onDuty) {
            var ids = Object.keys(ui.offers);
            if (!ids.length) {
                h += '<div class="empty muted"><div class="dots" style="margin-bottom:6px"><span></span><span></span><span></span></div>Esperando pedidos...</div>';
            }
            ids.forEach(function (id) {
                var o = ui.offers[id];
                h += '<div class="offer"><div class="row between"><span class="tag">Nuevo pedido</span><span class="price">' + (o.fare ? money(o.fare) : 'A convenir') + '</span></div>' +
                    '<b>' + esc(o.passenger) + '</b><span class="muted">A ' + km(o.distance) + ' de ti · ' + (o.dest ? 'viaje de ' + km(dist(o.pickup[0], o.pickup[1], o.dest[0], o.dest[1])) : 'destino a elegir') + '</span>' +
                    '<button class="btn primary small" data-accept="' + esc(id) + '">Aceptar</button></div>';
            });
        }
        h += '<p class="muted">Tu calificacion define tu prioridad: con 4.5★ o mas recibes los pedidos primero. Ganas el 80% de la tarifa y el 100% de las propinas.</p>';
        return h;
    }

    function render(force) {
        document.body.classList.toggle('drive', ui.tab === 'drive');
        document.body.classList.toggle('compact', ui.tab === 'ride' && !!S.rate);
        document.querySelectorAll('.tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.tab === ui.tab); });
        var html = ui.tab === 'drive' ? driverScreen() : ridePassenger();
        if (!force && html === ui.lastKey) return;
        var focused = document.activeElement && document.activeElement.id === 'tip-input';
        ui.lastKey = html;
        sheet.innerHTML = html;
        if (focused) { var inp = $('tip-input'); if (inp) { inp.focus(); inp.setSelectionRange && inp.setSelectionRange(inp.value.length, inp.value.length); } }
    }

    // Actualizaciones en vivo sin rehacer la hoja (barra y distancia)
    setInterval(function () {
        var bar = $('search-bar');
        if (bar && S.ride) bar.style.width = Math.min(100, (now() - ui.searchStart) / 10 / (S.ride.searchTime || 25)) + '%';
        var rem = $('live-rem');
        if (rem && S.ride) {
            var t = S.ride.state === 'riding' ? S.ride.dest : S.ride.pickup;
            if (t) rem.textContent = km(remainingTo(t[0], t[1]));
        }
        if (ui.tab === 'drive' && S.driving) render();
    }, 500);

    // ------------------------------------------------------------
    // Clicks en la hoja
    // ------------------------------------------------------------
    sheet.addEventListener('click', function (e) {
        var el = e.target.closest('button');
        if (!el || !ui.interactive) return;
        if (el.dataset.star) { ui.stars = Number(el.dataset.star); return render(true); }
        if (el.dataset.tip != null) { ui.tip = Number(el.dataset.tip); ui.customTip = ''; return render(true); }
        if (el.dataset.accept) { el.disabled = true; return send('accept', el.dataset.accept); }
        switch (el.dataset.act) {
            case 'request':
                if (ui.dest) send('request', ui.dest[0], ui.dest[1]); else send('request');
                break;
            case 'clearDest': ui.dest = null; render(true); break;
            case 'cancel': send('cancel'); break;
            case 'confirmDest':
                if (ui.dest) { send('setDest', ui.dest[0], ui.dest[1]); ui.pick = false; }
                break;
            case 'changeDest': ui.pick = true; ui.dest = null; render(true); break;
            case 'rate': send('rate', ui.stars, currentTip()); el.disabled = true; break;
            case 'duty': send('duty', S.driver && S.driver.onDuty ? '0' : '1'); break;
            case 'driverCancel': send('driverCancel'); break;
        }
    });
    sheet.addEventListener('input', function (e) {
        if (e.target.id !== 'tip-input') return;
        ui.customTip = e.target.value.replace(/[^0-9]/g, '').slice(0, 4);
        render();
    });

    document.querySelectorAll('.tabs button').forEach(function (b) {
        b.addEventListener('click', function () { ui.tab = b.dataset.tab; render(true); });
    });
    $('btn-close').onclick = function () { send('close'); };

    document.addEventListener('keydown', function (e) {
        if (!ui.interactive) return;
        var typing = e.target && e.target.tagName === 'INPUT';
        if (e.key === 'Escape') { e.preventDefault(); send('close'); }
        else if (!typing && (e.key === 'm' || e.key === 'M')) { e.preventDefault(); send('passive'); }
    });
    document.addEventListener('contextmenu', function (e) { e.preventDefault(); });

    // ------------------------------------------------------------
    // API para Lua
    // ------------------------------------------------------------
    window.RP = {
        graph: function (nodes, links, lanes) {
            if (!nodes || !nodes.length) { G = null; return; }
            G = { nodes: nodes, links: links || [], lanes: lanes || [], count: Math.floor(nodes.length / 3) };
            if (!mapReady && mapImg.complete && !mapImg.naturalWidth) buildRoadLayer();
        },

        state: function (s) {
            var prev = S;
            S = s || {};
            S.driver = S.driver || {};
            var r = S.ride;
            if (r && r.state === 'searching' && ui.searchId !== r.id) { ui.searchId = r.id; ui.searchStart = now(); }
            if (r && r.dest && !ui.pick) ui.dest = null;   // el destino confirmado ya se dibuja desde el estado
            if (r && r.state === 'riding' && !r.dest) ui.pick = true;
            if (!r) ui.pick = false;
            if (prev.ride && !r) ui.dest = null;
            if (S.rate && !prev.rate) { ui.tab = 'ride'; ui.stars = 5; ui.tip = 0; ui.customTip = ''; }
            if (S.driving || !S.driver.onDuty) ui.offers = {};
            if (!r && !S.driving) { route = null; car = null; }
            render();
        },

        offer: function (info) {
            if (!info || info.id == null) return;
            ui.offers[info.id] = info;
            if (!S.ride && !S.rate) ui.tab = 'drive';
            render(true);
        },
        offerGone: function (id) { delete ui.offers[id]; render(); },

        screen: function (name) {
            ui.tab = 'ride';
            if (name === 'pick') { ui.pick = true; ui.dest = null; }
            render(true);
        },

        route: function (nodes, animate, kind) { setRoute(nodes, !!animate, kind); },

        positions: function (x, y, rot, c) {
            me.x = x; me.y = y; me.rot = rot || 0; me.has = true;
            if (c) {
                if (!car) car = { sx: null, sy: null };
                car.x = c[0]; car.y = c[1]; car.remaining = c[2]; car.mode = c[3];
            } else car = null;
        },

        setInteractive: function (on) {
            ui.interactive = !!on;
            document.body.classList.toggle('passive', !on);
            $('hint').textContent = on ? 'M: modo mapa · Esc: ocultar' : 'M: usar la app';
            if (!on) { view.follow = true; drag = null; }
        }
    };

    render(true);
    requestAnimationFrame(frame);
    send('ready');
})();
