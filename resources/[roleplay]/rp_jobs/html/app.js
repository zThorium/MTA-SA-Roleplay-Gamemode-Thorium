/*
 * rp_jobs / app.js
 * Lua llama a:
 *   RP.game(nombre, params)   abre un minijuego (los minijuegos se registran con JG.register)
 *   RP.panel(datos)           panel de la sede del trabajo
 *   RP.market(datos)          punto de venta
 *   RP.summary(datos)         resumen al terminar el turno
 * El JS responde con mta.triggerEvent("rp:jobs:ui:result", json) / ui:close / ui:hq / ui:sell.
 * Abre index.html en un navegador normal con ?demo=compactor (u otro) para probar un minijuego.
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", JSON.stringify(args));
    }

    function el(tag, className, text) {
        var n = document.createElement(tag);
        if (className) n.className = className;
        if (text !== undefined && text !== null) n.textContent = text;
        return n;
    }

    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }
    function rgb(c) { return c ? "rgb(" + c[0] + "," + c[1] + "," + c[2] + ")" : "#f5a524"; }

    function hideAll() {
        ["game", "panel", "market", "summary"].forEach(function (id) { $(id).classList.add("hidden"); });
    }
    function show(id) {
        hideAll();
        $("backdrop").classList.remove("hidden");
        $(id).classList.remove("hidden");
    }

    /* ---------------- Sonidos sencillos (WebAudio) ---------------- */
    var audio = null;
    function sfx(kind) {
        try {
            audio = audio || new (window.AudioContext || window.webkitAudioContext)();
            var o = audio.createOscillator(), g = audio.createGain();
            var map = { hit: [520, 0.07, "square"], miss: [140, 0.15, "sawtooth"], good: [880, 0.12, "sine"],
                bad: [110, 0.25, "sawtooth"], tick: [1200, 0.03, "square"], splash: [200, 0.2, "triangle"],
                squish: [90, 0.18, "square"], shot: [70, 0.3, "sawtooth"] };
            var m = map[kind] || map.tick;
            o.type = m[2]; o.frequency.value = m[0];
            g.gain.setValueAtTime(0.08, audio.currentTime);
            g.gain.exponentialRampToValueAtTime(0.0001, audio.currentTime + m[1]);
            o.connect(g); g.connect(audio.destination);
            o.start(); o.stop(audio.currentTime + m[1]);
        } catch (e) { /* sin audio */ }
    }

    /* ---------------- Minijuegos ---------------- */
    var GAMES = {};
    var current = null;   // { finished, timers: [], cleanup: [] }

    function stopCurrent() {
        if (!current) return;
        current.finished = true;
        current.timers.forEach(function (t) { clearInterval(t); clearTimeout(t); });
        current.frames.forEach(function (f) { cancelAnimationFrame(f); });
        current.cleanup.forEach(function (fn) { try { fn(); } catch (e) { } });
        current = null;
    }

    function makeApi(stage) {
        var ctx = { finished: false, timers: [], frames: [], cleanup: [] };
        current = ctx;
        var api = {
            el: el, sfx: sfx, stage: stage,
            rand: function (a, b) { return a + Math.random() * (b - a); },
            randInt: function (a, b) { return Math.floor(a + Math.random() * (b - a + 1)); },
            done: function (result) {
                if (ctx.finished) return;
                ctx.finished = true;
                var r = result || {};
                setTimeout(function () {
                    stopCurrent();
                    send("rp:jobs:ui:result", JSON.stringify(r));
                }, r.delay || 700);
                delete r.delay;
            },
            every: function (ms, fn) { var t = setInterval(function () { if (!ctx.finished) fn(); }, ms); ctx.timers.push(t); return t; },
            after: function (ms, fn) { var t = setTimeout(function () { if (!ctx.finished) fn(); }, ms); ctx.timers.push(t); return t; },
            loop: function (fn) {
                var last = performance.now();
                function step(now) {
                    if (ctx.finished) return;
                    var dt = Math.min(0.05, (now - last) / 1000); last = now;
                    fn(dt, now);
                    ctx.frames.push(requestAnimationFrame(step));
                }
                ctx.frames.push(requestAnimationFrame(step));
            },
            on: function (target, ev, fn) {
                target.addEventListener(ev, fn);
                ctx.cleanup.push(function () { target.removeEventListener(ev, fn); });
            },
            // Cuenta atrás visible; onEnd se llama al llegar a 0
            timer: function (seconds, onEnd) {
                var left = seconds, t = $("game-timer");
                t.classList.remove("hidden", "low");
                t.textContent = left;
                api.every(1000, function () {
                    left -= 1;
                    t.textContent = Math.max(0, left);
                    if (left <= 5) t.classList.add("low");
                    if (left <= 0) { t.classList.add("hidden"); onEnd(); }
                });
            },
            help: function (text) { $("game-help").textContent = text; },
            foot: function (nodes) {
                var f = $("game-foot");
                f.innerHTML = "";
                (nodes || []).forEach(function (n) { f.appendChild(n); });
                f.classList.toggle("hidden", !nodes || !nodes.length);
            },
            flash: function (text, kind) {
                var n = el("div", "flash " + (kind || ""), text);
                stage.appendChild(n);
                setTimeout(function () { if (n.parentNode) n.parentNode.removeChild(n); }, 900);
            },
            // Posición del ratón relativa al escenario
            pos: function (e) {
                var r = stage.getBoundingClientRect();
                return { x: e.clientX - r.left, y: e.clientY - r.top, w: r.width, h: r.height };
            }
        };
        return api;
    }

    function startGame(name, params) {
        stopCurrent();
        var g = GAMES[name];
        params = params || {};
        document.documentElement.style.setProperty("--job", rgb(params.jobColor));
        var stage = $("game-stage");
        stage.innerHTML = "";
        stage.className = "stage stage-" + name;
        $("game-timer").classList.add("hidden");
        $("game-title").textContent = g ? g.title : name;
        $("game-help").textContent = g ? g.help : "";
        show("game");
        var api = makeApi(stage);
        api.foot([]);
        if (!g) { api.done({ fail: true }); return; }
        g.start(stage, params, api);
    }

    function cancel() {
        stopCurrent();
        send("rp:jobs:ui:close");
    }

    $("game-close").addEventListener("click", cancel);
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") { if (current) cancel(); else send("rp:jobs:ui:close"); }
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-close]"), function (b) {
        b.addEventListener("click", function () { send("rp:jobs:ui:close"); });
    });

    /* ---------------- Sede ---------------- */
    function renderPanel(d) {
        var job = d.job || {};
        document.documentElement.style.setProperty("--job", rgb(job.color));
        $("panel-title").textContent = (job.icon || "") + "  " + (job.name || "");
        $("panel-location").textContent = job.locationName || "";
        $("panel-desc").textContent = job.description || "";
        $("panel-level").textContent = d.level + (d.bonus ? "  (+" + d.bonus + "%)" : "");
        $("panel-earned").textContent = money(d.earned);
        $("panel-best").textContent = money(d.best);
        $("panel-tasks").textContent = d.tasks || 0;
        var pct = d.nextXP ? Math.round((d.xp - d.levelXP) / Math.max(1, d.nextXP - d.levelXP) * 100) : 100;
        $("panel-xp").style.width = Math.max(0, Math.min(100, pct)) + "%";
        $("panel-xptext").textContent = d.nextXP ? (d.xp + " / " + d.nextXP + " XP para el nivel " + (d.level + 1)) : (d.xp + " XP · nivel máximo");
        var perks = $("panel-perks");
        perks.innerHTML = "";
        (d.perks || []).forEach(function (p) { perks.appendChild(el("li", null, p)); });
        $("panel-pay").textContent = job.pay ? "Pago: " + job.pay : "";

        var actions = $("panel-actions");
        actions.innerHTML = "";
        function btn(text, cls, action, option, disabled, note) {
            var b = el("button", "btn " + (cls || ""), text);
            if (note) b.appendChild(el("span", "note", "(" + note + ")"));
            if (disabled) b.disabled = true;
            b.addEventListener("click", function () { send("rp:jobs:ui:hq", action, option || ""); });
            actions.appendChild(b);
        }
        if (d.onShift === job.id) {
            btn("Terminar turno", "primary", "stop");
        } else if (d.myJob === job.id) {
            if (d.onShift) {
                actions.appendChild(el("p", "muted small", "Ya estás de turno en otro trabajo."));
            } else if (d.options && d.options.length) {
                d.options.forEach(function (o) { btn(o.label, "primary", "start", o.id, !o.enabled, o.note); });
            } else {
                btn("Empezar turno", "primary", "start");
            }
            btn("Dejar el trabajo", "danger", "quit");
        } else if (d.canHire) {
            btn(d.myJob ? "Cambiarme a este trabajo" : "Pedir el puesto", "primary", "hire");
        } else {
            actions.appendChild(el("p", "muted small", "Para trabajar aquí, pide el puesto en la agencia de trabajos."));
        }
        show("panel");
    }

    /* ---------------- Punto de venta ---------------- */
    function renderMarket(d) {
        document.documentElement.style.setProperty("--job", "#f5a524");
        $("market-title").textContent = (d.icon || "") + "  " + (d.name || "");
        $("market-money").textContent = money(d.money);
        var list = $("market-list");
        list.innerHTML = "";
        (d.items || []).forEach(function (it) {
            var row = el("div", "row" + (it.have > 0 ? "" : " empty"));
            row.appendChild(el("div", "icon", it.icon));
            var info = el("div");
            info.appendChild(el("div", "name", it.name));
            info.appendChild(el("div", "sub", it.have > 0 ? ("Tienes " + it.have) : "No tienes"));
            row.appendChild(info);
            var price = el("div", "price");
            price.appendChild(document.createTextNode(money(it.price) + " "));
            var trend = el("span", "trend " + (it.trend > 0 ? "up" : (it.trend < 0 ? "down" : "")), it.trend > 0 ? "▲" : (it.trend < 0 ? "▼" : "•"));
            price.appendChild(trend);
            row.appendChild(price);
            var btns = el("div", "btns");
            if (it.have > 0) {
                var one = el("button", "btn", "Vender 1");
                one.addEventListener("click", function () { send("rp:jobs:ui:sell", it.id, 1); });
                btns.appendChild(one);
                if (it.have > 1) {
                    var all = el("button", "btn primary", "Todo");
                    all.addEventListener("click", function () { send("rp:jobs:ui:sell", it.id, it.have); });
                    btns.appendChild(all);
                }
            }
            row.appendChild(btns);
            list.appendChild(row);
        });
        show("market");
    }

    function renderSummary(d) {
        $("summary-title").textContent = "Turno terminado";
        $("summary-reason").textContent = d.reason || "";
        $("summary-earned").textContent = money(d.earned);
        $("summary-tasks").textContent = d.tasks || 0;
        $("summary-minutes").textContent = d.minutes || 0;
        show("summary");
    }

    window.JG = {
        register: function (name, def) { GAMES[name] = def; },
        sfx: sfx
    };

    window.RP = {
        game: startGame,
        panel: renderPanel,
        market: renderMarket,
        summary: renderSummary
    };

    // Vista previa fuera del juego: index.html?demo=compactor
    window.addEventListener("load", function () {
        var m = /demo=([a-z]+)/.exec(location.search);
        if (!m || window.mta) return;
        var demos = window.JG_DEMOS || {};
        var name = m[1];
        if (name === "panel") return renderPanel(demos.panel);
        if (name === "market") return renderMarket(demos.market);
        if (name === "summary") return renderSummary({ earned: 845, tasks: 12, minutes: 23, reason: "Terminaste tu turno." });
        startGame(name, demos[name] || {});
    });
})();
