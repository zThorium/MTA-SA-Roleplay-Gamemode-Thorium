/*
 * rp_factions / app.js
 * Lua llama a RP.render(datos). Las secciones que el rol no puede ver no
 * llegan en los datos (members/log/bank = false) y aqui no se muestran.
 * Acciones: mta.triggerEvent("rp:fac:ui:action", accion, JSON).
 */
(function () {
    "use strict";

    var $ = function (id) { return document.getElementById(id); };
    var data = null;
    var tab = "summary";
    var editing = null;        // rol en edicion (objeto) o {} para uno nuevo
    var confirmKick = null;    // characterId pendiente de confirmar

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }
    function action(name, payload) { send("rp:fac:ui:action", name, JSON.stringify([payload || {}])); }

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
    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }
    function has(perm) { return data.me.leader || data.me.perms.indexOf(perm) !== -1; }
    function maxLevel() { return data.me.leader ? 99 : Math.max(0, data.me.level - 1); }

    var TABS = [
        { id: "summary", label: "Resumen", visible: function () { return true; } },
        { id: "members", label: "Miembros", visible: function () { return data.members !== false || has("invite"); } },
        { id: "ranks", label: "Roles y permisos", visible: function () { return has("manage_ranks"); } },
        { id: "bank", label: "Fondos", visible: function () { return data.faction.bank !== false || has("bank_deposit"); } },
        { id: "invoices", label: "Facturas", visible: function () { return has("bill") || has("log_view"); } },
        { id: "log", label: "Registro", visible: function () { return data.log !== false; } }
    ];

    function renderTabs() {
        var nav = $("tabs");
        nav.innerHTML = "";
        var current = TABS.filter(function (t) { return t.id === tab && t.visible(); })[0];
        if (!current) tab = "summary";
        TABS.forEach(function (t) {
            if (!t.visible()) return;
            var b = button(t.label, t.id === tab ? "active" : "", function () {
                tab = t.id; editing = null; confirmKick = null; if (tab === "invoices") { invoices = null; action("invoices"); }
                render();
            });
            nav.appendChild(b);
            if (t.id === tab) $("title").textContent = t.label;
        });
    }

    // ---------------------------------------------------------- Resumen
    function card(label, value, className) {
        var c = el("div", "card");
        c.appendChild(el("span", "label", label));
        c.appendChild(el("strong", className, value));
        return c;
    }

    function renderSummary(panel) {
        var f = data.faction;
        var cards = el("div", "cards");
        cards.appendChild(card("Miembros en linea", String(f.online)));
        cards.appendChild(card("Tu sueldo por payday", money(data.me.salary), "money"));
        cards.appendChild(card(f.bank !== false ? "Fondos" : "Sueldos pagados por", f.bank !== false ? money(f.bank) : (f.stateFunded ? "El Estado" : "La faccion"), f.bank !== false ? "money" : ""));
        panel.appendChild(cards);

        var box = el("div", "box");
        box.appendChild(el("h3", null, "Anuncio"));
        if (has("edit_motd")) {
            var area = el("textarea");
            area.maxLength = 200;
            area.value = f.motd || "";
            area.placeholder = "Escribe un anuncio para todos los miembros";
            box.appendChild(area);
            var row = el("div", "row");
            row.appendChild(button("Guardar anuncio", "primary", function () { action("motd", { text: area.value }); }));
            box.appendChild(row);
        } else {
            box.appendChild(el("p", f.motd ? "motd" : "muted", f.motd || "Sin anuncios."));
        }
        panel.appendChild(box);

        var info = el("div", "box");
        info.appendChild(el("h3", null, "Tu acceso"));
        var labels = (data.permissions || []).map(function (p) { return p.label; });
        info.appendChild(el("p", "muted", data.me.leader ? "Eres el lider: tienes todos los permisos." :
            (labels.length ? "Tu rol te permite: " + labels.join(", ") + "." : "Tu rol no tiene permisos de gestion.")));
        info.appendChild(el("p", "muted", "Usa /f <mensaje> para hablar por el canal de la faccion."));
        if (!data.me.leader) {
            var leave = button("Dejar la faccion", "danger small", function () {
                if (leave.dataset.confirm) return action("leave");
                leave.dataset.confirm = "1";
                leave.textContent = "Pulsa otra vez para confirmar";
            });
            var r = el("div", "row"); r.appendChild(leave); info.appendChild(r);
        }
        panel.appendChild(info);
    }

    // ---------------------------------------------------------- Miembros
    function renderMembers(panel) {
        if (has("invite")) {
            var box = el("div", "box");
            box.appendChild(el("h3", null, "Invitar a un jugador"));
            var row = el("div", "row");
            var input = el("input");
            input.placeholder = "ID del jugador";
            input.maxLength = 24;
            row.appendChild(input);
            row.appendChild(button("Enviar invitacion", "primary", function () {
                if (input.value.trim()) action("invite", { target: input.value.trim() });
                input.value = "";
            }));
            box.appendChild(row);
            panel.appendChild(box);
        }
        if (data.members === false) return;

        var assignable = (data.ranks || []).filter(function (r) { return r.editable; });
        var table = el("table");
        var head = el("tr");
        ["Nombre", "Rol", "Ultima vez", ""].forEach(function (h) { head.appendChild(el("th", null, h)); });
        table.appendChild(head);

        data.members.forEach(function (m) {
            var tr = el("tr");
            var name = el("td");
            name.appendChild(el("span", "dot" + (m.online ? " on" : "")));
            name.appendChild(document.createTextNode(m.name));
            if (m.leader) name.appendChild(el("span", "badge", "Lider"));
            tr.appendChild(name);
            tr.appendChild(el("td", null, m.rank));
            tr.appendChild(el("td", "muted", m.online ? "En linea" : (m.lastPlayed || "-")));

            var actions = el("td");
            var wrap = el("div", "actions");
            if (m.manageable && has("set_rank") && assignable.length) {
                var sel = el("select");
                assignable.forEach(function (r) {
                    var o = el("option", null, r.name);
                    o.value = r.id;
                    if (r.id === m.rankId) o.selected = true;
                    sel.appendChild(o);
                });
                sel.addEventListener("change", function () {
                    action("setRank", { characterId: m.characterId, rankId: Number(sel.value) });
                });
                wrap.appendChild(sel);
            }
            if (m.manageable && has("kick")) {
                var pending = confirmKick === m.characterId;
                wrap.appendChild(button(pending ? "Confirmar" : "Expulsar", "danger small", function () {
                    if (pending) { confirmKick = null; action("kick", { characterId: m.characterId }); }
                    else { confirmKick = m.characterId; render(); }
                }));
            }
            actions.appendChild(wrap);
            tr.appendChild(actions);
            table.appendChild(tr);
        });
        var box2 = el("div", "box");
        box2.appendChild(el("h3", null, data.members.length + " miembros"));
        box2.appendChild(table);
        panel.appendChild(box2);
    }

    // ---------------------------------------------------------- Roles
    function permLabel(key) {
        var p = (data.permissions || []).filter(function (x) { return x.key === key; })[0];
        return p ? p.label : key;
    }

    function renderRankEditor(panel) {
        var r = editing;
        var box = el("div", "box");
        box.appendChild(el("h3", null, r.id ? "Editar rol " + r.name : "Nuevo rol"));

        var grid = el("div", "editor");
        function field(label, input) { var l = el("label", null, label); l.appendChild(input); grid.appendChild(l); return input; }
        var name = field("Nombre", el("input"));
        name.maxLength = 24; name.value = r.name || "";
        var level = field("Nivel (1-" + maxLevel() + ")", el("input"));
        level.type = "number"; level.min = 1; level.max = maxLevel(); level.value = r.level || 1;
        var salary = field("Sueldo por payday", el("input"));
        salary.type = "number"; salary.min = 0; salary.max = 5000; salary.value = r.salary || 0;
        var commission = field("Comision al facturar (%)", el("input"));
        commission.type = "number"; commission.min = 0; commission.max = 50; commission.value = r.commission || 0;
        box.appendChild(grid);
        box.appendChild(el("p", "muted", "El nivel define la jerarquia: un rol solo gestiona a los de nivel inferior. Solo puedes conceder permisos que tienes."));

        var perms = el("div", "permgrid");
        var current = r.perms || [];
        var checks = [];
        (data.permissions || []).forEach(function (p) {
            var lab = el("label", "perm");
            var c = el("input"); c.type = "checkbox"; c.value = p.key; c.checked = current.indexOf(p.key) !== -1;
            checks.push(c);
            var t = el("div"); t.appendChild(el("b", null, p.label)); t.appendChild(el("span", null, p.description));
            lab.appendChild(c); lab.appendChild(t);
            perms.appendChild(lab);
        });
        box.appendChild(perms);

        var row = el("div", "row");
        row.appendChild(button("Guardar rol", "primary", function () {
            action("rankSave", {
                id: r.id || null, name: name.value.trim(), level: Number(level.value), salary: Number(salary.value),
                commission: Number(commission.value) || 0,
                perms: checks.filter(function (c) { return c.checked; }).map(function (c) { return c.value; })
            });
            editing = null;
        }));
        row.appendChild(button("Cancelar", "ghost", function () { editing = null; render(); }));
        box.appendChild(row);
        panel.appendChild(box);
    }

    function renderRanks(panel) {
        if (editing) return renderRankEditor(panel);
        var top = el("div", "row");
        top.appendChild(el("p", "muted", "Define los roles de tu faccion, que puede hacer cada uno y cuanto cobra en cada payday."));
        if (maxLevel() >= 1) top.appendChild(button("+ Nuevo rol", "primary", function () { editing = {}; render(); }));
        panel.appendChild(top);

        var list = el("div", "ranks");
        (data.ranks || []).forEach(function (r) {
            var row = el("div", "rank");
            var info = el("div");
            info.appendChild(el("h4", null, r.name));
            var perms = (r.perms || []).map(permLabel);
            info.appendChild(el("div", "perms", perms.length ? perms.join(" · ") : "Sin permisos"));
            row.appendChild(info);
            row.appendChild(el("span", "level", "Nivel " + r.level));
            row.appendChild(el("span", "money", money(r.salary)));
            var actions = el("div", "actions");
            if (r.editable) {
                actions.appendChild(button("Editar", "ghost small", function () { editing = r; render(); }));
                actions.appendChild(button("Borrar", "danger small", function (e) {
                    var b = e.currentTarget;
                    if (b.dataset.confirm) return action("rankDelete", { id: r.id });
                    b.dataset.confirm = "1"; b.textContent = "Confirmar";
                }));
            } else {
                actions.appendChild(el("span", "muted", "Superior"));
            }
            row.appendChild(actions);
            list.appendChild(row);
        });
        panel.appendChild(list);
    }

    // ---------------------------------------------------------- Fondos
    function renderBank(panel) {
        var f = data.faction;
        var cards = el("div", "cards");
        if (f.bank !== false) cards.appendChild(card("Fondos de la faccion", money(f.bank), "money"));
        cards.appendChild(card("Tu efectivo", money(data.me.cash), "money"));
        cards.appendChild(card("Sueldos", f.stateFunded ? "Los paga el Estado" : "Salen de los fondos"));
        panel.appendChild(cards);

        function op(title, perm, name) {
            if (!has(perm)) return;
            var box = el("div", "box");
            box.appendChild(el("h3", null, title));
            var row = el("div", "row");
            var input = el("input"); input.type = "number"; input.min = 1; input.placeholder = "Cantidad";
            row.appendChild(input);
            row.appendChild(button(title, "primary", function () {
                var n = Math.floor(Number(input.value));
                if (n > 0) action(name, { amount: n });
                input.value = "";
            }));
            box.appendChild(row);
            panel.appendChild(box);
        }
        op("Depositar", "bank_deposit", "deposit");
        op("Retirar", "bank_withdraw", "withdraw");
        if (!f.stateFunded) panel.appendChild(el("p", "muted", "Si los fondos no alcanzan para el sueldo de un miembro, ese payday lo cubre el sueldo base del Estado."));
    }

    // ---------------------------------------------------------- Facturas
    var invoices = null;   // datos de rp:fac:invoices (se piden al abrir la pestaña)
    var STATUS = { pending: "Pendiente", paid: "Pagada", rejected: "Rechazada", expired: "Caducada" };
    function renderInvoices(panel) {
        var help = el("div", "box");
        help.appendChild(el("h3", null, "Cobrar a un cliente"));
        help.appendChild(el("p", "muted", has("bill")
            ? "Junto al cliente escribe /facturar <id> <monto> <concepto>. El cliente paga en efectivo o con el banco; el dinero va a los fondos y tu rol se lleva su comision."
            : "Tu rol no puede facturar; el lider lo activa con el permiso Facturar."));
        panel.appendChild(help);
        if (!invoices) { panel.appendChild(el("p", "muted", "Cargando...")); return; }

        var box = el("div", "box");
        box.appendChild(el("h3", null, (invoices.full ? "Aporte por miembro" : "Tu aporte") + " (ultimos " + invoices.days + " dias)"));
        var table = el("table", "table");
        var head = el("tr");
        ["Miembro", "Facturado", "Facturas", "Comision", "Ultima"].forEach(function (h) { head.appendChild(el("th", null, h)); });
        table.appendChild(head);
        if (!invoices.members.length) {
            var tr0 = el("tr"); var td0 = el("td", "muted", "Aun no hay facturas pagadas."); td0.colSpan = 5; tr0.appendChild(td0); table.appendChild(tr0);
        }
        invoices.members.forEach(function (m) {
            var tr = el("tr");
            [m.name, money(m.total), String(m.count), money(m.commission), m.last || "-"].forEach(function (v) { tr.appendChild(el("td", null, v)); });
            table.appendChild(tr);
        });
        box.appendChild(table);
        panel.appendChild(box);

        var box2 = el("div", "box");
        box2.appendChild(el("h3", null, "Ultimas facturas"));
        var list = el("ul", "log");
        if (!invoices.recent.length) list.appendChild(el("li", "muted", "Sin facturas."));
        invoices.recent.forEach(function (i) {
            var li = el("li");
            li.appendChild(el("span", "date", i.date));
            li.appendChild(el("span", null, "#" + i.id + " · " + i.employee + " → " + i.client + " · " + money(i.amount) + " · " + i.concept
                + " · " + (STATUS[i.status] || i.status) + (i.method ? " (" + (i.method === "cash" ? "efectivo" : "banco") + ")" : "")));
            list.appendChild(li);
        });
        box2.appendChild(list);
        panel.appendChild(box2);
    }

    // ---------------------------------------------------------- Registro
    function renderLog(panel) {
        var box = el("div", "box");
        var list = el("ul", "log");
        if (!data.log.length) list.appendChild(el("li", "muted", "Sin actividad."));
        data.log.forEach(function (row) {
            var li = el("li");
            li.appendChild(el("span", "date", row.date));
            li.appendChild(el("span", null, row.text));
            list.appendChild(li);
        });
        box.appendChild(list);
        panel.appendChild(box);
    }

    function render() {
        if (!data) return;
        var f = data.faction;
        document.documentElement.style.setProperty("--accent", f.color || "#f5a524");
        $("f-tag").textContent = f.tag;
        $("f-name").textContent = f.name;
        $("f-type").textContent = f.typeName;
        $("me-rank").textContent = data.me.leader ? data.me.rank + " (lider)" : data.me.rank;
        $("me-salary").textContent = "Sueldo: " + money(data.me.salary);
        renderTabs();

        var panel = $("panel");
        panel.innerHTML = "";
        ({ summary: renderSummary, members: renderMembers, ranks: renderRanks, bank: renderBank, invoices: renderInvoices, log: renderLog })[tab](panel);
    }

    $("btn-close").addEventListener("click", function () { send("rp:fac:ui:close"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" || e.key === "F3") { e.preventDefault(); send("rp:fac:ui:close"); }
    });

    window.RP = {
        invoices: function (d) { invoices = d; if (tab === "invoices" && !editing) render(); },
        render: function (d) {
            // Mientras se edita un rol no se redibuja (no se pierde lo escrito); se vera al guardar o cancelar
            data = d;
            if (editing) return;
            render();
        }
    };
})();
