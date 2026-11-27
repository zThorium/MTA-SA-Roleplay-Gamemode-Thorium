/*
 * rp_map / app.js
 * Interfaz del mapa F11. Lua llama a window.RP.* (open, close, player, cells, places,
 * route, navDist, adminData, adminPlayer) y la interfaz responde con mta.triggerEvent("rp:map:ui:*").
 * El servidor revalida todo; aqui solo hay lo que este jugador puede ver.
 * Vista previa sin el juego: abrir index.html#demo en un navegador.
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var N = 120;

    var S = { land: "", cells: {}, start: {}, places: [], placeById: {}, cats: [], catMap: {}, sectors: [], zones: [],
        settings: {}, prefs: {}, totals: { all: 0, city: {} }, isAdmin: false, cities: [], discoveredPct: 90, icons: [] };
    var cellZone = {}, cellCity = {}, cityLand = {};
    var player = null, route = { active: false }, mode = "2d", isOpen = false, firstCenter = true;
    var selection = null, pickMode = null, tab = "places", adminTab = "places", admin = null, adminForm = {};
    var hidden = {};

    // ---------------------------------------------------------------- utilidades
    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }
    function el(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text !== undefined) n.textContent = text;
        return n;
    }
    function btn(text, cls, fn) {
        var b = el("button", cls || "ghost", text);
        b.addEventListener("click", function (ev) { ev.stopPropagation(); play("click"); fn(ev); });
        return b;
    }
    var SOUNDS = { open: "maximize_003", close: "minimize_003", click: "click_002", select: "select_002",
        ok: "confirmation_002", big: "confirmation_003", error: "error_004", step: "pluck_001" };
    function play(name) {
        try { var a = new Audio("sounds/" + SOUNDS[name] + ".ogg"); a.volume = 0.45; var pr = a.play(); if (pr && pr.catch) pr.catch(function () {}); } catch (e) { /* sin audio */ }
    }
    function fmtDist(m) { return m >= 1000 ? (m / 1000).toFixed(1).replace(".", ",") + " km" : Math.round(m) + " m"; }
    function fmtPct(p) { return (Math.round(p * 10) / 10).toString().replace(".", ",") + "%"; }
    function cellOf(x, y) {
        var cx = Math.floor((x + 3000) / 50), cy = Math.floor((3000 - y) / 50);
        if (cx < 0 || cy < 0 || cx >= N || cy >= N) return 0;
        return cy * N + cx + 1;
    }
    function sectorOf(x, y) {
        var sx = Math.floor((x + 3000) / 500), sy = Math.floor((3000 - y) / 500);
        if (sx < 0 || sy < 0 || sx > 11 || sy > 11) return -1;
        return sy * 12 + sx;
    }
    function known(x, y) {
        if (S.settings.fog === 0 || S.adminView) return true;
        var c = cellOf(x, y);
        return !!(S.cells[c] || S.start[c]);
    }
    function distTo(x, y) { return player ? Math.sqrt((player.x - x) * (player.x - x) + (player.y - y) * (player.y - y)) : null; }
    function heading(deg) {
        var h = ((-deg % 360) + 360) % 360;   // GTA: antihorario -> brujula horaria
        var names = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"];
        return names[Math.round(h / 45) % 8] + " " + Math.round(h) + "°";
    }
    function placeName(x, y) {
        var c = cellOf(x, y);
        if (!known(x, y)) return "Zona sin explorar";
        return (cellZone[c] || "San Andreas") + (cellCity[c] ? ", " + cellCity[c] : "");
    }

    // ---------------------------------------------------------------- estado derivado
    function rebuildZones() {
        cellZone = {}; cellCity = {}; cityLand = {};
        for (var i = 0; i < S.zones.length; i++) {
            var z = S.zones[i];
            for (var k = 0; k < z.cells.length; k++) { cellZone[z.cells[k]] = z.name; cellCity[z.cells[k]] = z.city; }
            cityLand[z.city] = (cityLand[z.city] || 0) + z.cells.length;
        }
    }

    function sectorStats() {
        var list = [];
        for (var s = 0; s < S.sectors.length; s++) list[s] = { got: 0 };
        for (var c in S.cells) {
            c = +c;
            if (S.land.charCodeAt(c - 1) !== 49) continue;
            var i0 = c - 1, sx = Math.floor((i0 % N) / 10), sy = Math.floor(Math.floor(i0 / N) / 10);
            list[sy * 12 + sx].got++;
        }
        var out = [];
        for (s = 0; s < S.sectors.length; s++) {
            var sec = S.sectors[s], land = sec.land || 0, got = list[s].got;
            var pct = land > 0 ? got / land * 100 : 0;
            var state = sec.revealed || S.settings.fog === 0 ? 2 : (pct >= S.discoveredPct ? 2 : (got > 0 ? 1 : 0));
            out.push({ id: sec.id, name: sec.name, city: sec.city, land: land, got: got, pct: sec.revealed ? 100 : pct, state: state });
        }
        return out;
    }

    function landExplored() {
        var n = 0, byCity = {};
        for (var c in S.cells) {
            c = +c;
            if (S.land.charCodeAt(c - 1) === 49) {
                n++;
                var city = cellCity[c];
                if (city) byCity[city] = (byCity[city] || 0) + 1;
            }
        }
        return { n: n, byCity: byCity };
    }

    function refreshFog() {
        var fogOn = S.settings.fog !== 0 && !S.adminView;   // vista de admin: todo el mapa
        window.Map2D.setFog(S.land, S.cells, S.start, fogOn);
        window.Map3D.setFog(S.cells, S.start, fogOn);
        var st = sectorStats();
        window.Map2D.setSectors(st);
        refreshProgress();
        return st;
    }

    function refreshPlaces() {
        S.placeById = {};
        for (var i = 0; i < S.places.length; i++) S.placeById[S.places[i].id] = S.places[i];
        window.Map2D.setPlaces(S.places, S.catMap, hidden);
        window.Map3D.setPlaces(S.places, S.catMap, hidden);
        renderCats();
        renderNear();
    }

    function refreshProgress() {
        var total = 0;
        for (var k in cityLand) total += cityLand[k];
        var pct = total ? landExplored().n / total * 100 : 0;
        if (S.settings.fog === 0) pct = 100;
        $("b-prog").textContent = fmtPct(pct);
        $("b-prog-fill").style.width = pct + "%";
        if (tab === "stats") renderStats();
    }

    // ---------------------------------------------------------------- panel: lugares
    function renderCats() {
        var box = $("cats");
        box.textContent = "";
        var counts = {};
        for (var i = 0; i < S.places.length; i++) counts[S.places[i].cat] = (counts[S.places[i].cat] || 0) + 1;
        S.cats.forEach(function (c) {
            var row = el("div", "cat" + (hidden[c.key] ? " off" : ""));
            var dot = el("div", "dot");
            dot.style.background = c.color;
            dot.innerHTML = window.ICONS.svg(c.icon, 14);
            row.appendChild(dot);
            row.appendChild(el("span", "", c.name));
            row.appendChild(el("span", "n", String(counts[c.key] || 0)));
            row.title = hidden[c.key] ? "Mostrar en el mapa" : "Ocultar del mapa";
            row.addEventListener("click", function () {
                play("click");
                if (hidden[c.key]) delete hidden[c.key]; else hidden[c.key] = true;
                savePrefs();
                refreshPlaces();
            });
            box.appendChild(row);
        });
    }

    function renderNear() {
        var box = $("near");
        box.textContent = "";
        if (!player) return;
        var list = S.places.filter(function (p) { return !hidden[p.cat] && S.catMap[p.cat]; })
            .map(function (p) { return { p: p, d: distTo(p.x, p.y) }; })
            .sort(function (a, b) { return a.d - b.d; }).slice(0, 12);
        if (!list.length) { box.appendChild(el("div", "empty", "Aun no conoces lugares. Explora la ciudad.")); return; }
        list.forEach(function (it) { box.appendChild(placeRow(it.p, fmtDist(it.d))); });
    }

    function placeRow(p, right) {
        var c = S.catMap[p.cat] || { color: "#888", icon: "pin", name: "" };
        var row = el("div", "row");
        var dot = el("div", "dot");
        dot.style.background = c.color;
        dot.innerHTML = window.ICONS.svg(c.icon, 14);
        row.appendChild(dot);
        var t = el("div", "txt");
        t.appendChild(el("div", "", p.name));
        t.appendChild(el("small", "", c.name + (right ? " · " + right : "")));
        row.appendChild(t);
        row.addEventListener("click", function () { selectPlace(p.id, true); });
        return row;
    }

    // ---------------------------------------------------------------- tarjeta de seleccion
    function closeCard() {
        selection = null;
        $("card").classList.add("hidden");
        window.Map2D.setSelected(null);
        window.Map2D.setTemp(null);
        window.Map3D.clearHighlight();
    }

    function metaRow(box, k, v) { box.appendChild(el("span", "", k)); var b = el("b", "", v); box.appendChild(b); }

    function card(title, sub, color, icon, desc, x, y, buttons) {
        var c = $("card");
        c.textContent = "";
        var x0 = el("button", "x", "×");
        x0.addEventListener("click", function () { play("click"); closeCard(); });
        c.appendChild(x0);
        var line = el("div", "cat-line");
        if (icon) {
            var dot = el("div", "dot");
            dot.style.background = color;
            dot.innerHTML = window.ICONS.svg(icon, 13);
            line.appendChild(dot);
        }
        line.appendChild(el("span", "", sub));
        c.appendChild(line);
        c.appendChild(el("h3", "", title));
        if (desc) c.appendChild(el("p", "", desc));
        var meta = el("div", "meta");
        var d = distTo(x, y);
        if (d !== null) metaRow(meta, "Distancia", fmtDist(d));
        metaRow(meta, "Zona", placeName(x, y));
        var s = sectorOf(x, y);
        if (s >= 0 && S.sectors[s]) metaRow(meta, "Cuadricula", S.sectors[s].id + (known(x, y) ? " · " + S.sectors[s].name : ""));
        metaRow(meta, "Coordenadas", Math.round(x) + ", " + Math.round(y));
        c.appendChild(meta);
        var bx = el("div", "btns");
        buttons.forEach(function (b) { bx.appendChild(b); });
        c.appendChild(bx);
        c.classList.remove("hidden");
    }

    function gpsBtn(x, y, label, z) {
        var b = btn("Ruta GPS", "primary", function () {
            if (S.settings.gps === 0) return play("error");
            send("rp:map:ui:navigate", x, y, z || 0, label);
        });
        if (S.settings.gps === 0) { b.disabled = true; b.title = "GPS desactivado en el servidor"; }
        return b;
    }

    function selectPlace(id, focus) {
        var p = S.placeById[id];
        if (!p) return;
        play("select");
        selection = { type: "place", id: id };
        window.Map2D.setSelected(id);
        window.Map2D.setTemp(null);
        var c = S.catMap[p.cat] || { name: "Lugar", color: "#888", icon: "pin" };
        card(p.name, c.name, c.color, c.icon, p.desc, p.x, p.y, [
            gpsBtn(p.x, p.y, p.name, p.z),
        ].concat(S.isAdmin && p.src === "db" ? [btn("Editar lugar", "ghost", function () { adminEditPlace(p.id); })] : []));
        if (focus) focusOn(p.x, p.y);
    }

    // Clic en el mapa: se marca el punto y el GPS calcula la ruta al momento (se ve en el minimapa)
    function selectPoint(x, y) {
        play("select");
        selection = { type: "point", x: x, y: y };
        window.Map2D.setSelected(null);
        window.Map2D.setTemp(x, y);
        var k = known(x, y);
        var label = k ? (cellZone[cellOf(x, y)] || "Punto del mapa") : "Punto marcado";
        if (S.settings.gps !== 0) send("rp:map:ui:navigate", x, y, 0, label);
        var buttons = [btn("Quitar ruta", "ghost", function () { send("rp:map:ui:navStop"); closeCard(); })];
        if (S.isAdmin) buttons.push(btn("Crear lugar aquí", "primary", function () { adminNewPlace(x, y); }));
        card(k ? label : "Zona sin explorar", S.settings.gps !== 0 ? "Destino marcado · ruta en el minimapa" : "Punto del mapa", "#c55cff", "flag",
            k ? "" : "Aún no conoces esta zona; la ruta te lleva igualmente.", x, y, buttons);
    }

    // Clic derecho en el mapa: quita el destino y su ruta
    function clearDestination() {
        if (!route.active && !(selection && selection.type === "point")) return;
        play("click");
        if (route.active) send("rp:map:ui:navStop");
        closeCard();
    }

    // Atajos de admin desde la tarjeta: abren la pestaña Admin con el formulario listo
    function adminNewPlace(x, y) {
        adminForm.place = { x: x, y: y, z: 0, cat: "especial" };
        adminTab = "places";
        setTab("admin");
    }
    function adminEditPlace(id) {
        var p = S.placeById[id];
        if (!p) return;
        adminForm.place = { id: p.id, name: p.name, desc: p.desc, cat: p.cat, x: p.x, y: p.y, z: p.z, public: false };
        if (admin) admin.places.forEach(function (q) { if (q.id === p.id) adminForm.place.public = q.public; });
        adminTab = "places";
        setTab("admin");
    }

    function selectBuilding(b) {
        play("select");
        var best = null, bd = 90;
        S.places.forEach(function (p) {
            var d = Math.sqrt((p.x - b.x) * (p.x - b.x) + (p.y - b.y) * (p.y - b.y));
            if (d < bd) { bd = d; best = p; }
        });
        selection = { type: "building" };
        var desc = "Altura aproximada " + b.height + " m (unas " + b.floors + " plantas)." +
            (best ? " Aquí está: " + best.name + " (" + (S.catMap[best.cat] || { name: "" }).name + ")." : "");
        var buttons = [gpsBtn(b.x, b.y, best ? best.name : "Edificio")];
        if (best) buttons.push(btn("Ver " + best.name.slice(0, 18), "ghost", function () { selectPlace(best.id, false); }));
        card(best ? best.name : "Edificio", "Edificio · " + b.model, best ? (S.catMap[best.cat] || {}).color : "#9fb1c8",
            best ? (S.catMap[best.cat] || {}).icon : "building", desc, b.x, b.y, buttons);
    }

    function focusOn(x, y) {
        if (mode === "3d") window.Map3D.focus(x, y);
        else window.Map2D.centerOn(x, y, Math.max(window.Map2D.getView().s, 0.9));
    }

    // ---------------------------------------------------------------- seleccion en el mapa (formularios de admin)
    function startPick(text, fn) {
        pickMode = fn;
        $("pick-banner").textContent = text + "  (Esc del teclado cierra el mapa)";
        $("pick-banner").classList.remove("hidden");
    }
    function onMapClick(x, y) {
        if (pickMode) {
            var fn = pickMode;
            pickMode = null;
            $("pick-banner").classList.add("hidden");
            play("ok");
            return fn(x, y);
        }
        selectPoint(x, y);
    }

    // ---------------------------------------------------------------- estadisticas
    function renderStats() {
        var box = $("stats");
        box.textContent = "";
        var total = 0;
        for (var k in cityLand) total += cityLand[k];
        var ex = landExplored();
        var pct = S.settings.fog === 0 ? 100 : (total ? ex.n / total * 100 : 0);
        var big = el("div", "big-stat");
        big.appendChild(el("b", "", fmtPct(pct)));
        big.appendChild(el("span", "", "de San Andreas descubierto"));
        box.appendChild(big);
        var secs = sectorStats(), done = 0, part = 0, unk = 0;
        secs.forEach(function (s) { if (!s.land) return; if (s.state === 2) done++; else if (s.state === 1) part++; else unk++; });
        var discovered = S.places.length;
        var pending = Math.max(0, (S.totals.all || 0) - discovered);
        var grid = el("div", "stat-grid");
        [[done, "cuadrículas descubiertas"], [part, "cuadrículas a medias"], [unk, "cuadriculas desconocidas"],
            [ex.n, "celdas exploradas (50 m)"], [discovered, "lugares descubiertos"], [pending, "lugares pendientes"]]
            .forEach(function (it) {
                var b = el("div", "stat-box");
                b.appendChild(el("b", "", String(it[0])));
                b.appendChild(el("small", "", it[1]));
                grid.appendChild(b);
            });
        box.appendChild(grid);
        box.appendChild(el("div", "side-title", "Por territorio"));
        var knownByCity = {};
        S.places.forEach(function (p) { var c = cellCity[cellOf(p.x, p.y)]; if (c) knownByCity[c] = (knownByCity[c] || 0) + 1; });
        S.cities.forEach(function (city) {
            var land = cityLand[city] || 0;
            if (!land) return;
            var got = S.settings.fog === 0 ? land : (ex.byCity[city] || 0);
            var row = el("div", "prog-row");
            var h = el("div", "h");
            h.appendChild(el("span", "", city));
            var tot = S.totals.city ? (S.totals.city[city] || 0) : 0;
            h.appendChild(el("small", "", fmtPct(got / land * 100) + " · " + (knownByCity[city] || 0) + "/" + tot + " lugares"));
            row.appendChild(h);
            var bar = el("div", "bar"), fill = el("div");
            fill.style.width = (got / land * 100) + "%";
            bar.appendChild(fill);
            row.appendChild(bar);
            box.appendChild(row);
        });
        box.appendChild(el("div", "side-title", "Cuadrículas"));
        secs.filter(function (s) { return s.state > 0 && s.land > 0; }).sort(function (a, b) { return b.pct - a.pct; }).forEach(function (s) {
            var row = el("div", "prog-row");
            var h = el("div", "h");
            h.appendChild(el("span", "", s.id + " · " + s.name));
            h.appendChild(el("small", "", s.state === 2 ? "Descubierta" : fmtPct(s.pct)));
            row.appendChild(h);
            var bar = el("div", "bar"), fill = el("div");
            fill.style.width = Math.min(100, s.pct) + "%";
            bar.appendChild(fill);
            row.appendChild(bar);
            row.style.cursor = "pointer";
            row.addEventListener("click", function () {
                var sx = (S.sectors.indexOf(S.sectors.filter(function (q) { return q.id === s.id; })[0]));
                focusOn(-3000 + (sx % 12) * 500 + 250, 3000 - Math.floor(sx / 12) * 500 - 250);
            });
            box.appendChild(row);
        });
    }

    // ---------------------------------------------------------------- buscador (respeta la exploracion)
    var searchSel = 0, searchItems = [];
    function zoneKnown(z) {
        if (S.settings.fog === 0 || S.adminView) return z.cells[0];
        for (var i = 0; i < z.cells.length; i++) if (S.cells[z.cells[i]] || S.start[z.cells[i]]) return z.cells[i];
        return 0;
    }
    function norm(s) { return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, ""); }

    function runSearch(q) {
        var box = $("search-results");
        q = norm(q).trim();
        searchItems = [];
        if (q.length < 2) { box.classList.add("hidden"); return; }
        S.places.forEach(function (p) {
            var c = S.catMap[p.cat];
            if (norm(p.name).indexOf(q) >= 0 || (c && norm(c.name).indexOf(q) >= 0))
                searchItems.push({ t: p.name, s: (c ? c.name : "") + " · " + placeName(p.x, p.y), icon: c ? c.icon : "pin", color: c ? c.color : "#888",
                    go: function () { selectPlace(p.id, true); } });
        });
        S.zones.forEach(function (z) {
            if (norm(z.name).indexOf(q) < 0) return;
            var c = zoneKnown(z);
            if (!c) return;
            var i0 = c - 1;
            var x = -3000 + (i0 % N) * 50 + 25, y = 3000 - Math.floor(i0 / N) * 50 - 25;
            searchItems.push({ t: z.name, s: "Barrio · " + z.city, icon: "flag", color: "#9fb1c8", go: function () { focusOn(x, y); selectPoint(x, y); } });
        });
        S.cities.forEach(function (city) {
            if (norm(city).indexOf(q) < 0) return;
            var any = null;
            S.zones.forEach(function (z) { if (!any && z.city === city) { var c = zoneKnown(z); if (c) any = c; } });
            if (!any) return;
            var i0 = any - 1;
            var x = -3000 + (i0 % N) * 50 + 25, y = 3000 - Math.floor(i0 / N) * 50 - 25;
            searchItems.push({ t: city, s: "Territorio", icon: "building", color: "#ffe08a", go: function () { window.Map2D.centerOn(x, y, 0.3); window.Map3D.focus(x, y, 3500); } });
        });
        var secs = sectorStats();
        secs.forEach(function (s, idx) {
            if (s.state === 0) return;
            if (norm(s.id) === q || norm(s.name).indexOf(q) >= 0) {
                var x = -3000 + (idx % 12) * 500 + 250, y = 3000 - Math.floor(idx / 12) * 500 - 250;
                searchItems.push({ t: "Cuadrícula " + s.id, s: s.name + " · " + s.city, icon: "flag", color: "#f5a524", go: function () { focusOn(x, y); } });
            }
        });
        searchItems = searchItems.slice(0, 30);
        searchSel = 0;
        renderSearch();
    }

    function renderSearch() {
        var box = $("search-results");
        box.textContent = "";
        if (!searchItems.length) box.appendChild(el("div", "empty", "Nada conocido con ese nombre. Explora para descubrir mas lugares."));
        searchItems.forEach(function (it, i) {
            var r = el("div", "result" + (i === searchSel ? " sel" : ""));
            var dot = el("div", "dot");
            dot.style.background = it.color;
            dot.innerHTML = window.ICONS.svg(it.icon, 13);
            r.appendChild(dot);
            var t = el("div");
            t.appendChild(el("div", "", it.t));
            t.appendChild(el("small", "", it.s));
            r.appendChild(t);
            r.addEventListener("mousedown", function (ev) { ev.preventDefault(); chooseSearch(i); });
            box.appendChild(r);
        });
        box.classList.remove("hidden");
    }

    function chooseSearch(i) {
        var it = searchItems[i];
        if (!it) return;
        $("search-results").classList.add("hidden");
        $("search").blur();
        it.go();
    }

    // ---------------------------------------------------------------- GPS en el panel inferior
    function renderGps() {
        if (route.active) {
            $("b-gps").textContent = route.calculating ? "Calculando ruta a " + route.label : route.label + " · " + fmtDist(route.dist || 0);
            $("b-gps-stop").classList.remove("hidden");
        } else {
            $("b-gps").textContent = "Sin destino";
            $("b-gps-stop").classList.add("hidden");
        }
    }

    // ---------------------------------------------------------------- 2D / 3D
    function setMode(m, silent) {
        if (m === "3d" && (S.settings.mode3d === 0 || !window.Map3D.available())) {
            if (!silent) play("error");
            m = "2d";
        }
        mode = m;
        document.querySelectorAll("#mode-seg button").forEach(function (b) { b.classList.toggle("on", b.dataset.mode === m); });
        $("map2d").classList.toggle("hidden", m !== "2d");
        $("layer").classList.toggle("hidden", m !== "2d");
        $("map3d").classList.toggle("hidden", m !== "3d");
        $("help-3d").classList.toggle("hidden", m !== "3d");
        $("z-grid").classList.toggle("hidden", m !== "2d");
        window.Map2D.setActive(isOpen && m === "2d");
        window.Map3D.setActive(isOpen && m === "3d");
        if (m === "3d") {
            window.Map3D.setFog(S.cells, S.start, S.settings.fog !== 0 && !S.adminView);
            window.Map3D.setPlaces(S.places, S.catMap, hidden);
            window.Map3D.setRoute(route.active ? route.points : null, route.active ? [route.tx, route.ty] : null);
            if (player) { window.Map3D.setPlayer(player); }
            var v = window.Map2D.getView();
            window.Map3D.focus(v.cx, v.cy);
        }
        if (!silent) { play("click"); savePrefs(); }
    }

    // ---------------------------------------------------------------- preferencias
    var prefTimer = null;
    function savePrefs() {
        S.prefs.mode = mode;
        S.prefs.hidden = hidden;
        S.prefs.grid = $("z-grid").classList.contains("on");
        clearTimeout(prefTimer);
        prefTimer = setTimeout(function () { send("rp:map:ui:prefs", JSON.stringify(S.prefs)); }, 600);
    }

    // ---------------------------------------------------------------- tutorial (entrenador de primera vez)
    var COACH = [
        { el: "map-wrap", img: "mouse_move", text: "Arrastra con el ratón para mover el mapa." },
        { el: "map-wrap", img: "mouse_scroll", text: "Gira la rueda para acercarte o alejarte (o usa + y -)." },
        { el: "map-wrap", img: "mouse_left", text: "Haz clic en un icono o en cualquier punto para ver su información y poner una ruta GPS. Clic derecho quita el destino." },
        { el: "bottom", img: "mouse_left", text: "Lo oscuro aún no lo conoces: se descubre solo cuando caminas o conduces por ahí. Aquí ves cuánto llevas." },
        { el: "mode-seg", img: "mouse_left", text: "Cambia a 3D para ver los edificios con su altura real. En 3D, el botón derecho gira e inclina." },
        { el: "tabs", img: "mouse_left", text: "Aquí ves tus lugares cercanos y tu progreso por ciudad. Busca lugares arriba." },
    ];
    var coachStep = -1, coachSpot = null;
    function coachShow() {
        if (coachSpot) coachSpot.classList.remove("coach-spot");
        if (coachStep < 0 || coachStep >= COACH.length) {
            $("coach").classList.add("hidden");
            coachStep = -1;
            return;
        }
        var st = COACH[coachStep];
        coachSpot = $(st.el);
        coachSpot.classList.add("coach-spot");
        $("coach").classList.remove("hidden");
        $("coach-step").textContent = "Paso " + (coachStep + 1) + " de " + COACH.length;
        $("coach-img").src = "images/keys/" + st.img + ".png";
        $("coach-text").textContent = st.text;
        $("coach-next").textContent = coachStep === COACH.length - 1 ? "Entendido" : "Siguiente";
        // coordenadas relativas a la ventana (que esta transformada)
        var wr = $("win").getBoundingClientRect(), sr = coachSpot.getBoundingClientRect(), cw = 320, ch = 170;
        var r = { left: sr.left - wr.left, top: sr.top - wr.top, width: sr.width, height: sr.height, bottom: sr.bottom - wr.top };
        var x = Math.min(wr.width - cw - 12, Math.max(12, r.left + r.width / 2 - cw / 2));
        var y = r.bottom + 12 + ch < wr.height ? r.bottom + 12 : Math.max(12, r.top - ch - 12);
        if (r.height > 300) y = r.top + r.height / 2 - ch / 2;
        $("coach-card").style.left = x + "px";
        $("coach-card").style.top = y + "px";
        play("step");
    }
    function coachEnd() {
        coachStep = COACH.length;
        coachShow();
        S.prefs.tutorial = true;
        savePrefs();
    }
    $("coach-next").addEventListener("click", function () { coachStep++; if (coachStep >= COACH.length) coachEnd(); else coachShow(); });
    $("coach-skip").addEventListener("click", coachEnd);

    // ---------------------------------------------------------------- admin
    function adminInput(label, value, type) {
        var l = el("label", "", label);
        var i = el("input", "inp");
        i.type = type || "text";
        if (value !== undefined && value !== null) i.value = value;
        l.appendChild(i);
        return { label: l, input: i };
    }
    function adminCheck(label, on) {
        var l = el("label", "check");
        var i = el("input");
        i.type = "checkbox";
        i.checked = !!on;
        l.appendChild(i);
        l.appendChild(document.createTextNode(label));
        return { label: l, input: i };
    }
    function adminSelect(label, options, value) {
        var l = el("label", "", label);
        var s = el("select", "inp");
        options.forEach(function (o) {
            var op = el("option", "", o[1]);
            op.value = o[0];
            if (String(o[0]) === String(value)) op.selected = true;
            s.appendChild(op);
        });
        l.appendChild(s);
        return { label: l, input: s };
    }
    function confirmBtn(text, fn) {
        var armed = false;
        var b = btn(text, "danger-btn", function () {
            if (!armed) { armed = true; b.textContent = "¿Seguro? Pulsa otra vez"; setTimeout(function () { armed = false; b.textContent = text; }, 3000); return; }
            fn();
        });
        return b;
    }

    function renderAdmin() {
        var box = $("admin-body");
        box.textContent = "";
        document.querySelectorAll("#admin-seg button").forEach(function (b) { b.classList.toggle("on", b.dataset.a === adminTab); });
        if (!admin) { box.appendChild(el("div", "empty", "Cargando datos de administracion...")); return; }
        ({ places: adminPlaces, cats: adminCats, sectors: adminSectors, settings: adminSettings, players: adminPlayers })[adminTab](box);
    }

    function adminPlaces(box) {
        var f = adminForm.place || {};
        var form = el("div", "form");
        form.appendChild(el("div", "side-title", f.id ? "Editar lugar #" + f.id : "Nuevo lugar"));
        var name = adminInput("Nombre", f.name), desc = adminInput("Descripcion", f.desc);
        var cat = adminSelect("Categoría", admin.cats.map(function (c) { return [c.key, c.name]; }), f.cat || "especial");
        var two = el("div", "two");
        var x = adminInput("X", f.x !== undefined ? Math.round(f.x * 10) / 10 : "", "number");
        var y = adminInput("Y", f.y !== undefined ? Math.round(f.y * 10) / 10 : "", "number");
        var z = adminInput("Z", f.z !== undefined ? Math.round(f.z * 10) / 10 : 0, "number");
        two.appendChild(x.label); two.appendChild(y.label); two.appendChild(z.label);
        var pub = adminCheck("Visible desde el inicio (sin explorar)", f.public);
        [name.label, desc.label, cat.label, two, pub.label].forEach(function (n) { form.appendChild(n); });
        name.input.maxLength = 48; desc.input.maxLength = 255;
        function read() {
            return { id: f.id, name: name.input.value, desc: desc.input.value, cat: cat.input.value,
                x: parseFloat(x.input.value), y: parseFloat(y.input.value), z: parseFloat(z.input.value) || 0, public: pub.input.checked };
        }
        var bt = el("div", "btns");
        bt.appendChild(btn("Mi posicion", "ghost", function () {
            if (!player) return;
            adminForm.place = read(); adminForm.place.x = player.x; adminForm.place.y = player.y; adminForm.place.z = player.z; renderAdmin();
        }));
        bt.appendChild(btn("Elegir en mapa", "ghost", function () {
            adminForm.place = read();
            startPick("Haz clic donde va el lugar", function (px, py) { adminForm.place.x = px; adminForm.place.y = py; renderAdmin(); });
        }));
        bt.appendChild(btn("Guardar", "primary", function () { send("rp:map:ui:admin", "placeSave", JSON.stringify(read())); }));
        if (f.id) {
            bt.appendChild(btn("Nuevo", "ghost", function () { adminForm.place = {}; renderAdmin(); }));
            bt.appendChild(confirmBtn("Borrar", function () { send("rp:map:ui:admin", "placeDelete", String(f.id)); adminForm.place = {}; }));
        }
        form.appendChild(bt);
        box.appendChild(form);
        var filter = adminInput("Buscar en " + admin.places.length + " lugares", adminForm.placeFilter || "");
        box.appendChild(filter.label);
        var list = el("div", "admin-list");
        function fill() {
            list.textContent = "";
            var q = norm(filter.input.value);
            admin.places.filter(function (p) { return !q || norm(p.name).indexOf(q) >= 0; }).slice(0, 200).forEach(function (p) {
                var row = placeRow(p, (p.public ? "público · " : "") + "#" + p.id);
                row.onclick = null;
                row.addEventListener("click", function (ev) {
                    ev.stopPropagation();
                    adminForm.place = { id: p.id, name: p.name, desc: p.desc, cat: p.cat, x: p.x, y: p.y, z: p.z, public: p.public };
                    focusOn(p.x, p.y);
                    renderAdmin();
                });
                list.appendChild(row);
            });
        }
        filter.input.addEventListener("input", function () { adminForm.placeFilter = filter.input.value; fill(); });
        fill();
        box.appendChild(list);
    }

    function adminCats(box) {
        var f = adminForm.cat || { color: "#f5a524", icon: "star" };
        var form = el("div", "form");
        form.appendChild(el("div", "side-title", f.editing ? "Editar categoría" : "Nueva categoría"));
        var key = adminInput("Clave (minusculas, sin espacios)", f.key);
        key.input.maxLength = 24;
        if (f.editing) key.input.disabled = true;
        var name = adminInput("Nombre", f.name);
        name.input.maxLength = 40;
        var color = adminInput("Color", f.color, "color");
        var pub = adminCheck("Visible desde el inicio (sin explorar)", f.public);
        var picker = el("div", "icon-pick");
        var icon = f.icon;
        admin.icons.forEach(function (ic) {
            var b = el("button", ic === icon ? "on" : "");
            b.innerHTML = window.ICONS.svg(ic, 15);
            b.title = ic;
            b.addEventListener("click", function () {
                icon = ic;
                picker.querySelectorAll("button").forEach(function (q) { q.classList.toggle("on", q.title === ic); });
            });
            picker.appendChild(b);
        });
        [key.label, name.label, color.label, el("label", "", "Icono"), picker, pub.label].forEach(function (n) { form.appendChild(n); });
        var bt = el("div", "btns");
        bt.appendChild(btn("Guardar", "primary", function () {
            send("rp:map:ui:admin", "catSave", JSON.stringify({ key: key.input.value.trim(), name: name.input.value, color: color.input.value, icon: icon, public: pub.input.checked }));
        }));
        if (f.editing) {
            bt.appendChild(btn("Nueva", "ghost", function () { adminForm.cat = null; renderAdmin(); }));
            bt.appendChild(confirmBtn("Borrar", function () { send("rp:map:ui:admin", "catDelete", f.key); adminForm.cat = null; }));
        }
        form.appendChild(bt);
        box.appendChild(form);
        var list = el("div", "admin-list");
        admin.cats.forEach(function (c) {
            var row = el("div", "row");
            var dot = el("div", "dot");
            dot.style.background = c.color;
            dot.innerHTML = window.ICONS.svg(c.icon, 14);
            row.appendChild(dot);
            var t = el("div", "txt");
            t.appendChild(el("div", "", c.name));
            t.appendChild(el("small", "", c.key + (c.public ? " · pública" : "")));
            row.appendChild(t);
            row.addEventListener("click", function () {
                adminForm.cat = { editing: true, key: c.key, name: c.name, color: c.color, icon: c.icon, public: c.public };
                renderAdmin();
            });
            list.appendChild(row);
        });
        box.appendChild(list);
    }

    function adminSectors(box) {
        var idx = adminForm.sector !== undefined ? adminForm.sector : -1;
        var form = el("div", "form");
        form.appendChild(el("div", "side-help", "Elige una cuadrícula en la lista o pulsa \"Elegir en mapa\"."));
        var sel = adminSelect("Cuadrícula", [[-1, "-"]].concat(admin.sectors.map(function (s, i) { return [i, s.id + " · " + (s.customName || s.name)]; })), idx);
        sel.input.addEventListener("change", function () { adminForm.sector = +sel.input.value; renderAdmin(); });
        form.appendChild(sel.label);
        form.appendChild(btn("Elegir en mapa", "ghost", function () {
            startPick("Haz clic en la cuadrícula", function (x, y) { adminForm.sector = sectorOf(x, y); renderAdmin(); });
        }));
        if (idx >= 0) {
            var s = admin.sectors[idx];
            var name = adminInput("Nombre (vacio = " + s.name + ")", s.customName || "");
            name.input.maxLength = 40;
            var city = adminSelect("Territorio", [["", "Automático (" + s.city + ")"]].concat(admin.cities.map(function (c) { return [c, c]; })), s.customCity || "");
            var rev = adminCheck("Visible para todos desde el inicio", s.revealed);
            [name.label, city.label, rev.label].forEach(function (n) { form.appendChild(n); });
            form.appendChild(el("small", "", "Celdas de tierra: " + s.land + " (" + s.land * 2500 / 1e6 + " km²)"));
            var bt = el("div", "btns");
            bt.appendChild(btn("Guardar", "primary", function () {
                send("rp:map:ui:admin", "sectorSave", JSON.stringify({ name: name.input.value, city: city.input.value || null, revealed: rev.input.checked }), s.id);
            }));
            bt.appendChild(btn("Ver", "ghost", function () { focusOn(-3000 + (idx % 12) * 500 + 250, 3000 - Math.floor(idx / 12) * 500 - 250); }));
            form.appendChild(bt);
        }
        box.appendChild(form);
    }

    function adminSettings(box) {
        var st = admin.settings, defs = admin.defs;
        var form = el("div", "form");
        var radius = adminInput("Radio de exploración (m, " + defs.radius[2] + "-" + defs.radius[3] + ")", st.radius, "number");
        var interval = adminInput("Intervalo de exploración (ms, " + defs.interval[2] + "-" + defs.interval[3] + ")", st.interval, "number");
        var checks = [["fog", "Niebla de exploracion (si se apaga, todo el mapa se ve)"], ["gps", "GPS"], ["mode3d", "Vista 3D"],
            ["music", "Tema de fondo con el mapa abierto"], ["blips", "Importar tiendas, bencineras, talleres, cajeros..."], ["houses", "Mostrar casas de rp_properties"]]
            .map(function (c) { var ch = adminCheck(c[1], st[c[0]] === 1); ch.key = c[0]; return ch; });
        form.appendChild(radius.label);
        form.appendChild(interval.label);
        checks.forEach(function (c) { form.appendChild(c.label); });
        form.appendChild(btn("Guardar ajustes", "primary", function () {
            var data = { radius: +radius.input.value, interval: +interval.input.value };
            checks.forEach(function (c) { data[c.key] = c.input.checked ? 1 : 0; });
            send("rp:map:ui:admin", "settingsSave", JSON.stringify(data));
        }));
        box.appendChild(form);
    }

    function adminPlayers(box) {
        var form = el("div", "form");
        var q = adminInput("Jugador (id o nombre) o id de personaje", adminForm.playerQuery || "");
        form.appendChild(q.label);
        form.appendChild(btn("Consultar progreso", "primary", function () {
            adminForm.playerQuery = q.input.value;
            adminForm.player = undefined;
            send("rp:map:ui:admin", "playerQuery", q.input.value);
        }));
        box.appendChild(form);
        var info = adminForm.player;
        if (info === null) box.appendChild(el("div", "empty", "No encontrado."));
        else if (info) {
            var c = el("div", "stat-box");
            c.appendChild(el("b", "", info.name + " · " + fmtPct(info.pct)));
            c.appendChild(el("small", "", "Personaje #" + info.cid + (info.online ? " (conectado)" : "") + " · " + info.land + " celdas de tierra" +
                (info.sectors !== undefined ? " · " + info.sectors + " cuadrículas completas" : "")));
            box.appendChild(c);
            var bt = el("div", "btns");
            bt.style.marginTop = "8px";
            bt.appendChild(confirmBtn("Reiniciar exploracion", function () { send("rp:map:ui:admin", "playerReset", String(info.cid)); }));
            box.appendChild(bt);
        }
    }

    // ---------------------------------------------------------------- vista admin / jugador (/mapajugador)
    function renderView() {
        var b = $("view-toggle");
        b.classList.toggle("hidden", !S.isAdmin);
        b.textContent = S.adminView ? "Vista: Admin" : "Vista: Jugador";
        b.title = S.adminView ? "Ves todos los lugares y todo el mapa. Clic (o /mapajugador) para verlo como un jugador normal."
            : "Ves solo lo que tu personaje ha descubierto. Clic (o /mapajugador) para volver a la vista de admin.";
        b.classList.toggle("player", !S.adminView);
    }

    // ---------------------------------------------------------------- pestañas
    function setTab(t) {
        tab = t;
        document.querySelectorAll("#tabs button").forEach(function (b) { b.classList.toggle("on", b.dataset.tab === t); });
        ["places", "stats", "admin"].forEach(function (p) { $("page-" + p).classList.toggle("hidden", p !== t); });
        if (t === "stats") renderStats();
        if (t === "admin") { send("rp:map:ui:admin", "open", ""); renderAdmin(); }
    }

    // ---------------------------------------------------------------- eventos de la interfaz
    function bindUi() {
        $("btn-close").addEventListener("click", function () { send("rp:map:ui:close"); });
        document.addEventListener("keydown", function (e) {
            if (e.key === "Escape" || e.key === "F11") { e.preventDefault(); send("rp:map:ui:close"); return; }
            if (document.activeElement === $("search")) {
                if (e.key === "ArrowDown") { searchSel = Math.min(searchItems.length - 1, searchSel + 1); renderSearch(); e.preventDefault(); }
                else if (e.key === "ArrowUp") { searchSel = Math.max(0, searchSel - 1); renderSearch(); e.preventDefault(); }
                else if (e.key === "Enter") chooseSearch(searchSel);
            }
        });
        $("search").addEventListener("input", function () { runSearch(this.value); });
        $("search").addEventListener("focus", function () { if (this.value.length >= 2) runSearch(this.value); });
        $("search").addEventListener("blur", function () { setTimeout(function () { $("search-results").classList.add("hidden"); }, 120); });
        document.querySelectorAll("#mode-seg button").forEach(function (b) { b.addEventListener("click", function () { setMode(b.dataset.mode); }); });
        document.querySelectorAll("#tabs button").forEach(function (b) { b.addEventListener("click", function () { play("click"); setTab(b.dataset.tab); }); });
        document.querySelectorAll("#admin-seg button").forEach(function (b) { b.addEventListener("click", function () { play("click"); adminTab = b.dataset.a; renderAdmin(); }); });
        $("z-in").addEventListener("click", function () { play("click"); if (mode === "3d") window.Map3D.zoom(1.5); else window.Map2D.zoom(1.6); });
        $("z-out").addEventListener("click", function () { play("click"); if (mode === "3d") window.Map3D.zoom(1 / 1.5); else window.Map2D.zoom(1 / 1.6); });
        $("z-me").addEventListener("click", function () { play("click"); if (player) focusOn(player.x, player.y); });
        $("z-grid").addEventListener("click", function () {
            play("click");
            var on = !this.classList.contains("on");
            this.classList.toggle("on", on);
            window.Map2D.setGrid(on);
            savePrefs();
        });
        $("cats-all").addEventListener("click", function () { hidden = {}; savePrefs(); refreshPlaces(); });
        $("view-toggle").addEventListener("click", function () { play("click"); send("rp:map:ui:admin", "view", ""); });
        $("b-gps-stop").addEventListener("click", function () { play("click"); send("rp:map:ui:navStop"); });
    }

    var tipEl = $("sector-tip");
    function onHover(x, y, sec, px, py) {
        if (x === null || x === undefined) { tipEl.classList.add("hidden"); $("b-cursor").textContent = "-"; return; }
        var d = distTo(x, y);
        $("b-cursor").textContent = Math.round(x) + ", " + Math.round(y) + (d !== null ? " · a " + fmtDist(d) : "");
        if (sec < 0 || !S.sectors[sec] || !$("z-grid").classList.contains("on")) { tipEl.classList.add("hidden"); return; }
        var st = sectorStats()[sec];
        tipEl.textContent = "";
        var s = S.sectors[sec];
        var stateTxt = ["Desconocida", "Parcialmente explorada", "Descubierta"][st.state];
        var stateCol = ["#6f7888", "#f5a524", "#4cd38a"][st.state];
        var head = el("div", "st", stateTxt);
        head.style.color = stateCol;
        tipEl.appendChild(head);
        tipEl.appendChild(el("b", "", "Cuadrícula " + s.id + (st.state > 0 ? " · " + s.name : "")));
        var placesIn = 0;
        S.places.forEach(function (p) { if (sectorOf(p.x, p.y) === sec) placesIn++; });
        tipEl.appendChild(el("div", "", (st.state > 0 ? s.city + " · " : "") + (s.land ? fmtPct(Math.min(100, st.pct)) + " explorada" : "Agua") +
            " · " + placesIn + " lugares"));
        tipEl.style.left = Math.min(px + 18, $("map-wrap").clientWidth - 220) + "px";
        tipEl.style.top = Math.min(py + 18, $("map-wrap").clientHeight - 80) + "px";
        tipEl.classList.remove("hidden");
    }

    // ---------------------------------------------------------------- API para Lua
    function applyState(st) {
        S.land = st.land || S.land;
        S.cells = {}; (st.cells || []).forEach(function (i) { S.cells[i] = true; });
        S.start = {}; (st.start || []).forEach(function (i) { S.start[i] = true; });
        S.places = st.places || [];
        S.cats = st.cats || [];
        S.catMap = {}; S.cats.forEach(function (c) { S.catMap[c.key] = c; });
        S.sectors = st.sectors || [];
        S.zones = st.zones || S.zones;
        S.settings = st.settings || {};
        S.adminView = !!st.adminView;
        S.prefs = st.prefs || {};
        S.totals = st.totals || { all: 0, city: {} };
        S.isAdmin = !!st.isAdmin;
        S.cities = st.cities || [];
        S.discoveredPct = st.discoveredPct || 90;
        hidden = {};
        if (S.prefs.hidden) for (var k in S.prefs.hidden) if (S.prefs.hidden[k]) hidden[k] = true;
        rebuildZones();
    }

    window.RP = {
        open: function (st) {
            var wasOpen = isOpen;
            applyState(st);
            isOpen = true;
            document.body.classList.add("open");
            $("win").classList.remove("hidden");
            $("tab-admin").classList.toggle("hidden", !S.isAdmin);
            if (!S.isAdmin && tab === "admin") setTab("places");
            var grid = S.prefs.grid !== false;
            $("z-grid").classList.toggle("on", grid);
            window.Map2D.setGrid(grid);
            $("mode-seg").querySelector('[data-mode="3d"]').disabled = S.settings.mode3d === 0;
            refreshFog();
            refreshPlaces();
            renderView();
            renderGps();
            setMode(wasOpen ? mode : (S.prefs.mode || "2d"), true);
            if (!wasOpen) {
                play("open");
                firstCenter = true;
                closeCard();
                if (!S.prefs.tutorial) { coachStep = 0; setTimeout(coachShow, 450); }
            }
            if (tab === "stats") renderStats();
            if (tab === "admin") renderAdmin();
        },
        close: function () {
            if (!isOpen) return;
            isOpen = false;
            play("close");
            pickMode = null;
            $("pick-banner").classList.add("hidden");
            if (coachStep >= 0) { if (coachSpot) coachSpot.classList.remove("coach-spot"); $("coach").classList.add("hidden"); }
            document.body.classList.remove("open");
            window.Map2D.setActive(false);
            window.Map3D.setActive(false);
            setTimeout(function () { if (!isOpen) $("win").classList.add("hidden"); }, 230);
        },
        player: function (p) {
            var first = !player;
            player = p;
            $("b-pos").textContent = p.inside ? "Interior" : Math.round(p.x * 10) / 10 + ", " + Math.round(p.y * 10) / 10 + ", " + Math.round(p.z * 10) / 10;
            $("b-head").textContent = heading(p.rot);
            $("top-zone").textContent = p.inside ? "Interior" : p.zone + ", " + p.city;
            window.Map2D.setPlayer(p);
            window.Map3D.setPlayer(p);
            if (firstCenter && isOpen) {
                firstCenter = false;
                if (!p.inside) { window.Map2D.jumpTo(p.x, p.y, 0.9); window.Map3D.focus(p.x, p.y, 1400); }
            }
            if (first || Math.random() < 0.05) renderNear();
        },
        cells: function (list, newPlaces) {
            (list || []).forEach(function (i) { S.cells[i] = true; });
            (newPlaces || []).forEach(function (p) { if (!S.placeById[p.id]) S.places.push(p); });
            refreshFog();
            if (newPlaces && newPlaces.length) { refreshPlaces(); play("ok"); }
        },
        places: function (list, totals) {
            S.places = list || [];
            S.totals = totals || S.totals;
            refreshPlaces();
            if (selection && selection.type === "place" && !S.placeById[selection.id]) closeCard();
            if (tab === "stats") renderStats();
        },
        route: function (r) {
            route = r || { active: false };
            window.Map2D.setRoute(route.active ? route.points : null, route.active ? [route.tx, route.ty] : null);
            window.Map3D.setRoute(route.active ? route.points : null, route.active ? [route.tx, route.ty] : null);
            renderGps();
        },
        navDist: function (d) { if (route.active) { route.dist = d; route.calculating = false; renderGps(); } },
        adminData: function (data) {
            admin = data;
            if (admin && admin.places) admin.places.sort(function (a, b) { return a.name.localeCompare(b.name); });
            if (tab === "admin") renderAdmin();
        },
        adminPlayer: function (info) { adminForm.player = info; if (tab === "admin" && adminTab === "players") renderAdmin(); },
    };

    // ---------------------------------------------------------------- arranque
    window.Map3D.setup($("map3d"), {
        onPlace: function (id) { selectPlace(id, false); },
        onBuilding: selectBuilding,
        onClick: onMapClick,
        onRightClick: clearDestination,
    });
    window.Map2D.init($("map2d"), $("layer"), $("map-wrap"), {
        onClick: onMapClick,
        onRightClick: clearDestination,
        onHover: onHover,
        onPlace: function (id) { selectPlace(id, false); },
        onBase: function () { window.Map3D.refreshTexture(); },
        onFog: function () { window.Map3D.refreshTexture(); },
        onMissing: function () { $("nofile").classList.remove("hidden"); },
    });
    if (!window.MAP_ROADS || !window.MAP_BUILDINGS || !window.MAP_TERRAIN) $("nofile").classList.remove("hidden");
    bindUi();
    send("rp:map:ui:ready");

    // Vista previa en un navegador normal: index.html#demo
    if (!window.mta && location.hash.indexOf("demo") >= 0) {
        var land = window.MAP_TERRAIN ? window.MAP_TERRAIN.a : new Array(14401).join("1");
        var cells = [];
        for (var cy = 88; cy < 106; cy++) for (var cx = 84; cx < 110; cx++) cells.push(cy * N + cx + 1);
        var zones = [{ name: "El Corona", city: "Los Santos", cells: cells.slice(0, 200) }, { name: "Idlewood", city: "Los Santos", cells: cells.slice(200) }];
        var sectors = [];
        for (var s = 0; s < 144; s++) sectors.push({ id: "ABCDEFGHIJKL"[s % 12] + (Math.floor(s / 12) + 1), name: "Sector " + s, city: "Los Santos", land: 100 });
        var cats = [{ key: "hospital", name: "Hospitales", icon: "hospital", color: "#ff4d5e", public: true },
            { key: "policia", name: "Comisarías", icon: "police", color: "#4d8dff", public: true },
            { key: "gasolinera", name: "Gasolineras", icon: "fuel", color: "#ffd84d" },
            { key: "gimnasio", name: "Gimnasios", icon: "gym", color: "#5fe0a0" }];
        window.RP.open({ land: land, cells: cells, start: [], cats: cats, sectors: sectors, zones: zones, cities: ["Los Santos", "San Fierro"],
            places: [{ id: 1, name: "All Saints General Hospital", cat: "hospital", x: 1172, y: -1323, z: 15, desc: "Hospital de Market." },
                { id: 2, name: "Comisaría LSPD", cat: "policia", x: 1555, y: -1675, z: 16, desc: "Pershing Square." },
                { id: 3, name: "Gasolinera de Idlewood", cat: "gasolinera", x: 1940, y: -1773, z: 13, desc: "" },
                { id: 4, name: "Gimnasio de Ganton", cat: "gimnasio", x: 2229, y: -1721, z: 13, desc: "" }],
            settings: { fog: 1, gps: 1, mode3d: 1 },
            prefs: { tutorial: location.hash.indexOf("tuto") < 0 }, totals: { all: 40, city: { "Los Santos": 25 } }, isAdmin: true });
        window.RP.player({ x: 1742, y: -1861, z: 13.5, rot: 30, zone: "El Corona", city: "Los Santos", inside: false });
        window.RP.route({ active: true, label: "Gimnasio de Ganton", tx: 2229, ty: -1721, dist: 720,
            points: [1742, -1861, 1820, -1861, 1820, -1740, 2050, -1740, 2229, -1721] });
        if (location.hash.indexOf("3d") >= 0) setMode("3d", true);
    }
})();
