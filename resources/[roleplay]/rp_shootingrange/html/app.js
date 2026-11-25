/*
 * rp_shootingrange / app.js
 * Lua llama a RP.menu / start / round / hit / hud / results. El JS solo dibuja y pide (mta.triggerEvent);
 * armas, balas y habilidad las decide siempre el servidor.
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var data = null, filter = "all", roundEnd = 0, roundStart = 0, timer = null, kindNames = {
        static: "Blancos fijos", advance: "Blancos que avanzan", lateral: "Blanco lateral"
    };

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

    // toJSON de Lua puede mandar listas como objeto {"1":...}; esto las deja siempre como array
    function list(x) { return Array.isArray(x) ? x : (x && typeof x === "object" ? Object.keys(x).map(function (k) { return x[k]; }) : []); }

    function show(id) { ["menu", "results", "hud"].forEach(function (k) { $(k).classList.toggle("hidden", k !== id); }); }

    function skillText(s) { return s.level + " (" + Math.floor(s.value) + "/1000)"; }

    function glyph(cat) { return { pistol: "PIS", smg: "SMG", shotgun: "ESC", rifle: "FUS" }[cat] || "ARM"; }

    function renderCards() {
        var box = $("cards");
        box.textContent = "";
        var count = 0;
        data.weapons.forEach(function (w) {
            if (filter !== "all" && w.category !== filter) return;
            count++;
            var c = el("div", "card");
            var head = el("div", "card-head");
            head.appendChild(el("div", "glyph", glyph(w.category)));
            var names = el("div");
            names.appendChild(el("div", "card-name", w.name));
            names.appendChild(el("div", "card-cat", w.categoryName));
            head.appendChild(names);
            c.appendChild(head);

            var r1 = el("div", "row");
            r1.appendChild(el("span", "", "Munición de entrenamiento: ∞"));
            r1.appendChild(el("span", "badge " + w.skill.key, w.skill.level));
            c.appendChild(r1);

            var track = el("div", "track");
            var fill = el("div", "fill " + w.skill.key);
            track.appendChild(fill);
            c.appendChild(track);
            var next = w.skill.nextLevel ? " → " + w.skill.nextLevel : " (máximo)";
            c.appendChild(el("div", "card-cat", "Habilidad " + Math.floor(w.skill.value) + "/1000" + next));
            setTimeout(function () { fill.style.width = Math.round(w.skill.progress * 100) + "%"; }, 30);

            var btn = el("button", "btn primary", "Entrenar");
            btn.addEventListener("click", function () { send("rp:range:ui:train", w.item); });
            c.appendChild(btn);
            box.appendChild(c);
        });
        $("empty").classList.toggle("hidden", data.weapons.length > 0);
        $("tabs").classList.toggle("hidden", data.weapons.length === 0);
        if (count === 0 && data.weapons.length > 0) { filter = "all"; renderCards(); }
    }

    function renderTabs() {
        var tabs = $("tabs"), seen = {}, list = [{ key: "all", name: "Todas" }];
        tabs.textContent = "";
        data.weapons.forEach(function (w) {
            if (!seen[w.category]) { seen[w.category] = 1; list.push({ key: w.category, name: w.categoryName }); }
        });
        list.forEach(function (t) {
            var b = el("button", "tab" + (t.key === filter ? " on" : ""), t.name);
            b.addEventListener("click", function () { filter = t.key; renderTabs(); renderCards(); });
            tabs.appendChild(b);
        });
    }

    function tickTime() {
        var now = Date.now();
        if (now < roundStart) {
            $("hud-banner").textContent = "¡Prepárate! " + Math.ceil((roundStart - now) / 1000);
            $("hud-time").textContent = "--";
            return;
        }
        if ($("hud-banner").textContent.indexOf("Prepárate") === 0) $("hud-banner").textContent = "¡Fuego!";
        $("hud-time").textContent = Math.max(0, Math.ceil((roundEnd - now) / 1000)) + "s";
    }

    // ------------------------------------------------------------------ Graficas (SVG)
    // Una serie por grafica (sin leyenda: el titulo la nombra). Tema oscuro de la skill dataviz.
    var SVGNS = "http://www.w3.org/2000/svg";
    var C = { series: "#338ced", grid: "#303030", axis: "#474747", surface: "#191919", ink: "#efefef", muted: "#9c9c9c" };

    function svgEl(tag, attrs, parent) {
        var n = document.createElementNS(SVGNS, tag);
        for (var k in attrs) if (attrs.hasOwnProperty(k)) n.setAttribute(k, attrs[k]);
        if (parent) parent.appendChild(n);
        return n;
    }

    // Tooltip HTML compartido por cada grafica (texto con textContent, nunca HTML)
    function tooltip(plot) {
        var tip = plot.querySelector(".tip");
        if (!tip) { tip = el("div", "tip"); plot.appendChild(tip); }
        return {
            show: function (x, y, title, value) {
                tip.textContent = "";
                tip.appendChild(el("div", "", title));
                tip.appendChild(el("b", "", value));
                tip.style.left = x + "px";
                tip.style.top = y + "px";
                tip.classList.add("show");
            },
            hide: function () { tip.classList.remove("show"); },
        };
    }

    // Marco comun: escala Y fija [0, max], 3 lineas de cuadricula, etiquetas a la izquierda
    function frame(plot, maxY, ticks, fmt) {
        plot.textContent = "";
        var W = plot.clientWidth || 280, H = plot.clientHeight || 150;
        var P = { l: 34, r: 12, t: 10, b: 18 };
        var svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, preserveAspectRatio: "none" }, plot);
        var y = function (v) { return P.t + (H - P.t - P.b) * (1 - v / maxY); };
        ticks.forEach(function (t) {
            svgEl("line", { x1: P.l, x2: W - P.r, y1: y(t), y2: y(t), stroke: t === 0 ? C.axis : C.grid, "stroke-width": 1 }, svg);
            var lbl = svgEl("text", { x: P.l - 6, y: y(t) + 3, "text-anchor": "end", "class": "axis-text" }, svg);
            lbl.textContent = fmt(t);
        });
        return { svg: svg, W: W, H: H, P: P, y: y };
    }

    // Etiquetas del eje X: solo la primera y la ultima sesion (fechas)
    function xLabels(f, xs, items) {
        if (!items.length) return;
        var first = svgEl("text", { x: xs[0], y: f.H - 4, "text-anchor": items.length > 1 ? "start" : "middle", "class": "axis-text" }, f.svg);
        first.textContent = items[0].date || "";
        if (items.length > 1) {
            var last = svgEl("text", { x: xs[xs.length - 1], y: f.H - 4, "text-anchor": "end", "class": "axis-text" }, f.svg);
            last.textContent = "Hoy";
        }
    }

    function xPositions(f, n, inset) {
        var a = f.P.l + inset, b = f.W - f.P.r - inset, xs = [];
        for (var i = 0; i < n; i++) xs.push(n === 1 ? (a + b) / 2 : a + (b - a) * i / (n - 1));
        return xs;
    }

    // Linea + area tenue + puntos con anillo; etiqueta solo en el ultimo valor; umbrales opcionales
    function lineChart(plot, items, key, maxY, ticks, fmt, title, thresholds) {
        var f = frame(plot, maxY, ticks, fmt), tip = tooltip(plot);
        (thresholds || []).forEach(function (t) {
            if (t.v <= 0 || t.v > maxY) return;
            svgEl("line", { x1: f.P.l, x2: f.W - f.P.r, y1: f.y(t.v), y2: f.y(t.v), stroke: C.axis, "stroke-width": 1 }, f.svg);
            // A la izquierda: la etiqueta del ultimo valor va a la derecha y no se pisan
            var lbl = svgEl("text", { x: f.P.l + 4, y: f.y(t.v) - 3, "text-anchor": "start", "class": "axis-text" }, f.svg);
            lbl.textContent = t.label;
        });
        var xs = xPositions(f, items.length, 6);
        var pts = items.map(function (it, i) { return [xs[i], f.y(Math.max(0, Math.min(maxY, it[key])))]; });
        if (pts.length > 1) {
            var line = pts.map(function (p, i) { return (i ? "L" : "M") + p[0].toFixed(1) + " " + p[1].toFixed(1); }).join(" ");
            svgEl("path", { d: line + " L" + pts[pts.length - 1][0] + " " + f.y(0) + " L" + pts[0][0] + " " + f.y(0) + " Z",
                fill: C.series, "fill-opacity": 0.1, stroke: "none" }, f.svg);
            svgEl("path", { d: line, fill: "none", stroke: C.series, "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round" }, f.svg);
        }
        pts.forEach(function (p, i) {
            var last = i === pts.length - 1;
            svgEl("circle", { cx: p[0], cy: p[1], r: last ? 5 : 4, fill: C.series, stroke: C.surface, "stroke-width": 2 }, f.svg);
            var hit = svgEl("circle", { cx: p[0], cy: p[1], r: 12, "class": "hit" }, f.svg);
            hit.addEventListener("mouseenter", function () {
                tip.show(p[0] * plot.clientWidth / f.W, p[1] * plot.clientHeight / f.H, title + " · " + items[i].date, fmt(items[i][key]));
            });
            hit.addEventListener("mouseleave", tip.hide);
        });
        if (pts.length) {
            var lp = pts[pts.length - 1];
            var v = svgEl("text", { x: lp[0] - 8, y: Math.max(12, lp[1] - 9), "text-anchor": "end", "class": "value-text" }, f.svg);
            v.textContent = fmt(items[items.length - 1][key]);
        }
        xLabels(f, xs, items);
    }

    // Barras <= 24px, punta redondeada de 4px y base recta; la ultima (esta sesion) destacada
    function barChart(plot, items, key, maxY, ticks, fmt, title) {
        var f = frame(plot, maxY, ticks, fmt), tip = tooltip(plot);
        var n = items.length, band = (f.W - f.P.l - f.P.r) / Math.max(1, n);
        var bw = Math.min(24, band - 2), xs = [];
        items.forEach(function (it, i) {
            var cx = f.P.l + band * (i + 0.5), x = cx - bw / 2;
            var top = f.y(Math.max(0, Math.min(maxY, it[key]))), base = f.y(0), r = Math.min(4, (base - top) / 2, bw / 2);
            xs.push(cx);
            var d = "M" + x + " " + base + " L" + x + " " + (top + r) + " Q" + x + " " + top + " " + (x + r) + " " + top +
                " L" + (x + bw - r) + " " + top + " Q" + (x + bw) + " " + top + " " + (x + bw) + " " + (top + r) + " L" + (x + bw) + " " + base + " Z";
            svgEl("path", { d: d, fill: C.series, "fill-opacity": i === n - 1 ? 1 : 0.55 }, f.svg);
            var hit = svgEl("rect", { x: cx - band / 2, y: f.P.t, width: band, height: base - f.P.t, "class": "hit" }, f.svg);
            hit.addEventListener("mouseenter", function () {
                tip.show(cx * plot.clientWidth / f.W, top * plot.clientHeight / f.H, title + " · " + it.date, fmt(it[key]));
            });
            hit.addEventListener("mouseleave", tip.hide);
            if (i === n - 1) {
                var v = svgEl("text", { x: cx, y: Math.max(12, top - 5), "text-anchor": "middle", "class": "value-text" }, f.svg);
                v.textContent = fmt(it[key]);
            }
        });
        xLabels(f, xs, items);
    }

    function niceMax(v) {
        var steps = [100, 200, 300, 500, 800, 1000, 1500, 2000, 3000, 5000, 8000, 10000];
        for (var i = 0; i < steps.length; i++) if (v <= steps[i]) return steps[i];
        return Math.ceil(v / 5000) * 5000;
    }

    function renderHistory(r) {
        var items = list(r.history), t = r.totals || {};
        $("hist-title").textContent = "Tu progreso con " + r.weapon +
            (items.length === 1 ? " (1 sesión)" : " (últimas " + items.length + " sesiones)");

        // Fichas: tendencia = precision de esta sesion frente a la media de las anteriores
        var prev = items.slice(0, -1), prevAcc = 0;
        prev.forEach(function (it) { prevAcc += it.accuracy; });
        prevAcc = prev.length ? Math.round(prevAcc / prev.length) : null;
        var kpis = $("hist-kpis");
        kpis.textContent = "";
        function kpi(label, value, delta) {
            var d = el("div", "kpi");
            d.appendChild(el("small", "", label));
            var b = el("b", "", value);
            d.appendChild(b);
            if (delta) d.appendChild(el("span", "delta " + delta.cls, delta.text));
            kpis.appendChild(d);
        }
        kpi("Sesiones", String(t.sessions || 0));
        kpi("Precisión media", (t.accuracy || 0) + "%");
        kpi("Mejor puntuación", String(t.bestScore || 0));
        if (prevAcc === null) kpi("Tendencia", "—");
        else {
            var diff = r.accuracy - prevAcc;
            kpi("Tendencia (precisión)", (diff > 0 ? "+" : "") + diff + " pts",
                { cls: diff > 0 ? "up" : diff < 0 ? "down" : "flat", text: diff > 0 ? "▲ mejor" : diff < 0 ? "▼ peor" : "= igual" });
        }

        var maxScore = niceMax(Math.max.apply(null, items.map(function (it) { return it.score; }).concat([100])));
        var levels = list(r.levels).filter(function (l) { return l.from > 0; }).map(function (l) { return { v: l.from, label: l.name }; });
        // Se dibuja cuando la ventana ya tiene tamano (show() acaba de hacerla visible)
        setTimeout(function () {
            lineChart(document.querySelector("#chart-acc .plot"), items, "accuracy", 100, [0, 50, 100],
                function (v) { return Math.round(v) + "%"; }, "Precisión");
            barChart(document.querySelector("#chart-score .plot"), items, "score", maxScore, [0, maxScore / 2, maxScore],
                function (v) { return String(Math.round(v)); }, "Puntuación");
            lineChart(document.querySelector("#chart-skill .plot"), items, "skill", r.skillMax || 1000, [0, 500, 1000],
                function (v) { return String(Math.round(v)); }, "Habilidad", levels);
        }, 30);
        $("hist-note").textContent = items.length < 2
            ? "Es tu primera sesión con esta arma: entrena más para ver tu tendencia."
            : "Total con esta arma: " + (t.shots || 0) + " disparos, " + (t.hits || 0) + " impactos. Mejor precisión: " + (t.bestAccuracy || 0) + "%.";
    }

    window.RP = {
        menu: function (d, ui) {
            data = d;
            clearInterval(timer);
            $("menu-title").textContent = ui.title;
            $("menu-sub").textContent = d.location || "";
            $("menu-player").textContent = "";
            var p = el("span");
            p.appendChild(document.createTextNode("Tirador: "));
            p.appendChild(el("b", "", d.player || "-"));
            p.appendChild(document.createTextNode("  ·  " + d.rounds + " rondas por sesión  ·  munición infinita (no gasta tus balas)" +
                (d.dailyRoom >= 0 ? "  ·  habilidad disponible hoy: " + d.dailyRoom + " pts" : "")));
            $("menu-player").appendChild(p);
            $("menu-foot").textContent = d.inside ? "Esc: salir del campo" : "Esc: cerrar";
            filter = "all";
            renderTabs();
            renderCards();
            show("menu");
        },
        start: function (info) {
            $("hud-weapon").textContent = info.weapon;
            $("hud-hint").textContent = "F2: salir del entrenamiento";
            RP.hud(info.hud);
            $("hud-banner").textContent = "";
            show("hud");
        },
        round: function (index, total, kind, delayMs, timeMs) {
            roundStart = Date.now() + delayMs;
            roundEnd = roundStart + timeMs;
            $("hud-round").textContent = "Ronda " + index + "/" + total + " · " + (kindNames[kind] || kind);
            clearInterval(timer);
            timer = setInterval(tickTime, 200);
            tickTime();
        },
        hud: function (h) {
            $("hud-ammo").textContent = h.ammo;
            $("hud-score").textContent = h.score;
            $("hud-acc").textContent = h.accuracy + "%";
            $("hud-level").textContent = "Habilidad: " + skillText(h.skill);
            $("hud-bar").className = "fill " + h.skill.key;
            $("hud-bar").style.width = Math.round(h.skill.progress * 100) + "%";
        },
        hit: function (zoneKey, zoneName, points) {
            var t = $("toast");
            t.textContent = "+" + points + " " + zoneName;
            t.classList.remove("show");
            void t.offsetWidth;
            t.classList.add("show");
        },
        results: function (r) {
            clearInterval(timer);
            var reasons = { done: "Sesión completada", abort: "Entrenamiento abandonado" };
            $("res-sub").textContent = r.weapon + " · " + (reasons[r.reason] || "");
            var box = $("res-stats");
            box.textContent = "";
            [["Disparos", r.shots], ["Impactos", r.hits], ["Fallos", r.misses], ["Precisión", r.accuracy + "%"], ["Puntuación", r.score]]
                .forEach(function (s) {
                    var d = el("div");
                    d.appendChild(el("small", "", s[0]));
                    d.appendChild(el("b", "", String(s[1])));
                    box.appendChild(d);
                });
            $("res-before").textContent = "Antes: " + skillText(r.before);
            $("res-after").textContent = "Ahora: " + skillText(r.after);
            $("res-bar").className = "fill " + r.before.key;
            $("res-bar").style.width = Math.round(r.before.progress * 100) + "%";
            $("res-bar-new").style.width = "0";
            $("res-gain").textContent = (r.gained > 0
                ? "Habilidad +" + r.gained + " puntos (solo impactos válidos)"
                : "Sin progreso: acierta los blancos para mejorar la habilidad.") +
                (r.capped ? " · Llegaste al tope de habilidad" + (r.dailyRoom === 0 ? " de hoy: vuelve mañana." : " de esta sesión.") : "");
            show("results");
            renderHistory(r);
            setTimeout(function () {
                $("res-bar-new").style.width = Math.round(r.after.progress * 100) + "%";
                if (r.after.key !== r.before.key) $("res-bar").style.width = "100%";
            }, 60);
        }
    };

    $("menu-close").addEventListener("click", function () { send("rp:range:ui:close"); });
    $("res-exit").addEventListener("click", function () { send("rp:range:ui:close"); });
    $("res-again").addEventListener("click", function () { send("rp:range:ui:again"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" && !$("hud").offsetParent) send("rp:range:ui:close");
    });
})();
