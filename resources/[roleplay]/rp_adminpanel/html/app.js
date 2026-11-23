/*
 * rp_adminpanel / app.js
 * Lua llama a RP.on(tipo, datos). Tipos: open, dash, players, accounts, iam, logs.
 * El JS solo pinta y pide; el servidor valida cada permiso.
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var state = { me: null, catalog: [], dash: null, players: [], accounts: [], iam: null, logs: [], tab: "dash", sel: null };
    var pollTimer = null, renderedSel = null;

    var ICON = {
        dash: "M3 12l9-8 9 8M5 10v10h5v-6h4v6h5V10",
        players: "M16 11a4 4 0 1 0-8 0M4 21a8 8 0 0 1 16 0",
        accounts: "M4 6h16M4 12h16M4 18h10",
        iam: "M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z",
        logs: "M6 3h9l4 4v14H6zM9 12h7M9 16h7",
        commands: "M5 8l4 4-4 4M12 17h7",
        user: "M16 11a4 4 0 1 0-8 0M4 21a8 8 0 0 1 16 0",
        book: "M5 4h10a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3zM8 4v13",
        wallet: "M3 7h15a3 3 0 0 1 3 3v7a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3zM3 7l11-3v3M16 13h2",
        car: "M4 16l1.5-5a2 2 0 0 1 2-1.5h9a2 2 0 0 1 2 1.5L20 16M4 16v3h3v-2h10v2h3v-3M4 16h16",
        home: "M3 11l9-7 9 7v9h-6v-6H9v6H3z",
        flag: "M5 21V4m0 1h12l-2 4 2 4H5",
        bolt: "M13 3L5 14h6l-1 7 8-11h-6z"
    };
    function icon(name) {
        return '<svg viewBox="0 0 24 24"><path d="' + (ICON[name] || "") + '"/></svg>';
    }

    var TABS = [
        { id: "dash", name: "Dashboard", sub: "Resumen del servidor en tiempo real", icon: "dash", perm: null },
        { id: "players", name: "Jugadores", sub: "Jugadores en linea, vista 3D y acciones", icon: "players", perm: "players.view" },
        { id: "accounts", name: "Cuentas", sub: "Busqueda de cuentas y asignacion de rangos", icon: "accounts", perm: "accounts.view" },
        { id: "iam", name: "Permisos (IAM)", sub: "Control de acceso por rango y por cuenta", icon: "iam", perm: "iam.manage" },
        { id: "logs", name: "Auditoria", sub: "Registro de acciones administrativas", icon: "logs", perm: "logs.view" },
        { id: "commands", name: "Comandos", sub: "Catalogo de comandos de administracion", icon: "commands", perm: "commands.view" }
    ];

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }
    function req(kind, a, b, c) { send("rp:adminpanel:ui:req", kind, a === undefined ? "" : a, b === undefined ? "" : b, c === undefined ? "" : c); }
    function el(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text !== undefined) n.textContent = text;
        return n;
    }
    function btn(label, cls, fn) { var b = el("button", "btn " + (cls || ""), label); b.addEventListener("click", fn); return b; }
    function can(perm) { return !perm || (state.me && state.me.perms.indexOf(perm) !== -1); }
    function roleName(l) {
        if (state.iam && state.iam.roleNames[l]) return state.iam.roleNames[l];
        return ["Jugador", "Admin", "Admin senior", "Super admin"][l] || ("Nivel " + l);
    }
    function badge(l) { return el("span", "badge l" + l, roleName(l)); }
    function num(n) { return (Number(n) || 0).toLocaleString("es"); }
    function money(n) { return "$" + num(n); }
    function uptime(s) {
        var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d ? d + " d " : "") + h + " h " + m + " min";
    }

    /* ---------------- Navegacion ---------------- */
    function setTab(id) {
        state.tab = id;
        send("rp:adminpanel:ui:preview", "", 0, 0, 0, 0, 0);   // oculta el 3D
        clearInterval(pollTimer);
        renderedSel = null;
        $("search").value = "";
        $("search").style.visibility = (id === "dash" || id === "iam") ? "hidden" : "visible";
        $("search").placeholder = id === "accounts" ? "Buscar cuenta y pulsar Enter..." : "Filtrar...";
        var t = TABS.filter(function (x) { return x.id === id; })[0];
        $("page-title").textContent = t.name;
        $("page-sub").textContent = t.sub;
        if (id === "dash") { req("dash"); if (can("logs.view")) req("logs"); pollTimer = setInterval(function () { req("dash"); }, 10000); }
        if (id === "players") { req("players"); pollTimer = setInterval(function () { req("players"); }, 3000); }
        if (id === "accounts") req("accounts", "");
        if (id === "iam") req("iam");
        if (id === "logs") req("logs");
        renderTabs();
        render();
    }

    function renderTabs() {
        var box = $("tabs");
        box.textContent = "";
        TABS.forEach(function (t) {
            if (!can(t.perm)) return;
            var b = el("button", "tab" + (t.id === state.tab ? " active" : ""));
            b.innerHTML = icon(t.icon);
            b.appendChild(el("span", "", t.name));
            b.addEventListener("click", function () { setTab(t.id); });
            box.appendChild(b);
        });
    }

    function render() {
        var v = $("view"), keep = v.scrollTop, listEl = v.querySelector(".list"), keepList = listEl ? listEl.scrollTop : 0;
        v.textContent = "";
        v.style.overflowY = state.tab === "players" ? "hidden" : "auto";
        document.documentElement.classList.remove("scene");
        $("count").textContent = "";
        ({ dash: renderDash, players: renderPlayers, accounts: renderAccounts, iam: renderIam, logs: renderLogs, commands: renderCommands }[state.tab])(v);
        v.scrollTop = keep;
        var l2 = v.querySelector(".list"); if (l2) l2.scrollTop = keepList;
    }

    /* ---------------- Graficos (SVG propio, sin librerias) ---------------- */
    var BLUE = "#1d63d8";

    function lineChart(seriesList, colors) {
        var W = 600, H = 190, L = 34, R = 10, T = 10, B = 24;
        var max = 1;
        seriesList.forEach(function (s) { s.forEach(function (p) { if (p.n > max) max = p.n; }); });
        max = Math.ceil(max * 1.15);
        var n = seriesList[0].length, step = (W - L - R) / Math.max(1, n - 1);
        var out = '<svg class="chart" viewBox="0 0 ' + W + " " + H + '" preserveAspectRatio="none">';
        for (var g = 0; g <= 4; g++) {
            var y = T + (H - T - B) * g / 4;
            out += '<line class="axis" x1="' + L + '" x2="' + (W - R) + '" y1="' + y + '" y2="' + y + '"/>';
            out += '<text x="' + (L - 6) + '" y="' + (y + 3) + '" text-anchor="end">' + Math.round(max * (4 - g) / 4) + "</text>";
        }
        seriesList[0].forEach(function (p, i) {
            out += '<text x="' + (L + step * i) + '" y="' + (H - 6) + '" text-anchor="middle">' + p.d + "</text>";
        });
        seriesList.forEach(function (s, si) {
            var pts = s.map(function (p, i) { return (L + step * i) + "," + (T + (H - T - B) * (1 - p.n / max)); });
            if (si === 0) out += '<polygon points="' + L + "," + (H - B) + " " + pts.join(" ") + " " + (L + step * (n - 1)) + "," + (H - B) + '" fill="' + colors[si] + '" opacity="0.10"/>';
            out += '<polyline points="' + pts.join(" ") + '" fill="none" stroke="' + colors[si] + '" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>';
            pts.forEach(function (p) { var c = p.split(","); out += '<circle cx="' + c[0] + '" cy="' + c[1] + '" r="3.5" fill="#fff" stroke="' + colors[si] + '" stroke-width="2"/>'; });
        });
        return out + "</svg>";
    }

    function barChart(s, color) {
        var W = 600, H = 190, L = 34, R = 10, T = 10, B = 24, max = 1;
        s.forEach(function (p) { if (p.n > max) max = p.n; });
        max = Math.ceil(max * 1.15);
        var slot = (W - L - R) / s.length, bw = slot * 0.5;
        var out = '<svg class="chart" viewBox="0 0 ' + W + " " + H + '" preserveAspectRatio="none">';
        for (var g = 0; g <= 4; g++) {
            var y = T + (H - T - B) * g / 4;
            out += '<line class="axis" x1="' + L + '" x2="' + (W - R) + '" y1="' + y + '" y2="' + y + '"/>';
            out += '<text x="' + (L - 6) + '" y="' + (y + 3) + '" text-anchor="end">' + Math.round(max * (4 - g) / 4) + "</text>";
        }
        s.forEach(function (p, i) {
            var h = (H - T - B) * p.n / max, x = L + slot * i + (slot - bw) / 2;
            out += '<rect x="' + x + '" y="' + (H - B - h) + '" width="' + bw + '" height="' + h + '" rx="4" fill="' + color + '"/>';
            if (p.n) out += '<text x="' + (x + bw / 2) + '" y="' + (H - B - h - 4) + '" text-anchor="middle" style="fill:#12233f">' + p.n + "</text>";
            out += '<text x="' + (x + bw / 2) + '" y="' + (H - 6) + '" text-anchor="middle">' + p.d + "</text>";
        });
        return out + "</svg>";
    }

    function donut(parts) {
        var total = parts.reduce(function (a, p) { return a + p.n; }, 0), R = 46, C = 2 * Math.PI * R, off = 0;
        var out = '<svg width="130" height="130" viewBox="0 0 130 130"><circle cx="65" cy="65" r="' + R + '" fill="none" stroke="#eef4fe" stroke-width="18"/>';
        if (total) parts.forEach(function (p) {
            var len = C * p.n / total;
            if (len > 0) out += '<circle cx="65" cy="65" r="' + R + '" fill="none" stroke="' + p.color + '" stroke-width="18" stroke-dasharray="' + len + " " + (C - len) + '" stroke-dashoffset="' + (-off) + '" transform="rotate(-90 65 65)"/>';
            off += len;
        });
        out += '<text x="65" y="63" text-anchor="middle" style="font-size:24px;font-weight:700;fill:#0a2a66">' + total + '</text>';
        out += '<text x="65" y="80" text-anchor="middle" style="font-size:10px;fill:#8b9ab4">en linea</text></svg>';
        return out;
    }

    function card(title, sub) {
        var c = el("div", "card"), h = el("h3", "", title);
        if (sub) h.appendChild(el("small", "", sub));
        c.appendChild(h);
        return c;
    }
    function kpi(ico, value, label, sub, pct) {
        var c = el("div", "card"), k = el("div", "kpi"), i = el("div", "ico"), b = el("div");
        i.innerHTML = icon(ico);
        b.appendChild(el("div", "v", value)); b.appendChild(el("div", "l", label));
        if (sub) b.appendChild(el("div", "s", sub));
        k.appendChild(i); k.appendChild(b); c.appendChild(k);
        if (pct !== undefined) { var bar = el("div", "bar"), f = el("i"); f.style.width = Math.min(100, pct) + "%"; bar.appendChild(f); c.appendChild(bar); }
        return c;
    }

    /* ---------------- Dashboard ---------------- */
    function renderDash(v) {
        var d = state.dash;
        if (!d) return v.appendChild(el("div", "empty", "Cargando metricas..."));
        var k1 = el("div", "grid g-kpi"), k2 = el("div", "grid g-kpi");
        k1.appendChild(kpi("players", d.online + " / " + d.maxPlayers, "Jugadores en linea", "Ping medio " + d.pingAvg + " ms", d.online * 100 / Math.max(1, d.maxPlayers)));
        k1.appendChild(kpi("user", num(d.accounts), "Cuentas registradas", "Personajes: " + num(d.characters)));
        k1.appendChild(kpi("wallet", money((d.cash || 0) + (d.bank || 0)), "Dinero en circulacion", "Efectivo " + money(d.cash) + " / Banco " + money(d.bank)));
        k1.appendChild(kpi("bolt", d.resRunning + " / " + d.resTotal, "Recursos activos", "Tiempo en linea " + uptime(d.uptime), d.resRunning * 100 / Math.max(1, d.resTotal)));
        k2.appendChild(kpi("car", num(d.vehicles), "Vehiculos", ""));
        k2.appendChild(kpi("home", num(d.properties), "Propiedades", ""));
        k2.appendChild(kpi("flag", num(d.factions), "Facciones", ""));
        k2.appendChild(kpi("book", num(d.actionsToday), "Acciones admin hoy", "Auditadas en el registro"));
        v.appendChild(k1); v.appendChild(k2);

        var r1 = el("div", "grid g-2"), c1 = card("Actividad de los ultimos 7 dias", "inicios de sesion y altas");
        var wrap = el("div"); wrap.innerHTML = lineChart([d.logins, d.regs], [BLUE, "#7aa7f0"]);
        c1.appendChild(wrap);
        var lg = el("div", "legend"); lg.innerHTML = '<span><i style="background:' + BLUE + '"></i>Inicios de sesion</span><span><i style="background:#7aa7f0"></i>Cuentas nuevas</span>';
        c1.appendChild(lg);
        var c2 = card("Rangos conectados");
        var dw = el("div", "donut-wrap"), dn = el("div"), ul = el("ul");
        var lv = d.levels || {};
        var parts = [{ n: lv["0"] || 0, color: "#c5d6f2", name: "Jugadores" }, { n: lv["1"] || 0, color: "#5b97f5", name: "Admin" },
                     { n: lv["2"] || 0, color: "#1d63d8", name: "Admin senior" }, { n: lv["3"] || 0, color: "#0a2a66", name: "Super admin" }];
        dn.innerHTML = donut(parts); dw.appendChild(dn);
        parts.forEach(function (p) { var li = el("li"); li.innerHTML = '<i style="background:' + p.color + '"></i>' + p.name + "<b>" + p.n + "</b>"; ul.appendChild(li); });
        dw.appendChild(ul); c2.appendChild(dw);
        r1.appendChild(c1); r1.appendChild(c2); v.appendChild(r1);

        var r2 = el("div", "grid g-2"), c3 = card("Acciones de administracion", "ultimos 7 dias");
        var w3 = el("div"); w3.innerHTML = barChart(d.actions, BLUE); c3.appendChild(w3);
        var c4 = card("Actividad reciente", can("logs.view") ? "auditoria" : "sin acceso al registro"), feed = el("div", "feed");
        state.logs.slice(0, 6).forEach(function (l) {
            var row = el("div");
            row.appendChild(el("b", "", l.admin));
            row.appendChild(document.createTextNode(" " + l.cmd + (l.target ? " " + l.target : "")));
            row.appendChild(el("small", "", l.time + (l.details ? " - " + l.details : "")));
            feed.appendChild(row);
        });
        if (!state.logs.length) feed.appendChild(el("div", "", "Sin acciones registradas."));
        c4.appendChild(feed);
        r2.appendChild(c3); r2.appendChild(c4); v.appendChild(r2);
        $("count").textContent = "Actualizado automaticamente cada 10 s";
    }

    /* ---------------- Jugadores ---------------- */
    function renderPlayers(v) {
        var q = $("search").value.trim().toLowerCase();
        var list = state.players.filter(function (p) { return !q || (p.name + " " + p.account + " " + p.id).toLowerCase().indexOf(q) !== -1; });
        $("count").textContent = list.length + " jugadores en linea";
        var wrap = el("div", "players"), left = el("div", "card tbl-card list"), col = el("div", "rcol"), stage = el("div"), right = el("div", "card detail scroll");
        stage.id = "stage"; col.appendChild(stage); col.appendChild(right);
        var t = el("table"), thead = el("thead"), hr = el("tr");
        ["ID", "Personaje", "Cuenta", "Rango", "Zona", "Ping"].forEach(function (x) { hr.appendChild(el("th", "", x)); });
        thead.appendChild(hr); t.appendChild(thead);
        var tb = el("tbody");
        list.forEach(function (p) {
            var r = el("tr", "click" + (state.sel === p.id ? " sel" : ""));
            r.appendChild(el("td", "mono", String(p.id)));
            r.appendChild(el("td", "", p.name));
            r.appendChild(el("td", "", p.account));
            var bt = el("td"); bt.appendChild(badge(p.level)); r.appendChild(bt);
            r.appendChild(el("td", "", p.zone));
            r.appendChild(el("td", "", p.ping + " ms"));
            r.addEventListener("click", function () { state.sel = p.id; render(); });
            tb.appendChild(r);
        });
        t.appendChild(tb); left.appendChild(t);
        if (!list.length) left.appendChild(el("div", "empty", "Nadie coincide."));

        var cur = state.players.filter(function (p) { return p.id === state.sel; })[0];
        if (cur) {
            right.appendChild(el("h2", "", cur.name));
            var f = el("div", "facts");
            [["ID", cur.id], ["Cuenta", cur.account], ["Rango", roleName(cur.level)], ["Dinero", money(cur.money)],
             ["Vida / chaleco", cur.hp + " / " + cur.armor], ["Zona", cur.zone], ["Int / Dim", cur.int + " / " + cur.dim],
             ["Posicion", cur.x + ", " + cur.y + ", " + cur.z]].forEach(function (kv) {
                var a = el("div"); a.appendChild(document.createTextNode(kv[0])); a.appendChild(el("b", "", String(kv[1]))); f.appendChild(a);
            });
            right.appendChild(f);
            var b = el("div", "btns");
            if (can("players.goto")) b.appendChild(btn("Ir hasta", "", function () { req("act", "goto", cur.id); }));
            if (can("players.bring")) b.appendChild(btn("Traer", "", function () { req("act", "bring", cur.id); }));
            if (can("players.heal")) b.appendChild(btn("Curar", "", function () { req("act", "heal", cur.id); }));
            if (can("players.freeze")) b.appendChild(btn(cur.frozen ? "Descongelar" : "Congelar", "", function () { req("act", "freeze", cur.id); }));
            right.appendChild(b);
            if (can("players.kick")) {
                var kr = el("div", "btns"), reason = el("input", "inp");
                reason.placeholder = "Motivo de la expulsion"; reason.maxLength = 80; reason.style.flex = "1";
                kr.appendChild(reason);
                kr.appendChild(btn("Expulsar", "danger", function () { req("act", "kick", cur.id, reason.value); }));
                right.appendChild(kr);
            }
        } else {
            right.appendChild(el("div", "empty", "Selecciona un jugador para verlo en 3D y actuar."));
        }
        wrap.appendChild(left); wrap.appendChild(col); v.appendChild(wrap);
        var de = document.documentElement;
        if (cur) {
            var sr = stage.getBoundingClientRect();   // agujero en la mascara: deja ver la escena 3D del juego
            de.style.setProperty("--hx", sr.left + "px"); de.style.setProperty("--hy", sr.top + "px");
            de.style.setProperty("--hw", sr.width + "px"); de.style.setProperty("--hh", sr.height + "px");
        }
        de.classList.toggle("scene", !!cur);

        // el 3D solo se recrea al cambiar de seleccion, skin o apariencia
        var look = cur && cur.look ? JSON.stringify(cur.look) : "";
        var key = cur ? cur.id + ":" + cur.skin + ":" + look : null;
        if (key !== renderedSel) {
            renderedSel = key;
            if (cur) {
                setTimeout(function () {
                    var s = $("stage"), r = s && s.getBoundingClientRect();
                    if (r) send("rp:adminpanel:ui:preview", look, cur.skin, Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height));
                }, 80);
            } else send("rp:adminpanel:ui:preview", "", 0, 0, 0, 0, 0);
        }
    }

    /* ---------------- Cuentas ---------------- */
    function renderAccounts(v) {
        $("count").textContent = state.accounts.length + " cuentas";
        var c = el("div", "card tbl-card"), t = el("table"), thead = el("thead"), h = el("tr");
        ["ID", "Usuario", "Rango", "Ultimo acceso", "Estado", can("iam.manage") ? "Cambiar rango" : ""].forEach(function (x) { h.appendChild(el("th", "", x)); });
        thead.appendChild(h); t.appendChild(thead);
        var tb = el("tbody");
        state.accounts.forEach(function (a) {
            var r = el("tr");
            r.appendChild(el("td", "mono", String(a.id)));
            r.appendChild(el("td", "", a.username));
            var bt = el("td"); bt.appendChild(badge(a.level)); r.appendChild(bt);
            r.appendChild(el("td", "", a.last || "-"));
            var st = el("td"); st.appendChild(el("span", "badge" + (a.online ? " on" : ""), a.online ? "En linea" : "Desconectado")); r.appendChild(st);
            var td = el("td");
            if (can("iam.manage")) {
                var rt = el("div", "row-tools"), sel = el("select", "inp");
                for (var l = 0; l <= 3; l++) { var o = el("option", "", roleName(l)); o.value = l; if (l === a.level) o.selected = true; sel.appendChild(o); }
                rt.appendChild(sel);
                rt.appendChild(btn("Aplicar", "primary", function () {
                    if (+sel.value !== a.level) { req("setlevel", a.id, sel.value); setTimeout(function () { req("accounts", $("search").value.trim()); }, 400); }
                }));
                td.appendChild(rt);
            }
            r.appendChild(td);
            tb.appendChild(r);
        });
        t.appendChild(tb); c.appendChild(t); v.appendChild(c);
        if (!state.accounts.length) v.appendChild(el("div", "empty", "Sin resultados."));
    }

    /* ---------------- IAM ---------------- */
    function renderIam(v) {
        var d = state.iam;
        if (!d) return v.appendChild(el("div", "empty", "Cargando..."));
        var c = el("div", "card tbl-card");
        var head = el("div"); head.style.padding = "16px 18px 6px";
        head.appendChild(el("h3", "", "Permisos por rango"));
        head.appendChild(el("p", "sec", "El Super admin siempre tiene acceso total. Cada cambio se aplica al instante a todos los administradores de ese rango y queda auditado."));
        c.appendChild(head);
        var t = el("table"), thead = el("thead"), h = el("tr");
        h.appendChild(el("th", "", "Permiso"));
        [1, 2, d.super].forEach(function (l) { h.appendChild(el("th", "c", roleName(l))); });
        thead.appendChild(h); t.appendChild(thead);
        var tb = el("tbody"), last = null;
        d.perms.forEach(function (p) {
            if (p.group !== last) {
                last = p.group;
                var g = el("tr"), gc = el("td", "", p.group); gc.colSpan = 4; gc.style.cssText = "background:#f7faff;color:#1d63d8;font-weight:700;font-size:11px;text-transform:uppercase;letter-spacing:.06em";
                g.appendChild(gc); tb.appendChild(g);
            }
            var r = el("tr"), nm = el("td", "", p.label); nm.title = p.key; r.appendChild(nm);
            [1, 2, d.super].forEach(function (l) {
                var td = el("td", "c"), cb = el("input"); cb.type = "checkbox";
                if (l >= d.super) { cb.checked = true; cb.disabled = true; }
                else if (p.locked) { cb.checked = false; cb.disabled = true; }
                else {
                    cb.checked = !!(d.roles[l] && d.roles[l][p.key]);
                    cb.addEventListener("change", function () { req("roleperm", l, p.key, cb.checked ? "1" : "0"); });
                }
                td.appendChild(cb); r.appendChild(td);
            });
            tb.appendChild(r);
        });
        t.appendChild(tb); c.appendChild(t); v.appendChild(c);

        v.appendChild(el("div", "group", "Administradores y excepciones por cuenta"));
        v.appendChild(el("p", "sec", "Una excepcion permite o deniega un permiso a una sola cuenta, por encima de su rango. Para dar rango a alguien nuevo usa la seccion Cuentas."));
        d.admins.forEach(function (a) {
            var cd = el("div", "card admin-card"), hd = el("div", "head");
            hd.appendChild(el("b", "", a.username)); hd.appendChild(badge(a.level)); cd.appendChild(hd);
            if (a.level >= d.super) { cd.appendChild(el("p", "sec", "Super admin: acceso total, sin excepciones.")); v.appendChild(cd); return; }
            var grid = el("div", "ov-grid");
            d.perms.forEach(function (p) {
                if (p.locked) return;
                var lb = el("label"), sel = el("select", "inp");
                lb.appendChild(el("span", "", p.label));
                var cur = a.ov[p.key] === true ? "allow" : a.ov[p.key] === false ? "deny" : "inherit";
                [["inherit", "Segun rango"], ["allow", "Permitir"], ["deny", "Denegar"]].forEach(function (o) {
                    var op = el("option", "", o[1]); op.value = o[0]; if (cur === o[0]) op.selected = true; sel.appendChild(op);
                });
                sel.addEventListener("change", function () { req("override", a.id, p.key, sel.value); });
                lb.appendChild(sel); grid.appendChild(lb);
            });
            cd.appendChild(grid); v.appendChild(cd);
        });
    }

    /* ---------------- Auditoria ---------------- */
    function renderLogs(v) {
        var q = $("search").value.trim().toLowerCase();
        var rows = state.logs.filter(function (l) { return !q || (l.admin + l.cmd + l.target + l.details).toLowerCase().indexOf(q) !== -1; });
        $("count").textContent = rows.length + " acciones recientes";
        var c = el("div", "card tbl-card"), t = el("table"), thead = el("thead"), h = el("tr");
        ["Fecha", "Administrador", "Accion", "Objetivo", "Detalle"].forEach(function (x) { h.appendChild(el("th", "", x)); });
        thead.appendChild(h); t.appendChild(thead);
        var tb = el("tbody");
        rows.forEach(function (l) {
            var r = el("tr");
            [l.time, l.admin, l.cmd, l.target, l.details].forEach(function (x, i) { r.appendChild(el("td", i === 2 ? "mono" : "", x)); });
            tb.appendChild(r);
        });
        t.appendChild(tb); c.appendChild(t); v.appendChild(c);
        var bar = el("div", "btns"); bar.style.marginTop = "14px";
        bar.appendChild(btn("Actualizar", "primary", function () { req("logs"); }));
        v.appendChild(bar);
    }

    /* ---------------- Comandos ---------------- */
    function renderCommands(v) {
        var q = $("search").value.trim().toLowerCase(), total = 0;
        state.catalog.forEach(function (cat) {
            var items = (cat.items || []).filter(function (it) { return !q || (it.cmd + " " + (it.args || "") + " " + it.desc + " " + (it.res || "")).toLowerCase().indexOf(q) !== -1; });
            if (!items.length) return;
            v.appendChild(el("div", "group", cat.name));
            items.forEach(function (it) {
                total++;
                var row = el("button", "item"), top = el("div", "top");
                top.appendChild(el("span", "cmd", it.cmd));
                if (it.args) top.appendChild(el("span", "args", it.args));
                if (it.res) top.appendChild(el("span", "res", it.res));
                row.appendChild(top);
                row.appendChild(el("div", "desc", it.desc));
                if (it.alt) row.appendChild(el("div", "alt", "Tambien: " + it.alt));
                row.addEventListener("click", function () { send("rp:adminpanel:ui:copy", it.cmd + (it.args ? " " : "")); });
                v.appendChild(row);
            });
        });
        if (!total) v.appendChild(el("div", "empty", "Ningun comando coincide."));
        $("count").textContent = total + " comandos - clic para copiar";
    }

    /* ---------------- Entrada ---------------- */
    $("btn-close").addEventListener("click", function () { send("rp:adminpanel:ui:close"); });
    $("search").addEventListener("input", function () { if (state.tab !== "accounts") render(); });
    $("search").addEventListener("keydown", function (e) { if (e.key === "Enter" && state.tab === "accounts") req("accounts", $("search").value.trim()); });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") send("rp:adminpanel:ui:close"); });

    window.RP = {
        on: function (kind, data) {
            // defensa: si el dato llega envuelto en un array de mas, lo desenvuelve
            if (Array.isArray(data) && data.length === 1 && (Array.isArray(data[0]) || kind === "open" || kind === "iam" || kind === "dash")) data = data[0];
            if (kind === "open") {
                state.me = data.me; state.catalog = data.catalog || [];
                $("who").textContent = data.me.name; $("role").textContent = data.me.role;
                $("avatar").textContent = (data.me.name || "?").charAt(0).toUpperCase();
                setTab("dash");
                return;
            }
            if (kind === "dash") state.dash = data;
            else if (kind === "players") state.players = data;
            else if (kind === "accounts") state.accounts = data;
            else if (kind === "iam") state.iam = data;
            else if (kind === "logs") state.logs = data;
            if (kind === state.tab || (kind === "logs" && state.tab === "dash")) {
                // no reconstruir la vista mientras se escribe un motivo o se elige un select
                var a = document.activeElement;
                if (a && (a.tagName === "INPUT" || a.tagName === "SELECT") && a.id !== "search" && kind === "players") return;
                render();
            }
        }
    };
})();
