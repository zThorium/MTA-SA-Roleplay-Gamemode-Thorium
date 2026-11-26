/*
 * rp_firefighters / app.js
 * Un solo documento con dos modos según el hash:
 *   #hud   (navegador dx sin entrada): FD.alert, FD.incident, FD.tick, FD.result, FD.sound, FD.setTop
 *   #panel (navegador de GUI con cursor): FD.panel
 * Sin window.mta (navegador normal) carga datos de ejemplo: index.html#hud, #result, #panel.
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var mode = (location.hash || "#hud").slice(1);

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

    function icon(id) {
        var ns = "http://www.w3.org/2000/svg";
        var s = document.createElementNS(ns, "svg");
        var u = document.createElementNS(ns, "use");
        u.setAttribute("href", "#" + id);
        s.appendChild(u);
        return s;
    }

    function mmss(s) {
        s = Math.max(0, Math.floor(s));
        var m = Math.floor(s / 60), r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }

    /* ---------------- Sonidos (UX-06): uno por evento ---------------- */
    var SOUNDS = {
        alert: ["sounds/kenney/error_006.ogg"],
        tick: ["sounds/kenney/tick_002.ogg"],
        focusOut: ["sounds/kenney/bong_001.ogg"],
        pickup: ["sounds/kenney/drop_001.ogg", "sounds/kenney/drop_002.ogg"],
        rescued: ["sounds/kenney/confirmation_001.ogg"],
        success: ["sounds/kenney/confirmation_003.ogg"],
        coins: ["sounds/coins.wav"],
        fail: ["sounds/kenney/error_004.ogg"],
        heartbeat: ["sounds/heartbeat.wav"],
        open: ["sounds/kenney/maximize_003.ogg"],
        close: ["sounds/kenney/minimize_003.ogg"],
        click: ["sounds/kenney/click_002.ogg"],
        guide: ["sounds/kenney/pluck_001.ogg"]
    };
    function play(name, volume) {
        var list = SOUNDS[name];
        if (!list) return;
        try {
            var a = new Audio(list[Math.floor(Math.random() * list.length)]);
            a.volume = volume || 0.7;
            a.play();
        } catch (e) { /* sin audio en la vista previa */ }
    }

    /* ---------------- HUD ---------------- */
    var inc = null;          // incidente actual
    var alertTimer = null, resultTimer = null;
    var lastStep = "", novice = false;

    var GUIDE = {
        "goto": { keys: [], text: "Ve a la emergencia: sigue el <b>blip naranja</b> del radar." },
        extinguish: { keys: ["mouse_left"], text: "Saca el <b>extintor</b> (rueda) y mantén <b>clic izquierdo</b> apuntando a las llamas." },
        cannon: { keys: ["mouse_left", "or", "keyboard_ctrl"], text: "Apunta con la cámara y dispara el <b>cañón de agua</b> a los focos." },
        rescue: { keys: ["keyboard_e"], text: "Acércate a un civil (globo <b>!</b>) y pulsa <b>E</b> para cargarlo." },
        carry: { keys: [], text: "Llévalo a la <b>zona segura</b>: ambulancia y marcador rosa." },
        drop: { keys: ["keyboard_e"], text: "Pulsa <b>E</b> para dejarlo con los paramédicos." },
        wait: { keys: [], text: "Todo controlado. Espera el informe de la central." }
    };

    function renderGuide(step) {
        var g = GUIDE[step];
        var box = $("guide");
        if (!g) { box.classList.add("hidden"); return; }
        box.classList.remove("hidden");
        box.classList.toggle("novice", novice);
        if (step === lastStep) return;
        lastStep = step;
        var keys = $("guide-keys");
        keys.innerHTML = "";
        g.keys.forEach(function (k) {
            if (k === "or") { keys.appendChild(el("span", "or", "o")); return; }
            var img = el("img");
            img.src = "../images/keys/" + k + ".png";
            keys.appendChild(img);
        });
        keys.classList.toggle("hidden", g.keys.length === 0);
        $("guide-text").innerHTML = g.text;          // textos fijos de GUIDE, nunca datos de jugadores
        box.classList.remove("flash");
        void box.offsetWidth;
        box.classList.add("flash");
        if (novice) play("guide", 0.5);
    }

    var STATE_LABEL = { trapped: "Atrapado", carried: "A hombros", safe: "A salvo", dead: "Fallecido" };

    function renderIncident() {
        if (!inc) { $("inc").classList.add("hidden"); $("urgency").classList.remove("on"); return; }
        $("inc").classList.remove("hidden");
        $("inc-name").textContent = inc.name;
        $("inc-zone").textContent = inc.zone;
        renderTick();
    }

    function renderTick() {
        if (!inc) return;
        var t = $("inc-time");
        t.textContent = mmss(inc.timeLeft);
        t.classList.toggle("low", inc.timeLeft <= 60);
        $("inc-bar").style.width = (100 * inc.timeLeft / inc.timeTotal) + "%";

        var foci = $("inc-foci"), alive = 0;
        if (foci.children.length !== inc.foci.length) {
            foci.innerHTML = "";
            inc.foci.forEach(function () {
                var f = el("div", "focus");
                f.appendChild(el("div", "lvl"));
                f.appendChild(icon("i-flame"));
                foci.appendChild(f);
            });
        }
        inc.foci.forEach(function (f, i) {
            var n = foci.children[i];
            if (f.hp > 0) alive++;
            var wasOut = n.classList.contains("out");
            n.classList.toggle("out", f.hp <= 0);
            n.firstChild.style.height = f.hp + "%";
            if (f.hp <= 0 && !wasOut) { n.classList.remove("pop"); void n.offsetWidth; n.classList.add("pop"); }
        });
        $("inc-foci-count").textContent = "· " + alive + " de " + inc.foci.length + " activos";

        var list = $("inc-victims"), safe = 0, urgent = false;
        list.innerHTML = "";
        inc.victims.forEach(function (v, i) {
            if (v.state === "safe") safe++;
            var low = (v.state === "trapped" || v.state === "carried") && v.life <= 60;
            if (low) urgent = true;
            var row = el("div", "victim " + v.state + (low ? " low" : ""));
            row.appendChild(icon("i-person"));
            var mid = el("div");
            mid.appendChild(el("div", "v-state", "Civil " + (i + 1) + " · " + (STATE_LABEL[v.state] || v.state)));
            if (v.state === "trapped" || v.state === "carried") {
                var bar = el("div", "bar"), fill = el("i");
                fill.style.width = (100 * v.life / inc.lifeTotal) + "%";
                bar.appendChild(fill);
                mid.appendChild(bar);
            }
            row.appendChild(mid);
            row.appendChild(el("div", "v-life", (v.state === "trapped" || v.state === "carried") ? mmss(v.life) : ""));
            list.appendChild(row);
        });
        $("inc-vic-count").textContent = "· " + safe + " de " + inc.victims.length + " a salvo";
        $("urgency").classList.toggle("on", urgent && !inc.ended);
        return urgent;
    }

    function hideAlert() {
        var a = $("alert");
        if (a.classList.contains("hidden")) return;
        a.classList.add("leaving");
        setTimeout(function () { a.classList.add("hidden"); a.classList.remove("leaving"); }, 450);
    }

    window.FD = {
        setTop: function (y) { document.documentElement.style.setProperty("--top", (Number(y) || 200) + 14 + "px"); },

        alert: function (a) {
            novice = !!a.novice;
            $("alert-name").textContent = a.name;
            $("alert-zone").textContent = a.zone;
            $("alert-coords").textContent = "X " + a.x.toFixed(1) + "  Y " + a.y.toFixed(1) + "  Z " + a.z.toFixed(1);
            $("alert-foci").textContent = a.foci;
            $("alert-victims").textContent = a.victims;
            $("alert-time").textContent = mmss(a.time);
            $("alert-life").textContent = mmss(a.life) + " min";
            var box = $("alert");
            box.classList.remove("hidden", "leaving");
            box.style.animation = "none"; void box.offsetWidth; box.style.animation = "";
            play("alert", 0.8);
            setTimeout(function () { play("alert", 0.8); }, 700);
            clearTimeout(alertTimer);
            alertTimer = setTimeout(hideAlert, 9000);
        },

        incident: function (d) {
            inc = d;
            lastStep = "";
            if (!d) hideAlert();
            renderIncident();
        },

        tick: function (t, step) {
            if (!inc) return;
            inc.timeLeft = t.t;
            (t.f || []).forEach(function (hp, i) { if (inc.foci[i]) inc.foci[i].hp = hp; });
            (t.v || []).forEach(function (v, i) { if (inc.victims[i]) { inc.victims[i].state = v[0]; inc.victims[i].life = v[1]; } });
            var urgent = renderTick();
            renderGuide(step);
            if (urgent) play("tick", 0.45);
            else if (inc.timeLeft <= 30) play("tick", 0.3);
        },

        result: function (r) {
            if (inc) inc.ended = true;
            $("urgency").classList.remove("on");
            var box = $("result");
            box.classList.remove("hidden", "leaving");
            box.classList.toggle("fail", !r.success);
            $("result-svg").firstChild.setAttribute("href", r.success ? "#i-check" : "#i-cross");
            $("result-kicker").textContent = r.name;
            $("result-title").textContent = r.success ? "EMERGENCIA RESUELTA" : "EMERGENCIA FALLIDA";
            $("result-reason").textContent = r.reason || "";
            var grid = $("result-grid");
            grid.innerHTML = "";
            function cell(cls, value, label) {
                var c = el("div", "cell " + cls);
                c.appendChild(el("b", null, value));
                c.appendChild(el("span", null, label));
                grid.appendChild(c);
                return c.firstChild;
            }
            cell("", r.rescued + "/" + r.victims, "civiles a salvo");
            if (r.participated) {
                var m = cell("money", money(0), "al banco");
                cell("gain", "+" + (r.xp || 0), "XP de facción");
                if (r.money > 0) countUp(m, r.money);
            } else {
                cell("", "—", "sin participación");
                cell("", "—", "sin XP");
            }
            $("result-rank").textContent = "";
            if (r.rank) {
                $("result-rank").appendChild(document.createTextNode("Rango: "));
                $("result-rank").appendChild(el("b", null, r.rank));
                $("result-rank").appendChild(document.createTextNode(" · " + (r.totalXp || 0) + " XP"));
            }
            if (r.success) { play("success"); if (r.money > 0) setTimeout(function () { play("coins"); }, 450); }
            else play("fail");
            clearTimeout(resultTimer);
            resultTimer = setTimeout(function () {
                box.classList.add("leaving");
                setTimeout(function () { box.classList.add("hidden"); }, 500);
            }, 8000);
        },

        sound: function (name) { play(name); },

        /* ---------------- Panel del vestuario ---------------- */
        panel: function (d) { renderPanel(d); }
    };

    function countUp(node, target) {
        var start = Date.now(), dur = 1200;
        (function step() {
            var k = Math.min(1, (Date.now() - start) / dur);
            node.textContent = money(Math.round(target * (1 - Math.pow(1 - k, 3))));
            if (k < 1) requestAnimationFrame(step);
        })();
    }

    /* ---------------- Panel ---------------- */
    var panelData = null, chosenSkin = null;
    var SKIN_COLORS = ["#ff6a2b", "#d9b04a", "#e8473a"];

    // Silueta del uniforme (no hay imágenes de skins: son material de Rockstar)
    function figure(color) {
        var ns = "http://www.w3.org/2000/svg";
        var s = document.createElementNS(ns, "svg");
        s.setAttribute("viewBox", "0 0 70 100");
        s.innerHTML =
            '<path d="M14 26a21 15 0 0 1 42 0v3H14z" fill="' + color + '"/>' +
            '<rect x="10" y="27" width="50" height="4" rx="2" fill="' + color + '"/>' +
            '<circle cx="35" cy="37" r="9" fill="#d9b7a0"/>' +
            '<path d="M16 100V62a19 16 0 0 1 38 0v38z" fill="#3a2a22"/>' +
            '<rect x="16" y="70" width="38" height="4" fill="#e8e05a"/><rect x="16" y="84" width="38" height="4" fill="#e8e05a"/>';
        return s;
    }

    function renderPanel(d) {
        panelData = d;
        if (chosenSkin === null) chosenSkin = d.skin;
        $("panel").classList.remove("hidden");

        var skins = $("skins");
        skins.innerHTML = "";
        d.skins.forEach(function (sk, i) {
            var c = el("div", "skin" + (sk.id === chosenSkin ? " sel" : ""));
            var fig = el("div", "fig");
            fig.appendChild(figure(SKIN_COLORS[i % SKIN_COLORS.length]));
            c.appendChild(fig);
            c.appendChild(el("div", "s-id", "#" + sk.id));
            c.appendChild(el("div", "s-name", sk.name));
            c.addEventListener("click", function () { chosenSkin = sk.id; play("click"); renderPanel(panelData); });
            skins.appendChild(c);
        });

        var eq = $("equip");
        eq.innerHTML = "";
        d.equipment.forEach(function (name) {
            var r = el("div", "eq");
            r.appendChild(icon("i-check"));
            r.appendChild(el("span", null, name));
            eq.appendChild(r);
        });

        var btn = $("duty-btn");
        var changing = d.onDuty && chosenSkin !== d.skin;
        btn.classList.toggle("off", d.onDuty && !changing);
        $("duty-label").textContent = !d.onDuty ? "ENTRAR DE SERVICIO" : (changing ? "CAMBIAR UNIFORME" : "SALIR DE SERVICIO");
        $("duty-hint").textContent = d.onDuty
            ? "Al salir devuelves el equipo y recuperas tu ropa."
            : "De servicio recibes alertas de emergencia y cobras el sueldo de tu rol.";

        $("badge-n").textContent = d.rankIndex;
        $("p-name").textContent = d.name;
        $("p-rank").textContent = d.rank;
        var s = d.stats;
        $("xp-text").textContent = s.xp + " XP";
        var pct = d.nextXp ? 100 * (s.xp - d.rankXp) / (d.nextXp - d.rankXp) : 100;
        $("xp-bar").style.width = Math.max(2, Math.min(100, pct)) + "%";
        $("xp-next").textContent = d.nextXp ? ("Faltan " + (d.nextXp - s.xp) + " XP para el siguiente rango") : "Rango máximo";

        var st = $("stats");
        st.innerHTML = "";
        [[s.fires, "Focos apagados"], [s.rescues, "Civiles rescatados"], [s.ok, "Emergencias resueltas"], [s.failed, "Emergencias fallidas"]]
            .forEach(function (x) {
                var c = el("div", "stat");
                c.appendChild(el("b", null, String(x[0])));
                c.appendChild(el("span", null, x[1]));
                st.appendChild(c);
            });

        var status = $("status");
        status.className = "status" + (d.onDuty ? " on" : "");
        status.innerHTML = "";
        status.appendChild(el("span", "dot"));
        status.appendChild(el("span", null, d.onDuty
            ? ("De servicio · " + d.colleagues + " bombero" + (d.colleagues === 1 ? "" : "s") + " en turno")
            : ("Fuera de servicio · " + d.colleagues + " en turno")));

        coach(d);
    }

    // Entrenador: la primera vez, señala el botón de servicio
    function coach(d) {
        var win = document.querySelector(".window");
        var old = win.querySelector(".coach-dim");
        if (old) old.remove();
        $("duty-btn").classList.remove("coach-spot");
        var bubble = $("coach");
        bubble.classList.add("hidden");
        if (d.onDuty || (d.stats.ok + d.stats.failed) > 0) return;
        win.appendChild(el("div", "coach-dim"));
        var btn = $("duty-btn");
        btn.classList.add("coach-spot");
        bubble.innerHTML = "";
        bubble.appendChild(el("small", null, "Paso 1 de 1"));
        bubble.appendChild(document.createTextNode("Elige uniforme y entra de servicio para recibir emergencias."));
        bubble.classList.remove("hidden");
        // offsetTop/Left (relativos a .window) no les afecta la animación de escala de entrada
        bubble.style.left = btn.offsetLeft + "px";
        bubble.style.top = (btn.offsetTop - bubble.offsetHeight - 14) + "px";
    }

    $("duty-btn").addEventListener("click", function () {
        if (!panelData) return;
        play("click");
        if (panelData.onDuty && chosenSkin === panelData.skin) send("rp:firefighters:ui:off");
        else send("rp:firefighters:ui:duty", chosenSkin);
    });
    function closePanel() { play("close"); send("rp:firefighters:ui:close"); }
    $("btn-close").addEventListener("click", closePanel);
    document.addEventListener("keydown", function (e) { if (e.key === "Escape" && mode === "panel") closePanel(); });

    /* ---------------- Arranque y vista previa ---------------- */
    if (mode === "panel") { play("open"); $("hud").classList.add("hidden"); }
    else $("hud").classList.remove("hidden");

    if (!window.mta) {
        var demoInc = {
            id: 1, name: "Edificio Calton Heights", zone: "Calton Heights, San Fierro", x: -2134.5, y: 1012.3, z: 79.8,
            extractRadius: 7, timeLeft: 296, timeTotal: 480, lifeTotal: 300,
            foci: [{ hp: 100 }, { hp: 64 }, { hp: 0 }, { hp: 22 }, { hp: 0 }],
            victims: [{ state: "trapped", life: 41 }, { state: "carried", life: 180 }, { state: "safe", life: 200 }]
        };
        if (mode === "hud") {
            FD.alert({ name: demoInc.name, zone: demoInc.zone, x: demoInc.x, y: demoInc.y, z: demoInc.z, foci: 5, victims: 3, time: 480, life: 300, novice: true });
            FD.incident(demoInc);
            FD.tick({ t: 296, f: [100, 64, 0, 22, 0], v: [["trapped", 41], ["carried", 180], ["safe", 200]] }, "rescue");
        } else if (mode === "result") {
            $("hud").classList.remove("hidden");
            FD.result({ success: true, name: demoInc.name, reason: "Fuego extinguido y civiles a salvo.", participated: true,
                rescued: 3, victims: 3, money: 1290, xp: 85, rank: "Bombero", totalXp: 335 });
        } else if (mode === "panel") {
            FD.panel({ onDuty: false, skin: 277, name: "Martina Rojas", skins: [{ id: 277, name: "Estructural" }, { id: 278, name: "Forestal" }, { id: 279, name: "Rescate" }],
                equipment: ["Extintor", "Motosierra de rescate"], stats: { xp: 335, fires: 14, rescues: 6, ok: 0, failed: 0 },
                rank: "Bombero", rankIndex: 2, rankCount: 5, rankXp: 250, nextXp: 700, colleagues: 3 });
        }
    }
})();
