/*
 * rp_interact / app.js
 * Menú contextual sobre una persona (M + clic derecho), formularios de dinero y objetos,
 * resultado del cacheo y tutorial de la primera vez.
 * Lua llama a:
 *   RP.open(data, x, y, tutorial)   abre el menú junto al punto donde se hizo clic
 *   RP.frisk(data)                  muestra lo que lleva la persona cacheada
 *   RP.close()                      cierra todo
 * Manda a Lua: rp:interact:ui:pick(id, json), rp:interact:ui:close, rp:interact:ui:tutorialDone
 * Vista previa sin el juego: index.html#demo, #tuto, #dinero, #objeto o #cacheo
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
    function arr(x) { return Array.isArray(x) ? x : []; }   // toJSON de Lua manda {} para listas vacías

    // ------------------------------------------------------------ sonidos (Kenney, CC0)
    var SOUNDS = {
        open: "maximize_003", close: "minimize_003", hover: "select_002", pick: "click_002",
        good: "confirmation_002", bad: "error_004", coach: "pluck_001"
    };
    var lastHover = 0;
    function play(name, vol) {
        if (!SOUNDS[name]) return;
        if (name === "hover") { var t = Date.now(); if (t - lastHover < 70) return; lastHover = t; }
        try { var a = new Audio("sounds/" + SOUNDS[name] + ".ogg"); a.volume = vol || 0.4; a.play(); } catch (e) { /* sin audio */ }
    }

    // ------------------------------------------------------------ estado
    var data = null;
    var view = "list";
    var money = 0;
    var picked = null, qty = 1;
    var closing = false;

    function fmt(n) { return "$" + String(Math.floor(n)).replace(/\B(?=(\d{3})+(?!\d))/g, "."); }

    // ------------------------------------------------------------ ficha
    function renderHead() {
        var t = data.target || {};
        $("avatar").textContent = (t.name || "?").charAt(0).toUpperCase();
        $("avatar").style.background = t.faction && t.faction.color
            ? "linear-gradient(135deg, " + t.faction.color + ", #2a2532)" : "";
        $("name").textContent = t.name || "—";
        var chips = $("chips");
        chips.textContent = "";
        if (t.id !== undefined && t.id !== null) chips.appendChild(el("span", "chip id", "ID " + t.id));
        if (t.level) chips.appendChild(el("span", "chip", "Nivel " + t.level));
        if (t.faction) {
            var f = el("span", "chip", t.faction.name + (t.faction.rank ? " · " + t.faction.rank : ""));
            if (t.faction.color) { f.style.background = t.faction.color + "33"; f.style.color = t.faction.color; }
            chips.appendChild(f);
        }
        arr(t.states).forEach(function (s) { chips.appendChild(el("span", "chip state", s)); });
        if (t.admin) chips.appendChild(el("span", "chip adm", "PJ " + t.admin.character + " · " + (t.admin.account || "?")));
    }

    // ------------------------------------------------------------ lista de acciones
    function renderList() {
        var list = $("list");
        list.textContent = "";
        if (data.far) list.appendChild(el("div", "far-note", "Estás lejos: solo ves las opciones de administración."));
        arr(data.groups).forEach(function (g) {
            var items = arr(g.items);
            if (!items.length) return;
            var title = el("div", "group-title t-" + (g.tone || "friend"), g.title);
            list.appendChild(title);
            items.forEach(function (it) {
                var b = el("button", "act t-" + (g.tone || "friend") + (it.locked ? " locked" : ""));
                b.dataset.id = it.id;
                b.appendChild(el("span", "ico", it.icon || "•"));
                var txt = el("span", "txt");
                txt.appendChild(el("span", "lbl", it.label));
                var desc = it.locked || it.desc;
                if (desc) txt.appendChild(el("span", "eff", it.locked ? "🔒 " + desc : desc));
                b.appendChild(txt);
                if (it.form && !it.locked) b.appendChild(el("span", "tag more", "›"));
                else if (it.ask && !it.locked) b.appendChild(el("span", "tag ask", "Pide permiso"));
                b.addEventListener("mouseenter", function () { if (!it.locked) play("hover"); });
                b.addEventListener("click", function () { choose(it); });
                list.appendChild(b);
            });
        });
    }

    function choose(it) {
        if (closing) return;
        if (it.locked) { play("bad"); return; }
        play("pick");
        if (it.form === "money") return showView("money");
        if (it.form === "item") return showView("item");
        send("rp:interact:ui:pick", it.id, "{}");
    }

    function showView(v) {
        view = v;
        $("list").classList.toggle("hidden", v !== "list");
        $("form-money").classList.toggle("hidden", v !== "money");
        $("form-item").classList.toggle("hidden", v !== "item");
        if (v === "money") openMoney();
        if (v === "item") openItems();
        place();
    }

    // ------------------------------------------------------------ dar dinero
    function maxMoney() { return Math.min(data.cash || 0, data.moneyMax || 5000); }
    function setMoney(n) {
        money = Math.max(0, Math.min(maxMoney(), Math.floor(n) || 0));
        $("money-input").value = String(money);
        $("money-ok").textContent = money > 0 ? "Dar " + fmt(money) : "Escribe cuánto";
        $("money-ok").disabled = money < 1;
    }
    function openMoney() {
        $("money-have").textContent = "Llevas " + fmt(data.cash || 0) + " · máximo " + fmt(data.moneyMax || 5000) + " por entrega";
        var q = $("money-quick");
        q.textContent = "";
        [10, 50, 100, 500, 1000].forEach(function (v) {
            if (v > maxMoney()) return;
            var b = el("button", null, "+" + v);
            b.addEventListener("click", function () { play("hover"); setMoney(money + v); });
            q.appendChild(b);
        });
        var all = el("button", null, "Todo");
        all.addEventListener("click", function () { play("hover"); setMoney(maxMoney()); });
        q.appendChild(all);
        setMoney(0);
        setTimeout(function () { $("money-input").focus(); $("money-input").select(); }, 30);
    }
    $("money-input").addEventListener("input", function () {
        var raw = parseInt(this.value.replace(/\D/g, ""), 10) || 0;
        if (raw > maxMoney()) { var box = this.parentNode; box.classList.remove("bad"); void box.offsetWidth; box.classList.add("bad"); play("bad"); }
        setMoney(raw);
    });
    $("money-input").addEventListener("keydown", function (e) { if (e.key === "Enter") $("money-ok").click(); });
    $("money-ok").addEventListener("click", function () {
        if (money < 1) return play("bad");
        play("good");
        send("rp:interact:ui:pick", "give_money", JSON.stringify({ amount: money }));
    });

    // ------------------------------------------------------------ dar un objeto
    function itemMax() { return picked ? Math.max(1, picked.amount || 1) : 1; }
    function setQty(n) {
        qty = Math.max(1, Math.min(itemMax(), n));
        $("qty").textContent = String(qty);
        $("item-ok").disabled = !picked;
        $("item-ok").textContent = picked ? "Ofrecer " + qty + " × " + picked.name : "Elige un objeto";
    }
    function openItems() {
        var box = $("items");
        box.textContent = "";
        picked = null;
        arr(data.items).forEach(function (it) {
            var b = el("button", "item");
            b.appendChild(el("span", "i-ico", it.icon || "📦"));
            b.appendChild(el("span", "i-name", it.name));
            b.appendChild(el("span", "i-n", "×" + it.amount));
            b.title = it.name;
            b.addEventListener("click", function () {
                play("hover");
                picked = it;
                Array.prototype.forEach.call(box.children, function (c) { c.classList.remove("on"); });
                b.classList.add("on");
                setQty(1);
            });
            box.appendChild(b);
        });
        setQty(1);
    }
    $("qty-minus").addEventListener("click", function () { play("hover"); setQty(qty - 1); });
    $("qty-plus").addEventListener("click", function () { play("hover"); setQty(qty + 1); });
    $("item-ok").addEventListener("click", function () {
        if (!picked) return play("bad");
        play("good");
        send("rp:interact:ui:pick", "give_item", JSON.stringify({ item: picked.id, amount: qty }));
    });

    Array.prototype.forEach.call(document.querySelectorAll("[data-back]"), function (b) {
        b.addEventListener("click", function () { play("pick"); showView("list"); });
    });

    // ------------------------------------------------------------ colocación junto al clic
    var anchor = { x: 0, y: 0 };
    function place() {
        var m = $("menu");
        var w = m.offsetWidth, h = m.offsetHeight;
        var x = anchor.x + 14, y = anchor.y - 20;
        if (x + w > window.innerWidth - 12) x = anchor.x - w - 14;   // no cabe a la derecha: a la izquierda
        x = Math.max(12, x);
        y = Math.max(12, Math.min(y, window.innerHeight - h - 12));
        m.style.left = x + "px";
        m.style.top = y + "px";
    }

    // ------------------------------------------------------------ tutorial (UX-03/04)
    var COACH = [
        { target: "head", text: "Aquí ves <b>quién es</b>: su nombre, su ID, su nivel y si está herido o esposado." },
        { target: "list", text: "Elige <b>qué hacer</b> con un clic. Las opciones en gris te dicen qué te falta (🔒)." },
        { target: "list", text: "Las que dicen <span class=\"tagx\">Pide permiso</span> le llegan como propuesta: la otra persona acepta con <span class=\"key\">E</span> o rechaza con <span class=\"key\">⌫</span>." }
    ];
    var coachStep = -1;
    function coachShow() {
        document.querySelectorAll(".coach-spot").forEach(function (n) { n.classList.remove("coach-spot"); });
        if (coachStep < 0 || coachStep >= COACH.length) {
            $("coach").classList.add("hidden");
            $("coach-dim").classList.add("hidden");
            $("menu").classList.remove("coach-on");
            if (coachStep >= COACH.length) send("rp:interact:ui:tutorialDone");
            coachStep = -1;
            return;
        }
        var s = COACH[coachStep];
        play("coach");
        $("coach-dim").classList.remove("hidden");
        $("menu").classList.add("coach-on");
        $(s.target).classList.add("coach-spot");
        $("coach-step").textContent = "Paso " + (coachStep + 1) + " de " + COACH.length;
        $("coach-text").innerHTML = s.text;   // texto fijo nuestro, sin datos del servidor
        $("coach-next").textContent = coachStep === COACH.length - 1 ? "¡Entendido!" : "Siguiente";
        var c = $("coach");
        c.classList.remove("hidden");
        var r = $("menu").getBoundingClientRect();
        var left = r.right + 16;
        if (left + c.offsetWidth > window.innerWidth - 12) left = r.left - c.offsetWidth - 16;
        c.style.left = Math.max(12, left) + "px";
        var tr = $(s.target).getBoundingClientRect();
        c.style.top = Math.max(12, Math.min(tr.top, window.innerHeight - c.offsetHeight - 12)) + "px";
    }
    $("coach-next").addEventListener("click", function () { coachStep++; coachShow(); });

    // ------------------------------------------------------------ cacheo
    var friskBusy = false;
    function take(what, btn) {
        if (friskBusy) return;
        friskBusy = true;
        btn.disabled = true;
        btn.textContent = "...";
        play("pick");
        send("rp:interact:ui:take", what);
        setTimeout(function () { friskBusy = false; }, 1500);   // cooldown del servidor
    }

    function showFrisk(d) {
        var wasOpen = !$("frisk").classList.contains("hidden");
        var scroll = $("frisk-items").scrollTop;
        $("frisk-name").textContent = d.name || "—";
        var cash = $("frisk-cash");
        cash.textContent = "";
        cash.appendChild(el("span", null, "💵 " + fmt(d.cash || 0) + " en efectivo"));
        if (d.canTake && d.cashTake > 0) {
            var cb = el("button", "take", "Quitar " + fmt(d.cashTake));
            cb.addEventListener("click", function () { take("$cash", cb); });
            cash.appendChild(cb);
        }
        $("frisk-note").textContent = d.canTake
            ? "Está reducido: puedes quitarle lo que lleva. Es un robo y suma búsqueda."
            : "Solo puedes mirar. Para quitarle cosas tiene que estar esposado, herido o aturdido.";
        $("frisk-note").className = "frisk-note" + (d.canTake ? " rob" : "");
        var box = $("frisk-items");
        box.textContent = "";
        var items = arr(d.items);
        if (!items.length) box.appendChild(el("div", "empty", "No lleva nada encima."));
        items.forEach(function (it, i) {
            var r = el("div", "fi");
            if (!wasOpen) r.style.animationDelay = (i * 0.03) + "s";
            else r.style.animation = "none";
            r.appendChild(el("span", "i-ico", it.icon || "📦"));
            r.appendChild(el("span", "i-name", it.name));
            r.appendChild(el("b", null, "×" + it.amount));
            if (it.takeable) {
                var b = el("button", "take", "Quitar");
                b.addEventListener("mouseenter", function () { play("hover"); });
                b.addEventListener("click", function () { take(it.id, b); });
                r.appendChild(b);
            }
            box.appendChild(r);
        });
        box.scrollTop = scroll;
        friskBusy = false;
        $("frisk").classList.remove("hidden");
        if (!wasOpen) play("open");
    }

    // ------------------------------------------------------------ cerrar
    function requestClose() { if (!closing) send("rp:interact:ui:close"); }
    $("btn-close").addEventListener("click", function () { play("close"); requestClose(); });
    $("frisk-close").addEventListener("click", function () { play("close"); requestClose(); });
    document.addEventListener("keydown", function (e) {
        if (e.key !== "Escape") return;
        e.preventDefault();
        if (coachStep >= 0) { coachStep = COACH.length; return coachShow(); }
        if (view !== "list" && !$("menu").classList.contains("hidden")) { play("pick"); return showView("list"); }
        play("close");
        requestClose();
    });
    document.addEventListener("contextmenu", function (e) { e.preventDefault(); });

    // ------------------------------------------------------------ API para Lua
    window.RP = {
        open: function (d, x, y, tutorial) {
            data = d || {};
            closing = false;
            $("frisk").classList.add("hidden");
            var m = $("menu");
            m.classList.remove("hidden", "leaving");
            void m.offsetWidth;
            anchor = { x: x || window.innerWidth / 2, y: y || window.innerHeight / 3 };
            renderHead();
            renderList();
            showView("list");
            play("open");
            if (tutorial) { coachStep = 0; setTimeout(coachShow, 350); }
        },
        frisk: function (d) {
            // Llega justo despues de cerrar el menu (RP.close): sin esto la X y Esc no respondian
            closing = false;
            $("menu").classList.add("hidden");
            showFrisk(d || {});
        },
        close: function () {
            closing = true;
            coachStep = -1;
            coachShow();
            $("menu").classList.add("leaving");
            setTimeout(function () { if (closing) { $("menu").classList.add("hidden"); $("frisk").classList.add("hidden"); } }, 180);
        }
    };

    // ------------------------------------------------------------ vista previa sin el juego
    var DEMO = {
        target: { name: "Carl Johnson", id: 7, level: 4, states: ["Herido"], faction: { name: "Los Santos PD", rank: "Oficial", color: "#3b6fe0" } },
        cash: 1240, moneyMax: 5000,
        items: [{ id: "water", name: "Agua", icon: "💧", amount: 3 }, { id: "medkit", name: "Botiquín", icon: "🩹", amount: 1 },
                { id: "burger", name: "Hamburguesa", icon: "🍔", amount: 2 }, { id: "phone", name: "Teléfono", icon: "📱", amount: 1 }],
        groups: [
            { title: "Social", tone: "friend", items: [
                { id: "greet", label: "Saludar", icon: "👋", desc: "Un gesto con la mano" },
                { id: "handshake", label: "Dar la mano", icon: "🤝", desc: "Tiene que aceptar", ask: true },
                { id: "kiss", label: "Besar", icon: "💋", desc: "Tiene que aceptar", ask: true, locked: "Ahora no puede" }] },
            { title: "Documentos", tone: "info", items: [
                { id: "show_dni", label: "Mostrar DNI", icon: "🪪", desc: "Le enseñas tu documento" },
                { id: "show_license", label: "Mostrar licencia", icon: "🚘", locked: "No tienes licencia de conducir" }] },
            { title: "Dar", tone: "money", items: [
                { id: "give_money", label: "Dar dinero", icon: "💵", desc: "Llevas $1240 en efectivo", form: "money" },
                { id: "give_item", label: "Dar un objeto", icon: "🎁", desc: "Tiene que aceptar", form: "item", ask: true }] },
            { title: "Ayuda", tone: "help", items: [
                { id: "help_up", label: "Reanimar con botiquín", icon: "🩹", desc: "Gasta 1 botiquín · 8 s" },
                { id: "frisk", label: "Cachear", icon: "🔎", desc: "Está reducido: no hace falta permiso" }] },
            { title: "Otros", tone: "muted", items: [{ id: "report", label: "Reportar", icon: "🚩", desc: "Abre el reporte F1 con esta persona" }] },
            { title: "Administración", tone: "admin", items: [{ id: "adm_check", label: "Ficha (/check)", icon: "📋" }, { id: "adm_goto", label: "Ir hacia él (/goto)", icon: "➡️" }] }
        ]
    };
    var hash = location.hash;
    if (!window.mta && (hash === "#demo" || hash === "#tuto" || hash === "#dinero" || hash === "#objeto")) {
        document.body.style.background = "#4a5a48";
        RP.open(DEMO, window.innerWidth * 0.42, window.innerHeight * 0.3, hash === "#tuto");
        if (hash === "#dinero") showView("money");
        if (hash === "#objeto") showView("item");
    } else if (!window.mta && hash === "#cacheo") {
        document.body.style.background = "#4a5a48";
        RP.frisk({ name: "Carl Johnson", cash: 350, cashTake: 350, canTake: true, items: DEMO.items.map(function (x) { return { id: x.id, name: x.name, icon: x.icon, amount: x.amount, takeable: true }; }) });
    }
})();
