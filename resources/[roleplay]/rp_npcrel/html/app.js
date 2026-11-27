/*
 * rp_npcrel / app.js
 * Panel de la conversacion (ficha, acciones, dialogo, tutorial) y panel /vinculos.
 * Lua llama a:
 *   RP.open(data, tutorial)   abre la escena con el saludo
 *   RP.result(res)            resultado de una accion (frases, ganancias, etapa)
 *   RP.unbusy()               el servidor no respondio: vuelve a permitir elegir
 *   RP.toast(text, love)      aviso corto (numero guardado...)
 *   RP.close()                cierra la escena
 *   RP.list(list, max, days)  abre /vinculos
 *   RP.closeList()
 * Manda a Lua: rp:npcrel:ui:pick(id), rp:npcrel:ui:leave, rp:npcrel:ui:closeList, rp:npcrel:ui:tutorialDone
 * Vista previa sin el juego: index.html#demo o index.html#lista
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
        if (text !== undefined && text !== null) n.textContent = text;   // nunca innerHTML con datos
        return n;
    }

    function restart(node, cls) { node.classList.remove(cls); void node.offsetWidth; node.classList.add(cls); }

    // ------------------------------------------------------------ sonidos (Kenney, CC0)
    var SOUNDS = {
        open: ["maximize_003"], close: ["minimize_003"], hover: ["select_002"], pick: ["click_002"],
        good: ["confirmation_002"], great: ["confirmation_003"], bad: ["error_004"], bored: ["question_001"],
        stage: ["confirmation_003"], toast: ["glass_001"], coach: ["pluck_001"]
    };
    var lastHover = 0;
    function play(name, vol) {
        var list = SOUNDS[name];
        if (!list) return;
        if (name === "hover") { var t = Date.now(); if (t - lastHover < 70) return; lastHover = t; }
        try {
            var a = new Audio("sounds/kenney/" + list[Math.floor(Math.random() * list.length)] + ".ogg");
            a.volume = vol || 0.45;
            a.play();
        } catch (e) { /* sin audio */ }
    }

    // ------------------------------------------------------------ datos fijos
    var STAGE_ICONS = ["👤", "🙂", "🤝", "😍", "💞", "💍"];
    var STAGE_NAMES = ["Desconocido", "Conocido", "Amigo", "Coqueteo", "Pareja", "Pareja estable"];
    var KIND_TITLE = { friend: "Amistad", romance: "Romance", special: "Especial" };
    var KIND_ORDER = ["friend", "romance", "special"];
    var MOOD_ICON = { happy: "😊", calm: "🙂", sad: "😔" };

    var state = null;          // ultimo snapshot del servidor
    var keyMap = {};           // "1".."0" -> id de accion
    var busy = false, ended = false, coachStep = 0;
    var typer = null, queue = [];

    // toJSON de Lua puede mandar una tabla vacia como objeto: siempre listas reales
    function arr(x) { return Array.isArray(x) ? x : []; }

    function phoneText(n) { n = String(n || ""); return n.length === 7 ? n.slice(0, 3) + "-" + n.slice(3) : n; }

    // ------------------------------------------------------------ ficha
    function setAvatar(box, letterNode, badgeNode, d) {
        box.classList.toggle("f", d.gender === 1);
        letterNode.textContent = (d.name || "?").charAt(0).toUpperCase();
        if (badgeNode) badgeNode.classList.toggle("hidden", !d.dating);
    }

    function renderPath(stage) {
        var ol = $("path");
        ol.textContent = "";
        for (var i = 1; i <= 6; i++) {
            var li = el("li", i < stage ? "done" : (i === stage ? "now" : ""));
            var n = el("div", "node", STAGE_ICONS[i - 1]);
            n.title = STAGE_NAMES[i - 1];
            li.appendChild(n);
            ol.appendChild(li);
        }
    }

    function renderMarks(id, marks, value) {
        var box = $(id);
        box.textContent = "";
        marks.forEach(function (m) {
            var d = el("div", "mark" + (value >= m.v ? " ok" : ""));
            d.style.left = m.v + "%";
            d.title = m.t;
            d.appendChild(el("span", null, m.t));
            box.appendChild(d);
        });
    }

    function renderTraits(d, prev) {
        var box = $("traits");
        box.textContent = "";
        var known = arr(d.traits);
        for (var i = 0; i < (d.traitCount || 2); i++) {
            if (known[i]) {
                var isNew = prev && arr(prev.traits).indexOf(known[i]) === -1;
                box.appendChild(el("span", "trait" + (isNew ? " new" : ""), known[i]));
            } else {
                var u = el("span", "trait unknown", "???");
                u.title = i === 0 ? "Se descubre al ser Conocidos" : "Se descubre al ser Amigos";
                box.appendChild(u);
            }
        }
    }

    function renderEnergy(d) {
        var box = $("energy");
        box.textContent = "";
        var total = d.total || 14, left = Math.max(0, d.left || 0);
        for (var i = 0; i < total; i++) box.appendChild(el("i", i < left ? "" : "off"));
        box.classList.toggle("low", left <= 4 && left > 1);
        box.classList.toggle("empty", left <= 1);
        box.title = "Le quedan " + left + " temas de conversación";
    }

    function renderCard(d, prev) {
        setAvatar($("avatar"), $("avatar-letter"), $("avatar-badge"), d);
        $("name").textContent = d.name;
        var chip = $("stage-chip");
        chip.textContent = d.stageName;
        chip.className = "chip s" + d.stage;
        if (prev && prev.stage !== d.stage) restart(chip, "pop");
        $("mood").textContent = (MOOD_ICON[d.moodKey] || "") + " " + (d.mood || "");
        renderPath(d.stage);

        $("fill-f").style.width = Math.max(0, Math.min(100, d.friendship)) + "%";
        $("fill-r").style.width = Math.max(0, Math.min(100, d.romance)) + "%";
        $("val-f").textContent = d.friendship;
        $("val-r").textContent = d.romance;
        var r = d.rules || { known: 15, friend: 40, crush: 30, askout: 60, stable: 90 };
        renderMarks("marks-f", [{ v: r.known, t: "Conocido" }, { v: r.friend, t: "Amigo" }], d.friendship);
        renderMarks("marks-r", [{ v: r.crush, t: "Se gustan" }, { v: r.askout, t: "Salir" }, { v: r.stable, t: "Estable" }], d.romance);

        var goal = $("goal");
        goal.textContent = d.goal || "";
        goal.classList.toggle("ready", /^¡/.test(d.goal || ""));
        renderTraits(d, prev);
        renderEnergy(d);
    }

    function floatGain(valId, trackId, n, cls) {
        if (!n) return;
        var g = el("span", "gain " + cls + (n < 0 ? " neg" : ""), (n > 0 ? "+" : "") + n);
        var host = $(valId).parentNode;
        host.style.position = "relative";
        host.appendChild(g);
        setTimeout(function () { if (g.parentNode) g.parentNode.removeChild(g); }, 1700);
        restart($(trackId).parentNode, "flash");
    }

    // ------------------------------------------------------------ acciones
    function renderActions(d) {
        var box = $("actions");
        box.textContent = "";
        keyMap = {};
        var n = 0;
        KIND_ORDER.forEach(function (kind) {
            var items = arr(d.actions).filter(function (a) { return a.kind === kind; });
            if (!items.length) return;
            box.appendChild(el("div", "group-title", KIND_TITLE[kind]));
            items.forEach(function (a) {
                var b = el("button", "act " + kind + (a.enabled ? "" : " locked"));
                b.dataset.id = a.id;
                var key = "";
                if (a.enabled) { n++; key = n === 10 ? "0" : String(n); keyMap[key] = a.id; }
                b.appendChild(el("kbd", null, key || "·"));
                b.appendChild(el("span", "ico", a.enabled ? a.icon : "🔒"));
                var txt = el("span", "txt");
                txt.appendChild(el("span", "lbl", a.label));
                txt.appendChild(el("span", "eff", a.effect || ""));
                b.appendChild(txt);
                var tagText = a.hint || (a.tired ? "Aburre" : (a.risky ? "Arriesgado" : ""));
                if (tagText) {
                    var cls = "tag";
                    if (!a.enabled) cls += "";
                    else if (/^\$/.test(tagText)) cls += " cost";
                    else if (/amig/.test(tagText)) cls += " no";
                    else if (a.tired || a.risky) cls += " tired";
                    b.appendChild(el("span", cls, tagText));
                }
                if (a.enabled) {
                    b.addEventListener("mouseenter", function () { play("hover", 0.25); });
                    b.addEventListener("click", function () { pick(a.id); });
                } else {
                    b.title = "Bloqueado: " + (a.hint || "");
                }
                box.appendChild(b);
            });
        });
        box.classList.toggle("busy", busy);
        box.classList.toggle("ended", ended);
    }

    function pick(id) {
        if (!state || busy || ended || coachStep) return;
        var btn = document.querySelector('.act[data-id="' + id + '"]');
        if (!btn || btn.classList.contains("locked")) return;
        busy = true;
        btn.classList.add("picked");
        $("actions").classList.add("busy");
        play("pick");
        send("rp:npcrel:ui:pick", id);
    }

    // ------------------------------------------------------------ dialogo
    function stopTyper() { if (typer) { clearInterval(typer); typer = null; } }

    function typeLine(item) {
        stopTyper();
        var line = document.querySelector(".npc-line");
        line.classList.remove("bad", "great");
        if (item.mood) line.classList.add(item.mood);
        restart(line, "npc-line");
        $("speaker").textContent = item.who;
        var box = $("npc-text");
        var chars = Array.from(item.text || "");   // respeta tildes y emojis
        var i = 0;
        box.textContent = "";
        var caret = el("span", "caret", "▍");
        typer = setInterval(function () {
            i = Math.min(chars.length, i + 1);
            box.textContent = chars.slice(0, i).join("");
            if (i < chars.length) box.appendChild(caret);
            else {
                stopTyper();
                if (queue.length) setTimeout(nextLine, 1100);
            }
        }, 24);
    }

    function nextLine() { if (queue.length) typeLine(queue.shift()); }

    function say(lines) {
        queue = lines.filter(function (l) { return l && l.text; });
        nextLine();
    }

    function showMe(text) {
        var m = $("me-line");
        if (!text) { m.classList.add("hidden"); return; }
        $("me-text").textContent = text;
        m.classList.remove("hidden");
        restart(m, "me-line");
    }

    // ------------------------------------------------------------ cartel y avisos
    function banner(title, sub) {
        var b = $("banner");
        $("banner-title").textContent = title;
        $("banner-sub").textContent = sub || "";
        b.classList.remove("hidden");
        restart(b, "banner");
        clearTimeout(banner.t);
        banner.t = setTimeout(function () { b.classList.add("hidden"); }, 3500);
    }

    function toast(text, love) {
        var t = $("toast");
        t.textContent = text;
        t.className = "toast" + (love ? " love" : "");
        play("toast", 0.4);
        clearTimeout(toast.t);
        toast.t = setTimeout(function () { t.classList.add("hidden"); }, 3300);
    }

    // ------------------------------------------------------------ tutorial (primera conversacion)
    var COACH = [
        { target: "card", side: "right",
          html: "Esta es la ficha de la persona. Lo que sienten se mide en <b>Amistad</b> y <b>Romance</b>; al subir cambian de etapa y se desbloquean acciones. La meta 🎯 te dice qué falta." },
        { target: "actions", side: "left",
          html: "Elige qué hacer: haz <img class='key-ico' src='img/mouse_left.png'> clic o pulsa su número <kbd>1</kbd>. Cada persona tiene <b>rasgos</b>: a unas les gustan los chistes; a otras, los regalos." },
        { target: "hints", side: "up",
          html: "Repetir lo mismo <b>aburre</b> y coquetear puede salir mal. Cuando la barra de ganas se vacíe se irá. Para irte: <b>Despedirse</b> o <img class='key-ico' src='img/keyboard_backspace.png'>." }
    ];

    function placeCoach(step) {
        var c = $("coach"), t = $(step.target).getBoundingClientRect();
        var w = c.offsetWidth, h = c.offsetHeight, gap = 18, x, y;
        if (step.side === "right") { x = t.right + gap; y = t.top; }
        else if (step.side === "left") { x = t.left - w - gap; y = t.top + t.height / 2 - h / 2; }
        else { x = innerWidth / 2 - w / 2; y = t.top - h - gap; }
        c.style.left = Math.max(10, Math.min(innerWidth - w - 10, x)) + "px";
        c.style.top = Math.max(10, Math.min(innerHeight - h - 10, y)) + "px";
    }

    function showCoach() {
        document.querySelectorAll(".coach-spot").forEach(function (n) { n.classList.remove("coach-spot"); });
        if (!coachStep || coachStep > COACH.length) {
            coachStep = 0;
            $("coach").classList.add("hidden");
            $("coach-dim").classList.add("hidden");
            return;
        }
        var step = COACH[coachStep - 1];
        $(step.target).classList.add("coach-spot");
        $("coach-step").textContent = "Paso " + coachStep + " de " + COACH.length;
        $("coach-text").innerHTML = step.html;   // texto fijo nuestro, sin datos de jugadores
        $("coach-next").textContent = coachStep === COACH.length ? "¡A charlar!" : "Siguiente";
        $("coach-dim").classList.remove("hidden");
        $("coach").classList.remove("hidden");
        placeCoach(step);
        play("coach", 0.4);
    }

    $("coach-next").addEventListener("click", function () {
        coachStep++;
        if (coachStep > COACH.length) send("rp:npcrel:ui:tutorialDone");
        showCoach();
    });

    // ------------------------------------------------------------ teclado
    document.addEventListener("keydown", function (e) {
        if (!$("list").classList.contains("hidden")) {
            if (e.key === "Escape" || e.key === "Backspace") { e.preventDefault(); send("rp:npcrel:ui:closeList"); }
            return;
        }
        if (!state) return;
        if (coachStep) {
            if (e.key === "Enter" || e.key === " ") { e.preventDefault(); $("coach-next").click(); }
            return;
        }
        if (e.key === "Backspace" || e.key === "Escape") { e.preventDefault(); if (!ended) send("rp:npcrel:ui:leave"); return; }
        if (keyMap[e.key]) { e.preventDefault(); pick(keyMap[e.key]); }
    });

    // ------------------------------------------------------------ panel /vinculos
    var listData = [], listTab = "all";
    var TABS = [
        { id: "all", label: "Todos", test: function () { return true; } },
        { id: "couple", label: "Pareja", test: function (p) { return p.stage >= 5; } },
        { id: "crush", label: "Coqueteo", test: function (p) { return p.stage === 4; } },
        { id: "friend", label: "Amigos", test: function (p) { return p.stage === 3; } },
        { id: "known", label: "Conocidos", test: function (p) { return p.stage <= 2; } }
    ];

    function idleText(d) {
        if (d <= 0) return "Hablaron hoy";
        if (d === 1) return "Hace 1 día";
        return "Hace " + d + " días";
    }

    function miniBar(icon, value, cls) {
        var row = el("div", "pbar");
        row.appendChild(el("span", null, icon));
        var tr = el("div", "track");
        var f = el("div", "fill " + cls);
        f.style.width = Math.max(0, Math.min(100, value)) + "%";
        tr.appendChild(f);
        row.appendChild(tr);
        row.appendChild(el("b", null, value));
        return row;
    }

    function renderList() {
        var tabs = $("tabs");
        tabs.textContent = "";
        TABS.forEach(function (t) {
            var count = listData.filter(t.test).length;
            if (t.id !== "all" && !count) return;
            var b = el("button", "tab" + (listTab === t.id ? " on" : ""), t.label);
            b.appendChild(el("span", null, count));
            b.addEventListener("click", function () { listTab = t.id; play("pick", 0.3); renderList(); });
            tabs.appendChild(b);
        });

        var grid = $("grid");
        grid.textContent = "";
        var tab = TABS.filter(function (t) { return t.id === listTab; })[0] || TABS[0];
        var items = listData.filter(tab.test);
        if (!listData.length) {
            var e = el("div", "empty");
            e.appendChild(document.createTextNode("Aún no tienes vínculos."));
            e.appendChild(el("br"));
            e.appendChild(document.createTextNode("Acércate a alguien del barrio y pulsa "));
            var img = el("img");
            img.src = "../images/keys/keyboard_h.png";
            e.appendChild(img);
            e.appendChild(document.createTextNode(" para hablar."));
            grid.appendChild(e);
            return;
        }
        items.forEach(function (p, i) {
            var c = el("div", "pcard" + (p.stage >= 5 ? " couple" : ""));
            c.style.animationDelay = Math.min(i * 0.03, 0.4) + "s";
            var head = el("div", "card-head");
            var av = el("div", "avatar");
            var letter = el("span");
            av.appendChild(letter);
            var badge = el("i", "badge", "♥");
            av.appendChild(badge);
            setAvatar(av, letter, badge, p);
            head.appendChild(av);
            var who = el("div", "who");
            who.appendChild(el("div", "name", p.name));
            var sub = el("div", "sub");
            sub.appendChild(el("span", "chip s" + p.stage, STAGE_ICONS[p.stage - 1] + " " + p.stageName));
            who.appendChild(sub);
            head.appendChild(who);
            c.appendChild(head);

            var bars = el("div", "pbars");
            bars.appendChild(miniBar("🤝", p.friendship, "fill-f"));
            bars.appendChild(miniBar("💗", p.romance, "fill-r"));
            c.appendChild(bars);

            var meta = el("div", "pmeta");
            meta.appendChild(el("span", p.phone ? "phone" : "", p.phone ? "📱 " + phoneText(p.phone) : "Sin número"));
            meta.appendChild(el("span", p.cooling ? "cold" : "", (p.cooling ? "❄ " : "🕒 ") + idleText(p.idleDays)));
            arr(p.traits).forEach(function (t) { meta.appendChild(el("span", null, t)); });
            c.appendChild(meta);
            if (p.cooling) c.appendChild(el("div", "pgoal", "Se está enfriando: llámale o búscale pronto."));
            else if (p.goal) c.appendChild(el("div", "pgoal", "🎯 " + p.goal));
            grid.appendChild(c);
        });
    }

    $("list-close").addEventListener("click", function () { send("rp:npcrel:ui:closeList"); });

    // ------------------------------------------------------------ API para Lua
    window.RP = {
        open: function (d, tutorial) {
            state = d; busy = false; ended = false; queue = [];
            $("list").classList.add("hidden");
            var talk = $("talk");
            talk.classList.remove("hidden", "leaving");
            renderCard(d, null);
            renderActions(d);
            showMe(null);
            var first = (d.name || "").split(" ")[0];
            say([{ who: first, text: d.greeting || "Hola." }]);
            play("open", 0.35);
            coachStep = tutorial ? 1 : 0;
            if (coachStep) setTimeout(showCoach, 700);
        },

        result: function (res) {
            if (!state) return;
            var prev = state;
            state = res.state;
            busy = false;
            ended = !!res.ended;
            renderCard(state, prev);
            renderActions(state);
            var first = (state.name || "").split(" ")[0];
            showMe(res.playerText);
            var lines = [{ who: first, text: res.text, mood: res.outcome === "bad" ? "bad" : (res.outcome === "great" ? "great" : null) }];
            if (res.stageText) lines.push({ who: first, text: res.stageText, mood: "great" });
            if (res.tiredText) lines.push({ who: first, text: res.tiredText });
            setTimeout(function () { say(lines); }, res.playerText ? 450 : 0);

            if (res.gain) {
                floatGain("val-f", "fill-f", res.gain.friendship, "f");
                floatGain("val-r", "fill-r", res.gain.romance, "r");
            }
            if (res.stageUp) {
                setTimeout(function () { banner(state.stageName.toUpperCase(), state.name); play("stage", 0.5); }, 500);
            } else if (res.bored) play("bored");
            else play(res.outcome === "bad" ? "bad" : (res.outcome === "great" ? "great" : "good"));
            if (res.saved) setTimeout(function () { toast("📒 " + first + " ya te recuerda: aparece en /vinculos"); }, res.stageUp ? 1800 : 300);
        },

        unbusy: function () {
            busy = false;
            if (state) renderActions(state);
        },

        toast: function (text, love) { toast(text, love); },

        close: function () {
            if (!state) return;
            state = null; coachStep = 0; queue = []; stopTyper();
            showCoach();
            play("close", 0.3);
            var talk = $("talk");
            talk.classList.add("leaving");
            setTimeout(function () { if (!state) talk.classList.add("hidden"); }, 360);
        },

        list: function (list, max) {
            listData = arr(list);
            listTab = "all";
            $("list-count").textContent = listData.length + " de " + (max || 40) + " personas que te recuerdan";
            $("list").classList.remove("hidden");
            renderList();
            play("open", 0.35);
        },

        closeList: function () {
            if ($("list").classList.contains("hidden")) return;
            $("list").classList.add("hidden");
            play("close", 0.3);
        }
    };

    // ------------------------------------------------------------ vista previa sin el juego
    if (!window.mta) {
        document.body.style.background = "linear-gradient(160deg,#3b4a5a,#7a6a58)";
        var demo = {
            name: "Valeria Castillo", gender: 1, stage: 3, stageName: "Amigo", friendship: 46, romance: 22, dating: false,
            traits: ["Romántica", "Fiestera"], traitCount: 2, mood: "Animada", moodKey: "happy", left: 9, total: 14,
            goal: "Romance 30 para gustarse.", rules: { known: 15, friend: 40, crush: 30, askout: 60, stable: 90 },
            greeting: "¡Leo! Justo estaba pensando en ti.",
            actions: [
                { id: "talk", label: "Charlar", icon: "💬", kind: "friend", enabled: true, hint: "", effect: "+Amistad" },
                { id: "joke", label: "Bromear", icon: "😄", kind: "friend", enabled: true, hint: "", effect: "+Amistad", tired: true },
                { id: "compliment", label: "Cumplido", icon: "✨", kind: "romance", enabled: true, hint: "", effect: "+Amistad +Romance" },
                { id: "flirt", label: "Coquetear", icon: "😉", kind: "romance", enabled: true, hint: "", effect: "+Romance", risky: true },
                { id: "gift", label: "Regalo", icon: "🎁", kind: "romance", enabled: true, hint: "$60", effect: "+Amistad +Romance" },
                { id: "hug", label: "Abrazar", icon: "🤗", kind: "friend", enabled: true, hint: "", effect: "+Amistad +Romance" },
                { id: "number", label: "Pedir número", icon: "📱", kind: "special", enabled: true, hint: "", effect: "Guarda su número" },
                { id: "askout", label: "Pedir salir", icon: "💘", kind: "special", enabled: false, hint: "Romance 60+", effect: "Ser pareja" },
                { id: "kiss", label: "Besar", icon: "💋", kind: "romance", enabled: false, hint: "Hay que ser pareja", effect: "+Romance" },
                { id: "bye", label: "Despedirse", icon: "👋", kind: "special", enabled: true, hint: "", effect: "Terminar la charla" }
            ]
        };
        if (location.hash === "#lista") {
            RP.list([
                { name: "Valeria Castillo", gender: 1, stage: 5, stageName: "Pareja", friendship: 72, romance: 81, dating: true, phone: 5561234, traits: ["Romántica", "Fiestera"], idleDays: 0, cooling: false, goal: "Romance 90 y amistad 70: pareja estable." },
                { name: "Diego Herrera", gender: 0, stage: 3, stageName: "Amigo", friendship: 52, romance: 4, phone: 5567788, traits: ["Seria", "Amable"], idleDays: 5, cooling: true },
                { name: "Lucía Navarro", gender: 1, stage: 2, stageName: "Conocido", friendship: 18, romance: 6, traits: ["Tímida"], idleDays: 1, cooling: false, goal: "Amistad 40 para ser amigos." }
            ], 40);
        } else {
            RP.open(demo, location.hash === "#tutorial");
            var origSend = send;
            send = function (name, id) {
                origSend(name, id);
                if (name !== "rp:npcrel:ui:pick") return;
                setTimeout(function () {
                    var s = JSON.parse(JSON.stringify(state));
                    s.friendship += 4; s.romance += 3; s.left -= 1;
                    var up = s.romance >= 30 && s.stage < 4;
                    if (up) { s.stage = 4; s.stageName = "Coqueteo"; s.goal = "Romance 60 para pedirle salir."; }
                    RP.result({ action: id, outcome: "good", playerText: "Tienes una sonrisa muy bonita.", text: "Ay, gracias, qué amable. Me haces sonrojar…",
                        gain: { friendship: 4, romance: 3 }, stageUp: up ? 4 : null, stageText: up ? "Creo que me estás empezando a gustar." : null, state: s });
                }, 600);
            };
        }
    }
})();
