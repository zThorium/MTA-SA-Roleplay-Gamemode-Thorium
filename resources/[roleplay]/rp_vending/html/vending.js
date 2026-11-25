/*
 * rp_vending / vending.js
 * Menu de la expendedora y datafono. El datafono es el mismo minijuego que la bencinera
 * (rp_vehicles/html/fuel.js): arrastrar la tarjeta a la ranura, deslizarla y teclear la clave.
 * Lua llama a RPV.menu(datos), RPV.pos(datos), RPV.result(ok, texto, efectivo) y RPV.hide().
 * Eventos hacia Lua: rp:vending:ui:choose (indice), rp:vending:ui:pay ("card"|"cash", dueno, clave),
 * rp:vending:ui:cancel, rp:vending:ui:sound (nombre).
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

    var view = null;

    // ------------------------------------------------------------
    // Menu de productos
    // ------------------------------------------------------------
    var M = null;

    function menu(d) {
        M = { d: d, busy: false };
        $("menu").classList.toggle("food", d.kind === "food");
        $("m-logo").textContent = d.kind === "food" ? "🍫" : "🥤";
        $("m-title").textContent = d.title || "Expendedora";
        var box = $("m-products");
        box.textContent = "";
        list(d.products).forEach(function (p, i) {
            var b = el("button", "product");
            b.type = "button";
            b.appendChild(el("span", "num", String(i + 1)));
            b.appendChild(el("span", "icon", p.icon || "🥤"));
            var info = el("span", "info");
            info.appendChild(el("div", "name", p.name));
            info.appendChild(el("div", "desc", p.canCarry ? p.description : (p.reason || "No te cabe en el inventario.")));
            b.appendChild(info);
            b.appendChild(el("span", "price", money(p.price)));
            b.disabled = !p.canCarry;
            b.addEventListener("click", function () { choose(p); });
            box.appendChild(b);
        });
        $("m-wallet").textContent = "Llevas " + money(d.cash) + " en efectivo" +
            (Number(d.cards) > 0 ? " y " + d.cards + (Number(d.cards) === 1 ? " tarjeta." : " tarjetas.") : ". No llevas tarjeta.");
        show("menu");
    }

    function choose(p) {
        if (!M || M.busy || !p.canCarry) return;
        M.busy = true;
        sound("beep");
        send("rp:vending:ui:choose", p.index);
        setTimeout(function () { if (M) M.busy = false; }, 1500);   // si el servidor rechaza, se puede reintentar
    }

    $("m-close").addEventListener("click", function () { send("rp:vending:ui:cancel"); });

    // ------------------------------------------------------------
    // Datafono
    // ------------------------------------------------------------
    var P = null;
    var KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "X", "0", "<", "OK"];

    function pos(d) {
        P = { d: d, state: "swipe", owner: null, last4: "", pin: "" };
        $("p-station").textContent = String(d.station || "EXPENDEDORA").toUpperCase();
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
        status(cards.length ? "DESLICE LA TARJETA" : "PAGO EN EFECTIVO");
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
        setTimeout(function () { if (P && P.state !== "done") back(); }, 1500);
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
            setTimeout(function () { resetCard(c); }, 260);
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

    function back() {
        if (!P || P.state === "busy" || P.state === "done") return;
        send("rp:vending:ui:cancel");
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

    // ------------------------------------------------------------
    function show(which) {
        view = which;
        $("menu").classList.toggle("hidden", which !== "menu");
        $("pay").classList.toggle("hidden", which !== "pay");
    }

    document.addEventListener("keydown", function (e) {
        if (view === "menu" && M) {
            if (e.key === "Escape") { e.preventDefault(); send("rp:vending:ui:cancel"); }
            else if (/^[1-9]$/.test(e.key)) {
                var p = list(M.d.products)[Number(e.key) - 1];
                if (p) choose(p);
            }
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
        hide: function () { show(null); M = null; P = null; drag = null; },
    };
})();
