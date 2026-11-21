/*
 * rp_robbery / app.js
 * Negociacion por turnos. Lua llama a:
 *   RP.start(nombreJugador, nombrePolicia)
 *   RP.turn({ lines: [{speaker, text, mood, burst}], options: [{id, label}], status: {...}, done, result })
 * y el JS avisa a Lua con:
 *   rp:robbery:ui:speaker (speaker, mood)   al empezar cada frase (Lua mueve la camara)
 *   rp:robbery:ui:choose (id)               opcion elegida
 *   rp:robbery:ui:closed ()                 se cerro la ultima frase de un turno final
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    function el(tag, className, text) {
        var n = document.createElement(tag);
        if (className) n.className = className;
        if (text !== undefined) n.textContent = text;
        return n;
    }

    // Pitido de la maquina de escribir (WebAudio, sin archivos)
    var audio = null;
    function blip(speaker) {
        try {
            audio = audio || new (window.AudioContext || window.webkitAudioContext)();
            var o = audio.createOscillator(), g = audio.createGain();
            o.type = "square";
            o.frequency.value = speaker === "cop" ? 220 + Math.random() * 30 : 420 + Math.random() * 40;
            g.gain.value = 0.035;
            o.connect(g); g.connect(audio.destination);
            o.start(); o.stop(audio.currentTime + 0.035);
        } catch (e) { /* sin audio */ }
    }
    function sting() {
        try {
            audio = audio || new (window.AudioContext || window.webkitAudioContext)();
            var o = audio.createOscillator(), g = audio.createGain();
            o.type = "sawtooth";
            o.frequency.setValueAtTime(880, audio.currentTime);
            o.frequency.exponentialRampToValueAtTime(110, audio.currentTime + 0.35);
            g.gain.setValueAtTime(0.12, audio.currentTime);
            g.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + 0.4);
            o.connect(g); g.connect(audio.destination);
            o.start(); o.stop(audio.currentTime + 0.4);
        } catch (e) { /* sin audio */ }
    }

    var names = { player: "Tu", cop: "Policia" };
    var queue = [], current = null, typing = null, typed = 0, pending = null, waitingChoice = false;
    var lastStatus = {};

    function setStatus(st) {
        if (!st) return;
        $("status").classList.remove("hidden");
        $("round").textContent = "ronda " + Math.min(st.round, st.maxRounds) + "/" + st.maxRounds;
        function put(id, text, cls, key) {
            var n = $(id);
            n.textContent = text;
            n.className = cls || "";
            if (lastStatus[key] !== undefined && lastStatus[key] !== st[key]) {
                void n.offsetWidth;
                n.classList.add("pulse");
            }
        }
        put("chips", String(st.chips), "", "chips");
        put("seconds", st.seconds + " s", "", "seconds");
        put("traps", st.noTraps ? "SI" : "no", st.noTraps ? "yes" : "no", "noTraps");
        put("tires", st.noTires ? "SI" : "no", st.noTires ? "yes" : "no", "noTires");
        var dots = "";
        for (var i = 0; i < 3; i++) dots += i < st.patience ? "●" : "○";
        put("patience", dots, st.patience <= 1 ? "no" : "", "patience");
        lastStatus = st;
    }

    function burst(text, mood) {
        var b = $("burst");
        $("burst-text").textContent = text;
        b.className = "";
        if (mood === "intro" || mood === "deal") b.classList.add("blue");
        if (mood && mood.indexOf("bluff_ok") === 0) b.classList.add("gold");
        void b.offsetWidth;
        b.classList.add("on");
        var f = $("flash"); f.className = ""; void f.offsetWidth; f.className = "on";
        var l = $("lines"); l.className = ""; void l.offsetWidth; l.className = "on";
        document.body.classList.remove("shake"); void document.body.offsetWidth;
        document.body.classList.add("shake");
        sting();
    }

    function clearOptions() {
        var list = $("options");
        while (list.firstChild) list.removeChild(list.firstChild);
    }

    function showOptions(options) {
        clearOptions();
        waitingChoice = true;
        options.forEach(function (o, i) {
            var li = el("li", o.id);
            li.appendChild(el("span", "key", String(i + 1)));
            li.appendChild(document.createTextNode(o.label));
            li.style.animationDelay = (i * 70) + "ms";
            li.addEventListener("click", function () { choose(o.id); });
            $("options").appendChild(li);
        });
    }

    function choose(id) {
        if (!waitingChoice) return;
        waitingChoice = false;
        clearOptions();
        send("rp:robbery:ui:choose", id);
    }

    function startLine(line) {
        current = line;
        typed = 0;
        var d = $("dialog");
        d.classList.remove("hidden", "ready", "player", "shout", "pop");
        if (line.speaker === "player") d.classList.add("player");
        if (line.burst) d.classList.add("shout");
        void d.offsetWidth;
        d.classList.add("pop");
        $("nameplate").textContent = line.speaker === "cop" ? names.cop : names.player;
        $("text").textContent = "";
        send("rp:robbery:ui:speaker", line.speaker, line.mood || "");
        var delay = 0;
        if (line.burst) { burst(line.burst, line.mood); delay = 700; }
        clearInterval(typing);
        setTimeout(function () {
            if (current !== line) return;
            typing = setInterval(function () {
                typed++;
                $("text").textContent = line.text.slice(0, typed);
                if (typed % 2 === 0 && line.text.charAt(typed - 1) !== " ") blip(line.speaker);
                if (typed >= line.text.length) finishTyping();
            }, 28);
        }, delay);
    }

    function finishTyping() {
        clearInterval(typing);
        typing = null;
        if (!current) return;
        typed = current.text.length;
        $("text").textContent = current.text;
        $("dialog").classList.add("ready");
    }

    function advance() {
        if (!current) return;
        if (typed < current.text.length) return finishTyping();
        if (queue.length > 0) return startLine(queue.shift());
        // fin de las frases de este turno
        current = null;
        $("dialog").classList.remove("ready");
        if (pending.done) {
            send("rp:robbery:ui:closed");
        } else {
            showOptions(pending.options || []);
        }
    }

    $("dialog").addEventListener("click", advance);
    document.addEventListener("keydown", function (e) {
        if (e.key === " " || e.key === "Enter") { e.preventDefault(); advance(); return; }
        var n = parseInt(e.key, 10);
        if (waitingChoice && n >= 1) {
            var items = $("options").children;
            if (items[n - 1]) items[n - 1].click();
        }
    });

    window.RP = {
        start: function (playerName, copName) {
            names.player = playerName || "Tu";
            names.cop = copName || "Policia";
        },
        turn: function (t) {
            pending = t;
            waitingChoice = false;
            clearOptions();
            setStatus(t.status);
            queue = (t.lines || []).slice();
            if (queue.length > 0) startLine(queue.shift());
            else if (t.done) send("rp:robbery:ui:closed");
            else showOptions(t.options || []);
        }
    };

    // Vista previa en un navegador normal
    if (!window.mta) {
        RP.start("Carl Johnson", "Sgto. Ramirez");
        RP.turn({
            lines: [
                { speaker: "cop", text: "¡Atencion, Carl! ¡Habla el Sargento Ramirez! ¡ESTAS rodeado!", mood: "intro", burst: "¡ALTO AHI!" },
                { speaker: "cop", text: "Bien. ¿Que mas quieres?" }
            ],
            options: [
                { id: "seconds", label: "Soltar un rehen: +10 s de ventaja" },
                { id: "traps", label: "Soltar un rehen: sin pinchos ni barricadas" },
                { id: "bluff", label: "Farolear: ¡tengo explosivos!" },
                { id: "deal", label: "Cerrar el trato" },
                { id: "surrender", label: "Rendirse" }
            ],
            status: { chips: 3, seconds: 5, noTraps: false, noTires: false, patience: 3, round: 1, maxRounds: 6 },
            done: false
        });
    }
})();
