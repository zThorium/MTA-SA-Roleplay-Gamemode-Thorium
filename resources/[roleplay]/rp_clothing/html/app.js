/*
 * rp_clothing / app.js  (panel lateral del estudio)
 * Lua llama a:
 *   RP.show(datos)              tienda (modo "shop")
 *   RP.wardrobeMode()           solo "Mis accesorios" (/accesorios)
 *   RP.setOwned(lista, lim)     accesorios del jugador
 *   RP.setPreview(key, ajust)   accesorio del catalogo que se ve sobre el cuerpo (false = ninguno)
 *   RP.editStart(info)          empieza el ajuste con el gizmo { name, icon, isNew, bones, price }
 *   RP.editState(st)            { mode, bone, canUndo }
 *   RP.did(modo)                el jugador ya movio/giro/escalo (entrenador)
 *   RP.editEnd(guardado)
 *   RP.sound(nombre)
 * El servidor valida cada prueba, compra y ajuste; aqui solo se muestra.
 */
(function () {
    "use strict";

    var $ = function (id) { return document.getElementById(id); };
    var data = null;          // datos de la tienda
    var mode = "shop";
    var tab = "clothes";
    var selected = {};        // [slot] = indice elegido (en prueba)
    var owned = [];
    var limits = { owned: 20, worn: 5 };
    var confirmDelete = null;
    var preview = { key: null, adjusted: false };
    var edit = null;          // { name, icon, isNew, bones, price, mode, bone, canUndo, did }

    // ------------------------------------------------------------ utilidades
    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }
    var sounds = {};
    function sound(name) {
        try {
            if (!sounds[name]) sounds[name] = new Audio("sounds/" + name + ".ogg");
            var a = sounds[name].cloneNode();
            a.volume = 0.5;
            a.play();
        } catch (e) { /* sin audio */ }
    }
    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined && text !== null) node.textContent = text;
        return node;
    }
    function button(text, className, onClick, snd) {
        var b = el("button", className, text);
        b.type = "button";
        b.addEventListener("click", function () { sound(snd || "click_002"); onClick(); });
        return b;
    }
    function key(name) {
        var img = el("img", "key");
        img.src = "../images/keys/" + name + ".png";
        img.alt = "";
        return img;
    }
    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }
    function price(slot, index) {
        var base = (data.prices || {})[slot] || 0;
        return Math.floor(base * (1 + (index % 5) * 0.15) * (data.multiplier || 1) + 0.5);
    }

    function tabs() {
        var nav = $("tabs");
        nav.innerHTML = "";
        if (edit) { nav.style.display = "none"; return; }
        nav.style.display = "";
        var list = mode === "shop"
            ? [["clothes", data && data.skins ? "Conjuntos" : "Ropa"], ["toys", "Accesorios"], ["owned", "Mis accesorios"]]
            : [["owned", "Mis accesorios"]];
        if (!list.some(function (t) { return t[0] === tab; })) tab = list[0][0];
        list.forEach(function (t) {
            nav.appendChild(button(t[1], t[0] === tab ? "active" : "", function () {
                tab = t[0];
                confirmDelete = null;
                if (tab !== "toys" && preview.key) send("rp:cloth:ui:preview", "");
                render();
            }, "select_002"));
        });
    }

    // ------------------------------------------------------------ Ropa
    function slotRow(panel, k, name, count, current, label) {
        if (selected[k] === undefined) selected[k] = current;
        var idx = selected[k];
        var row = el("div", "slot");

        var head = el("div", "slot-head");
        head.appendChild(el("h2", null, name));
        head.appendChild(el("span", idx === current ? "owned" : "sub", idx === current ? "Lo llevas puesto" : "Probándote"));
        row.appendChild(head);

        var picker = el("div", "picker");
        function move(step) {
            var pos = (idx + step + count) % count;
            selected[k] = pos;
            send("rp:cloth:ui:try", k, String(label ? label(pos, true) : pos));
            render();
        }
        picker.appendChild(button("‹", "arrow", function () { move(-1); }, "select_002"));
        picker.appendChild(el("span", null, label ? label(idx) : ("Prenda " + (idx + 1) + " de " + count)));
        picker.appendChild(button("›", "arrow", function () { move(1); }, "select_002"));
        row.appendChild(picker);

        var value = label ? label(idx, true) : idx;
        var cost = price(k, value);
        var buyRow = el("div", "buy-row");
        buyRow.appendChild(el("span", "price", idx === current ? "" : money(cost)));
        var buy = button(cost > data.money && idx !== current ? "Sin efectivo" : "Comprar", "primary", function () { send("rp:cloth:ui:buy", k, String(value)); });
        buy.disabled = idx === current || cost > data.money;
        buyRow.appendChild(buy);
        row.appendChild(buyRow);
        panel.appendChild(row);
    }

    function renderClothes(panel) {
        if (data.skins) {
            var list = data.skins.list || [];
            var current = Math.max(0, list.indexOf(data.skins.current));
            panel.appendChild(el("p", "muted", "Cambia de conjunto con las flechas: te lo pruebas al instante. Solo se guarda si lo compras."));
            slotRow(panel, "skin", "Conjunto", list.length, current, function (pos, raw) {
                return raw ? list[pos] : ("Conjunto " + (pos + 1) + " de " + list.length);
            });
            return;
        }
        panel.appendChild(el("p", "muted", "Cambia de prenda con las flechas: te la pruebas al instante. Solo se guarda lo que compras."));
        (data.clothes || []).forEach(function (s) { slotRow(panel, s.key, s.name, s.count, s.current); });
    }

    // ------------------------------------------------------------ Accesorios (catalogo)
    function renderToys(panel) {
        panel.appendChild(el("p", "muted", "Toca un accesorio para verlo puesto. Con «Ajustar» lo colocas a tu gusto antes de comprarlo."));
        var full = owned.length >= limits.owned;
        if (full) panel.appendChild(el("p", "warn", "Ya tienes " + limits.owned + " accesorios. Tira alguno en «Mis accesorios» para comprar más."));
        var grid = el("div", "grid");
        (data.toys || []).forEach(function (t) {
            var isOn = preview.key === t.id;
            var card = el("div", "toy" + (isOn ? " on" : ""));
            card.addEventListener("click", function () { sound("select_002"); send("rp:cloth:ui:preview", isOn ? "" : t.id); });
            card.appendChild(el("div", "icon", t.icon || "🎁"));
            card.appendChild(el("h2", null, t.name));
            card.appendChild(el("span", "price", money(t.price)));
            if (isOn) {
                card.appendChild(el("span", "tag", preview.adjusted ? "Ajustado a tu cuerpo ✓" : "Así te queda"));
                var actions = el("div", "card-actions");
                actions.appendChild(button("Ajustar", "ghost small", function () { send("rp:cloth:ui:adjust", t.id); }));
                var b = button(t.price > data.money ? "Sin efectivo" : "Comprar", "primary small", function () { send("rp:cloth:ui:buyToy", t.id); });
                b.disabled = t.price > data.money || full;
                actions.appendChild(b);
                actions.addEventListener("click", function (e) { e.stopPropagation(); });
                card.appendChild(actions);
            }
            grid.appendChild(card);
        });
        panel.appendChild(grid);
    }

    // ------------------------------------------------------------ Mis accesorios
    function renderOwned(panel) {
        var worn = owned.filter(function (t) { return t.worn; }).length;
        panel.appendChild(el("p", "muted", "Tienes " + owned.length + " de " + limits.owned + " accesorios · puestos " + worn + " de " + limits.worn + ". Con «Ajustar» los colocas arrastrando sobre tu personaje."));
        if (!owned.length) {
            panel.appendChild(el("p", "empty", mode === "shop" ? "Aún no tienes accesorios. Mira la pestaña «Accesorios»." : "Aún no tienes accesorios. Cómpralos en cualquier tienda de ropa."));
            return;
        }
        var list = el("div", "list");
        owned.forEach(function (t) {
            var row = el("div", "item" + (t.worn ? " worn" : ""));
            row.appendChild(el("div", "icon", t.icon || "🎁"));
            var name = el("div", "item-name");
            name.appendChild(el("h2", null, t.name));
            name.appendChild(el("span", t.worn ? "owned" : "sub", t.worn ? "Puesto" : "Guardado"));
            row.appendChild(name);
            var actions = el("div", "actions");
            var wear = button(t.worn ? "Quitar" : "Poner", "ghost small", function () { send("rp:cloth:ui:wear", String(t.id), t.worn ? "0" : "1"); }, "drop_002");
            wear.disabled = !t.worn && worn >= limits.worn;
            actions.appendChild(wear);
            actions.appendChild(button("Ajustar", "primary small", function () { send("rp:cloth:ui:edit", String(t.id)); }));
            actions.appendChild(button(confirmDelete === t.id ? "¿Seguro?" : "Tirar", "danger small", function () {
                if (confirmDelete === t.id) { confirmDelete = null; send("rp:cloth:ui:delete", String(t.id)); }
                else { confirmDelete = t.id; render(); }
            }));
            row.appendChild(actions);
            list.appendChild(row);
        });
        panel.appendChild(list);
    }

    // ------------------------------------------------------------ Ajuste con gizmo (entrenador)
    var STEPS = [
        { id: "move", key: "keyboard_g", text: "Arrastra las flechas de colores para colocarlo." },
        { id: "rotate", key: "keyboard_r", text: "Pulsa Rotar y arrastra un anillo para girarlo." },
        { id: "scale", key: "keyboard_s", text: "Si hace falta, cambia el tamaño con Escalar.", optional: true },
    ];

    function renderEdit(panel, footer) {
        var current = null;
        STEPS.forEach(function (s) { if (!current && !s.optional && !edit.did[s.id]) current = s.id; });

        var coach = el("div", "coach");
        coach.appendChild(el("h3", null, "Cómo colocarlo"));
        STEPS.forEach(function (s, i) {
            var done = !!edit.did[s.id];
            var row = el("div", "step" + (done ? " done" : "") + (current === s.id ? " now" : ""));
            row.appendChild(el("span", "num", done ? "✓" : String(i + 1)));
            row.appendChild(el("span", "txt", s.text));
            row.appendChild(key(s.key));
            coach.appendChild(row);
        });
        var last = el("div", "step" + (!current ? " now" : ""));
        last.appendChild(el("span", "num", "4"));
        last.appendChild(el("span", "txt", edit.isNew ? "Pulsa «Comprar»: se guarda tal cual lo dejaste." : "Pulsa «Guardar»."));
        coach.appendChild(last);
        panel.appendChild(coach);

        // Herramientas
        var tools = el("div", "tools");
        [["move", "Mover", "keyboard_g"], ["rotate", "Rotar", "keyboard_r"], ["scale", "Escalar", "keyboard_s"]].forEach(function (m) {
            var b = el("button", "tool" + (edit.mode === m[0] ? " active" : ""));
            b.type = "button";
            b.appendChild(key(m[2]));
            b.appendChild(el("span", null, m[1]));
            b.addEventListener("click", function () { sound("select_002"); send("rp:cloth:ui:mode", m[0]); });
            tools.appendChild(b);
        });
        panel.appendChild(tools);

        var field = el("label", "field", "Pegado a");
        var select = el("select");
        (edit.bones || []).forEach(function (b) {
            var o = el("option", null, b.name);
            o.value = b.id;
            if (b.id === edit.bone) o.selected = true;
            select.appendChild(o);
        });
        select.addEventListener("change", function () { sound("select_002"); send("rp:cloth:ui:bone", select.value); });
        field.appendChild(select);
        panel.appendChild(field);

        var misc = el("div", "misc");
        var undo = button("Deshacer", "ghost small", function () { send("rp:cloth:ui:undo"); });
        undo.disabled = !edit.canUndo;
        undo.appendChild(key("keyboard_ctrl"));
        undo.appendChild(key("keyboard_z"));
        misc.appendChild(undo);
        misc.appendChild(button("Restablecer", "ghost small", function () { send("rp:cloth:ui:reset"); }));
        panel.appendChild(misc);
        panel.appendChild(el("p", "muted", "Mantén Shift para moverlo con precisión y Ctrl para que encaje. Arrastra fuera del accesorio para girar la cámara."));

        footer.appendChild(button("Cancelar", "ghost", function () { send("rp:cloth:ui:done", "0"); }));
        if (edit.isNew) {
            footer.appendChild(button("Listo", "ghost", function () { send("rp:cloth:ui:done", "1"); }));
            var canBuy = data && edit.price !== undefined && edit.price !== null && edit.price <= data.money && owned.length < limits.owned;
            var buy = button("Comprar " + money(edit.price), "primary", function () {
                var k = edit.key || preview.key;
                send("rp:cloth:ui:done", "1");
                send("rp:cloth:ui:buyToy", k);
            });
            buy.disabled = !canBuy;
            footer.appendChild(buy);
        } else {
            footer.appendChild(button("Guardar", "primary", function () { send("rp:cloth:ui:done", "1"); }));
        }
    }

    // ------------------------------------------------------------ render
    function render() {
        if (mode === "shop" && !data) return;
        var panel = $("panel"), footer = $("footer");
        panel.innerHTML = "";
        footer.innerHTML = "";
        if (edit) {
            $("title").textContent = (edit.icon ? edit.icon + " " : "") + edit.name;
            $("subtitle").textContent = edit.isNew ? "Colócalo como quieras antes de comprarlo" : "Ajusta tu accesorio";
        } else {
            $("title").textContent = mode === "shop" ? data.store : "Mis accesorios";
            $("subtitle").textContent = mode === "shop" ? data.storeType + " · lo que no compres se devuelve al salir" : "Ponte, ajusta o tira tus accesorios";
        }
        $("money-box").style.display = mode === "shop" ? "" : "none";
        if (data) $("money").textContent = money(data.money);
        footer.style.display = edit ? "" : "none";
        tabs();
        if (edit) return renderEdit(panel, footer);
        ({ clothes: renderClothes, toys: renderToys, owned: renderOwned })[tab](panel);
    }

    $("btn-close").addEventListener("click", function () {
        sound("minimize_003");
        if (edit) send("rp:cloth:ui:done", "0"); else send("rp:cloth:ui:close");
    });

    window.RP = {
        show: function (d) {
            // Si cambio algo guardado (compro ropa) el servidor vuelve a poner lo guardado: se reinicia la prueba.
            var sig = function (x) { return JSON.stringify(x && (x.skins ? x.skins.current : (x.clothes || []).map(function (c) { return c.current; }))); };
            if (!data || mode !== "shop" || sig(data) !== sig(d)) selected = {};
            if (!data) sound("maximize_003");
            mode = "shop";
            data = d;
            owned = Array.isArray(d.owned) ? d.owned : [];
            limits = d.limits || limits;
            render();
        },
        wardrobeMode: function () { mode = "wardrobe"; tab = "owned"; sound("maximize_003"); render(); },
        setOwned: function (list, lim) {
            owned = Array.isArray(list) ? list : [];
            if (lim && lim.owned) limits = lim;
            render();
        },
        setPreview: function (k, adjusted) {
            preview.key = k || null;
            preview.adjusted = !!adjusted;
            render();
        },
        editStart: function (info) {
            edit = info || {};
            edit.did = {};
            edit.mode = "move";
            sound("pluck_001");
            render();
        },
        editState: function (st) {
            if (!edit || !st) return;
            edit.mode = st.mode || edit.mode;
            edit.bone = st.bone;
            edit.canUndo = !!st.canUndo;
            render();
        },
        did: function (m) {
            if (!edit || edit.did[m]) return;
            edit.did[m] = true;
            sound("pluck_001");
            render();
        },
        editEnd: function (saved) {
            edit = null;
            if (saved) sound("confirmation_001");
            render();
        },
        sound: sound
    };
})();
