/*
 * rp_agency / app.js
 *
 * Vistas: dispensador de turnos, tramite en el mostrador (dialogo con la
 * trabajadora, ficha, foto, firma, DNI, ofertas de trabajo) y tarjeta del DNI.
 *
 * Lua llama a:
 *   RP.dispenser(nombreAgencia, ticketActual|null)
 *   RP.ticketOut(codigo, motivo, personasDelante)
 *   RP.service({ clerk, reason, profile, dni, price, requireDni })
 *   RP.cueDone(nombre)            fin de una animacion pedida con la cue
 *   RP.dniResult(ok, tarjeta|mensaje, precio)
 *   RP.jobs(lista, trabajoActual|null)
 *   RP.jobResult(ok, idTrabajo|mensaje)
 *   RP.switched(motivo, estadoDni)
 *   RP.infoShot(n, total, texto) / RP.infoDone()
 *   RP.card(tarjeta, nombreDeQuienLaMuestra|null)
 *
 * El JS llama a Lua con mta.triggerEvent("rp:agency:ui:<accion>", ...).
 */
(function () {
    "use strict";

    var $ = function (id) { return document.getElementById(id); };

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

    function show(id) { $(id).classList.remove("hidden"); }
    function hide(id) { $(id).classList.add("hidden"); }
    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }

    var view = null;   // "dispenser" | "service" | "card"

    function setView(name) {
        view = name;
        ["dispenser", "service", "cardview"].forEach(function (v) { hide(v); });
        if (name) show(name === "card" ? "cardview" : name);
    }

    /* ================= Dispensador ================= */
    var dispLocked = false;

    function pickReason(reason) {
        if (dispLocked) return;
        dispLocked = true;
        Array.prototype.forEach.call(document.querySelectorAll(".disp-btn"), function (b) { b.disabled = true; });
        send("rp:agency:ui:ticket", reason);
    }

    Array.prototype.forEach.call(document.querySelectorAll(".disp-btn"), function (b) {
        b.addEventListener("click", function () { pickReason(b.getAttribute("data-reason")); });
    });
    $("disp-close").addEventListener("click", function () { send("rp:agency:ui:close"); });

    /* ================= Tarjeta del DNI ================= */
    function drawSignature(canvas, data) {
        var ctx = canvas.getContext("2d");
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        if (!data) return;
        ctx.strokeStyle = "#1a237e";
        ctx.lineWidth = Math.max(1.5, canvas.width / 160);
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        data.split("|").forEach(function (stroke) {
            var pts = stroke.split(";");
            ctx.beginPath();
            pts.forEach(function (p, i) {
                var xy = p.split(",");
                var x = Number(xy[0]) / 99 * canvas.width;
                var y = Number(xy[1]) / 99 * canvas.height;
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            });
            ctx.stroke();
        });
    }

    function buildCard(card) {
        var node = $("card-template").content.firstElementChild.cloneNode(true);
        var parts = String(card.name || "").split(" ");
        var first = parts.shift() || "";
        var f = {
            number: card.number, first: first, last: parts.join(" "),
            gender: card.gender, birth: card.birth, height: (card.height || 0) + " cm",
            issued: card.issued, expires: card.expires, copies: "0" + (card.copies || 1),
            origin: card.origin,
        };
        var surname = (f.last || first).toUpperCase().replace(/[^A-Z]/g, "<");
        f.mrz = ("IDSAN" + card.number + "<<" + surname + "<<" + first.toUpperCase().replace(/[^A-Z]/g, "<") + "<<<<<<<<<<<<<<<<<<<<<<<<").slice(0, 44);
        Array.prototype.forEach.call(node.querySelectorAll("[data-f]"), function (n) {
            n.textContent = f[n.getAttribute("data-f")] || "";
        });
        drawSignature(node.querySelector("canvas"), card.signature);
        return node;
    }

    function closeCard() { if (view === "card") send("rp:agency:ui:close"); }
    $("cardview").addEventListener("click", closeCard);

    /* ================= Dialogo ================= */
    var S = null;          // estado del tramite
    var typing = null;     // { timer, full, done }
    var optionKeys = [];   // callbacks por tecla 1..n

    function setName(name) { $("dialog-name").textContent = name; }

    function clearOptions() { $("dialog-options").innerHTML = ""; optionKeys = []; }

    // La trabajadora dice algo (efecto maquina de escribir). then() al terminar
    function say(text, then) {
        show("dialog");
        hide("dialog-reply");
        clearOptions();
        var node = $("dialog-text");
        node.textContent = "";
        if (typing) clearInterval(typing.timer);
        var i = 0;
        typing = { full: text, done: then };
        typing.timer = setInterval(function () {
            i += 2;
            node.textContent = text.slice(0, i);
            if (i >= text.length) finishTyping();
        }, 28);
    }

    function finishTyping() {
        if (!typing) return;
        clearInterval(typing.timer);
        $("dialog-text").textContent = typing.full;
        var done = typing.done;
        typing = null;
        if (done) done();
    }

    $("dialog").addEventListener("click", function (e) {
        if (e.target.closest(".opt")) return;
        finishTyping();
    });

    // Dice algo y muestra opciones [{label, fn, primary}]
    function ask(text, options) {
        say(text, function () { setOptions(options); });
    }

    function setOptions(options) {
        clearOptions();
        options.forEach(function (o, idx) {
            var b = el("button", "opt" + (o.primary ? " primary" : ""));
            b.appendChild(el("kbd", null, String(idx + 1)));
            b.appendChild(el("span", null, o.label));
            var run = function () {
                if (!optionKeys.length) return;
                clearOptions();
                o.fn();
            };
            b.addEventListener("click", run);
            optionKeys.push(run);
            $("dialog-options").appendChild(b);
        });
    }

    // Respuesta del jugador (burbuja)
    function reply(text) {
        var r = $("dialog-reply");
        r.textContent = "— " + text;
        show("dialog-reply");
    }

    function wait(ms, fn) { setTimeout(fn, ms); }
    function cue(name) { send("rp:agency:ui:cue", name); }

    /* ---------- Ficha ---------- */
    var FIELDS = [
        { key: "name", label: "Nombre completo", q: "¿Me dice su nombre completo, por favor?" },
        { key: "age", label: "Edad", q: "¿Que edad tiene?" },
        { key: "gender", label: "Sexo", q: "¿Sexo?" },
        { key: "origin", label: "Lugar de nacimiento", q: "¿Donde nacio?" },
        { key: "height", label: "Estatura", q: "¿Cuanto mide, mas o menos?" },
    ];

    function answerFor(key) {
        var p = S.profile;
        if (key === "name") return p.name;
        if (key === "age") return p.age + " años";
        if (key === "gender") return p.gender === 1 ? "Mujer" : "Hombre";
        if (key === "origin") return p.origin || "Los Santos";
        if (key === "height") return p.height + " cm";
        return "";
    }

    function openForm(duplicate) {
        $("form-kind").textContent = duplicate ? "DUPLICADO" : "ALTA";
        var dl = $("form-fields");
        dl.innerHTML = "";
        FIELDS.forEach(function (f) {
            dl.appendChild(el("dt", null, f.label));
            var dd = el("dd");
            dd.id = "ff-" + f.key;
            dl.appendChild(dd);
        });
        $("form-photo").classList.remove("taken");
        show("form");
    }

    // Escribe un campo de la ficha letra a letra
    function typeField(key, text, done) {
        var dd = $("ff-" + key);
        dd.classList.add("typing");
        var i = 0;
        var t = setInterval(function () {
            i++;
            dd.textContent = text.slice(0, i);
            if (i >= text.length) {
                clearInterval(t);
                dd.classList.remove("typing");
                if (done) done();
            }
        }, 55);
    }

    /* ---------- Firma ---------- */
    var sign = { strokes: [], current: null, drawing: false };

    function signPoint(e) {
        var c = $("sign-canvas");
        var r = c.getBoundingClientRect();
        var x = Math.max(0, Math.min(99, Math.round((e.clientX - r.left) / r.width * 99)));
        var y = Math.max(0, Math.min(99, Math.round((e.clientY - r.top) / r.height * 99)));
        return [x, y];
    }

    function signEncode() {
        return sign.strokes.filter(function (s) { return s.length > 1; }).map(function (s) {
            return s.map(function (p) { return p[0] + "," + p[1]; }).join(";");
        }).join("|").slice(0, 3900).replace(/[|;,]+$/, "");
    }

    function signRedraw() { drawSignature($("sign-canvas"), signEncode()); }

    function signTotal() {
        return sign.strokes.reduce(function (n, s) { return n + s.length; }, 0);
    }

    $("sign-canvas").addEventListener("mousedown", function (e) {
        sign.drawing = true;
        sign.current = [signPoint(e)];
        sign.strokes.push(sign.current);
    });
    window.addEventListener("mousemove", function (e) {
        if (!sign.drawing) return;
        var p = signPoint(e);
        var last = sign.current[sign.current.length - 1];
        if (Math.abs(p[0] - last[0]) + Math.abs(p[1] - last[1]) < 2) return;
        if (signTotal() > 380) return;   // limite de tamano
        sign.current.push(p);
        signRedraw();
        $("sign-ok").disabled = signTotal() < 12;
    });
    window.addEventListener("mouseup", function () { sign.drawing = false; });
    $("sign-clear").addEventListener("click", function () {
        sign.strokes = [];
        signRedraw();
        $("sign-ok").disabled = true;
    });

    function askSignature(done) {
        sign.strokes = [];
        signRedraw();
        $("sign-ok").disabled = true;
        show("sign");
        $("sign-ok").onclick = function () {
            var data = signEncode();
            if (data.length < 8) return;
            hide("sign");
            done(data);
        };
    }

    /* ---------- Tramite: DNI ---------- */
    function startDni() {
        if (S.dni === "has") {
            return say("Consta un DNI vigente a su nombre y lo lleva encima, asi que no hace falta tramitar otro.", function () { wait(900, menu); });
        }
        if (S.dni === "lost") {
            return ask("Consta un DNI a su nombre, pero no lo lleva. Le puedo imprimir un duplicado por " + money(S.price) + " en efectivo. ¿Lo tramitamos?", [
                { label: "Si, hagame el duplicado", primary: true, fn: function () { reply("Si, por favor."); dniProcess(true); } },
                { label: "No, gracias", fn: function () { reply("No, gracias."); wait(600, menu); } },
            ]);
        }
        dniProcess(false);
    }

    function dniProcess(duplicate) {
        var intro = duplicate ? "De acuerdo. Confirmo sus datos para el duplicado."
                              : "Perfecto, vamos a tramitar su DNI. Le hare unas preguntas.";
        say(intro, function () {
            openForm(duplicate);
            cue("type");
            wait(700, function () { question(0); });
        });
    }

    function question(n) {
        var f = FIELDS[n];
        if (!f) return photo();
        var answer = answerFor(f.key);
        ask(f.q, [{ label: answer, primary: true, fn: function () {
            reply(answer);
            cue("type");
            typeField(f.key, answer, function () { wait(350, function () { question(n + 1); }); });
        } }]);
    }

    function photo() {
        cue("idle");
        ask("Ahora mire a la camara, por favor. Y una sonrisa...", [{ label: "📸 Sonreir", primary: true, fn: function () {
            cue("photo");
            var fl = $("flash");
            fl.classList.remove("go");
            void fl.offsetWidth;
            fl.classList.add("go");
            $("form-photo").classList.add("taken");
            wait(900, function () {
                say("Muy bien, ha salido estupendo. Solo falta su firma.", function () {
                    askSignature(function (sig) {
                        S.signature = sig;
                        reply("(firma)");
                        say("Gracias. Voy a imprimirlo, deme un momento.", function () {
                            wait(900, printDni);
                        });
                    });
                });
            });
        } }]);
    }

    function printDni() {
        hide("dialog");
        hide("form");
        S.waiting = "print";
        cue("print");
    }

    function afterPrint() {
        S.waiting = "dni";
        show("dialog");
        $("dialog-text").textContent = "...";
        clearOptions();
        send("rp:agency:ui:dni", S.signature);
    }

    function dniResult(ok, data, price) {
        if (S.waiting !== "dni") return;
        S.waiting = null;
        if (!ok) {
            return say(String(data), function () { wait(1200, menu); });
        }
        cue("hand");
        S.dni = "has";
        say((price > 0 ? "Son " + money(price) + ". " : "") + "Aqui tiene su DNI. Guardelo bien.", function () {
            var slot = $("reveal-card");
            slot.innerHTML = "";
            slot.appendChild(buildCard(data));
            show("reveal");
            $("reveal-ok").onclick = function () {
                hide("reveal");
                menu();
            };
        });
    }

    /* ---------- Tramite: trabajo ---------- */
    function startJob() {
        if (S.requireDni && S.dni === "none") {
            return ask("Para darle de alta en un trabajo necesito su DNI y no consta ninguno a su nombre. ¿Se lo tramito ahora?", [
                { label: "Si, tramitemos el DNI", primary: true, fn: function () { reply("Si, claro."); send("rp:agency:ui:switch", "dni"); } },
                { label: "Ahora no", fn: function () { reply("Ahora no."); wait(600, menu); } },
            ]);
        }
        say("Veamos que ofertas tenemos hoy...", function () {
            cue("type");
            S.waiting = "jobs";
            send("rp:agency:ui:jobs");
        });
    }

    function renderJobs() {
        var box = $("jobs");
        box.innerHTML = "";
        S.jobs.forEach(function (j) {
            var b = el("button", "job" + (j.id === S.currentJob ? " current" : ""));
            b.appendChild(el("span", "icon", j.icon));
            b.appendChild(el("strong", null, j.name));
            b.appendChild(el("span", "pay", j.pay));
            b.appendChild(el("span", "where", (j.locationName || j.zone || "") + (j.distance ? " · " + j.distance + " km" : "")));
            b.addEventListener("click", function () { pickJob(j); });
            box.appendChild(b);
        });
        show("jobs");
    }

    function jobsArrived(list, current) {
        if (S.waiting !== "jobs") return;
        S.waiting = null;
        S.jobs = list || [];
        S.currentJob = current;
        cue("idle");
        if (!S.jobs.length) return say("Vaya, ahora mismo no hay ofertas. Vuelva mas tarde.", function () { wait(900, menu); });
        renderJobs();
        say("Estas son las ofertas de hoy. Elija una y le cuento los detalles.", function () {
            setOptions([{ label: "Mejor otro dia", fn: function () { hide("jobs"); reply("Mejor otro dia."); wait(500, menu); } }]);
        });
    }

    function pickJob(j) {
        hide("jobs");
        S.job = j;
        reply(j.name);
        var text = j.name + ": " + j.description + " Se paga " + j.pay + "." + (j.requirements ? " Requisitos: " + j.requirements + "." : "") +
                   " ¿Quiere mas informacion, volver atras o lo confirmo?";
        ask(text, jobOptions());
    }

    function jobOptions() {
        return [
            { label: "Mas informacion", fn: function () { reply("Cuenteme mas."); wait(500, jobInfo); } },
            { label: "Volver", fn: function () { renderJobs(); say("Claro, elija otra.", function () {
                setOptions([{ label: "Mejor otro dia", fn: function () { hide("jobs"); wait(300, menu); } }]);
            }); } },
            { label: "Confirmar", primary: true, fn: takeJob },
        ];
    }

    function jobInfo() {
        hide("dialog");
        hide("leave-btn");
        S.waiting = "info";
        send("rp:agency:ui:jobInfo", S.job.id);
    }

    function infoShot(n, total, text) {
        if (S.waiting !== "info") return;
        show("caption");
        $("caption-step").textContent = S.job.name + "  ·  " + n + "/" + total;
        var t = $("caption-text");
        t.textContent = text;
        t.style.animation = "none";
        void t.offsetWidth;
        t.style.animation = "";
    }

    function infoDone() {
        if (S.waiting !== "info") return;
        S.waiting = null;
        hide("caption");
        show("leave-btn");
        ask("Ahi lo tiene: " + S.job.howTo + " ¿Que hacemos?", jobOptions());
    }

    function takeJob() {
        reply("Lo quiero.");
        say("Un segundo, que le doy de alta en el sistema...", function () {
            cue("type");
            S.waiting = "take";
            wait(900, function () { send("rp:agency:ui:jobTake", S.job.id); });
        });
    }

    function jobResult(ok, data) {
        if (S.waiting !== "take") return;
        S.waiting = null;
        cue("idle");
        if (!ok) return say(String(data), function () { wait(1200, menu); });
        S.currentJob = data;
        S.jobDone = true;
        say("¡Listo! Desde hoy trabaja como " + S.job.name + ". Le marque la ubicacion en el mapa. " + S.job.howTo, function () {
            wait(1400, menu);
        });
    }

    /* ---------- Menu y despedida ---------- */
    function menu() {
        var opts = [];
        if (!S.jobDone) opts.push({ label: "Obtener un trabajo", fn: function () { reply("Quiero un trabajo."); send("rp:agency:ui:switch", "job"); } });
        if (S.dni !== "has") opts.push({ label: S.dni === "lost" ? "Duplicado del DNI" : "Tramitar mi DNI", fn: function () { reply("Necesito el DNI."); send("rp:agency:ui:switch", "dni"); } });
        opts.push({ label: "Marcharse", primary: true, fn: bye });
        ask("¿Desea hacer algo mas?", opts);
    }

    function bye() {
        reply("Eso es todo, gracias.");
        cue("bye");
        say("Que tenga un buen dia.", function () { wait(1100, function () { send("rp:agency:ui:leave"); }); });
    }

    $("leave-btn").addEventListener("click", function () {
        if (S && (S.waiting === "print" || S.waiting === "dni" || S.waiting === "take")) return;
        send("rp:agency:ui:leave");
    });

    function route(reason) {
        S.reason = reason;
        if (reason === "dni") startDni(); else startJob();
    }

    /* ================= Teclado ================= */
    document.addEventListener("keydown", function (e) {
        if (view === "dispenser") {
            if (e.key === "1") pickReason("dni");
            else if (e.key === "2") pickReason("job");
            else if (e.key === "Escape") send("rp:agency:ui:close");
        } else if (view === "card") {
            if (e.key === "Escape" || e.key === "Enter") closeCard();
        } else if (view === "service") {
            var n = parseInt(e.key, 10);
            if (n >= 1 && optionKeys[n - 1]) optionKeys[n - 1]();
            else if (e.key === " " || e.key === "Enter") finishTyping();
        }
    });

    /* ================= API para Lua ================= */
    window.RP = {
        dispenser: function (agency, current) {
            setView("dispenser");
            dispLocked = false;
            $("disp-agency").textContent = agency;
            $("ticket").className = "ticket";
            hide("disp-result");
            show("disp-question");
            show("disp-options");
            Array.prototype.forEach.call(document.querySelectorAll(".disp-btn"), function (b) { b.disabled = !!current; });
        },

        ticketOut: function (code, label, ahead) {
            $("ticket-num").textContent = code;
            $("ticket-label").textContent = label;
            var t = $("ticket");
            t.className = "ticket out";
            setTimeout(function () { t.className = "ticket torn"; }, 1500);
            hide("disp-options");
            hide("disp-question");
            var r = $("disp-result");
            r.innerHTML = "";
            r.appendChild(document.createTextNode("Su turno es "));
            r.appendChild(el("b", null, code));
            r.appendChild(el("br"));
            r.appendChild(document.createTextNode(ahead > 0
                ? "Hay " + ahead + (ahead === 1 ? " persona" : " personas") + " delante. Espere a que le llamen."
                : "No hay nadie delante: le llamaran enseguida."));
            show("disp-result");
        },

        service: function (data) {
            setView("service");
            S = { clerk: data.clerk, reason: data.reason, profile: data.profile || {}, dni: data.dni,
                  price: data.price, requireDni: data.requireDni, jobs: [], waiting: null };
            ["form", "jobs", "sign", "reveal", "caption"].forEach(hide);
            show("leave-btn");
            setName(data.clerk + " · Agencia de Empleo");
            var hello = (S.profile.gender === 1 ? "Bienvenida" : "Bienvenido") + " a la Agencia de Empleo y Registro Civil. Soy " + data.clerk + ". ¿En que le puedo ayudar?";
            say(hello, function () {
                reply(data.reason === "dni" ? "Vengo a sacarme el DNI." : "Busco trabajo.");
                wait(900, function () { route(data.reason); });
            });
        },

        cueDone: function (name) {
            if (name === "print" && S && S.waiting === "print") afterPrint();
        },

        dniResult: function (ok, data, price) { if (S) dniResult(ok, data, price); },
        jobs: function (list, current) { if (S) jobsArrived(list, current); },
        jobResult: function (ok, data) { if (S) jobResult(ok, data); },
        switched: function (reason, dni) { if (S) { S.dni = dni; route(reason); } },
        infoShot: function (n, total, text) { if (S) infoShot(n, total, text); },
        infoDone: function () { if (S) infoDone(); },

        card: function (card, owner) {
            setView("card");
            $("card-owner").textContent = owner ? owner + " te muestra su DNI" : "";
            var slot = $("card-slot");
            slot.innerHTML = "";
            slot.appendChild(buildCard(card));
        },
    };

    // Vista previa fuera del juego: abre index.html?demo=dispenser|service|card
    if (!window.mta) {
        var demo = (location.search.match(/demo=(\w+)/) || [])[1];
        var card = { number: "12345678Z", name: "Carlos Mendez Rivera", gender: "M", birth: "14/03/1998", origin: "Los Santos",
                     height: 178, issued: "20/11/2026", expires: "20/11/2036", copies: 1, signature: "10,60;20,30;30,70;40,35;50,65;60,40|65,60;90,55" };
        if (demo === "dispenser") { RP.dispenser("Agencia de Empleo y Registro Civil", null); setTimeout(function () { RP.ticketOut("D-07", "Obtencion de DNI", 2); }, 1500); }
        if (demo === "card") RP.card(card, "Carlos Mendez");
        if (demo === "service") {
            document.body.style.background = "#556";
            RP.service({ clerk: "Marta", reason: "dni", dni: "none", price: 50, requireDni: true,
                         profile: { name: "Carlos Mendez", age: 28, gender: 0, origin: "Los Santos", height: 178 } });
            var origSend = send;
            send = function (name, a) {
                origSend.apply(null, arguments);
                if (name === "rp:agency:ui:cue" && a === "print") setTimeout(function () { RP.cueDone("print"); }, 1500);
                if (name === "rp:agency:ui:dni") setTimeout(function () { RP.dniResult(true, card, 0); }, 600);
            };
        }
    }
})();
