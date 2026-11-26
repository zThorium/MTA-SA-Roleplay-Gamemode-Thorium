/*
 * rp_pizzeria / app.js
 * Dos modos segun el hash: #hud (comandas, cocina, resultados; sin raton) y #panel (ventanas).
 * Lua llama a PZ.state(estado), PZ.fx(tipo, datos), PZ.panel(tipo, datos) y PZ.stock(stock).
 * Los tiempos llegan como "hace cuantos ms" y se animan aqui con Date.now().
 * Vista previa en un navegador: index.html#hud o index.html#panel (abre la consola y llama a PZ.demo()).
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var MODE = location.hash.indexOf("#panel") === 0 ? "panel" : "hud";
    var BAKE_BURN = 1.7, FRY_BURN = 1.9, BAKE_WIN = 0.35, FRY_WIN = 0.4;

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
    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }
    function canvas(w, h) { var c = document.createElement("canvas"); c.width = w; c.height = h || w; return c; }

    // ---------- Sonidos ----------
    var sounds = {};
    // Que suena en cada momento. Kenney (CC0) en sounds/kenney/; si hay varios, se elige uno al azar
    // para que los sonidos repetidos (ingredientes, cortes) no cansen. sizzle sigue siendo sintetizado.
    var K = "kenney/";
    var SOUNDS = {
        bell:    [K + "glass_001.ogg"],                                            // entra un cliente
        print:   [K + "confirmation_001.ogg"],                                     // pedido tomado
        pop:     [K + "drop_001.ogg", K + "drop_002.ogg", K + "drop_003.ogg", K + "drop_004.ogg"],   // ingrediente
        paint:   [K + "scroll_001.ogg", K + "scroll_002.ogg", K + "scroll_003.ogg"],               // pintar salsa/queso
        oven:    [K + "open_002.ogg"],                                             // meter/sacar del horno
        ding:    [K + "bong_001.ogg"],                                             // en su punto
        alarm:   [K + "error_006.ogg"],                                            // se quema
        chop:    [K + "scratch_001.ogg", K + "scratch_002.ogg", K + "scratch_003.ogg"],            // corte
        box:     [K + "close_002.ogg"],                                            // caja cerrada
        restock: [K + "drop_002.ogg"],                                             // caja a la despensa
        sizzle:  ["sizzle.wav"],                                                    // freidora
        cash:    [K + "confirmation_003.ogg"],                                     // entrega buena
        angry:   [K + "error_004.ogg"],                                            // queja / se va
        click:   [K + "click_002.ogg"],                                            // botones
        select:  [K + "select_002.ogg"],                                           // elegir herramienta o comanda
        open:    [K + "maximize_003.ogg"],                                         // abrir ventana
        close:   [K + "minimize_003.ogg"],                                         // cerrar ventana
        good:    [K + "confirmation_002.ogg"],                                     // "¡Bien!"
        meh:     [K + "question_001.ogg"],                                         // "intenta seguir la linea"
        step:    [K + "pluck_001.ogg"],                                            // paso nuevo del tutorial/entrenador
        tick:    [K + "tick_002.ogg"]                                              // reloj: un cliente esta a punto de irse
    };
    function play(name, vol) {
        try {
            var list = SOUNDS[name] || [name + ".wav"];
            var file = list[Math.floor(Math.random() * list.length)];
            var a = sounds[file] || (sounds[file] = new Audio("sounds/" + file));
            var b = a.cloneNode(); b.volume = vol || 0.7; b.play();
        } catch (e) { /* sin audio en la vista previa */ }
    }

    // =====================================================================
    // HUD
    // =====================================================================
    var S = null, recv = 0, alerted = {}, shownTickets = {};

    function orderById(id) {
        if (!S) return null;
        for (var i = 0; i < S.orders.length; i++) if (S.orders[i].id === id) return S.orders[i];
        return null;
    }

    function stageText(o) {
        if (o.status === "queue") return "En la fila";
        var t = { "new": "Por armar", assembled: "Armada", baking: "En el horno", baked: "Horneada", boxed: "Lista para entregar" }[o.stage] || "";
        if (o.side && o.sideState !== "done" && o.stage === "boxed") t = "Falta guarnición";
        return t;
    }

    function renderTickets() {
        var box = $("tickets");
        box.textContent = "";
        if (!S) return;
        // La fila no tiene comanda: la comanda se imprime al tomar el pedido en la caja
        var inLine = S.orders.filter(function (o) { return o.status === "queue"; }).length;
        var q = $("queue");
        q.textContent = inLine === 0 ? "Nadie en la fila" : inLine === 1 ? "🧍 1 cliente en la fila" : "🧍 " + inLine + " clientes en la fila";
        q.classList.toggle("busy", inLine > 0);
        S.orders.forEach(function (o) {
            if (o.status === "queue") return;
            // solo cae (animacion) la comanda nueva; las demas no se re-animan en cada actualizacion
            var isNew = !shownTickets[o.id];
            shownTickets[o.id] = true;
            var t = el("div", "ticket" + (isNew ? " new" : ""));
            t.dataset.id = o.id;
            var head = el("div", "t-head");
            head.appendChild(el("span", null, o.name));
            head.appendChild(el("span", null, "#" + o.id));
            t.appendChild(head);
            {
                var c = canvas(64); PIZZA.mini(c, o.pizza); t.appendChild(c);
                o.pizza.toppings.forEach(function (tp) {
                    var line = el("div", "t-line");
                    line.appendChild(el("b", null, tp.count + "×"));
                    line.appendChild(el("span", null, PIZZA.NAMES[tp.id] || tp.id));
                    if (tp.zone !== "whole") line.appendChild(el("i", null, PIZZA.ZONES[tp.zone]));
                    t.appendChild(line);
                });
                t.appendChild(el("div", "t-line", "🔥 " + PIZZA.BAKE[o.pizza.bake] + " · ✂ " + o.pizza.slices + " trozos"));
                if (o.side) t.appendChild(el("div", "t-line", "🍟 " + PIZZA.SIDES[o.side] + (o.sideState === "done" ? " ✔" : "")));
            }
            var st = el("div", "t-status" + (o.stage === "boxed" ? " ok" : ""), stageText(o));
            t.appendChild(st);
            var bar = el("div", "bar"); bar.appendChild(el("div")); t.appendChild(bar);
            box.appendChild(t);
        });
    }

    function slotEl(title, slot, burnAt, win) {
        var d = el("div", "k-slot");
        var name = el("div", "k-name");
        name.appendChild(el("span", null, title));
        var who = el("b", null, "vacío");
        name.appendChild(who);
        d.appendChild(name);
        var bar = el("div", "k-bar"), zone = el("div", "zone"), fill = el("div", "fill");
        bar.appendChild(zone); bar.appendChild(fill); d.appendChild(bar);
        if (slot) {
            var o = orderById(slot.order);
            who.textContent = o ? o.name : "#" + slot.order;
            // la barra llega hasta "quemado"
            zone.style.left = ((1 - win) / burnAt * 100) + "%";
            zone.style.width = (2 * win / burnAt * 100) + "%";
        } else {
            zone.style.display = "none";
        }
        d._slot = slot; d._fill = fill; d._burn = burnAt; d._win = win;
        return d;
    }

    function renderKitchen() {
        var ov = $("k-ovens"), fr = $("k-fryer");
        ov.textContent = ""; fr.textContent = "";
        if (!S) return;
        ov.appendChild(slotEl("Horno 1", S.ovens[0], BAKE_BURN, BAKE_WIN));
        ov.appendChild(slotEl("Horno 2", S.ovens[1], BAKE_BURN, BAKE_WIN));
        fr.appendChild(slotEl("Canasta 1", S.fryer[0], FRY_BURN, FRY_WIN));
        fr.appendChild(slotEl("Canasta 2", S.fryer[1], FRY_BURN, FRY_WIN));
    }

    function renderInfo() {
        $("st-earned").textContent = money(S.earned);
        $("st-served").textContent = S.served;
        $("st-streak").textContent = S.streak >= 2 ? S.streak + " 🔥" : S.streak;
        $("st-level").textContent = S.level;

        var hand = $("hand");
        if (S.hand) {
            var o = orderById(S.hand.order);
            var what = { raw: "Pizza cruda", baked: "Pizza horneada", boxed: "Caja de pizza" }[S.hand.kind];
            hand.textContent = "🍕 En la mano: " + what + " de " + (o ? o.name : "?");
            hand.classList.remove("hidden");
        } else hand.classList.add("hidden");

        var low = [];
        var names = { dough: "masa", sauce: "salsa", cheese: "queso" };
        for (var k in S.stock) {
            if (!S.stock.hasOwnProperty(k)) continue;
            var lim = names[k] ? 2 : 5;
            if (S.stock[k] <= lim) low.push(names[k] || (PIZZA.NAMES[k] || k).toLowerCase());
        }
        var warn = $("warn");
        if (low.length) { warn.textContent = "⚠ Queda poco: " + low.join(", ") + " · repón en la despensa"; warn.classList.remove("hidden"); }
        else warn.classList.add("hidden");
    }

    // ---------- Urgencia: la musica acelera, suena un reloj y los bordes laten en rojo ----------
    var musicEl = null, musicRate = 1, lastTick = 0;
    function urgency(dt) {
        var minLeft = 1;
        S.orders.forEach(function (o) {
            var left = 1 - (o.ago + dt) / o.patience;
            if (left < minLeft) minLeft = left;
        });
        var target = minLeft > 0.35 ? 1 : minLeft > 0.15 ? 1.1 : 1.22;
        musicRate += (target - musicRate) * 0.02;              // cambio suave, sin saltos
        if (musicEl) musicEl.playbackRate = Math.round(musicRate * 1000) / 1000;
        var critical = minLeft <= 0.15 && S.orders.length > 0;
        $("urgent").classList.toggle("on", critical);
        if (critical && Date.now() - lastTick > 1000) { lastTick = Date.now(); play("tick", 0.5); }
    }

    function tick() {
        requestAnimationFrame(tick);
        if (!S) return;
        var dt = Date.now() - recv;
        // paciencia en las comandas
        var nodes = $("tickets").children;
        for (var i = 0; i < nodes.length; i++) {
            var o = orderById(Number(nodes[i].dataset.id));
            if (!o) continue;
            var left = Math.max(0, 1 - (o.ago + dt) / o.patience);
            var fill = nodes[i].querySelector(".bar div");
            fill.style.width = (left * 100) + "%";
            fill.style.background = left > 0.6 ? "#4cd38a" : left > 0.35 ? "#f5c542" : left > 0.15 ? "#f08c3a" : "#e5484d";
            nodes[i].classList.toggle("urgent", left <= 0.15);
        }
        urgency(dt);
        // hornos y freidora
        var slots = document.querySelectorAll(".k-slot");
        for (var j = 0; j < slots.length; j++) {
            var d = slots[j], sl = d._slot;
            if (!sl) { d._fill.style.width = "0"; continue; }
            var r = (sl.ago + dt) / sl.target;
            d._fill.style.width = Math.min(100, r / d._burn * 100) + "%";
            d.classList.toggle("ready", r >= 1 - d._win && r <= 1 + d._win);
            d.classList.toggle("burning", r > 1 + d._win);
            var key = j + ":" + sl.order;
            if (r >= 0.95 && !alerted[key]) { alerted[key] = 1; play("ding"); toast("¡" + d.querySelector(".k-name span").textContent + " en su punto!", "good"); }
            if (r >= 1 + d._win && alerted[key] === 1) { alerted[key] = 2; play("alarm"); toast("¡Se está quemando! (" + d.querySelector(".k-name span").textContent + ")", "bad"); }
        }
    }

    // La tarjeta del tutorial se coloca donde hay que mirar: junto al panel iluminado o junto al objetivo 3D
    var tutorialAnchor = null, tutorialFocus = null;
    function placeTutorial() {
        var box = $("tutorial"), w = 330, h = box.offsetHeight || 140, W = window.innerWidth, H = window.innerHeight, x, y;
        if (tutorialFocus === "kitchen") {
            var k = $("kitchen").getBoundingClientRect();
            x = k.left - w - 28; y = k.top + k.height / 2 - h / 2;
        } else if (tutorialFocus === "tickets") {
            var tr = $("tickets").getBoundingClientRect(), rr = $("rail").getBoundingClientRect();
            x = rr.left + rr.width / 2 - w / 2; y = Math.max(tr.bottom, rr.bottom + 140) + 24;
        } else if (tutorialAnchor) {
            // a la derecha del objetivo; si no cabe, a la izquierda
            x = tutorialAnchor.x + 70; y = tutorialAnchor.y - h / 2;
            if (x + w > W - 290) x = tutorialAnchor.x - w - 70;
        } else {
            x = W / 2 - w / 2; y = H - h - 260;
        }
        box.style.left = Math.max(12, Math.min(W - w - 12, x)) + "px";
        box.style.top = Math.max(12, Math.min(H - h - 12, y)) + "px";
    }

    function toast(text, kind) {
        var t = el("div", "toast " + (kind || ""), text);
        $("toasts").appendChild(t);
        setTimeout(function () { t.remove(); }, 4500);
        while ($("toasts").children.length > 4) $("toasts").firstChild.remove();
    }

    var resultTimer;
    // Efectos del resultado: confeti si la pizza fue excelente y el dinero "vuela" al marcador de ganado
    function celebrate(card, d) {
        var rc = card.getBoundingClientRect(), sc = $("st-earned").getBoundingClientRect();
        var cx = rc.left + rc.width / 2, cy = rc.top + 40;
        if (d.final >= 85) {
            var colors = ["#f5a524", "#e5484d", "#4cd38a", "#4dabf7", "#ffd23c", "#c83c32"];
            for (var i = 0; i < 46; i++) {
                var c = el("div", "confetti");
                c.style.left = cx + "px"; c.style.top = cy + "px";
                c.style.background = colors[i % colors.length];
                var ang = Math.random() * Math.PI * 2, dist = 120 + Math.random() * 220;
                c.style.setProperty("--dx", Math.cos(ang) * dist + "px");
                c.style.setProperty("--dy", (Math.sin(ang) * dist + 160) + "px");
                c.style.setProperty("--rot", (Math.random() * 720 - 360) + "deg");
                c.style.animationDelay = (Math.random() * 0.15) + "s";
                $("hud").appendChild(c);
                setTimeout(function (n) { return function () { n.remove(); }; }(c), 2000);
            }
        }
        if (d.paid > 0) {
            var m = el("div", "money-fly", "+" + money(d.paid));
            m.style.left = (cx - 30) + "px"; m.style.top = (rc.bottom - 60) + "px";
            m.style.setProperty("--dx", (sc.left - cx + 20) + "px");
            m.style.setProperty("--dy", (sc.top - rc.bottom + 60) + "px");
            $("hud").appendChild(m);
            setTimeout(function () { m.remove(); }, 1600);
        }
    }

    function showResult(d) {
        var r = $("result");
        r.textContent = "";
        var head = el("div", "r-head");
        var img = el("img"); img.src = "../images/" + (d.tip > 0 ? "tip" : d.reaction) + ".png";
        head.appendChild(img);
        var who = el("div");
        who.appendChild(el("div", "r-name", d.name));
        who.appendChild(el("div", "r-quote", d.complaint ? "«" + d.complaint + "»" : d.final >= 85 ? "«¡Perfecta!»" : "«Gracias.»"));
        head.appendChild(who);
        r.appendChild(head);
        r.appendChild(el("div", "r-score", d.final));
        var stars = Math.round(d.final / 20);
        r.appendChild(el("div", "r-stars", "★★★★★".slice(0, stars) + "☆☆☆☆☆".slice(0, 5 - stars)));
        var parts = [["Ingredientes", d.parts.ing], ["Horneado", d.parts.bake], ["Corte", d.parts.cut], ["Espera", d.parts.wait]];
        if (d.parts.side !== false) parts.push(["Guarnición", d.parts.side]);
        parts.forEach(function (p) {
            var row = el("div", "r-part");
            row.appendChild(el("span", null, p[0]));
            var b = el("div", "b"), f = el("div"); f.style.width = p[1] + "%"; b.appendChild(f); row.appendChild(b);
            row.appendChild(el("em", null, p[1]));
            r.appendChild(row);
        });
        r.appendChild(el("div", "r-pay", "+" + money(d.paid)));
        if (d.tip > 0) r.appendChild(el("div", "r-tip", "incluye " + money(d.tip) + " de propina" + (d.streak >= 2 ? " · racha x" + d.streak : "")));
        else r.appendChild(el("div", "r-tip", d.final < 50 ? "Sin propina. El cliente se quejó." : "Sin propina."));
        r.classList.remove("hidden");
        celebrate(r, d);
        r.style.animation = "none"; void r.offsetWidth; r.style.animation = "";
        clearTimeout(resultTimer);
        resultTimer = setTimeout(function () { r.classList.add("hidden"); }, 6500);
    }

    // =====================================================================
    // Paneles
    // =====================================================================
    var win = $("win"), current = null, stock = {}, stockMax = {};

    function close() { play("close", 0.4); send("rp:pizzeria:ui:close"); }

    function header(title, sub) {
        var h = el("div", "w-head");
        var t = el("div", "w-title", title);
        if (sub) t.appendChild(el("small", null, sub));
        h.appendChild(t);
        var x = el("button", "x", "×");
        x.addEventListener("click", close);
        h.appendChild(x);
        return h;
    }
    function button(text, cls, fn) {
        var b = el("button", "btn " + (cls || ""), text);
        b.addEventListener("click", function (e) { play("click", 0.45); fn(e); });
        return b;
    }

    // ---------- Contratacion y salida ----------
    function panelHire(d) {
        win.className = "window hire";
        win.appendChild(header("Well Stacked Pizza", "Idlewood · Los Santos"));
        var hero = el("div", "hire-hero"), inner = el("div");
        inner.appendChild(el("b", null, "🍕 Pizzero"));
        inner.appendChild(el("span", null, d.hired ? "Tu trabajo actual" : "Se busca personal"));
        hero.appendChild(inner); win.appendChild(hero);
        win.appendChild(el("p", null, d.description));
        win.appendChild(el("p", "pay", d.pay));
        if (d.hired) {
            var g = el("div", "grid");
            [["Nivel", d.level], ["XP", d.xp], ["Pizzas", d.tasks], ["Ganado", money(d.earned)]].forEach(function (p) {
                var c = el("div"); c.appendChild(el("b", null, String(p[1]))); c.appendChild(document.createTextNode(p[0])); g.appendChild(c);
            });
            win.appendChild(g);
            if (d.best > 0) win.appendChild(el("p", "hint", "Mejor turno: " + money(d.best)));
            var row = el("div", "row");
            row.appendChild(button("Dejar el trabajo", "", function () { send("rp:pizzeria:ui:hire", "quit"); }));
            row.appendChild(el("div", "spacer"));
            row.appendChild(button("Ahora no", "", close));
            if (d.tasks > 0) row.appendChild(button("Turno con tutorial", "", function () { send("rp:pizzeria:ui:hire", "tutorial"); }));
            row.appendChild(button(d.tasks > 0 ? "Empezar turno" : "Empezar (con tutorial)", "go", function () { send("rp:pizzeria:ui:hire", "start"); }));
            win.appendChild(row);
        } else {
            win.appendChild(el("p", null, "¿Quieres trabajar de pizzero?"));
            if (d.other) win.appendChild(el("div", "note", "Dejarás tu trabajo actual de " + d.other + "."));
            var r2 = el("div", "row");
            r2.appendChild(el("div", "spacer"));
            r2.appendChild(button("No, gracias", "", close));
            r2.appendChild(button("Aceptar el trabajo", "primary", function () { send("rp:pizzeria:ui:hire", "hire"); }));
            win.appendChild(r2);
        }
    }

    function panelLeave() {
        win.className = "window hire";
        win.appendChild(header("¿Terminar el turno?", "Los pedidos pendientes se pierden"));
        var row = el("div", "row");
        row.appendChild(el("div", "spacer"));
        row.appendChild(button("Seguir trabajando", "", close));
        row.appendChild(button("Terminar turno", "primary", function () { send("rp:pizzeria:ui:leave"); }));
        win.appendChild(row);
    }

    // ---------- Armado ----------
    var GRID = 22, R = 200, CX = 230, CY = 230, INNER = R * 0.88, BRUSH = 30;

    function panelAssembly(d) {
        win.className = "window";
        win.appendChild(header("Mesa de armado", "Elige la comanda, pon salsa y queso, y coloca los ingredientes"));
        var a = { ticket: d.tickets[0], sauce: {}, cheese: {}, items: [], tool: "sauce", painting: false, cellsTotal: 0 };
        current = a;

        var wrap = el("div", "kitchen-win");
        // izquierda: comandas
        var left = el("div", "col-left");
        left.appendChild(el("div", "hint", "Comandas por armar"));
        d.tickets.forEach(function (t) {
            var tk = el("div", "tk" + (t === a.ticket ? " sel" : ""));
            tk.appendChild(el("b", null, t.name + " #" + t.id));
            t.pizza.toppings.forEach(function (tp) {
                tk.appendChild(el("div", null, tp.count + "× " + PIZZA.NAMES[tp.id] + (tp.zone !== "whole" ? " (" + PIZZA.ZONES[tp.zone] + ")" : "")));
            });
            tk.addEventListener("click", function () {
                a.ticket = t;
                Array.prototype.forEach.call(left.querySelectorAll(".tk"), function (n) { n.classList.remove("sel"); });
                tk.classList.add("sel"); play("select", 0.45); refresh();
            });
            left.appendChild(tk);
        });
        var c = canvas(100); left.appendChild(c); a.preview = c;
        wrap.appendChild(left);

        // centro: tabla y pizza
        var board = el("div", "board");
        var cv = canvas(460); board.appendChild(cv);
        wrap.appendChild(board);
        var ctx = cv.getContext("2d");

        // derecha: herramientas y comprobacion
        var right = el("div", "col-right");
        var tools = el("div", "tools");
        var toolList = [{ id: "sauce", name: "Salsa", base: true }, { id: "cheese", name: "Queso", base: true }];
        Object.keys(PIZZA.NAMES).forEach(function (id) { if (stockMax[id] !== undefined) toolList.push({ id: id, name: PIZZA.NAMES[id] }); });
        a.toolEls = {};
        toolList.forEach(function (t) {
            var b = el("div", "tool"), ic = canvas(30); PIZZA.icon(ic, t.id); b.appendChild(ic);
            var txt = el("div"); txt.appendChild(document.createTextNode(t.name)); var sm = el("small"); txt.appendChild(sm); b.appendChild(txt);
            b.addEventListener("click", function () { a.tool = t.id; play("select", 0.45); refresh(); });
            a.toolEls[t.id] = { el: b, small: sm };
            tools.appendChild(b);
        });
        right.appendChild(tools);
        var check = el("div", "check"); right.appendChild(check);
        var row = el("div", "row");
        row.appendChild(button("Deshacer", "", function () { a.items.pop(); refresh(); }));
        row.appendChild(button("Limpiar", "", function () { a.items = []; a.sauce = {}; a.cheese = {}; a.sauceOk = a.cheeseOk = false; refresh(); }));
        right.appendChild(row);
        var go = button("Al horno ➜", "go", function () {
            go.disabled = true;
            send("rp:pizzeria:ui:assemble", a.ticket.id, coverage(a.sauce), coverage(a.cheese), JSON.stringify([a.items]));
            setTimeout(function () { go.disabled = false; }, 1200);
        });
        right.appendChild(go);
        right.appendChild(el("div", "hint", "Salsa y queso: arrastra sobre la masa. Ingredientes: clic donde quieras ponerlos. Esc para salir."));
        wrap.appendChild(right);
        win.appendChild(wrap);

        // celdas validas (dentro de la masa)
        for (var gy = 0; gy < GRID; gy++) for (var gx = 0; gx < GRID; gx++) if (inCell(gx, gy)) a.cellsTotal++;

        function inCell(gx, gy) {
            var cell = INNER * 2 / GRID;
            var x = -INNER + (gx + .5) * cell, y = -INNER + (gy + .5) * cell;
            return x * x + y * y <= INNER * INNER * 0.92;
        }
        function coverage(cells) { return Math.round(Object.keys(cells).length / a.cellsTotal * 100) / 100; }
        function paint(px, py) {
            var cells = a.tool === "sauce" ? a.sauce : a.cheese;
            var cell = INNER * 2 / GRID;
            for (var gy = 0; gy < GRID; gy++) for (var gx = 0; gx < GRID; gx++) {
                var x = CX - INNER + (gx + .5) * cell, y = CY - INNER + (gy + .5) * cell;
                if ((x - px) * (x - px) + (y - py) * (y - py) <= BRUSH * BRUSH && inCell(gx, gy)) cells[gy * GRID + gx] = 1;
            }
            // al llegar a cubrir lo suficiente, un "bien" una sola vez por capa
            var key = a.tool === "sauce" ? "sauceOk" : "cheeseOk";
            if (!a[key] && coverage(cells) >= 0.8) { a[key] = true; play("good", 0.5); }
        }
        function used(id) { var n = 0; a.items.forEach(function (p) { if (p.t === id) n++; }); return n; }

        function refresh() {
            ctx.clearRect(0, 0, 460, 460);
            PIZZA.draw(ctx, CX, CY, R, { sauce: a.sauce, cheese: a.cheese, items: a.items, grid: GRID });
            if (a.pop && Date.now() - a.pop.t < 300) {
                var k = (Date.now() - a.pop.t) / 300;
                ctx.strokeStyle = "rgba(255,255,255," + (1 - k) + ")"; ctx.lineWidth = 3;
                ctx.beginPath(); ctx.arc(a.pop.x, a.pop.y, 10 + k * 26, 0, Math.PI * 2); ctx.stroke();
            }
            var halves = a.ticket.pizza.toppings.some(function (t) { return t.zone !== "whole"; });
            if (halves) {
                ctx.strokeStyle = "rgba(255,255,255,.5)"; ctx.setLineDash([6, 6]); ctx.lineWidth = 2;
                ctx.beginPath(); ctx.moveTo(CX, CY - R); ctx.lineTo(CX, CY + R); ctx.stroke(); ctx.setLineDash([]);
            }
            PIZZA.mini(a.preview, a.ticket.pizza);
            Object.keys(a.toolEls).forEach(function (id) {
                var t = a.toolEls[id];
                t.el.classList.toggle("sel", a.tool === id);
                var left = id === "sauce" || id === "cheese" ? (stock[id] || 0) : (stock[id] || 0) - used(id);
                t.small.textContent = (id === "sauce" || id === "cheese") ? "quedan " + left : left + " en stock";
                t.el.classList.toggle("empty", left <= 0);
            });
            check.textContent = "";
            function line(label, value, ok) {
                var d2 = el("div"); d2.appendChild(el("span", null, label)); d2.appendChild(el("b", ok ? "ok" : "bad", value)); check.appendChild(d2);
            }
            var sc = coverage(a.sauce), ch = coverage(a.cheese);
            line("Salsa", Math.round(sc * 100) + "%", sc >= 0.8);
            line("Queso", Math.round(ch * 100) + "%", ch >= 0.8);
            a.ticket.pizza.toppings.forEach(function (tp) {
                var n = 0;
                a.items.forEach(function (p) {
                    if (p.t !== tp.id) return;
                    if (tp.zone === "whole" || (tp.zone === "left" && p.x < -0.08) || (tp.zone === "right" && p.x > 0.08)) n++;
                });
                line(PIZZA.NAMES[tp.id] + (tp.zone !== "whole" ? " (" + PIZZA.ZONES[tp.zone] + ")" : ""), n + " / " + tp.count, n === tp.count);
            });
            line("Masa disponible", String(stock.dough || 0), (stock.dough || 0) > 0);
            coach();
        }
        a.refresh = refresh;

        // ---- Entrenador (tutorial y niveles bajos): un paso a la vez, solo lo que hay que tocar iluminado ----
        var dim = null, bubble = null;
        if (d.coach) {
            dim = el("div", "coach-dim"); win.appendChild(dim);
            bubble = el("div", "coach-bubble"); win.appendChild(bubble);
        }
        function placedIn(tp) {
            var n = 0;
            a.items.forEach(function (p) {
                if (p.t !== tp.id) return;
                if (tp.zone === "whole" || (tp.zone === "left" && p.x < -0.08) || (tp.zone === "right" && p.x > 0.08)) n++;
            });
            return n;
        }
        function coach() {
            if (!d.coach) return;
            var step, key, target, text, tool;
            if (coverage(a.sauce) < 0.8) {
                step = 1; key = "sauce"; tool = "sauce"; target = a.toolEls.sauce.el;
                text = "Toca la SALSA y pinta la masa: mantén el clic y arrastra hasta cubrirla toda.";
            } else if (coverage(a.cheese) < 0.8) {
                step = 2; key = "cheese"; tool = "cheese"; target = a.toolEls.cheese.el;
                text = "¡Bien! Ahora el QUESO: píntalo encima de la salsa igual que antes.";
            } else {
                var tps = a.ticket.pizza.toppings;
                for (var i = 0; i < tps.length; i++) {
                    var tp = tps[i], n = placedIn(tp);
                    if (n !== tp.count) {
                        step = 3; key = "top:" + tp.id; tool = tp.id; target = a.toolEls[tp.id] && a.toolEls[tp.id].el;
                        var where = tp.zone === "left" ? " en la mitad IZQUIERDA" : tp.zone === "right" ? " en la mitad DERECHA" : "";
                        text = "Pon " + tp.count + " " + PIZZA.NAMES[tp.id].toUpperCase() + where + ": haz clic sobre la pizza. Llevas " + n + " de " + tp.count +
                            (n > tp.count ? " (te sobran: usa Deshacer)." : ".");
                        break;
                    }
                }
                if (!step) { step = 4; key = "oven"; target = go; text = "¡Pizza lista! Pulsa AL HORNO."; }
            }
            // al cambiar de paso se elige sola la herramienta correcta
            if (key !== a.coachKey) {
                a.coachKey = key;
                if (tool) { a.tool = tool; Object.keys(a.toolEls).forEach(function (id) { a.toolEls[id].el.classList.toggle("sel", id === tool); }); }
                play("step", 0.5);
            }
            Array.prototype.forEach.call(win.querySelectorAll(".coach-spot"), function (n2) { n2.classList.remove("coach-spot"); });
            if (target) target.classList.add("coach-spot");
            if (step <= 3) board.classList.add("coach-spot");
            bubble.textContent = "";
            bubble.appendChild(el("b", null, "Paso " + step + " de 4"));
            // dibujo del raton: arrastrar para pintar, clic para el resto
            var mouse = el("img", "key-ico"); mouse.src = "../images/keys/" + (step <= 2 ? "mouse_move" : "mouse_left") + ".png";
            bubble.appendChild(mouse);
            bubble.appendChild(el("div", null, text));
            // globo pegado a lo que hay que tocar (a su izquierda, sobre el borde de la tabla)
            if (target) {
                var wr = win.getBoundingClientRect(), tr = target.getBoundingClientRect();
                bubble.style.left = Math.max(8, tr.left - wr.left - 262) + "px";
                bubble.style.top = Math.max(8, tr.top - wr.top + tr.height / 2 - 40) + "px";
            }
        }

        function pos(e) { var r = cv.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; }
        cv.addEventListener("mousedown", function (e) {
            var p = pos(e);
            if (a.tool === "sauce" || a.tool === "cheese") {
                if ((stock[a.tool] || 0) <= 0) return;
                // un sonido suave al empezar el trazo (no uno por cada tramo: se pisaban y sonaba a fallo)
                play("paint", 0.3);
                a.painting = true; paint(p.x, p.y); refresh(); return;
            }
            var nx = (p.x - CX) / INNER, ny = (p.y - CY) / INNER;
            if (nx * nx + ny * ny > 0.95) return;
            if ((stock[a.tool] || 0) - used(a.tool) <= 0) return;
            if (a.items.length >= 40) return;
            a.items.push({ t: a.tool, x: Math.round(nx * 1000) / 1000, y: Math.round(ny * 1000) / 1000 });
            play("pop", 0.4);
            // rebote: aro que se abre donde cayo el ingrediente
            a.pop = { x: p.x, y: p.y, t: Date.now() };
            (function anim() { if (!a.pop || Date.now() - a.pop.t > 300) { refresh(); return; } refresh(); requestAnimationFrame(anim); })();
            refresh();
        });
        cv.addEventListener("mousemove", function (e) { if (a.painting) { var p = pos(e); paint(p.x, p.y); refresh(); } });
        window.addEventListener("mouseup", function () { a.painting = false; });
        refresh();
    }

    // ---------- Corte ----------
    function panelCut(d) {
        var need = d.slices / 2;
        win.className = "window";
        win.appendChild(header("Corte y empaque", "Pizza de " + d.name + ": " + d.slices + " trozos"));
        var a = { cuts: [], start: null, preview: null, done: {}, flash: null, t0: Date.now() };
        current = a;
        var wrap = el("div", "kitchen-win");
        var board = el("div", "board"); var cv = canvas(460); board.appendChild(cv); wrap.appendChild(board);
        var boxLid = el("div", "box-lid hidden"); board.appendChild(boxLid);
        var praise = el("div", "praise hidden"); board.appendChild(praise);
        var ctx = cv.getContext("2d");
        var right = el("div", "col-right");

        // Explicacion para todos: 3 pasos con dibujo y frase corta
        var how = el("div", "cut-how");
        [["🔪", "Agarra el cuchillo"], ["@mouse_move", d.guides ? "Arrastra por la línea amarilla" : "Arrastra pasando por el centro"], ["🍕", need + " cortes = " + d.slices + " trozos"]].forEach(function (s, i) {
            var st = el("div", "cut-step"), ico = el("b");
            if (s[0].charAt(0) === "@") { var im = el("img", "key-ico"); im.src = "../images/keys/" + s[0].slice(1) + ".png"; ico.appendChild(im); }
            else ico.textContent = s[0];
            st.appendChild(ico); st.appendChild(el("span", null, (i + 1) + ". " + s[1])); how.appendChild(st);
        });
        right.appendChild(how);
        var info = el("div", "check"); right.appendChild(info);
        var row = el("div", "row");
        row.appendChild(button("Deshacer", "", function () { var c = a.cuts.pop(); if (c && c.guide !== undefined) delete a.done[c.guide]; }));
        row.appendChild(button("Tirar pizza", "", function () { send("rp:pizzeria:ui:discard"); close(); }));
        right.appendChild(row);
        var go = button("Empacar ➜", "go", function () {
            go.disabled = true;
            play("box");
            boxLid.classList.remove("hidden");   // la caja se cierra sobre la pizza
            setTimeout(function () {
                send("rp:pizzeria:ui:cut", JSON.stringify([a.cuts.map(function (c) { return { a: c.a, d: c.d }; })]));
            }, 650);
            setTimeout(function () { go.disabled = false; boxLid.classList.add("hidden"); }, 1800);
        });
        right.appendChild(go);
        wrap.appendChild(right);
        win.appendChild(wrap);
        var built = d.built || {};

        // Lineas guia: la primera vertical y el resto repartidas por igual
        var guides = [];
        for (var i = 0; i < need; i++) guides.push(90 + i * 180 / need);
        function guideLine(angDeg) {
            var r = angDeg * Math.PI / 180, ux = Math.cos(r), uy = Math.sin(r), L = R * 1.02;
            return { x1: CX - ux * L, y1: CY - uy * L, x2: CX + ux * L, y2: CY + uy * L };
        }
        function nextGuide() { for (var g = 0; g < guides.length; g++) if (!a.done[g]) return g; return -1; }

        function draw() {
            ctx.clearRect(0, 0, 460, 460);
            var cuts = a.cuts.slice(); if (a.start && a.preview) cuts.push(a.preview);
            PIZZA.draw(ctx, CX, CY, R, { sauce: !!built.sauce, cheese: !!built.cheese, items: built.items || [], ratio: d.ratio, cuts: cuts });
            var now = Date.now();
            if (d.guides) {
                var ng = nextGuide();
                guides.forEach(function (ang, g) {
                    if (a.done[g]) return;
                    var l = guideLine(ang), active = g === ng;
                    ctx.save();
                    ctx.setLineDash([12, 10]); ctx.lineDashOffset = -now / 40;
                    ctx.lineWidth = active ? 6 : 3;
                    ctx.strokeStyle = active ? "rgba(255,210,60," + (0.65 + 0.35 * Math.sin(now / 200)) + ")" : "rgba(255,255,255,.35)";
                    ctx.beginPath(); ctx.moveTo(l.x1, l.y1); ctx.lineTo(l.x2, l.y2); ctx.stroke();
                    ctx.restore();
                    // numero del corte en la punta
                    ctx.fillStyle = active ? "#ffd23c" : "rgba(255,255,255,.6)";
                    ctx.beginPath(); ctx.arc(l.x1, l.y1, 15, 0, Math.PI * 2); ctx.fill();
                    ctx.fillStyle = "#2b2520"; ctx.font = "bold 16px Segoe UI"; ctx.textAlign = "center"; ctx.textBaseline = "middle";
                    ctx.fillText(String(g + 1), l.x1, l.y1);
                    // cuchillo que recorre la linea activa mientras no estas cortando
                    if (active && !a.start) {
                        var t = ((now - a.t0) % 1800) / 1800;
                        var kx = l.x1 + (l.x2 - l.x1) * t, ky = l.y1 + (l.y2 - l.y1) * t;
                        ctx.font = "34px Segoe UI Emoji"; ctx.fillText("🔪", kx + 14, ky - 14);
                    }
                });
            } else {
                // sin guias: solo el centro marcado
                ctx.fillStyle = "rgba(255,255,255,.75)"; ctx.beginPath(); ctx.arc(CX, CY, 5, 0, Math.PI * 2); ctx.fill();
            }
            if (a.flash && now - a.flash.t < 350) {   // destello del corte recien hecho
                ctx.save(); ctx.beginPath(); ctx.arc(CX, CY, R, 0, Math.PI * 2); ctx.clip();
                ctx.strokeStyle = "rgba(255,255,255," + (1 - (now - a.flash.t) / 350) + ")"; ctx.lineWidth = 10;
                ctx.beginPath(); ctx.moveTo(a.flash.l.x1, a.flash.l.y1); ctx.lineTo(a.flash.l.x2, a.flash.l.y2); ctx.stroke(); ctx.restore();
            }
            info.textContent = "";
            var l1 = el("div"); l1.appendChild(el("span", null, "Cortes"));
            l1.appendChild(el("b", a.cuts.length === need ? "ok" : "bad", a.cuts.length + " / " + need)); info.appendChild(l1);
            go.classList.toggle("pulse", a.cuts.length === need);
        }
        (function loop() { if (!cv.isConnected) return; draw(); requestAnimationFrame(loop); })();

        function showPraise(text, good) {
            praise.textContent = text;
            praise.className = "praise " + (good ? "good" : "meh");
            void praise.offsetWidth;
            praise.classList.add("show");
            play(good ? "good" : "meh", 0.55);
        }
        function pos(e) { var r = cv.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; }
        function lineFrom(p1, p2) {
            var dx = p2.x - p1.x, dy = p2.y - p1.y, len = Math.sqrt(dx * dx + dy * dy);
            if (len < 10) return null;
            var ux = dx / len, uy = dy / len;
            var dist = Math.abs((CX - p1.x) * uy - (CY - p1.y) * ux) / R;   // 0 = pasa por el centro
            var ang = (Math.atan2(dy, dx) * 180 / Math.PI + 360) % 180;
            return { x1: p1.x - ux * 600, y1: p1.y - uy * 600, x2: p1.x + ux * 600, y2: p1.y + uy * 600, a: Math.round(ang * 10) / 10, d: Math.round(dist * 1000) / 1000, len: len };
        }
        // Con guias, un trazo parecido a una linea pendiente se ajusta a ella
        function snap(l) {
            if (!d.guides || l.d > 0.3) return l;
            var best = -1, bestDiff = 22;
            guides.forEach(function (g, i) {
                if (a.done[i]) return;
                var diff = Math.abs((((l.a - g) % 180) + 270) % 180 - 90);
                if (diff < bestDiff) { best = i; bestDiff = diff; }
            });
            if (best < 0) return l;
            var gl = guideLine(guides[best]);
            a.done[best] = true;
            return { x1: gl.x1 * 3 - CX * 2, y1: gl.y1 * 3 - CY * 2, x2: gl.x2 * 3 - CX * 2, y2: gl.y2 * 3 - CY * 2,
                a: guides[best] % 180, d: 0, guide: best, snapped: true };
        }
        cv.addEventListener("mousedown", function (e) { a.start = pos(e); a.preview = null; });
        cv.addEventListener("mousemove", function (e) { if (a.start) a.preview = lineFrom(a.start, pos(e)); });
        window.addEventListener("mouseup", function (e) {
            if (!a.start) return;
            var l = lineFrom(a.start, pos(e));
            a.start = null; a.preview = null;
            if (!l || l.len < R * 0.9) { if (l) showPraise("¡Más largo! De un lado al otro", false); return; }
            if (a.cuts.length >= 12) return;
            l = snap(l);
            a.cuts.push(l);
            a.flash = { l: l, t: Date.now() };
            play("chop", 0.7);
            if (l.snapped) showPraise(a.cuts.length === need ? "¡Perfecto! Ahora empácala" : "¡Bien!", true);
            else if (d.guides) showPraise("Intenta seguir la línea amarilla", false);
        });
    }

    // ---------- Freidora ----------
    function panelFryer(d) {
        win.className = "window fryer";
        win.appendChild(header("Freidora", "Papas fritas y palitos de ajo: sácalos en la zona verde"));
        var recvF = Date.now();
        var baskets = el("div", "baskets");
        var anyFree = false;
        d.baskets.forEach(function (b, i) {
            var box = el("div", "basket" + (b ? " on" : ""));
            box.appendChild(el("div", "oil"));
            var inner = el("div", "b-in");
            inner.appendChild(el("div", "b-title", "Canasta " + (i + 1)));
            if (b) {
                inner.appendChild(el("div", "hint", PIZZA.SIDES[b.side] + " · pedido #" + b.order));
                var bar = el("div", "k-bar"), zone = el("div", "zone"), fill = el("div", "fill");
                zone.style.left = ((1 - FRY_WIN) / FRY_BURN * 100) + "%"; zone.style.width = (2 * FRY_WIN / FRY_BURN * 100) + "%";
                bar.appendChild(zone); bar.appendChild(fill); inner.appendChild(bar);
                (function animate() {
                    if (!fill.isConnected) return;
                    var r = (b.ago + Date.now() - recvF) / b.target;
                    fill.style.width = Math.min(100, r / FRY_BURN * 100) + "%";
                    fill.style.background = r > 1 + FRY_WIN ? "#e5484d" : r >= 1 - FRY_WIN ? "#4cd38a" : "#f5a524";
                    requestAnimationFrame(animate);
                })();
                inner.appendChild(button("Sacar", "primary", function () { send("rp:pizzeria:ui:fry", "take", i + 1); }));
            } else {
                anyFree = true;
                inner.appendChild(el("div", "hint", "Vacía"));
            }
            box.appendChild(inner);
            baskets.appendChild(box);
        });
        win.appendChild(baskets);
        win.appendChild(el("div", "hint", "Guarniciones pendientes"));
        var list = el("div", "list");
        if (!d.pending.length) list.appendChild(el("div", "hint", "Ningún pedido lleva guarnición ahora mismo."));
        d.pending.forEach(function (p) {
            var it = el("div", "item");
            it.appendChild(el("span", null, PIZZA.SIDES[p.side] + " para " + p.name + " (#" + p.id + ")"));
            it.appendChild(el("div", "spacer"));
            var b = button("Freír", "go", function () { send("rp:pizzeria:ui:fry", "fry", p.id); });
            b.disabled = !anyFree;
            it.appendChild(b);
            list.appendChild(it);
        });
        win.appendChild(list);
    }

    // ---------- Despensa ----------
    function panelPantry() {
        win.className = "window pantry";
        win.appendChild(header("Despensa", "Arrastra cada caja a su estante para reponer"));
        var shelves = el("div", "shelves"), crates = el("div", "crates");
        var ids = ["dough", "sauce", "cheese"].concat(Object.keys(PIZZA.NAMES).filter(function (id) { return stockMax[id] !== undefined; }));
        var names = { dough: "Masa", sauce: "Salsa", cheese: "Queso" };
        var shelfEls = {};
        ids.forEach(function (id) {
            var s = el("div", "shelf"); s.dataset.id = id;
            var ic = canvas(40); PIZZA.icon(ic, id); s.appendChild(ic);
            s.appendChild(el("div", "s-name", names[id] || PIZZA.NAMES[id]));
            var bar = el("div", "k-bar"), fill = el("div", "fill"); bar.appendChild(fill); s.appendChild(bar);
            var cnt = el("div", "s-count"); s.appendChild(cnt);
            shelfEls[id] = { el: s, fill: fill, cnt: cnt };
            shelves.appendChild(s);

            var cr = el("div", "crate"); cr.dataset.id = id;
            var ic2 = canvas(22); PIZZA.icon(ic2, id); cr.appendChild(ic2);
            cr.appendChild(el("div", null, (names[id] || PIZZA.NAMES[id]).toUpperCase()));
            cr.addEventListener("mousedown", function (e) { startDrag(cr, e); });
            crates.appendChild(cr);
        });
        win.appendChild(shelves); win.appendChild(crates);
        win.appendChild(el("div", "hint", "Cada caja repone una parte del estante. Si no queda masa, salsa o queso, no podrás armar pizzas."));

        function refresh() {
            ids.forEach(function (id) {
                var max = stockMax[id] || 1, n = stock[id] || 0, s = shelfEls[id];
                s.fill.style.width = (n / max * 100) + "%";
                s.fill.style.background = n / max < 0.25 ? "#e5484d" : n / max < 0.5 ? "#f5a524" : "#4cd38a";
                s.cnt.textContent = n + " / " + max;
                s.el.classList.toggle("full", n >= max);
            });
        }
        current = { refresh: refresh };

        var drag = null;
        function startDrag(cr, e) {
            if (cr.classList.contains("cool")) return;
            var g = cr.cloneNode(true); g.classList.add("ghost"); document.body.appendChild(g);
            drag = { id: cr.dataset.id, ghost: g, src: cr };
            move(e);
        }
        function over(e) {
            var t = document.elementFromPoint(e.clientX, e.clientY);
            while (t && !(t.classList && t.classList.contains("shelf"))) t = t.parentNode;
            return t;
        }
        function move(e) {
            if (!drag) return;
            drag.ghost.style.left = e.clientX + "px"; drag.ghost.style.top = e.clientY + "px";
            Array.prototype.forEach.call(shelves.children, function (s) { s.classList.remove("over"); });
            var t = over(e); if (t && t.dataset.id === drag.id) t.classList.add("over");
        }
        window.addEventListener("mousemove", move);
        window.addEventListener("mouseup", function (e) {
            if (!drag) return;
            var t = over(e), d0 = drag; drag = null;
            d0.ghost.remove();
            Array.prototype.forEach.call(shelves.children, function (s) { s.classList.remove("over"); });
            if (t && t.dataset.id === d0.id) {
                send("rp:pizzeria:ui:restock", d0.id);
                play("restock", 0.7);
                Array.prototype.forEach.call(crates.children, function (c) { c.classList.add("cool"); });
                setTimeout(function () { Array.prototype.forEach.call(crates.children, function (c) { c.classList.remove("cool"); }); }, 1600);
            }
        });
        refresh();
    }

    // =====================================================================
    // API para Lua
    // =====================================================================
    window.PZ = {
        state: function (s) {
            S = s; recv = Date.now();
            stock = s.stock || stock;
            renderTickets(); renderKitchen(); renderInfo();
        },
        fx: function (kind, d) {
            if (kind === "bell") { play("bell"); toast("🔔 Entró un cliente", ""); }
            else if (kind === "ordered") { play("print"); }
            else if (kind === "oven_in") play("oven");
            else if (kind === "oven_out") play(d.ratio >= BAKE_BURN ? "alarm" : "oven");
            else if (kind === "fry_in") play("sizzle");
            else if (kind === "boxed") play("box");
            else if (kind === "served") { play(d.final >= 50 ? "cash" : "angry"); showResult(d); }
            else if (kind === "left") { play("angry"); toast("😠 Un cliente se fue sin su pizza", "bad"); }
        },
        panel: function (kind, d) {
            if (d && d.max) stockMax = d.max;
            if (d && d.stock) stock = d.stock;
            // la freidora y la despensa se refrescan en sitio
            if (kind === "pantry" && current && current.refresh && win.classList.contains("pantry")) { current.refresh(); return; }
            win.textContent = "";
            current = null;
            if ($("panel").classList.contains("hidden") && kind !== "leave") play("open", 0.4);
            $("panel").classList.remove("hidden");
            if (kind === "hire") panelHire(d);
            else if (kind === "leave") panelLeave();
            else if (kind === "assembly") panelAssembly(d);
            else if (kind === "cut") panelCut(d);
            else if (kind === "fryer") panelFryer(d);
            else if (kind === "pantry") panelPantry(d);
        },
        // Musica de fondo en bucle (sounds/music.mp3). Si el archivo no existe, no suena nada.
        music: function (vol) {
            try {
                var m = new Audio("sounds/musica_fondo.mp3");
                m.loop = true; m.volume = Math.max(0, Math.min(1, Number(vol) || 0));
                var p = m.play(); if (p && p.catch) p.catch(function () {});
                musicEl = m;
            } catch (e) { /* sin musica */ }
        },
        // Tarjeta del tour guiado: { step, total, title, text } o null para ocultarla
        tutorial: function (t) {
            var box = $("tutorial");
            // foco: oscurece la pantalla y deja iluminada solo una parte del HUD
            ["kitchen", "rail"].forEach(function (id) { $(id).classList.remove("spot"); });
            if (t && t.focus) $(t.focus === "tickets" ? "rail" : t.focus).classList.add("spot");
            if (!t) { box.classList.add("hidden"); return; }
            box.querySelector(".tu-step").textContent = "Tutorial · paso " + t.step + " de " + t.total;
            box.querySelector(".tu-title").textContent = t.title;
            box.querySelector(".tu-text").textContent = t.text;
            var bar = box.querySelector(".tu-bar");
            if (!bar) { bar = el("div", "tu-bar"); bar.appendChild(el("div")); box.appendChild(bar); }
            bar.firstChild.style.width = (t.step / t.total * 100) + "%";
            tutorialFocus = t.focus || null;
            placeTutorial();
            if (box.classList.contains("hidden") || box.dataset.step !== String(t.step)) play("step", 0.45);
            box.dataset.step = String(t.step);
            box.classList.remove("hidden");
        },
        // Punto de la pantalla donde esta el objetivo 3D (lo manda Lua): la tarjeta se pone al lado
        tutorialAt: function (x, y) { tutorialAnchor = x >= 0 ? { x: x, y: y } : null; placeTutorial(); },
        // Con una ventana abierta la tarjeta se esconde (la ventana trae su propia guia)
        tutorialHidden: function (on) { $("tutorial").classList.toggle("away", !!on); },
        stock: function (s) {
            stock = s || stock;
            if (current && current.refresh) current.refresh();
        },
        demo: function () {
            var o = { id: 1, name: "Rosa", status: "waiting", stage: "new", ago: 20000, patience: 170000,
                pizza: { toppings: [{ id: "pepperoni", count: 6, zone: "whole" }, { id: "olive", count: 4, zone: "left" }], bake: "normal", slices: 6 }, side: "fries", sideState: false };
            var st = { dough: 4, sauce: 5, cheese: 5, pepperoni: 18, mushroom: 18, olive: 18 };
            var mx = { dough: 8, sauce: 10, cheese: 10, pepperoni: 36, mushroom: 36, olive: 36 };
            if (MODE === "hud") {
                PZ.state({ orders: [o, { id: 2, name: "Kevin", status: "queue", stage: "new", ago: 3000, patience: 150000, pizza: o.pizza }], queue: [2],
                    hand: { order: 1, kind: "raw" }, ovens: [{ order: 1, ago: 15000, target: 22000 }, false], fryer: [false, false],
                    stock: st, earned: 340, served: 4, streak: 3, level: 2 });
                PZ.fx("served", { id: 3, name: "Tony", final: 91, reaction: "love", complaint: false, paid: 92, tip: 30, streak: 3,
                    parts: { ing: 95, bake: 88, cut: 90, wait: 100, side: false } });
                PZ.tutorial({ step: 6, total: 12, title: "Mira la cocina", text: "Aquí ves cómo se hornea. Cuando la barra llegue a la zona verde, sácala.", focus: "kitchen" });
            } else {
                if (location.hash === "#panel-cut") PZ.panel("cut", { id: 1, name: "Rosa", slices: 6, guides: true, ratio: 1, built: { sauce: true, cheese: true, items: [{ t: "pepperoni", x: 0.3, y: 0.2 }, { t: "pepperoni", x: -0.4, y: -0.3 }, { t: "olive", x: -0.2, y: 0.5 }] } });
                else PZ.panel("assembly", { tickets: [{ id: 1, name: "Rosa", pizza: o.pizza }], stock: st, max: mx, coach: true });
            }
        }
    };

    document.addEventListener("keydown", function (e) {
        if (MODE === "panel" && (e.key === "Escape" || e.key === "Backspace")) close();
    });

    if (MODE === "hud") { $("hud").classList.remove("hidden"); requestAnimationFrame(tick); }
    if (!window.mta) { document.body.style.background = "#46525e"; setTimeout(function () { PZ.demo(); }, 200); }
})();
