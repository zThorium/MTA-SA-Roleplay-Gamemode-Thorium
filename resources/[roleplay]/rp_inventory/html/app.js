/*
 * rp_inventory / app.js
 * Lua llama a RP.render(items, peso, pesoMaximo, mochila), RP.nearby(personas), RP.ground(objetosDelSuelo),
 * RP.character(estado), RP.setLayout(json) y RP.opened().
 * Acciones via mta.triggerEvent: rp:inv:ui:use / drop / dropAt / give / pickup / close / layout /
 * toBackpack / fromBackpack / dropBackpack.
 *
 * Arrastrar (Mayús = solo 1):
 *   casilla -> casilla            mover o intercambiar (inventario <-> mochila = guardar / sacar)
 *   casilla -> persona            dar
 *   casilla -> "Cerca de ti"      dejar a tus pies
 *   casilla -> fuera de paneles   tirar donde sueltas
 *   casilla -> hueco de Personaje equipar / usar (arma, chaleco, mochila, telefono...)
 *   suelo   -> inventario         recoger
 *   mochila equipada -> fuera     tirarla con todo
 */
(function () {
    "use strict";

    var MIN_SLOTS = 30;
    var MAX_CELLS = 120;
    var DRAG_THRESHOLD = 6;
    var ICON_DIR = "icons/";

    var state = { items: [], nearby: [], ground: [], bp: null, weight: 0, max: 0, filter: "all", char: {} };
    var layout = { base: {}, bp: {} };   // posiciones de las casillas (ver place)
    var drag = null;                       // { kind: "inv"|"ground"|"pack"|"weapon", item, amount, startX, startY, active, node }
    var menuItem = null;
    var $ = function (id) { return document.getElementById(id); };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined) node.textContent = text;
        return node;
    }

    // ---- Sonidos (Kenney CC0, uno por accion) ----
    var SOUNDS = {
        open: ["maximize_003"], close: ["minimize_003"], click: ["click_002"],
        drop: ["drop_001", "drop_002", "drop_003"], error: ["error_004"], ok: ["confirmation_001"]
    };
    function play(name) {
        var list = SOUNDS[name];
        if (!list) return;
        try {
            var a = new Audio("sounds/" + list[Math.floor(Math.random() * list.length)] + ".ogg");
            a.volume = 0.45;
            a.play();
        } catch (e) { /* sin audio */ }
    }

    // ---- Categorias (pestañas) ----
    var TABS = [
        { id: "all", icon: "🗂️", title: "Todo" },
        { id: "food", icon: "🍔", title: "Comida y bebida", re: /^(water|sandwich|burger|coffee|soda_|energy_drink|snack_)/ },
        { id: "health", icon: "🩹", title: "Salud y protección", re: /^(medkit|vest|pol_vest)$/ },
        { id: "docs", icon: "🪪", title: "Documentos, llaves y teléfono", re: /^(id_card|driver_license|train_ticket|phone|vkey:|bcard:)/ },
        { id: "weapons", icon: "🔫", title: "Armas, munición y equipo policial", re: /^(wpn_|ammo_|pol_)/ },
        { id: "goods", icon: "🐟", title: "Trabajos y hallazgos", re: /^(fish_|old_boot|message_bottle|pearl|meat_|hide_|antlers|ore_|gem_|old_|gold_ring|rare_vinyl|broken_phone)/ },
        { id: "other", icon: "📦", title: "Otros" }
    ];
    function categoryOf(item) {
        for (var i = 1; i < TABS.length - 1; i++) if (TABS[i].re.test(item.id)) return TABS[i].id;
        return "other";
    }

    // ---- Iconos ----
    function iconNode(item, className) {
        var node = el("span", className || "icon");
        if (item.iconImg) {
            var img = document.createElement("img");
            img.src = item.iconImg;
            img.draggable = false;
            node.appendChild(img);
        } else {
            node.textContent = item.icon || "📦";
        }
        return node;
    }

    function keyOf(item) { return (item.bp ? "bp:" : "") + item.id; }
    function sectionOf(item) { return item.bp ? "bp" : "base"; }
    function findItem(id, inBp) {
        return state.items.filter(function (it) { return it.id === id && !!it.bp === !!inBp; })[0];
    }

    // ---- Posiciones de las casillas ----
    // layout[bloque][clave] = numero de casilla. Cada item se queda donde lo dejes; los nuevos van al primer
    // hueco libre. Se guarda en el cliente por personaje (Lua) para que sobreviva a reconectar.
    function place(list, section, minTotal) {
        var map = layout[section];
        var cells = [];
        var rest = [];
        list.forEach(function (it) {
            var idx = map[keyOf(it)];
            if (typeof idx === "number" && idx >= 0 && idx < MAX_CELLS && !cells[idx]) cells[idx] = it;
            else rest.push(it);
        });
        rest.forEach(function (it) {
            var i = 0;
            while (cells[i]) i++;
            cells[i] = it;
            map[keyOf(it)] = i;
        });
        return { cells: cells, total: Math.max(minTotal, Math.ceil(cells.length / 6) * 6) };
    }

    // Con una pestaña activa se muestran solo los de esa categoria, juntos (sin huecos)
    function placeFiltered(list, section, minTotal) {
        var placed = place(list, section, 0);
        var cells = placed.cells.filter(function (it) { return it && categoryOf(it) === state.filter; });
        return { cells: cells, total: Math.max(minTotal, Math.ceil(cells.length / 6) * 6) };
    }

    function saveLayout() { send("rp:inv:ui:layout", JSON.stringify(layout)); }

    // ---- Casillas ----
    function equippedWeapon() { return state.char.weaponItem || null; }

    function itemSlot(item) {
        var cls = "slot item" + (item.bp ? " bp" : "") + (menuItem && keyOf(menuItem) === keyOf(item) ? " selected" : "");
        if (!item.bp && item.id === equippedWeapon()) cls += " equipped";
        var slot = el("div", cls);
        slot.appendChild(iconNode(item));
        if (item.amount > 1) slot.appendChild(el("span", "qty", item.amount));
        slot.appendChild(el("span", "kg", (item.weight * item.amount).toFixed(1)));
        bindItem(slot, item, "inv");
        return slot;
    }

    function addCells(grid, section, placed) {
        for (var i = 0; i < placed.total; i++) {
            var it = placed.cells[i];
            var slot = it ? itemSlot(it) : el("div", "slot empty" + (section === "bp" ? " bp" : ""));
            slot.setAttribute("data-sec", section);
            slot.setAttribute("data-idx", i);
            grid.appendChild(slot);
        }
    }

    function renderTabs() {
        var box = $("tabs");
        box.innerHTML = "";
        TABS.forEach(function (t) {
            var count = t.id === "all" ? state.items.length : state.items.filter(function (it) { return categoryOf(it) === t.id; }).length;
            if (t.id !== "all" && count === 0 && state.filter !== t.id) return;   // solo pestañas con algo
            var b = el("button", "tab" + (state.filter === t.id ? " on" : ""), t.icon);
            b.type = "button";
            b.title = t.title + " (" + count + ")";
            b.addEventListener("click", function () {
                state.filter = t.id;
                play("click");
                renderInventory();
            });
            box.appendChild(b);
        });
    }

    function renderInventory() {
        renderTabs();
        var grid = $("grid");
        grid.innerHTML = "";
        var base = state.items.filter(function (it) { return !it.bp; });
        var packed = state.items.filter(function (it) { return it.bp; });
        var filtered = state.filter !== "all";
        addCells(grid, "base", filtered ? placeFiltered(base, "base", MIN_SLOTS) : place(base, "base", MIN_SLOTS));

        var zone = $("bp-zone");
        zone.innerHTML = "";
        if (!state.bp) return;
        var head = el("div", "bp-head");
        head.appendChild(iconNode(state.bp, "bp-ico"));
        var info = el("div", "bp-info");
        info.appendChild(el("strong", null, state.bp.name));
        info.appendChild(el("span", null, state.bp.used.toFixed(1) + " / " + state.bp.capacity + " kg en la mochila"));
        var bar = el("div", "bar");
        var fill = el("div");
        fill.style.width = Math.min(100, state.bp.capacity > 0 ? state.bp.used / state.bp.capacity * 100 : 0) + "%";
        bar.appendChild(fill);
        info.appendChild(bar);
        head.appendChild(info);
        zone.appendChild(head);
        var bpGrid = el("div", "grid grid-6");
        bpGrid.id = "bp-grid";
        addCells(bpGrid, "bp", filtered ? placeFiltered(packed, "bp", state.bp.slots || 0) : place(packed, "bp", state.bp.slots || 0));
        zone.appendChild(bpGrid);
    }

    // Peso total (inventario + mochila equipada)
    function renderWeight() {
        var total = state.weight + (state.bp ? state.bp.used : 0);
        var cap = state.max + (state.bp ? state.bp.capacity : 0);
        var ratio = cap > 0 ? Math.min(1, total / cap) : 0;
        $("weight-label").textContent = total.toFixed(1) + "/" + cap + " KG";
        $("weight-label").title = state.bp ? "Inventario " + state.max + " kg + mochila " + state.bp.capacity + " kg" : "";
        var bar = $("weight-bar");
        bar.style.width = (ratio * 100) + "%";
        bar.style.background = ratio > 0.9 ? "#e5484d" : ratio > 0.7 ? "#f5a524" : "#4cd38a";
    }

    // ---- Cerca de ti ----
    function renderGround() {
        var grid = $("ground");
        grid.innerHTML = "";
        var n = Math.max(9, Math.ceil(state.ground.length / 3) * 3);
        for (var i = 0; i < n; i++) {
            var g = state.ground[i];
            if (!g) { grid.appendChild(el("div", "slot empty ground")); continue; }
            var slot = el("div", "slot item ground");
            slot.appendChild(iconNode(g));
            if (g.amount > 1) slot.appendChild(el("span", "qty", g.amount));
            bindItem(slot, g, "ground");
            grid.appendChild(slot);
        }
    }

    function renderPeople() {
        var list = $("people");
        list.innerHTML = "";
        if (!state.nearby.length) {
            list.appendChild(el("p", "empty-note", "Nadie cerca. Acércate a alguien para darle cosas."));
            return;
        }
        state.nearby.forEach(function (p) {
            var card = el("div", "person");
            card.setAttribute("data-id", p.id);
            var who = el("span", "who", p.name + " ");
            who.appendChild(el("small", null, "(" + p.id + ")"));
            card.appendChild(who);
            card.appendChild(el("span", "give-hint", "suelta aquí"));
            list.appendChild(card);
        });
    }

    // ---- Personaje ----
    var EQUIP = [
        { id: "weapon", label: "Arma", ph: "🔫", accepts: /^wpn_/ },
        { id: "vest", label: "Chaleco", ph: "🦺", accepts: /^(vest|pol_vest)$/ },
        { id: "pack", label: "Mochila", ph: "🎒", accepts: /^bp_/ },
        { id: "phone", label: "Teléfono", ph: "📱", accepts: /^phone$/ },
        { id: "idcard", label: "DNI", ph: "🆔", accepts: /^id_card$/ },
        { id: "license", label: "Licencia", ph: "🪪", accepts: /^driver_license$/ }
    ];

    // Que hay en cada hueco ahora mismo (null = vacio)
    function equipContent(slot) {
        switch (slot.id) {
            case "weapon": return equippedWeapon() ? findItem(equippedWeapon(), false) || null : null;
            case "vest": return state.char.armor > 0
                ? { id: "vest", name: "Chaleco puesto", iconImg: ICON_DIR + "vest.webp", description: "Blindaje " + Math.round(state.char.armor) + " %." }
                : null;
            case "pack": return state.bp ? { id: "pack", name: state.bp.name, iconImg: state.bp.iconImg, icon: state.bp.icon,
                description: state.bp.used.toFixed(1) + " / " + state.bp.capacity + " kg. Arrástrala fuera para tirarla con todo." } : null;
            case "phone": return findItem("phone", false) || null;
            case "idcard": return findItem("id_card", false) || null;
            case "license": return findItem("driver_license", false) || null;
        }
        return null;
    }

    function renderCharacter() {
        $("char-name").textContent = state.char.name || "";
        $("hp-bar").style.width = Math.max(0, Math.min(100, state.char.health || 0)) + "%";
        $("ar-bar").style.width = Math.max(0, Math.min(100, state.char.armor || 0)) + "%";
        var box = $("equip");
        box.innerHTML = "";
        EQUIP.forEach(function (def) {
            var wrap = el("div", "eq");
            var content = equipContent(def);
            var slot = el("div", "slot " + (content ? "item" : "empty"));
            slot.setAttribute("data-eq", def.id);
            if (content) {
                slot.appendChild(iconNode(content));
                if (def.id === "weapon") bindItem(slot, content, "weapon");
                else if (def.id === "pack") bindItem(slot, content, "pack");
                else if (def.id !== "vest") bindItem(slot, content, "inv");
                else bindTooltip(slot, content);
            } else {
                slot.appendChild(el("span", "ph", def.ph));
                slot.title = "Arrastra aquí: " + def.label.toLowerCase();
            }
            wrap.appendChild(slot);
            wrap.appendChild(el("label", null, def.label));
            box.appendChild(wrap);
        });
    }

    function renderAll() {
        renderInventory();
        renderWeight();
        renderGround();
        renderPeople();
        renderCharacter();
    }

    // ---- Tooltip ----
    var tip = $("tooltip");
    function hint(img, text) {
        var s = el("span");
        if (img) {
            var i = document.createElement("img");
            i.className = "key-ico";
            i.src = "keys/" + img + ".png";
            s.appendChild(i);
        }
        s.appendChild(document.createTextNode(text));
        return s;
    }

    function showTip(item, kind, x, y) {
        if (drag && drag.active) return;
        if ($("menu").style.display === "block") return;
        tip.innerHTML = "";
        tip.appendChild(el("h4", null, item.name + (item.amount > 1 ? " ×" + item.amount : "")));
        if (item.description) tip.appendChild(el("p", null, item.description));
        if (typeof item.weight === "number") tip.appendChild(el("div", "meta", (item.weight * (item.amount || 1)).toFixed(2) + " kg" + (item.bp ? " · en la mochila" : "")));
        var acts = el("div", "acts");
        if (kind === "ground") {
            acts.appendChild(hint("mouse_left", " ×2 recoger"));
            acts.appendChild(hint("mouse_move", " arrastra al inventario"));
        } else if (kind === "pack") {
            acts.appendChild(hint("mouse_move", " arrastra fuera para tirarla"));
        } else if (kind === "weapon") {
            acts.appendChild(hint("mouse_left", " ×2 guardar el arma"));
        } else if (item.weight !== undefined) {
            if (item.usable) acts.appendChild(hint("mouse_left", " ×2 " + useLabel(item).toLowerCase()));
            acts.appendChild(hint("mouse_right", " más opciones"));
        }
        if (acts.childNodes.length) tip.appendChild(acts);
        tip.style.display = "block";
        moveTip(x, y);
    }
    function moveTip(x, y) {
        var w = tip.offsetWidth, h = tip.offsetHeight;
        var left = x + 16, top = y + 16;
        if (left + w > window.innerWidth - 8) left = x - w - 12;
        if (top + h > window.innerHeight - 8) top = window.innerHeight - h - 8;
        tip.style.left = left + "px";
        tip.style.top = top + "px";
    }
    function hideTip() { tip.style.display = "none"; }

    function bindTooltip(node, item, kind) {
        node.addEventListener("mouseenter", function (e) { showTip(item, kind, e.clientX, e.clientY); });
        node.addEventListener("mousemove", function (e) { if (tip.style.display === "block") moveTip(e.clientX, e.clientY); });
        node.addEventListener("mouseleave", hideTip);
    }

    // ---- Acciones ----
    function useLabel(item) {
        if (/^wpn_/.test(item.id)) return item.id === equippedWeapon() ? "Guardar" : "Equipar";
        if (/^bp_/.test(item.id)) return "Ponerse";
        if (/^(id_card|driver_license)$/.test(item.id)) return "Ver";
        if (item.id === "phone") return "Abrir";
        return "Usar";
    }

    function useItem(item) {
        if (!item || !item.usable) return;
        if (item.bp) { play("error"); return; }   // primero hay que sacarlo de la mochila
        play("click");
        send("rp:inv:ui:use", item.id);
    }

    function pickup(g) { play("drop"); send("rp:inv:ui:pickup", g.ref); }

    function bindItem(node, item, kind) {
        bindTooltip(node, item, kind);
        node.addEventListener("mousedown", function (e) {
            if (e.button !== 0) return;
            hideMenu();
            drag = { kind: kind, item: item, amount: e.shiftKey ? 1 : (item.amount || 1), startX: e.clientX, startY: e.clientY, active: false, node: node };
        });
        node.addEventListener("dblclick", function () {
            if (kind === "ground") pickup(item);
            else if (kind === "weapon") useItem(item);
            else if (kind === "inv") useItem(item);
        });
        if (kind === "inv") {
            node.addEventListener("contextmenu", function (e) {
                e.preventDefault();
                openMenu(item, e.clientX, e.clientY);
            });
        }
    }

    // ---- Menu de clic derecho ----
    function hideMenu() {
        $("menu").style.display = "none";
        if (menuItem) { menuItem = null; renderInventory(); }
    }

    function openMenu(item, x, y) {
        hideTip();
        menuItem = item;
        renderInventory();
        var m = $("menu");
        m.innerHTML = "";
        m.appendChild(el("h4", null, item.name));
        var qty = null;
        if (item.amount > 1) {
            var row = el("div", "qty-row");
            row.appendChild(el("span", null, "Cantidad"));
            var minus = el("button", null, "−");
            qty = el("input");
            qty.type = "number";
            qty.min = 1;
            qty.max = item.amount;
            qty.value = 1;
            var plus = el("button", null, "+");
            var all = el("button", null, "∀");
            all.title = "Todo";
            minus.type = plus.type = all.type = "button";
            minus.addEventListener("click", function () { qty.value = Math.max(1, (parseInt(qty.value, 10) || 1) - 1); });
            plus.addEventListener("click", function () { qty.value = Math.min(item.amount, (parseInt(qty.value, 10) || 1) + 1); });
            all.addEventListener("click", function () { qty.value = item.amount; });
            row.appendChild(minus);
            row.appendChild(qty);
            row.appendChild(plus);
            row.appendChild(all);
            m.appendChild(row);
        }
        function amount() { return qty ? Math.max(1, Math.min(item.amount, parseInt(qty.value, 10) || 1)) : 1; }
        function action(label, cls, fn, disabled) {
            var b = el("button", cls, label);
            b.type = "button";
            b.disabled = !!disabled;
            b.addEventListener("click", function () { fn(); hideMenu(); });
            m.appendChild(b);
        }
        if (item.usable) action(useLabel(item), "primary", function () { useItem(item); }, item.bp);
        if (item.bp) {
            action("Sacar de la mochila", null, function () { play("drop"); send("rp:inv:ui:fromBackpack", item.id, amount()); });
        } else if (state.bp && !/^bp_/.test(item.id)) {
            action("Guardar en la mochila", null, function () { play("drop"); send("rp:inv:ui:toBackpack", item.id, amount()); });
        }
        state.nearby.forEach(function (p) {
            action("Dar a " + p.name + " (" + p.id + ")", null, function () { play("ok"); send("rp:inv:ui:give", item.id, amount(), p.id); }, item.bp);
        });
        action("Tirar al suelo", "danger", function () { play("drop"); send("rp:inv:ui:drop", item.id, amount()); }, item.bp);

        m.style.display = "block";
        var w = m.offsetWidth, h = m.offsetHeight;
        m.style.left = Math.min(x, window.innerWidth - w - 8) + "px";
        m.style.top = Math.min(y, window.innerHeight - h - 8) + "px";
    }

    document.addEventListener("mousedown", function (e) {
        var m = $("menu");
        if (m.style.display === "block" && !m.contains(e.target)) hideMenu();
    });
    document.addEventListener("contextmenu", function (e) { e.preventDefault(); });

    // ---- Arrastrar ----
    function inRect(node, x, y) {
        if (!node) return false;
        var r = node.getBoundingClientRect();
        return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
    }
    function firstAt(selector, x, y) {
        var nodes = document.querySelectorAll(selector);
        for (var i = 0; i < nodes.length; i++) if (inRect(nodes[i], x, y)) return nodes[i];
        return null;
    }
    function overPanel(x, y) {
        return inRect($("panel-near"), x, y) || inRect($("panel-inv"), x, y) || inRect($("panel-char"), x, y) || inRect(document.querySelector(".topbar"), x, y);
    }

    // Que pasaria si sueltas aqui: { node, run } o null
    function targetAt(d, x, y) {
        var it = d.item;
        if (d.kind === "inv") {
            var person = firstAt(".person", x, y);
            if (person) return { node: person, run: function () {
                if (it.bp) { play("error"); return; }
                play("ok");
                send("rp:inv:ui:give", it.id, d.amount, parseInt(person.getAttribute("data-id"), 10));
            } };
            var eq = firstAt("[data-eq]", x, y);
            if (eq) {
                var def = EQUIP.filter(function (q) { return q.id === eq.getAttribute("data-eq"); })[0];
                if (def && def.accepts.test(it.id) && it.usable) return { node: eq, run: function () { useItem(it); } };
                return null;
            }
            var cell = firstAt("#grid .slot, #bp-grid .slot", x, y);
            if (cell) return { node: cell, run: function () { moveTo(d, cell.getAttribute("data-sec"), parseInt(cell.getAttribute("data-idx"), 10)); } };
            if (inRect($("panel-near"), x, y)) return { node: $("ground"), run: function () {
                if (it.bp) { play("error"); return; }
                play("drop");
                send("rp:inv:ui:drop", it.id, d.amount);
            } };
            if (!overPanel(x, y)) return { node: null, out: true, run: function () {
                if (it.bp) { play("error"); return; }
                play("drop");
                send("rp:inv:ui:dropAt", it.id, d.amount, x, y);
            } };
            return null;
        }
        if (d.kind === "ground") {
            if (inRect($("panel-inv"), x, y)) return { node: firstAt("#grid .slot", x, y), run: function () { pickup(it); } };
            return null;
        }
        if (d.kind === "weapon") {
            if (inRect($("panel-inv"), x, y)) return { node: firstAt("#grid .slot", x, y), run: function () { useItem(it); } };
            return null;
        }
        if (d.kind === "pack") {
            if (!overPanel(x, y) || inRect($("panel-near"), x, y)) return { node: inRect($("panel-near"), x, y) ? $("ground") : null, out: !overPanel(x, y), run: function () {
                play("drop");
                send("rp:inv:ui:dropBackpack");
            } };
            return null;
        }
        return null;
    }

    // Soltar en una casilla: dentro del mismo bloque la coloca (o intercambia); entre bloques guarda o saca
    function moveTo(d, section, idx) {
        var item = d.item;
        var from = sectionOf(item);
        var key = keyOf(item);
        if (from === section) {
            if (state.filter !== "all") return;   // con una pestaña activa no se reordena
            var map = layout[from];
            var current = map[key];
            if (current === idx) return;
            state.items.forEach(function (it) {
                if (sectionOf(it) === from && keyOf(it) !== key && map[keyOf(it)] === idx) map[keyOf(it)] = current;   // intercambio
            });
            map[key] = idx;
            play("drop");
            saveLayout();
            renderInventory();
            return;
        }
        if (section === "bp" && (!state.bp || /^bp_/.test(item.id))) { play("error"); return; }   // una mochila no va en otra
        var newKey = (section === "bp" ? "bp:" : "") + item.id;
        var exists = state.items.some(function (it) { return keyOf(it) === newKey; });
        if (!exists && state.filter === "all") {
            layout[section][newKey] = idx;
            saveLayout();
        }
        play("drop");
        send(section === "bp" ? "rp:inv:ui:toBackpack" : "rp:inv:ui:fromBackpack", item.id, d.amount);
    }

    var lastHover = null;
    function setHover(node) {
        if (lastHover === node) return;
        if (lastHover) lastHover.classList.remove("drop-hover");
        lastHover = node;
        if (node) node.classList.add("drop-hover");
    }

    function highlightEquip(on, item) {
        var slots = document.querySelectorAll("[data-eq]");
        for (var i = 0; i < slots.length; i++) {
            var def = EQUIP.filter(function (q) { return q.id === slots[i].getAttribute("data-eq"); })[0];
            slots[i].classList.toggle("can-drop", !!(on && item && def && def.accepts.test(item.id) && item.usable));
        }
    }

    document.addEventListener("mousemove", function (e) {
        if (!drag) return;
        if (!drag.active) {
            if (Math.abs(e.clientX - drag.startX) + Math.abs(e.clientY - drag.startY) < DRAG_THRESHOLD) return;
            drag.active = true;
            hideTip();
            var ghost = $("ghost");
            ghost.innerHTML = "";
            var ic = iconNode(drag.item);
            ghost.className = "ghost slot";
            ghost.appendChild(ic);
            if (drag.amount > 1) ghost.appendChild(el("span", "qty", drag.amount));
            ghost.style.display = "block";
            drag.node.classList.add("dragging-src");
            document.body.classList.add("dragging");
            if (drag.kind === "inv") highlightEquip(true, drag.item);
        }
        var g = $("ghost");
        g.style.left = e.clientX + "px";
        g.style.top = e.clientY + "px";
        var t = targetAt(drag, e.clientX, e.clientY);
        document.body.classList.toggle("dragging-out", !!(t && t.out));
        setHover(t ? t.node : null);
    });

    document.addEventListener("mouseup", function (e) {
        if (!drag) return;
        var d = drag;
        drag = null;
        if (!d.active) return;
        document.body.classList.remove("dragging", "dragging-out");
        $("ghost").style.display = "none";
        if (d.node) d.node.classList.remove("dragging-src");
        setHover(null);
        highlightEquip(false);
        var t = targetAt(d, e.clientX, e.clientY);
        if (t) t.run();
    });

    function close() {
        hideMenu();
        hideTip();
        play("close");
        send("rp:inv:ui:close");
    }

    $("btn-close").addEventListener("click", close);
    document.addEventListener("keydown", function (e) {
        if (document.activeElement && document.activeElement.tagName === "INPUT" && e.key !== "Escape") return;
        if (e.key === "Escape" && $("menu").style.display === "block") { hideMenu(); return; }
        if (e.key === "Escape" || e.key === "i" || e.key === "I") {
            e.preventDefault();
            close();
        }
    });

    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

    window.RP = {
        render: function (items, weight, maxWeight, bp) {
            state.items = Array.isArray(items) ? items : [];
            state.bp = bp && bp.name ? bp : null;
            state.weight = Number(weight) || 0;
            state.max = Number(maxWeight) || 0;
            if (menuItem) {   // el menu apunta a un item que puede haber cambiado
                $("menu").style.display = "none";
                menuItem = null;
            }
            if (drag && drag.active) return;   // no reconstruir mientras se arrastra
            renderAll();
        },
        // Posiciones guardadas de las casillas (JSON); Lua las envia al crear el navegador, antes del primer render
        setLayout: function (json) {
            try {
                var saved = JSON.parse(json);
                ["base", "bp"].forEach(function (s) {
                    var src = saved && saved[s] || {};
                    Object.keys(src).forEach(function (k) {
                        if (typeof src[k] === "number" && src[k] >= 0 && src[k] < MAX_CELLS) layout[s][k] = Math.floor(src[k]);
                    });
                });
            } catch (e) { /* archivo corrupto: se ignora */ }
        },
        nearby: function (list) {
            var next = Array.isArray(list) ? list : [];
            if (same(next, state.nearby)) return;   // solo redibuja si cambia (evita parpadeo)
            state.nearby = next;
            if (!(drag && drag.active)) renderPeople();
        },
        // Objetos del suelo al alcance: [{ ref, id, name, icon, iconImg, amount }]
        ground: function (list) {
            var next = Array.isArray(list) ? list : [];
            if (same(next, state.ground)) return;
            state.ground = next;
            if (!(drag && drag.active)) renderGround();
        },
        // { name, health, armor, weaponItem }
        character: function (c) {
            c = c || {};
            if (same(c, state.char)) return;
            state.char = c;
            if (drag && drag.active) return;
            renderCharacter();
            renderInventory();
        },
        opened: function () {
            state.filter = "all";
            hideMenu();
            hideTip();
            play("open");
            renderAll();
        }
    };

    // Vista previa sin el juego (index.html#demo)
    if (!window.mta && location.hash === "#demo") {
        var I = function (id, name, amount, w, usable) { return { id: id, name: name, amount: amount, weight: w, usable: usable, iconImg: ICON_DIR + id + ".webp", description: "Descripción de ejemplo." }; };
        window.RP.character({ name: "Carl Johnson", health: 82, armor: 40, weaponItem: "wpn_colt45" });
        window.RP.nearby([{ id: 3, name: "Lance Vance" }]);
        window.RP.ground([{ ref: 1, id: "burger", name: "Hamburguesa", iconImg: ICON_DIR + "burger.webp", amount: 2 }]);
        var demo = [I("water", "Botella de agua", 5, 0.5, true), I("burger", "Hamburguesa", 3, 0.4, true), I("phone", "Teléfono móvil", 1, 0.2, true),
            I("id_card", "DNI", 1, 0.02, true), I("medkit", "Botiquín", 2, 1, true), I("ammo_pistol", "Munición de pistola", 60, 0.02, false),
            { id: "wpn_colt45", name: "Colt 45", icon: "🔫", amount: 1, weight: 1, usable: true }, I("ore_gold", "Pepita de oro", 4, 0.2, false)];
        var packed = I("snack_chips", "Papas fritas", 2, 0.15, true);
        packed.bp = true;
        demo.push(packed);
        window.RP.render(demo, 6.2, 15, { name: "Mochila escolar", iconImg: ICON_DIR + "bp_school.webp", capacity: 10, used: 0.3, slots: 12 });
    }
})();
