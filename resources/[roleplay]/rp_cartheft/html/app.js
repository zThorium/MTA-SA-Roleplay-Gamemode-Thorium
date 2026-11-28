/*
 * rp_cartheft / app.js
 * Minijuegos del robo de vehiculos. Lua llama a RP.start(modo, config, tutorial):
 *   "pick"  cerradura: Espacio o clic cuando la aguja esta en la zona verde, un pin cada vez
 *   "wire"  puente: une cada cable con el borne de su color y da la chispa con Espacio o clic
 * Al terminar: mta.triggerEvent("rp:cartheft:ui:result", modo, ok). Esc: "rp:cartheft:ui:cancel".
 * Vista previa sin el juego: index.html#pick o index.html#wire (con tutorial).
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    function el(tag, className, text) {
        var n = document.createElement(tag);
        if (className) n.className = className;
        if (text !== undefined) n.textContent = text;
        return n;
    }

    // Sonidos (paleta estandar de assets/README.md)
    var SOUNDS = {
        open: ["maximize_003"], close: ["minimize_003"], step: ["pluck_001"],
        pin: ["click_002", "click_004"], scrape: ["impactMetal_light_002"], good: ["confirmation_002"],
        win: ["confirmation_003"], bad: ["error_004"], fail: ["error_006"], shock: ["glitch_002"], select: ["select_002"]
    };
    function play(name) {
        var list = SOUNDS[name];
        if (!list) return;
        var a = new Audio("sounds/kenney/" + list[Math.floor(Math.random() * list.length)] + ".ogg");
        a.volume = 0.6;
        a.play().catch(function () {});
    }

    var mode = null, cfg = null, tutorial = false, finished = false;
    var needle = { pos: 0, dir: 1, speed: 1, zoneAt: 0, zoneW: 20, running: false };
    var pick = { pin: 0, misses: 0 };
    var wire = { colorsLeft: [], colorsRight: [], selected: null, done: 0, misses: 0, sparking: false };
    var COLORS = [
        { id: "rojo", hex: "#e2473f" }, { id: "azul", hex: "#3f7fe2" },
        { id: "amarillo", hex: "#f2c94c" }, { id: "verde", hex: "#4cd38a" }
    ];

    function flash(kind) {
        var f = $("flash");
        f.className = "flash";
        void f.offsetWidth;
        f.className = "flash " + kind;
        if (kind === "bad") {
            var w = $("win");
            w.classList.remove("shake");
            void w.offsetWidth;
            w.classList.add("shake");
        }
    }

    function lives(id, lost, total) {
        var box = $(id);
        box.innerHTML = "";
        for (var i = 0; i < total; i++) box.appendChild(el("span", i < total - lost ? "" : "lost"));
    }

    function hint(img, text) {
        var h = el("div", "hint");
        var i = el("img", "key-ico");
        i.src = "images/" + img + ".png";
        h.appendChild(i);
        h.appendChild(el("span", "", text));
        return h;
    }

    function setHints(list) {
        var f = $("hints");
        f.innerHTML = "";
        for (var i = 0; i < list.length; i++) f.appendChild(hint(list[i][0], list[i][1]));
    }

    // ---------------------------------------------------------- entrenador
    var spot = null;
    function coach(target, step, html) {
        if (spot) spot.classList.remove("coach-spot");
        spot = null;
        if (!tutorial || !target) {
            $("coach").classList.add("hidden");
            $("coach-dim").classList.add("hidden");
            return;
        }
        spot = target;
        spot.classList.add("coach-spot");
        $("coach-dim").classList.remove("hidden");
        $("coach").classList.remove("hidden");
        $("coach-step").textContent = step;
        var t = $("coach-text");
        t.innerHTML = "";
        for (var i = 0; i < html.length; i++) {
            if (html[i].img) {
                var im = el("img");
                im.src = "images/" + html[i].img + ".png";
                t.appendChild(im);
            } else t.appendChild(el("span", "", html[i]));
        }
    }

    // ---------------------------------------------------------- aguja
    function placeZone(zoneEl, w) {
        needle.zoneW = w;
        needle.zoneAt = 10 + Math.random() * (80 - w);
        zoneEl.style.left = needle.zoneAt + "%";
        zoneEl.style.width = w + "%";
    }

    var last = 0;
    function tick(t) {
        if (!mode || finished) return;
        var dt = last ? Math.min(0.05, (t - last) / 1000) : 0;
        last = t;
        if (needle.running) {
            needle.pos += needle.dir * needle.speed * 200 * dt;   // 100% ida en 1/(2*speed) s
            if (needle.pos >= 100) { needle.pos = 100; needle.dir = -1; }
            if (needle.pos <= 0) { needle.pos = 0; needle.dir = 1; }
            var n = mode === "pick" ? $("pick-needle") : $("spark-needle");
            n.style.left = needle.pos + "%";
        }
        requestAnimationFrame(tick);
    }

    function inZone() { return needle.pos >= needle.zoneAt && needle.pos <= needle.zoneAt + needle.zoneW; }

    function end(ok) {
        if (finished) return;
        finished = true;
        needle.running = false;
        play(ok ? "win" : "fail");
        flash(ok ? "ok" : "bad");
        if (tutorial) send("rp:cartheft:ui:tutorialSeen", mode);
        var m = mode;
        setTimeout(function () { send("rp:cartheft:ui:result", m, ok); }, 700);
    }

    // ---------------------------------------------------------- cerradura
    function pickRefresh() {
        var pins = $("pins").children;
        for (var i = 0; i < pins.length; i++) {
            pins[i].className = "pin" + (i < pick.pin ? " up" : "") + (i === pick.pin ? " current" : "");
        }
        $("pick-count").textContent = "Pin " + Math.min(pick.pin + 1, cfg.PINS) + " de " + cfg.PINS;
        lives("pick-lives", pick.misses, cfg.MISSES);
        coach($("pick-track"), "Paso " + (pick.pin + 1) + " de " + cfg.PINS,
            ["Pulsa", { img: "keyboard_space" }, "o", { img: "mouse_left" }, "cuando la aguja blanca este en la zona verde"]);
    }

    function startPick() {
        $("eyebrow").textContent = "Paso 1 de 2 · Robo de vehiculo";
        $("title").textContent = "Forzar la cerradura";
        var pins = $("pins");
        pins.innerHTML = "";
        for (var i = 0; i < cfg.PINS; i++) {
            var p = el("div", "pin");
            p.appendChild(el("div", "body"));
            pins.appendChild(p);
        }
        pick.pin = 0; pick.misses = 0;
        nextPin();
        setHints([["keyboard_space", "Levantar pin"], ["mouse_left", "Tambien con clic"], ["keyboard_escape", "Salir"]]);
    }

    function nextPin() {
        needle.pos = 0; needle.dir = 1;
        needle.speed = (cfg.SPEED[pick.pin] || cfg.SPEED[cfg.SPEED.length - 1]);
        placeZone($("pick-zone"), cfg.ZONE[pick.pin] || cfg.ZONE[cfg.ZONE.length - 1]);
        needle.running = true;
        pickRefresh();
    }

    function pickAction() {
        if (!needle.running) return;
        if (inZone()) {
            pick.pin++;
            play("pin");
            flash("ok");
            if (pick.pin >= cfg.PINS) { pickRefresh(); coach(null); return end(true); }
            play("step");
            nextPin();
        } else {
            pick.misses++;
            play("scrape");
            flash("bad");
            pickRefresh();
            if (pick.misses >= cfg.MISSES) { coach(null); return end(false); }
        }
    }

    // ---------------------------------------------------------- puente
    function shuffle(a) {
        for (var i = a.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1)), t = a[i];
            a[i] = a[j]; a[j] = t;
        }
        return a;
    }

    function wireButton(c, side) {
        var b = el("div", "wire", c.id);
        b.style.background = c.hex;
        b.setAttribute("data-color", c.id);
        b.addEventListener("click", function () { onWire(side, b); });
        return b;
    }

    function wireRefresh() {
        $("wire-count").textContent = wire.sparking ? "Chispa" : ("Cables " + wire.done + " de " + cfg.PAIRS);
        lives("wire-lives", wire.misses, cfg.MISSES);
        if (wire.sparking) {
            return coach($("spark-track"), "Ultimo paso",
                ["Pulsa", { img: "keyboard_space" }, "o", { img: "mouse_left" }, "en la zona verde para dar la chispa"]);
        }
        var left = $("wires-left").children, target = null;
        for (var i = 0; i < left.length; i++) {
            if (!left[i].classList.contains("done")) { target = left[i]; break; }
        }
        if (wire.selected) {
            var color = wire.selected.getAttribute("data-color"), right = $("wires-right").children;
            for (var k = 0; k < right.length; k++) {
                if (right[k].getAttribute("data-color") === color) { target = right[k]; break; }
            }
            coach(target, "Cable " + (wire.done + 1) + " de " + cfg.PAIRS,
                [{ img: "mouse_left" }, "Ahora el borne del mismo color a la derecha"]);
        } else {
            coach(target, "Cable " + (wire.done + 1) + " de " + cfg.PAIRS,
                [{ img: "mouse_left" }, "Haz clic en un cable de la izquierda"]);
        }
    }

    function drawLink(a, b, hex) {
        var board = $("board").getBoundingClientRect(), ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
        var line = document.createElementNS("http://www.w3.org/2000/svg", "line");
        line.setAttribute("x1", ra.right - board.left); line.setAttribute("y1", ra.top + ra.height / 2 - board.top);
        line.setAttribute("x2", rb.left - board.left); line.setAttribute("y2", rb.top + rb.height / 2 - board.top);
        line.setAttribute("stroke", hex); line.setAttribute("stroke-width", "6"); line.setAttribute("stroke-linecap", "round");
        $("links").appendChild(line);
    }

    function onWire(side, b) {
        if (finished || wire.sparking || b.classList.contains("done")) return;
        if (side === "left") {
            if (wire.selected) wire.selected.classList.remove("selected");
            wire.selected = b;
            b.classList.add("selected");
            play("select");
            return wireRefresh();
        }
        if (!wire.selected) return;
        var a = wire.selected;
        a.classList.remove("selected");
        wire.selected = null;
        if (a.getAttribute("data-color") === b.getAttribute("data-color")) {
            a.classList.add("done"); b.classList.add("done");
            drawLink(a, b, a.style.background);
            wire.done++;
            play("good");
            flash("ok");
            if (wire.done >= cfg.PAIRS) {
                wire.sparking = true;
                $("spark").classList.remove("hidden");
                needle.pos = 0; needle.dir = 1; needle.speed = cfg.SPARK_SPEED;
                placeZone($("spark-zone"), cfg.SPARK_ZONE);
                needle.running = true;
                play("step");
                setHints([["keyboard_space", "Dar la chispa"], ["mouse_left", "Tambien con clic"], ["keyboard_escape", "Salir"]]);
            }
        } else {
            wireMiss();
        }
        wireRefresh();
    }

    function wireMiss() {
        wire.misses++;
        play("shock");
        flash("bad");
        if (wire.misses >= cfg.MISSES) { coach(null); end(false); }
    }

    function sparkAction() {
        if (!wire.sparking || !needle.running) return;
        if (inZone()) { needle.running = false; coach(null); return end(true); }
        wireMiss();
        wireRefresh();
    }

    function startWire() {
        $("eyebrow").textContent = "Paso 2 de 2 · Robo de vehiculo";
        $("title").textContent = "Hacer el puente";
        var colors = shuffle(COLORS.slice()).slice(0, cfg.PAIRS);
        var left = $("wires-left"), right = $("wires-right");
        left.innerHTML = ""; right.innerHTML = ""; $("links").innerHTML = "";
        var i;
        for (i = 0; i < colors.length; i++) left.appendChild(wireButton(colors[i], "left"));
        var shuffled = shuffle(colors.slice());
        for (i = 0; i < shuffled.length; i++) right.appendChild(wireButton(shuffled[i], "right"));
        wire.selected = null; wire.done = 0; wire.misses = 0; wire.sparking = false;
        $("spark").classList.add("hidden");
        setHints([["mouse_left", "Unir cables del mismo color"], ["keyboard_escape", "Salir"]]);
        wireRefresh();
    }

    // ---------------------------------------------------------- entrada
    function action() {
        if (finished) return;
        if (mode === "pick") pickAction();
        else if (mode === "wire") sparkAction();
    }

    document.addEventListener("keydown", function (e) {
        if (e.repeat) return;
        if (e.key === "Escape") { play("close"); return send("rp:cartheft:ui:cancel"); }
        if (e.code === "Space") { e.preventDefault(); action(); }
    });
    $("pick-track").addEventListener("mousedown", action);
    $("pins").addEventListener("mousedown", action);
    $("spark-track").addEventListener("mousedown", action);
    $("btn-close").addEventListener("click", function () { play("close"); send("rp:cartheft:ui:cancel"); });

    window.RP = {
        start: function (m, config, showTutorial) {
            mode = m; cfg = config; tutorial = !!showTutorial; finished = false; last = 0;
            $("pick").classList.toggle("hidden", m !== "pick");
            $("wire").classList.toggle("hidden", m !== "wire");
            play("open");
            if (m === "pick") startPick(); else startWire();
            requestAnimationFrame(tick);
        }
    };

    // Vista previa en un navegador normal
    if (!window.mta) {
        var demo = (location.hash || "#pick").substring(1);
        if (demo === "wire") RP.start("wire", { PAIRS: 3, MISSES: 3, SPARK_ZONE: 18, SPARK_SPEED: 1.1 }, true);
        else RP.start("pick", { PINS: 3, ZONE: [22, 16, 11], SPEED: [0.9, 1.15, 1.4], MISSES: 3 }, true);
    }
})();
