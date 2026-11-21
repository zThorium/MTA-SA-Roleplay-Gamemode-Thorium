/*
 * rp_help / app.js
 * Lua llama a:
 *   RP.boot(contenido)            una vez, al cargar (reglas, conceptos, teclas... de s_config.lua)
 *   RP.show(tab|false, jugadores) cada vez que se muestra el panel
 *   RP.setPlayers(jugadores), RP.setMyReports(lista), RP.reportResult(ok, mensaje)
 * Y recibe: rp:help:ui:close, :discord, :players, :myReports, :report(categoria, indice, texto)
 *
 * El navegador no se destruye al cerrar: el estado (pestana, formulario) se conserva.
 */
(function () {
    "use strict";

    var $ = function (id) { return document.getElementById(id); };
    var data = null;
    var tab = "home";
    var players = [];
    var myReports = null;
    var form = { category: "", target: "", text: "", msg: "", ok: false, sending: false };
    var query = "";

    var TABS = [
        { id: "home",     ico: "⌂", label: "Inicio" },
        { id: "guide",    ico: "⚑", label: "Guia para nuevos" },
        { id: "rules",    ico: "⚖", label: "Reglas" },
        { id: "concepts", ico: "ℹ", label: "Conceptos de rol" },
        { id: "keys",     ico: "⌨", label: "Teclas" },
        { id: "commands", ico: "/",      label: "Comandos" },
        { id: "report",   ico: "⚠", label: "Reportar" }
    ];
    var SEARCHABLE = { rules: true, concepts: true, keys: true, commands: true };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined && text !== null) node.textContent = text;
        return node;
    }
    function button(text, className, onClick) {
        var b = el("button", className, text);
        b.type = "button";
        b.addEventListener("click", onClick);
        return b;
    }
    function matches() {
        if (!query) return true;
        for (var i = 0; i < arguments.length; i++) {
            if (String(arguments[i] || "").toLowerCase().indexOf(query) !== -1) return true;
        }
        return false;
    }

    function setTab(id) {
        tab = id;
        query = "";
        $("search").value = "";
        if (id === "report") { send("rp:help:ui:players"); send("rp:help:ui:myReports"); }
        render();
        $("panel").scrollTop = 0;
    }

    function renderTabs() {
        var nav = $("tabs");
        nav.innerHTML = "";
        TABS.forEach(function (t) {
            var b = button("", t.id === tab ? "active" : "", function () { setTab(t.id); });
            b.appendChild(el("span", "ico", t.ico));
            b.appendChild(el("span", null, t.label));
            nav.appendChild(b);
        });
    }

    // ---------------------------------------------------------------- Inicio
    function renderHome(panel) {
        panel.appendChild(el("p", "lead", data.welcome));
        var cards = el("div", "cards");
        [
            ["guide", "⚑", "Soy nuevo", "Los primeros pasos en la ciudad, en orden."],
            ["rules", "⚖", "Reglas", "Lo que esta permitido y lo que no."],
            ["concepts", "ℹ", "Conceptos de rol", "MG, PG, DM, PK, CK... explicados con ejemplos."],
            ["keys", "⌨", "Teclas", "Todas las teclas del servidor de un vistazo."],
            ["commands", "/", "Comandos", "Comandos utiles para el dia a dia."],
            ["report", "⚠", "Reportar a un jugador", "Avisa al staff de un problema. Queda registrado."]
        ].forEach(function (c) {
            var card = button("", "card", function () { setTab(c[0]); });
            card.appendChild(el("span", "ico", c[1]));
            card.appendChild(el("strong", null, c[2]));
            card.appendChild(el("p", null, c[3]));
            cards.appendChild(card);
        });
        panel.appendChild(cards);
        panel.appendChild(el("div", "notice", "Consejo: usa el buscador de arriba en Reglas, Conceptos, Teclas y Comandos. Tambien puedes abrir este panel con /ayuda y el formulario de reporte con /reportar."));
    }

    // ---------------------------------------------------------------- Listas
    function renderNumbered(panel, list, intro) {
        if (intro) panel.appendChild(el("p", "lead", intro));
        var shown = 0;
        list.forEach(function (r, i) {
            if (!matches(r.title, r.text)) return;
            var item = el("div", "item");
            item.appendChild(el("span", "num", String(i + 1)));
            var body = el("div");
            body.appendChild(el("h3", null, r.title));
            body.appendChild(el("p", null, r.text));
            item.appendChild(body);
            panel.appendChild(item);
            shown++;
        });
        if (!shown) panel.appendChild(el("p", "empty", "Nada coincide con la busqueda."));
    }

    function renderGuide(panel) {
        panel.appendChild(el("p", "lead", "Si es tu primera vez, sigue estos pasos. Puedes volver aqui cuando quieras con F1."));
        data.guide.forEach(function (g) {
            var item = el("div", "item");
            var body = el("div");
            body.appendChild(el("h3", null, g.title));
            body.appendChild(el("p", null, g.text));
            item.appendChild(body);
            panel.appendChild(item);
        });
    }

    function renderConcepts(panel) {
        panel.appendChild(el("p", "lead", "Las siglas que vas a leer en el servidor. Romper estos conceptos es motivo de sancion."));
        var grid = el("div", "concepts");
        var shown = 0;
        data.concepts.forEach(function (c) {
            if (!matches(c.tag, c.name, c.text)) return;
            var box = el("div", "concept");
            box.appendChild(el("span", "tag", c.tag));
            var body = el("div");
            body.appendChild(el("h3", null, c.name));
            body.appendChild(el("p", null, c.text));
            box.appendChild(body);
            grid.appendChild(box);
            shown++;
        });
        panel.appendChild(shown ? grid : el("p", "empty", "Nada coincide con la busqueda."));
    }

    function renderKeys(panel) {
        var shown = 0;
        data.keys.forEach(function (g) {
            var rows = el("div", "rows");
            g.items.forEach(function (k) {
                if (!matches(k.key, k.text, g.group)) return;
                var row = el("div", "row");
                var keyCell = el("div", "k");
                keyCell.appendChild(el("kbd", null, k.key));
                row.appendChild(keyCell);
                row.appendChild(el("span", null, k.text));
                rows.appendChild(row);
            });
            if (!rows.children.length) return;
            panel.appendChild(el("h3", "section-title", g.group));
            panel.appendChild(rows);
            shown++;
        });
        if (!shown) panel.appendChild(el("p", "empty", "Nada coincide con la busqueda."));
        else panel.appendChild(el("div", "notice", "Las teclas de vehiculo se pueden cambiar en Ajustes > Binds de MTA."));
    }

    function renderCommands(panel) {
        var rows = el("div", "rows");
        data.commands.forEach(function (c) {
            if (!matches(c.cmd, c.text)) return;
            var row = el("div", "row");
            row.appendChild(el("code", null, c.cmd));
            row.appendChild(el("span", null, c.text));
            rows.appendChild(row);
        });
        panel.appendChild(rows.children.length ? rows : el("p", "empty", "Nada coincide con la busqueda."));
    }

    // ---------------------------------------------------------------- Reportar
    function renderReport(panel) {
        panel.appendChild(el("p", "lead", "Cuentanos que paso con el mayor detalle posible (hora, lugar, que hizo). El staff conectado lo recibe al instante y queda guardado. Abusar de los reportes tambien se sanciona."));

        var box = el("div", "report");

        var catLabel = el("label", null, "Motivo");
        var cat = el("select");
        cat.appendChild(new Option("Elige un motivo...", ""));
        data.categories.forEach(function (c) { cat.appendChild(new Option(c.label, c.id)); });
        cat.value = form.category;
        cat.addEventListener("change", function () { form.category = cat.value; });
        catLabel.appendChild(cat);
        box.appendChild(catLabel);

        var tLabel = el("label", null, "Jugador reportado");
        var wrap = el("div", "with-btn");
        var target = el("select");
        target.appendChild(new Option("Ninguno (bug u otro)", ""));
        players.forEach(function (p) { target.appendChild(new Option("(" + p.id + ") " + p.name, String(p.index))); });
        target.value = form.target;
        if (target.value !== form.target) form.target = "";   // ya no esta en la lista
        target.addEventListener("change", function () { form.target = target.value; });
        wrap.appendChild(target);
        wrap.appendChild(button("↻", "btn", function () { send("rp:help:ui:players"); }));
        tLabel.appendChild(wrap);
        box.appendChild(tLabel);

        var txtLabel = el("label", "full", "Que ocurrio");
        var txt = el("textarea");
        txt.maxLength = data.maxText;
        txt.placeholder = "Ej.: Me atropello varias veces en Pershing Square sin ningun rol previo, sobre las 18:30.";
        txt.value = form.text;
        var counter = el("span", "counter");
        function updateCounter() {
            var n = txt.value.trim().length;
            counter.textContent = n + " / " + data.maxText;
            counter.className = "counter" + (n > 0 && n < data.minText ? " bad" : "");
        }
        txt.addEventListener("input", function () { form.text = txt.value; updateCounter(); });
        updateCounter();
        txtLabel.appendChild(txt);
        txtLabel.appendChild(counter);
        box.appendChild(txtLabel);

        var actions = el("div", "actions full");
        var msg = el("span", "msg" + (form.msg ? (form.ok ? " ok" : " err") : ""), form.msg);
        actions.appendChild(msg);
        var submit = button(form.sending ? "Enviando..." : "Enviar reporte", "btn primary", function () {
            if (form.sending) return;
            var text = txt.value.trim();
            if (!form.category) return showMsg("Elige un motivo.", false);
            if (text.length < data.minText) return showMsg("Describe lo ocurrido (minimo " + data.minText + " caracteres).", false);
            form.sending = true;
            form.msg = "";
            send("rp:help:ui:report", form.category, form.target, text);
            render();
        });
        submit.disabled = form.sending;
        actions.appendChild(submit);
        box.appendChild(actions);
        panel.appendChild(box);

        panel.appendChild(el("h3", "section-title", "Mis reportes"));
        var my = el("div", "my");
        if (myReports === null) my.appendChild(el("p", "empty", "Cargando..."));
        else if (!myReports.length) my.appendChild(el("p", "empty", "Todavia no enviaste ningun reporte."));
        else myReports.forEach(function (r) {
            var item = el("div", "my-item");
            var top = el("div", "top");
            top.appendChild(el("strong", null, "#" + r.id));
            top.appendChild(el("span", "badge " + r.status, r.statusLabel));
            top.appendChild(el("span", null, r.category + (r.target ? " · " + r.target : "")));
            top.appendChild(el("span", "date", r.date));
            item.appendChild(top);
            item.appendChild(el("p", null, r.text));
            if (r.handledBy) item.appendChild(el("span", "note", (r.status === "closed" ? "Cerrado por " : "Atendido por ") + r.handledBy + (r.note ? ": " + r.note : "")));
            my.appendChild(item);
        });
        panel.appendChild(my);
    }

    function showMsg(text, ok) {
        form.msg = text;
        form.ok = ok;
        render();
    }

    // ---------------------------------------------------------------- Render
    var RENDER = { home: renderHome, guide: renderGuide, rules: function (p) { renderNumbered(p, data.rules, "Al jugar en el servidor aceptas estas reglas. El desconocimiento no exime de la sancion."); },
        concepts: renderConcepts, keys: renderKeys, commands: renderCommands, report: renderReport };

    function render() {
        if (!data) return;
        renderTabs();
        var current = TABS.filter(function (t) { return t.id === tab; })[0];
        $("title").textContent = current ? current.label : "";
        $("search").className = SEARCHABLE[tab] ? "" : "hidden";
        var panel = $("panel");
        var scroll = panel.scrollTop;
        panel.innerHTML = "";
        RENDER[tab](panel);
        panel.scrollTop = scroll;
    }

    $("search").addEventListener("input", function () {
        query = this.value.trim().toLowerCase();
        render();
    });
    $("btn-close").addEventListener("click", function () { send("rp:help:ui:close"); });
    $("btn-discord").addEventListener("click", function () { send("rp:help:ui:discord"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" || e.key === "F1") { e.preventDefault(); send("rp:help:ui:close"); }
    });

    window.RP = {
        boot: function (d) {
            data = d;
            $("server-name").textContent = d.serverName;
            $("discord-sub").textContent = d.hasDiscord ? "Copiar enlace de invitacion" : "Proximamente";
            render();
        },
        show: function (t, list) {
            players = list || [];
            var w = $("window");
            w.classList.remove("enter");
            void w.offsetWidth;   // reinicia la animacion de entrada
            w.classList.add("enter");
            if (t && RENDER[t]) setTab(t);
            else if (tab === "report") setTab("report");
            else render();
        },
        setPlayers: function (list) {
            players = list || [];
            if (tab === "report") render();
        },
        setMyReports: function (list) {
            myReports = list || [];
            if (tab === "report") render();
        },
        reportResult: function (ok, message) {
            form.sending = false;
            if (ok) { form.category = ""; form.target = ""; form.text = ""; }
            showMsg(message, ok);
        }
    };
})();
