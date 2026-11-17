/*
 * rp_inventory / app.js
 * Lua llama a RP.render(items, peso, pesoMaximo). Acciones via mta.triggerEvent.
 */
(function () {
    "use strict";

    var MIN_SLOTS = 15;
    var state = { items: [], selected: null };
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

    function renderGrid() {
        var grid = $("grid");
        grid.innerHTML = "";
        var total = Math.max(MIN_SLOTS, Math.ceil(state.items.length / 5) * 5);

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
            slot.title = item.name;
            slot.addEventListener("click", (function (id) {
                return function () { state.selected = id; renderGrid(); renderDetails(); };
            })(item.id));
            grid.appendChild(slot);
        }
    }

    function renderDetails() {
        var box = $("details");
        box.innerHTML = "";
        var item = state.items.filter(function (it) { return it.id === state.selected; })[0];
        if (!item) {
            box.appendChild(el("p", "empty-details", state.items.length ? "Selecciona un objeto para ver sus detalles." : "Tu inventario esta vacio. Compra objetos en las tiendas."));
            return;
        }

        box.appendChild(el("div", "big-icon", item.icon || "📦"));
        box.appendChild(el("h2", null, item.name));
        box.appendChild(el("p", null, item.description || ""));
        box.appendChild(el("div", "meta", "Cantidad: " + item.amount + " · " + (item.weight * item.amount).toFixed(2) + " kg"));

        var actions = el("div", "actions");
        if (item.usable) {
            var use = el("button", "primary", "Usar");
            use.type = "button";
            use.addEventListener("click", function () { send("rp:inv:ui:use", item.id); });
            actions.appendChild(use);
        }

        var row = el("div", "drop-row");
        var qty = el("input");
        qty.type = "number";
        qty.min = 1;
        qty.max = item.amount;
        qty.value = 1;
        var drop = el("button", "danger", "Tirar");
        drop.type = "button";
        drop.addEventListener("click", function () {
            var n = Math.max(1, Math.min(item.amount, parseInt(qty.value, 10) || 1));
            send("rp:inv:ui:drop", item.id, n);
        });
        row.appendChild(qty);
        row.appendChild(drop);
        actions.appendChild(row);
        box.appendChild(actions);
    }

    function renderWeight(weight, max) {
        var ratio = max > 0 ? Math.min(1, weight / max) : 0;
        $("weight-label").textContent = weight.toFixed(1) + " / " + max + " kg";
        var bar = $("weight-bar");
        bar.style.width = (ratio * 100) + "%";
        bar.style.background = ratio > 0.9 ? "#e5484d" : ratio > 0.7 ? "#f5a524" : "#4cd38a";
    }

    function close() { send("rp:inv:ui:close"); }

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
            renderGrid();
            renderDetails();
            renderWeight(Number(weight) || 0, Number(maxWeight) || 0);
        }
    };

    renderGrid();
    renderDetails();
})();
