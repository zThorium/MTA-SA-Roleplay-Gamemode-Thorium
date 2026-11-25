/*
 * rp_vending / vending.js
 * La maquina expendedora: vitrina con espirales y codigos (11, 12, 13, 21...), panel con
 * pantalla y teclado, datafono (mismo minijuego que rp_vehicles/html/fuel.js) y la caida del
 * producto a la bandeja.
 *
 * Lua llama a RPV.menu(datos), RPV.pos(datos), RPV.result(ok, texto, efectivo) y RPV.hide().
 * Eventos hacia Lua: rp:vending:ui:choose (codigo), rp:vending:ui:back, rp:vending:ui:cancel,
 * rp:vending:ui:pay ("card"|"cash", dueno, clave), rp:vending:ui:sound (nombre).
 */
(function () {
    "use strict";

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);   // vista previa en un navegador normal
    }
    var $ = function (id) { return document.getElementById(id); };
    function el(tag, className, text) {
        var n = document.createElement(tag);
        if (className) n.className = className;
        if (text !== undefined) n.textContent = text;
        return n;
    }
    function money(n) { return "$" + Math.round(Number(n) || 0).toLocaleString("es"); }
    function list(x) { return Array.isArray(x) ? x : (x && typeof x === "object" ? Object.keys(x).map(function (k) { return x[k]; }) : []); }
    function sound(name) { send("rp:vending:ui:sound", name); }
    function later(fn, ms) { return setTimeout(fn, ms); }

    var view = null;

    // =============================================================== Maquina
    // phase: "select" (marcando) | "wait" (esperando al servidor) | "pay" | "dispense" | "ready" | "taken"
    var M = null;
    var KEYPAD = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK"];

    function makeUnit(prod, depth) {
        var u = el("div", "unit d" + depth);
        var p = el("div", "p p-" + (prod.look || "can"));
        p.style.setProperty("--c", prod.color || "#888");
        p.appendChild(el("span", "tag", prod.tag || ""));
        u.appendChild(p);
        return u;
    }

    function menu(d) {
        var products = list(d.products), slots = list(d.slots), cols = Number(d.columns) || 3;
        M = { d: d, products: products, codes: {}, input: "", phase: "select", picked: null, timer: null };

        $("machine").classList.toggle("food", d.kind === "food");
        $("machine").classList.remove("dim");
        $("v-brand").textContent = d.brand || d.title || "Expendedora";

        // Vitrina: estantes de "cols" espirales; los huecos sobrantes quedan vacios
        var shelves = $("v-shelves");
        shelves.textContent = "";
        var rows = Math.max(1, Math.ceil(slots.length / cols));
        for (var r = 0; r < rows; r++) {
            var shelf = el("div", "shelf");
            shelf.style.gridTemplateColumns = "repeat(" + cols + ", 1fr)";
            for (var c = 0; c < cols; c++) {
                var s = slots[r * cols + c];
                var slot = el("div", "slot");
                slot.appendChild(el("div", "coil"));
                var stock = el("div", "stock");
                slot.appendChild(stock);
                var code = el("div", "code");
                if (s) {
                    var prod = products[Number(s.product) - 1] || {};
                    stock.appendChild(makeUnit(prod, 2));
                    stock.appendChild(makeUnit(prod, 1));
                    stock.appendChild(makeUnit(prod, 0));
                    code.textContent = String(s.code);
                    code.appendChild(el("b", "", money(prod.price)));
                    if (!prod.canCarry) slot.classList.add("full");
                    M.codes[s.code] = { product: Number(s.product), slot: slot, stock: stock };
                } else {
                    slot.classList.add("empty");
                    code.textContent = "--";
                }
                slot.appendChild(code);
                shelf.appendChild(slot);
            }
            shelves.appendChild(shelf);
        }

        // Teclado
        var keys = $("v-keys");
        keys.textContent = "";
        KEYPAD.forEach(function (k) {
            var b = el("button", k === "C" ? "c" : k === "OK" ? "ok" : "", k);
            b.type = "button";
            b.setAttribute("data-k", k);
            b.addEventListener("click", function () { press(k); });
            keys.appendChild(b);
        });

        $("v-tray").classList.remove("ready");
        $("v-tray-item").textContent = "";
        $("v-fly").textContent = "";
        $("v-arrow").classList.remove("on");
        $("v-wallet").textContent = "Llevas " + money(d.cash) + " en efectivo" +
            (Number(d.cards) > 0 ? " y " + d.cards + (Number(d.cards) === 1 ? " tarjeta." : " tarjetas.") : ". No llevas tarjeta.");
        hint("Marca en el teclado el código del producto · <Esc> salir");
        resetInput();
        show("machine");
        fit();
    }

    function hint(text, ready) {
        var h = $("v-hint");
        h.textContent = "";
        // "<Esc>" se muestra como tecla; el resto como texto
        text.split(/(<[^>]+>)/).forEach(function (part) {
            if (/^<[^>]+>$/.test(part)) h.appendChild(el("kbd", "", part.slice(1, -1)));
            else if (part) h.appendChild(document.createTextNode(part));
        });
        h.classList.toggle("ready", !!ready);
    }

    function lcd(text, info, kind) {
        var box = $("v-lcd").parentNode;
        $("v-lcd").textContent = text;
        $("v-info").textContent = info || "";
        box.classList.remove("err", "blink");
        if (kind) { void box.offsetWidth; box.classList.add(kind); if (kind === "err") box.classList.add("blink"); }
    }

    function leds(green, red) {
        $("v-led-g").classList.toggle("on", !!green);
        $("v-led-r").classList.toggle("on", !!red);
    }

    function resetInput() {
        if (!M) return;
        clearTimeout(M.timer);
        M.input = "";
        M.phase = "select";
        if (M.picked && M.codes[M.picked]) M.codes[M.picked].slot.classList.remove("picked");
        M.picked = null;
        lcd("00", "MARQUE CÓDIGO");
        leds(false, false);
    }

    function flashKey(k) {
        var b = $("v-keys").querySelector('[data-k="' + k + '"]');
        if (!b) return;
        b.classList.add("press");
        later(function () { b.classList.remove("press"); }, 120);
    }

    function press(k) {
        if (!M || M.phase !== "select") return;
        flashKey(k);
        sound("beep");
        if (k === "C") return resetInput();
        if (k === "OK") return M.input.length === 2 ? check() : error("ERR", "MARQUE 2 DÍGITOS");
        if (M.input.length >= 2) M.input = "";
        M.input += k;
        lcd((M.input + "_").slice(0, 2), "CÓDIGO " + M.input);
        if (M.input.length === 2) later(check, 250);
    }

    function error(text, info) {
        sound("error");
        lcd(text, info, "err");
        leds(false, true);
        M.phase = "error";
        M.timer = later(resetInput, 1300);
    }

    function check() {
        if (!M || M.phase !== "select" || M.input.length !== 2) return;
        var code = Number(M.input), entry = M.codes[code];
        if (!entry) return error("ERR", "CÓDIGO NO VÁLIDO");
        var prod = M.products[entry.product - 1];
        if (!prod || !prod.canCarry) return error("NO", (prod && prod.reason) || "NO TE CABE EN EL INVENTARIO");
        M.picked = code;
        entry.slot.classList.add("picked");
        lcd(money(prod.price), String(prod.name).toUpperCase());
        leds(true, false);
        M.phase = "wait";
        later(function () {
            if (!M || M.phase !== "wait") return;
            send("rp:vending:ui:choose", code);
            // Si el servidor no abre el datafono (lo rechazó), se vuelve a marcar
            M.timer = later(function () { if (M && M.phase === "wait") error("ERR", "NO DISPONIBLE"); }, 3000);
        }, 700);
    }

    $("v-close").addEventListener("click", function () { escape(); });

    // Escala la maquina para que entre en pantallas bajas (zoom mantiene la geometria interna)
    function fit() {
        var f = document.querySelector(".vm-frame");
        f.style.zoom = 1;
        var s = Math.min(1, (window.innerHeight - 80) / f.offsetHeight, (window.innerWidth - 40) / f.offsetWidth);
        f.style.zoom = s;
    }
    window.addEventListener("resize", function () { if (view === "machine" || view === "pay") fit(); });

    // ------------------------------------------------ caida del producto
    // Posicion de un elemento dentro del marco (sin transformaciones ni zoom)
    function offsetIn(node, frame) {
        var x = 0, y = 0;
        while (node && node !== frame) { x += node.offsetLeft; y += node.offsetTop; node = node.offsetParent; }
        return { x: x, y: y };
    }

    function dispense() {
        var entry = M && M.codes[M.picked];
        if (!entry) return trayReady(null);
        M.phase = "dispense";
        lcd("OK", "RETIRANDO...");
        leds(true, false);
        var frame = document.querySelector(".vm-frame");
        var front = entry.stock.querySelector(".unit.d0");
        var prod = M.products[entry.product - 1];
        if (!front) return trayReady(prod);

        // Clon que vuela; el original sale de la espiral y los de atras avanzan
        var st = offsetIn(entry.stock, frame);
        var fly = makeUnit(prod, 0);
        fly.className = "unit";
        $("v-fly").appendChild(fly);
        var uw = fly.offsetWidth, uh = fly.offsetHeight;
        var x0 = st.x + (entry.stock.offsetWidth - uw) / 2, y0 = st.y + entry.stock.offsetHeight - uh;
        fly.style.left = x0 + "px";
        fly.style.top = y0 + "px";
        front.remove();
        var d1 = entry.stock.querySelector(".unit.d1"), d2 = entry.stock.querySelector(".unit.d2");
        if (d1) d1.className = "unit d0";
        if (d2) d2.className = "unit d1";
        entry.stock.insertBefore(makeUnit(prod, 2), entry.stock.firstChild);

        var tray = $("v-tray"), tp = offsetIn(tray, frame);
        var x1 = tp.x + tray.offsetWidth / 2 - uw / 2, y1 = tp.y + tray.offsetHeight - uh - 4;
        var coil = entry.slot.querySelector(".coil");
        coil.animate([{ transform: "rotate(0deg)" }, { transform: "rotate(360deg)" }], { duration: 900, easing: "ease-in-out" });

        // Los pasos se encadenan con timers (no con onfinish): aunque la animacion no se dibuje
        // (ventana sin foco, CEF ocupado), el producto siempre llega a la bandeja.
        // 1) la espiral empuja el producto hacia el vidrio
        fly.animate([
            { transform: "translate(0, 0) scale(1)" },
            { transform: "translate(0, -2px) scale(1.15)" },
        ], { duration: 900, easing: "ease-in-out", fill: "forwards" });
        later(function () {
            // 2) cae girando hasta la bandeja (aceleracion como la gravedad) y rebota
            var dx = x1 - x0, dy = y1 - y0;
            fly.animate([
                { transform: "translate(0, -2px) scale(1.15) rotate(0deg)", offset: 0 },
                { transform: "translate(" + dx * 0.6 + "px, " + dy * 0.55 + "px) scale(1.15) rotate(-35deg)", offset: 0.55 },
                { transform: "translate(" + dx + "px, " + dy + "px) scale(1.2) rotate(-80deg)", offset: 0.85 },
                { transform: "translate(" + dx + "px, " + (dy - 10) + "px) scale(1.2) rotate(-74deg)", offset: 0.93 },
                { transform: "translate(" + dx + "px, " + dy + "px) scale(1.2) rotate(-80deg)", offset: 1 },
            ], { duration: 820, easing: "cubic-bezier(0.55, 0, 1, 0.45)", fill: "forwards" });
            later(function () {
                fly.remove();
                trayReady(prod);
            }, 840);
        }, 900);
    }

    function trayReady(prod) {
        if (!M) return;
        M.phase = "ready";
        sound("ok");
        var item = $("v-tray-item");
        item.textContent = "";
        if (prod) {
            var u = makeUnit(prod, 0);
            u.className = "unit";
            u.style.position = "relative";
            u.style.transform = "scale(1.2)";
            item.appendChild(u);
        }
        $("v-tray").classList.add("ready");
        $("v-arrow").classList.add("on");
        lcd("OK", "RETIRE SU PRODUCTO");
        hint("¡Listo! Haz clic en la bandeja para sacar tu producto", true);
    }

    function take() {
        if (!M || M.phase !== "ready") return;
        M.phase = "taken";
        sound("beep");
        var item = $("v-tray-item").firstChild;
        if (item) item.animate([
            { transform: "translateY(0) scale(1.2)", opacity: 1 },
            { transform: "translateY(-60px) scale(1.5)", opacity: 0 },
        ], { duration: 350, easing: "ease-in", fill: "forwards" });
        later(function () { send("rp:vending:ui:cancel"); }, 360);
    }

    $("v-tray").addEventListener("click", take);

    function escape() {
        if (!M) return;
        if (M.phase === "ready") return take();
        if (M.phase === "select" || M.phase === "error") send("rp:vending:ui:cancel");
    }

    // =============================================================== Datafono
    var P = null;
    var KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "X", "0", "<", "OK"];

    function pos(d) {
        if (M) { clearTimeout(M.timer); M.phase = "pay"; }
        P = { d: d, state: "swipe", owner: null, last4: "", pin: "" };
        $("p-station").textContent = String(d.product || d.station || "EXPENDEDORA").toUpperCase();
        $("p-amount").textContent = money(d.amount);
        $("p-paper").className = "paper";
        $("p-paper").textContent = "";
        var cards = list(d.cards);
        var box = $("p-cards");
        box.textContent = "";
        cards.forEach(function (c) {
            var card = el("div", "card");
            card.setAttribute("data-owner", c.owner);
            card.setAttribute("data-last4", c.last4);
            card.appendChild(el("div", "stripe"));
            card.appendChild(el("div", "bank", "BANCO DE SAN ANDREAS"));
            card.appendChild(el("div", "chip"));
            card.appendChild(el("div", "num", "•••• •••• •••• " + c.last4));
            card.appendChild(el("div", "holder", c.holder));
            box.appendChild(card);
            bindCard(card);
        });
        if (!cards.length) box.appendChild(el("div", "empty", "No llevas ninguna tarjeta."));
        $("p-hint").textContent = cards.length
            ? "Arrastra tu tarjeta a la ranura del datafono y deslízala hacia la derecha. Luego escribe tu clave (la ves en tu inventario) y pulsa OK."
            : "Sin tarjeta solo puedes pagar en efectivo.";
        $("p-cash").textContent = "Pagar en efectivo (" + money(d.amount) + ")";
        $("p-cash").disabled = Number(d.cash) < Number(d.amount);
        $("p-back").disabled = false;
        var keys = $("p-keys");
        keys.textContent = "";
        KEYS.forEach(function (k) {
            var b = el("button", k === "X" ? "red" : k === "<" ? "yellow" : k === "OK" ? "green" : "",
                k === "X" ? "ANULAR" : k === "<" ? "BORRAR" : k);
            b.type = "button";
            if (k === "OK") b.style.gridColumn = "span 3";
            b.addEventListener("click", function () { key(k); });
            keys.appendChild(b);
        });
        lcd("PAY", "PAGUE EN EL DATAFONO");
        status(cards.length ? "DESLICE LA TARJETA" : "PAGO EN EFECTIVO");
        $("machine").classList.add("dim");
        show("pay");
    }

    function status(text, kind) {
        $("p-status").textContent = text;
        var screen = $("p-status").parentNode;
        screen.classList.remove("error", "ok");
        if (kind) screen.classList.add(kind);
        $("p-pin").textContent = P && P.state === "pin" ? (P.pin.replace(/./g, "*") + "____".slice(P.pin.length)) : "";
    }

    function errorFlash(text, back) {
        sound("error");
        status(text, "error");
        var box = $("pos");
        box.classList.remove("shake"); void box.offsetWidth; box.classList.add("shake");
        later(function () { if (P && P.state !== "done") back(); }, 1500);
    }

    function key(k) {
        if (!P || P.state === "busy" || P.state === "done") return;
        sound("beep");
        if (P.state !== "pin") {
            if (k !== "X") errorFlash("DESLICE PRIMERO", function () { status("DESLICE LA TARJETA"); });
            return;
        }
        if (k === "X") { P.state = "swipe"; P.pin = ""; return status("DESLICE LA TARJETA"); }
        if (k === "<") { P.pin = P.pin.slice(0, -1); return status("INGRESE CLAVE"); }
        if (k === "OK") {
            if (P.pin.length !== 4) return errorFlash("CLAVE DE 4 DIGITOS", function () { status("INGRESE CLAVE"); });
            P.state = "busy";
            status("PROCESANDO...");
            $("p-pin").textContent = "";
            send("rp:vending:ui:pay", "card", String(P.owner), P.pin);
            return;
        }
        if (P.pin.length < 4) P.pin += k;
        status("INGRESE CLAVE");
    }

    // --- Arrastrar y deslizar la tarjeta ---
    var drag = null;

    function grooveRect() { return $("p-groove").getBoundingClientRect(); }

    function bindCard(card) {
        card.addEventListener("mousedown", function (e) {
            if (!P || (P.state !== "swipe" && P.state !== "pin") || e.button !== 0) return;
            var r = card.getBoundingClientRect();
            drag = { card: card, dx: e.clientX - r.left, dy: e.clientY - r.top, inGroove: false, startTime: 0 };
            card.classList.remove("back");
            card.classList.add("dragging");
            place(card, r.left, r.top);
            e.preventDefault();
        });
    }

    function place(card, x, y) { card.style.left = x + "px"; card.style.top = y + "px"; }

    // En la ranura la tarjeta va de lado (banda negra arriba) y se mueve solo en X
    function grooveTrack() {
        var g = grooveRect(), w = 290 * 0.72;
        return { y: g.top - 10, from: g.left - w * 0.55, to: g.right - w * 0.45 };
    }

    document.addEventListener("mousemove", function (e) {
        if (!drag) return;
        var card = drag.card;
        if (!drag.inGroove) {
            place(card, e.clientX - drag.dx, e.clientY - drag.dy);
            var g = grooveRect();
            var nearGroove = e.clientX > g.left - 160 && e.clientX < g.right && e.clientY > g.top - 60 && e.clientY < g.bottom + 60;
            $("p-groove").classList.toggle("target", nearGroove);
            if (nearGroove) {
                drag.inGroove = true;
                card.classList.add("flipped");
                card.style.transformOrigin = "top left";
                card.style.transform = "scale(0.72)";
                var t = grooveTrack();
                drag.offset = e.clientX - t.from;
                place(card, t.from, t.y);
            }
            return;
        }
        var tr = grooveTrack();
        var cx = Math.max(tr.from, Math.min(tr.to, e.clientX - drag.offset));
        place(card, cx, tr.y);
        var p = (cx - tr.from) / (tr.to - tr.from);
        if (p > 0.05 && !drag.startTime) drag.startTime = performance.now();
        if (p < 0.02) drag.startTime = 0;
        if (p >= 0.999) finishSwipe();
    });

    document.addEventListener("mouseup", function () {
        if (!drag) return;
        if (drag.inGroove) {
            // Soltaste antes de terminar: vuelve al inicio de la ranura
            var tr = grooveTrack();
            drag.card.classList.add("back");
            place(drag.card, tr.from, tr.y);
            var c = drag.card;
            drag = null;
            later(function () { resetCard(c); }, 260);
            if (P && P.state === "swipe") errorFlash("DESLICE HASTA EL FINAL", function () { status("DESLICE LA TARJETA"); });
            return;
        }
        resetCard(drag.card);
        drag = null;
        $("p-groove").classList.remove("target");
    });

    function resetCard(card) {
        card.classList.remove("dragging", "flipped", "back");
        card.style.left = card.style.top = card.style.transform = "";
        $("p-groove").classList.remove("target");
    }

    function finishSwipe() {
        var d = drag, ms = d.startTime ? performance.now() - d.startTime : 0;
        drag = null;
        resetCard(d.card);
        if (ms < 140) return errorFlash("MUY RAPIDO, REPITA", function () { status("DESLICE LA TARJETA"); });
        if (ms > 1800) return errorFlash("MUY LENTO, REPITA", function () { status("DESLICE LA TARJETA"); });
        sound("swipe");
        P.state = "pin";
        P.owner = d.card.getAttribute("data-owner");
        P.last4 = d.card.getAttribute("data-last4");
        P.pin = "";
        status("INGRESE CLAVE");
    }

    $("p-cash").addEventListener("click", function () {
        if (!P || P.state === "busy" || P.state === "done" || this.disabled) return;
        P.state = "busy";
        status("PAGO EN EFECTIVO...");
        send("rp:vending:ui:pay", "cash", "0", "");
    });

    // Volver a la maquina sin pagar
    function back() {
        if (!P || P.state === "busy" || P.state === "done") return;
        P = null;
        drag = null;
        send("rp:vending:ui:back");
        $("machine").classList.remove("dim");
        show("machine");
        resetInput();
    }
    $("p-back").addEventListener("click", back);

    function pad(s, n) { s = String(s); while (s.length < n) s += " "; return s; }
    function lpad(s, n) { s = String(s); while (s.length < n) s = " " + s; return s; }

    function receipt(cash) {
        var d = P.d, now = new Date();
        var date = ("0" + now.getDate()).slice(-2) + "/" + ("0" + (now.getMonth() + 1)).slice(-2) + "/" + now.getFullYear() + " " +
            ("0" + now.getHours()).slice(-2) + ":" + ("0" + now.getMinutes()).slice(-2);
        var lines = [
            String(d.station || "EXPENDEDORA").toUpperCase(),
            date,
            "------------------------",
            pad(String(d.product || "").toUpperCase().slice(0, 15), 15) + lpad(money(d.amount), 9),
            "------------------------",
            pad("TOTAL", 15) + lpad(money(d.amount), 9),
            cash ? "EFECTIVO" : "TARJETA **** " + P.last4,
            "       APROBADO",
            " ¡Retire su producto!",
        ];
        $("p-paper").textContent = lines.join("\n");
        $("p-paper").className = "paper out";
    }

    function result(ok, text, cash) {
        if (!P) return;
        if (ok) {
            P.state = "done";
            status(cash ? "PAGADO" : "APROBADO", "ok");
            $("p-keys").querySelectorAll("button").forEach(function (b) { b.disabled = true; });
            $("p-cash").disabled = true;
            $("p-back").disabled = true;
            receipt(cash);
            // Se ve salir la boleta y luego la maquina entrega el producto
            later(function () {
                if (!M) return;
                P = null;
                $("machine").classList.remove("dim");
                show("machine");
                dispense();
            }, 1900);
            return;
        }
        if (cash) return errorFlash(text, function () { P.state = "swipe"; status("DESLICE LA TARJETA"); });
        if (text === "CLAVE INCORRECTA") {
            P.state = "pin"; P.pin = "";
            return errorFlash(text, function () { status("INGRESE CLAVE"); });
        }
        P.state = "swipe";
        errorFlash(text, function () { status("DESLICE LA TARJETA"); });
    }

    // =============================================================== Vistas y teclado
    function show(which) {
        view = which;
        // El datafono se muestra encima de la maquina
        $("machine").classList.toggle("hidden", which !== "machine" && which !== "pay");
        $("pay").classList.toggle("hidden", which !== "pay");
    }

    document.addEventListener("keydown", function (e) {
        if (view === "machine" && M) {
            if (e.key === "Escape") { e.preventDefault(); escape(); }
            else if (/^[0-9]$/.test(e.key)) press(e.key);
            else if (e.key === "Backspace" || e.key === "Delete") { e.preventDefault(); press("C"); }
            else if (e.key === "Enter") { e.preventDefault(); if (M.phase === "ready") take(); else press("OK"); }
        } else if (view === "pay" && P) {
            if (e.key === "Escape") { e.preventDefault(); back(); }
            else if (/^[0-9]$/.test(e.key)) key(e.key);
            else if (e.key === "Backspace") { e.preventDefault(); key("<"); }
            else if (e.key === "Enter") { e.preventDefault(); key("OK"); }
        }
    });

    window.RPV = {
        menu: menu,
        pos: pos,
        result: result,
        hide: function () {
            if (M) clearTimeout(M.timer);
            show(null); M = null; P = null; drag = null;
        },
    };

    // Vista previa en un navegador normal (fuera de MTA): abre una maquina de ejemplo
    if (!window.mta) {
        menu({
            brand: "Sprunk", kind: "drink", columns: 3, cash: 120, cards: 1,
            products: [
                { index: 1, name: "Lata de Sprunk", price: 3, look: "can", color: "#2f9e44", tag: "SPRUNK", canCarry: true },
                { index: 2, name: "Lata de eCola", price: 3, look: "can", color: "#c92a2a", tag: "eCOLA", canCarry: true },
                { index: 3, name: "Botella de agua", price: 4, look: "bottle", color: "#4dabf7", tag: "AGUA", canCarry: true },
                { index: 4, name: "Bebida energetica", price: 6, look: "can", color: "#1c1c1c", tag: "VOLT", canCarry: false, reason: "Inventario lleno" },
            ],
            slots: [11, 12, 13, 21, 22, 23, 31, 32, 33, 41, 42, 43].map(function (c, i) { return { code: c, product: Math.floor(i / 3) + 1 }; }),
        });
        // vending.html#pay muestra el datafono; #drop simula la caida de la espiral 22 a la bandeja;
        // #food muestra la maquina de snacks
        if (location.hash === "#food") {
            menu({
                brand: "Snacks", kind: "food", columns: 3, cash: 40, cards: 0,
                products: [
                    { index: 1, name: "Papas fritas", price: 4, look: "bag", color: "#f08c00", tag: "PAPAS", canCarry: true },
                    { index: 2, name: "Barra de chocolate", price: 4, look: "bar", color: "#6f3b1d", tag: "CHOCO", canCarry: true },
                    { index: 3, name: "Galletas", price: 5, look: "bag", color: "#c2a26b", tag: "GALLETAS", canCarry: true },
                ],
                slots: [11, 12, 13, 21, 22, 23, 31, 32, 33, 41, 42, 43].map(function (c, i) { return { code: c, product: Math.floor(i / 4) + 1 }; }),
            });
        } else if (location.hash === "#pay") {
            pos({ station: "Expendedora Sprunk", product: "Lata de Sprunk", amount: 3, cash: 120, cards: [{ owner: 1, last4: "4821", holder: "Carl Johnson" }] });
        } else if (location.hash === "#drop") {
            M.picked = 22;
            dispense();
        }
    }
})();
