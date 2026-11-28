/*
 * rp_furniture / app.js
 * Una misma pagina para los 4 navegadores: #left (catalogo), #right (inspector y casa),
 * #top (barra de herramientas) y #modal (contenedores y emisoras). Lua llama a
 * FURN.init(datos), FURN.state(estado) y FURN.modal(tipo, datos).
 */
(function () {
    "use strict";

    var PANEL = (location.hash || "#left").slice(1);
    if (PANEL === "modal") { document.documentElement.className = "modal"; document.body.className = "modal"; }
    var app = document.getElementById("app");
    var D = { items: [], cats: [], swatches: [], mats: [], grids: [], rots: [] };
    var S = null;                       // ultimo estado enviado por Lua
    var ui = { cat: "sala", search: "", tab: "obj", confirm: null, bpName: "", member: "" };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }
    function cmd() { send.apply(null, ["rp:furn:ui:cmd"].concat(Array.prototype.slice.call(arguments))); }
    // Los botones reaccionan al pulsar (mousedown), no al soltar: si el panel se reconstruye
    // entre pulsar y soltar, el "click" se pierde y parece que la interfaz no detecta el ratón.
    function press(node, fn) {
        node.addEventListener("mousedown", function (e) {
            if (e.button !== 0) return;
            e.preventDefault();
            fn(e);
        });
    }

    function el(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text !== undefined) n.textContent = text;
        return n;
    }
    function btn(text, cls, fn) {
        var b = el("button", cls || "", text);
        press(b, fn);
        return b;
    }
    function obj(x) { return (!x || Array.isArray(x)) ? {} : x; }
    function arr(x) { return Array.isArray(x) ? x : []; }
    function money(n) { return "$" + String(Math.floor(n || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ","); }
    function hex(c) { return "#" + ("000000" + (c >>> 0).toString(16)).slice(-6); }

    // Solo cuenta como "escribiendo" si el usuario hizo clic en el campo: el foco automatico del
    // navegador (buscador al cargar) activaba el modo de escritura y bloqueaba camara y atajos.
    var lastDown = 0;
    document.addEventListener("mousedown", function () { lastDown = Date.now(); }, true);
    document.addEventListener("focusin", function (e) {
        if (/^(INPUT|TEXTAREA)$/.test(e.target.tagName) && e.target.type !== "range") {
            if (Date.now() - lastDown > 800) { e.target.blur(); return; }
            cmd("typing", true);
        }
    });
    document.addEventListener("focusout", function (e) {
        if (/^(INPUT|TEXTAREA)$/.test(e.target.tagName)) cmd("typing", false);
    });

    function confirmBtn(id, text, fn, cls) {
        var asking = ui.confirm === id;
        return btn(asking ? "¿Seguro?" : text, (cls || "") + (asking ? " danger" : ""), function () {
            if (asking) { ui.confirm = null; fn(); } else { ui.confirm = id; render(); setTimeout(function () { if (ui.confirm === id) { ui.confirm = null; render(); } }, 3000); }
        });
    }

    /* ---------------- Panel izquierdo: catalogo ---------------- */
    function renderLeft() {
        var p = el("div", "panel left");
        p.appendChild(el("h2", "", "Catálogo"));
        p.appendChild(el("div", "sub", S ? (S.name || "") : ""));

        var sWrap = el("div", "search");
        var inp = el("input"); inp.type = "text"; inp.placeholder = "Buscar mueble…"; inp.value = ui.search;
        inp.addEventListener("input", function () { ui.search = inp.value; renderGrid(); });
        sWrap.appendChild(inp);
        p.appendChild(sWrap);

        var cats = el("div", "cats");
        D.cats.forEach(function (c) {
            var b = btn(c.icon + " " + c.name, ui.cat === c.id && !ui.search ? "on" : "", function () { ui.cat = c.id; ui.search = ""; render(); });
            cats.appendChild(b);
        });
        p.appendChild(cats);

        var grid = el("div", "grid");
        grid.id = "grid";
        p.appendChild(grid);
        app.innerHTML = "";
        app.appendChild(p);
        renderGrid();
    }

    var thumbs = {};          // key -> data URI (miniaturas 3D generadas por Lua)
    var lastThumbReq = "";

    function renderGrid() {
        var grid = document.getElementById("grid");
        if (!grid) return;
        grid.innerHTML = "";
        var q = ui.search.trim().toLowerCase();
        var stock = S ? obj(S.stock) : {};
        var icons = {};
        D.cats.forEach(function (c) { icons[c.id] = c.icon; });
        var shown = 0, keys = [];
        D.items.forEach(function (it) {
            if (q ? it.name.toLowerCase().indexOf(q) < 0 : it.cat !== ui.cat) return;
            if (shown++ > 300) return;
            keys.push(it.key);
            var c = el("div", "card" + (S && S.ghost === it.key ? " sel" : ""));
            var pic = el("div", "pic");
            pic.setAttribute("data-key", it.key);
            if (thumbs[it.key]) {
                var im = el("img"); im.src = thumbs[it.key]; pic.appendChild(im);
            } else {
                pic.appendChild(el("div", "ico", icons[it.cat] || "📦"));
            }
            c.appendChild(pic);
            c.appendChild(el("div", "nm", it.name));
            c.appendChild(el("div", "pr", money(it.price)));
            if (stock[it.key]) c.appendChild(el("div", "bd", "En bodega: " + stock[it.key]));
            press(c, function () { cmd("pick", it.key); });
            grid.appendChild(c);
        });
        if (!shown) grid.appendChild(el("div", "empty", "Sin resultados."));
        // pide a Lua las miniaturas que faltan (solo si cambio la lista visible)
        var missing = keys.filter(function (k) { return !thumbs[k]; }).join(",");
        if (missing !== lastThumbReq) { lastThumbReq = missing; if (missing) cmd("thumbs", missing); }
    }

    /* ---------------- Panel derecho ---------------- */
    function field(label, name, value, step) {
        var d = el("div");
        d.appendChild(el("label", "", label));
        var i = el("input"); i.type = "number"; i.step = step || "0.05"; i.value = value;
        i.addEventListener("change", function () { cmd("field", name, i.value); });
        i.addEventListener("keydown", function (e) { if (e.key === "Enter") i.blur(); e.stopPropagation(); });
        d.appendChild(i);
        return d;
    }

    function swatches(current, onPick) {
        var sw = el("div", "sw");
        var none = el("div", "c none" + (current === -1 || current === undefined || current === null ? " cur" : ""));
        none.title = "Sin tinte";
        press(none, function () { onPick(-1); });
        sw.appendChild(none);
        D.swatches.forEach(function (c) {
            var d = el("div", "c" + (current === c ? " cur" : ""));
            d.style.background = hex(c);
            press(d, function () { onPick(c); });
            sw.appendChild(d);
        });
        return sw;
    }

    function materialsRow(current, onPick) {
        var b = el("div", "btns");
        D.mats.forEach(function (m) {
            b.appendChild(btn(m.name, (current || "liso") === m.id ? "on" : "", function () { onPick(m.id === "liso" ? "" : m.id); }));
        });
        return b;
    }

    function renderObject(body) {
        var f = S.first;
        if (S.selCount === 0 && !S.ghost) {
            body.appendChild(el("div", "empty", "Elige un mueble del catálogo o haz clic en uno de la casa para editarlo."));
            var s = el("div", "sec");
            s.appendChild(el("h3", "", "Atajos"));
            s.appendChild(el("div", "muted", "Clic: seleccionar / colocar · arrastra una flecha (rojo X, verde Y, azul Z) para mover solo en ese eje · 4/5/6: mover, girar, escalar · mantén X, Y o Z mientras arrastras para bloquear el eje · mantén Mayús para mover sin rejilla · Q/E: girar · Supr: a la bodega · Ctrl+Z / Ctrl+Y · Ctrl+D duplicar · Tab: rejilla"));
            body.appendChild(s);
            body.appendChild(btn("Seleccionar todo", "", function () { cmd("selectall"); }));
            return;
        }
        if (S.selCount === 0 && S.ghost) {
            var g = el("div", "sec");
            g.appendChild(el("h3", "", "Colocando"));
            g.appendChild(el("div", "", "Clic para colocar. Esc o clic derecho para soltar."));
            g.appendChild(el("h3", "", "Color del próximo mueble"));
            g.appendChild(swatches(S.ghostColor === undefined || S.ghostColor === null ? -1 : S.ghostColor, function (c) { cmd("paint", c, null); }));
            g.appendChild(el("h3", "", "Material"));
            g.appendChild(materialsRow(S.ghostMat, function (m) { cmd("paint", null, m); }));
            body.appendChild(g);
            return;
        }

        var h = el("div", "sec");
        h.appendChild(el("h3", "", S.selCount > 1 ? S.selCount + " muebles seleccionados" : f.name));
        if (S.selCount === 1) {
            var r1 = el("div", "row f3"); r1.appendChild(field("X", "x", f.x)); r1.appendChild(field("Y", "y", f.y)); r1.appendChild(field("Z", "z", f.z));
            var r2 = el("div", "row f3"); r2.appendChild(field("RX", "rx", f.rx, "1")); r2.appendChild(field("RY", "ry", f.ry, "1")); r2.appendChild(field("RZ", "rz", f.rz, "1"));
            var r3 = el("div", "row f3"); r3.appendChild(field("EX", "sx", f.sx)); r3.appendChild(field("EY", "sy", f.sy)); r3.appendChild(field("EZ", "sz", f.sz));
            h.appendChild(r1); h.appendChild(r2); h.appendChild(r3);
        }
        body.appendChild(h);

        var st = el("div", "sec");
        st.appendChild(el("h3", "", "Color"));
        st.appendChild(swatches(S.selCount === 1 ? f.color : null, function (c) { cmd("paint", c, null); }));
        st.appendChild(el("h3", "", "Material"));
        st.appendChild(materialsRow(S.selCount === 1 ? f.mat : "", function (m) { cmd("paint", null, m); }));
        body.appendChild(st);

        var ac = el("div", "sec");
        ac.appendChild(el("h3", "", "Acciones"));
        var b = el("div", "btns");
        b.appendChild(btn("Duplicar", "", function () { cmd("duplicate"); }));
        b.appendChild(btn("Girar 90°", "", function () { cmd("rotate", 90); }));
        b.appendChild(btn("A la bodega", "", function () { cmd("delete"); }));
        b.appendChild(confirmBtn("sell", S.selCount === 1 ? "Vender (" + money(f.sell) + ")" : "Vender", function () { cmd("sell"); }, "danger"));
        ac.appendChild(b);
        body.appendChild(ac);
    }

    function barClass(pct) { return pct >= 100 ? "bar full" : (pct >= 80 ? "bar warn" : "bar"); }

    function renderHouse(body) {
        var s1 = el("div", "sec");
        s1.appendChild(el("h3", "", "Capacidad"));
        var pct = Math.min(100, Math.round((S.weight || 0) / Math.max(1, S.limit) * 100));
        var bar = el("div", barClass(pct)); var fill = el("i"); fill.style.width = pct + "%"; bar.appendChild(fill);
        s1.appendChild(bar);
        s1.appendChild(el("div", "muted", (Math.round(S.weight * 10) / 10) + " / " + S.limit + " de capacidad · " + S.count + " muebles"));
        body.appendChild(s1);

        var hid = el("div", "sec");
        hid.appendChild(el("h3", "", "Objetos originales ocultos"));
        if (S.isOwner) {
            var sb0 = btn("🧹 Vaciar interior", "primary", function () { cmd("scan"); });
            sb0.style.width = "100%";
            hid.appendChild(sb0);
            hid.appendChild(el("div", "muted", "Oculta todos los muebles y objetos decorativos que trae la casa para que la diseñes desde cero. Las paredes, los suelos y las puertas no se tocan. Se puede deshacer con Ctrl+Z, con «Restaurar», o con el comando /restaurarcasa si algo sale mal. Para quitar un objeto suelto usa «Ocultar» en la barra."));
        }
        var rem = arr(S.removed);
        if (!rem.length) hid.appendChild(el("div", "muted", "Ninguno todavía."));
        var list = el("div", "list");
        rem.forEach(function (r, i) {
            var it = el("div", "it");
            it.appendChild(el("span", "", r.m === -1 ? "Todos los muebles originales" : r.r ? "Modelo " + r.m + " · todos los de la casa" : "Modelo " + r.m + " (" + r.x.toFixed(1) + ", " + r.y.toFixed(1) + ")"));
            if (S.isOwner) it.appendChild(btn("Restaurar", "", function () { cmd("unhide", i + 1); }));
            list.appendChild(it);
        });
        hid.appendChild(list);
        if (S.isOwner && rem.length) hid.appendChild(btn("Restaurar todo", "", function () { cmd("unhide", 0); }));
        body.appendChild(hid);

        var bp = el("div", "sec");
        bp.appendChild(el("h3", "", "Planos"));
        if (S.isOwner) {
            var row = el("div", "row");
            var ni = el("input"); ni.type = "text"; ni.maxLength = 40; ni.placeholder = "Nombre del plano"; ni.value = ui.bpName;
            ni.addEventListener("input", function () { ui.bpName = ni.value; });
            ni.addEventListener("keydown", function (e) { e.stopPropagation(); });
            row.appendChild(ni);
            var sb = btn("Guardar", "primary", function () { if (ui.bpName.trim().length >= 2) { cmd("bpSave", ui.bpName.trim()); ui.bpName = ""; } });
            sb.style.flex = "0 0 auto";
            row.appendChild(sb);
            bp.appendChild(row);
        }
        var bl = el("div", "list");
        arr(S.blueprints).forEach(function (b) {
            var it = el("div", "it");
            it.appendChild(el("span", "", b.name));
            if (S.isOwner) {
                it.appendChild(btn("Aplicar", "", function () { cmd("bpApply", b.id, false); }));
                it.appendChild(btn("Reemplazar", "", function () { cmd("bpApply", b.id, true); }));
            }
            it.appendChild(btn("✕", "danger", function () { cmd("bpDelete", b.id); }));
            bl.appendChild(it);
        });
        if (!arr(S.blueprints).length) bl.appendChild(el("div", "muted", "Aún no tienes planos guardados."));
        bp.appendChild(bl);
        bp.appendChild(el("div", "muted", "Un plano guarda la disposición, colores y materiales; sirve en casas con el mismo interior. «Reemplazar» manda lo actual a la bodega."));
        body.appendChild(bp);

        if (S.isOwner) {
            var mem = el("div", "sec");
            mem.appendChild(el("h3", "", "Residentes (pueden decorar)"));
            var mr = el("div", "row");
            var mi = el("input"); mi.type = "number"; mi.placeholder = "ID del jugador"; mi.value = ui.member;
            mi.addEventListener("input", function () { ui.member = mi.value; });
            mi.addEventListener("keydown", function (e) { e.stopPropagation(); });
            mr.appendChild(mi);
            var ab = btn("Añadir", "", function () { if (ui.member) { cmd("memberAdd", ui.member); ui.member = ""; } });
            ab.style.flex = "0 0 auto";
            mr.appendChild(ab);
            mem.appendChild(mr);
            var ml = el("div", "list");
            arr(S.members).forEach(function (m) {
                var it = el("div", "it");
                it.appendChild(el("span", "", m.name));
                it.appendChild(btn("Quitar", "danger", function () { cmd("memberRemove", m.id); }));
                ml.appendChild(it);
            });
            if (!arr(S.members).length) ml.appendChild(el("div", "muted", "Sin residentes."));
            mem.appendChild(ml);
            body.appendChild(mem);

            var dz = el("div", "sec");
            dz.appendChild(el("h3", "", "Zona peligrosa"));
            dz.appendChild(confirmBtn("clear", "Vaciar la casa (todo a la bodega)", function () { cmd("clearall"); }, "danger"));
            body.appendChild(dz);
        }

        var stock = obj(S.stock), keys = Object.keys(stock);
        var bo = el("div", "sec");
        bo.appendChild(el("h3", "", "Bodega (" + keys.reduce(function (a, k) { return a + stock[k]; }, 0) + ")"));
        var byKey = {};
        D.items.forEach(function (i) { byKey[i.key] = i; });
        var sl = el("div", "list");
        keys.forEach(function (k) {
            var it = el("div", "it");
            it.appendChild(el("span", "", stock[k] + "× " + (byKey[k] ? byKey[k].name : k)));
            if (byKey[k]) it.appendChild(btn("Colocar", "", function () { cmd("pick", k); }));
            sl.appendChild(it);
        });
        if (!keys.length) sl.appendChild(el("div", "muted", "Vacía. Lo que guardes con «A la bodega» aparece aquí."));
        bo.appendChild(sl);
        body.appendChild(bo);
    }

    function renderRight() {
        var p = el("div", "panel right");
        if (S) { var mny = el("div", "sub", "Cuenta bancaria: " + money(S.money) + "  ·  " + (S.name || "")); mny.style.paddingTop = "12px"; p.appendChild(mny); }
        var tabs = el("div", "tabs");
        tabs.appendChild(btn("Objeto", ui.tab === "obj" ? "on" : "", function () { ui.tab = "obj"; render(); }));
        tabs.appendChild(btn("Casa", ui.tab === "house" ? "on" : "", function () { ui.tab = "house"; render(); }));
        p.appendChild(tabs);
        var body = el("div", "body");
        if (!S) body.appendChild(el("div", "empty", "Cargando…"));
        else if (ui.tab === "obj") renderObject(body); else renderHouse(body);
        p.appendChild(body);
        var keep = app.querySelector(".body");
        var scroll = keep ? keep.scrollTop : 0;
        app.innerHTML = "";
        app.appendChild(p);
        body.scrollTop = scroll;
    }

    /* ---------------- Barra superior ---------------- */
    function renderTop() {
        var p = el("div", "panel top");
        if (!S) { app.innerHTML = ""; app.appendChild(p); return; }
        p.appendChild(btn("🖱 Elegir", S.tool !== "hide" ? "on" : "", function () { cmd("tool", "select"); }));
        p.appendChild(btn("🚫 Ocultar", S.tool === "hide" ? "on" : "", function () { cmd("tool", "hide"); }));
        p.appendChild(el("div", "sep"));

        var g = el("select");
        D.grids.forEach(function (v) {
            var o = el("option", "", v === 0 ? "Libre" : v + " m"); o.value = v; if (v === S.grid) o.selected = true; g.appendChild(o);
        });
        g.title = "Rejilla. Mantén Mayús para mover sin rejilla"; g.addEventListener("change", function () { cmd("grid", g.value); g.blur(); });
        p.appendChild(g);
        var r = el("select");
        D.rots.forEach(function (v) {
            var o = el("option", "", v + "°"); o.value = v; if (v === S.rotStep) o.selected = true; r.appendChild(o);
        });
        r.addEventListener("change", function () { cmd("rotstep", r.value); r.blur(); });
        p.appendChild(r);
        p.appendChild(el("div", "sep"));

        [["Mover", "move", "4"], ["Girar", "rotate", "5"], ["Escalar", "scale", "6"]].forEach(function (v) {
            var b = btn(v[0], S.gizmo === v[1] ? "on" : "", function () { cmd("gizmo", v[1]); });
            b.title = "Tecla " + v[2];
            p.appendChild(b);
        });
        p.appendChild(el("div", "sep"));
        var u = btn("↶", "", function () { cmd("undo"); }); u.title = "Deshacer (Ctrl+Z)"; u.disabled = !S.canUndo; p.appendChild(u);
        var rd = btn("↷", "", function () { cmd("redo"); }); rd.title = "Rehacer (Ctrl+Y)"; rd.disabled = !S.canRedo; p.appendChild(rd);
        p.appendChild(btn("Cancelar", "danger", function () { cmd("cancel"); }));
        p.appendChild(btn("✔ Terminar", "primary", function () { cmd("finish"); }));
        app.innerHTML = "";
        app.appendChild(p);
    }

    /* ---------------- Ventana modal ---------------- */
    function closeModal() { send("rp:furn:ui:modalClose"); }

    function itemList(items, label, onOne, onAll) {
        var col = el("div");
        col.appendChild(el("h3", "muted", label));
        var list = el("div", "list");
        items.forEach(function (it) {
            var r = el("div", "it");
            r.appendChild(el("span", "", (it.icon || "") + " " + it.name + " ×" + it.amount));
            r.appendChild(btn("1", "", function () { onOne(it, 1); }));
            r.appendChild(btn("Todo", "", function () { onAll(it, it.amount); }));
            list.appendChild(r);
        });
        if (!items.length) list.appendChild(el("div", "empty", "Vacío"));
        col.appendChild(list);
        return col;
    }

    function modal(kind, data) {
        document.body.className = "modal";
        app.innerHTML = "";
        var w = el("div", "win");
        if (kind === "storage") {
            w.appendChild(el("h1", "", data.title || "Contenedor"));
            var pct = Math.min(100, Math.round((data.weight || 0) / data.cap * 100));
            var bar = el("div", barClass(pct)); var fill = el("i"); fill.style.width = pct + "%"; bar.appendChild(fill);
            w.appendChild(bar);
            w.appendChild(el("div", "muted", (Math.round(data.weight * 10) / 10) + " / " + data.cap + " kg"));
            var cols = el("div", "cols");
            cols.appendChild(itemList(arr(data.items), "Dentro", function (it, n) { send("rp:furn:ui:stTake", data.fid, it.id, n); }, function (it, n) { send("rp:furn:ui:stTake", data.fid, it.id, n); }));
            cols.appendChild(itemList(arr(data.mine), "En tu inventario", function (it, n) { send("rp:furn:ui:stPut", data.fid, it.id, n); }, function (it, n) { send("rp:furn:ui:stPut", data.fid, it.id, n); }));
            w.appendChild(cols);
        } else if (kind === "stations") {
            w.appendChild(el("h1", "", data.title || "Emisora"));
            var stl = el("div", "stl");
            arr(data.stations).forEach(function (s) {
                stl.appendChild(btn("📻 " + s.name, s.id === data.current ? "on" : "", function () { send("rp:furn:ui:station", data.fid, s.id); }));
            });
            w.appendChild(stl);
        }
        w.appendChild(btn("Cerrar", "", closeModal));
        app.appendChild(w);
    }

    document.addEventListener("keydown", function (e) {
        if (PANEL === "modal" && e.key === "Escape") closeModal();
    });

    /* ---------------- Ciclo ---------------- */
    var zoomK = 1;
    function applyZoom() {
        app.style.zoom = zoomK;
        app.style.width = (window.innerWidth / zoomK) + "px";
        app.style.height = (window.innerHeight / zoomK) + "px";
    }
    window.addEventListener("resize", applyZoom);

    function render() {
        if (PANEL === "left") renderLeft();
        else if (PANEL === "right") renderRight();
        else if (PANEL === "top") renderTop();
    }

    window.FURN = {
        init: function (data) {
            D = { items: arr(data.items), cats: arr(data.cats), swatches: arr(data.swatches), mats: arr(data.mats), grids: arr(data.grids), rots: arr(data.rots) };
            if (D.cats.length && !D.cats.some(function (c) { return c.id === ui.cat; })) ui.cat = D.cats[0].id;
            render();
        },
        state: function (s) {
            var prevGhost = S && S.ghost;
            S = s;
            // no se reconstruye el panel mientras se escribe en un campo
            var a = document.activeElement;
            if (a && /^(INPUT|SELECT)$/.test(a.tagName) && a.type !== "button") {
                if (PANEL === "left" && prevGhost !== s.ghost) renderGrid();
                return;
            }
            if (PANEL === "left") renderGrid(); else render();
        },
        modal: modal,
        // Escala de la interfaz segun la resolucion (la calcula Lua). #app se dibuja a tamano de
        // diseno y el zoom lo lleva al tamano real del panel, sin recortes ni barras de desplazamiento.
        zoom: function (k) {
            zoomK = (k > 0.3 && k < 4) ? k : 1;
            applyZoom();
        },
        thumb: function (key, data) {
            thumbs[key] = data;
            var pic = document.querySelector(".pic[data-key=\"" + key + "\"]");
            if (pic) { pic.innerHTML = ""; var im = el("img"); im.src = data; pic.appendChild(im); }
        },
    };

    if (PANEL !== "modal") send("rp:furn:ui:ready", PANEL);
})();
