/* rp_medics / app.js — panel del vestuario: uniforme, servicio y casillero personal.
   Lua llama a MD.panel(data); las acciones salen con mta.triggerEvent("rp:medics:ui:action", accion, a, b). */
(function () {
    "use strict";

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
    }
    function act(action, a, b) { send("rp:medics:ui:action", action, a === undefined ? false : a, b === undefined ? false : b); }

    var SOUNDS = {
        open: "sounds/maximize_003.ogg", close: "sounds/minimize_003.ogg", click: "sounds/click_002.ogg",
        move: "sounds/drop_001.ogg", duty: "sounds/confirmation_003.ogg", error: "sounds/error_004.ogg"
    };
    function sound(k) { try { var a = new Audio(SOUNDS[k]); a.volume = 0.5; a.play(); } catch (e) { } }

    function $(id) { return document.getElementById(id); }
    function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;" }[c]; }); }

    var data = null, skin = null, first = true;

    function coachText(d) {
        if (d.loading) return "Abriendo tu casillero…";
        if (d.onDuty) return "Estás de servicio. Al terminar, pulsa <b>Sacar todo y salir de servicio</b> para recuperar tus cosas.";
        if (d.wornPack && d.lockerPack) return "Ya tienes una mochila en el casillero: sácala o quítate la que llevas antes de entrar de servicio.";
        return "Pulsa <b>Guardar todo y entrar de servicio</b>: tus cosas y tu mochila quedan aquí y te pones la mochila médica.";
    }

    function packSlot(el, pack, onClick, emptyText) {
        el.className = "pack-slot" + (pack ? " full" : "") + (pack && pack.duty ? " duty" : "");
        el.onclick = null;
        if (!pack) { el.innerHTML = '<svg><use href="#i-pack"/></svg>' + emptyText; return; }
        el.innerHTML = '<svg><use href="#i-pack"/></svg>' + esc(pack.name) +
            (pack.duty ? ' <span class="tag">servicio</span>' : "") + "<small>" + pack.count + " dentro</small>";
        if (!pack.duty) el.onclick = function () { sound("move"); onClick(); };
    }

    function list(el, items, onClick, emptyText) {
        el.innerHTML = "";
        if (!items.length) { el.innerHTML = '<div class="empty">' + emptyText + "</div>"; return; }
        items.forEach(function (it) {
            var row = document.createElement("div");
            row.className = "item" + (it.locked ? " locked" : "");
            row.innerHTML = '<span class="ico">' + esc(it.icon) + "</span>" + esc(it.name) +
                (it.locked ? ' <span class="tag">material</span>' : it.kept ? ' <span class="tag">se queda contigo</span>' : "") +
                '<span class="amt">×' + it.amount + "</span>";
            if (!it.locked) row.onclick = function () { row.classList.add("moving"); sound("move"); onClick(it.id); };
            el.appendChild(row);
        });
    }

    function render() {
        var d = data;
        $("state").textContent = d.onDuty ? "De servicio" : "Fuera de servicio";
        $("state").className = "state" + (d.onDuty ? " on" : "");
        $("coach").innerHTML = coachText(d);

        if (skin === null) skin = d.skin;
        var skins = $("skins");
        skins.innerHTML = "";
        d.skins.forEach(function (s) {
            var b = document.createElement("div");
            b.className = "skin" + (s.id === skin ? " sel" : "");
            b.textContent = "Paramédico · " + s.name;
            b.onclick = function () {
                skin = s.id; sound("click"); render();
                if (d.onDuty) act("duty_on", skin, false);   // de servicio: cambia de uniforme al momento
            };
            skins.appendChild(b);
        });

        var main = $("btn-main"), alt = $("btn-alt");
        main.className = "btn primary" + (d.onDuty ? " off" : "");
        $("main-label").textContent = d.onDuty ? "Sacar todo y salir de servicio" : "Guardar todo y entrar de servicio";
        main.onclick = function () { sound("duty"); d.onDuty ? act("duty_off", true) : act("duty_on", skin, true); };
        alt.textContent = d.onDuty ? "Salir de servicio y dejar mis cosas aquí" : "Entrar de servicio sin guardar nada";
        alt.onclick = function () { sound("click"); d.onDuty ? act("duty_off", false) : act("duty_on", skin, false); };
        $("note").innerHTML = "Haz clic en un objeto para pasarlo de un lado a otro. " +
            "El teléfono y los documentos se quedan contigo." +
            (d.requireUnarmed ? " <b>De servicio no se llevan armas.</b>" : "") +
            "<br>Médicos de servicio ahora: <b>" + d.colleagues + "</b>";

        packSlot($("worn-pack"), d.wornPack, function () { act("store_pack"); }, "Sin mochila puesta");
        packSlot($("locker-pack"), d.lockerPack, function () { act("take_pack"); }, "Hueco para tu mochila");
        list($("carried"), d.carried, function (id) { act("store", id); }, "No llevas nada encima.");
        list($("stored"), d.stored, function (id) { act("take", id); }, "Tu casillero está vacío.");
        $("carried-n").textContent = "(" + d.carried.length + ")";
        $("stored-n").textContent = "(" + d.stored.length + ")";
    }

    function close() { sound("close"); send("rp:medics:ui:close"); }

    window.MD = {
        panel: function (d) {
            if (first) { sound("open"); first = false; }
            data = d;
            render();
        }
    };

    $("btn-close").onclick = close;
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") close(); });

    // Vista previa en un navegador normal (sin MTA): datos de ejemplo
    if (!window.mta) {
        window.MD.panel({
            onDuty: false, skin: 274, colleagues: 2, requireUnarmed: true, name: "Ana Rojas",
            skins: [{ id: 274, name: "Los Santos" }, { id: 275, name: "Las Venturas" }, { id: 276, name: "San Fierro" }],
            carried: [
                { id: "phone", name: "Telefono movil", icon: "📱", amount: 1, kept: true },
                { id: "wpn_deagle", name: "Desert Eagle", icon: "🔫", amount: 1 },
                { id: "burger", name: "Hamburguesa", icon: "🍔", amount: 2 },
                { id: "medkit", name: "Botiquin", icon: "🩹", amount: 1, locked: true }
            ],
            stored: [{ id: "lockpick", name: "Ganzua", icon: "🔧", amount: 3 }],
            wornPack: { id: "bp_hiking", name: "Mochila de montaña", count: 7 },
            lockerPack: false
        });
    }
})();
