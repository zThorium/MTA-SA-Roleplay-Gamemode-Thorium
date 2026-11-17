/* rp_bank / atm.js  -  Lua llama a RP.render(datos) */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var tab = "withdraw";
    var LABELS = { withdraw: "Retirar", deposit: "Depositar", transfer: "Transferir" };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }
    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }

    var TYPES = {
        deposit: ["Deposito", true], withdraw: ["Retiro", false],
        transfer_in: ["Transferencia de ", true], transfer_out: ["Transferencia a ", false],
        purchase: ["Compra: ", false], sale: ["Venta: ", true],
        payday: ["Sueldo: ", true]
    };

    function setTab(name) {
        tab = name;
        document.querySelectorAll(".tabs button").forEach(function (b) { b.classList.toggle("active", b.dataset.tab === name); });
        $("target-row").hidden = name !== "transfer";
        $("submit").textContent = LABELS[name];
    }

    document.querySelectorAll(".tabs button").forEach(function (b) {
        b.addEventListener("click", function () { setTab(b.dataset.tab); });
    });
    document.querySelectorAll("#quick button").forEach(function (b) {
        b.addEventListener("click", function () { $("amount").value = b.dataset.v; });
    });

    $("form").addEventListener("submit", function (e) {
        e.preventDefault();
        var amount = parseInt($("amount").value, 10);
        if (!(amount > 0)) return;
        send("rp:atm:ui:action", tab, amount, $("target").value.trim());
        $("amount").value = "";
    });

    $("btn-close").addEventListener("click", function () { send("rp:atm:ui:close"); });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") send("rp:atm:ui:close"); });

    window.RP = {
        render: function (d) {
            $("holder").textContent = d.name || "";
            $("balance").textContent = money(d.balance);
            $("cash").textContent = money(d.cash);
            var withdrawBtn = document.querySelector('.tabs button[data-tab="withdraw"]');
            withdrawBtn.hidden = !d.canWithdraw;
            if (!d.canWithdraw && tab === "withdraw") setTab("deposit");

            var list = $("history");
            list.innerHTML = "";
            var rows = Array.isArray(d.history) ? d.history : [];
            if (!rows.length) {
                var li = document.createElement("li");
                li.className = "empty";
                li.textContent = "Sin movimientos todavia";
                list.appendChild(li);
            }
            rows.forEach(function (r) {
                var t = TYPES[r.type] || [r.type, true];
                var li = document.createElement("li");
                var desc = document.createElement("span");
                desc.className = "desc";
                desc.textContent = t[0] + (r.other_name ? String(r.other_name).replace(/_/g, " ") : "") + " · " + r.date;
                var amt = document.createElement("span");
                amt.className = t[1] ? "in" : "out";
                amt.textContent = (t[1] ? "+" : "-") + money(r.amount);
                li.appendChild(desc);
                li.appendChild(amt);
                list.appendChild(li);
            });
        }
    };
    setTab("withdraw");
})();
