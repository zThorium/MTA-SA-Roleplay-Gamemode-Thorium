/*
 * rp_driving / app.js
 * Lua llama a RP.menu(datos), RP.result(datos) y RP.card(datos).
 * Eventos hacia Lua: rp:driving:ui:close, rp:driving:ui:start(testId),
 * rp:driving:ui:menu, rp:driving:ui:reprint.
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var MEDALS = ["Sin medalla", "Bronce", "Plata", "Oro", "Platino"];
    var MEDAL_SHORT = ["–", "B", "P", "O", "Pt"];
    var state = { menu: null, rankingTest: null, result: null };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);   // vista previa en un navegador normal
    }

    function el(tag, className, text) {
        var n = document.createElement(tag);
        if (className) n.className = className;
        if (text !== undefined && text !== null) n.textContent = text;   // textContent, nunca innerHTML con datos
        return n;
    }

    function list(x) {   // toJSON de Lua convierte {} en [] y a veces una lista en objeto
        if (!x) return [];
        if (Array.isArray(x)) return x;
        return Object.keys(x).map(function (k) { return x[k]; });
    }

    function secs(s) { return (Number(s) || 0).toFixed(2) + " s"; }

    function medalEl(medal, big) {
        medal = Number(medal) || 0;
        var m = el("div", "medal " + (medal > 0 ? "m" + medal : "none") + (big ? " big" : ""), MEDAL_SHORT[medal]);
        m.title = MEDALS[medal];
        return m;
    }

    function dot(medal) { return el("span", "dot m" + (Number(medal) || 0)); }

    function show(id) {
        ["menu", "result", "card"].forEach(function (v) { $(v).classList.toggle("hidden", v !== id); });
    }

    function close() { send("rp:driving:ui:close"); }

    document.querySelectorAll("[data-close]").forEach(function (b) { b.addEventListener("click", close); });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") close(); });

    // Pestanas
    function setTab(name) {
        document.querySelectorAll(".tabs button").forEach(function (b) { b.classList.toggle("active", b.getAttribute("data-tab") === name); });
        ["tests", "ranking", "license"].forEach(function (t) { $("tab-" + t).classList.toggle("hidden", t !== name); });
    }
    document.querySelectorAll(".tabs button").forEach(function (b) {
        b.addEventListener("click", function () { setTab(b.getAttribute("data-tab")); });
    });

    // ---------------------------------------------------------------- Menu
    function renderTests(data) {
        var box = $("tests");
        box.textContent = "";
        list(data.tests).forEach(function (t) {
            var card = el("div", "test" + (t.unlocked ? "" : " locked"));
            card.appendChild(t.unlocked ? medalEl(t.best ? t.best.medal : 0) : el("div", "medal lock", "🔒"));
            var info = el("div");
            info.appendChild(el("h3", null, t.index + ". " + t.name));
            info.appendChild(el("p", null, t.unlocked ? t.short : "Aprueba la prueba anterior para desbloquearla."));
            var stats = el("div", "stats");
            if (t.best && t.best.medal > 0) {
                var b = el("span"); b.appendChild(document.createTextNode("Mejor ")); b.appendChild(el("b", null, t.best.score + "%"));
                b.appendChild(document.createTextNode(" · " + secs(t.best.time)));
                stats.appendChild(b);
            } else {
                stats.appendChild(el("span", null, "Par " + t.par + " s · Platino " + t.platinum + " s"));
            }
            if (t.best && t.best.attempts) stats.appendChild(el("span", null, t.best.attempts + " intentos"));
            if (t.record) stats.appendChild(el("span", "record", "Record: " + t.record.name + " " + t.record.score + "%"));
            info.appendChild(stats);
            card.appendChild(info);
            if (t.unlocked) card.addEventListener("click", function () { send("rp:driving:ui:start", t.id); });
            box.appendChild(card);
        });
    }

    function boardRow(pos, name, sub, pts, medal, me) {
        var li = el("li", me ? "me" : "");
        li.appendChild(el("span", "pos", String(pos)));
        var n = el("span");
        n.appendChild(document.createTextNode(name + " "));
        n.appendChild(dot(medal));
        n.appendChild(el("span", "sub", sub));
        li.appendChild(n);
        li.appendChild(el("span", "pts", pts));
        return li;
    }

    function renderRanking(data) {
        var ol = $("overall");
        ol.textContent = "";
        var overall = list(data.overall);
        if (!overall.length) ol.appendChild(el("p", "empty", "Aun no hay resultados. ¡Se el primero!"));
        overall.forEach(function (r, i) {
            ol.appendChild(boardRow(i + 1, r.name, r.tests + " pruebas · " + r.golds + " oros · " + secs(r.time), r.total + " pts", r.medal));
        });

        var sel = $("ranking-test");
        sel.textContent = "";
        list(data.tests).forEach(function (t) {
            var o = el("option", null, t.index + ". " + t.name);
            o.value = t.id;
            sel.appendChild(o);
        });
        if (state.rankingTest) sel.value = state.rankingTest;
        renderPerTest();
    }

    function renderPerTest() {
        var data = state.menu;
        var testId = $("ranking-test").value;
        state.rankingTest = testId;
        var ol = $("per-test");
        ol.textContent = "";
        var per = (data.perTest && !Array.isArray(data.perTest)) ? list(data.perTest[testId]) : [];
        if (!per.length) ol.appendChild(el("p", "empty", "Nadie ha aprobado esta prueba todavia."));
        per.forEach(function (r, i) {
            ol.appendChild(boardRow(i + 1, r.name, MEDALS[r.medal] + " · " + secs(r.time), r.score + "%", r.medal));
        });
    }
    $("ranking-test").addEventListener("change", renderPerTest);

    function renderLicense(data) {
        var box = $("license");
        box.textContent = "";
        var lic = data.license || {};
        var wrap = el("div", "license-box");
        var tests = list(data.tests);
        var passed = tests.filter(function (t) { return t.best && t.best.medal > 0; }).length;

        if (lic.status === "valid") {
            var p = el("p"); p.appendChild(document.createTextNode("Licencia vigente n.º "));
            p.appendChild(el("strong", null, lic.number)); p.appendChild(document.createTextNode(" · expedida el " + lic.issued));
            wrap.appendChild(p);
            if (lic.hasItem) {
                wrap.appendChild(el("p", null, "La llevas en el inventario. La policia puede pedirtela: ensenala con /mostrarlicencia <id>."));
            } else {
                wrap.appendChild(el("p", null, lic.pending ? "Tu licencia esta lista para recoger." : "No llevas el papel encima. Puedes pedir un duplicado."));
                var btn = el("button", "primary", lic.pending ? "Recoger licencia" : "Duplicado ($" + lic.reprintPrice + ")");
                btn.addEventListener("click", function () { send("rp:driving:ui:reprint"); });
                wrap.appendChild(btn);
            }
        } else if (lic.status === "revoked") {
            wrap.appendChild(el("p", null, "Tu licencia esta RETIRADA" + (lic.reason ? " (" + lic.reason + ")" : "") + "."));
            wrap.appendChild(el("p", null, "Aprueba de nuevo el examen final para rehabilitarla."));
        } else {
            wrap.appendChild(el("p", null, "Aprueba las " + tests.length + " pruebas (minimo bronce) para obtener tu licencia de conducir."));
        }
        wrap.appendChild(el("p", null, "Pruebas aprobadas: " + passed + " / " + tests.length));
        var bar = el("div", "progress"), fill = el("div");
        fill.style.width = (tests.length ? passed / tests.length * 100 : 0) + "%";
        bar.appendChild(fill);
        wrap.appendChild(bar);
        wrap.appendChild(el("p", "hint", "Medallas: bronce 70%, plata 85%, oro 100% y platino 100% por debajo del tiempo de platino. La distincion de tu licencia es tu peor medalla."));
        box.appendChild(wrap);
    }

    function renderMenu(data) {
        state.menu = data;
        var me = data.me || {};
        var s = $("summary");
        s.textContent = "";
        s.appendChild(document.createTextNode("Tu puntaje"));
        s.appendChild(el("strong", null, (me.total || 0) + " / " + (me.max || 0)));
        renderTests(data);
        renderRanking(data);
        renderLicense(data);
        setTab(data.view === "license" ? "license" : (data.view === "ranking" ? "ranking" : "tests"));
        show("menu");
    }

    // ---------------------------------------------------------------- Resultado
    function renderResult(r) {
        state.result = r;
        var top = $("result-medal");
        top.replaceWith(medalEl(r.passed ? r.medal : 0, true));
        top = document.querySelector(".result-top .medal");
        top.id = "result-medal";

        $("result-kicker").textContent = "Prueba " + r.index + " · " + r.name;
        var title = $("result-title");
        title.textContent = r.passed ? (MEDALS[r.medal] + "!") : "Suspendido";
        title.className = r.passed ? "" : "fail";
        $("result-sub").textContent = r.passed ? ("Tiempo " + secs(r.time) + " · par " + r.par + " s") : (r.reason || "");
        var sc = $("result-score");
        sc.textContent = "";
        if (r.score !== undefined && r.score !== null) {
            sc.appendChild(document.createTextNode(String(r.score)));
            sc.appendChild(el("small", null, "%"));
        }

        var badges = $("result-badges");
        badges.textContent = "";
        if (r.schoolRecord) badges.appendChild(el("span", "badge hot", "★ Nuevo record de la autoescuela"));
        else if (r.improved) badges.appendChild(el("span", "badge good", "Nuevo record personal"));
        if (r.unlocked) badges.appendChild(el("span", "badge", "Desbloqueada: " + r.unlocked));
        if (r.best && r.best.medal > 0 && !r.improved) badges.appendChild(el("span", "badge", "Tu mejor: " + r.best.score + "% · " + secs(r.best.time)));

        var table = $("result-breakdown");
        table.textContent = "";
        var b = r.breakdown || {};
        var rows = [
            ["Tiempo (" + secs(r.time) + ")", b.time],
            ["Dano del auto (" + (r.damage || 0) + ")", b.damage],
            ["Conos derribados (" + (r.cones || 0) + ")", b.cones],
        ];
        if (r.dist !== undefined && r.dist !== null) rows.push(["Precision al parar (" + r.dist + " m)", b.position]);
        if (r.angle !== undefined && r.angle !== null) rows.push(["Angulo al parar (" + r.angle + "°)", b.angle]);
        rows.forEach(function (row) {
            var tr = el("tr");
            tr.appendChild(el("td", null, row[0]));
            var v = Number(row[1]) || 0;
            tr.appendChild(el("td", v > 0 ? "minus" : "zero", r.passed || r.score !== undefined ? (v > 0 ? "-" + v : "0") : "–"));
            table.appendChild(tr);
        });

        var tiers = $("result-tiers");
        tiers.textContent = "";
        [[1, "70%"], [2, "85%"], [3, "100%"], [4, "100% < " + r.platinum + " s"]].forEach(function (t) {
            var d = el("div", r.passed && r.medal >= t[0] ? "reached" : "");
            d.appendChild(dot(t[0]));
            d.appendChild(document.createTextNode(MEDALS[t[0]] + " " + t[1]));
            tiers.appendChild(d);
        });

        $("btn-next").classList.toggle("hidden", !r.nextId);
        show("result");
    }

    $("btn-retry").addEventListener("click", function () { if (state.result) send("rp:driving:ui:start", state.result.testId); });
    $("btn-next").addEventListener("click", function () { if (state.result && state.result.nextId) send("rp:driving:ui:start", state.result.nextId); });
    $("btn-menu").addEventListener("click", function () { send("rp:driving:ui:menu"); });

    // ---------------------------------------------------------------- Tarjeta
    function renderCard(c) {
        var caption = { own: "Tu licencia de conducir", shown: (c.from || "Alguien") + " te ensena su licencia", check: "Registro de licencias · " + c.name };
        $("card-caption").textContent = caption[c.mode] || "";
        $("lc-name").textContent = c.name || "";
        $("lc-number").textContent = c.number || "—";
        $("lc-age").textContent = (c.age || "?") + " / " + (c.gender || "?");
        $("lc-issued").textContent = c.issued || "—";
        var medal = $("lc-medal");
        medal.textContent = "";
        medal.appendChild(dot(c.medal));
        medal.appendChild(document.createTextNode(" " + MEDALS[c.medal || 0] + " (" + (c.score || 0) + "/" + (c.maxScore || 0) + ")"));
        var initials = String(c.name || "?").split(" ").map(function (p) { return p.charAt(0); }).join("").slice(0, 2).toUpperCase();
        $("lc-photo").textContent = initials;
        var stamp = $("lc-stamp");
        var labels = { valid: "VIGENTE", revoked: "RETIRADA", none: "SIN LICENCIA" };
        stamp.textContent = labels[c.status] || "";
        stamp.className = "lc-stamp " + (c.status || "none");
        var note = "";
        if (c.status === "revoked") note = "Retirada el " + (c.revoked || "?") + (c.by ? " por " + c.by : "") + (c.reason ? ": " + c.reason : "") + ".";
        else if (c.status === "none") note = "No consta ninguna licencia de conducir a este nombre.";
        $("card-note").textContent = note;
        show("card");
    }

    window.RP = { menu: renderMenu, result: renderResult, card: renderCard };
})();
