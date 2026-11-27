/*
 * rp_achievements / app.js
 * Panel de logros. Lua llama a RP.catalog(catálogo), RP.show(estado) y RP.claimed(n, ok).
 * El JS solo pide; el servidor revalida y entrega.
 * Eventos: rp:achievements:ui:close, rp:achievements:ui:claim(n), rp:achievements:ui:coachDone.
 * Modo demo: abrir index.html en un navegador (sin mta) carga datos de ejemplo.
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var CAT = null, state = null, tab = "all", selected = null;

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
    // 12345 -> "12.345" (como ACH.fmt; toLocaleString("es") no separa los de 4 cifras)
    function fmt(n) { return String(Math.floor(n || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, "."); }
    function goal(a, n) { return a.unit === "money" ? "$" + fmt(n) : a.unit === "%" ? fmt(n) + " %" : fmt(n); }

    // ---------------------------------------------------------------- sonidos (paleta estándar, UX-06)
    var SOUNDS = { click: "click_002.ogg", select: "select_002.ogg", open: "maximize_003.ogg", close: "minimize_003.ogg",
        coins: "coins.wav", error: "error_004.ogg", coach: "pluck_001.ogg" };
    var lastSound = 0;
    function play(name) {
        var now = Date.now();
        if (now - lastSound < 80) return;
        lastSound = now;
        try { var a = new Audio("sounds/" + SOUNDS[name]); a.volume = 0.5; a.play(); } catch (e) { /* sin audio */ }
    }

    var toastTimer;
    function toast(text, err) {
        var t = $("toast");
        t.textContent = text;
        t.className = "toast on" + (err ? " err" : "");
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { t.className = "toast" + (err ? " err" : ""); }, 2600);
    }

    // ---------------------------------------------------------------- utilidades del modelo
    function prog(a) { return (state.progress && state.progress[a.key]) || { t: 0, v: 0 }; }
    function medalOf(a, tier) { return tier > 0 ? a.medals[tier - 1] : 0; }
    function medalHex(m) { return m ? CAT.medals[m - 1].hex : ""; }
    function isClaimed(i) { return state.claimed.indexOf(i) !== -1; }
    function readyList() {
        var out = [];
        CAT.milestones.forEach(function (m, i) { if (state.points >= m.points && !isClaimed(i + 1)) out.push(i + 1); });
        return out;
    }
    // 0..1 hacia la siguiente medalla
    function fracOf(a, p) {
        if (p.t >= a.tiers.length) return 1;
        var from = p.t > 0 ? a.tiers[p.t - 1] : 0, to = a.tiers[p.t];
        return Math.max(0, Math.min(1, (p.v - from) / Math.max(1, to - from)));
    }

    // ---------------------------------------------------------------- cabecera
    function renderHeader() {
        $("points").innerHTML = fmt(state.points) + " <small>/ " + fmt(state.max) + "</small>";
        var counts = [0, 0, 0, 0];
        CAT.achievements.forEach(function (a) {
            var p = prog(a);
            for (var i = 0; i < p.t; i++) counts[a.medals[i] - 1]++;
        });
        var box = $("medal-counts");
        box.textContent = "";
        CAT.medals.forEach(function (m, i) {
            var c = el("div", "mc");
            c.title = m.name;
            var dot = el("i");
            c.style.setProperty("--c", m.hex);
            c.appendChild(dot);
            c.appendChild(document.createTextNode(counts[i]));
            box.appendChild(c);
        });
    }

    // ---------------------------------------------------------------- hitos
    function renderMilestones() {
        var track = $("track");
        Array.prototype.slice.call(track.querySelectorAll(".node")).forEach(function (n) { n.remove(); });
        var list = CAT.milestones, max = list[list.length - 1].points;
        var ready = readyList();
        if (!selected || selected > list.length) {
            selected = ready[0] || null;
            if (!selected) list.some(function (m, i) { if (state.points < m.points) { selected = i + 1; return true; } return false; });
            selected = selected || list.length;
        }
        list.forEach(function (m, i) {
            var idx = i + 1;
            var n = el("div", "node");
            n.style.left = (m.points / max * 100) + "%";
            var claimed = isClaimed(idx), reached = state.points >= m.points;
            n.textContent = claimed ? "✔" : reached ? "🎁" : "🔒";
            if (claimed) n.classList.add("claimed");
            else if (reached) n.classList.add("ready");
            if (idx === selected) n.classList.add("sel");
            n.appendChild(el("span", "pts", fmt(m.points)));
            n.addEventListener("click", function () { play("select"); selected = idx; renderMilestones(); });
            track.appendChild(n);
        });
        $("track-fill").style.width = Math.min(100, state.points / max * 100) + "%";
        renderReward();
    }

    function renderReward() {
        var box = $("reward");
        box.textContent = "";
        var m = CAT.milestones[selected - 1];
        if (!m) return;
        box.appendChild(el("div", "rt", "HITO " + selected + " · " + fmt(m.points) + " PTS"));
        var items = el("div", "items");
        if (m.bank > 0) items.appendChild(el("span", "chip money", "$" + fmt(m.bank) + " al banco"));
        if (m.xp > 0) items.appendChild(el("span", "chip xp", fmt(m.xp) + " XP"));
        (m.items || []).forEach(function (it) { items.appendChild(el("span", "chip", it.icon + " " + it.n + "x " + it.name)); });
        if (m.cosmetic) items.appendChild(el("span", "chip cos", "✨ " + m.cosmetic));
        box.appendChild(items);
        if (isClaimed(selected)) {
            box.appendChild(el("div", "state", "✔ Reclamada"));
        } else if (state.points >= m.points) {
            var b = el("button", "btn primary claim", "Reclamar");
            b.addEventListener("click", function () {
                b.disabled = true;
                play("click");
                send("rp:achievements:ui:claim", selected);
            });
            box.appendChild(b);
        } else {
            box.appendChild(el("div", "state", "Te faltan " + fmt(m.points - state.points) + " puntos"));
        }
    }

    // ---------------------------------------------------------------- pestañas
    function renderTabs() {
        var nav = $("tabs");
        nav.textContent = "";
        var tabs = [{ key: "all", name: "Todos", icon: "🏆" }, { key: "near", name: "Casi lo tienes", icon: "🔥" }].concat(CAT.categories);
        tabs.forEach(function (c) {
            var b = el("button", "tab" + (c.key === tab ? " on" : ""));
            b.textContent = c.icon + " " + c.name;
            var list = filtered(c.key);
            if (c.key !== "all") b.appendChild(el("span", "n", list.length));
            b.addEventListener("click", function () { play("click"); tab = c.key; renderTabs(); renderGrid(); });
            nav.appendChild(b);
        });
    }

    function isNear(a) {
        var p = prog(a);
        return p.t < a.tiers.length && fracOf(a, p) >= 0.6 && !(a.secret && p.t === 0);
    }

    function filtered(key) {
        return CAT.achievements.filter(function (a) {
            if (key === "all") return true;
            if (key === "near") return isNear(a);
            return a.cat === key;
        });
    }

    // ---------------------------------------------------------------- tarjetas
    function card(a) {
        var p = prog(a);
        var hidden = a.secret && p.t === 0;
        var m = medalOf(a, p.t), done = p.t >= a.tiers.length;
        var nextM = done ? m : a.medals[p.t];
        var c = el("div", "card" + (m ? "" : " none") + (hidden ? " secret" : "") + (done ? " top" : "") + (isNear(a) ? " near" : ""));
        if (m) c.style.setProperty("--mc", medalHex(m));
        c.style.setProperty("--nc", medalHex(nextM));
        c.appendChild(el("div", "medal", hidden ? "❔" : a.icon));
        var body = el("div");
        var name = el("div", "c-name", hidden ? "Logro secreto" : a.name);
        if (m) name.appendChild(el("span", "c-tag", CAT.medals[m - 1].label));
        body.appendChild(name);
        var desc;
        if (hidden) desc = "Sigue jugando para descubrirlo.";
        else if (done) desc = "¡Completado! " + (a.desc.indexOf("%s") !== -1 ? a.desc.replace("%s", goal(a, a.tiers[a.tiers.length - 1])) : a.desc);
        else desc = (a.desc.indexOf("%s") !== -1 ? a.desc.replace("%s", goal(a, a.tiers[p.t])) : a.desc) +
            " · " + CAT.medals[nextM - 1].name + " +" + CAT.medals[nextM - 1].points + " pts";
        body.appendChild(el("div", "c-desc", desc));
        if (!hidden) {
            var bar = el("div", "bar"), fill = el("i");
            fill.style.width = (fracOf(a, p) * 100) + "%";
            bar.appendChild(fill);
            body.appendChild(bar);
            var foot = el("div", "c-foot");
            foot.appendChild(el("span", "", done ? goal(a, p.v) : goal(a, p.v) + " / " + goal(a, a.tiers[p.t])));
            var pips = el("div", "pips");
            a.medals.forEach(function (mm, i) {
                var pip = el("span", "pip" + (i < p.t ? " on" : ""));
                pip.style.setProperty("--c", medalHex(mm));
                pip.title = CAT.medals[mm - 1].name + ": " + goal(a, a.tiers[i]);
                pips.appendChild(pip);
            });
            foot.appendChild(pips);
            body.appendChild(foot);
        }
        c.appendChild(body);
        return c;
    }

    function renderGrid() {
        var grid = $("grid");
        grid.textContent = "";
        var list = filtered(tab).slice().sort(function (x, y) {
            if (tab === "near") return fracOf(y, prog(y)) - fracOf(x, prog(x));
            return 0;
        });
        list.forEach(function (a) { grid.appendChild(card(a)); });
        $("empty").style.display = list.length ? "none" : "block";
        if (tab === "near" && !list.length) $("empty").textContent = "Ningún logro está a punto: ¡sal a la calle!";
        else $("empty").textContent = "Nada por aquí todavía.";
    }

    function renderAll() { renderHeader(); renderMilestones(); renderTabs(); renderGrid(); }

    // ---------------------------------------------------------------- entrenador (UX-04)
    function showCoach() {
        var ms = $("milestones");
        $("coach").classList.add("on");
        ms.classList.add("spot");
        // El globo apunta a la barra de hitos: justo debajo de ella
        document.querySelector(".coach-box").style.top = (ms.offsetTop + ms.offsetHeight + 14) + "px";
        play("coach");
    }
    $("coach-ok").addEventListener("click", function () {
        $("coach").classList.remove("on");
        $("milestones").classList.remove("spot");
        play("click");
        send("rp:achievements:ui:coachDone");
    });

    // ---------------------------------------------------------------- cierre
    function close() { play("close"); send("rp:achievements:ui:close"); }
    $("btn-close").addEventListener("click", close);
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") close(); });

    // ---------------------------------------------------------------- API para Lua
    var opened = false;
    window.RP = {
        catalog: function (data) { CAT = data; },
        show: function (data) {
            var first = !state;
            state = data;
            // toJSON de Lua: una tabla vacía puede llegar como objeto
            if (!Array.isArray(state.claimed)) state.claimed = state.claimed ? Object.keys(state.claimed).map(function (k) { return state.claimed[k]; }) : [];
            state.progress = state.progress || {};
            if (!CAT) return;
            renderAll();
            if (first && !opened) {
                opened = true;
                play("open");
                if (data.coach) setTimeout(showCoach, 350);
            }
        },
        claimed: function (index, ok) {
            if (ok) { play("coins"); toast("¡Recompensa reclamada!"); }
            else { play("error"); toast("No se pudo reclamar: haz sitio en el inventario.", true); renderMilestones(); }
        },
    };

    // ---------------------------------------------------------------- modo demo
    if (!window.mta) {
        var demoCat = {
            categories: [
                { key: "work", name: "Trabajo", icon: "🛠️" }, { key: "treasure", name: "Tesoros", icon: "🪙" },
                { key: "road", name: "Carretera", icon: "🚗" }, { key: "street", name: "Ley y calle", icon: "🚔" },
                { key: "life", name: "Vida", icon: "🏠" }],
            medals: [{ name: "Bronce", label: "BRONCE", points: 10, hex: "#cd7f32" }, { name: "Plata", label: "PLATA", points: 25, hex: "#c8d2de" },
                { name: "Oro", label: "ORO", points: 50, hex: "#ffc440" }, { name: "Platino", label: "PLATINO", points: 100, hex: "#7fe8ff" }],
            milestones: [{ points: 50, bank: 1000, xp: 500, items: [], cosmetic: "" },
                { points: 150, bank: 2500, xp: 1000, items: [], cosmetic: "Icono 🏅 Medalla para tu fila del Tab (/perfil)" },
                { points: 300, bank: 5000, xp: 2000, items: [{ name: "Botiquín", icon: "🩹", n: 2 }], cosmetic: "" },
                { points: 500, bank: 8000, xp: 3000, items: [{ name: "Mochila de excursión", icon: "🎒", n: 1 }], cosmetic: "" },
                { points: 800, bank: 12000, xp: 4000, items: [], cosmetic: "Icono 🏆 Trofeo" }],
            achievements: [
                { key: "currante", cat: "work", icon: "⏱️", name: "Currante", desc: "Termina %s turnos de trabajo", tiers: [5, 25, 100, 400], medals: [1, 2, 3, 4], unit: "" },
                { key: "sueldo", cat: "work", icon: "💵", name: "Sueldo honrado", desc: "Gana %s trabajando", tiers: [5000, 50000, 250000, 1000000], medals: [1, 2, 3, 4], unit: "money" },
                { key: "pizzero", cat: "work", icon: "🍕", name: "Pizzero", desc: "Entrega %s pizzas en Well Stacked Pizza", tiers: [10, 50, 200, 1000], medals: [1, 2, 3, 4], unit: "" },
                { key: "leyenda", cat: "treasure", icon: "👑", name: "Leyenda enterrada", desc: "Desentierra un objeto legendario", tiers: [1], medals: [3], unit: "" },
                { key: "buscatesoros", cat: "treasure", icon: "📡", name: "Buscatesoros", desc: "Desentierra %s objetos con el detector", tiers: [10, 50, 250, 1000], medals: [1, 2, 3, 4], unit: "" },
                { key: "licencia", cat: "road", icon: "🪪", name: "Licencia en mano", desc: "Aprueba la autoescuela y saca tu licencia", tiers: [1], medals: [2], unit: "" },
                { key: "piloto", cat: "road", icon: "🏁", name: "Piloto", desc: "Termina %s carreras", tiers: [3, 15, 50, 150], medals: [1, 2, 3, 4], unit: "" },
                { key: "rejas", cat: "street", icon: "⛓️", name: "Entre rejas", desc: "Acaba en la cárcel", tiers: [1], medals: [1], unit: "", secret: true },
                { key: "fantasma", cat: "street", icon: "👻", name: "Fantasma", desc: "Pierde a la policía %s veces", tiers: [1, 10, 30, 100], medals: [1, 2, 3, 4], unit: "" },
                { key: "ahorrador", cat: "life", icon: "🏦", name: "Ahorrador", desc: "Ten %s en tu cuenta del banco", tiers: [10000, 100000, 1000000, 5000000], medals: [1, 2, 3, 4], unit: "money" },
                { key: "veterano", cat: "life", icon: "⭐", name: "Veterano", desc: "Llega al nivel %s", tiers: [5, 10, 25, 50], medals: [1, 2, 3, 4], unit: "" },
            ],
        };
        RP.catalog(demoCat);
        RP.show({
            points: 185, max: 4000, claimed: [1], coach: location.hash === "#coach",
            progress: {
                currante: { t: 2, v: 31 }, sueldo: { t: 1, v: 41000 }, pizzero: { t: 4, v: 1200 },
                leyenda: { t: 1, v: 1 }, buscatesoros: { t: 0, v: 7 }, licencia: { t: 1, v: 1 },
                piloto: { t: 0, v: 1 }, rejas: { t: 0, v: 0 }, fantasma: { t: 1, v: 8 },
                ahorrador: { t: 1, v: 62000 }, veterano: { t: 1, v: 7 },
            },
        });
    }
})();
