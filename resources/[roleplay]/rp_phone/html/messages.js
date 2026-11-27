/*
 * rp_phone / messages.js  -  App Mensajes (SMS entre telefonos)
 * JS  -> mta.triggerEvent("rp:phone:ui:sms", accion, ...)   (client/c_messages.lua)
 * Lua -> RP.sms.on(evento, [args])  eventos: list, chat, message, read, badge, failed
 * Otras apps: Messages.open(numero, nombre) abre la conversacion (lo usa Contactos).
 */
(function () {
    "use strict";

    var $ = function (id) { return document.getElementById(id); };
    var S = { convos: [], contacts: [], names: {}, chat: null, badge: 0, refresh: null };

    function send() {
        var args = ["rp:phone:ui:sms"].concat(Array.prototype.slice.call(arguments));
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }
    function el(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text !== undefined && text !== null) n.textContent = text;
        return n;
    }
    function play(src) {
        try { var a = new Audio(src); a.volume = 0.45; var p = a.play(); if (p && p.catch) p.catch(function () {}); } catch (e) { /* sin audio */ }
    }
    function pretty(n) { return String(n).replace(/^(\d{3})(\d{4})$/, "$1-$2"); }
    function nameOf(number) { return S.names[number] || pretty(number); }
    function avatar(name, number) {
        var a = el("div", "sms-avatar");
        a.textContent = S.names[number] ? name.charAt(0).toUpperCase() : "#";
        return a;
    }
    function hhmm(d) { return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0"); }
    function shortTime(ts) {
        if (!ts) return "";
        var d = new Date(ts * 1000), now = new Date();
        var days = Math.floor((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000);
        if (days === 0) return hhmm(d);
        if (days === 1) return "Ayer";
        return d.getDate() + "/" + (d.getMonth() + 1);
    }
    function longTime(ts) {
        var t = shortTime(ts);
        return t.indexOf(":") > 0 ? "Hoy " + t : t + " " + hhmm(new Date(ts * 1000));
    }
    function isActive() { return $("view-messages").classList.contains("active"); }

    // ---------------------------------------------------------------- Lista
    function renderList() {
        var box = $("sms-list"), filter = $("sms-filter").value.trim().toLowerCase();
        box.innerHTML = "";
        var rows = S.convos.filter(function (c) {
            return !filter || nameOf(c.number).toLowerCase().indexOf(filter) >= 0 || c.number.indexOf(filter.replace(/\D/g, "") || "x") >= 0;
        });
        if (!S.convos.length) {
            var e = el("div", "sms-empty", "Aún no tienes mensajes. Escríbele a alguien de tu agenda o a cualquier número.");
            e.appendChild(el("br"));
            var b = el("button", null, "Nuevo mensaje");
            b.type = "button";
            b.addEventListener("click", openPicker);
            e.appendChild(b);
            return box.appendChild(e);
        }
        rows.forEach(function (c) {
            var row = el("div", "sms-row" + (c.unread ? " unread" : ""));
            row.appendChild(el("i", "dot"));
            row.appendChild(avatar(nameOf(c.number), c.number));
            var txt = el("div", "txt"), top = el("div", "top");
            top.appendChild(el("strong", null, nameOf(c.number)));
            top.appendChild(el("time", null, shortTime(c.ts)));
            txt.appendChild(top);
            txt.appendChild(el("small", null, (c.lastMine ? "Tú: " : "") + c.last));
            row.appendChild(txt);
            row.title = "Clic derecho para borrar la conversación";
            row.addEventListener("click", function () { open(c.number); });
            row.addEventListener("contextmenu", function (ev) {
                ev.preventDefault();
                if (row.dataset.confirm) { send("delete", c.number); return; }
                row.dataset.confirm = "1";
                txt.querySelector("small").textContent = "Clic derecho otra vez para borrar esta conversación";
                setTimeout(function () { renderList(); }, 2500);
            });
            box.appendChild(row);
        });
    }
    $("sms-filter").addEventListener("input", renderList);

    // ---------------------------------------------------------------- Nuevo mensaje
    function renderContacts() {
        var box = $("sms-contacts"), q = $("sms-to").value.trim().toLowerCase();
        box.innerHTML = "";
        var list = S.contacts.filter(function (c) { return !q || c.name.toLowerCase().indexOf(q) >= 0 || c.number.indexOf(q.replace(/\D/g, "") || "x") >= 0; });
        if (!list.length) box.appendChild(el("div", "sms-empty", S.contacts.length ? "Ningún contacto coincide. Escribe el número completo (7 dígitos) y pulsa Ir." : "Tu agenda está vacía. Escribe un número de 7 dígitos y pulsa Ir."));
        list.forEach(function (c) {
            var row = el("div", "sms-row");
            row.appendChild(avatar(c.name, c.number));
            var txt = el("div", "txt");
            txt.appendChild(el("strong", null, c.name));
            txt.appendChild(el("small", null, pretty(c.number)));
            row.appendChild(txt);
            row.addEventListener("click", function () { $("sms-pick").hidden = true; open(c.number); });
            box.appendChild(row);
        });
    }
    function openPicker() {
        $("sms-to").value = "";
        renderContacts();
        $("sms-pick").hidden = false;
        setTimeout(function () { $("sms-to").focus(); }, 150);
    }
    function goTyped() {
        var digits = $("sms-to").value.replace(/\D/g, "");
        if (digits.length !== 7) { $("sms-to").focus(); return; }
        $("sms-pick").hidden = true;
        open(digits);
    }
    $("sms-new").addEventListener("click", openPicker);
    $("sms-pick-cancel").addEventListener("click", function () { $("sms-pick").hidden = true; });
    $("sms-to").addEventListener("input", renderContacts);
    $("sms-to").addEventListener("keydown", function (e) { if (e.key === "Enter") goTyped(); });
    $("sms-to-go").addEventListener("click", goTyped);

    // ---------------------------------------------------------------- Conversacion
    function open(number, name) {
        number = String(number).replace(/\D/g, "");
        if (name) S.names[number] = S.names[number] || name;
        S.chat = { number: number, messages: [], loading: true };
        $("sms-chat-name").textContent = nameOf(number);
        $("sms-chat-number").textContent = S.names[number] ? pretty(number) : "";
        var av = avatar(nameOf(number), number);
        $("sms-chat-avatar").replaceWith(av);
        av.id = "sms-chat-avatar";
        $("sms-msgs").innerHTML = "";
        $("sms-input").value = "";
        $("sms-chat").hidden = false;
        send("open", number);
        setTimeout(function () { $("sms-input").focus(); }, 150);
    }
    function closeChat() {
        $("sms-chat").hidden = true;
        S.chat = null;
        send("list");
        send("badge");
    }
    $("sms-chat-back").addEventListener("click", closeChat);
    $("sms-chat-call").addEventListener("click", function () { if (S.chat && window.Phone.call) window.Phone.call(S.chat.number); });

    function renderChat() {
        var c = S.chat, box = $("sms-msgs");
        if (!c) return;
        box.innerHTML = "";
        if (!c.messages.length && !c.failed) box.appendChild(el("div", "sms-empty", "Escribe el primer mensaje a " + nameOf(c.number) + "."));
        var lastTs = 0, lastMine = -1;
        c.messages.forEach(function (m, i) { if (m.mine) lastMine = i; });
        c.messages.forEach(function (m, i) {
            if (m.ts && m.ts - lastTs > 3600) box.appendChild(el("div", "when", longTime(m.ts)));
            lastTs = m.ts || lastTs;
            box.appendChild(el("div", "sms-bubble " + (m.mine ? "mine" : "them"), m.body));
            if (i === lastMine && i === c.messages.length - 1) box.appendChild(el("div", "sms-status", m.read ? "Leído" : "Entregado"));
        });
        if (c.failed) {
            box.appendChild(el("div", "sms-bubble mine failed", c.failed));
            box.appendChild(el("div", "sms-status failed", "No entregado: el número no existe"));
        }
        box.scrollTop = box.scrollHeight;
    }
    $("sms-compose").addEventListener("submit", function (e) {
        e.preventDefault();
        var text = $("sms-input").value.trim();
        if (!text || !S.chat) return;
        S.chat.lastSent = text;
        send("send", S.chat.number, text);
        $("sms-input").value = "";
        play("sounds/tinder/click_002.ogg");
    });

    // ---------------------------------------------------------------- Aviso y globo
    var toastTimer = null;
    function toast(number, msg) {
        var t = document.querySelector(".sms-toast");
        if (!t) { t = el("div", "sms-toast"); document.querySelector(".screen").appendChild(t); }
        t.innerHTML = "";
        var name = S.names[number] || msg.name || pretty(number);
        t.appendChild(avatar(name, number));
        var tx = el("div");
        tx.appendChild(el("b", null, name));
        tx.appendChild(el("span", null, msg.body));
        t.appendChild(tx);
        t.hidden = false;
        t.onclick = function () { t.hidden = true; window.Phone.show("messages"); open(number, name); };
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { t.hidden = true; }, 4500);
    }
    function setBadge(n) {
        S.badge = Math.max(0, n || 0);
        var b = $("sms-badge");
        b.hidden = !S.badge;
        b.textContent = S.badge > 9 ? "9+" : String(S.badge);
    }

    // ---------------------------------------------------------------- Eventos de Lua
    var ON = {
        list: function (data) {
            data = data || {};
            S.convos = data.convos || [];
            S.contacts = data.contacts || [];
            S.names = {};
            S.contacts.forEach(function (c) { S.names[c.number] = c.name; });
            renderList();
            if (!$("sms-pick").hidden) renderContacts();
        },
        chat: function (data) {
            if (!data || !S.chat || S.chat.number !== data.number) return;
            S.chat.messages = data.messages || [];
            S.chat.failed = null;
            renderChat();
            send("badge");
        },
        message: function (number, msg) {
            if (!msg) return;
            if (S.chat && S.chat.number === number && !$("sms-chat").hidden && isActive()) {
                S.chat.messages.push(msg);
                S.chat.failed = null;
                if (!msg.mine) {
                    play("sounds/tinder/glass_001.ogg");
                    clearTimeout(S.refresh);   // marcarlo como leido
                    S.refresh = setTimeout(function () { if (S.chat && S.chat.number === number) send("open", number); }, 800);
                }
                return renderChat();
            }
            if (msg.mine) return;
            play("sounds/tinder/glass_001.ogg");
            toast(number, msg);
            setBadge(S.badge + 1);
            if (isActive()) send("list");
        },
        read: function (number) {
            if (S.chat && S.chat.number === number) {
                S.chat.messages.forEach(function (m) { if (m.mine) m.read = true; });
                renderChat();
            }
        },
        badge: function (n) { setBadge(n); },
        failed: function (number) {
            if (S.chat && S.chat.number === number) { S.chat.failed = S.chat.lastSent || "…"; renderChat(); }
        },
    };

    window.RP = window.RP || {};
    RP.sms = { on: function (name, args) { var fn = ON[name]; if (fn) fn.apply(null, Array.isArray(args) ? args : [args]); } };

    window.Messages = {
        onShow: function (name) {
            if (name !== "messages") return;
            if (!S.chat) send("list");
            send("badge");
        },
        open: function (number, name) {
            window.Phone.show("messages");
            open(number, name);
        },
    };

    setTimeout(function () { send("badge"); }, 500);
})();
