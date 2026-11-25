/*
 * rp_missions / app.js
 * Lua llama a MISSIONS_UI.menu(data) y MISSIONS_UI.lobby(data).
 * Eventos hacia Lua: rp:missions:ui:create|join|leave|setrole|vote|invite|start|kick|public|close
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };

    var DIFFS = [
        { key: "easy",   label: "Facil",   mult: "x1.0",  desc: "4 vidas compartidas\nEnemigos suaves", color: "#4cd38a" },
        { key: "normal", label: "Normal",  mult: "x1.25", desc: "2 vidas compartidas\nEnemigos con armadura", color: "#f5a524" },
        { key: "hard",   label: "Dificil", mult: "x1.5",  desc: "Sin vidas extra\nMas punteria y salud", color: "#e5484d" }
    ];

    var state = { menu: null, picked: null, lobby: null };

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
    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }
    function rgb(c) { return c ? "rgb(" + c[0] + "," + c[1] + "," + c[2] + ")" : "#f5a524"; }
    function fmt(ms) {
        if (!ms) return "--";
        var s = Math.floor(ms / 1000);
        return ("0" + Math.floor(s / 60)).slice(-2) + ":" + ("0" + (s % 60)).slice(-2);
    }
    function show(view) {
        ["menu", "lobby"].forEach(function (v) { $("view-" + v).classList.toggle("hidden", v !== view); });
    }
    function theme(color, letter) {
        document.documentElement.style.setProperty("--contact", rgb(color));
        $("badge").textContent = letter || "M";
    }

    // ---------------- Menu ----------------
    function renderMenu() {
        var d = state.menu;
        var contactName = d.missions.length && d.contact ? d.missions[0].contactName : null;
        theme(d.missions.length && d.contact ? d.missions[0].color : null, contactName ? contactName[0] : "M");
        $("title").textContent = contactName ? contactName + " tiene trabajo" : "Misiones";
        $("subtitle").textContent = "Elige una mision, forma un grupo y sube de nivel";
        $("rank").innerHTML = "";
        var r = $("rank");
        r.appendChild(el("div", null, "Nivel " + d.level));
        var b = el("div"); b.appendChild(document.createTextNode("Respeto ")); b.appendChild(el("b", null, d.respect + " (" + d.rank + ")")); r.appendChild(b);
        r.appendChild(el("div", null, "Grupo max. " + d.partyCap + (d.discount > 0 ? " | Descuento " + Math.round(d.discount * 100) + "%" : "")));

        var list = $("missions"); clear(list);
        if (!d.missions.length) list.appendChild(el("div", "empty", "No hay misiones disponibles."));
        if (state.picked === null || !d.missions.some(function (m) { return m.id === state.picked; })) state.picked = d.missions.length ? d.missions[0].id : null;
        d.missions.forEach(function (m) {
            var it = el("div", "item pick" + (m.locked ? " locked" : "") + (m.id === state.picked ? " sel" : ""));
            it.style.setProperty("--c", rgb(m.color));
            var left = el("div");
            left.appendChild(el("div", "name", m.title));
            left.appendChild(el("div", "meta", m.contactName + " | " + m.minP + "-" + m.maxP + " jugadores"));
            var right = el("div", "side");
            if (m.locked) right.appendChild(el("div", "lock", m.locked));
            else if (m.done > 0) right.appendChild(el("div", "done", "Completada x" + m.done));
            else right.appendChild(el("div", null, money(m.cash)));
            it.appendChild(left); it.appendChild(right);
            it.onclick = function () { state.picked = m.id; renderMenu(); };
            list.appendChild(it);
        });
        renderDetail();

        var lobbies = $("lobbies"); clear(lobbies);
        if (!d.lobbies.length) lobbies.appendChild(el("div", "empty", "No hay salas abiertas ahora."));
        d.lobbies.forEach(function (l) {
            var it = el("div", "item");
            var left = el("div");
            left.appendChild(el("div", "name", l.title));
            left.appendChild(el("div", "meta", "Lider: " + l.leader + " | " + l.count + "/" + l.max));
            var btn = el("button", null, "Unirme");
            btn.onclick = function () { send("rp:missions:ui:join", l.id); };
            it.appendChild(left); it.appendChild(btn);
            lobbies.appendChild(it);
        });
        show("menu");
    }

    function renderDetail() {
        var box = $("detail"); clear(box);
        var m = state.menu.missions.filter(function (x) { return x.id === state.picked; })[0];
        if (!m) { box.appendChild(el("div", "empty", "Selecciona una mision.")); return; }
        box.appendChild(el("div", "d-title", m.title));
        box.appendChild(el("div", null, m.desc));
        var st = el("div", "d-stats");
        [["XP", m.xp + "+"], ["Dinero", money(m.cash)], ["Respeto", "+" + m.respect], ["Nivel", m.minLevel], ["Recomendado", m.recommended + " jug."]].forEach(function (p) {
            var s = el("span", null, p[0] + " "); s.appendChild(el("b", null, String(p[1]))); st.appendChild(s);
        });
        box.appendChild(st);
        if (m.minRespect > 0) box.appendChild(el("div", "meta", "Respeto necesario: " + m.minRespect));
        if (m.best) box.appendChild(el("div", "meta", "Tu mejor tiempo: " + fmt(m.best)));
        var btn = el("button", "primary", m.locked ? "Bloqueada: " + m.locked : "Crear sala");
        btn.disabled = !!m.locked;
        btn.onclick = function () { send("rp:missions:ui:create", m.id); };
        box.appendChild(btn);
    }

    // ---------------- Sala ----------------
    function renderLobby() {
        var d = state.lobby;
        theme(d.color, d.contactName ? d.contactName[0] : "M");
        $("title").textContent = d.title;
        $("subtitle").textContent = "Mision de " + d.contactName + (d.isLeader ? " | Eres el lider" : "");
        $("rank").innerHTML = "";
        $("l-desc").textContent = d.desc;
        $("l-count").textContent = d.members.length + "/" + d.maxP + " (min. " + d.minP + ")";

        var list = $("members"); clear(list);
        d.members.forEach(function (m) {
            var it = el("div", "item member");
            var left = el("div");
            var nm = el("div", "name", m.name);
            if (m.leader) nm.appendChild(el("span", "crown", "LIDER"));
            left.appendChild(nm);
            var roleName = "Sin rol";
            d.roles.forEach(function (r) { if (r.id === m.role) roleName = r.name; });
            left.appendChild(el("div", "meta", roleName + " | Nv. " + m.level + " | Respeto " + m.respect));
            it.appendChild(left);
            var right = el("div", "side");
            var vote = m.vote ? DIFFS.filter(function (x) { return x.key === m.vote; })[0] : null;
            if (vote) right.appendChild(el("div", null, "Vota " + vote.label));
            if (d.isLeader && !m.leader) {
                var k = el("button", "kick", "Expulsar");
                k.onclick = function () { send("rp:missions:ui:kick", m.name); };
                right.appendChild(k);
            }
            it.appendChild(right);
            list.appendChild(it);
        });

        var roles = $("roles"); clear(roles);
        var none = el("div", "chip" + (d.myRole ? "" : " sel"), "Automatico");
        none.onclick = function () { send("rp:missions:ui:setrole", ""); };
        roles.appendChild(none);
        d.roles.forEach(function (r) {
            var full = r.taken >= r.max && d.myRole !== r.id;
            var c = el("div", "chip" + (d.myRole === r.id ? " sel" : "") + (full ? " full" : ""), r.name);
            c.appendChild(el("small", null, r.taken + "/" + r.max));
            c.title = r.desc || "";
            c.onclick = function () { if (!full) send("rp:missions:ui:setrole", r.id); };
            roles.appendChild(c);
        });
        var cur = d.roles.filter(function (r) { return r.id === d.myRole; })[0];
        $("role-hint").textContent = cur ? cur.desc : "Se asignara un rol libre al empezar.";

        var diffs = $("diffs"); clear(diffs);
        DIFFS.forEach(function (df) {
            var n = el("div", "diff" + (d.myVote === df.key ? " sel" : ""));
            n.style.setProperty("--dc", df.color);
            n.appendChild(el("b", null, df.label));
            n.appendChild(el("span", null, df.desc));
            n.appendChild(el("i", null, df.mult + "  |  " + (d.counts[df.key] || 0) + " voto(s)"));
            n.onclick = function () { send("rp:missions:ui:vote", df.key); };
            diffs.appendChild(n);
        });

        $("r-xp").textContent = d.xp + "+";
        $("r-cash").textContent = money(d.cash);
        $("r-resp").textContent = "+" + d.respect;

        $("leader-box").classList.toggle("hidden", !d.isLeader);
        $("chk-public").checked = !!d.public;
        var nb = $("nearby"); clear(nb);
        if (!d.nearby.length) nb.appendChild(el("div", "empty", "Nadie cerca. Escribe un ID o nombre."));
        d.nearby.forEach(function (p) {
            var it = el("div", "item");
            it.appendChild(el("div", "name", p.name + (p.id ? "  #" + p.id : "")));
            var b = el("button", null, "Invitar");
            b.onclick = function () { send("rp:missions:ui:invite", p.i); };
            it.appendChild(b);
            nb.appendChild(it);
        });

        var start = $("btn-start");
        start.disabled = !d.isLeader || d.members.length < d.minP;
        start.textContent = d.isLeader ? (d.members.length < d.minP ? "Faltan jugadores (" + d.minP + ")" : "Iniciar mision") : "Esperando al lider";
        show("lobby");
    }

    $("btn-menu-close").onclick = function () { send("rp:missions:ui:close"); };
    $("btn-leave").onclick = function () { send("rp:missions:ui:leave"); };
    $("btn-start").onclick = function () { send("rp:missions:ui:start"); };
    $("btn-invite").onclick = function () {
        var v = $("inv-name").value.trim();
        if (v) { send("rp:missions:ui:invite", v); $("inv-name").value = ""; }
    };
    $("inv-name").addEventListener("keydown", function (e) { if (e.key === "Enter") $("btn-invite").click(); });
    $("chk-public").onchange = function () { send("rp:missions:ui:public", this.checked); };
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" && !$("view-menu").classList.contains("hidden")) send("rp:missions:ui:close");
    });

    window.MISSIONS_UI = {
        menu: function (d) { state.menu = d; renderMenu(); },
        lobby: function (d) { state.lobby = d; renderLobby(); }
    };
})();
