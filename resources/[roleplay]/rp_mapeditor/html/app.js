/*
    rp_mapeditor / app.js
    Una sola página para los cinco navegadores, con la organización del editor de mapas de MTA:
        #top    barra de iconos (arriba a la izquierda)
        #dock   columna de tipos de elemento (izquierda)
        #win    ventana flotante: navegador de modelos, opciones de marcador/pickup/punto o lista
        #props  ventana flotante: propiedades de lo elegido (doble clic o Enter)
        #modal  proyectos, ajustes, versiones, importar y exportar
    Lua -> JS: ME.recv(tipo, datos)        JS -> Lua: send(accion, objeto)
    Los tooltips los dibuja Lua (send("hover")): las barras son demasiado estrechas para mostrarlos.
    Modo demo en un navegador normal: index.html?demo#win (o #top, #dock, #props, #modal).
*/
(function () {
    "use strict";
    var PANEL = (location.hash || "#win").slice(1);
    var DEMO = location.search.indexOf("demo") !== -1;
    var S = {
        catalog: { vehicles: [], peds: [], anims: [], favorites: [], recents: [] },
        project: null, settings: {}, editors: [], state: {}, selection: [], selected: [], rows: [],
        tab: "objects", group: "fav", query: "", thumbs: {}, view: "browser", browser: null, versions: null, exported: null,
        other: { etype: "marker", mtype: "cylinder", size: 1.5, color: "#ffc83c", alpha: 160, icon: "", label: "", ptype: 0, amount: 100, ammo: 50, respawn: 30000, name: "punto" }
    };

    function send(action, obj) {
        var json = JSON.stringify(obj || {});
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent("rp:me:ui", action, json);
        else console.log("[demo] ->", action, json);
    }
    function sound(name) { try { var a = new Audio("sounds/" + name + ".ogg"); a.volume = 0.5; a.play(); } catch (e) { } }
    function $(id) { return document.getElementById(id); }
    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined && text !== null) e.textContent = text;
        return e;
    }
    function btn(text, onClick, cls) {
        var b = el("button", cls || "", text);
        b.addEventListener("click", function (ev) { ev.stopPropagation(); sound("click_002"); onClick(ev); });
        return b;
    }
    function input(type, value, onChange, attrs) {
        var i = el("input");
        i.type = type;
        if (type === "checkbox") i.checked = !!value; else i.value = value === undefined || value === null ? "" : value;
        for (var k in (attrs || {})) i.setAttribute(k, attrs[k]);
        i.addEventListener("change", function () { onChange(type === "checkbox" ? i.checked : i.value, i); });
        return i;
    }
    function row(label, control) {
        var l = el("label", "row");
        l.appendChild(el("span", "", label));
        l.appendChild(control);
        return l;
    }
    function num(v, d) { var n = parseFloat(v); return isNaN(n) ? d : n; }
    function fixed(v) { return Math.round(num(v, 0) * 1000) / 1000; }
    function hexToRgb(h) { h = (h || "#ffffff").replace("#", ""); return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)]; }
    function rgbToHex(c) { c = c || [255, 255, 255]; return "#" + [0, 1, 2].map(function (i) { var s = (c[i] | 0).toString(16); return s.length < 2 ? "0" + s : s; }).join(""); }
    function clone(o) { return JSON.parse(JSON.stringify(o)); }

    // Diálogos propios (CEF de MTA no garantiza confirm/prompt)
    function overlay(msg, withInput, def, onOk) {
        var o = el("div", "ask"), b = el("div", "askbox");
        b.appendChild(el("div", "", msg));
        var i = null;
        if (withInput) { i = input("text", def, function () { }, { maxlength: "48" }); b.appendChild(i); }
        var f = el("div", "flex"); f.style.marginTop = "10px"; f.style.justifyContent = "flex-end";
        f.appendChild(btn("Cancelar", function () { o.remove(); }));
        f.appendChild(btn("Aceptar", function () { var v = i ? i.value.trim() : true; o.remove(); if (v) onOk(v); }, "primary"));
        b.appendChild(f); o.appendChild(b); document.body.appendChild(o);
        if (i) i.focus();
        sound("question_001");
    }
    function ask(msg, onYes) { overlay(msg, false, null, onYes); }
    // Desde las barras (navegadores pequeños) la pregunta se abre centrada en la ventana modal;
    // al aceptar, Lua ejecuta la acción indicada
    function askModal(msg, action, data) { send("confirm", { text: msg, action: action, data: data || {} }); }
    function askText(msg, def, onOk) { overlay(msg, true, def, onOk); }

    var TYPE_NAMES = { object: "Objeto", vehicle: "Vehículo", ped: "Ped", marker: "Marcador", pickup: "Pickup", point: "Punto", removal: "Quitado" };

    /* ---------- Iconos (SVG propios, trazo de 2 px) ---------- */
    var ICONS = {
        folder: "M3 6h6l2 2h10v11H3z",
        publish: "M12 16V4M7 9l5-5 5 5M4 20h16",
        gear: "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2",
        history: "M3 12a9 9 0 1 0 3-6.7M3 4v5h5M12 7v5l3 3",
        swap: "M7 4v13M3 13l4 4 4-4M17 20V7M13 11l4-4 4 4",
        undo: "M9 14L4 9l5-5M4 9h10a6 6 0 0 1 0 12h-3",
        redo: "M15 14l5-5-5-5M20 9H10a6 6 0 0 0 0 12h3",
        move: "M12 2v20M2 12h20M12 2l-3 3M12 2l3 3M12 22l-3-3M12 22l3-3M2 12l3-3M2 12l3 3M22 12l-3-3M22 12l-3 3",
        rotate: "M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5",
        scale: "M4 14v6h6M4 20l7-7M20 10V4h-6M20 4l-7 7",
        axes: "M12 12V3M12 12l8 5M12 12l-8 5",
        grid: "M4 4h16v16H4zM4 10h16M4 15h16M10 4v16M15 4v16",
        list: "M8 6h13M8 12h13M8 18h13M3 6h1M3 12h1M3 18h1",
        play: "M7 4l13 8-13 8z",
        exit: "M15 4h4v16h-4M10 8l-4 4 4 4M6 12h10",
        cube: "M12 2l9 5v10l-9 5-9-5V7zM12 12l9-5M12 12v10M12 12L3 7",
        car: "M3 14l2-6h14l2 6v4H3zM6 18v2M18 18v2M7 14h.01M17 14h.01M3 14h18",
        ped: "M12 3a2 2 0 1 1 0 4 2 2 0 0 1 0-4zM8 22l2-8-3-3 5-2 5 2-3 3 2 8M12 9v5",
        marker: "M12 2a6 6 0 0 1 6 6c0 5-6 12-6 12S6 13 6 8a6 6 0 0 1 6-6zM12 6a2 2 0 1 0 0 4 2 2 0 0 0 0-4z",
        pickup: "M12 21s-8-5-8-11a4 4 0 0 1 8-1 4 4 0 0 1 8 1c0 6-8 11-8 11z",
        point: "M5 22V3M5 4h12l-3 4 3 4H5",
        eraser: "M20 20H9L3 14l10-10 8 8-7 8M7 10l7 7",
        close: "M6 6l12 12M18 6L6 18"
    };
    function icon(name) {
        var ns = "http://www.w3.org/2000/svg";
        var svg = document.createElementNS(ns, "svg");
        svg.setAttribute("viewBox", "0 0 24 24");
        var p = document.createElementNS(ns, "path");
        p.setAttribute("d", ICONS[name] || "");
        svg.appendChild(p);
        return svg;
    }
    // Botón de icono con tooltip (lo dibuja Lua junto al cursor)
    function ibtn(name, tip, onClick, on, disabled) {
        var b = el("button", "ib" + (on ? " on" : ""));
        b.appendChild(icon(name));
        b.disabled = !!disabled;
        b.addEventListener("click", function (ev) { ev.stopPropagation(); if (b.disabled) return; sound("click_002"); onClick(ev); });
        b.addEventListener("mouseenter", function () { send("hover", { text: tip }); });
        b.addEventListener("mouseleave", function () { send("hover", { text: "" }); });
        return b;
    }

    // El teclado va al panel solo mientras escribes en un campo
    document.addEventListener("focusin", function (e) {
        if (/INPUT|TEXTAREA|SELECT/.test(e.target.tagName) && e.target.type !== "checkbox") send("typing", { on: true, panel: PANEL });
    });
    document.addEventListener("focusout", function (e) {
        if (/INPUT|TEXTAREA|SELECT/.test(e.target.tagName)) send("typing", { on: false });
    });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Enter" && e.target.tagName === "INPUT") e.target.blur();
        if (e.key === "Escape" && PANEL === "modal" && !/INPUT|TEXTAREA/.test(e.target.tagName)) closeModal();
    });

    function winHeader(title, closeAction) {
        var h = el("div", "whead");
        h.appendChild(el("b", "", title));
        var x = el("button", "ib small");
        x.appendChild(icon("close"));
        x.addEventListener("click", function () { sound("click_002"); send(closeAction); });
        h.appendChild(x);
        return h;
    }

    /* ================= Barra superior ================= */
    function renderTop() {
        var app = $("app"), st = S.state, P = S.project || {};
        app.innerHTML = "";
        var bar = el("div", "top");
        var g = el("div", "grp");
        g.appendChild(ibtn("folder", "Proyectos", function () { send("openModal", { view: "browser" }); }));
        g.appendChild(ibtn("publish", P.live ? "Publicar cambios (versión nueva)" : "Publicar en el mundo", function () {
            if (!P.id) return;
            askModal("¿Publicar «" + P.name + "»? Lo verán todos los jugadores.", "cmd", { kind: "publish", a: P.id });
        }));
        g.appendChild(ibtn("gear", "Ajustes del proyecto y del mapa", function () { send("openModal", { view: "settings" }); }));
        g.appendChild(ibtn("history", "Versiones publicadas", function () { send("openModal", { view: "versions" }); }));
        g.appendChild(ibtn("swap", "Importar / exportar .map", function () { send("openModal", { view: "import" }); }));
        bar.appendChild(g);
        var g2 = el("div", "grp");
        g2.appendChild(ibtn("undo", "Deshacer (Ctrl+Z)", function () { send("undo"); }, false, !st.canUndo));
        g2.appendChild(ibtn("redo", "Rehacer (Ctrl+Y)", function () { send("redo"); }, false, !st.canRedo));
        bar.appendChild(g2);
        var g3 = el("div", "grp");
        g3.appendChild(ibtn("move", "Mover (1)", function () { send("gizmo", { mode: "move" }); }, st.gizmo === "move"));
        g3.appendChild(ibtn("rotate", "Girar (2)", function () { send("gizmo", { mode: "rotate" }); }, st.gizmo === "rotate"));
        g3.appendChild(ibtn("scale", "Escalar (3)", function () { send("gizmo", { mode: "scale" }); }, st.gizmo === "scale"));
        g3.appendChild(ibtn("axes", st.localAxes ? "Ejes locales (L)" : "Ejes del mundo (L)", function () { send("localAxes"); }, st.localAxes));
        g3.appendChild(ibtn("grid", st.gridOn ? "Rejilla activada (G)" : "Rejilla desactivada (G)", function () { send("grid", { on: !st.gridOn }); }, st.gridOn));
        var gs = el("select", "mini");
        [0.05, 0.1, 0.25, 0.5, 1, 2, 5].forEach(function (v) { var op = el("option", "", v + "m"); op.value = v; if (st.grid === v) op.selected = true; gs.appendChild(op); });
        gs.addEventListener("change", function () { send("grid", { grid: parseFloat(gs.value) }); });
        gs.addEventListener("mouseenter", function () { send("hover", { text: "Tamaño de la rejilla" }); });
        gs.addEventListener("mouseleave", function () { send("hover", { text: "" }); });
        g3.appendChild(gs);
        var rs = el("select", "mini");
        [0, 5, 15, 45, 90].forEach(function (v) { var op = el("option", "", v ? v + "°" : "libre"); op.value = v; if (st.rotStep === v) op.selected = true; rs.appendChild(op); });
        rs.addEventListener("change", function () { send("grid", { rotStep: parseFloat(rs.value) }); });
        rs.addEventListener("mouseenter", function () { send("hover", { text: "Paso de giro" }); });
        rs.addEventListener("mouseleave", function () { send("hover", { text: "" }); });
        g3.appendChild(rs);
        bar.appendChild(g3);
        var g4 = el("div", "grp");
        g4.appendChild(ibtn("list", "Elementos del proyecto", function () { send("dock", { kind: "list" }); }, st.win === "list"));
        g4.appendChild(ibtn("play", "Probar con tu personaje (F)", function () { send("test"); }));
        g4.appendChild(ibtn("exit", "Salir del editor", function () { askModal("¿Salir del editor? Todo está guardado en el borrador.", "exit", {}); }));
        bar.appendChild(g4);
        app.appendChild(bar);
    }

    /* ================= Columna de tipos ================= */
    var DOCK = [
        ["objects", "cube", "Objetos", "object"], ["vehicles", "car", "Vehículos", "vehicle"], ["peds", "ped", "Peds", "ped"],
        ["marker", "marker", "Marcadores", "marker"], ["pickup", "pickup", "Pickups", "pickup"], ["point", "point", "Puntos de aparición", "point"],
        ["remove", "eraser", "Quitar edificios del mapa original", null]
    ];
    function renderDock() {
        var app = $("app"), st = S.state;
        app.innerHTML = "";
        var d = el("div", "dock");
        DOCK.forEach(function (x) {
            var on = x[0] === "remove" ? st.tool === "remove" : (st.win === x[0] || st.placing === x[3]);
            d.appendChild(ibtn(x[1], x[2], function () { send("dock", { kind: x[0] }); }, on));
        });
        app.appendChild(d);
    }

    /* ================= Ventana: catálogo, opciones y lista ================= */
    var GROUPS = window.ME_GROUPS || [], MODELS = window.ME_MODELS || [], KW = window.ME_KW || {};
    var byId = {};
    MODELS.forEach(function (m) { byId[m[0]] = m; });

    // Árbol de categorías como el navegador del editor de MTA (categories.js), con favoritos,
    // recientes y los grupos por archivo del juego como entradas extra
    function countNode(n) {
        if (n.total !== undefined) return n.total;
        var t = (n.m || []).length;
        (n.c || []).forEach(function (k) { t += countNode(k); });
        n.total = t;
        return t;
    }
    var ROOT = {
        n: "Categorías",
        c: [{ n: "★ Favoritos", fav: true }, { n: "Recientes", rec: true }]
            .concat(window.ME_CATS || [])
            .concat([{ n: "Por archivo del juego", c: GROUPS.map(function (g, i) { return { n: g, file: i + 1 }; }) }])
    };
    S.path = [];
    function curNode() { return S.path.length ? S.path[S.path.length - 1] : ROOT; }
    var observer = null, thumbQueue = [], thumbTimer = null;
    var WIN_TITLES = { objects: "Objetos", vehicles: "Vehículos", peds: "Peds", marker: "Marcador", pickup: "Pickup", point: "Punto de aparición", list: "Elementos del proyecto" };

    function requestThumb(key) {
        if (S.thumbs[key] !== undefined) return;
        S.thumbs[key] = null;
        thumbQueue.push(key);
        clearTimeout(thumbTimer);
        thumbTimer = setTimeout(function () { send("thumbs", { list: thumbQueue.slice(0, 60) }); thumbQueue = []; }, 150);
    }

    function catalogItems() {
        var q = S.query.trim().toLowerCase(), out = [], i;
        if (S.tab === "objects") {
            var fav = {}; S.catalog.favorites.forEach(function (m) { fav[m] = true; });
            var src, node = curNode();
            if (q) src = MODELS;
            else if (node.fav) src = S.catalog.favorites.map(function (m) { return byId[m]; }).filter(Boolean);
            else if (node.rec) src = S.catalog.recents.map(function (m) { return byId[m]; }).filter(Boolean);
            else if (node.file) src = MODELS.filter(function (m) { return m[2] === node.file; });
            else src = (node.m || []).map(function (id) { return byId[id]; }).filter(Boolean);
            for (i = 0; i < src.length && out.length < 300; i++) {
                var m = src[i];
                if (!q || String(m[0]) === q || m[1].toLowerCase().indexOf(q) !== -1 || (KW[m[0]] && KW[m[0]].toLowerCase().indexOf(q) !== -1))
                    out.push({ etype: "object", model: m[0], name: m[1], key: "o:" + m[0], fav: !!fav[m[0]] });
            }
        } else if (S.tab === "vehicles") {
            S.catalog.vehicles.forEach(function (v) {
                if (!q || String(v[0]) === q || v[1].toLowerCase().indexOf(q) !== -1) out.push({ etype: "vehicle", model: v[0], name: v[1], key: "v:" + v[0] });
            });
        } else if (S.tab === "peds") {
            S.catalog.peds.forEach(function (p) {
                if (!q || String(p).indexOf(q) === 0) out.push({ etype: "ped", model: p, name: "Skin " + p, key: "p:" + p });
            });
        }
        return out;
    }

    function renderWin() {
        var app = $("app");
        app.innerHTML = "";
        app.appendChild(winHeader(WIN_TITLES[S.tab] || "Elegir", "closeWin"));
        if (S.tab === "marker" || S.tab === "pickup" || S.tab === "point") return renderOther(app);
        if (S.tab === "list") return renderList(app);

        var sbox = el("div", "search");
        var q = input("text", S.query, function () { }, { placeholder: S.tab === "objects" ? "Buscar por nombre o número (ej. 1337, bench)" : "Buscar..." });
        q.addEventListener("input", function () { S.query = q.value; renderCards(); });
        sbox.appendChild(q);
        if (S.tab === "objects") {
            var crumbs = el("div", "crumbs"); crumbs.id = "crumbs";
            sbox.appendChild(crumbs);
        } else {
            sbox.appendChild(el("div", "muted small", "Clic para colocarlo. La ventana se cierra y lo pones con clic en el mundo."));
        }
        app.appendChild(sbox);
        var sc = el("div", "scroll"); sc.id = "cards";
        app.appendChild(sc);
        renderCards();
    }

    // Migas: Categorías › Edificios › Fábricas (clic para volver a ese nivel)
    function renderCrumbs() {
        var cr = $("crumbs");
        if (!cr) return;
        cr.innerHTML = "";
        if (S.query.trim()) { cr.appendChild(el("span", "muted small", "Resultados en todas las categorías")); return; }
        [ROOT].concat(S.path).forEach(function (n, i) {
            if (i > 0) cr.appendChild(el("span", "muted", " › "));
            var a = el("a", i === S.path.length ? "cur" : "", n.n);
            if (i < S.path.length) a.addEventListener("click", function () { S.path = S.path.slice(0, i); sound("click_002"); renderCards(); });
            cr.appendChild(a);
        });
    }

    function renderCards() {
        var sc = $("cards");
        if (!sc) return;
        sc.innerHTML = "";
        sc.scrollTop = 0;
        var node = curNode(), q = S.query.trim();
        if (S.tab === "objects") {
            renderCrumbs();
            // subcategorías del nivel actual
            if (!q && node.c && node.c.length) {
                var list = el("div", "cats");
                node.c.forEach(function (k) {
                    var it = el("div", "cat");
                    it.appendChild(el("span", "", k.n));
                    var cnt = k.fav ? S.catalog.favorites.length : k.rec ? S.catalog.recents.length
                        : k.file ? MODELS.filter(function (m) { return m[2] === k.file; }).length : countNode(k);
                    it.appendChild(el("span", "cnt", String(cnt)));
                    it.appendChild(el("span", "arr", "›"));
                    it.addEventListener("click", function () { S.path.push(k); sound("click_002"); renderCards(); });
                    list.appendChild(it);
                });
                sc.appendChild(list);
                if (!node.m || !node.m.length) return;
            }
        }
        var items = catalogItems();
        if (!items.length) {
            sc.appendChild(el("div", "empty", S.tab === "objects" && !q && node.fav ? "Aún no tienes favoritos: pulsa la estrella de un objeto para guardarlo aquí." :
                S.tab === "objects" && !q && node.rec ? "Aquí aparecen los últimos objetos que colocaste." : "Nada coincide con la búsqueda."));
            return;
        }
        if (S.tab === "objects") sc.appendChild(el("div", "muted small pad0", items.length + (items.length >= 300 ? "+ (afina la búsqueda)" : "") + " objetos · clic para colocarlo"));
        var grid = el("div", "cards");
        if (observer) observer.disconnect();
        observer = "IntersectionObserver" in window ? new IntersectionObserver(function (entries) {
            entries.forEach(function (en) { if (en.isIntersecting) requestThumb(en.target.dataset.key); });
        }, { root: sc }) : null;
        items.forEach(function (it) {
            var c = el("div", "card");
            c.dataset.key = it.key;
            var th = el("div", "th");
            if (S.thumbs[it.key]) { var im = el("img"); im.src = S.thumbs[it.key]; th.appendChild(im); } else th.textContent = "▦";
            c.appendChild(th);
            c.appendChild(el("div", "nm", it.name));
            c.appendChild(el("div", "id", "#" + it.model));
            if (it.etype === "object") {
                var f = el("span", "fav" + (it.fav ? " on" : ""), "★");
                f.addEventListener("click", function (ev) { ev.stopPropagation(); send("favorite", { model: it.model }); });
                c.appendChild(f);
            }
            c.addEventListener("click", function () { send("pick", { etype: it.etype, model: it.model }); });
            grid.appendChild(c);
            if (observer) observer.observe(c); else requestThumb(it.key);
        });
        sc.appendChild(grid);
    }

    function renderOther(app) {
        var o = S.other, box = el("div", "scroll pad");
        o.etype = S.tab;
        if (o.etype === "marker") {
            var mt = el("select");
            ["cylinder", "checkpoint", "ring", "arrow", "corona"].forEach(function (x) { var op = el("option", "", x); op.value = x; if (o.mtype === x) op.selected = true; mt.appendChild(op); });
            mt.addEventListener("change", function () { o.mtype = mt.value; });
            box.appendChild(row("Forma", mt));
            box.appendChild(row("Tamaño", input("number", o.size, function (v) { o.size = num(v, 1.5); }, { step: "0.1", min: "0.1", max: "20" })));
            box.appendChild(row("Color", input("color", o.color, function (v) { o.color = v; })));
            box.appendChild(row("Icono", input("text", o.icon, function (v) { o.icon = v; }, { placeholder: "opcional (rp_markers)" })));
            box.appendChild(row("Texto", input("text", o.label, function (v) { o.label = v; }, { maxlength: "48" })));
        } else if (o.etype === "pickup") {
            var pt = el("select");
            [["0", "Vida"], ["1", "Chaleco"], ["2", "Arma"], ["3", "Modelo propio"]].forEach(function (x) { var op = el("option", "", x[1]); op.value = x[0]; if (String(o.ptype) === x[0]) op.selected = true; pt.appendChild(op); });
            pt.addEventListener("change", function () { o.ptype = parseInt(pt.value, 10); o.amount = o.ptype === 2 ? 22 : o.ptype === 3 ? 1239 : 100; renderWin(); });
            box.appendChild(row("Clase", pt));
            box.appendChild(row(o.ptype === 2 ? "ID de arma" : o.ptype === 3 ? "Modelo" : "Cantidad", input("number", o.amount, function (v) { o.amount = num(v, 100); })));
            if (o.ptype === 2) box.appendChild(row("Munición", input("number", o.ammo, function (v) { o.ammo = num(v, 50); })));
            box.appendChild(row("Reaparece (s)", input("number", o.respawn / 1000, function (v) { o.respawn = num(v, 30) * 1000; })));
        } else {
            box.appendChild(row("Nombre", input("text", o.name, function (v) { o.name = v; }, { maxlength: "32" })));
            box.appendChild(el("div", "muted small", "Los puntos no se ven en el mundo: otros sistemas los leen con getMapPoints."));
        }
        box.appendChild(el("div", "sep"));
        box.appendChild(btn("Colocar", function () { send("pick", otherPick()); }, "primary"));
        app.appendChild(box);
    }

    function otherPick() {
        var o = S.other, rgb = hexToRgb(o.color);
        if (o.etype === "marker") return { etype: "marker", model: 0, props: { mtype: o.mtype, size: o.size, color: [rgb[0], rgb[1], rgb[2], o.alpha], icon: o.icon, label: o.label } };
        if (o.etype === "pickup") return { etype: "pickup", model: 0, props: { ptype: o.ptype, amount: o.amount, ammo: o.ammo, respawn: o.respawn } };
        return { etype: "point", model: 0, props: { name: o.name } };
    }

    function renderList(app) {
        var sbox = el("div", "search");
        var q = input("text", S.query, function () { }, { placeholder: "Filtrar elementos" });
        q.addEventListener("input", function () { S.query = q.value; renderListItems(); });
        sbox.appendChild(q);
        sbox.appendChild(el("div", "muted small", S.rows.length + " elementos · clic elige, doble clic va hasta él, Mayús+clic añade"));
        app.appendChild(sbox);
        var sc = el("div", "scroll list"); sc.id = "list";
        app.appendChild(sc);
        renderListItems();
    }

    function renderListItems() {
        var sc = $("list");
        if (!sc) return;
        sc.innerHTML = "";
        var q = S.query.trim().toLowerCase(), sel = {};
        S.selected.forEach(function (id) { sel[id] = true; });
        var n = 0;
        S.rows.forEach(function (r) {
            if (q && (r.label + " " + r.id).toLowerCase().indexOf(q) === -1) return;
            if (++n > 600) return;
            var it = el("div", "item" + (sel[r.id] ? " sel" : ""));
            it.appendChild(el("span", "tag", TYPE_NAMES[r.etype] || r.etype));
            it.appendChild(el("span", "", r.label + "  #" + r.id));
            if (r.lock) it.appendChild(el("span", "lock", "🔒 " + r.lock));
            it.addEventListener("click", function (ev) { send("selectId", { id: r.id, add: ev.shiftKey }); });
            it.addEventListener("dblclick", function () { send("selectId", { id: r.id, focus: true }); });
            sc.appendChild(it);
        });
        if (!n) sc.appendChild(el("div", "empty", "El proyecto está vacío: coloca algo desde la columna de la izquierda."));
    }

    /* ================= Ventana de propiedades ================= */
    var propsKey = "";

    function renderProps(force) {
        var key = S.selection.map(function (r) { return r.id; }).join(",");
        // no se repinta mientras escribes en un campo de la misma selección
        var ae = document.activeElement;
        if (!force && key === propsKey && ae && /INPUT|SELECT|TEXTAREA/.test(ae.tagName)) return;
        propsKey = key;
        var app = $("app");
        app.innerHTML = "";
        app.appendChild(winHeader(S.selection.length > 1 ? S.selection.length + " elementos" : "Propiedades", "closeProps"));
        var box = el("div", "scroll pad");
        app.appendChild(box);
        if (S.selection.length === 1) renderPropsOne(box, S.selection[0]);
        else if (S.selection.length > 1) renderMulti(box);
        else box.appendChild(el("div", "empty", "Nada elegido."));
    }

    function sendRow(r) { send("props", { rows: [r] }); }

    function transformRows(box, r) {
        box.appendChild(el("h3", "", "Posición"));
        var g = el("div", "grid3");
        ["x", "y", "z"].forEach(function (k) {
            g.appendChild(input("number", fixed(r[k]), function (v) { var n = clone(r); n[k] = num(v, r[k]); sendRow(n); }, { step: "0.1", title: k.toUpperCase() }));
        });
        box.appendChild(g);
        if (r.etype === "marker" || r.etype === "pickup" || r.etype === "removal") return;
        box.appendChild(el("h3", "", r.etype === "ped" || r.etype === "point" ? "Mirando a (Z)" : "Giro X · Y · Z"));
        var g2 = el("div", "grid3");
        (r.etype === "ped" || r.etype === "point" ? ["rz"] : ["rx", "ry", "rz"]).forEach(function (k) {
            g2.appendChild(input("number", fixed(r[k]), function (v) { var n = clone(r); n[k] = num(v, 0); sendRow(n); }, { step: "5" }));
        });
        box.appendChild(g2);
    }

    function propInput(r, label, key, type, attrs, def) {
        var p = r.props || {};
        var val = p[key] === undefined ? def : p[key];
        return row(label, input(type, val, function (v) {
            var n = clone(r); n.props = n.props || {};
            n.props[key] = type === "checkbox" ? v : type === "number" ? num(v, def) : v;
            sendRow(n);
        }, attrs));
    }

    function renderPropsOne(box, r) {
        var p = r.props || {};
        box.appendChild(el("b", "", r.label || TYPE_NAMES[r.etype]));
        box.appendChild(el("div", "muted small", TYPE_NAMES[r.etype] + " · id " + r.id));
        var acts = el("div", "flex");
        acts.style.margin = "8px 0";
        acts.appendChild(btn("Ir hasta", function () { send("focus"); }));
        if (r.etype !== "removal") acts.appendChild(btn("Al suelo", function () { send("ground"); }));
        if (r.etype !== "removal") acts.appendChild(btn("Duplicar", function () { send("duplicate"); }));
        acts.appendChild(btn(r.etype === "removal" ? "Restaurar edificio" : "Borrar", function () { send("delete"); }, "danger"));
        box.appendChild(acts);
        transformRows(box, r);
        box.appendChild(el("h3", "", "Propiedades"));
        if (r.etype === "object") {
            box.appendChild(row("Modelo", input("number", r.model, function (v) { var n = clone(r); n.model = num(v, r.model); sendRow(n); })));
            var s = p.scale || [1, 1, 1];
            box.appendChild(el("div", "muted small", "Escala X · Y · Z (3 = escalar con el gizmo, Ctrl = uniforme)"));
            var g = el("div", "grid3");
            [0, 1, 2].forEach(function (i) {
                g.appendChild(input("number", fixed(s[i]), function (v) { var n = clone(r); n.props = n.props || {}; var ns = (p.scale || [1, 1, 1]).slice(); ns[i] = num(v, 1); n.props.scale = ns; sendRow(n); }, { step: "0.1", min: "0.05", max: "20" }));
            });
            box.appendChild(g);
            box.appendChild(propInput(r, "Opacidad", "alpha", "number", { min: "0", max: "255" }, 255));
            box.appendChild(propInput(r, "Colisiones", "col", "checkbox", null, true));
            box.appendChild(propInput(r, "Doble cara", "ds", "checkbox", null, false));
            box.appendChild(propInput(r, "Congelado", "frozen", "checkbox", null, true));
            box.appendChild(propInput(r, "Rompible", "brk", "checkbox", null, false));
        } else if (r.etype === "vehicle") {
            box.appendChild(row("Modelo", input("number", r.model, function (v) { var n = clone(r); n.model = num(v, r.model); sendRow(n); }, { min: "400", max: "611" })));
            var c = p.color || [255, 255, 255, 255, 255, 255];
            box.appendChild(row("Color 1", input("color", rgbToHex(c.slice(0, 3)), function (v) { var n = clone(r); var cc = c.slice(); var x = hexToRgb(v); cc[0] = x[0]; cc[1] = x[1]; cc[2] = x[2]; n.props.color = cc; sendRow(n); })));
            box.appendChild(row("Color 2", input("color", rgbToHex(c.slice(3, 6)), function (v) { var n = clone(r); var cc = c.slice(); var x = hexToRgb(v); cc[3] = x[0]; cc[4] = x[1]; cc[5] = x[2]; n.props.color = cc; sendRow(n); })));
            box.appendChild(propInput(r, "Matrícula", "plate", "text", { maxlength: "8" }, ""));
            box.appendChild(row("Mejoras", input("text", (p.upg || []).join(","), function (v) {
                var n = clone(r); n.props.upg = v.split(/[,\s]+/).map(function (x) { return parseInt(x, 10); }).filter(function (x) { return x >= 1000 && x <= 1193; }); sendRow(n);
            }, { placeholder: "1010,1025..." })));
            box.appendChild(propInput(r, "Vinilo (0-3)", "paintjob", "number", { min: "0", max: "3" }, 3));
            box.appendChild(propInput(r, "Cerrado", "locked", "checkbox", null, true));
            box.appendChild(propInput(r, "Motor", "engine", "checkbox", null, false));
            box.appendChild(propInput(r, "Luces", "lights", "checkbox", null, false));
            box.appendChild(propInput(r, "Sirenas", "sirens", "checkbox", null, false));
            box.appendChild(propInput(r, "Congelado", "frozen", "checkbox", null, true));
        } else if (r.etype === "ped") {
            box.appendChild(row("Skin", input("number", r.model, function (v) { var n = clone(r); n.model = num(v, r.model); sendRow(n); }, { min: "0", max: "312" })));
            var an = el("select"), cur = (p.block || "") + "/" + (p.anim || "");
            S.catalog.anims.forEach(function (a) { var op = el("option", "", a[0]); op.value = a[1] + "/" + a[2]; if (op.value === cur) op.selected = true; an.appendChild(op); });
            an.addEventListener("change", function () { var n = clone(r); var x = an.value.split("/"); n.props.block = x[0]; n.props.anim = x[1]; sendRow(n); });
            box.appendChild(row("Animación", an));
            box.appendChild(propInput(r, "Bloque", "block", "text", { placeholder: "o escribe una propia" }, ""));
            box.appendChild(propInput(r, "Animación", "anim", "text", null, ""));
            box.appendChild(propInput(r, "Congelado", "frozen", "checkbox", null, true));
        } else if (r.etype === "marker") {
            var mt = el("select");
            ["cylinder", "checkpoint", "ring", "arrow", "corona"].forEach(function (x) { var op = el("option", "", x); op.value = x; if (p.mtype === x) op.selected = true; mt.appendChild(op); });
            mt.addEventListener("change", function () { var n = clone(r); n.props.mtype = mt.value; sendRow(n); });
            box.appendChild(row("Forma", mt));
            box.appendChild(propInput(r, "Tamaño", "size", "number", { step: "0.1" }, 1.5));
            var mc = p.color || [255, 200, 60, 160];
            box.appendChild(row("Color", input("color", rgbToHex(mc), function (v) { var n = clone(r); var x = hexToRgb(v); n.props.color = [x[0], x[1], x[2], mc[3]]; sendRow(n); })));
            box.appendChild(row("Opacidad", input("number", mc[3], function (v) { var n = clone(r); n.props.color = [mc[0], mc[1], mc[2], num(v, 160)]; sendRow(n); }, { min: "0", max: "255" })));
            box.appendChild(propInput(r, "Icono", "icon", "text", null, ""));
            box.appendChild(propInput(r, "Texto", "label", "text", { maxlength: "48" }, ""));
        } else if (r.etype === "pickup") {
            box.appendChild(el("div", "muted small", ["Vida", "Chaleco", "Arma", "Modelo propio"][p.ptype || 0]));
            box.appendChild(propInput(r, p.ptype === 2 ? "ID de arma" : p.ptype === 3 ? "Modelo" : "Cantidad", "amount", "number", null, 100));
            if (p.ptype === 2) box.appendChild(propInput(r, "Munición", "ammo", "number", null, 50));
            box.appendChild(propInput(r, "Reaparece (ms)", "respawn", "number", { step: "1000" }, 30000));
        } else if (r.etype === "point") {
            box.appendChild(propInput(r, "Nombre", "name", "text", { maxlength: "32" }, "punto"));
        } else if (r.etype === "removal") {
            box.appendChild(el("div", "muted small", "Modelo " + r.model + (p.lod ? " · LOD " + p.lod : "")));
            box.appendChild(propInput(r, "Radio (m)", "radius", "number", { step: "0.5", min: "0.1", max: "250" }, 1));
            box.appendChild(el("div", "help", "Con radio grande se quitan todas las copias de ese modelo en la zona."));
        }
    }

    function renderMulti(box) {
        var counts = {};
        S.selection.forEach(function (r) { counts[r.etype] = (counts[r.etype] || 0) + 1; });
        box.appendChild(el("div", "muted", Object.keys(counts).map(function (k) { return counts[k] + " " + TYPE_NAMES[k].toLowerCase(); }).join(" · ")));
        var acts = el("div", "flex"); acts.style.margin = "10px 0";
        acts.appendChild(btn("Al suelo", function () { send("ground"); }));
        acts.appendChild(btn("Duplicar", function () { send("duplicate"); }));
        acts.appendChild(btn("Copiar", function () { send("copy"); }));
        acts.appendChild(btn("Ir hasta", function () { send("focus"); }));
        acts.appendChild(btn("Borrar", function () { send("delete"); }, "danger"));
        box.appendChild(acts);
        box.appendChild(el("div", "help", "Arrastra las flechas para mover el grupo; el anillo Z gira el grupo alrededor de su centro."));
        box.appendChild(btn("Soltar selección", function () { send("selectNone"); }));
    }

    /* ================= Modal ================= */
    function closeModal() { send("closeModal"); }

    function modalShell(title, extra) {
        var app = $("app");
        app.innerHTML = "";
        document.body.className = "modal";
        var box = el("div", "modalbox"), head = el("div", "head");
        head.appendChild(el("h2", "", title));
        if (extra) head.appendChild(extra);
        head.appendChild(btn("Cerrar", closeModal));
        box.appendChild(head);
        var body = el("div", "body");
        box.appendChild(body);
        app.appendChild(box);
        return body;
    }

    function renderConfirm() {
        var app = $("app");
        app.innerHTML = "";
        document.body.className = "modal";
        var o = el("div", "ask"), b = el("div", "askbox");
        b.appendChild(el("div", "", S.confirm || "¿Seguro?"));
        var f = el("div", "flex"); f.style.marginTop = "12px"; f.style.justifyContent = "flex-end";
        f.appendChild(btn("Cancelar", closeModal));
        f.appendChild(btn("Aceptar", function () { send("confirmOk"); }, "primary"));
        b.appendChild(f); o.appendChild(b); app.appendChild(o);
        sound("question_001");
    }

    function renderModal() {
        if (S.view === "confirm") return renderConfirm();
        if (S.view === "browser") return renderBrowser();
        if (S.view === "settings") return renderSettings();
        if (S.view === "versions") return renderVersions();
        if (S.view === "export") return renderExport();
        if (S.view === "import") return renderImport();
    }

    function renderBrowser() {
        var body = modalShell("Proyectos de mapa");
        var b = S.browser;
        var form = el("div", "proj");
        var nm = input("text", "", function () { }, { placeholder: "Nombre del proyecto nuevo", maxlength: "48" });
        var ds = input("text", "", function () { }, { placeholder: "Descripción (opcional)", maxlength: "255" });
        form.appendChild(nm); form.appendChild(ds);
        form.appendChild(btn("Crear y abrir", function () {
            if (nm.value.trim().length < 3) return nm.focus();
            send("cmd", { kind: "create", a: nm.value.trim(), b: ds.value.trim() });
        }, "primary"));
        body.appendChild(form);
        body.appendChild(el("div", "muted small", "Se crea donde estás (tu interior) y se edita en una dimensión de borrador privada. Se publica en el mundo cuando pulses «Publicar»."));
        body.appendChild(el("div", "sep"));
        if (!b) return body.appendChild(el("div", "empty", "Cargando proyectos..."));
        if (!b.list.length) return body.appendChild(el("div", "empty", "Aún no hay proyectos. Crea el primero arriba."));
        b.list.forEach(function (P) {
            var c = el("div", "proj"), info = el("div", "info");
            info.appendChild(el("b", "", P.name));
            if (P.live) info.appendChild(el("span", "pill live", "publicado v" + P.live));
            if (P.editors && P.editors.length) info.appendChild(el("span", "pill edit", "editando: " + P.editors.join(", ")));
            if (P.description) info.appendChild(el("div", "", P.description));
            info.appendChild(el("div", "meta", P.count + " elementos · " + P.versions + " versiones · int " + P.interior + ", dim " + P.dimension + " · creado por " + (P.createdName || "?")));
            c.appendChild(info);
            c.appendChild(btn(b.info.current === P.id ? "Abierto" : "Abrir", function () { send("cmd", { kind: "open", a: P.id }); }, "primary"));
            c.appendChild(btn("Duplicar", function () {
                askText("Nombre de la copia:", P.name + " copia", function (n) { send("cmd", { kind: "duplicate", a: P.id, b: n }); });
            }));
            if (P.live) c.appendChild(btn("Despublicar", function () { ask("¿Quitar «" + P.name + "» del mundo?", function () { send("cmd", { kind: "unpublish", a: P.id }); }); }));
            else c.appendChild(btn("Borrar", function () { ask("¿Borrar «" + P.name + "» y sus " + P.count + " elementos? No se puede deshacer.", function () { send("cmd", { kind: "delete", a: P.id }); }); }, "danger"));
            body.appendChild(c);
        });
    }

    function renderSettings() {
        var P = S.project;
        var body = modalShell("Ajustes del proyecto");
        if (!P) return body.appendChild(el("div", "empty", "Abre un proyecto primero."));
        body.appendChild(el("div", "small muted", P.count + " elementos · " + (P.live ? "publicado (versión " + P.live + ")" : "sin publicar") + " · editando ahora: " + ((S.editors || []).join(", ") || "—")));
        if (P.live) {
            var pub = el("div", "flex"); pub.style.marginTop = "8px";
            pub.appendChild(btn("Despublicar", function () { ask("¿Quitar «" + P.name + "» del mundo?", function () { send("cmd", { kind: "unpublish", a: P.id }); }); }, "danger"));
            body.appendChild(pub);
        }
        var meta = { name: P.name, description: P.description, interior: P.interior, dimension: P.dimension };
        body.appendChild(el("h3", "", "Datos"));
        body.appendChild(row("Nombre", input("text", meta.name, function (v) { meta.name = v; }, { maxlength: "48" })));
        body.appendChild(row("Descripción", input("text", meta.description, function (v) { meta.description = v; }, { maxlength: "255" })));
        body.appendChild(row("Interior", input("number", meta.interior, function (v) { meta.interior = num(v, 0); }, { min: "0", max: "255" })));
        body.appendChild(row("Dimensión", input("number", meta.dimension, function (v) { meta.dimension = num(v, 0); }, { min: "0", max: "65535" })));
        body.appendChild(el("div", "muted small", "Interior y dimensión donde aparece al publicar. 0 y 0 = el mundo abierto."));
        body.appendChild(btn("Guardar datos", function () { send("cmd", { kind: "meta", a: P.id, b: meta }); }, "primary"));
        body.appendChild(el("div", "sep"));
        body.appendChild(el("h3", "", "Ajustes del mapa"));
        body.appendChild(el("div", "help", P.dimension === 0 ? "Publicado en el mundo abierto estos ajustes no se aplican (mandan el clima y la hora globales). Mientras editas sí los ves." : "Se aplican a quien esté en la dimensión " + P.dimension + "."));
        var s = clone(S.settings || {});
        var fields = [["hour", "Hora (0-23)"], ["minute", "Minuto"], ["weather", "Clima (0-255)"], ["gravity", "Gravedad (0.008 normal)"], ["speed", "Velocidad de juego (1 normal)"], ["waves", "Altura de olas"], ["farclip", "Distancia de dibujado"]];
        fields.forEach(function (f) {
            body.appendChild(row(f[1], input("number", s[f[0]] === undefined ? "" : s[f[0]], function (v) { if (v === "") delete s[f[0]]; else s[f[0]] = num(v, 0); }, { step: "any", placeholder: "sin cambiar" })));
        });
        var acts = el("div", "flex");
        acts.appendChild(btn("Aplicar ajustes", function () { send("cmd", { kind: "settings", a: P.id, b: s }); }, "primary"));
        acts.appendChild(btn("Quitar todos", function () { send("cmd", { kind: "settings", a: P.id, b: {} }); }));
        body.appendChild(acts);
        body.appendChild(el("div", "sep"));
        body.appendChild(el("h3", "", "Ayuda"));
        body.appendChild(el("div", "small muted", "Columna izquierda: qué colocar. Doble clic o Enter sobre algo: propiedades. 1 mover · 2 girar · 3 escalar · L ejes · G rejilla · R girar 90° · Re/Av Pág subir y bajar · Supr borrar · Ctrl+C/V/D/Z/Y · F probar · H ocultar todo · Retroceso cierra ventanas."));
        var tf = el("div", "flex"); tf.style.marginTop = "8px";
        tf.appendChild(btn("Repetir tutorial", function () { send("tutorialReset"); closeModal(); }));
        tf.appendChild(btn("Saltar tutorial", function () { send("tutorialDone"); }));
        body.appendChild(tf);
    }

    function renderVersions() {
        var P = S.project;
        var body = modalShell("Versiones publicadas");
        if (!P) return;
        var v = S.versions;
        if (!v) return body.appendChild(el("div", "empty", "Cargando..."));
        if (!v.list.length) return body.appendChild(el("div", "empty", "Aún no publicaste este proyecto."));
        body.appendChild(el("div", "help", "«Publicar esta» vuelve a poner en el mundo una versión anterior. «Cargar en borrador» reemplaza lo que estás editando por ella."));
        v.list.forEach(function (x) {
            var c = el("div", "proj"), info = el("div", "info");
            info.appendChild(el("b", "", "Versión " + x.version));
            if (x.live) info.appendChild(el("span", "pill live", "en el mundo"));
            info.appendChild(el("div", "meta", x.count + " elementos · " + x.by + " · " + x.at));
            c.appendChild(info);
            if (!x.live) c.appendChild(btn("Publicar esta", function () { send("cmd", { kind: "pubversion", a: P.id, b: x.id }); }, "primary"));
            c.appendChild(btn("Cargar en borrador", function () {
                ask("Esto reemplaza el borrador actual por la versión " + x.version + ". ¿Seguir?", function () { send("cmd", { kind: "loadversion", a: P.id, b: x.id }); });
            }));
            body.appendChild(c);
        });
    }

    function renderExport() {
        var x = S.exported;
        var back = btn("Importar", function () { S.view = "import"; renderModal(); });
        var body = modalShell("Exportar .map", back);
        if (!x) return body.appendChild(el("div", "empty", "Generando..."));
        body.appendChild(el("div", "help", "Ya está en tu portapapeles." + (x.path ? " También se guardó en el servidor: rp_mapeditor/" + x.path : "")));
        var ta = el("textarea", "code"); ta.value = x.text; ta.readOnly = true;
        body.appendChild(ta);
    }

    function renderImport() {
        var P = S.project;
        var exp = btn("Exportar", function () { if (P) send("openModal", { view: "export" }); });
        var body = modalShell("Importar .map", exp);
        if (!P) return;
        body.appendChild(el("div", "help", "Pega el contenido de un archivo .map del editor de MTA (objetos, vehículos, peds, marcadores, pickups, spawnpoints y removeWorldObject). Los modelos que no existen se descartan."));
        var ta = el("textarea", "code"); ta.placeholder = "<map> ... </map>";
        body.appendChild(ta);
        var rep = input("checkbox", false, function () { });
        var l = el("label", "row"); l.appendChild(rep);
        var sp = el("span", "", "Reemplazar todo el borrador (si no, se añade)"); sp.style.flex = "1";
        l.appendChild(sp);
        body.appendChild(l);
        body.appendChild(btn("Importar", function () {
            if (ta.value.length < 10) return ta.focus();
            var go = function () { send("cmd", { kind: "import", a: P.id, b: ta.value, c: rep.checked }); closeModal(); };
            if (rep.checked) ask("¿Borrar el borrador actual e importar?", go); else go();
        }, "primary"));
    }

    /* ================= Recepción ================= */
    function render(kind) {
        if (PANEL === "win") {
            if (kind === "thumb") return;
            if (kind === "rows" || kind === "selected") { if (S.tab === "list") renderListItems(); return; }
            if (kind === "state" || kind === "project") return;
            renderWin();
        } else if (PANEL === "props") {
            if (kind === "selection") renderProps(false);
            else if (kind === "catalog") renderProps(true);
        } else if (PANEL === "top") {
            if (kind === "state" || kind === "project") renderTop();
        } else if (PANEL === "dock") {
            if (kind === "state") renderDock();
        } else if (PANEL === "modal") {
            renderModal();
        }
    }

    window.ME = {
        recv: function (kind, data) {
            switch (kind) {
                case "catalog": S.catalog = data; break;
                case "project": S.project = data.project; S.settings = data.settings || {}; S.editors = data.editors || []; break;
                case "state": S.state = data; break;
                case "selection": S.selection = data || []; break;
                case "selected": S.selected = data || []; break;
                case "rows": S.rows = data || []; break;
                case "recents": S.catalog.recents = data || []; if (S.tab === "objects" && curNode().rec) renderCards(); return;
                case "favorites": S.catalog.favorites = data || []; if (S.tab === "objects") renderCards(); return;
                case "thumb":
                    S.thumbs[data.key] = data.src;
                    var c = document.querySelector('.card[data-key="' + data.key + '"] .th');
                    if (c) { c.innerHTML = ""; var im = el("img"); im.src = data.src; c.appendChild(im); }
                    return;
                case "view":
                    if (PANEL === "win") { if (S.tab !== data) S.query = ""; S.tab = data; }
                    else { S.view = data; if (data === "versions") S.versions = null; if (data === "export") S.exported = null; }
                    break;
                case "browser": S.browser = data; break;
                case "versions": S.versions = data; break;
                case "exported": S.exported = data; S.view = "export"; break;
                case "confirm": S.confirm = data; S.view = "confirm"; break;
            }
            render(kind);
        }
    };

    /* ================= Arranque ================= */
    document.body.className = "p-" + PANEL + (PANEL === "modal" ? " modal" : "");
    if (PANEL === "win") renderWin();
    if (PANEL === "props") renderProps(true);
    if (PANEL === "top") renderTop();
    if (PANEL === "dock") renderDock();
    if (PANEL === "modal") renderModal();

    if (DEMO) {
        ME.recv("catalog", { vehicles: [[411, "Infernus"], [560, "Sultan"]], peds: [0, 7, 28], anims: [["Ninguna", "", ""], ["Sentado", "ped", "SEAT_idle"]], favorites: [1337, 1280], recents: [] });
        ME.recv("project", { project: { id: 1, name: "Plaza Ganton", description: "Mercadillo", count: 42, live: 3, interior: 0, dimension: 0 }, settings: { hour: 21 }, editors: ["Fabian Rojas"] });
        ME.recv("state", { tool: "select", gizmo: "move", grid: 0.5, gridOn: true, rotStep: 15, canUndo: true, canRedo: false, speed: 1, win: "objects", props: true });
        ME.recv("rows", [{ id: 3, etype: "object", label: "bench (1280)" }, { id: 2, etype: "removal", label: "Quitado: lamppost1" }, { id: 1, etype: "point", label: "Punto «salida»", lock: "Otro" }]);
        ME.recv("selection", [{ id: 3, etype: "object", model: 1280, x: 2495.1, y: -1680.2, z: 13.3, rx: 0, ry: 0, rz: 90, props: { alpha: 255 }, label: "bench (1280)" }]);
        if (location.search.indexOf("cat") !== -1) ROOT.c.forEach(function (k) { if (k.n === "Edificios") { S.path = [k, k.c[0]]; } });
        if (PANEL === "win") ME.recv("view", location.search.indexOf("list") !== -1 ? "list" : "objects");
        if (PANEL === "modal") ME.recv("view", "browser");
        if (PANEL === "modal" && location.search.indexOf("confirm") !== -1) ME.recv("confirm", "¿Salir del editor? Todo está guardado en el borrador.");
        ME.recv("browser", { list: [{ id: 1, name: "Plaza Ganton", description: "Mercadillo", count: 42, live: 3, versions: 3, interior: 0, dimension: 0, editors: ["Fabian Rojas"], createdName: "Fabian Rojas" }, { id: 2, name: "Evento playa", count: 0, live: false, versions: 0, interior: 0, dimension: 500, editors: [] }], info: { super: true, current: 1 } });
    }
})();
