/*
 * rp_train / app.js · UI del torniquete (c_gates.lua)
 * Lua llama a: RP.show(estacion, precio) · RP.punching() · RP.punched(estacion, minutos)
 *              RP.validated() · RP.noTicket(precio) · RP.nudge() · RP.reset() · RP.hide()
 * No hay ratón: la E la escucha Lua. Vista previa sin el juego: index.html#demo
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var card = $("card"), prompt = $("prompt"), promptText = $("promptText");
    var station = "", price = 25;

    var SOUNDS = {
        open: ["sounds/kenney/glass_001.ogg"],
        punch: ["sounds/kenney/impactMetal_light_000.ogg"],
        tear: ["sounds/kenney/scratch_001.ogg", "sounds/kenney/scratch_002.ogg"],
        ok: ["sounds/kenney/confirmation_001.ogg"],
        error: ["sounds/kenney/error_004.ogg"]
    };
    function play(name) {
        var list = SOUNDS[name];
        if (!list) return;
        try { var a = new Audio(list[Math.floor(Math.random() * list.length)]); a.volume = 0.6; a.play(); } catch (e) { }
    }

    function setPrompt(text, cls, showKey) {
        promptText.textContent = text;
        prompt.className = "prompt" + (cls ? " " + cls : "") + (showKey ? "" : " hide-key");
    }

    function base() {
        card.className = "card";
        $("empty").className = "empty hidden";
        $("title").textContent = "Torniquete";
        $("station").textContent = station;
        $("price").textContent = "$" + Number(price).toLocaleString("es");
    }

    var timers = [];
    function later(fn, ms) { timers.push(setTimeout(fn, ms)); }
    function clearTimers() { timers.forEach(clearTimeout); timers = []; }

    window.RP = {
        show: function (st, p) {
            clearTimers();
            station = st || "Estación"; price = p || price;
            base();
            setPrompt("Validar boleto", "", true);
            play("open");
        },
        punching: function () {
            clearTimers();
            card.className = "card punching";
            setPrompt("Validando…", "wait", false);
            later(function () { play("punch"); }, 330);
        },
        punched: function (st, minutes) {
            card.className = "card punching done";
            later(function () { play("tear"); }, 150);
            later(function () { play("ok"); }, 450);
            setPrompt("¡Adelante! Sube al tren con E" + (minutes ? " (vale " + minutes + " min)" : ""), "ok", false);
        },
        validated: function () {
            clearTimers();
            card.className = "card done";
            setPrompt("Tu boleto ya está validado: adelante", "ok", false);
            play("ok");
        },
        noTicket: function (p) {
            clearTimers();
            card.className = "card no-ticket";
            $("empty").className = "empty";
            setPrompt("Cómpralo en la boletería de la estación ($" + Number(p || price).toLocaleString("es") + ")", "bad", false);
            play("error");
        },
        nudge: function () {
            if (card.classList.contains("shake")) return;
            card.classList.add("shake");
            later(function () { card.classList.remove("shake"); }, 360);
            play("error");
        },
        reset: function () { RP.show(station, price); },
        hide: function () { clearTimers(); card.className = "card hidden"; }
    };

    // Vista previa en un navegador normal: index.html#demo (recorre los estados)
    if (!window.mta && location.hash === "#demo") {
        RP.show("Unity Station", 25);
        setTimeout(RP.punching, 1500);
        setTimeout(function () { RP.punched("Unity Station", 30); }, 2100);
        setTimeout(function () { RP.noTicket(25); }, 5000);
    }
})();
