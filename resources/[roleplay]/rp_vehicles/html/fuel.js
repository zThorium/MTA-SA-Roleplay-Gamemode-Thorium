/*
 * rp_vehicles / fuel.js
 * Bencinera: dialogo de litros y datafono. Lua llama a RPF.dialog(datos),
 * RPF.pos(datos), RPF.result(ok, texto, efectivo) y RPF.hide().
 * Eventos hacia Lua: rp:fuel:ui:order (litros | "full"), rp:fuel:ui:cancel,
 * rp:fuel:ui:pay ("card" | "cash", dueno, clave), rp:fuel:ui:sound (nombre).
 */
(function () {
    "use strict";

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
    }
    var $ = function (id) { return document.getElementById(id); };
    function esc(s) {
        return String(s === null || s === undefined ? "" : s).replace(/[&<>"']/g, function (c) {
            return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
        });
    }
    function money(n) { return "$" + Math.round(Number(n) || 0).toLocaleString("es-AR"); }
    function list(x) { return Array.isArray(x) ? x : (x && typeof x === "object" ? Object.keys(x).map(function (k) { return x[k]; }) : []); }
    function sound(name) { send("rp:fuel:ui:sound", name); }

    var view = null;

    // ------------------------------------------------------------
    // Dialogo: cuantos litros
    // ------------------------------------------------------------
    var D = null;

    function dialog(d) {
        var room = Math.max(1, Math.floor(Number(d.capacity) - Number(d.fuel)));
        D = { d: d, room: room, liters: room, full: true };
        $("d-station").textContent = d.station || "Bencinera";
        $("d-vehicle").textContent = d.vehicle || "";
        $("d-current").textContent = "Actual " + Number(d.fuel).toFixed(1) + " L";
        $("d-cap").textContent = "Tanque " + d.capacity + " L";
        $("d-range").max = room;
        var html = "";
        [5, 10, 20, 30].forEach(function (n) {
            html += '<button type="button" data-l="' + n + '"' + (n > room ? " disabled" : "") + ">" + n + " L<small>" + money(n * d.price) + "</small></button>";
        });
        html += '<button type="button" data-l="full">Lleno<small>' + room + " L</small></button>";
        $("d-presets").innerHTML = html;
        $("d-presets").querySelectorAll("button").forEach(function (b) {
            b.addEventListener("click", function () {
                var l = b.getAttribute("data-l");
                if (l === "full") set(room, true); else set(Number(l), false);
            });
        });
        set(room, true);
        show("dialog");
    }

    function set(liters, full) {
        D.liters = Math.max(1, Math.min(D.room, liters));
        D.full = full || D.liters >= D.room;
        var d = D.d, total = Math.ceil(D.liters * d.price);
        $("d-range").value = D.liters;
        $("d-liters").textContent = D.liters + " L";
        $("d-now").style.width = (100 * d.fuel / d.capacity) + "%";
        $("d-add").style.width = (100 * D.liters / d.capacity) + "%";
        $("d-calc").textContent = (D.full ? "Lleno · " : "") + D.liters + " L × " + money(d.price);
        $("d-total").textContent = money(total);
        $("d-presets").querySelectorAll("button").forEach(function (b) {
            var l = b.getAttribute("data-l");
            b.classList.toggle("selected", l === "full" ? D.full : (!D.full && Number(l) === D.liters));
        });
        var canPay = d.cards > 0 || d.cash >= total;
        $("d-pay").textContent = d.cards > 0
            ? "Pagas al final con tu tarjeta (clave) o en efectivo. Llevas " + money(d.cash) + " en efectivo."
            : (canPay ? "No llevas tarjeta: pagas en efectivo (llevas " + money(d.cash) + ")."
                      : "No llevas tarjeta y no te alcanza el efectivo (" + money(d.cash) + "). Elige menos litros.");
        $("d-ok").disabled = !canPay;
    }

    $("d-range").addEventListener("input", function () { set(Number(this.value), false); });
    $("d-ok").addEventListener("click", function () {
        if (!D || this.disabled) return;
        this.disabled = true;
        send("rp:fuel:ui:order", D.full ? "full" : String(D.liters));
    });
    $("d-cancel").addEventListener("click", function () { send("rp:fuel:ui:cancel"); });

    // ------------------------------------------------------------
    // Datafono
    // ------------------------------------------------------------
    var P = null;
    var KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "X", "0", "<", "OK"];

    function pos(d) {
        P = { d: d, state: "swipe", owner: null, last4: "", pin: "" };
        $("p-station").textContent = String(d.station || "BENCINERA").toUpperCase() + " · " + Number(d.liters).toFixed(1) + " L";
        $("p-amount").textContent = money(d.amount);
        $("p-paper").className = "paper";
        $("p-paper").textContent = "";
        var cards = list(d.cards);
        var html = "";
        cards.forEach(function (c) {
            html += '<div class="card" data-owner="' + c.owner + '" data-last4="' + esc(c.last4) + '">' +
                '<div class="stripe"></div><div class="bank">BANCO DE SAN ANDREAS</div><div class="chip"></div>' +
                '<div class="num">•••• •••• •••• ' + esc(c.last4) + '</div><div class="holder">' + esc(c.holder) + "</div></div>";
        });
        $("p-cards").innerHTML = html || '<div class="empty">No llevas ninguna tarjeta.</div>';
        $("p-hint").textContent = cards.length
            ? "Arrastra tu tarjeta a la ranura del datafono y deslízala hacia la derecha. Luego escribe tu clave (la ves en tu inventario) y pulsa OK."
            : "Sin tarjeta solo puedes pagar en efectivo.";
        $("p-cash").textContent = "Pagar en efectivo (" + money(d.amount) + ")";
        $("p-cash").disabled = Number(d.cash) < Number(d.amount);
        $("p-cards").querySelectorAll(".card").forEach(bindCard);
        var keys = "";
        KEYS.forEach(function (k) {
            var cls = k === "X" ? "red" : k === "<" ? "yellow" : k === "OK" ? "green" : "";
            keys += '<button type="button" class="' + cls + '" data-k="' + k + '"' + (k === "OK" ? ' style="grid-column: span 3"' : "") + ">" +
                (k === "X" ? "ANULAR" : k === "<" ? "BORRAR" : k) + "</button>";
        });
        $("p-keys").innerHTML = keys;
        $("p-keys").querySelectorAll("button").forEach(function (b) {
            b.addEventListener("click", function () { key(b.getAttribute("data-k")); });
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
        var pos = $("pos");
        pos.classList.remove("shake"); void pos.offsetWidth; pos.classList.add("shake");
        setTimeout(function () { if (P && P.state !== "done") { back(); } }, 1500);
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
            send("rp:fuel:ui:pay", "card", String(P.owner), P.pin);
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
            drag = { card: card, dx: e.clientX - r.left, dy: e.clientY - r.top, inGroove: false, startTime: 0, progress: 0 };
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
            var x = e.clientX - drag.dx, y = e.clientY - drag.dy;
            place(card, x, y);
            var g = grooveRect();
            var near = e.clientX > g.left - 160 && e.clientX < g.right && e.clientY > g.top - 60 && e.clientY < g.bottom + 60;
            $("p-groove").classList.toggle("target", near);
            if (near) {
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
        P.cash = true;
        status("PAGO EN EFECTIVO...");
        send("rp:fuel:ui:pay", "cash", "0", "");
    });

    function pad(s, n) { s = String(s); while (s.length < n) s += " "; return s; }
    function lpad(s, n) { s = String(s); while (s.length < n) s = " " + s; return s; }

    function receipt(cash) {
        var d = P.d, now = new Date();
        var date = ("0" + now.getDate()).slice(-2) + "/" + ("0" + (now.getMonth() + 1)).slice(-2) + "/" + now.getFullYear() + " " +
            ("0" + now.getHours()).slice(-2) + ":" + ("0" + now.getMinutes()).slice(-2);
        var lines = [
            String(d.station || "BENCINERA").toUpperCase(),
            date,
            "------------------------",
            pad("BENCINA", 14) + lpad(Number(d.liters).toFixed(1) + " L", 10),
            "------------------------",
            pad("TOTAL", 14) + lpad(money(d.amount), 10),
            cash ? "EFECTIVO" : "TARJETA **** " + P.last4,
            "       APROBADO",
            "  ¡Gracias, buen viaje!",
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
            receipt(cash);
            return;
        }
        if (cash) {
            return errorFlash(text, function () { P.state = "swipe"; status("DESLICE LA TARJETA"); });
        }
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
        $("dialog").classList.toggle("hidden", which !== "dialog");
        $("pay").classList.toggle("hidden", which !== "pay");
        if (which === "dialog") $("d-ok").focus();
    }

    document.addEventListener("keydown", function (e) {
        if (view === "dialog") {
            if (e.key === "Escape") { e.preventDefault(); send("rp:fuel:ui:cancel"); }
            if (e.key === "Enter") { e.preventDefault(); $("d-ok").click(); }
        } else if (view === "pay" && P) {
            if (/^[0-9]$/.test(e.key)) key(e.key);
            else if (e.key === "Backspace") { e.preventDefault(); key("<"); }
            else if (e.key === "Enter") { e.preventDefault(); key("OK"); }
        }
    });

    window.RPF = {
        dialog: dialog,
        pos: pos,
        result: result,
        hide: function () { show(null); D = null; P = null; drag = null; },
    };
})();
