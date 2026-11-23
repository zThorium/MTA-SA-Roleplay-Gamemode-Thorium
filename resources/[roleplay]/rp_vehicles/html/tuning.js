/*
 * rp_vehicles / tuning.js
 * Panel lateral del taller. Lua llama a RPT.show(datos, refresco), RPT.enter()
 * y RPT.hide(). Eventos hacia Lua: rp:tune:ui:preview (carrito JSON),
 * rp:tune:ui:buy (carrito JSON), rp:tune:ui:camera (categoria), rp:tune:ui:exit.
 */
(function () {
    "use strict";

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
    }
    var $ = function (id) { return document.getElementById(id); };
    function esc(s) {
        return String(s === null || s === undefined ? "" : s).replace(/[&<>"']/g, function (c) {
            return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
        });
    }
    function money(n) { return "$" + Number(n || 0).toLocaleString("es-AR"); }
    function list(x) { return Array.isArray(x) ? x : (x && typeof x === "object" ? Object.keys(x).map(function (k) { return x[k]; }) : []); }
    function same(a, b) { for (var i = 0; i < a.length; i++) if (Number(a[i]) !== Number(b[i])) return false; return true; }
    function css(c) { return "rgb(" + c[0] + "," + c[1] + "," + c[2] + ")"; }

    // Paleta rapida (ademas de los deslizadores RGB)
    var PALETTE = [
        [245, 245, 245], [180, 180, 180], [90, 90, 95], [20, 20, 22], [140, 20, 25], [220, 40, 40], [240, 110, 30], [245, 190, 30],
        [250, 230, 90], [120, 200, 60], [30, 120, 50], [20, 160, 150], [40, 140, 230], [20, 60, 160], [15, 25, 70], [110, 60, 200],
        [200, 70, 170], [240, 150, 190], [120, 75, 45], [200, 165, 110], [80, 95, 60], [60, 70, 85], [200, 175, 60], [170, 185, 200],
    ];

    var T = null;   // estado del panel

    function init(d, keepCategory) {
        var st = d.state;
        var cat = keepCategory && T ? T.cat : null;
        T = {
            d: d, cat: cat, sel: {}, slotOf: {}, current: {},
            c1: st.c.slice(0, 3), c2: st.c.slice(3, 6), h: st.h.slice(0, 3), p: Number(st.p),
        };
        list(d.slots).forEach(function (s) {
            T.current[s.slot] = Number(s.current) || 0;
            list(s.upgrades).forEach(function (u) { T.slotOf[u.id] = s.slot; });
        });
        $("shop").textContent = d.shop;
        $("car").textContent = d.name + " · " + d.plate;
        $("money").textContent = money(d.money);
        $("buy").disabled = true;
        draw();
    }

    function buildCart() {
        var d = T.d, st = d.state, total = 0, cart = { upgrades: [], remove: [], full: [] };
        var c = T.c1.concat(T.c2);
        if (!same(c, st.c.slice(0, 6))) {
            cart.colors = c;
            if (!same(T.c1, st.c.slice(0, 3))) total += d.prices.color;
            if (!same(T.c2, st.c.slice(3, 6))) total += d.prices.color;
        }
        if (!same(T.h, st.h)) { cart.headlight = T.h; total += d.prices.color; }
        if (T.p !== Number(st.p)) { cart.paintjob = T.p; total += d.prices.paintjob; }
        var prices = {};
        list(d.slots).forEach(function (s) { list(s.upgrades).forEach(function (u) { prices[u.id] = u.price; }); });
        Object.keys(T.current).forEach(function (slot) {
            var cur = T.current[slot];
            var sel = T.sel.hasOwnProperty(slot) ? T.sel[slot] : cur;
            if (sel !== cur) {
                if (sel === 0) { cart.remove.push(Number(slot)); total += d.prices.remove; }
                else { cart.upgrades.push(sel); total += prices[sel] || 0; }
            }
            if (sel) cart.full.push(sel);
        });
        list(st.u).forEach(function (id) { if (T.slotOf[id] === undefined) cart.full.push(id); });
        cart.total = total;
        return cart;
    }

    var timer = null;
    function changed() {
        var cart = buildCart();
        $("total").textContent = money(cart.total);
        $("buy").disabled = cart.total <= 0;
        clearTimeout(timer);
        timer = setTimeout(function () { send("rp:tune:ui:preview", JSON.stringify(buildCart())); }, 80);
    }

    function categories() {
        var d = T.d;
        var cats = [];
        if (d.perf) cats.push({ id: "perf", name: "Rendimiento" });
        cats.push({ id: "colors", name: "Pintura" }, { id: "lights", name: "Color de faros" });
        if (d.paintjobs > 0) cats.push({ id: "paintjob", name: "Vinilos (paintjob)" });
        list(d.slots).forEach(function (s) { cats.push({ id: "slot" + s.slot, name: s.name, slot: s.slot }); });
        return cats;
    }

    function isChanged(c) {
        var st = T.d.state;
        if (c.id === "colors") return !same(T.c1.concat(T.c2), st.c.slice(0, 6));
        if (c.id === "lights") return !same(T.h, st.h);
        if (c.id === "paintjob") return T.p !== Number(st.p);
        return T.sel.hasOwnProperty(c.slot) && T.sel[c.slot] !== T.current[c.slot];
    }

    // Vista de camara de cada pantalla de rendimiento
    function cameraFor(cat) {
        if (!cat) return "colors";
        if (cat === "perf:engine" || cat === "perf:turbo") return "perf_engine";
        if (cat === "perf:brakes" || cat === "perf:tires") return "perf_wheel";
        if (cat === "perf:suspension") return "perf_side";
        return cat.indexOf("perf") === 0 ? "perf" : cat;
    }

    function open(cat) {
        T.cat = cat;
        T.pend = null;
        send("rp:tune:ui:camera", cameraFor(cat));
        draw();
    }

    function colorEditor(title, key) {
        var c = T[key];
        var html = '<div class="label">' + esc(title) + '</div><div class="preview-chip" style="background:' + css(c) + '"></div><div class="swatches">';
        PALETTE.forEach(function (p, i) {
            html += '<div class="swatch' + (same(p, c) ? " selected" : "") + '" data-key="' + key + '" data-sw="' + i + '" style="background:' + css(p) + '"></div>';
        });
        html += "</div>";
        ["R", "G", "B"].forEach(function (l, i) {
            html += '<div class="slider"><span>' + l + '</span><input type="range" min="0" max="255" value="' + c[i] + '" data-key="' + key + '" data-ch="' + i + '"><span>' + c[i] + "</span></div>";
        });
        return html;
    }

    function bindColors(root) {
        root.querySelectorAll("[data-sw]").forEach(function (el) {
            el.addEventListener("click", function () {
                T[el.getAttribute("data-key")] = PALETTE[Number(el.getAttribute("data-sw"))].slice();
                changed(); draw();
            });
        });
        root.querySelectorAll("input[type=range]").forEach(function (el) {
            el.addEventListener("input", function () {
                var key = el.getAttribute("data-key");
                T[key][Number(el.getAttribute("data-ch"))] = Number(el.value);
                el.nextElementSibling.textContent = el.value;
                changed();
            });
            el.addEventListener("change", draw);
        });
    }

    function draw() {
        var d = T.d, root = $("list"), html = "";
        $("back").classList.toggle("hidden", !T.cat);
        if (!T.cat) {
            $("crumb").textContent = "Categorias";
            var repaired = !!d.repaired;
            html += '<button type="button" class="item repair" id="repair"' + (repaired ? " disabled" : "") + ">" +
                (repaired ? "Vehiculo reparado" : "Reparar vehiculo") + "<small>Estado " + d.health + "%</small>" +
                '<span class="price">' + (repaired ? "—" : money(d.repair)) + "</span></button>";
            categories().forEach(function (c) {
                html += '<button type="button" class="item" data-cat="' + c.id + '">' + esc(c.name) +
                    (isChanged(c) ? '<span class="dot">●</span>' : "") + '<span class="price">&rsaquo;</span></button>';
            });
            root.innerHTML = html;
            $("repair").addEventListener("click", function () { this.disabled = true; send("rp:tune:ui:repair"); });
            root.querySelectorAll("[data-cat]").forEach(function (b) {
                b.addEventListener("click", function () { open(b.getAttribute("data-cat")); });
            });
        } else if (T.cat === "colors") {
            $("crumb").textContent = "Pintura · " + money(d.prices.color) + " cada color";
            root.innerHTML = colorEditor("Color primario", "c1") + colorEditor("Color secundario", "c2");
            bindColors(root);
        } else if (T.cat === "lights") {
            $("crumb").textContent = "Color de faros · " + money(d.prices.color);
            root.innerHTML = colorEditor("Faros", "h");
            bindColors(root);
        } else if (T.cat === "paintjob") {
            $("crumb").textContent = "Vinilos";
            var opts = [{ v: 3, n: "Sin vinilo" }];
            for (var i = 0; i < d.paintjobs; i++) opts.push({ v: i, n: "Vinilo " + (i + 1) });
            opts.forEach(function (p) {
                html += '<button type="button" class="item' + (T.p === p.v ? " selected" : "") + '" data-pj="' + p.v + '">' + p.n +
                    '<span class="price">' + (Number(d.state.p) === p.v ? "Actual" : money(d.prices.paintjob)) + "</span></button>";
            });
            root.innerHTML = html;
            root.querySelectorAll("[data-pj]").forEach(function (b) {
                b.addEventListener("click", function () { T.p = Number(b.getAttribute("data-pj")); changed(); draw(); });
            });
        } else if (T.cat.indexOf("perf") === 0) {
            drawPerf(root);
        } else {
            var slot = Number(T.cat.substr(4));
            var s = list(d.slots).filter(function (x) { return x.slot === slot; })[0];
            if (!s) { T.cat = null; return draw(); }
            $("crumb").textContent = s.name;
            var sel = T.sel.hasOwnProperty(slot) ? T.sel[slot] : T.current[slot];
            html += '<button type="button" class="item' + (sel === 0 ? " selected" : "") + '" data-up="0">Ninguna<span class="price">' +
                (T.current[slot] ? "Quitar " + money(d.prices.remove) : "De fabrica") + "</span></button>";
            list(s.upgrades).forEach(function (u) {
                var installed = T.current[slot] === u.id;
                html += '<button type="button" class="item' + (sel === u.id ? " selected" : "") + (installed ? " installed" : "") + '" data-up="' + u.id + '">' +
                    esc(u.name) + '<span class="price">' + (installed ? "Instalada" : money(u.price)) + "</span></button>";
            });
            root.innerHTML = html;
            root.querySelectorAll("[data-up]").forEach(function (b) {
                b.addEventListener("click", function () { T.sel[slot] = Number(b.getAttribute("data-up")); changed(); draw(); });
            });
        }
        var cart = buildCart();
        $("total").textContent = money(cart.total);
        $("buy").disabled = cart.total <= 0;
    }


    // ---- Rendimiento ----------------------------------------------------
    var LEVEL_LABELS = ["De fabrica", "Nivel 1", "Nivel 2", "Nivel 3"];

    function pct(n) { n = Number(n) || 0; return (n > 0 ? "+" : "") + (Math.round(n * 10) / 10) + "%"; }

    // Barras de stats. next (opcional) = stats que tendria con la pieza elegida.
    function statBlock(p, next) {
        var html = '<div class="stats">';
        list(p.defs).forEach(function (def, i) {
            var cur = Number(p.stats[i]) || 0, nxt = next ? Number(next[i]) || 0 : cur;
            var cap = Number(def.cap) || 1;
            var lo = Math.max(0, Math.min(cur, nxt)) / cap * 100, hi = Math.max(0, Math.max(cur, nxt)) / cap * 100;
            var worse = def.cost ? nxt > cur : nxt < cur;
            var diff = nxt - cur;
            html += '<div class="stat"><span class="name">' + esc(def.name) + '</span>' +
                '<div class="bar' + (def.cost ? " cost" : "") + '"><b class="' + (worse ? "bad" : "good") + '" style="width:' + Math.min(100, hi) + '%"></b>' +
                '<i style="width:' + Math.min(100, lo) + '%"></i></div>' +
                '<span class="val">' + pct(nxt) + "</span>" +
                (next && Math.abs(diff) >= 0.05 ? '<span class="diff ' + (worse ? "bad" : "good") + '">' + (diff > 0 ? "▲" : "▼") + "</span>" : "") + "</div>";
        });
        return html + "</div>";
    }

    function wearBar(wear) {
        var w = Math.max(0, Math.min(100, Number(wear) || 0));
        var cls = w >= 100 ? "dead" : (w >= 70 ? "warn" : "ok");
        return '<div class="wear ' + cls + '"><i style="width:' + w + '%"></i></div>';
    }

    function drawPerf(root) {
        var p = T.d.perf, html = "";
        var partId = T.cat.indexOf("perf:") === 0 ? T.cat.substr(5) : null;
        var part = partId ? list(p.parts).filter(function (x) { return x.id === partId; })[0] : null;
        if (partId && !part) { T.cat = "perf"; return drawPerf(root); }

        if (!part) {
            $("crumb").textContent = "Rendimiento · " + p.class;
            html += '<div class="info"><span>Clase: <strong>' + esc(p.class) + '</strong></span><span>Kilometraje: <strong>' + p.odo + " km</strong></span></div>";
            html += statBlock(p, null);
            list(p.parts).forEach(function (x) {
                html += '<button type="button" class="item" data-part="' + x.id + '"><span>' + esc(x.name) +
                    '<small class="sub">' + (x.level ? esc(x.levelName) : "De fabrica") + "</small></span>" +
                    (x.level && x.wears ? '<span class="wearbox">' + wearBar(x.wear) + "<em>" + Math.round(x.wear) + "%</em></span>" : "") +
                    '<span class="price">&rsaquo;</span></button>';
            });
            if (p.maintTotal > 0) {
                html += '<button type="button" class="item repair" id="maintAll">Mantenimiento general<span class="price">' + money(p.maintTotal) + "</span></button>";
            }
            root.innerHTML = html;
            root.querySelectorAll("[data-part]").forEach(function (b) {
                b.addEventListener("click", function () { open("perf:" + b.getAttribute("data-part")); });
            });
            var all = $("maintAll");
            if (all) all.addEventListener("click", function () { this.disabled = true; send("rp:tune:ui:maint", "all"); });
            return;
        }

        $("crumb").textContent = part.name;
        var pend = T.pend && T.pend.part === part.id ? T.pend.level : null;
        var preview = null;
        if (pend !== null && pend > 0) preview = list(part.levels)[pend - 1].stats;
        html += '<div class="info"><span>' + esc(part.desc) + "</span></div>";
        html += statBlock(p, preview);
        if (part.level && part.wears) {
            html += '<div class="wearline"><span>Desgaste ' + Math.round(part.wear) + "%</span>" + wearBar(part.wear) + "</div>";
            if (part.maint > 0) {
                html += '<button type="button" class="item repair" id="maint">Mantenimiento<span class="price">' + money(part.maint) + "</span></button>";
            }
        }
        html += '<button type="button" class="item' + (part.level === 0 ? " installed" : "") + (pend === 0 ? " selected" : "") + '" data-lv="0">' +
            "De fabrica" + '<span class="price">' + (part.level === 0 ? "Instalada" : (pend === 0 ? "Confirmar " : "Quitar ") + money(p.remove)) + "</span></button>";
        list(part.levels).forEach(function (lv) {
            var disabled = !lv.ok && !lv.installed;
            html += '<button type="button" class="item' + (lv.installed ? " installed" : "") + (pend === lv.level ? " selected" : "") +
                (disabled ? " locked" : "") + '" data-lv="' + lv.level + '"' + (disabled ? " disabled" : "") + ">" +
                '<span>' + esc(lv.name) + (disabled ? '<small class="sub">' + esc(lv.why) + "</small>" : "") + "</span>" +
                '<span class="price">' + (lv.installed ? "Instalada" : (pend === lv.level ? "Confirmar " : "") + money(lv.price)) + "</span></button>";
        });
        root.innerHTML = html;
        var m = $("maint");
        if (m) m.addEventListener("click", function () { this.disabled = true; send("rp:tune:ui:maint", part.id); });
        root.querySelectorAll("[data-lv]").forEach(function (b) {
            b.addEventListener("click", function () {
                var level = Number(b.getAttribute("data-lv"));
                if (T.pend && T.pend.part === part.id && T.pend.level === level) {
                    b.disabled = true;
                    T.pend = null;
                    send("rp:tune:ui:perf", part.id, level);
                } else {
                    T.pend = { part: part.id, level: level };   // primer click: vista previa; segundo: confirmar
                    draw();
                }
            });
        });
    }

    $("back").addEventListener("click", function () {
        open(T.cat && T.cat.indexOf("perf:") === 0 ? "perf" : null);
    });
    $("exit").addEventListener("click", function () { send("rp:tune:ui:exit"); });
    $("buy").addEventListener("click", function () {
        var cart = buildCart();
        if (cart.total <= 0) return;
        this.disabled = true;
        send("rp:tune:ui:buy", JSON.stringify(cart));
    });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" || e.key === "Backspace") { e.preventDefault(); send("rp:tune:ui:exit"); }
    });

    window.RPT = {
        show: function (data, refresh) { init(data, refresh); },
        enter: function () { $("panel").classList.remove("hidden"); },
        hide: function () { $("panel").classList.add("hidden"); T = null; $("list").innerHTML = ""; },
    };
})();
