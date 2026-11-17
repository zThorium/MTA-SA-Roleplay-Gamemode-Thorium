/*
 * rp_clothing / app.js
 * Lua llama a:
 *   RP.show(datos)           probador de una tienda (modo "shop")
 *   RP.wardrobeMode()        solo "Mis accesorios" (/accesorios)
 *   RP.setOwned(lista, lim)  actualiza los accesorios del jugador
 * El servidor valida cada prueba y compra; aqui solo se muestra.
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

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }
    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined && text !== null) node.textContent = text;
        return node;
    }
    function button(text, className, onClick) {
        var b = el("button", className, text);
        b.type = "button";
        b.addEventListener("click", onClick);
        return b;
    }
    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }
    function price(slot, index) {
        var base = (data.prices || {})[slot] || 0;
        return Math.floor(base * (1 + (index % 5) * 0.15) * (data.multiplier || 1) + 0.5);
    }

    function tabs() {
        var list = mode === "shop"
            ? [["clothes", data && data.skins ? "Conjuntos" : "Ropa"], ["toys", "Accesorios"], ["owned", "Mis accesorios"]]
            : [["owned", "Mis accesorios"]];
        if (!list.some(function (t) { return t[0] === tab; })) tab = list[0][0];
        var nav = $("tabs");
        nav.innerHTML = "";
        list.forEach(function (t) {
            nav.appendChild(button(t[1], t[0] === tab ? "active" : "", function () { tab = t[0]; confirmDelete = null; render(); }));
        });
    }

    // ------------------------------------------------------------ Ropa
    function slotRow(panel, key, name, count, current, label) {
        if (selected[key] === undefined) selected[key] = current;
        var idx = selected[key];
        var row = el("div", "slot");

        var info = el("div");
        info.appendChild(el("h2", null, name));
        info.appendChild(el("div", idx === current ? "owned" : "sub", idx === current ? "Lo llevas puesto" : "Probando"));
        row.appendChild(info);

        var picker = el("div", "picker");
        function move(step) {
            var pos = (idx + step + count) % count;
            selected[key] = pos;
            send("rp:cloth:ui:try", key, String(label ? label(pos, true) : pos));
            render();
        }
        picker.appendChild(button("‹", "arrow", function () { move(-1); }));
        picker.appendChild(el("span", null, label ? label(idx) : ("Prenda " + (idx + 1) + " de " + count)));
        picker.appendChild(button("›", "arrow", function () { move(1); }));
        row.appendChild(picker);

        var value = label ? label(idx, true) : idx;
        var cost = price(key, value);
        row.appendChild(el("span", "price", idx === current ? "-" : money(cost)));
        var buy = button("Comprar", "primary", function () { send("rp:cloth:ui:buy", key, String(value)); });
        buy.disabled = idx === current || cost > data.money;
        row.appendChild(buy);
        panel.appendChild(row);
    }

    function renderClothes(panel) {
        if (data.skins) {
            var list = data.skins.list || [];
            var current = Math.max(0, list.indexOf(data.skins.current));
            panel.appendChild(el("p", "muted", "Elige un conjunto y pruebatelo. Solo se guarda si lo compras."));
            slotRow(panel, "skin", "Conjunto", list.length, current, function (pos, raw) {
                return raw ? list[pos] : ("Conjunto " + (pos + 1) + " de " + list.length + " (#" + list[pos] + ")");
            });
            return;
        }
        panel.appendChild(el("p", "muted", "Cambia de prenda con las flechas: te la pruebas al instante. Solo se guarda lo que compras."));
        (data.clothes || []).forEach(function (s) { slotRow(panel, s.key, s.name, s.count, s.current); });
    }

    // ------------------------------------------------------------ Accesorios (catalogo)
    function renderToys(panel) {
        panel.appendChild(el("p", "muted", "Los accesorios se guardan en \"Mis accesorios\" (tambien con /accesorios). Ahi puedes ponertelos y ajustar posicion, rotacion y tamano."));
        var grid = el("div", "grid");
        (data.toys || []).forEach(function (t) {
            var card = el("div", "toy");
            card.appendChild(el("div", "icon", t.icon || "🎁"));
            card.appendChild(el("h2", null, t.name));
            var row = el("div", "row");
            row.appendChild(el("span", "price", money(t.price)));
            var b = button("Comprar", "primary small", function () { send("rp:cloth:ui:buyToy", t.id); });
            b.disabled = t.price > data.money || owned.length >= limits.owned;
            row.appendChild(b);
            card.appendChild(row);
            grid.appendChild(card);
        });
        panel.appendChild(grid);
    }

    // ------------------------------------------------------------ Mis accesorios
    function renderOwned(panel) {
        var worn = owned.filter(function (t) { return t.worn; }).length;
        panel.appendChild(el("p", "muted", "Tienes " + owned.length + " de " + limits.owned + " accesorios. Puestos: " + worn + " de " + limits.worn + "."));
        if (!owned.length) {
            panel.appendChild(el("p", "muted", "Aun no tienes accesorios. Compralos en cualquier tienda de ropa."));
            return;
        }
        var list = el("div", "list");
        owned.forEach(function (t) {
            var row = el("div", "item");
            row.appendChild(el("div", "icon", t.icon || "🎁"));
            var name = el("h2", null, t.name);
            if (t.worn) name.appendChild(el("span", "badge", "Puesto"));
            row.appendChild(name);
            var actions = el("div", "actions");
            var wear = button(t.worn ? "Quitar" : "Poner", "ghost small", function () { send("rp:cloth:ui:wear", String(t.id), t.worn ? "0" : "1"); });
            wear.disabled = !t.worn && worn >= limits.worn;
            actions.appendChild(wear);
            actions.appendChild(button("Editar", "ghost small", function () { send("rp:cloth:ui:edit", String(t.id)); }));
            actions.appendChild(button(confirmDelete === t.id ? "Confirmar" : "Tirar", "danger small", function () {
                if (confirmDelete === t.id) { confirmDelete = null; send("rp:cloth:ui:delete", String(t.id)); }
                else { confirmDelete = t.id; render(); }
            }));
            row.appendChild(actions);
            list.appendChild(row);
        });
        panel.appendChild(list);
    }

    function render() {
        if (mode === "shop" && !data) return;
        $("title").textContent = mode === "shop" ? data.store : "Mis accesorios";
        $("subtitle").innerHTML = mode === "shop"
            ? data.storeType + " · <kbd>Esc</kbd> para salir. Lo que no compres se devuelve al cerrar."
            : "Ponte, ajusta o tira tus accesorios. <kbd>Esc</kbd> para cerrar.";
        $("money-box").style.display = mode === "shop" ? "" : "none";
        if (data) $("money").textContent = money(data.money);
        tabs();
        var panel = $("panel");
        panel.innerHTML = "";
        ({ clothes: renderClothes, toys: renderToys, owned: renderOwned })[tab](panel);
    }

    $("btn-close").addEventListener("click", function () { send("rp:cloth:ui:close"); });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") send("rp:cloth:ui:close"); });

    window.RP = {
        show: function (d) {
            // Si cambio algo guardado (compro ropa) el servidor vuelve a poner lo guardado: se reinicia la prueba.
            // Si no (compro un accesorio), se mantiene lo que se estaba probando.
            var key = function (x) { return JSON.stringify(x && (x.skins ? x.skins.current : (x.clothes || []).map(function (c) { return c.current; }))); };
            if (!data || mode !== "shop" || key(data) !== key(d)) selected = {};
            mode = "shop";
            data = d;
            owned = Array.isArray(d.owned) ? d.owned : [];
            limits = d.limits || limits;
            render();
        },
        wardrobeMode: function () { mode = "wardrobe"; tab = "owned"; render(); },
        setOwned: function (list, lim) {
            owned = Array.isArray(list) ? list : [];
            if (lim) limits = lim;
            render();
        }
    };
})();
