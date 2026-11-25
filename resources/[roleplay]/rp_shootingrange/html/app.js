/*
 * rp_shootingrange / app.js
 * Lua llama a RP.menu / start / round / hit / hud / results. El JS solo dibuja y pide (mta.triggerEvent);
 * armas, balas y habilidad las decide siempre el servidor.
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var data = null, filter = "all", roundEnd = 0, roundStart = 0, timer = null, kindNames = {
        static: "Blancos fijos", advance: "Blancos que avanzan", lateral: "Blanco lateral"
    };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    function el(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text !== undefined) n.textContent = text;
        return n;
    }

    function show(id) { ["menu", "results", "hud"].forEach(function (k) { $(k).classList.toggle("hidden", k !== id); }); }

    function skillText(s) { return s.level + " (" + Math.floor(s.value) + "/1000)"; }

    function glyph(cat) { return { pistol: "PIS", smg: "SMG", shotgun: "ESC", rifle: "FUS" }[cat] || "ARM"; }

    function renderCards() {
        var box = $("cards");
        box.textContent = "";
        var count = 0;
        data.weapons.forEach(function (w) {
            if (filter !== "all" && w.category !== filter) return;
            count++;
            var c = el("div", "card");
            var head = el("div", "card-head");
            head.appendChild(el("div", "glyph", glyph(w.category)));
            var names = el("div");
            names.appendChild(el("div", "card-name", w.name));
            names.appendChild(el("div", "card-cat", w.categoryName));
            head.appendChild(names);
            c.appendChild(head);

            var r1 = el("div", "row");
            r1.appendChild(el("span", "", "Munición: " + w.ammo));
            r1.appendChild(el("span", "badge " + w.skill.key, w.skill.level));
            c.appendChild(r1);

            var track = el("div", "track");
            var fill = el("div", "fill " + w.skill.key);
            track.appendChild(fill);
            c.appendChild(track);
            var next = w.skill.nextLevel ? " → " + w.skill.nextLevel : " (máximo)";
            c.appendChild(el("div", "card-cat", "Habilidad " + Math.floor(w.skill.value) + "/1000" + next));
            setTimeout(function () { fill.style.width = Math.round(w.skill.progress * 100) + "%"; }, 30);

            var btn = el("button", "btn primary", w.ammo > 0 ? "Entrenar" : "Sin munición");
            btn.disabled = w.ammo < 1;
            btn.addEventListener("click", function () { send("rp:range:ui:train", w.item); });
            c.appendChild(btn);
            box.appendChild(c);
        });
        $("empty").classList.toggle("hidden", data.weapons.length > 0);
        $("tabs").classList.toggle("hidden", data.weapons.length === 0);
        if (count === 0 && data.weapons.length > 0) { filter = "all"; renderCards(); }
    }

    function renderTabs() {
        var tabs = $("tabs"), seen = {}, list = [{ key: "all", name: "Todas" }];
        tabs.textContent = "";
        data.weapons.forEach(function (w) {
            if (!seen[w.category]) { seen[w.category] = 1; list.push({ key: w.category, name: w.categoryName }); }
        });
        list.forEach(function (t) {
            var b = el("button", "tab" + (t.key === filter ? " on" : ""), t.name);
            b.addEventListener("click", function () { filter = t.key; renderTabs(); renderCards(); });
            tabs.appendChild(b);
        });
    }

    function tickTime() {
        var now = Date.now();
        if (now < roundStart) {
            $("hud-banner").textContent = "¡Prepárate! " + Math.ceil((roundStart - now) / 1000);
            $("hud-time").textContent = "--";
            return;
        }
        if ($("hud-banner").textContent.indexOf("Prepárate") === 0) $("hud-banner").textContent = "¡Fuego!";
        $("hud-time").textContent = Math.max(0, Math.ceil((roundEnd - now) / 1000)) + "s";
    }

    window.RP = {
        menu: function (d, ui) {
            data = d;
            clearInterval(timer);
            $("menu-title").textContent = ui.title;
            $("menu-sub").textContent = d.location || "";
            $("menu-player").textContent = "";
            var p = el("span");
            p.appendChild(document.createTextNode("Tirador: "));
            p.appendChild(el("b", "", d.player || "-"));
            p.appendChild(document.createTextNode("  ·  " + d.rounds + " rondas por sesión  ·  se gastan tus balas reales"));
            $("menu-player").appendChild(p);
            $("menu-foot").textContent = d.inside ? "Esc: salir del campo" : "Esc: cerrar";
            filter = "all";
            renderTabs();
            renderCards();
            show("menu");
        },
        start: function (info) {
            $("hud-weapon").textContent = info.weapon;
            $("hud-hint").textContent = "F2: salir del entrenamiento";
            RP.hud(info.hud);
            $("hud-banner").textContent = "";
            show("hud");
        },
        round: function (index, total, kind, delayMs, timeMs) {
            roundStart = Date.now() + delayMs;
            roundEnd = roundStart + timeMs;
            $("hud-round").textContent = "Ronda " + index + "/" + total + " · " + (kindNames[kind] || kind);
            clearInterval(timer);
            timer = setInterval(tickTime, 200);
            tickTime();
        },
        hud: function (h) {
            $("hud-ammo").textContent = h.ammo;
            $("hud-score").textContent = h.score;
            $("hud-acc").textContent = h.accuracy + "%";
            $("hud-level").textContent = "Habilidad: " + skillText(h.skill);
            $("hud-bar").className = "fill " + h.skill.key;
            $("hud-bar").style.width = Math.round(h.skill.progress * 100) + "%";
        },
        hit: function (zoneKey, zoneName, points) {
            var t = $("toast");
            t.textContent = "+" + points + " " + zoneName;
            t.classList.remove("show");
            void t.offsetWidth;
            t.classList.add("show");
        },
        results: function (r) {
            clearInterval(timer);
            var reasons = { done: "Sesión completada", ammo: "Sin munición", abort: "Entrenamiento abandonado" };
            $("res-sub").textContent = r.weapon + " · " + (reasons[r.reason] || "");
            var box = $("res-stats");
            box.textContent = "";
            [["Disparos", r.shots], ["Impactos", r.hits], ["Fallos", r.misses], ["Precisión", r.accuracy + "%"], ["Puntuación", r.score]]
                .forEach(function (s) {
                    var d = el("div");
                    d.appendChild(el("small", "", s[0]));
                    d.appendChild(el("b", "", String(s[1])));
                    box.appendChild(d);
                });
            $("res-before").textContent = "Antes: " + skillText(r.before);
            $("res-after").textContent = "Ahora: " + skillText(r.after);
            $("res-bar").className = "fill " + r.before.key;
            $("res-bar").style.width = Math.round(r.before.progress * 100) + "%";
            $("res-bar-new").style.width = "0";
            $("res-gain").textContent = r.gained > 0
                ? "Habilidad +" + r.gained + " puntos (solo impactos válidos)"
                : "Sin progreso: acierta los blancos para mejorar la habilidad.";
            show("results");
            setTimeout(function () {
                $("res-bar-new").style.width = Math.round(r.after.progress * 100) + "%";
                if (r.after.key !== r.before.key) $("res-bar").style.width = "100%";
            }, 60);
        }
    };

    $("menu-close").addEventListener("click", function () { send("rp:range:ui:close"); });
    $("res-exit").addEventListener("click", function () { send("rp:range:ui:close"); });
    $("res-again").addEventListener("click", function () { send("rp:range:ui:again"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" && !$("hud").offsetParent) send("rp:range:ui:close");
    });
})();
