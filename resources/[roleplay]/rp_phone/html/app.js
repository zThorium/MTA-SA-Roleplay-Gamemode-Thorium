/*
 * rp_phone / app.js
 * Lua -> RP.boot / setNotes / setContacts / setNearby / setBank (Fotogram: RP.social y RP.camera en social.js)
 * JS  -> mta.triggerEvent("rp:phone:ui:*", ...)
 */
(function () {
    "use strict";

    var $ = function (id) { return document.getElementById(id); };
    var state = { notes: [], contacts: [], editing: null, bankMode: "deposit" };
    var DAYS = ["domingo", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado"];
    var MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined) node.textContent = text;
        return node;
    }

    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }

    function show(name) {
        document.querySelectorAll(".view").forEach(function (v) { v.classList.toggle("active", v.id === "view-" + name); });
        document.querySelector(".screen").classList.toggle("dark-status", name === "home");
        if (name === "bank") send("rp:phone:ui:bankOpen");
        if (window.Fotogram) Fotogram.onShow(name);
        if (name === "contact-add") send("rp:phone:ui:nearby");
    }

    function emptyItem(list, text) {
        var li = el("li", "empty", text);
        list.appendChild(li);
    }

    // ---------------------------------------------------------------- Reloj
    function tick() {
        var d = new Date();
        var hh = String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
        $("clock").textContent = hh;
        $("widget-time").textContent = hh;
        $("widget-date").textContent = DAYS[d.getDay()] + ", " + d.getDate() + " de " + MONTHS[d.getMonth()];
    }
    tick();
    setInterval(tick, 10000);

    // ---------------------------------------------------------------- Navegacion
    document.querySelectorAll("[data-open]").forEach(function (b) {
        b.addEventListener("click", function () { show(b.dataset.open); });
    });
    document.querySelectorAll(".back").forEach(function (b) {
        b.addEventListener("click", function () { show(b.dataset.to || "home"); });
    });
    $("home-bar").addEventListener("click", function () { show("home"); });
    // Apps de otros recursos (se abren en su propia interfaz)
    document.querySelectorAll("[data-app]").forEach(function (b) {
        b.addEventListener("click", function () { send("rp:phone:ui:openApp", b.dataset.app); });
    });
    document.addEventListener("keydown", function (e) {
        if (document.body.classList.contains("camera-mode")) return;   // la camara usa sus propias teclas (social.js)
        var tag = document.activeElement && document.activeElement.tagName;
        if (e.key === "Escape" || ((e.key === "p" || e.key === "P") && tag !== "INPUT" && tag !== "TEXTAREA")) {
            e.preventDefault();
            send("rp:phone:ui:close");
        }
    });

    // ---------------------------------------------------------------- Notas
    function renderNotes() {
        var list = $("notes-list");
        list.innerHTML = "";
        if (!state.notes.length) return emptyItem(list, "No tienes notas");
        state.notes.forEach(function (n) {
            var li = el("li");
            var text = el("div");
            text.appendChild(el("strong", null, n.title));
            text.appendChild(el("span", "sub", n.date + "  " + String(n.body || "").slice(0, 40)));
            li.appendChild(text);
            li.appendChild(el("span", "sub", "›"));
            li.addEventListener("click", function () { editNote(n); });
            list.appendChild(li);
        });
    }

    function editNote(note) {
        state.editing = note ? note.id : null;
        $("note-title").value = note ? note.title : "";
        $("note-body").value = note ? note.body : "";
        $("note-delete").hidden = !note;
        document.querySelector("#view-note h1").textContent = note ? note.title : "Nueva nota";
        show("note");
    }

    $("note-new").addEventListener("click", function () { editNote(null); });
    $("note-save").addEventListener("click", function () {
        var title = $("note-title").value.trim();
        if (!title) { $("note-title").focus(); return; }
        send("rp:phone:ui:noteSave", state.editing || 0, title, $("note-body").value);
        show("notes");
    });
    $("note-delete").addEventListener("click", function () {
        if (state.editing) send("rp:phone:ui:noteDelete", state.editing);
        show("notes");
    });

    // ---------------------------------------------------------------- Contactos
    function renderContacts() {
        var list = $("contacts-list");
        list.innerHTML = "";
        if (!state.contacts.length) return emptyItem(list, "Tu agenda esta vacia");
        state.contacts.forEach(function (c) {
            var li = el("li");
            var text = el("div");
            text.appendChild(el("strong", null, c.name));
            text.appendChild(el("span", "sub", String(c.number).replace(/^(\d{3})(\d{4})$/, "$1-$2")));
            var del = el("button", "del", "Eliminar");
            del.type = "button";
            del.addEventListener("click", function (e) { e.stopPropagation(); send("rp:phone:ui:contactDelete", c.id); });
            li.appendChild(text);
            li.appendChild(del);
            list.appendChild(li);
        });
    }

    $("contact-new").addEventListener("click", function () {
        $("contact-name").value = "";
        $("contact-number").value = "";
        show("contact-add");
    });
    $("contact-save").addEventListener("click", function () {
        var name = $("contact-name").value.trim();
        var number = parseInt($("contact-number").value, 10);
        if (!name || !(number >= 1000000 && number <= 9999999)) return;
        send("rp:phone:ui:contactAdd", name, number);
        show("contacts");
    });

    // ---------------------------------------------------------------- Banco
    document.querySelectorAll("[data-bank]").forEach(function (b) {
        b.addEventListener("click", function () {
            state.bankMode = b.dataset.bank;
            document.querySelectorAll("[data-bank]").forEach(function (x) { x.classList.toggle("active", x === b); });
            $("bank-target").hidden = state.bankMode !== "transfer";
            $("bank-go").textContent = state.bankMode === "transfer" ? "Transferir" : "Depositar";
        });
    });
    $("bank-go").addEventListener("click", function () {
        var amount = parseInt($("bank-amount").value, 10);
        if (!(amount > 0)) return;
        send("rp:phone:ui:bankAction", state.bankMode, amount, $("bank-target").value.trim());
        $("bank-amount").value = "";
    });

    // ---------------------------------------------------------------- API para Lua
    window.RP = {
        boot: function (info) {
            $("settings-owner").textContent = info.owner || "-";
            $("settings-number").textContent = String(info.number || "-").replace(/^(\d{3})(\d{4})$/, "$1-$2");
            show("home");
        },
        setNotes: function (rows) { state.notes = Array.isArray(rows) ? rows : []; renderNotes(); },
        setContacts: function (rows) { state.contacts = Array.isArray(rows) ? rows : []; renderContacts(); },
        setNearby: function (rows) {
            var list = $("nearby-list");
            list.innerHTML = "";
            if (!rows || !rows.length) return emptyItem(list, "No hay nadie cerca");
            rows.forEach(function (r) {
                var li = el("li");
                li.appendChild(el("span", null, r.name));
                var add = el("button", "del", "Agregar");
                add.style.color = "#0a7aff";
                add.type = "button";
                add.addEventListener("click", function () { send("rp:phone:ui:contactAddPlayer", r.index); show("contacts"); });
                li.appendChild(add);
                list.appendChild(li);
            });
        },
        setBank: function (d) {
            $("bank-holder").textContent = d.name || "";
            $("bank-balance").textContent = money(d.balance);
            $("bank-cash").textContent = money(d.cash);
            var list = $("bank-history");
            list.innerHTML = "";
            var rows = Array.isArray(d.history) ? d.history : [];
            if (!rows.length) return emptyItem(list, "Sin movimientos");
            var TYPES = { deposit: ["Deposito", 1], withdraw: ["Retiro", 0], transfer_in: ["De ", 1], transfer_out: ["A ", 0], purchase: ["Compra: ", 0], sale: ["Venta: ", 1], payday: ["Sueldo: ", 1] };
            rows.forEach(function (r) {
                var t = TYPES[r.type] || [r.type, 1];
                var li = el("li");
                var text = el("div");
                text.appendChild(el("span", null, t[0] + (r.other_name ? String(r.other_name).replace(/_/g, " ") : "")));
                text.appendChild(el("span", "sub", r.date));
                li.appendChild(text);
                li.appendChild(el("span", t[1] ? "in" : "out", (t[1] ? "+" : "-") + money(r.amount)));
                list.appendChild(li);
            });
        },
    };

    // Para social.js (Fotogram)
    window.Phone = { $: $, el: el, send: send, show: show };
})();
