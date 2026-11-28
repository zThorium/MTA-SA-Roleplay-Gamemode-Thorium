/* rp_quiz / app.js — muestra las preguntas y manda los índices elegidos; corrige el servidor. */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var data = null, answers = [], i = 0, result = null, waitTimer = null;

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
    }
    function sound(n) { try { var a = new Audio("sounds/" + n + ".ogg"); a.volume = .5; a.play(); } catch (e) { } }
    function el(t, c, txt) { var e = document.createElement(t); if (c) e.className = c; if (txt !== undefined) e.textContent = txt; return e; }

    function show() {
        var q = data.questions[i];
        $("count").textContent = "Pregunta " + (i + 1) + " de " + data.questions.length;
        $("question").textContent = q.text;
        $("bar").style.width = (i / data.questions.length * 100) + "%";
        var box = $("options");
        box.innerHTML = "";
        q.options.forEach(function (o, k) {
            var b = el("button", "option" + (answers[i] === k + 1 ? " sel" : ""));
            b.appendChild(el("b", null, "ABCD".charAt(k)));
            b.appendChild(document.createTextNode(o));
            b.onclick = function () { answers[i] = k + 1; sound("select_002"); show(); };
            box.appendChild(b);
        });
        $("prev").disabled = i === 0;
        var last = i === data.questions.length - 1;
        $("next").textContent = last ? "Enviar respuestas" : "Siguiente";
        $("next").disabled = !answers[i];
    }

    function waitThen(seconds) {
        var btn = $("r-action");
        clearInterval(waitTimer);
        if (seconds <= 0) { btn.disabled = false; btn.textContent = "Intentar otra vez"; return; }
        btn.disabled = true;
        var left = seconds;
        btn.textContent = "Intentar otra vez (" + left + ")";
        waitTimer = setInterval(function () {
            left--;
            if (left <= 0) { clearInterval(waitTimer); btn.disabled = false; btn.textContent = "Intentar otra vez"; }
            else btn.textContent = "Intentar otra vez (" + left + ")";
        }, 1000);
    }

    window.Quiz = {
        open: function (d) {
            data = d; answers = []; i = 0; result = null;
            $("pass").textContent = d.pass;
            $("card").classList.remove("hidden");
            $("quiz").classList.remove("hidden");
            $("result").classList.add("hidden");
            $("intro").classList.remove("hidden");
            sound("maximize_003");
            show();
            if (d.wait > 0) { Quiz.result({ ok: false, correct: 0, total: d.questions.length, pass: d.pass, wrong: [], wait: d.wait, cooling: true }); }
        },
        result: function (r) {
            result = r;
            $("quiz").classList.add("hidden");
            $("result").classList.remove("hidden");
            $("bar").style.width = "100%";
            $("badge").textContent = r.ok ? "✓" : "✕";
            $("badge").classList.toggle("bad", !r.ok);
            $("r-title").textContent = r.ok ? "¡Aprobado!" : (r.cooling ? "Espera un momento" : "Casi");
            $("r-text").textContent = r.ok
                ? r.correct + " de " + r.total + " aciertos. Ya puedes crear tu personaje. Recuerda: F1 tiene las reglas y la ayuda."
                : (r.cooling ? "Podrás repetir el cuestionario en unos segundos." : r.correct + " de " + r.total + " aciertos; necesitas " + r.pass + ". Repasa estas:");
            var ul = $("wrong");
            ul.innerHTML = "";
            (r.wrong || []).forEach(function (w) {
                var li = el("li");
                li.appendChild(el("b", null, w.text));
                li.appendChild(el("span", null, "✓ " + w.right));
                li.appendChild(document.createElement("br"));
                li.appendChild(el("em", null, w.why));
                ul.appendChild(li);
            });
            sound(r.ok ? "confirmation_003" : "error_004");
            if (r.ok) { $("r-action").disabled = false; $("r-action").textContent = "Crear mi personaje"; }
            else waitThen(r.wait || 0);
        }
    };

    $("prev").onclick = function () { if (i > 0) { i--; sound("click_002"); show(); } };
    $("next").onclick = function () {
        if (!answers[i]) return;
        sound("click_002");
        if (i < data.questions.length - 1) { i++; show(); return; }
        $("next").disabled = true;
        send("rp:quiz:ui:submit", JSON.stringify(answers));
    };
    $("r-action").onclick = function () {
        if (!result) return;
        sound("click_002");
        if (result.ok) { $("card").classList.add("hidden"); send("rp:quiz:ui:close"); }
        else send("rp:quiz:ui:retry");
    };
    document.addEventListener("keydown", function (e) {
        if ($("quiz").classList.contains("hidden") || !data) return;
        var n = { "1": 1, "2": 2, "3": 3, "4": 4, "a": 1, "b": 2, "c": 3, "d": 4 }[e.key.toLowerCase()];
        if (n && n <= data.questions[i].options.length) { answers[i] = n; sound("select_002"); show(); }
        if (e.key === "Enter" && answers[i]) $("next").click();
    });

    // Vista previa sin MTA: index.html#demo / #demo-fail
    if (!window.mta && location.hash.indexOf("#demo") === 0) {
        Quiz.open({ pass: 7, wait: 0, questions: [
            { text: "¿Qué es el MetaGaming (MG)?", options: ["Jugar mucho tiempo seguido", "Usar en el rol información que tu personaje no conoce", "Hablar por el chat OOC", "Robar un banco"] },
            { text: "¿Qué diferencia hay entre IC y OOC?", options: ["Ninguna", "IC es el chat de admins", "OOC es lo que hace tu personaje", "IC es tu personaje; OOC eres tú"] }
        ] });
        answers[0] = 2; show();
        if (location.hash === "#demo-fail") Quiz.result({ ok: false, correct: 5, total: 8, pass: 7, wait: 30, wrong: [
            { text: "¿Qué es el PowerGaming (PG)?", right: "Forzar acciones irreales o no dar opción al otro jugador", why: "PG es hacer lo imposible o imponer el resultado al otro." }] });
    }
})();
