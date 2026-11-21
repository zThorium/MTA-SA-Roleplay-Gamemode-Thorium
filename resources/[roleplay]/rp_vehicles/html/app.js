/*
 * rp_vehicles / app.js
 * Lua llama a RPV.show(vista, datos). Vistas: menu, trunk, plate, fines,
 * admin, police, tuning. Las acciones vuelven a Lua con mta.triggerEvent.
 */
(function () {
    "use strict";

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
    }
    function action(name, a, b) { send("rp:veh:ui:action", name, a === undefined ? "" : a, b === undefined ? "" : b); }
    function close() { send("rp:veh:ui:close"); }

    var $ = function (id) { return document.getElementById(id); };
    function esc(s) {
        return String(s === null || s === undefined ? "" : s).replace(/[&<>"']/g, function (c) {
            return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
        });
    }
    function person(n) { return esc(String(n || "?").replace(/_/g, " ")); }
    function money(n) { return "$" + Number(n || 0).toLocaleString("es-AR"); }
    function list(x) { return Array.isArray(x) ? x : (x && typeof x === "object" ? Object.keys(x).map(function (k) { return x[k]; }) : []); }

    var view = null;

    function openWindow(title, subtitle, html, small) {
        $("menu").classList.add("hidden");
        document.body.classList.add("dim");
        var w = $("window");
        w.classList.remove("hidden");
        w.classList.toggle("small", !!small);
        $("title").textContent = title;
        $("subtitle").textContent = subtitle || "";
        $("body").innerHTML = html;
    }

    // ---------------------------------------------------------- Menu
    function renderMenu(d) {
        $("window").classList.add("hidden");
        document.body.classList.remove("dim");
        var m = $("menu");
        var html = '<div class="head"><strong>' + esc(d.name) + '</strong><span>' + esc(d.plate) + "</span></div>";
        var lastGroup = null;
        list(d.options).forEach(function (o) {
            if (o.group && o.group !== lastGroup) html += '<div class="sep"></div>';
            lastGroup = o.group || null;
            html += '<button type="button" data-id="' + esc(o.id) + '" class="' + esc(o.group || "") + '"' + (o.disabled ? " disabled" : "") + ">" +
                "<span>" + esc(o.icon || "") + "</span>" + esc(o.label) + (o.hint ? "<small>" + esc(o.hint) + "</small>" : "") + "</button>";
        });
        m.innerHTML = html;
        m.classList.remove("hidden");
        var x = Math.min(d.x + 8, window.innerWidth - m.offsetWidth - 8);
        var y = Math.min(d.y + 8, window.innerHeight - m.offsetHeight - 8);
        m.style.left = Math.max(8, x) + "px";
        m.style.top = Math.max(8, y) + "px";
        m.querySelectorAll("button[data-id]").forEach(function (b) {
            b.addEventListener("click", function () { action(b.getAttribute("data-id")); });
        });
    }

    // ---------------------------------------------------------- Maletero
    function itemRows(items, verb, act) {
        if (!items.length) return '<p class="empty">Vacio</p>';
        return items.map(function (it) {
            return '<div class="item"><span class="icon">' + esc(it.icon) + '</span><span class="name">' + esc(it.name) +
                "<small>x" + it.amount + " · " + (it.weight * it.amount).toFixed(2) + ' kg</small></span>' +
                '<input type="number" min="1" max="' + it.amount + '" value="1" data-amt="' + esc(it.id) + '">' +
                '<button type="button" class="btn" data-act="' + act + '" data-item="' + esc(it.id) + '">' + verb + "</button></div>";
        }).join("");
    }

    function renderTrunk(d) {
        var pct = d.capacity > 0 ? Math.min(100, d.weight / d.capacity * 100) : 100;
        openWindow("Maletero", d.name + " · " + d.plate,
            '<div class="cols">' +
            '<div class="card"><h2>Tu inventario</h2><div class="items">' + itemRows(list(d.inventory), "Guardar", "trunk_put") + "</div></div>" +
            '<div class="card"><h2>Maletero</h2><div class="faint">' + d.weight + " / " + d.capacity + ' kg</div>' +
            '<div class="bar"><div style="width:' + pct + '%"></div></div><div class="items">' + itemRows(list(d.trunk), "Sacar", "trunk_take") + "</div></div>" +
            "</div>");
        $("body").querySelectorAll("button[data-act]").forEach(function (b) {
            b.addEventListener("click", function () {
                var input = b.parentNode.querySelector("input");
                var n = parseInt(input.value, 10);
                if (n > 0) action(b.getAttribute("data-act"), b.getAttribute("data-item"), n);
            });
        });
    }

    // ---------------------------------------------------------- Matricula
    function renderPlate(d) {
        openWindow("Matricula", d.name,
            '<div class="plate"><div class="state">SAN ANDREAS</div><div class="number">' + esc(d.plate) + "</div></div>", true);
    }

    // ---------------------------------------------------------- Multas (dueno)
    function finesTable(fines, payable) {
        fines = list(fines);
        if (!fines.length) return '<p class="empty">Sin multas.</p>';
        return '<div class="table-wrap"><table><tr><th>#</th><th>Fecha</th><th>Agente</th><th>Motivo</th><th>Monto</th><th>Estado</th>' + (payable ? "<th></th>" : "") + "</tr>" +
            fines.map(function (f) {
                var paid = Number(f.paid) === 1;
                return "<tr><td>" + f.id + "</td><td>" + esc(f.at) + "</td><td>" + esc(f.officer_name) + "</td><td>" + esc(f.reason) + "</td><td>" + money(f.amount) +
                    '</td><td><span class="tag ' + (paid ? "ok" : "bad") + '">' + (paid ? "Pagada" : "Pendiente") + "</span></td>" +
                    (payable ? "<td>" + (paid ? "" : '<button type="button" class="btn primary" data-pay="' + f.id + '">Pagar</button>') + "</td>" : "") + "</tr>";
            }).join("") + "</table></div>";
    }

    function renderFines(d) {
        openWindow("Multas", d.name + " · " + d.plate,
            (d.clamped ? '<p class="tag bad" style="margin-bottom:12px">El vehiculo tiene un cepo policial</p>' : "") +
            '<p class="faint" style="margin-bottom:10px">Las multas se pagan desde tu cuenta bancaria.</p>' + finesTable(d.fines, true));
        $("body").querySelectorAll("[data-pay]").forEach(function (b) {
            b.addEventListener("click", function () { b.disabled = true; action("fine_pay", Number(b.getAttribute("data-pay"))); });
        });
    }

    // ---------------------------------------------------------- Admin
    var SEATS = ["Piloto", "Copiloto", "Pasajero trasero izq.", "Pasajero trasero der."];
    var adminTab = "hits";

    function renderAdmin(d) {
        var hits = list(d.hits), entries = list(d.entries);
        var last = hits[0];
        var html = '<div class="cols wide"><div>' +
            '<div id="preview"><span>Vista 3D del vehiculo</span></div>' +
            '<dl class="facts">' +
            "<dt>ID</dt><dd>" + d.id + "</dd>" +
            "<dt>Dueno</dt><dd>" + person(d.owner) + "</dd>" +
            "<dt>Estado</dt><dd>" + d.health + "% · " + (d.locked ? "Cerrado" : "Abierto") + " · Motor " + (d.engine ? "encendido" : "apagado") + "</dd>" +
            "<dt>Ultimo golpe</dt><dd>" + (last ? person(last.character_name) + ' <span class="faint">' + esc(last.at) + "</span>" : "-") + "</dd>" +
            "<dt>Ultimo piloto</dt><dd>" + (d.lastDriver ? person(d.lastDriver.name) + ' <span class="faint">' + esc(d.lastDriver.at) + "</span>" : "-") + "</dd>" +
            "<dt>Copiloto</dt><dd>" + (d.lastPassenger ? person(d.lastPassenger.character_name) + ' <span class="faint">' + esc(SEATS[d.lastPassenger.seat] || "Pasajero") + " · " + esc(d.lastPassenger.at) + "</span>" : "Nadie en las ultimas " + d.retention + " h") + "</dd>" +
            "</dl></div><div>" +
            '<div class="tabs"><button type="button" data-tab="hits">Golpes (' + hits.length + ')</button><button type="button" data-tab="entries">Ocupantes (' + entries.length + ")</button></div>" +
            '<div id="tab"></div><p class="faint" style="margin-top:8px">Se guardan las ultimas ' + d.retention + " horas.</p></div></div>";
        openWindow("Administracion del vehiculo", d.name + " · " + d.plate, html);

        function tab() {
            $("body").querySelectorAll("[data-tab]").forEach(function (b) { b.classList.toggle("active", b.getAttribute("data-tab") === adminTab); });
            var t = $("tab");
            if (adminTab === "hits") {
                t.innerHTML = !hits.length ? '<p class="empty">Nadie golpeo este vehiculo.</p>' :
                    '<div class="table-wrap"><table><tr><th>Jugador</th><th>Con</th><th>Dano</th><th>Golpes</th><th>Hora</th></tr>' +
                    hits.map(function (h) {
                        return "<tr><td>" + person(h.character_name) + "</td><td>" + esc(h.weapon_name) + "</td><td>" + h.loss + "</td><td>" + h.hits + "</td><td>" + esc(h.at) + "</td></tr>";
                    }).join("") + "</table></div>";
            } else {
                t.innerHTML = !entries.length ? '<p class="empty">Nadie se subio.</p>' :
                    '<div class="table-wrap"><table><tr><th>Jugador</th><th>Asiento</th><th>Hora</th></tr>' +
                    entries.map(function (e) {
                        return "<tr><td>" + person(e.character_name) + "</td><td>" + esc(SEATS[e.seat] || "Pasajero") + "</td><td>" + esc(e.at) + "</td></tr>";
                    }).join("") + "</table></div>";
            }
        }
        $("body").querySelectorAll("[data-tab]").forEach(function (b) {
            b.addEventListener("click", function () { adminTab = b.getAttribute("data-tab"); tab(); });
        });
        tab();
        // Le dice a Lua donde dibujar el auto en 3D
        setTimeout(function () {
            var r = $("preview").getBoundingClientRect();
            send("rp:veh:ui:preview", Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height));
        }, 250);
    }

    // ---------------------------------------------------------- Policia
    function renderPolice(d) {
        var html = '<div class="cols wide"><div>' +
            '<dl class="facts" style="margin-bottom:14px">' +
            "<dt>Matricula</dt><dd>" + esc(d.plate) + "</dd>" +
            "<dt>Dueno</dt><dd>" + person(d.owner) + "</dd>" +
            "<dt>Cerradura</dt><dd>" + (d.locked ? "Cerrado" : "Abierto") + "</dd>" +
            "<dt>Cepo</dt><dd>" + (d.clamped ? '<span class="tag bad">Puesto</span>' : '<span class="tag ok">No</span>') + "</dd>" +
            "<dt>Deuda</dt><dd>" + money(d.unpaid) + "</dd></dl>" +
            '<button type="button" class="btn ' + (d.clamped ? "danger" : "police") + '" id="clamp" style="width:100%;margin-bottom:16px">' + (d.clamped ? "Quitar cepo" : "Poner cepo") + "</button>" +
            '<div class="card"><h2>Nueva multa</h2>' +
            '<input type="number" id="fine-amount" min="' + d.fineMin + '" max="' + d.fineMax + '" placeholder="Monto ($' + d.fineMin + " - $" + d.fineMax + ')" style="width:100%;margin-bottom:8px">' +
            '<textarea id="fine-reason" maxlength="128" placeholder="Motivo (p. ej. estacionado en lugar prohibido)"></textarea>' +
            '<button type="button" class="btn police" id="fine-send" style="width:100%;margin-top:8px">Multar</button></div>' +
            "</div><div>" +
            '<div class="tabs"><button type="button" data-tab="fines" class="active">Multas</button><button type="button" data-tab="log">Historial</button></div>' +
            '<div id="ptab"></div></div></div>';
        openWindow("Policia", d.name + " · " + d.plate, html);

        var log = list(d.log);
        function tab(name) {
            $("body").querySelectorAll("[data-tab]").forEach(function (b) { b.classList.toggle("active", b.getAttribute("data-tab") === name); });
            $("ptab").innerHTML = name === "fines" ? finesTable(d.fines, false) :
                (!log.length ? '<p class="empty">Sin registros.</p>' :
                    '<div class="table-wrap"><table><tr><th>Fecha</th><th>Quien</th><th>Accion</th></tr>' +
                    log.map(function (l) { return "<tr><td>" + esc(l.at) + "</td><td>" + person(l.actor_name) + "</td><td>" + esc(l.text) + "</td></tr>"; }).join("") +
                    "</table></div>");
        }
        $("body").querySelectorAll("[data-tab]").forEach(function (b) {
            b.addEventListener("click", function () { tab(b.getAttribute("data-tab")); });
        });
        tab("fines");
        $("clamp").addEventListener("click", function () { this.disabled = true; action("police_clamp"); });
        $("fine-send").addEventListener("click", function () {
            var amount = parseInt($("fine-amount").value, 10);
            var reason = $("fine-reason").value.trim();
            if (!(amount >= d.fineMin && amount <= d.fineMax) || reason.length < 3) return;
            this.disabled = true;
            action("police_fine", amount, reason);
        });
    }

    // ---------------------------------------------------------- API para Lua
    window.RPV = {
        show: function (name, data) {
            view = name;
            switch (name) {
                case "menu": renderMenu(data); break;
                case "trunk": renderTrunk(data); break;
                case "plate": renderPlate(data); break;
                case "fines": renderFines(data); break;
                case "admin": renderAdmin(data); break;
                case "police": renderPolice(data); break;
            }
        },
        hide: function () {
            view = null;
            $("menu").classList.add("hidden");
            $("window").classList.add("hidden");
            document.body.classList.remove("dim");
            $("body").innerHTML = "";
        },
        previewUnsupported: function () {
            var p = $("preview");
            if (p) p.innerHTML = "<span>La vista 3D necesita el recurso object_preview y una tarjeta grafica con MRT.</span>";
        },
    };

    $("btn-close").addEventListener("click", close);
    $("backdrop").addEventListener("mousedown", close);
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" || (e.key && e.key.toLowerCase() === "m" && view === "menu")) { e.preventDefault(); close(); }
    });
})();
