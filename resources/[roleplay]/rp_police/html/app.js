/*
 * rp_police / app.js
 * Lua llama a RP.open(modo, datos) y RP.update(tipo, datos). Modos: mdt, search,
 * armory, garage, lab, form. Las acciones salen por mta.triggerEvent("rp:pol:ui:action", ...)
 * y el servidor las valida. Todo el texto entra con textContent (nunca innerHTML).
 */
(function () {
    "use strict";

    var $ = function (id) { return document.getElementById(id); };
    var mode = null, data = {}, tab = "citizens";
    var live = {};            // datos recibidos por update: citizens, profile, vehicle, bolos, dispatch, units, evidence, lab
    var resultsEl = null;     // contenedor que se redibuja en las pestanas del MDT

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }
    function act(name, payload) { send("rp:pol:ui:action", name, JSON.stringify([payload || {}])); }

    function el(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text !== undefined && text !== null) n.textContent = text;
        return n;
    }
    function btn(text, cls, fn) {
        var b = el("button", "btn" + (cls ? " " + cls : ""), text);
        b.type = "button";
        b.addEventListener("click", fn);
        return b;
    }
    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }
    function clear(n) { while (n.firstChild) n.removeChild(n.firstChild); return n; }
    function tag(text, cls) { return el("span", "tag " + (cls || ""), text); }
    function empty(text) { return el("div", "empty", text); }
    function kv(k, v) { var d = el("div", "kv"); d.appendChild(el("span", "", k)); d.appendChild(el("span", "", v)); return d; }
    function field(label, input) { var w = el("div"); w.appendChild(el("label", "", label)); w.appendChild(input); return w; }
    function input(type, ph, max) {
        var i = el("input"); i.type = type; i.placeholder = ph || ""; if (max) i.maxLength = max; return i;
    }

    function setHeader(title, sub, tabs) {
        $("title").textContent = title;
        $("subtitle").textContent = sub || "";
        var nav = clear($("tabs"));
        (tabs || []).forEach(function (t) {
            var b = el("button", t.id === tab ? "active" : "", t.label);
            b.type = "button";
            b.addEventListener("click", function () { tab = t.id; if (t.load) act(t.load); renderMDT(); });
            nav.appendChild(b);
        });
        $("window").className = "window" + (mode === "form" || mode === "garage" ? " small" : "");
    }

    /* ---------- MDT ---------- */
    function renderMDT() {
        var tabs = [
            { id: "citizens", label: "Ciudadanos" },
            { id: "vehicles", label: "Vehiculos" },
            { id: "bolos", label: "BOLO y ordenes", load: "mdt_bolos" },
            { id: "dispatch", label: "Despacho", load: "mdt_dispatch" },
            { id: "units", label: "Unidades", load: "mdt_units" }
        ];
        if (data.perms && data.perms.evidence) tabs.push({ id: "evidence", label: "Evidencia", load: "mdt_evidence" });
        setHeader("MDT - Terminal de datos", data.me ? data.me.rank + " " + data.me.name : "", tabs);
        var body = clear($("body"));
        var view = { citizens: viewCitizens, vehicles: viewVehicles, bolos: viewBolos, dispatch: viewDispatch, units: viewUnits, evidence: viewEvidence }[tab];
        view(body);
    }

    function viewCitizens(body) {
        var row = el("div", "row");
        var q = input("text", "Nombre o apellido del ciudadano", 32);
        var go = function () { if (q.value.trim().length >= 2) { live.profile = null; act("mdt_search", { q: q.value }); } };
        q.addEventListener("keydown", function (e) { if (e.key === "Enter") go(); });
        row.appendChild(q);
        row.appendChild(btn("Buscar", "", go));
        body.appendChild(row);
        resultsEl = el("div");
        body.appendChild(resultsEl);
        drawCitizens();
        setTimeout(function () { q.focus(); }, 50);
    }

    function drawCitizens() {
        if (tab !== "citizens" || !resultsEl) return;
        clear(resultsEl);
        if (live.profile) return drawProfile(resultsEl, live.profile);
        var list = live.citizens || [];
        if (!live.citizens) return resultsEl.appendChild(empty("Busca un ciudadano por nombre."));
        if (!list.length) return resultsEl.appendChild(empty("Sin resultados."));
        var l = el("div", "list");
        list.forEach(function (c) {
            var it = el("div", "item click");
            it.appendChild(el("div", "ic", c.gender === 1 ? "👩" : "👨"));
            var m = el("div", "main");
            m.appendChild(el("div", "name", c.name));
            m.appendChild(el("div", "meta", c.age + " anos - ID civil #" + c.id));
            it.appendChild(m);
            it.addEventListener("click", function () { act("mdt_profile", { id: c.id }); });
            l.appendChild(it);
        });
        resultsEl.appendChild(l);
    }

    function recordRow(r) {
        var it = el("div", "item");
        var label = { arrest: "ARRESTO", fine: "MULTA", note: "NOTA" }[r.kind] || r.kind;
        it.appendChild(tag(label, r.kind === "arrest" ? "danger" : r.kind === "fine" ? "warn" : "blue"));
        var m = el("div", "main");
        m.appendChild(el("div", "name", r.text));
        var extra = r.kind === "arrest" ? r.minutes + " min" : r.kind === "fine" ? money(r.amount) + (r.paid ? " (pagada)" : " (PENDIENTE)") : "";
        m.appendChild(el("div", "meta", [r.at, r.officer, extra].filter(Boolean).join(" - ")));
        it.appendChild(m);
        return it;
    }

    function drawProfile(root, p) {
        root.appendChild(btn("← Volver a resultados", "ghost", function () { live.profile = null; drawCitizens(); }));
        if (p.warrants.length) {
            var ab = el("div", "alert-banner", "ORDEN DE CAPTURA ACTIVA: " + p.warrants.map(function (w) { return w.description; }).join(" | "));
            ab.style.marginTop = "12px";
            root.appendChild(ab);
        }
        var g = el("div", "grid2");
        g.style.marginTop = "12px";
        var a = el("div", "card");
        a.appendChild(el("h2", "", p.name));
        a.appendChild(kv("Edad", p.age + " anos"));
        a.appendChild(kv("Genero", p.gender === 1 ? "Femenino" : "Masculino"));
        a.appendChild(kv("Origen", p.origin));
        a.appendChild(kv("Registrado", p.since));
        a.appendChild(kv("Licencia de conducir", p.license ? p.license.number + " (" + (p.license.status === "valid" ? "vigente" : p.license.status) + ")" : "No tiene"));
        a.appendChild(kv("Multas pendientes", money(p.unpaid)));
        g.appendChild(a);
        var b = el("div", "card");
        b.appendChild(el("h2", "", "Bienes"));
        b.appendChild(el("h3", "", "Vehiculos (" + p.vehicles.length + ")"));
        if (!p.vehicles.length) b.appendChild(el("div", "meta", "Ninguno"));
        p.vehicles.forEach(function (v) { b.appendChild(kv(v.name, v.plate)); });
        b.appendChild(el("h3", "", "Propiedades (" + p.properties.length + ")"));
        if (!p.properties.length) b.appendChild(el("div", "meta", "Ninguna"));
        p.properties.forEach(function (h) { b.appendChild(kv(h.name, h.type)); });
        g.appendChild(b);
        root.appendChild(g);

        root.appendChild(el("h3", "", "Antecedentes"));
        var l = el("div", "list");
        if (!p.records.length) l.appendChild(empty("Sin antecedentes."));
        p.records.forEach(function (r) { l.appendChild(recordRow(r)); });
        root.appendChild(l);

        if (data.perms && data.perms.fine) {
            root.appendChild(el("h3", "", "Agregar nota"));
            var row = el("div", "row");
            var n = input("text", "Nota para el historial", 200);
            row.appendChild(n);
            row.appendChild(btn("Guardar", "", function () { act("record_add", { id: p.id, text: n.value }); }));
            root.appendChild(row);
        }
    }

    function viewVehicles(body) {
        var row = el("div", "row");
        var q = input("text", "Matricula", 8);
        var go = function () { if (q.value.trim().length >= 2) act("mdt_vehicle", { plate: q.value }); };
        q.addEventListener("keydown", function (e) { if (e.key === "Enter") go(); });
        row.appendChild(q);
        row.appendChild(btn("Consultar", "", go));
        body.appendChild(row);
        resultsEl = el("div");
        body.appendChild(resultsEl);
        drawVehicle();
        setTimeout(function () { q.focus(); }, 50);
    }

    function drawVehicle() {
        if (tab !== "vehicles" || !resultsEl) return;
        clear(resultsEl);
        var v = live.vehicle;
        if (!v) return resultsEl.appendChild(empty("Consulta una matricula."));
        if (!v.found) return resultsEl.appendChild(empty("La matricula " + v.plate + " no esta registrada."));
        if (v.bolo) resultsEl.appendChild(el("div", "alert-banner", "BOLO ACTIVO: " + v.bolo));
        var c = el("div", "card");
        c.appendChild(el("h2", "", v.plate + " - " + v.name));
        c.appendChild(kv("Propietario", v.owner));
        c.appendChild(kv("Multas pendientes", money(v.unpaid)));
        c.appendChild(kv("Cepo", v.clamped ? "Si" : "No"));
        resultsEl.appendChild(c);
        resultsEl.appendChild(el("div", "meta", "Para ver los antecedentes del propietario, buscalo en Ciudadanos.")).style.marginTop = "10px";
    }

    function viewBolos(body) {
        if (data.perms && data.perms.bolo) {
            var card = el("div", "card");
            card.appendChild(el("h2", "", "Emitir BOLO / orden de captura"));
            var kind = el("select");
            [["person", "Persona (orden de captura)"], ["vehicle", "Vehiculo (BOLO)"]].forEach(function (o) {
                var op = el("option", "", o[1]); op.value = o[0]; kind.appendChild(op);
            });
            var subject = input("text", "Nombre Apellido o matricula", 40);
            var desc = input("text", "Descripcion y motivo", 200);
            var reward = input("number", "Recompensa ($)", 6);
            reward.min = 0;
            card.appendChild(field("Tipo", kind));
            card.appendChild(field("Sujeto", subject));
            card.appendChild(field("Descripcion", desc));
            card.appendChild(field("Recompensa", reward));
            var r = el("div", "row"); r.style.marginTop = "12px";
            r.appendChild(btn("Emitir", "", function () {
                act("bolo_add", { kind: kind.value, subject: subject.value, description: desc.value, reward: reward.value || 0 });
                subject.value = ""; desc.value = ""; reward.value = "";
            }));
            card.appendChild(r);
            body.appendChild(card);
        }
        body.appendChild(el("h3", "", "Activos"));
        resultsEl = el("div");
        body.appendChild(resultsEl);
        drawBolos();
    }

    function drawBolos() {
        if (tab !== "bolos" || !resultsEl) return;
        clear(resultsEl);
        var list = live.bolos;
        if (!list) return resultsEl.appendChild(empty("Cargando..."));
        if (!list.length) return resultsEl.appendChild(empty("No hay BOLO activos."));
        var l = el("div", "list");
        list.forEach(function (b) {
            var it = el("div", "item");
            it.appendChild(tag(b.warrant ? "ORDEN" : b.kind === "vehicle" ? "VEHICULO" : "PERSONA", b.warrant ? "danger" : "warn"));
            var m = el("div", "main");
            m.appendChild(el("div", "name", b.subject));
            m.appendChild(el("div", "meta", b.description + " - " + b.officer + " " + b.at + (b.reward > 0 ? " - Recompensa " + money(b.reward) : "")));
            it.appendChild(m);
            if (data.perms && data.perms.bolo) it.appendChild(btn("Cancelar", "ghost", function () { act("bolo_close", { id: b.id }); }));
            l.appendChild(it);
        });
        resultsEl.appendChild(l);
    }

    function viewDispatch(body) {
        resultsEl = el("div");
        body.appendChild(resultsEl);
        drawDispatch();
    }

    function drawDispatch() {
        if (tab !== "dispatch" || !resultsEl) return;
        clear(resultsEl);
        var list = live.dispatch || data.alerts || [];
        if (!list.length) return resultsEl.appendChild(empty("Sin avisos recientes."));
        var l = el("div", "list");
        list.forEach(function (a) {
            var it = el("div", "item");
            it.appendChild(tag(a.code, "danger"));
            var m = el("div", "main");
            m.appendChild(el("div", "name", a.title + " - " + a.zone));
            m.appendChild(el("div", "meta", (a.desc || "Sin descripcion") + (a.responders ? " - " + a.responders + " unidad(es) respondiendo" : "")));
            it.appendChild(m);
            it.appendChild(btn("Responder", "", function () { act("alert_respond", { id: a.id }); }));
            l.appendChild(it);
        });
        resultsEl.appendChild(l);
    }

    function viewUnits(body) {
        resultsEl = el("div");
        body.appendChild(resultsEl);
        drawUnits();
    }

    function drawUnits() {
        if (tab !== "units" || !resultsEl) return;
        clear(resultsEl);
        var list = live.units;
        if (!list) return resultsEl.appendChild(empty("Cargando..."));
        var l = el("div", "list");
        list.forEach(function (u) {
            var it = el("div", "item");
            it.appendChild(el("div", "ic", "👮"));
            var m = el("div", "main");
            m.appendChild(el("div", "name", u.name + " (ID " + u.id + ")"));
            m.appendChild(el("div", "meta", u.rank + " - " + u.zone + " - " + u.vehicle));
            it.appendChild(m);
            l.appendChild(it);
        });
        resultsEl.appendChild(l);
    }

    function viewEvidence(body) {
        resultsEl = el("div");
        body.appendChild(resultsEl);
        drawEvidence();
    }

    function evidenceRow(e, withAction) {
        var it = el("div", "item");
        it.appendChild(el("div", "ic", e.kind === "blood" ? "🩸" : "🔸"));
        var m = el("div", "main");
        m.appendChild(el("div", "name", "#" + e.id + " " + e.detail));
        m.appendChild(el("div", "meta", e.location + " - recolectada por " + e.by + " (" + e.at + ")" + (e.result ? " - Resultado: " + e.result : "")));
        it.appendChild(m);
        if (withAction) it.appendChild(btn("Analizar", "", function () { act("lab_analyze", { id: e.id }); }));
        else it.appendChild(tag(e.result ? "ANALIZADA" : "PENDIENTE", e.result ? "ok" : "warn"));
        return it;
    }

    function drawEvidence() {
        if (tab !== "evidence" || !resultsEl) return;
        clear(resultsEl);
        var ev = live.evidence;
        if (!ev) return resultsEl.appendChild(empty("Cargando..."));
        var all = ev.pending.concat(ev.done);
        if (!all.length) return resultsEl.appendChild(empty("No hay evidencia registrada."));
        var l = el("div", "list");
        all.forEach(function (e) { l.appendChild(evidenceRow(e, false)); });
        resultsEl.appendChild(l);
    }

    /* ---------- Cacheo ---------- */
    function renderSearch() {
        setHeader("Cacheo", data.name, []);
        var body = clear($("body"));
        body.appendChild(el("div", "meta", "Efectivo: " + money(data.cash) + " (no se puede decomisar desde aqui)."));
        body.appendChild(el("h3", "", "Objetos"));
        if (!data.items.length) return body.appendChild(empty("No lleva nada encima."));
        var l = el("div", "list");
        data.items.forEach(function (i) {
            var it = el("div", "item");
            it.appendChild(el("div", "ic", i.icon || "📦"));
            var m = el("div", "main");
            m.appendChild(el("div", "name", i.name + " x" + i.amount));
            it.appendChild(m);
            if (i.police) it.appendChild(tag("EQUIPO LSPD", "blue"));
            it.appendChild(btn("Decomisar 1", "ghost", function () { act("seize", { item: i.id, amount: 1 }); }));
            if (i.amount > 1) it.appendChild(btn("Todo", "danger", function () { act("seize", { item: i.id, amount: i.amount }); }));
            l.appendChild(it);
        });
        body.appendChild(l);
    }

    /* ---------- Armeria ---------- */
    function renderArmory() {
        setHeader("Armeria", "Nivel de rol " + data.level + " - Efectivo " + money(data.cash), []);
        var body = clear($("body"));
        var l = el("div", "list");
        data.items.forEach(function (i) {
            var it = el("div", "item" + (i.locked ? " locked" : ""));
            it.appendChild(el("div", "ic", i.icon || "📦"));
            var m = el("div", "main");
            m.appendChild(el("div", "name", i.name + (i.amount > 1 ? " x" + i.amount : "")));
            m.appendChild(el("div", "meta", i.description + (i.have ? " - Llevas " + i.have : "")));
            it.appendChild(m);
            if (i.locked) it.appendChild(tag("Nivel " + i.level, "danger"));
            else it.appendChild(tag(i.issued ? "Equipo del Estado" : money(i.price), i.issued ? "ok" : "warn"));
            var b = btn(i.issued ? "Retirar" : "Comprar", "", function () { act("armory_buy", { item: i.item }); });
            b.disabled = !!i.locked;
            it.appendChild(b);
            l.appendChild(it);
        });
        body.appendChild(l);
    }

    /* ---------- Garaje ---------- */
    function renderGarage() {
        setHeader("Garaje policial", "Nivel de rol " + data.level, []);
        var body = clear($("body"));
        var l = el("div", "list");
        data.vehicles.forEach(function (v) {
            var it = el("div", "item" + (v.locked ? " locked" : ""));
            it.appendChild(el("div", "ic", "🚓"));
            var m = el("div", "main");
            m.appendChild(el("div", "name", v.name));
            it.appendChild(m);
            if (v.locked) it.appendChild(tag("Nivel " + v.level, "danger"));
            var b = btn("Sacar", "", function () { act("garage_spawn", { model: v.model }); });
            b.disabled = !!v.locked;
            it.appendChild(b);
            l.appendChild(it);
        });
        body.appendChild(l);
        var r = el("div", "row"); r.style.marginTop = "14px";
        var ret = btn("Devolver mi vehiculo", "ghost", function () { act("garage_return"); });
        ret.disabled = !data.hasVehicle;
        r.appendChild(ret);
        body.appendChild(r);
    }

    /* ---------- Laboratorio ---------- */
    function renderLab() {
        setHeader("Laboratorio forense", "Analiza la evidencia recolectada", []);
        var body = clear($("body"));
        var ev = live.lab || data;
        body.appendChild(el("h3", "", "Por analizar (" + ev.pending.length + ")"));
        var l = el("div", "list");
        if (!ev.pending.length) l.appendChild(empty("No hay evidencia pendiente."));
        ev.pending.forEach(function (e) { l.appendChild(evidenceRow(e, true)); });
        body.appendChild(l);
        body.appendChild(el("h3", "", "Analizadas"));
        var d = el("div", "list");
        if (!ev.done.length) d.appendChild(empty("Todavia no hay resultados."));
        ev.done.forEach(function (e) { d.appendChild(evidenceRow(e, false)); });
        body.appendChild(d);
    }

    /* ---------- Formularios (multa y arresto) ---------- */
    function renderForm() {
        var fine = data.kind === "fine";
        setHeader(fine ? "Multar" : "Arrestar", data.name, []);
        var body = clear($("body"));
        var amount, minutes, reason = el("textarea");
        reason.maxLength = fine ? 120 : 200;
        reason.placeholder = fine ? "Motivo de la multa" : "Cargos";
        if (fine) {
            amount = input("number", "Monto", 5);
            amount.min = 1; amount.max = data.max;
            body.appendChild(field("Monto (maximo " + money(data.max) + ")", amount));
        } else {
            minutes = input("number", "Minutos", 3);
            minutes.min = 1; minutes.max = data.maxMin;
            amount = input("number", "Multa opcional", 5);
            amount.min = 0; amount.max = data.max;
            body.appendChild(field("Condena en minutos (maximo " + data.maxMin + ")", minutes));
            body.appendChild(field("Multa adicional (opcional)", amount));
        }
        body.appendChild(field(fine ? "Motivo" : "Cargos", reason));
        var row = el("div", "row"); row.style.marginTop = "14px";
        row.appendChild(btn(fine ? "Cobrar multa" : "Encarcelar", fine ? "" : "danger", function () {
            if (fine) act("form_fine", { amount: amount.value, reason: reason.value });
            else act("form_arrest", { minutes: minutes.value, fine: amount.value || 0, reason: reason.value });
        }));
        row.appendChild(btn("Cancelar", "ghost", function () { send("rp:pol:ui:cancel"); }));
        body.appendChild(row);
        setTimeout(function () { (minutes || amount).focus(); }, 50);
    }

    /* ---------- API para Lua ---------- */
    function render() {
        resultsEl = null;
        ({ mdt: renderMDT, search: renderSearch, armory: renderArmory, garage: renderGarage, lab: renderLab, form: renderForm })[mode]();
    }

    window.RP = {
        open: function (m, d) {
            mode = m; data = d || {}; live = {}; tab = "citizens";
            render();
        },
        update: function (kind, d) {
            if (kind === "citizens") { live.citizens = d.list; live.profile = null; drawCitizens(); }
            else if (kind === "profile") { live.profile = d; if (tab === "citizens") drawCitizens(); }
            else if (kind === "vehicle") { live.vehicle = d; drawVehicle(); }
            else if (kind === "bolos") { live.bolos = d.list; drawBolos(); }
            else if (kind === "dispatch") { live.dispatch = d.list; drawDispatch(); }
            else if (kind === "units") { live.units = d.list; drawUnits(); }
            else if (kind === "evidence") { live.evidence = d; drawEvidence(); }
            else if (kind === "lab") { live.lab = d; if (mode === "lab") renderLab(); }
            else if (kind === "armory") { data = d; if (mode === "armory") renderArmory(); }
            else if (kind === "garage") { for (var k in d) data[k] = d[k]; if (mode === "garage") renderGarage(); }
            else if (kind === "search") { data = d; if (mode === "search") renderSearch(); }
        }
    };

    $("btn-close").addEventListener("click", function () { send("rp:pol:ui:cancel"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" || e.key === "F6") send("rp:pol:ui:cancel");
    });
})();
