/*
 * rp_radio / app.js
 * Lua llama a RP.show(emisoras, actual, volumen) y RP.setCurrent(id).
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var current = null;

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

    function mark() {
        var items = $("list").children;
        for (var i = 0; i < items.length; i++) {
            var active = Number(items[i].getAttribute("data-id")) === current;
            items[i].className = "station" + (active ? " active" : "");
        }
    }

    $("btn-close").addEventListener("click", function () { send("rp:radio:ui:close"); });
    $("btn-off").addEventListener("click", function () { send("rp:radio:ui:select", 0); });
    $("vol").addEventListener("input", function () {
        $("vol-val").textContent = this.value + "%";
        send("rp:radio:ui:volume", Number(this.value));
    });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") send("rp:radio:ui:close");
    });

    window.RP = {
        show: function (stations, cur, vol) {
            var list = $("list");
            list.innerHTML = "";
            (stations || []).forEach(function (st) {
                var b = el("button", "station");
                b.setAttribute("data-id", st.id);
                b.appendChild(el("span", "dot"));
                b.appendChild(el("span", "name", st.name));
                b.appendChild(el("span", "genre", st.genre));
                b.addEventListener("click", function () { send("rp:radio:ui:select", st.id); });
                list.appendChild(b);
            });
            $("vol").value = vol;
            $("vol-val").textContent = vol + "%";
            current = cur;
            mark();
        },
        setCurrent: function (cur) { current = cur; mark(); }
    };
})();
