/*
 * rp_emergency / app.js
 * Lua llama a RP.show(servicios, ocupado).
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var services = [];
    var busy = false;

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

    function choose(i) {
        var s = services[i];
        if (!s || busy) return;
        send("rp:emergency:ui:call", s.id);
    }

    function render() {
        var list = $("list");
        list.innerHTML = "";
        services.forEach(function (s, i) {
            var b = el("button", "item");
            b.type = "button";
            b.disabled = busy;
            b.appendChild(el("div", "icon", s.icon || ""));
            var info = el("div", "info");
            info.appendChild(el("h2", "", s.name));
            info.appendChild(el("p", "", s.desc));
            b.appendChild(info);
            b.appendChild(el("span", "key", String(i + 1)));
            b.addEventListener("click", function () { choose(i); });
            list.appendChild(b);
        });
        $("busy").hidden = !busy;
    }

    $("btn-close").addEventListener("click", function () { send("rp:emergency:ui:close"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") send("rp:emergency:ui:close");
        var n = parseInt(e.key, 10);
        if (n >= 1 && n <= services.length) choose(n - 1);
    });

    window.RP = {
        show: function (list, isBusy) {
            services = list || [];
            busy = !!isBusy;
            render();
        }
    };
})();
