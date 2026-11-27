/*
 * rp_map / map2d.js
 * Mapa 2D en canvas calibrado con las coordenadas reales de GTA SA:
 *   mundo (x, y) en metros, -3000..3000, y = norte.  pantalla X = W/2 + (x - cx) * s ; Y = H/2 - (y - cy) * s
 * Capas: radar oscurecido + calles y edificios vectoriales (base precalculada), niebla por celdas
 * de 50 m, cuadriculas de 500 m, ruta GPS; iconos, marcadores y jugador en DOM (clic y hover).
 * Solo se redibuja cuando algo cambia.
 */
(function () {
    "use strict";
    var WORLD = 6000, HALF = 3000, N = 120, BASE = 4096, BK = BASE / WORLD;
    var MINOR = { casa: 1, apartamento: 1, cajero: 1 };

    var cv, ctx, layer, wrap, hooks = {};
    var W = 0, H = 0, dpr = 1;
    var view = { cx: 1500, cy: -1700, s: 0.25 }, anim = null;
    var base = null, baseReady = false, fogCanvas = null, fogOn = true;
    var roadGrid = null, bldGrid = null;
    var showGrid = true, sectors = [], hoverSector = -1;
    var route = null, player = null, temp = null, dest = null;
    var places = [], cats = {}, hidden = {}, selectedId = null, markers = [];
    var els = {}, meEl = null, tempEl = null, destEl = null;
    var dirty = true, raf = null, active = false;

    function minScale() { return Math.min(W, H) / WORLD * 0.95; }
    function clampView() {
        view.s = Math.max(minScale(), Math.min(6, view.s));
        var mx = HALF, my = HALF;
        view.cx = Math.max(-mx, Math.min(mx, view.cx));
        view.cy = Math.max(-my, Math.min(my, view.cy));
    }
    function w2s(x, y) { return [W / 2 + (x - view.cx) * view.s, H / 2 - (y - view.cy) * view.s]; }
    function s2w(px, py) { return [view.cx + (px - W / 2) / view.s, view.cy - (py - H / 2) / view.s]; }

    // ---------------------------------------------------------------- capa base
    function bucket(size, add) {
        var g = {};
        add(function (x, y, item) {
            var k = Math.floor((x + HALF) / size) + "," + Math.floor((y + HALF) / size);
            (g[k] || (g[k] = [])).push(item);
        });
        return g;
    }

    function buildGrids() {
        var R = window.MAP_ROADS, B = window.MAP_BUILDINGS;
        if (R) {
            roadGrid = bucket(250, function (put) {
                for (var i = 0; i < R.s.length; i += 3) {
                    var a = R.s[i], b = R.s[i + 1];
                    put((R.n[a * 2] + R.n[b * 2]) / 2, (R.n[a * 2 + 1] + R.n[b * 2 + 1]) / 2, i);
                }
            });
        }
        if (B) {
            bldGrid = bucket(250, function (put) {
                for (var i = 0; i < B.b.length; i += 8) put(B.b[i], B.b[i + 1], i);
            });
        }
    }

    // t: 1 autopista, +2 un sentido. Un solo trazo por estilo: sin "puntos" donde se solapan los tramos
    var ROAD_STYLES = [{ c: "rgba(190,200,220,0.55)", w: 6, min: 0.8 }, { c: "rgba(255,190,110,0.80)", w: 10, min: 1.4 }];

    function drawRoads(g, sc, ox, oy, filter) {
        var R = window.MAP_ROADS;
        if (!R) return;
        g.lineCap = "round";
        g.lineJoin = "round";
        for (var pass = 0; pass < 2; pass++) {
            var st = ROAD_STYLES[pass];
            g.strokeStyle = st.c;
            g.lineWidth = Math.max(st.min, st.w * sc);
            g.beginPath();
            for (var i = 0; i < R.s.length; i += 3) {
                if (filter && !filter[i]) continue;
                if ((R.s[i + 2] & 1) !== pass) continue;
                var a = R.s[i], b = R.s[i + 1];
                g.moveTo(ox + (R.n[a * 2] + HALF) * sc, oy + (HALF - R.n[a * 2 + 1]) * sc);
                g.lineTo(ox + (R.n[b * 2] + HALF) * sc, oy + (HALF - R.n[b * 2 + 1]) * sc);
            }
            g.stroke();
        }
    }

    function drawBuildings(g, sc, ox, oy, list) {
        var B = window.MAP_BUILDINGS;
        if (!B) return;
        g.fillStyle = "rgba(170,180,205,0.10)";
        g.strokeStyle = "rgba(200,210,230,0.18)";
        g.lineWidth = 1;
        var n = list ? list.length : B.b.length / 8;
        for (var k = 0; k < n; k++) {
            var i = list ? list[k] : k * 8;
            var cx = B.b[i], cy = B.b[i + 1], hx = B.b[i + 2], hy = B.b[i + 3], r = B.b[i + 4];
            var c = Math.cos(r), s = Math.sin(r);
            g.beginPath();
            var pts = [[-hx, -hy], [hx, -hy], [hx, hy], [-hx, hy]];
            for (var p = 0; p < 4; p++) {
                var wx = cx + pts[p][0] * c - pts[p][1] * s, wy = cy + pts[p][0] * s + pts[p][1] * c;
                var X = ox + (wx + HALF) * sc, Y = oy + (HALF - wy) * sc;
                if (p === 0) g.moveTo(X, Y); else g.lineTo(X, Y);
            }
            g.closePath();
            g.fill();
            g.stroke();
        }
    }

    function buildBase(img) {
        base = document.createElement("canvas");
        base.width = base.height = BASE;
        var g = base.getContext("2d");
        g.fillStyle = "#0d1420";
        g.fillRect(0, 0, BASE, BASE);
        if (img) {
            g.filter = "grayscale(0.35) brightness(0.40) contrast(1.25) saturate(0.85)";
            g.drawImage(img, 0, 0, BASE, BASE);
            g.filter = "none";
        }
        // tinte frio uniforme
        g.fillStyle = "rgba(20,28,52,0.28)";
        g.fillRect(0, 0, BASE, BASE);
        drawBuildings(g, BK, 0, 0, null);
        drawRoads(g, BK, 0, 0, null);
        baseReady = true;
        if (hooks.onBase) hooks.onBase(base);
        invalidate();
    }

    // ---------------------------------------------------------------- niebla
    function setFog(land, cells, start, on) {
        fogOn = on;
        var small = document.createElement("canvas");
        small.width = small.height = N;
        var g = small.getContext("2d");
        var im = g.createImageData(N, N), d = im.data;
        for (var i = 0; i < N * N; i++) {
            var seen = !on || cells[i + 1] || start[i + 1];
            var a = seen ? 0 : (land.charCodeAt(i) === 49 ? 248 : 215);
            d[i * 4] = 7; d[i * 4 + 1] = 9; d[i * 4 + 2] = 15; d[i * 4 + 3] = a;
        }
        g.putImageData(im, 0, 0);
        // version grande y suavizada: bordes difusos como en GTA VI
        fogCanvas = document.createElement("canvas");
        fogCanvas.width = fogCanvas.height = 960;
        var fg = fogCanvas.getContext("2d");
        fg.imageSmoothingEnabled = true;
        fg.filter = "blur(5px)";
        fg.drawImage(small, 0, 0, 960, 960);
        fg.filter = "none";
        if (hooks.onFog) hooks.onFog(fogCanvas);
        invalidate();
    }

    // ---------------------------------------------------------------- dibujo
    function visibleItems(grid) {
        var a = s2w(0, 0), b = s2w(W, H), out = [];
        var x0 = Math.floor((a[0] + HALF) / 250) - 1, x1 = Math.floor((b[0] + HALF) / 250) + 1;
        var y0 = Math.floor((b[1] + HALF) / 250) - 1, y1 = Math.floor((a[1] + HALF) / 250) + 1;
        for (var x = x0; x <= x1; x++) for (var y = y0; y <= y1; y++) {
            var l = grid[x + "," + y];
            if (l) for (var k = 0; k < l.length; k++) out.push(l[k]);
        }
        return out;
    }

    function render() {
        raf = null;
        if (!active) return;
        if (anim) {
            var t = Math.min(1, (performance.now() - anim.t0) / anim.ms), e = 1 - Math.pow(1 - t, 3);
            view.cx = anim.from.cx + (anim.to.cx - anim.from.cx) * e;
            view.cy = anim.from.cy + (anim.to.cy - anim.from.cy) * e;
            view.s = Math.exp(Math.log(anim.from.s) + (Math.log(anim.to.s) - Math.log(anim.from.s)) * e);
            if (t >= 1) anim = null;
            dirty = true;
        }
        if (dirty) { dirty = false; draw(); }
        if (anim) invalidate();
    }

    function invalidate() {
        dirty = true;
        if (!raf && active) raf = requestAnimationFrame(render);
    }

    function draw() {
        clampView();
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.fillStyle = "#0b0f16";
        ctx.fillRect(0, 0, W, H);
        var e = W / 2 - (HALF + view.cx) * view.s, f = H / 2 - (HALF - view.cy) * view.s;
        if (baseReady) {
            ctx.imageSmoothingEnabled = true;
            ctx.imageSmoothingQuality = "high";
            ctx.save();
            ctx.setTransform(dpr * view.s / BK, 0, 0, dpr * view.s / BK, dpr * e, dpr * f);
            ctx.drawImage(base, 0, 0);
            ctx.restore();
        }
        // Detalle vectorial al acercarse (la base ya no da resolucion)
        if (view.s > 1.0 && roadGrid) {
            var sel = {}, vis = visibleItems(roadGrid);
            for (var i = 0; i < vis.length; i++) sel[vis[i]] = 1;
            ctx.save();
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
            if (bldGrid) drawBuildings(ctx, view.s, e, f, visibleItems(bldGrid));
            drawRoads(ctx, view.s, e, f, sel);
            ctx.restore();
        }
        // Niebla
        if (fogCanvas && fogOn) {
            ctx.save();
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
            ctx.imageSmoothingEnabled = true;
            ctx.drawImage(fogCanvas, e, f, WORLD * view.s, WORLD * view.s);
            ctx.restore();
        }
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        if (showGrid) drawSectors(e, f);
        if (route && route.length >= 4) drawRoute();
        positionDom();
    }

    function drawSectors(e, f) {
        var step = 500 * view.s;
        ctx.lineWidth = 1;
        ctx.strokeStyle = "rgba(255,255,255,0.08)";
        ctx.beginPath();
        for (var k = 0; k <= 12; k++) {
            ctx.moveTo(e + k * step, f); ctx.lineTo(e + k * step, f + 12 * step);
            ctx.moveTo(e, f + k * step); ctx.lineTo(e + 12 * step, f + k * step);
        }
        ctx.stroke();
        if (hoverSector >= 0) {
            var sx = hoverSector % 12, sy = Math.floor(hoverSector / 12);
            ctx.strokeStyle = "rgba(245,165,36,0.85)";
            ctx.lineWidth = 2;
            ctx.strokeRect(e + sx * step, f + sy * step, step, step);
            ctx.fillStyle = "rgba(245,165,36,0.06)";
            ctx.fillRect(e + sx * step, f + sy * step, step, step);
        }
        if (step > 70) {
            ctx.font = "600 " + Math.round(Math.min(15, 9 + step / 60)) + "px Segoe UI, Arial";
            ctx.textBaseline = "top";
            for (var s = 0; s < 144; s++) {
                var sec = sectors[s];
                if (!sec) continue;
                var x = e + (s % 12) * step + 6, y = f + Math.floor(s / 12) * step + 5;
                if (x > W || y > H || x + step < 0 || y + step < 0) continue;
                ctx.fillStyle = sec.state === 2 ? "rgba(255,210,120,0.85)" : "rgba(255,255,255,0.40)";
                ctx.fillText(sec.id + (sec.state > 0 && step > 140 ? "  " + sec.name : ""), x, y);
            }
        }
    }

    function drawRoute() {
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        var w = Math.max(4, Math.min(16, 9 * view.s));
        for (var pass = 0; pass < 2; pass++) {
            ctx.beginPath();
            for (var i = 0; i < route.length; i += 2) {
                var p = w2s(route[i], route[i + 1]);
                if (i === 0) ctx.moveTo(p[0], p[1]); else ctx.lineTo(p[0], p[1]);
            }
            ctx.strokeStyle = pass === 0 ? "rgba(40,8,60,0.85)" : "#c55cff";
            ctx.lineWidth = pass === 0 ? w + 4 : w;
            if (pass === 1) { ctx.shadowColor = "rgba(197,92,255,0.8)"; ctx.shadowBlur = 10; }
            ctx.stroke();
            ctx.shadowBlur = 0;
        }
    }

    // ---------------------------------------------------------------- DOM: iconos, marcadores, jugador
    function placeEl(pl) {
        var el = els["p" + pl.id];
        var c = cats[pl.cat] || { color: "#888", icon: "pin" };
        if (!el) {
            el = document.createElement("div");
            el.className = "poi";
            el.innerHTML = '<div class="dot"></div><div class="lbl"></div>';
            el.addEventListener("mousedown", function (ev) { ev.stopPropagation(); });
            el.addEventListener("click", function (ev) { ev.stopPropagation(); if (hooks.onPlace) hooks.onPlace(el._id); });
            layer.appendChild(el);
            els["p" + pl.id] = el;
        }
        el._id = pl.id;
        if (el._sig !== c.color + c.icon + pl.name) {
            el._sig = c.color + c.icon + pl.name;
            el.firstChild.style.background = c.color;
            el.firstChild.innerHTML = window.ICONS.svg(c.icon, 15);
            el.lastChild.textContent = pl.name;
        }
        return el;
    }

    function markerEl(m) {
        var el = els["m" + m.id];
        if (!el) {
            el = document.createElement("div");
            el.className = "mk";
            el.addEventListener("mousedown", function (ev) { ev.stopPropagation(); });
            el.addEventListener("click", function (ev) { ev.stopPropagation(); if (hooks.onMarker) hooks.onMarker(el._id); });
            layer.appendChild(el);
            els["m" + m.id] = el;
        }
        el._id = m.id;
        var color = m.favorite ? "#f5a524" : "#4fd1ff";
        if (el._sig !== color) {
            el._sig = color;
            el.innerHTML = '<svg viewBox="0 0 24 24" width="28" height="28"><path fill="' + color + '" stroke="#0a0c12" stroke-width="1.5" d="M12 2a7 7 0 017 7c0 5-7 13-7 13S5 14 5 9a7 7 0 017-7z"/><circle cx="12" cy="9" r="2.6" fill="#0a0c12"/></svg>';
        }
        el.title = m.name;
        return el;
    }

    function positionDom() {
        var seen = {}, i, p;
        var zoomedOut = view.s < 0.35;
        for (i = 0; i < places.length; i++) {
            var pl = places[i];
            if (hidden[pl.cat] || !cats[pl.cat]) continue;
            if (zoomedOut && MINOR[pl.cat] && selectedId !== pl.id) continue;
            p = w2s(pl.x, pl.y);
            if (p[0] < -30 || p[1] < -30 || p[0] > W + 30 || p[1] > H + 30) continue;
            var el = placeEl(pl);
            el.style.left = p[0] + "px"; el.style.top = p[1] + "px";
            el.classList.toggle("sel", selectedId === pl.id);
            seen["p" + pl.id] = true;
        }
        for (i = 0; i < markers.length; i++) {
            var m = markers[i];
            p = w2s(m.x, m.y);
            var me = markerEl(m);
            me.style.left = p[0] + "px"; me.style.top = p[1] + "px";
            seen["m" + m.id] = true;
        }
        for (var k in els) {
            if (!seen[k]) { els[k].remove(); delete els[k]; }
        }
        if (player && !player.inside) {
            if (!meEl) {
                meEl = document.createElement("div");
                meEl.className = "me";
                meEl.innerHTML = '<svg viewBox="0 0 34 34"><path d="M17 4l9 24-9-5-9 5z" fill="#f5a524" stroke="#14080e" stroke-width="2" stroke-linejoin="round"/></svg>';
                layer.appendChild(meEl);
            }
            p = w2s(player.x, player.y);
            meEl.style.left = p[0] + "px"; meEl.style.top = p[1] + "px";
            meEl.firstChild.style.transform = "rotate(" + (-player.rot) + "deg)";
            meEl.style.display = "";
        } else if (meEl) meEl.style.display = "none";
        if (temp) {
            if (!tempEl) { tempEl = document.createElement("div"); tempEl.className = "temp"; layer.appendChild(tempEl); }
            p = w2s(temp[0], temp[1]);
            tempEl.style.left = p[0] + "px"; tempEl.style.top = p[1] + "px"; tempEl.style.display = "";
        } else if (tempEl) tempEl.style.display = "none";
        if (dest) {
            if (!destEl) {
                destEl = document.createElement("div");
                destEl.className = "dest";
                destEl.innerHTML = '<svg viewBox="0 0 24 24" width="30" height="30"><path d="M6 3h2v18H6z" fill="#fff"/><path d="M8 4h11l-3 4 3 4H8z" fill="#c55cff" stroke="#14080e" stroke-width="1"/></svg>';
                layer.appendChild(destEl);
            }
            p = w2s(dest[0], dest[1]);
            destEl.style.left = (p[0] + 9) + "px"; destEl.style.top = p[1] + "px"; destEl.style.display = "";
        } else if (destEl) destEl.style.display = "none";
    }

    // ---------------------------------------------------------------- interaccion
    function sectorAt(x, y) {
        var sx = Math.floor((x + HALF) / 500), sy = Math.floor((HALF - y) / 500);
        if (sx < 0 || sy < 0 || sx > 11 || sy > 11) return -1;
        return sy * 12 + sx;
    }

    function bindInput() {
        var down = null;
        wrap.addEventListener("mousedown", function (ev) {
            if (!active || ev.button !== 0) return;
            down = { x: ev.clientX, y: ev.clientY, cx: view.cx, cy: view.cy, moved: false };
            wrap.classList.add("drag");
        });
        window.addEventListener("mousemove", function (ev) {
            if (!active) return;
            var r = cv.getBoundingClientRect();
            var px = ev.clientX - r.left, py = ev.clientY - r.top;
            if (down) {
                var dx = ev.clientX - down.x, dy = ev.clientY - down.y;
                if (Math.abs(dx) + Math.abs(dy) > 4) down.moved = true;
                if (down.moved) {
                    anim = null;
                    view.cx = down.cx - dx / view.s;
                    view.cy = down.cy + dy / view.s;
                    invalidate();
                }
            }
            if (px >= 0 && py >= 0 && px <= W && py <= H) {
                var w = s2w(px, py), sec = sectorAt(w[0], w[1]);
                if (sec !== hoverSector) { hoverSector = sec; invalidate(); }
                if (hooks.onHover) hooks.onHover(w[0], w[1], sec, px, py);
            } else if (hoverSector !== -1) {
                hoverSector = -1; invalidate();
                if (hooks.onHover) hooks.onHover(null);
            }
        });
        window.addEventListener("mouseup", function (ev) {
            if (!down) return;
            wrap.classList.remove("drag");
            var wasClick = !down.moved;
            down = null;
            if (wasClick && active) {
                var r = cv.getBoundingClientRect();
                var w = s2w(ev.clientX - r.left, ev.clientY - r.top);
                if (hooks.onClick) hooks.onClick(w[0], w[1], sectorAt(w[0], w[1]));
            }
        });
        // Clic derecho: quita el destino marcado
        wrap.addEventListener("contextmenu", function (ev) {
            ev.preventDefault();
            if (active && hooks.onRightClick) hooks.onRightClick();
        });
        wrap.addEventListener("wheel", function (ev) {
            if (!active) return;
            ev.preventDefault();
            var r = cv.getBoundingClientRect();
            zoomAt(ev.deltaY < 0 ? 1.35 : 1 / 1.35, ev.clientX - r.left, ev.clientY - r.top);
        }, { passive: false });
    }

    function zoomAt(k, px, py) {
        var from = anim ? anim.to : { cx: view.cx, cy: view.cy, s: view.s };
        var ns = Math.max(minScale(), Math.min(6, from.s * k));
        var cur = { cx: view.cx, cy: view.cy, s: view.s };
        // mantener bajo el cursor el mismo punto del mundo
        var wx = from.cx + (px - W / 2) / from.s, wy = from.cy - (py - H / 2) / from.s;
        var to = { cx: wx - (px - W / 2) / ns, cy: wy + (py - H / 2) / ns, s: ns };
        anim = { from: cur, to: to, t0: performance.now(), ms: 220 };
        invalidate();
    }

    function resize() {
        var r = wrap.getBoundingClientRect();
        dpr = window.devicePixelRatio || 1;
        W = Math.max(1, r.width); H = Math.max(1, r.height);
        cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
        invalidate();
    }

    window.Map2D = {
        init: function (canvas, domLayer, wrapper, h) {
            cv = canvas; ctx = cv.getContext("2d"); layer = domLayer; wrap = wrapper; hooks = h || {};
            buildGrids();
            bindInput();
            window.addEventListener("resize", resize);
            var img = new Image();
            img.onload = function () { buildBase(img); };
            img.onerror = function () { buildBase(null); if (hooks.onMissing) hooks.onMissing(); };
            img.src = "data/map.jpg";
        },
        setActive: function (on) { active = on; if (on) { resize(); invalidate(); } },
        resize: resize,
        setFog: setFog,
        setSectors: function (list) { sectors = list; invalidate(); },
        setGrid: function (on) { showGrid = on; invalidate(); },
        setPlaces: function (list, catMap, hiddenMap) { places = list; cats = catMap; hidden = hiddenMap || {}; invalidate(); },
        setMarkers: function (list) { markers = list || []; invalidate(); },
        setPlayer: function (p) { player = p; positionDomOnly(); },
        setRoute: function (pts, d) { route = pts && pts.length >= 4 ? pts : null; dest = d || null; invalidate(); },
        setTemp: function (x, y) { temp = x === null ? null : [x, y]; invalidate(); },
        setSelected: function (id) { selectedId = id; invalidate(); },
        zoom: function (k) { zoomAt(k, W / 2, H / 2); },
        centerOn: function (x, y, s) {
            anim = { from: { cx: view.cx, cy: view.cy, s: view.s }, to: { cx: x, cy: y, s: s || Math.max(view.s, 0.8) }, t0: performance.now(), ms: 450 };
            invalidate();
        },
        jumpTo: function (x, y, s) { view.cx = x; view.cy = y; if (s) view.s = s; anim = null; invalidate(); },
        getView: function () { return { cx: view.cx, cy: view.cy, s: view.s }; },
        worldToScreen: w2s,
        getBase: function () { return baseReady ? base : null; },
        getFog: function () { return fogCanvas; },
    };

    function positionDomOnly() { if (active) positionDom(); }
})();
