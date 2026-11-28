/* rp_duty / app.js — panel del vestuario. Solo muestra y reenvía: el servidor valida todo. */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var data = null, selected = null, editing = null, tab = "duty";

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
    }
    var SOUNDS = {};
    function sound(name) {
        try {
            var a = SOUNDS[name] || (SOUNDS[name] = new Audio("sounds/" + name + ".ogg"));
            a.currentTime = 0; a.volume = 0.5; a.play();
        } catch (e) { /* sin audio */ }
    }
    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined) e.textContent = text;
        return e;
    }
    function action(name, d) { sound("click_002"); send("rp:duty:ui:action", name, JSON.stringify(d || {})); }
    function close() { sound("minimize_003"); $("panel").classList.add("hidden"); send("rp:duty:ui:close"); }

    // ---------- Servicio ----------
    function renderDuty() {
        var cards = $("cards");
        cards.innerHTML = "";
        var list = data.loadouts || [];
        $("empty").classList.toggle("hidden", list.length > 0);
        $("empty-hint").innerHTML = data.manage ? "Créalos tú en la pestaña <b>Uniformes</b>." : "Pídele al líder que los cree en la pestaña <b>Uniformes</b>.";
        $("guide").classList.toggle("hidden", data.onDuty || list.length === 0);
        if (selected === null && list.length) selected = data.current || list[0].id;
        list.forEach(function (l) {
            var c = el("div", "card");
            if (l.id === selected) c.classList.add("sel");
            if (data.onDuty && l.id === data.current) c.classList.add("current");
            c.appendChild(el("div", "name", l.name));
            c.appendChild(el("div", "meta", "Rol " + l.minLevel + "+ · " + (l.skin ? "Skin " + l.skin : "Su propia ropa")));
            var chips = el("div", "chips");
            if (!l.items.length) chips.appendChild(el("span", "chip", "Sin equipo"));
            l.items.forEach(function (it) { chips.appendChild(el("span", "chip", it.amount + "× " + it.name)); });
            c.appendChild(chips);
            c.onclick = function () { selected = l.id; sound("click_002"); renderDuty(); };
            cards.appendChild(c);
        });
        var on = $("on");
        on.disabled = !list.length || selected === null || (data.onDuty && selected === data.current);
        on.textContent = data.onDuty ? "Cambiar de uniforme" : "Entrar de servicio";
        $("off").classList.toggle("hidden", !data.onDuty);
        $("state").textContent = data.onDuty ? "De servicio" : "Fuera de servicio";
        $("state").classList.toggle("on", !!data.onDuty);
    }

    // ---------- Editor ----------
    function catalogOptions(sel, value) {
        (data.catalog || []).forEach(function (c) {
            var o = el("option", null, c.name);
            o.value = c.id;
            if (c.id === value) o.selected = true;
            sel.appendChild(o);
        });
    }
    function addItemRow(it) {
        var box = $("f-items");
        if (box.children.length >= data.limits.maxItems) { sound("error_004"); return; }
        var row = el("div", "irow");
        var sel = el("select"); catalogOptions(sel, it && it.id);
        var n = el("input"); n.type = "number"; n.min = 1; n.max = data.limits.maxAmount; n.value = (it && it.amount) || 1;
        var x = el("button", null, "✕"); x.type = "button"; x.title = "Quitar";
        x.onclick = function () { row.remove(); countItems(); };
        row.appendChild(sel); row.appendChild(n); row.appendChild(x);
        box.appendChild(row);
        countItems();
    }
    function countItems() { $("items-count").textContent = "(" + $("f-items").children.length + "/" + data.limits.maxItems + ")"; }
    function fillForm(l) {
        editing = l ? l.id : null;
        $("form-title").textContent = l ? "Editar «" + l.name + "»" : "Nuevo uniforme";
        $("f-name").value = l ? l.name : "";
        $("f-level").value = l ? l.minLevel : 1;
        $("f-skin").value = l && l.skin ? l.skin : "";
        $("f-items").innerHTML = "";
        (l ? l.items : []).forEach(addItemRow);
        countItems();
        $("del").classList.toggle("hidden", !l);
        renderList();
    }
    function renderList() {
        var box = $("list");
        box.innerHTML = "";
        var all = data.all || [];
        if (!all.length) box.appendChild(el("div", "none", "Aún no hay uniformes. Rellena el formulario y pulsa Guardar."));
        all.forEach(function (l) {
            var it = el("div", "item" + (l.id === editing ? " sel" : ""), l.name);
            it.appendChild(el("small", null, "Rol " + l.minLevel + "+ · " + l.items.length + " objeto(s)"));
            it.onclick = function () { sound("click_002"); fillForm(l); };
            box.appendChild(it);
        });
    }
    function collect() {
        var items = [];
        Array.prototype.forEach.call($("f-items").children, function (row) {
            items.push({ id: row.children[0].value, amount: parseInt(row.children[1].value, 10) || 0 });
        });
        var skin = $("f-skin").value.trim();
        return { id: editing, name: $("f-name").value.trim(), minLevel: parseInt($("f-level").value, 10) || 1,
            skin: skin === "" ? false : parseInt(skin, 10), items: items };
    }

    function setTab(t) {
        tab = (t === "edit" && data && data.manage) ? "edit" : "duty";
        Array.prototype.forEach.call(document.querySelectorAll(".tabs button"), function (b) { b.classList.toggle("on", b.dataset.tab === tab); });
        $("sec-duty").classList.toggle("hidden", tab !== "duty");
        $("sec-edit").classList.toggle("hidden", tab !== "edit");
    }

    // ---------- Entrada desde Lua ----------
    window.dutyOpen = function (d) {
        var first = !data || $("panel").classList.contains("hidden");
        var wasOn = data && data.onDuty;
        data = d;
        if (first) { selected = null; editing = null; sound("maximize_003"); }
        else if (wasOn !== d.onDuty) sound(d.onDuty ? "confirmation_001" : "drop_001");
        else if (tab === "edit") sound("confirmation_001");
        if (selected !== null && !(d.loadouts || []).some(function (l) { return l.id === selected; })) selected = null;
        $("panel").classList.remove("hidden");
        $("tag").textContent = d.tag || "FAC";
        $("faction").textContent = d.faction || "";
        $("rank").textContent = d.rank ? "Tu rol: " + d.rank : "";
        if (/^#[0-9a-f]{6}$/i.test(d.color || "")) document.documentElement.style.setProperty("--fac", d.color);
        $("tab-edit").classList.toggle("hidden", !d.manage);
        setTab(first ? "duty" : tab);
        renderDuty();
        if (d.manage) {
            var cur = editing && (d.all || []).filter(function (l) { return l.id === editing; })[0];
            if (first || !cur) fillForm(null); else renderList();
        }
    };

    // ---------- Botones ----------
    $("close").onclick = close;
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" && !$("panel").classList.contains("hidden")) close();
    });
    Array.prototype.forEach.call(document.querySelectorAll(".tabs button"), function (b) {
        b.onclick = function () { sound("click_002"); setTab(b.dataset.tab); };
    });
    $("on").onclick = function () { if (selected !== null) action("dutyOn", { id: selected }); };
    $("off").onclick = function () { action("dutyOff"); };
    $("add-item").onclick = function () { sound("click_002"); addItemRow(null); };
    $("new").onclick = function () { sound("click_002"); fillForm(null); };
    $("del").onclick = function () { if (editing !== null) action("delete", { id: editing }); };
    $("form").onsubmit = function (e) {
        e.preventDefault();
        var d = collect();
        if (d.name.length < 2) { sound("error_004"); $("f-name").focus(); return; }
        action("save", d);
    };

    // Vista previa en un navegador normal (sin MTA): index.html#demo
    if (!window.mta && location.hash.indexOf("#demo") === 0) {
        window.dutyOpen({
            faction: "Servicios Médicos de LS", tag: "LSMD", color: "#e5484d", rank: "Paramédico", onDuty: false, current: false, manage: true,
            loadouts: [
                { id: 1, name: "Paramédico", minLevel: 1, skin: 274, items: [{ id: "medkit", amount: 2, name: "Botiquín" }], allowed: true },
                { id: 2, name: "Jefe de turno", minLevel: 5, skin: 276, items: [{ id: "medkit", amount: 3, name: "Botiquín" }, { id: "radio", amount: 1, name: "Radio" }], allowed: true },
            ],
            all: [
                { id: 1, name: "Paramédico", minLevel: 1, skin: 274, items: [{ id: "medkit", amount: 2, name: "Botiquín" }] },
                { id: 2, name: "Jefe de turno", minLevel: 5, skin: 276, items: [{ id: "medkit", amount: 3, name: "Botiquín" }, { id: "radio", amount: 1, name: "Radio" }] },
            ],
            catalog: [{ id: "medkit", name: "Botiquín" }, { id: "radio", name: "Radio" }, { id: "water", name: "Agua" }],
            limits: { maxItems: 6, maxAmount: 20, maxLoadouts: 10 },
        });
        if (location.hash === "#demo-edit") { setTab("edit"); fillForm(data.all[1]); }
    }
})();
