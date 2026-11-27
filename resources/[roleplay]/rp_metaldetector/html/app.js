/*
 * rp_metaldetector / app.js
 * Panel del detector: Tienda (solo junto al vendedor), Progreso y Colección.
 * Lua llama a RP.show(datos) y RP.bought(tipo, índice). El JS solo pide; el servidor valida todo.
 * Eventos: rp:metaldetector:ui:close, rp:metaldetector:ui:buy(tipo, índice).
 * Modo demo: abrir index.html en un navegador (#shop, #progress, #collection).
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };
    var state = null, tab = "shop", selected = null, pending = null;

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    function el(tag, className, text) {
        var n = document.createElement(tag);
        if (className) n.className = className;
        if (text !== undefined) n.textContent = text;
        return n;
    }

    function money(n) { return "$" + Number(n || 0).toLocaleString("es"); }

    function hexA(hex, a) {
        var h = String(hex || "#f5a524").replace("#", "");
        var r = parseInt(h.substr(0, 2), 16), g = parseInt(h.substr(2, 2), 16), b = parseInt(h.substr(4, 2), 16);
        return "rgba(" + r + "," + g + "," + b + "," + a + ")";
    }

    function setTierVars(node, hex) {
        node.style.setProperty("--tier-c", hex);
        node.style.setProperty("--tier-a35", hexA(hex, 0.35));
        node.style.setProperty("--tier-a55", hexA(hex, 0.55));
        node.style.setProperty("--tier-a60", hexA(hex, 0.6));
        node.style.setProperty("--tier-a10", hexA(hex, 0.1));
    }

    // Imagen del detector: render del modelo; si aún no existe, el icono genérico
    function detectorImg(index) {
        var img = el("img");
        img.src = "../images/detectors/detector_" + index + ".png";
        img.onerror = function () { img.onerror = null; img.src = "../images/items/metal_detector.png"; };
        return img;
    }

    // ---------------------------------------------------------------- sonidos (UX-06)
    var SOUNDS = {
        click: ["click_002.ogg"], select: ["select_002.ogg"], open: ["maximize_003.ogg"], close: ["minimize_003.ogg"],
        buy: ["confirmation_001.ogg"], coins: ["coins.wav"], error: ["error_004.ogg"], coach: ["pluck_001.ogg"],
    };
    function play(name) {
        var list = SOUNDS[name];
        if (!list) return;
        try { var a = new Audio("sounds/" + list[Math.floor(Math.random() * list.length)]); a.volume = 0.5; a.play(); } catch (e) { /* sin audio */ }
    }

    // ---------------------------------------------------------------- pestañas
    function setTab(name) {
        tab = name;
        ["shop", "progress", "collection"].forEach(function (t) {
            $("tab-" + t).classList.toggle("on", t === name);
            $("view-" + t).classList.toggle("on", t === name);
        });
        renderCoach();
    }
    Array.prototype.forEach.call(document.querySelectorAll(".tab"), function (b) {
        b.addEventListener("click", function () { play("click"); setTab(b.getAttribute("data-tab")); });
    });

    // ---------------------------------------------------------------- tienda
    function shopEntries() {
        var list = state.tiers.map(function (t) { return { kind: "tier", data: t }; });
        list.push({ kind: "shovel", data: state.shovel });
        return list;
    }

    function entryKey(e) { return e.kind + (e.kind === "tier" ? e.data.index : ""); }

    function renderShop() {
        var view = $("view-shop");
        view.classList.toggle("closed", !state.canShop);
        var list = $("tier-list");
        list.textContent = "";
        var entries = shopEntries();
        if (!selected || !entries.some(function (e) { return entryKey(e) === selected; })) {
            var firstBuyable = entries.filter(function (e) { return e.kind === "tier" && !e.data.locked && !e.data.owned; }).pop();
            selected = entryKey(firstBuyable || entries[0]);
        }
        entries.forEach(function (e) {
            var isTier = e.kind === "tier", d = e.data;
            var color = isTier ? d.color : "#b0763a";
            var row = el("div", "tier");
            row.id = "row-" + entryKey(e);
            setTierVars(row, color);
            if (isTier && d.locked) row.classList.add("locked");
            if (entryKey(e) === selected) row.classList.add("sel");
            var ico = el("div", "tier-ico");
            if (isTier) ico.appendChild(detectorImg(d.index));
            else { var s = el("img"); s.src = "../images/items/shovel.png"; ico.appendChild(s); }
            var mid = el("div");
            var name = el("div", "tier-name", isTier ? d.name : "Pala");
            name.appendChild(el("span", "price", money(d.price)));
            mid.appendChild(name);
            mid.appendChild(el("div", "tier-desc", isTier ? d.desc : "Imprescindible para desenterrar lo que encuentra el detector."));
            var badge;
            if (isTier && state.equipped === d.index) badge = el("span", "badge hand", "En la mano");
            else if (d.owned) badge = el("span", "badge own", "Lo tienes");
            else if (isTier && d.locked) badge = el("span", "badge lock", "🔒 Nivel " + d.level);
            else badge = el("span");
            row.appendChild(ico); row.appendChild(mid); row.appendChild(badge);
            row.addEventListener("click", function () { selected = entryKey(e); play("select"); renderShop(); renderCoach(); });
            list.appendChild(row);
        });
        renderPreview(entries.filter(function (e) { return entryKey(e) === selected; })[0]);
    }

    function statRow(label, value, note) {
        var wrap = el("div");
        var r = el("div", "stat-row");
        r.appendChild(el("span", "", label));
        var bar = el("div", "stat-bar"), fill = el("i");
        fill.style.width = (value * 10) + "%";
        bar.appendChild(fill); r.appendChild(bar);
        r.appendChild(el("b", "", value + "/10"));
        wrap.appendChild(r);
        if (note) wrap.appendChild(el("div", "stat-note", note));
        return wrap;
    }

    function renderPreview(e) {
        if (!e) return;
        var isTier = e.kind === "tier", d = e.data;
        var pv = $("preview");
        setTierVars(pv, isTier ? d.color : "#b0763a");
        pv.style.setProperty("--tier", isTier ? d.color : "#b0763a");
        var img = $("pv-img");
        img.onerror = function () { img.onerror = null; img.src = "../images/items/metal_detector.png"; };
        img.src = isTier ? "../images/detectors/detector_" + d.index + ".png" : "../images/items/shovel.png";
        $("pv-name").textContent = isTier ? "Detector " + d.name : "Pala";
        $("pv-desc").textContent = isTier ? d.desc : "Sin pala no puedes desenterrar nada. Una sola vale para siempre.";
        var stats = $("pv-stats"), reach = $("pv-reach");
        stats.textContent = ""; reach.textContent = "";
        if (isTier) {
            stats.appendChild(statRow("Alcance", d.radius, "Empieza a sonar a " + d.range + " m"));
            stats.appendChild(statRow("Profundidad", d.depth, "Llega hasta " + d.maxDepth + " cm"));
            stats.appendChild(statRow("Precisión", d.accuracy, "Lectura del metal más fiable"));
            // Lo más valioso a su alcance
            var seen = {};
            state.collection.filter(function (c) { return c.depth <= d.maxDepth; })
                .sort(function (a, b) { return b.order - a.order; })
                .forEach(function (c) {
                    if (seen[c.rarity] || Object.keys(seen).length >= 3) return;
                    seen[c.rarity] = true;
                    var chip = el("span", "", c.rarity);
                    chip.style.color = c.color;
                    reach.appendChild(chip);
                });
        }
        var buy = $("pv-buy");
        buy.disabled = false;
        if (d.owned) { buy.textContent = "Ya lo tienes"; buy.disabled = true; }
        else if (isTier && d.locked) { buy.textContent = "🔒 Requiere nivel " + d.level + " de buscador"; buy.disabled = true; }
        else buy.textContent = "Comprar · " + money(d.price);
        buy.onclick = function () { if (!buy.disabled) askBuy(e); };
    }

    function askBuy(e) {
        var isTier = e.kind === "tier", d = e.data;
        pending = e;
        play("click");
        var modal = $("modal");
        setTierVars(modal, isTier ? d.color : "#b0763a");
        modal.style.setProperty("--tier", isTier ? d.color : "#b0763a");
        $("m-title").textContent = isTier ? "Detector " + d.name : "Pala";
        var p = $("m-text");
        p.textContent = "";
        p.appendChild(document.createTextNode(isTier ? "Este detector cuesta " : "La pala cuesta "));
        p.appendChild(el("b", "", money(d.price)));
        if (isTier) {
            p.appendChild(document.createTextNode(" y requiere nivel "));
            p.appendChild(el("b", "", String(d.level)));
            p.appendChild(document.createTextNode(" de buscador."));
        } else p.appendChild(document.createTextNode("."));
        p.appendChild(document.createTextNode(" ¿Quieres comprarlo?"));
        if (state.money < d.price) {
            p.appendChild(el("br"));
            var warn = el("b", "", "No te alcanza el efectivo (" + money(state.money) + ").");
            warn.style.color = "var(--danger)";
            p.appendChild(warn);
        }
        modal.classList.add("on");
    }
    $("m-cancel").addEventListener("click", function () { pending = null; $("modal").classList.remove("on"); play("close"); });
    $("m-ok").addEventListener("click", function () {
        if (!pending) return;
        send("rp:metaldetector:ui:buy", pending.kind, pending.kind === "tier" ? pending.data.index : 0);
        pending = null;
        $("modal").classList.remove("on");
    });

    // ---------------------------------------------------------------- progreso
    var TITLES = ["Buscador novato", "Rastreador de arena", "Cazatesoros", "Buscador de oro", "Leyenda de la playa"];

    function renderProgress() {
        var s = state;
        $("ring-level").textContent = s.level;
        var pct = s.nextXp ? Math.round(100 * (s.xp - s.levelXp) / (s.nextXp - s.levelXp)) : 100;
        $("ring").style.setProperty("--p", pct);
        $("level-title").textContent = TITLES[s.level - 1] || "Buscador";
        $("xp-fill").style.width = pct + "%";
        $("xp-text").textContent = s.nextXp ? (s.xp + " / " + s.nextXp + " XP · te faltan " + (s.nextXp - s.xp)) : (s.xp + " XP · nivel máximo");
        var next = s.tiers[s.level];
        $("level-next").textContent = next ? ("Siguiente nivel: desbloquea el detector " + next.name + ".") : "Tienes todos los detectores desbloqueados.";
        $("t-items").textContent = Number(s.itemsFound).toLocaleString("es");
        $("t-money").textContent = money(s.moneyEarned);
        $("t-col").textContent = s.distinct + " / " + s.finds;
        $("t-eq").textContent = s.equipped ? s.tiers[s.equipped - 1].name : "Ninguno";
        var ladder = $("ladder");
        ladder.textContent = "";
        s.tiers.forEach(function (t) {
            var st = el("div", "step " + (t.locked ? "todo" : "done"));
            setTierVars(st, t.color);
            st.appendChild(detectorImg(t.index));
            st.appendChild(el("b", "", t.name));
            st.appendChild(document.createTextNode((t.locked ? "🔒 " : "✓ ") + "Nivel " + t.level));
            ladder.appendChild(st);
        });
    }

    // ---------------------------------------------------------------- colección
    function renderCollection() {
        var head = $("col-head");
        head.textContent = "";
        head.appendChild(el("b", "", state.distinct + " de " + state.finds));
        head.appendChild(document.createTextNode(" descubiertos. Lo que falta sale como silueta: los objetos más hondos necesitan un detector mejor."));
        var grid = $("grid");
        grid.textContent = "";
        state.collection.forEach(function (c) {
            var found = c.times > 0;
            var card = el("div", "card" + (found ? "" : " missing"));
            card.style.setProperty("--rc", c.color);
            var img = el("img");
            img.src = "../images/items/" + c.item + ".png";
            card.appendChild(img);
            card.appendChild(el("div", "nm", found ? c.name : "???"));
            card.appendChild(el("div", "rr", c.rarity));
            card.appendChild(el("div", "ct", found ? ("x" + c.times + (c.price ? " · ≈ " + money(c.price) : "")) : ("~" + c.depth + " cm")));
            grid.appendChild(card);
        });
    }

    // ---------------------------------------------------------------- entrenador (UX-05): primera compra
    function renderCoach() {
        var bubble = $("coach");
        Array.prototype.forEach.call(document.querySelectorAll(".coach-spot"), function (n) { n.classList.remove("coach-spot"); });
        bubble.classList.remove("on");
        if (!state || tab !== "shop" || !state.canShop) return;
        var hasDetector = state.tiers.some(function (t) { return t.owned; });
        var target, title, text;
        if (!hasDetector) {
            target = selected === "tier1" ? $("pv-buy") : $("row-tier1");
            title = "Paso 1 de 2";
            text = selected === "tier1" ? "Compra el Pionero: es el detector de tu nivel." : "Empieza por el Pionero: haz clic en él.";
        } else if (!state.shovel.owned) {
            target = selected === "shovel" ? $("pv-buy") : $("row-shovel");
            title = "Paso 2 de 2";
            text = selected === "shovel" ? "Compra la pala." : "Te falta la pala para desenterrar lo que encuentres.";
        } else return;
        if (!target) return;
        target.classList.add("coach-spot");
        if (target.scrollIntoView) target.scrollIntoView({ block: "nearest" });
        bubble.textContent = "";
        bubble.appendChild(el("b", "", title));
        bubble.appendChild(document.createTextNode(text));
        bubble.classList.add("on");
        // Pegada al elemento: debajo si cabe, si no encima; alineada a su borde derecho (no tapa el nombre)
        var w = $("window").getBoundingClientRect(), r = target.getBoundingClientRect(), b = bubble.getBoundingClientRect();
        bubble.style.left = Math.max(12, Math.min(r.right - w.left - b.width, w.width - b.width - 12)) + "px";
        var below = r.bottom - w.top + 10;
        bubble.style.top = (below + b.height > w.height - 8 ? r.top - w.top - b.height - 10 : below) + "px";
    }

    // ---------------------------------------------------------------- cierre y teclas
    $("btn-close").addEventListener("click", function () { play("close"); send("rp:metaldetector:ui:close"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" || e.key === "Backspace") {
            if ($("modal").classList.contains("on")) { $("modal").classList.remove("on"); pending = null; return; }
            send("rp:metaldetector:ui:close");
        }
    });

    function toast(text) {
        var t = $("toast");
        t.textContent = text;
        t.classList.add("on");
        setTimeout(function () { t.classList.remove("on"); }, 2200);
    }

    // ---------------------------------------------------------------- API para Lua
    window.RP = {
        show: function (data) {
            var first = !state;
            state = data;
            $("subtitle").textContent = data.canShop ? "Equipo de playa · vendedor" : "Tu progreso de buscador";
            $("level-pill").textContent = "Nivel " + data.level + " de buscador";
            $("money").textContent = money(data.money);
            $("tab-shop").style.display = data.canShop ? "" : "none";
            renderShop(); renderProgress(); renderCollection();
            if (first) { play("open"); setTab(data.tab === "shop" && !data.canShop ? "progress" : (data.tab || "shop")); }
            else renderCoach();
        },
        bought: function (kind, index) {
            play("buy"); setTimeout(function () { play("coins"); }, 180);
            var row = $("row-" + kind + (kind === "tier" ? index : ""));
            if (row) { row.classList.remove("flash"); void row.offsetWidth; row.classList.add("flash"); }
            toast(kind === "tier" ? "¡Detector comprado! Úsalo desde el inventario (I)." : "¡Pala comprada!");
        },
        error: function () { play("error"); },
    };

    // ---------------------------------------------------------------- modo demo (sin MTA)
    if (!window.mta) {
        var demoTiers = [
            ["Pionero", 850, 1, "#1f6ff2", 4, 3, 4, 19, 18], ["Rastreador", 2400, 2, "#4cc43a", 5.5, 5, 5.5, 22, 24],
            ["Cazatesoros", 5200, 3, "#d61a14", 7, 6.5, 7, 25, 28], ["Buscador de Oro", 9500, 4, "#ffb805", 8.5, 8, 8.5, 27, 32],
            ["Abisal Pro", 16000, 5, "#c9a227", 10, 10, 10, 30, 37],
        ].map(function (t, i) {
            return { index: i + 1, name: t[0], price: t[1], level: t[2], color: t[3], radius: t[4], depth: t[5], accuracy: t[6], range: t[7], maxDepth: t[8],
                desc: "Descripción de ejemplo del detector.", owned: i === 0, locked: t[2] > 2 };
        });
        var demoCol = [["rusty_can", "Lata oxidada", "Común", 1, "#aab0ba", 10, 3], ["scrap_metal", "Chatarra", "Común", 1, "#aab0ba", 12, 5],
            ["rusty_key", "Llave oxidada", "Común", 1, "#aab0ba", 14, 1], ["lost_keys", "Llavero perdido", "Poco común", 2, "#5ad26e", 12, 2],
            ["old_coin", "Moneda de colección", "Poco común", 2, "#5ad26e", 18, 1], ["old_compass", "Brújula antigua", "Raro", 3, "#46a0ff", 22, 0],
            ["old_watch", "Reloj antiguo", "Raro", 3, "#46a0ff", 20, 1], ["gold_earrings", "Pendientes de oro", "Raro", 3, "#46a0ff", 16, 0],
            ["gold_ring", "Anillo de oro", "Épico", 4, "#b95fff", 24, 0], ["gold_chain", "Cadena de oro", "Épico", 4, "#b95fff", 26, 0],
            ["doubloon", "Doblón pirata", "Legendario", 5, "#ffc432", 30, 0], ["jeweled_tiara", "Tiara enjoyada", "Legendario", 5, "#ffc432", 35, 0]]
            .map(function (c) { return { item: c[0], name: c[1], rarity: c[2], order: c[3], color: c[4], depth: c[5], times: c[6], price: 60 }; });
        var tabDemo = (location.hash || "#shop").slice(1);
        window.RP.show({ tab: tabDemo, canShop: true, money: 3100, level: 2, maxLevel: 5, xp: 230, levelXp: 120, nextXp: 350,
            itemsFound: 13, moneyEarned: 940, distinct: 6, finds: 12, tiers: demoTiers, shovel: { price: 120, owned: false },
            collection: demoCol, equipped: 1 });
    }
})();
