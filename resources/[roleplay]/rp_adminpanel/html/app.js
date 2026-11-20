/*
 * rp_adminpanel / app.js
 * Lua llama a RP.show(catalogo): [{ id, name, items: [{ cmd, args, alt, desc, res }] }]
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var catalog = [];
    var activeTab = "todos";

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);   // vista previa en un navegador normal
    }

    function el(tag, className, text) {
        var n = document.createElement(tag);
        if (className) n.className = className;
        if (text !== undefined) n.textContent = text;
        return n;
    }

    function matches(item, q) {
        if (!q) return true;
        var hay = (item.cmd + " " + (item.args || "") + " " + item.desc + " " + (item.res || "")).toLowerCase();
        return hay.indexOf(q) !== -1;
    }

    function renderTabs() {
        var box = $("tabs");
        box.textContent = "";
        var tabs = [{ id: "todos", name: "Todos" }].concat(catalog);
        tabs.forEach(function (t) {
            var b = el("button", "tab" + (t.id === activeTab ? " active" : ""), t.name);
            b.addEventListener("click", function () { activeTab = t.id; renderTabs(); renderList(); });
            box.appendChild(b);
        });
    }

    function renderList() {
        var q = $("search").value.trim().toLowerCase();
        var list = $("list");
        list.textContent = "";
        var total = 0;

        catalog.forEach(function (cat) {
            if (activeTab !== "todos" && activeTab !== cat.id) return;
            var items = (cat.items || []).filter(function (it) { return matches(it, q); });
            if (!items.length) return;
            list.appendChild(el("div", "group", cat.name));
            items.forEach(function (it) {
                total++;
                var row = el("button", "item");
                var top = el("div", "top");
                top.appendChild(el("span", "cmd", it.cmd));
                if (it.args) top.appendChild(el("span", "args", it.args));
                if (it.res) top.appendChild(el("span", "res", it.res));
                row.appendChild(top);
                row.appendChild(el("div", "desc", it.desc));
                if (it.alt) row.appendChild(el("div", "alt", "Tambien: " + it.alt));
                row.addEventListener("click", function () {
                    send("rp:adminpanel:ui:copy", it.cmd + (it.args ? " " : ""));
                });
                list.appendChild(row);
            });
        });

        if (!total) list.appendChild(el("div", "empty", "Ningun comando coincide con la busqueda."));
        $("count").textContent = total + (total === 1 ? " comando" : " comandos");
    }

    $("btn-close").addEventListener("click", function () { send("rp:adminpanel:ui:close"); });
    $("search").addEventListener("input", renderList);
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") send("rp:adminpanel:ui:close");
    });

    window.RP = {
        show: function (data) {
            catalog = Array.isArray(data) ? data : [];
            activeTab = "todos";
            $("search").value = "";
            renderTabs();
            renderList();
            $("search").focus();
        }
    };
})();
