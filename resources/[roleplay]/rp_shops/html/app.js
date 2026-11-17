/*
 * rp_shops / app.js
 * Lua llama a RP.show(nombre, catalogo, dinero) y RP.setMoney(dinero).
 */
(function () {
    "use strict";

    var MAX_QTY = 10;
    var state = { catalog: [], money: 0, qty: {} };
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

    function money(n) { return "$" + Number(n).toLocaleString("es"); }

    function render() {
        $("money").textContent = money(state.money);
        var list = $("list");
        list.innerHTML = "";

        state.catalog.forEach(function (item) {
            var qty = state.qty[item.id] || 1;
            var total = item.price * qty;

            var row = el("div", "item");
            row.appendChild(el("div", "icon", item.icon || "📦"));

            var info = el("div", "info");
            info.appendChild(el("h2", null, item.name));
            info.appendChild(el("p", null, item.description || ""));
            info.appendChild(el("div", "meta", item.weight + " kg por unidad"));
            row.appendChild(info);

            var buy = el("div", "buy");
            var q = el("div", "qty");
            var minus = el("button", null, "-");
            var value = el("span", null, String(qty));
            var plus = el("button", null, "+");
            minus.type = plus.type = "button";
            minus.addEventListener("click", function () { state.qty[item.id] = Math.max(1, qty - 1); render(); });
            plus.addEventListener("click", function () { state.qty[item.id] = Math.min(MAX_QTY, qty + 1); render(); });
            q.appendChild(minus); q.appendChild(value); q.appendChild(plus);

            var price = el("span", "price", money(total));
            var btn = el("button", "primary", "Comprar");
            btn.type = "button";
            btn.disabled = total > state.money;
            btn.title = btn.disabled ? "No tienes suficiente dinero" : "";
            btn.addEventListener("click", function () { send("rp:shop:ui:buy", item.id, qty); });

            buy.appendChild(q); buy.appendChild(price); buy.appendChild(btn);
            row.appendChild(buy);
            list.appendChild(row);
        });
    }

    $("btn-close").addEventListener("click", function () { send("rp:shop:ui:close"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") send("rp:shop:ui:close");
    });

    window.RP = {
        show: function (name, catalog, cash) {
            $("shop-name").textContent = name || "Tienda";
            state.catalog = Array.isArray(catalog) ? catalog : [];
            state.money = Number(cash) || 0;
            state.qty = {};
            render();
        },
        setMoney: function (cash) {
            state.money = Number(cash) || 0;
            render();
        }
    };
})();
