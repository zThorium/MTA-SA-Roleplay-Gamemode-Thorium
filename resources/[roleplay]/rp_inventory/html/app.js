/*
 * rp_inventory / app.js
 * Lua llama a RP.render(items, peso, pesoMaximo, mochila), RP.nearby(lista) y RP.setLayout(json).
 * Acciones via mta.triggerEvent: rp:inv:ui:use / drop / dropAt / give / close / layout /
 * toBackpack / fromBackpack / dropBackpack.
 * Arrastrar: a otra casilla = mover o intercambiar; al otro bloque (inventario <-> mochila) = guardar/sacar;
 * sobre una persona = dar; fuera de la ventana = suelo.
 */
(function () {
    "use strict";

    var MIN_SLOTS = 18;
    var MAX_CELLS = 120;
    var DRAG_THRESHOLD = 6;
    var state = { items: [], selected: null, nearby: [], bp: null, weight: 0, max: 0 };
    var layout = { base: {}, bp: {} };   // posiciones de las casillas (ver place)
    var drag = null;   // { item, startX, startY, active }
    var $ = function (id) { return document.getElementById(id); };

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

    // Icono del item: imagen vectorial si tiene (iconImg) o el emoji de siempre
    function iconNode(item, className) {
        var node = el("span", className);
        if (item.iconImg) {
            var img = document.createElement("img");
            img.src = item.iconImg;
            img.draggable = false;
            node.appendChild(img);
        } else {
            node.textContent = item.icon || "📦";
        }
        return node;
    }

    // Un mismo item puede estar en el inventario y en la mochila: la clave de seleccion incluye el origen
    function keyOf(item) { return (item.bp ? "bp:" : "") + item.id; }

    function selectedItem() {
        return state.items.filter(function (it) { return keyOf(it) === state.selected; })[0];
    }

    // Cantidad elegida en el panel de detalles (1 por defecto)
    function chosenAmount(item) {
        var qty = $("qty");
        var n = qty ? parseInt(qty.value, 10) : 1;
        return Math.max(1, Math.min(item.amount, n || 1));
    }

    // ---- Posiciones de las casillas ----
    // layout[bloque][clave] = numero de casilla. Cada item se queda donde lo dejes; los nuevos van al primer
    // hueco libre. Se guarda en el cliente por personaje (Lua) para que sobreviva a reconectar.
    function sectionOf(item) { return item.bp ? "bp" : "base"; }

    function place(list, section, minTotal) {
        var map = layout[section];
        var cells = [];
        var rest = [];
        list.forEach(function (it) {
            var idx = map[keyOf(it)];
            if (typeof idx === "number" && idx >= 0 && idx < MAX_CELLS && !cells[idx]) cells[idx] = it;
            else rest.push(it);
        });
        rest.forEach(function (it) {
            var i = 0;
            while (cells[i]) i++;
            cells[i] = it;
            map[keyOf(it)] = i;
        });
        return { cells: cells, total: Math.max(minTotal, Math.ceil(cells.length / 6) * 6) };
    }

    function saveLayout() { send("rp:inv:ui:layout", JSON.stringify(layout)); }

    function slotFor(item) {
        var cls = "slot" + (item.bp ? " bp" : "") + (keyOf(item) === state.selected ? " selected" : "");
        var slot = el("div", cls);
        slot.appendChild(iconNode(item, "icon"));
        slot.appendChild(el("span", "name", item.name));
        slot.appendChild(el("span", "amount", "x" + item.amount));
        slot.appendChild(el("span", "kg", (item.weight * item.amount).toFixed(2) + " kg"));
        if (item.bp) slot.appendChild(el("span", "badge", "🎒"));
        slot.title = item.name + (item.bp ? " (en la mochila)" : "");
        slot.addEventListener("mousedown", function (e) {
            if (e.button !== 0) return;
            state.selected = keyOf(item);
            drag = { item: item, startX: e.clientX, startY: e.clientY, active: false };
            renderGrid();
            renderDetails();
        });
        return slot;
    }

    function sectionHead(title, detail) {
        var h = el("div", "sec-head");
        h.appendChild(el("strong", null, title));
        h.appendChild(el("span", null, detail));
        return h;
    }

    function addCells(grid, section, placed) {
        for (var i = 0; i < placed.total; i++) {
            var it = placed.cells[i];
            var slot = it ? slotFor(it) : el("div", "slot empty" + (section === "bp" ? " bp" : ""));
            slot.setAttribute("data-sec", section);
            slot.setAttribute("data-idx", i);
            grid.appendChild(slot);
        }
    }

    // Inventario base y, debajo, los slots que anade la mochila equipada (otro color)
    function renderGrid() {
        var grid = $("grid");
        grid.innerHTML = "";
        var base = state.items.filter(function (it) { return !it.bp; });
        var packed = state.items.filter(function (it) { return it.bp; });

        if (state.bp) grid.appendChild(sectionHead("Inventario", state.weight.toFixed(1) + " / " + state.max + " kg"));
        addCells(grid, "base", place(base, "base", MIN_SLOTS));
        if (!state.bp) return;

        var head = el("div", "bp-head");
        head.appendChild(iconNode(state.bp, "bp-icon"));
        var info = el("div", "bp-info");
        info.appendChild(el("strong", null, state.bp.name));
        info.appendChild(el("span", null, state.bp.used.toFixed(1) + " / " + state.bp.capacity + " kg en la mochila"));
        var bar = el("div", "bp-bar");
        var fill = el("div", "bp-fill");
        fill.style.width = Math.min(100, state.bp.capacity > 0 ? state.bp.used / state.bp.capacity * 100 : 0) + "%";
        bar.appendChild(fill);
        info.appendChild(bar);
        head.appendChild(info);
        var dropPack = el("button", null, "Tirar mochila");
        dropPack.type = "button";
        dropPack.title = "La tira al suelo con todo lo que lleva dentro";
        dropPack.addEventListener("click", function () { send("rp:inv:ui:dropBackpack"); });
        head.appendChild(dropPack);
        grid.appendChild(head);

        addCells(grid, "bp", place(packed, "bp", state.bp.slots || 0));
    }

    function renderDetails() {
        var box = $("details");
        box.innerHTML = "";
        var item = selectedItem();
        if (!item) {
            box.appendChild(el("p", "empty-details", state.items.length ? "Selecciona un objeto para ver sus detalles." : "Tu inventario esta vacio. Compra objetos en las tiendas."));
            return;
        }

        var big = iconNode(item, "big-icon");
        big.style.display = "block";
        box.appendChild(big);
        box.appendChild(el("h2", null, item.name));
        box.appendChild(el("p", null, item.description || ""));
        box.appendChild(el("div", "meta", "Cantidad " + item.amount + " · " + (item.weight * item.amount).toFixed(2) + " kg"));
        if (item.bp) box.appendChild(el("div", "bp-tag", "🎒 Guardado en la mochila"));

        var actions = el("div", "actions");
        if (item.amount > 1) {
            var row = el("div", "qty-row");
            row.appendChild(el("span", null, "Cantidad a mover"));
            var qty = el("input");
            qty.id = "qty";
            qty.type = "number";
            qty.min = 1;
            qty.max = item.amount;
            qty.value = 1;
            row.appendChild(qty);
            actions.appendChild(row);
        }
        if (item.usable) {
            var use = el("button", "primary", "Usar");
            use.type = "button";
            use.addEventListener("click", function () { send("rp:inv:ui:use", item.id); });
            actions.appendChild(use);
        }
        // Mochila equipada: mover entre inventario y mochila (las mochilas no se guardan en mochilas)
        if (item.bp) {
            var out = el("button", "bp-move", "Sacar de la mochila");
            out.type = "button";
            out.addEventListener("click", function () { send("rp:inv:ui:fromBackpack", item.id, chosenAmount(item)); });
            actions.appendChild(out);
        } else if (state.bp && !/^bp_/.test(item.id)) {
            var into = el("button", "bp-move", "Guardar en la mochila");
            into.type = "button";
            into.addEventListener("click", function () { send("rp:inv:ui:toBackpack", item.id, chosenAmount(item)); });
            actions.appendChild(into);
        }
        var drop = el("button", "danger", "Tirar al suelo");
        drop.type = "button";
        drop.addEventListener("click", function () { send("rp:inv:ui:drop", item.id, chosenAmount(item)); });
        actions.appendChild(drop);
        box.appendChild(actions);
    }

    function renderNearby() {
        var list = $("nearby-list");
        list.innerHTML = "";
        if (!state.nearby.length) {
            list.appendChild(el("p", "nearby-empty", "Nadie cerca."));
            return;
        }
        state.nearby.forEach(function (p) {
            var card = el("div", "near-card");
            card.setAttribute("data-id", p.id);
            var who = el("span", "who", p.name + " ");
            who.appendChild(el("small", null, "(" + p.id + ")"));
            card.appendChild(who);
            var btn = el("button", null, "Dar");
            btn.type = "button";
            btn.disabled = !selectedItem();
            btn.addEventListener("click", function () { give(p.id); });
            card.appendChild(btn);
            list.appendChild(card);
        });
    }

    function give(targetId) {
        var item = selectedItem();
        if (item) send("rp:inv:ui:give", item.id, chosenAmount(item), targetId);
    }

    // Con mochila equipada el peso y el maximo suman los de la mochila (inventario 15 kg + capacidad de la mochila)
    function renderWeight(weight, max) {
        var total = weight + (state.bp ? state.bp.used : 0);
        var cap = max + (state.bp ? state.bp.capacity : 0);
        var ratio = cap > 0 ? Math.min(1, total / cap) : 0;
        $("weight-label").textContent = total.toFixed(1) + " / " + cap + " kg";
        $("weight-sub").textContent = state.bp
            ? "Inventario " + max + " kg + mochila " + state.bp.capacity + " kg"
            : "";
        var bar = $("weight-bar");
        bar.style.width = (ratio * 100) + "%";
        bar.style.background = ratio > 0.9 ? "#e5484d" : ratio > 0.7 ? "#f5a524" : "#4cd38a";
    }

    function close() { send("rp:inv:ui:close"); }

    // ---- Arrastrar: ventana translucida; soltar sobre una persona = dar, fuera de la ventana = suelo ----
    function cardAt(x, y) {
        var node = document.elementFromPoint(x, y);
        while (node && node !== document.body) {
            if (node.className && String(node.className).indexOf("near-card") !== -1) return node;
            node = node.parentNode;
        }
        return null;
    }

    function setHover(card) {
        var cards = document.querySelectorAll(".near-card");
        for (var i = 0; i < cards.length; i++) cards[i].classList.toggle("hover", cards[i] === card);
    }

    function inRect(node, x, y) {
        var r = node.getBoundingClientRect();
        return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
    }

    // Casilla de la cuadricula bajo el cursor (por geometria: con la ventana translucida no hay hit-testing)
    function slotAt(x, y) {
        if (!inRect($("grid"), x, y)) return null;
        var slots = document.querySelectorAll("#grid .slot");
        for (var i = 0; i < slots.length; i++) {
            if (inRect(slots[i], x, y)) return slots[i];
        }
        return null;
    }

    function setSlotHover(slot) {
        var slots = document.querySelectorAll("#grid .slot");
        for (var i = 0; i < slots.length; i++) slots[i].classList.toggle("drop-hover", slots[i] === slot);
    }

    // Soltar un item en una casilla: dentro del mismo bloque lo coloca (o intercambia); de un bloque al otro
    // (inventario <-> mochila) guarda o saca la cantidad elegida.
    function moveTo(item, section, idx) {
        var from = sectionOf(item);
        var key = keyOf(item);
        if (from === section) {
            var map = layout[from];
            var current = map[key];
            if (current === idx) return;
            state.items.forEach(function (it) {
                if (sectionOf(it) === from && keyOf(it) !== key && map[keyOf(it)] === idx) map[keyOf(it)] = current;   // intercambio
            });
            map[key] = idx;
            saveLayout();
            renderGrid();
            return;
        }
        if (section === "bp" && (!state.bp || /^bp_/.test(item.id))) return;   // sin mochila / una mochila no va en otra
        var newKey = (section === "bp" ? "bp:" : "") + item.id;
        var exists = state.items.some(function (it) { return keyOf(it) === newKey; });
        if (!exists) {
            layout[section][newKey] = idx;
            saveLayout();
        }
        send(section === "bp" ? "rp:inv:ui:toBackpack" : "rp:inv:ui:fromBackpack", item.id, chosenAmount(item));
    }

    document.addEventListener("mousemove", function (e) {
        if (!drag) return;
        if (!drag.active) {
            if (Math.abs(e.clientX - drag.startX) + Math.abs(e.clientY - drag.startY) < DRAG_THRESHOLD) return;
            drag.active = true;
            var ghost = $("ghost");
            ghost.textContent = drag.item.iconImg ? "" : (drag.item.icon || "📦");
            if (drag.item.iconImg) ghost.appendChild(iconNode(drag.item, "ghost-icon"));
            ghost.appendChild(el("small", null, "x" + chosenAmount(drag.item)));
            ghost.style.display = "block";
        }
        var g = $("ghost");
        g.style.left = e.clientX + "px";
        g.style.top = e.clientY + "px";
        // La ventana solo se vuelve translucida al salir de ella (para ver donde sueltas en el mundo)
        var inside = inRect($("window"), e.clientX, e.clientY);
        document.body.classList.toggle("dragging", !inside);
        setSlotHover(inside ? slotAt(e.clientX, e.clientY) : null);
        setHover(cardAt(e.clientX, e.clientY));
    });

    document.addEventListener("mouseup", function (e) {
        if (!drag) return;
        var d = drag;
        drag = null;
        if (!d.active) return;
        document.body.classList.remove("dragging");
        $("ghost").style.display = "none";
        setHover(null);
        setSlotHover(null);

        var amount = chosenAmount(d.item);
        var card = cardAt(e.clientX, e.clientY);
        if (card) {
            send("rp:inv:ui:give", d.item.id, amount, parseInt(card.getAttribute("data-id"), 10));
            return;
        }
        var inside = inRect($("window"), e.clientX, e.clientY);
        if (inside) {
            var slot = slotAt(e.clientX, e.clientY);
            if (slot) moveTo(d.item, slot.getAttribute("data-sec"), parseInt(slot.getAttribute("data-idx"), 10));
            return;
        }
        if (!inRect($("nearby"), e.clientX, e.clientY)) send("rp:inv:ui:dropAt", d.item.id, amount, e.clientX, e.clientY);
    });

    $("btn-close").addEventListener("click", close);
    document.addEventListener("keydown", function (e) {
        if (document.activeElement && document.activeElement.tagName === "INPUT" && e.key !== "Escape") return;
        if (e.key === "Escape" || e.key === "i" || e.key === "I") {
            e.preventDefault();
            close();
        }
    });

    window.RP = {
        render: function (items, weight, maxWeight, bp) {
            state.items = Array.isArray(items) ? items : [];
            state.bp = bp && bp.name ? bp : null;
            state.weight = Number(weight) || 0;
            state.max = Number(maxWeight) || 0;
            if (!state.items.some(function (it) { return keyOf(it) === state.selected; })) {
                state.selected = state.items.length ? keyOf(state.items[0]) : null;
            }
            // No reconstruir mientras se arrastra (el item seguiria "agarrado" a un nodo muerto)
            renderGrid();
            if (!document.getElementById("qty") || !(document.activeElement && document.activeElement.id === "qty")) renderDetails();
            renderNearby();
            renderWeight(Number(weight) || 0, Number(maxWeight) || 0);
        },
        // Posiciones guardadas de las casillas (JSON); Lua las envia al crear el navegador, antes del primer render
        setLayout: function (json) {
            try {
                var saved = JSON.parse(json);
                ["base", "bp"].forEach(function (s) {
                    var src = saved && saved[s] || {};
                    Object.keys(src).forEach(function (k) {
                        if (typeof src[k] === "number" && src[k] >= 0 && src[k] < MAX_CELLS) layout[s][k] = Math.floor(src[k]);
                    });
                });
            } catch (e) { /* archivo corrupto: se ignora */ }
        },
        nearby: function (list) {
            var next = Array.isArray(list) ? list : [];
            // Solo redibuja si cambia (evita parpadeo y perder el click)
            if (JSON.stringify(next) === JSON.stringify(state.nearby)) return;
            state.nearby = next;
            renderNearby();
        }
    };

    renderGrid();
    renderDetails();
    renderNearby();
})();
