/*
 * rp_resmanager / app.js
 * Lua llama a RM.render(listaDeRecursos). Acciones via mta.triggerEvent.
 */
(function () {
    "use strict";

    var STATE_LABEL = {
        running: "Iniciado", loaded: "Detenido", starting: "Iniciando...",
        stopping: "Deteniendo...", failed_to_load: "Error al cargar"
    };

    var all = [];
    var filter = "all";
    var query = "";

    var listEl = document.getElementById("list");
    var countEl = document.getElementById("count");
    var filtersEl = document.getElementById("filters");

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
    }

    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined) e.textContent = text;
        return e;
    }

    function btn(label, cls, disabled, onClick) {
        var b = el("button", "btn " + cls, label);
        b.type = "button";
        b.disabled = !!disabled;
        b.addEventListener("click", onClick);
        return b;
    }

    function matches(r) {
        if (filter === "running" && r.state !== "running") return false;
        if (filter === "stopped" && r.state === "running") return false;
        if (filter === "rp" && r.name.indexOf("rp_") !== 0) return false;
        if (query && r.name.toLowerCase().indexOf(query) === -1) return false;
        return true;
    }

    function draw() {
        listEl.textContent = "";
        var shown = all.filter(matches);
        shown.forEach(function (r) {
            var row = el("div", "row");
            row.appendChild(el("span", "dot " + r.state));

            var info = el("div", "info");
            info.appendChild(el("div", "name", r.name));
            var sub = STATE_LABEL[r.state] || r.state;
            if (r.author) sub += "  ·  " + r.author;
            if (r.locked) sub += "  ·  protegido";
            info.appendChild(el("div", "sub", sub));
            if (r.err) info.appendChild(el("div", "sub err", r.err));
            row.appendChild(info);

            var running = r.state === "running";
            var busy = r.state === "starting" || r.state === "stopping";
            var actions = el("div", "actions");
            actions.appendChild(btn("Iniciar", "go", running || busy, function () { send("rp:resmgr:ui:action", "start", r.name); }));
            actions.appendChild(btn("Reiniciar", "re", busy || r.locked, function () { send("rp:resmgr:ui:action", "restart", r.name); }));
            actions.appendChild(btn("Detener", "stop", !running || r.locked, function () { send("rp:resmgr:ui:action", "stop", r.name); }));
            row.appendChild(actions);

            listEl.appendChild(row);
        });
        if (!shown.length) listEl.appendChild(el("div", "empty", "Ningun recurso coincide."));
        var running = all.filter(function (r) { return r.state === "running"; }).length;
        countEl.textContent = shown.length + " mostrados · " + running + " iniciados de " + all.length;
    }

    [["all", "Todos"], ["rp", "Gamemode (rp_)"], ["running", "Iniciados"], ["stopped", "Detenidos"]].forEach(function (f) {
        var c = el("button", "chip" + (f[0] === filter ? " active" : ""), f[1]);
        c.type = "button";
        c.addEventListener("click", function () {
            filter = f[0];
            Array.prototype.forEach.call(filtersEl.children, function (x) { x.classList.remove("active"); });
            c.classList.add("active");
            draw();
        });
        filtersEl.appendChild(c);
    });

    document.getElementById("search").addEventListener("input", function (e) {
        query = e.target.value.trim().toLowerCase();
        draw();
    });
    document.getElementById("btn-refresh").addEventListener("click", function () { send("rp:resmgr:ui:refresh"); });
    document.getElementById("btn-close").addEventListener("click", function () { send("rp:resmgr:ui:close"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" || e.key === "F10") { e.preventDefault(); send("rp:resmgr:ui:close"); }
    });

    window.RM = {
        render: function (list) { all = list || []; draw(); }
    };
})();
