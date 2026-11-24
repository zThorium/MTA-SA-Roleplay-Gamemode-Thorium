/*
 * rp_races / app.js
 * Lua llama a RACES.menu(data), RACES.lobby(data), RACES.results(data) y RACES.votes(counts).
 * Eventos hacia Lua: rp:races:ui:create|join|random|leave|setting|invite|start|vote|close
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };

    // Debe coincidir con shared/s_config.lua
    var CFG = {
        classes: ["Compactos", "Deportivos", "Muscle", "Super", "Motos"],
        weathers: ["Despejado", "Soleado", "Nublado", "Lluvia", "Niebla", "Tormenta de arena"],
        hours: ["Hora del servidor", "Amanecer", "Mediodia", "Atardecer", "Noche"],
        difficulty: ["Facil", "Normal", "Dificil"],
        maxLaps: 5
    };
    var hourValues = [-1, 6, 12, 18, 23];

    var state = { menu: null, lobby: null, results: null, pickedTrack: 1, voted: null };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    function el(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text !== undefined) n.textContent = text;   // nunca innerHTML con datos de jugadores
        return n;
    }
    function clear(n) { while (n.firstChild) n.removeChild(n.firstChild); }
    function fillSelect(sel, labels, valueFn) {
        clear(sel);
        labels.forEach(function (l, i) {
            var o = el("option", null, l);
            o.value = valueFn ? valueFn(i) : (i + 1);
            sel.appendChild(o);
        });
    }
    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }
    function fmt(ms) {
        if (ms === undefined || ms === null) return "--";
        var s = ms / 1000;
        var m = Math.floor(s / 60);
        var r = (s % 60).toFixed(2);
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r;
    }
    function show(view) {
        ["menu", "lobby", "results"].forEach(function (v) { $("view-" + v).classList.toggle("hidden", v !== view); });
    }

    // ---------------- Menu ----------------
    function renderMenu() {
        var d = state.menu;
        $("title").textContent = "Carreras";
        $("subtitle").textContent = "Unete a una sala, crea la tuya o entra a una carrera aleatoria";
        var sel = $("menu-track");
        clear(sel);
        d.tracks.forEach(function (t) {
            var o = el("option", null, t.name + " (" + (t.length / 1000).toFixed(1) + " km)");
            o.value = t.idx;
            sel.appendChild(o);
        });
        sel.value = d.track;
        var box = $("lobbies");
        clear(box);
        if (!d.lobbies.length) box.appendChild(el("div", "empty", "No hay salas abiertas. Crea una o prueba la carrera aleatoria."));
        d.lobbies.forEach(function (l) {
            var row = el("div", "item");
            var info = el("div");
            info.appendChild(el("div", null, l.track));
            info.appendChild(el("div", "meta", "Anfitrion " + l.host + " · " + l.class + " · " + l.laps + " vueltas · " + l.players + "/" + l.max + " · inicia en " + l.secLeft + " s"));
            var b = el("button", null, "Unirme");
            b.addEventListener("click", function () { send("rp:races:ui:join", l.id); });
            row.appendChild(info);
            row.appendChild(b);
            box.appendChild(row);
        });
    }

    // ---------------- Sala ----------------
    var secTimer = null, secLeft = 0;
    function tickSecs() {
        $("secs").textContent = secLeft > 0 ? secLeft : 0;
        if (secLeft > 0) secLeft--;
    }

    function setVal(id, v) { var s = $(id); if (document.activeElement !== s) s.value = String(v); }

    function renderLobby() {
        var d = state.lobby, s = d.settings;
        $("title").textContent = d.trackName;
        $("subtitle").textContent = "Sala #" + d.id + " · " + (d.trackLength / 1000).toFixed(1) + " km · Anfitrion: " + d.hostName;
        $("host-tag").textContent = d.isHost ? "eres el anfitrion" : "solo lectura";
        $("count").textContent = d.players.length + "/" + d.max;

        var tracks = d.trackNames ? d.trackNames.map(function (n) { return { name: n }; }) : null;
        if (tracks) { fillSelect($("s-track"), tracks.map(function (t) { return t.name; })); }
        else if ($("s-track").options.length === 0) { fillSelect($("s-track"), [d.trackName]); }
        if (!$("s-class").options.length) {
            fillSelect($("s-class"), CFG.classes);
            fillSelect($("s-laps"), [1, 2, 3, 4, 5].map(function (n) { return n + (n === 1 ? " vuelta" : " vueltas"); }));
            fillSelect($("s-hour"), CFG.hours, function (i) { return hourValues[i]; });
            fillSelect($("s-weather"), CFG.weathers);
            fillSelect($("s-difficulty"), CFG.difficulty);
        }
        setVal("s-track", d.track); setVal("s-class", s.class); setVal("s-laps", s.laps);
        setVal("s-hour", s.hour); setVal("s-weather", s.weather); setVal("s-ghost", s.ghost);
        setVal("s-ai", s.ai); setVal("s-difficulty", s.difficulty); setVal("s-catchup", s.catchup);
        Array.prototype.forEach.call(document.querySelectorAll("#form select"), function (x) { x.disabled = !d.isHost; });
        $("s-difficulty").disabled = !d.isHost || !s.ai;

        var pl = $("players");
        clear(pl);
        d.players.forEach(function (n, i) {
            var row = el("div", "item", n);
            if (i === 0 && false) row.appendChild(el("span", "meta", "host"));
            pl.appendChild(row);
        });

        $("inv-title").classList.toggle("hidden", !d.isHost);
        var inv = $("invitable");
        inv.classList.toggle("hidden", !d.isHost);
        clear(inv);
        (d.invitable || []).forEach(function (n) {
            var c = el("span", "chip", n.replace(/_/g, " "));
            c.addEventListener("click", function () { send("rp:races:ui:invite", n); c.classList.add("sel"); });
            inv.appendChild(c);
        });
        $("btn-start").classList.toggle("hidden", !d.isHost);

        secLeft = d.secLeft;
        if (secTimer) clearInterval(secTimer);
        tickSecs();
        secTimer = setInterval(tickSecs, 1000);
    }

    // ---------------- Resultados ----------------
    function renderResults() {
        var d = state.results;
        $("title").textContent = "Resultados";
        $("subtitle").textContent = "Duracion de la carrera: " + fmt(d.duration * 1000);
        var tb = document.querySelector("#results tbody");
        clear(tb);
        d.rows.forEach(function (r) {
            var tr = el("tr", r.bot ? "bot" : (r.money > 0 ? "me" : ""));
            if (r.dnf) tr.classList.add("dnf");
            tr.appendChild(el("td", null, String(r.pos)));
            tr.appendChild(el("td", null, r.name));
            tr.appendChild(el("td", "t", r.dnf ? "DNF" : fmt(r.time)));
            tr.appendChild(el("td", null, fmt(r.best)));
            tr.appendChild(el("td", null, r.bot ? "-" : money(r.money)));
            tr.appendChild(el("td", null, r.bot ? "-" : String(r.xp)));
            tb.appendChild(tr);
        });
        renderVotes({});
        var left = d.voteSecs;
        $("vsecs").textContent = left;
        if (secTimer) clearInterval(secTimer);
        secTimer = setInterval(function () { left--; $("vsecs").textContent = Math.max(0, left); }, 1000);
    }

    function renderVotes(counts) {
        var box = $("votes");
        clear(box);
        state.results.tracks.forEach(function (name, i) {
            var n = counts[i + 1] || 0;
            var c = el("span", "chip" + (state.voted === i + 1 ? " sel" : ""), name + (n ? "  ×" + n : ""));
            c.addEventListener("click", function () { state.voted = i + 1; send("rp:races:ui:vote", i + 1); renderVotes(counts); });
            box.appendChild(c);
        });
    }

    // ---------------- API para Lua ----------------
    window.RACES = {
        menu: function (d) { state.menu = d; state.lobby = null; show("menu"); renderMenu(); },
        lobby: function (d) { state.lobby = d; show("lobby"); renderLobby(); },
        results: function (d) { state.results = d; state.voted = null; show("results"); renderResults(); },
        votes: function (c) { if (state.results) renderVotes(c); }
    };

    // ---------------- Eventos de UI ----------------
    $("btn-random").addEventListener("click", function () { send("rp:races:ui:random"); });
    $("btn-create").addEventListener("click", function () { send("rp:races:ui:create", parseInt($("menu-track").value, 10)); });
    $("btn-menu-close").addEventListener("click", function () { send("rp:races:ui:close"); });
    $("btn-leave").addEventListener("click", function () { send("rp:races:ui:leave"); });
    $("btn-start").addEventListener("click", function () { send("rp:races:ui:start"); });
    $("btn-exit").addEventListener("click", function () { send("rp:races:ui:vote", 0); });

    [["s-track", "track"], ["s-class", "class"], ["s-laps", "laps"], ["s-hour", "hour"], ["s-weather", "weather"],
     ["s-difficulty", "difficulty"], ["s-ghost", "ghost"], ["s-ai", "ai"], ["s-catchup", "catchup"]].forEach(function (p) {
        $(p[0]).addEventListener("change", function () {
            var v = $(p[0]).value;
            send("rp:races:ui:setting", p[1], v);
        });
    });
})();
