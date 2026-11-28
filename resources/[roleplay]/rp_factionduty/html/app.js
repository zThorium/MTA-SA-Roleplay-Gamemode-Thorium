/*
 * rp_factionduty / app.js
 * FDUTY.show(data) con data.mode = "locker" (vestuario) o "editor" (equipos de la facción).
 * Acciones: mta.triggerEvent("rp:factionduty:ui:action", accion, JSON); el servidor valida todo.
 * Abierto en un navegador normal (sin MTA) muestra datos de ejemplo: ?demo=locker o ?demo=editor.
 */
(function () {
    "use strict";

    var data = null;
    var editing = null;      // equipo en edición (editor)
    var $ = function (id) { return document.getElementById(id); };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
    }
    function action(name, payload) { send("rp:factionduty:ui:action", name, JSON.stringify([payload || {}])); }

    var SOUNDS = { click: "sounds/click_002.ogg", ok: "sounds/confirmation_001.ogg", error: "sounds/error_004.ogg", drop: "sounds/drop_001.ogg" };
    function sound(kind) {
        try { var a = new Audio(SOUNDS[kind]); a.volume = 0.5; a.play(); } catch (e) { /* sin audio */ }
    }

    function el(tag, className, text) {
        var e = document.createElement(tag);
        if (className) e.className = className;
        if (text !== undefined && text !== null) e.textContent = text;
        return e;
    }
    function button(text, className, onClick) {
        var b = el("button", "btn " + (className || ""), text);
        b.type = "button";
        b.addEventListener("click", function (e) { sound("click"); onClick(e); });
        return b;
    }
    function chips(items) {
        var box = el("div", "items");
        if (!items.length) box.appendChild(el("span", "meta", "Solo uniforme"));
        items.forEach(function (it) { box.appendChild(el("span", "chip", (it.icon ? it.icon + " " : "") + it.amount + " x " + it.name)); });
        return box;
    }
    function steps(list, now) {
        var ol = $("steps");
        ol.innerHTML = "";
        list.forEach(function (text, i) {
            ol.appendChild(el("li", i < now ? "done" : (i === now ? "now" : ""), text));
        });
    }

    // ---------------------------------------------------------- Vestuario
    function renderLocker() {
        $("title").textContent = "Vestuario de " + data.faction.name;
        $("subtitle").textContent = "Tu rol: " + (data.rank || "-") + " (nivel " + data.level + ")";
        var st = $("status");
        st.textContent = data.onDuty ? "De servicio" : "Fuera de servicio";
        st.className = "pill" + (data.onDuty ? " on" : "");
        steps(["Elige un equipo", "Pulsa «Ponerme este equipo»", "Vuelve aquí para salir de servicio"], data.onDuty ? 2 : 0);

        var body = $("body");
        if (!data.loadouts.length) {
            body.appendChild(el("p", "empty", "Tu facción aún no tiene equipos de servicio." +
                (data.canEdit ? " Créalos en F3 › Uniformes y equipo." : " Pide a tu líder que los cree en F3 › Uniformes y equipo.")));
        }
        var grid = el("div", "grid");
        data.loadouts.forEach(function (lo) {
            var current = data.onDuty && data.current === lo.id;
            var card = el("div", "card" + (current ? " current" : "") + (lo.locked ? " locked" : ""));
            var h = el("h3", null, lo.name);
            if (current) h.appendChild(el("span", "pill on", "Lo llevas"));
            card.appendChild(h);
            card.appendChild(el("span", "meta", "Rol mínimo: nivel " + lo.minLevel + " · Uniforme (skin " + lo.skin + ")"));
            card.appendChild(chips(lo.items));
            var row = el("div", "row");
            if (lo.locked) {
                row.appendChild(el("span", "meta", "Requiere un rol de nivel " + lo.minLevel + " o más"));
            } else if (!current) {
                row.appendChild(button(data.onDuty ? "Cambiar a este equipo" : "Ponerme este equipo", "primary", function () {
                    action("on", { lockerId: data.lockerId, loadoutId: lo.id });
                }));
            }
            card.appendChild(row);
            grid.appendChild(card);
        });
        body.appendChild(grid);

        if (data.onDuty) {
            $("footer-actions").appendChild(button("Salir de servicio y devolver el equipo", "danger", function () {
                action("off", { lockerId: data.lockerId });
            }));
        }
    }

    // ---------------------------------------------------------- Editor
    function itemOptions(select, selected) {
        data.allowed.forEach(function (a) {
            var o = el("option", null, (a.icon ? a.icon + " " : "") + a.name + " (máx. " + a.max + ")");
            o.value = a.id;
            if (a.id === selected) o.selected = true;
            select.appendChild(o);
        });
    }

    function renderForm(body) {
        var lo = editing;
        steps(["Nombre y rol mínimo", "Uniforme (número de skin)", "Objetos que se entregan", "Guardar"], 0);
        var form = el("form", "editor");
        function field(label, input) { var l = el("label", null, label); l.appendChild(input); form.appendChild(l); return input; }
        var name = field("Nombre del equipo", el("input")); name.maxLength = 24; name.value = lo.name || ""; name.placeholder = "Ej.: Turno de día";
        var level = field("Rol mínimo (1-" + data.maxLevel + ")", el("input")); level.type = "number"; level.min = 1; level.max = data.maxLevel; level.value = lo.minLevel || 1;
        var skin = field("Uniforme (skin 0-312)", el("input")); skin.type = "number"; skin.min = 0; skin.max = 312; skin.value = lo.skin != null ? lo.skin : 280;
        form.addEventListener("submit", function (e) { e.preventDefault(); });
        body.appendChild(form);
        body.appendChild(el("p", "note", "El rol mínimo es el nivel del rol en F3 › Roles y permisos: los roles de nivel menor no ven este equipo. " +
            "El uniforme es el número de skin de GTA SA."));

        var items = (lo.items || []).map(function (it) { return { id: it.id, amount: it.amount }; });
        var box = el("div");
        function drawItems() {
            box.innerHTML = "";
            box.appendChild(el("h3", "meta", "Objetos (" + items.length + "/" + data.maxItems + ")"));
            if (!data.allowed.length) {
                box.appendChild(el("p", "note", "Tu tipo de facción aún no tiene objetos de servicio: el equipo es solo el uniforme."));
                return;
            }
            items.forEach(function (it, i) {
                var row = el("div", "itemrow");
                var sel = el("select"); itemOptions(sel, it.id);
                sel.addEventListener("change", function () { it.id = sel.value; });
                var amount = el("input"); amount.type = "number"; amount.min = 1; amount.value = it.amount;
                amount.addEventListener("input", function () { it.amount = Math.floor(Number(amount.value)); });
                row.appendChild(sel); row.appendChild(amount);
                row.appendChild(button("Quitar", "danger small", function () { items.splice(i, 1); sound("drop"); drawItems(); }));
                box.appendChild(row);
            });
            if (items.length < data.maxItems) {
                box.appendChild(button("+ Añadir objeto", "small", function () {
                    items.push({ id: data.allowed[0].id, amount: 1 }); drawItems();
                }));
            }
        }
        drawItems();
        body.appendChild(box);

        $("footer-actions").appendChild(button("Cancelar", "", function () { editing = null; render(); }));
        $("footer-actions").appendChild(button("Guardar equipo", "primary", function () {
            action("save", { id: lo.id || null, name: name.value.trim(), minLevel: Number(level.value), skin: Number(skin.value), items: items });
            editing = null;
        }));
    }

    function renderEditor() {
        $("title").textContent = "Equipos de servicio · " + data.faction.name;
        $("subtitle").textContent = "Uniforme y objetos que cada rol recibe en el vestuario";
        var st = $("status");
        st.textContent = data.loadouts.length + "/" + data.maxLoadouts + " equipos";
        st.className = "pill";
        var body = $("body");
        if (!data.hasLocker) {
            body.appendChild(el("p", "note warn", "Tu facción aún no tiene vestuario: pide a un administrador que lo coloque (/makelocker). " +
                "Mientras no lo tenga, los sueldos se pagan como siempre."));
        }
        if (editing) return renderForm(body);
        steps(["Crea un equipo", "Define rol mínimo, uniforme y objetos", "Tus miembros lo eligen en el vestuario"], data.loadouts.length ? 2 : 0);

        var list = el("div", "list");
        if (!data.loadouts.length) list.appendChild(el("p", "empty", "Sin equipos. Crea el primero con «+ Nuevo equipo»."));
        data.loadouts.forEach(function (lo) {
            var line = el("div", "line");
            var info = el("div", "grow");
            info.appendChild(el("h3", null, lo.name));
            info.appendChild(el("span", "meta", "Nivel " + lo.minLevel + "+ · skin " + lo.skin));
            info.appendChild(chips(lo.items));
            line.appendChild(info);
            line.appendChild(button("Editar", "small", function () { editing = lo; render(); }));
            line.appendChild(button("Borrar", "danger small", function (e) {
                var b = e.currentTarget;
                if (b.dataset.confirm) return action("delete", { id: lo.id });
                b.dataset.confirm = "1"; b.textContent = "Confirmar";
            }));
            list.appendChild(line);
        });
        body.appendChild(list);
        if (data.loadouts.length < data.maxLoadouts) {
            $("footer-actions").appendChild(button("+ Nuevo equipo", "primary", function () { editing = {}; render(); }));
        }
    }

    function render() {
        if (!data) return;
        document.documentElement.style.setProperty("--accent", data.faction.color || "#4c9aff");
        $("tag").textContent = data.faction.tag || "--";
        $("body").innerHTML = "";
        $("footer-actions").innerHTML = "";
        if (data.mode === "editor") renderEditor(); else renderLocker();
    }

    $("btn-close").addEventListener("click", function () { send("rp:factionduty:ui:close"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") { e.preventDefault(); send("rp:factionduty:ui:close"); }
    });

    window.FDUTY = {
        show: function (d) {
            var before = data;
            data = d;
            // Sonido según lo que cambió: entrar/salir de servicio
            if (before && before.mode === "locker" && d.mode === "locker" && before.onDuty !== d.onDuty) sound(d.onDuty ? "ok" : "drop");
            if (d.mode !== "editor" || !editing) render();
        }
    };

    // Demo en un navegador normal
    var demo = /demo=(\w+)/.exec(location.search);
    if (demo && !window.mta) {
        var items = [{ id: "wpn_colt45", name: "Colt 45", icon: "🔫", amount: 1 }, { id: "ammo_pistol", name: "Municion de pistola", icon: "", amount: 34 }];
        if (demo[1] === "editor") {
            FDUTY.show({ mode: "editor", faction: { name: "Vigilancia Andes", tag: "VAS", color: "#6b7a8f" }, maxLevel: 10, maxLoadouts: 8, maxItems: 4,
                hasLocker: true, allowed: [{ id: "wpn_colt45", name: "Colt 45", icon: "🔫", max: 1 }, { id: "ammo_pistol", name: "Municion de pistola", icon: "", max: 34 }],
                loadouts: [{ id: 1, name: "Guardia", minLevel: 1, skin: 71, items: [] }, { id: 2, name: "Escolta armado", minLevel: 5, skin: 163, items: items }] });
        } else {
            FDUTY.show({ mode: "locker", lockerId: 1, faction: { name: "Vigilancia Andes", tag: "VAS", color: "#6b7a8f" }, rank: "Guardia", level: 3,
                onDuty: false, current: false, canEdit: false,
                loadouts: [{ id: 1, name: "Guardia", minLevel: 1, skin: 71, items: [], locked: false }, { id: 2, name: "Escolta armado", minLevel: 5, skin: 163, items: items, locked: true }] });
        }
    }
})();
