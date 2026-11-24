/*
 * rp_inventory / app.js
 * Lua llama a RP.render(items, peso, pesoMaximo) y RP.nearby(lista).
 * Acciones via mta.triggerEvent: rp:inv:ui:use / drop / dropAt / give / close.
 */
(function () {
    "use strict";

    var MIN_SLOTS = 18;
    var DRAG_THRESHOLD = 6;
    var state = { items: [], selected: null, nearby: [] };
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

    function selectedItem() {
        return state.items.filter(function (it) { return it.id === state.selected; })[0];
    }

    // Cantidad elegida en el panel de detalles (1 por defecto)
    function chosenAmount(item) {
        var qty = $("qty");
        var n = qty ? parseInt(qty.value, 10) : 1;
        return Math.max(1, Math.min(item.amount, n || 1));
    }

    function renderGrid() {
        var grid = $("grid");
        grid.innerHTML = "";
        var total = Math.max(MIN_SLOTS, Math.ceil(state.items.length / 6) * 6);

        for (var i = 0; i < total; i++) {
            var item = state.items[i];
            if (!item) {
                grid.appendChild(el("div", "slot empty"));
                continue;
            }
            var slot = el("div", "slot" + (item.id === state.selected ? " selected" : ""));
            slot.appendChild(el("span", "icon", item.icon || "📦"));
            slot.appendChild(el("span", "name", item.name));
            slot.appendChild(el("span", "amount", "x" + item.amount));
            slot.appendChild(el("span", "kg", (item.weight * item.amount).toFixed(2) + " kg"));
            slot.title = item.name;
            slot.addEventListener("mousedown", (function (it) {
                return function (e) {
                    if (e.button !== 0) return;
                    state.selected = it.id;
                    drag = { item: it, startX: e.clientX, startY: e.clientY, active: false };
                    renderGrid();
                    renderDetails();
                };
            })(item));
            grid.appendChild(slot);
        }
    }

    function renderDetails() {
        var box = $("details");
        box.innerHTML = "";
        var item = selectedItem();
        if (!item) {
            box.appendChild(el("p", "empty-details", state.items.length ? "Selecciona un objeto para ver sus detalles." : "Tu inventario esta vacio. Compra objetos en las tiendas."));
            return;
        }

        box.appendChild(el("div", "big-icon", item.icon || "📦"));
        box.appendChild(el("h2", null, item.name));
        box.appendChild(el("p", null, item.description || ""));
        box.appendChild(el("div", "meta", "Cantidad " + item.amount + " · " + (item.weight * item.amount).toFixed(2) + " kg"));

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

    function renderWeight(weight, max) {
        var ratio = max > 0 ? Math.min(1, weight / max) : 0;
        $("weight-label").textContent = weight.toFixed(1) + " / " + max + " kg";
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

    document.addEventListener("mousemove", function (e) {
        if (!drag) return;
        if (!drag.active) {
            if (Math.abs(e.clientX - drag.startX) + Math.abs(e.clientY - drag.startY) < DRAG_THRESHOLD) return;
            drag.active = true;
            document.body.classList.add("dragging");
            var ghost = $("ghost");
            ghost.textContent = drag.item.icon || "📦";
            ghost.appendChild(el("small", null, "x" + chosenAmount(drag.item)));
            ghost.style.display = "block";
        }
        var g = $("ghost");
        g.style.left = e.clientX + "px";
        g.style.top = e.clientY + "px";
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

        var amount = chosenAmount(d.item);
        var card = cardAt(e.clientX, e.clientY);
        if (card) {
            send("rp:inv:ui:give", d.item.id, amount, parseInt(card.getAttribute("data-id"), 10));
            return;
        }
        var rect = $("window").getBoundingClientRect();
        var inside = e.clientX >= rect.left && e.clientX <= rect.right && e.clientY >= rect.top && e.clientY <= rect.bottom;
        var nearbyRect = $("nearby").getBoundingClientRect();
        var overNearby = e.clientX >= nearbyRect.left && e.clientX <= nearbyRect.right && e.clientY >= nearbyRect.top && e.clientY <= nearbyRect.bottom;
        if (!inside && !overNearby) send("rp:inv:ui:dropAt", d.item.id, amount, e.clientX, e.clientY);
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
        render: function (items, weight, maxWeight) {
            state.items = Array.isArray(items) ? items : [];
            if (!state.items.some(function (it) { return it.id === state.selected; })) {
                state.selected = state.items.length ? state.items[0].id : null;
            }
            // No reconstruir mientras se arrastra (el item seguiria "agarrado" a un nodo muerto)
            renderGrid();
            if (!document.getElementById("qty") || !(document.activeElement && document.activeElement.id === "qty")) renderDetails();
            renderNearby();
            renderWeight(Number(weight) || 0, Number(maxWeight) || 0);
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
