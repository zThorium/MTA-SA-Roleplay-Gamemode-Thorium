/*
 * rp_scoreboard / app.js
 * Lua llama a:
 *   RP.setCatalog(cat)            efectos, iconos y banderas permitidos (shared/s_config.lua)
 *   RP.open(data) / RP.update(data) / RP.close() / RP.scroll(dir)
 *   RP.setAvatar(key, version, dataUri|null)
 *   RP.openEditor(myRow) / RP.closeEditor()
 * Envía: rp:scoreboard:ui:hidden, :save(json), :avatar(url), :clearAvatar, :closeEditor
 * Sin window.mta abre una demo: index.html (Tab) o index.html#editor.
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    function el(tag, className, text) {
        var n = document.createElement(tag);
        if (className) n.className = className;
        if (text !== undefined) n.textContent = text;   // datos de jugadores siempre como texto
        return n;
    }

    var SOUNDS = {
        open: ["maximize_003"], close: ["minimize_003"], click: ["click_002"],
        select: ["select_002"], save: ["confirmation_001"], error: ["error_004"]
    };
    function play(evt, vol) {
        var list = SOUNDS[evt];
        if (!list) return;
        try {
            var a = new Audio("sounds/" + list[Math.floor(Math.random() * list.length)] + ".ogg");
            a.volume = vol || 0.35;
            a.play();
        } catch (e) { /* sin audio */ }
    }

    var catalog = { effects: [], icons: [], flags: [], defaultColor: "#f2f4f8" };
    var iconByKey = {}, flagByKey = {};
    var avatars = {};          // key -> { v, uri }
    var rows = {};             // key -> { el, whoSig, facSig, lvl }
    var order = "";
    var board = $("board"), list = $("list");
    var ROW_STEP = 50;

    /* ------------------------------------------------ colores */
    function hexToRgb(h) {
        var n = parseInt(h.slice(1), 16);
        return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
    }
    function mix(a, b, t) {
        var x = hexToRgb(a), y = hexToRgb(b);
        return "rgb(" + Math.round(x[0] + (y[0] - x[0]) * t) + "," + Math.round(x[1] + (y[1] - x[1]) * t) + "," + Math.round(x[2] + (y[2] - x[2]) * t) + ")";
    }
    function validHex(h) { return typeof h === "string" && /^#[0-9a-fA-F]{6}$/.test(h); }
    function initials(name) {
        var p = String(name).trim().split(/\s+/);
        return ((p[0] || "?")[0] + (p[1] ? p[1][0] : "")).toUpperCase();
    }

    /* ------------------------------------------------ nombre con efecto */
    var SPLIT = { wave: 0.07, bounce: 0.09, type: 0.12 };

    function buildName(text, pr) {
        pr = pr || {};
        var c = validHex(pr.c) ? pr.c : catalog.defaultColor;
        var c2 = validHex(pr.c2) ? pr.c2 : null;
        var fx = pr.e || "none";
        var n = el("span", "name fx-" + fx);
        n.style.setProperty("--fx", c);

        if (SPLIT[fx] !== undefined) {
            var chars = Array.from(text);
            chars.forEach(function (ch, i) {
                var s = el("span", "ch", ch);
                s.style.color = c2 ? mix(c, c2, chars.length > 1 ? i / (chars.length - 1) : 0) : c;
                s.style.animationDelay = i * SPLIT[fx] + "s";
                n.appendChild(s);
            });
            return n;
        }

        n.textContent = text;
        if (fx === "rainbow") return n;
        if (fx === "shine") {
            n.classList.add("grad-text");
            n.style.backgroundImage = "linear-gradient(110deg, " + c + " 35%, #ffffff 50%, " + (c2 || c) + " 65%)";
        } else if (c2) {
            n.classList.add("grad-text");
            n.style.backgroundImage = "linear-gradient(90deg, " + c + ", " + c2 + ")";
        } else {
            n.style.color = c;
        }
        if (fx === "glitch") {
            n.appendChild(el("span", "glitch-layer g1", text));
            n.appendChild(el("span", "glitch-layer g2", text));
        }
        return n;
    }

    function buildIcon(key) {
        var ic = iconByKey[key];
        if (!ic) return null;
        var s = el("span", "ico ico-" + ic.anim, ic.emoji);
        s.title = ic.name;
        return s;
    }

    function buildFlag(code) {
        if (!flagByKey[code]) return null;
        var img = el("img", "flag");
        img.src = "flags/" + code + ".svg";
        img.alt = flagByKey[code].name;
        return img;
    }

    function buildAvatar(p) {
        var pr = p.pr || {};
        var av = el("div", "avatar");
        var a = avatars[p.k];
        if (pr.a > 0 && a && a.v === pr.a && a.uri) {
            var img = el("img");
            img.src = a.uri;
            av.appendChild(img);
            av.classList.add("has-img");
        } else {
            av.textContent = initials(p.name);
            av.style.background = validHex(pr.c) && pr.c !== catalog.defaultColor
                ? "linear-gradient(135deg, " + pr.c + ", " + (validHex(pr.c2) ? pr.c2 : pr.c) + ")"
                : "#8a93a3";
        }
        return av;
    }

    function buildWho(p) {
        var who = el("div", "who");
        who.appendChild(buildAvatar(p));
        var pr = p.pr || {};
        var flag = buildFlag(pr.f);
        if (flag) who.appendChild(flag);
        who.appendChild(buildName(p.name, pr));
        var ico = buildIcon(pr.i);
        if (ico) who.appendChild(ico);
        if (p.off) who.appendChild(el("span", "sub-tag", "conectando…"));
        else if (p.me) who.appendChild(el("span", "sub-tag", "tú"));
        return who;
    }

    function buildFac(fac) {
        if (!fac) return el("span", "fac-none", "—");
        var f = el("span", "fac");
        f.style.color = validHex(fac.color) ? fac.color : "#9aa3b2";
        f.appendChild(el("b", null, fac.tag || "?"));
        f.appendChild(el("span", null, fac.name || ""));
        return f;
    }

    function lvlTier(l) { return l >= 30 ? "t4" : l >= 20 ? "t3" : l >= 10 ? "t2" : l >= 5 ? "t1" : ""; }

    function buildPing() {
        var cell = el("div", "c-pingcell");
        var bars = el("div", "ping");
        for (var i = 0; i < 4; i++) bars.appendChild(el("i"));
        cell.appendChild(bars);
        cell.appendChild(el("span", "ping-ms", ""));
        return cell;
    }
    function setPing(cell, ms) {
        var bars = cell.firstChild;
        var on = ms < 80 ? 4 : ms < 150 ? 3 : ms < 250 ? 2 : 1;
        bars.className = "ping " + (on >= 3 ? "good" : on === 2 ? "mid" : "bad");
        for (var i = 0; i < 4; i++) bars.children[i].className = i < on ? "on" : "";
        cell.lastChild.textContent = ms + " ms";
    }

    /* ------------------------------------------------ filas */
    function makeRow(p) {
        var r = el("div", "row");
        r.appendChild(el("span", "r-id", String(p.id || "-")));
        r.appendChild(el("div"));                 // quien
        r.appendChild(el("div"));                 // faccion
        r.appendChild(el("div", "lvl"));          // nivel
        r.appendChild(buildPing());
        return { el: r, whoSig: null, facSig: null, lvl: null };
    }

    function updateRow(entry, p) {
        var r = entry.el;
        r.classList.toggle("me", !!p.me);
        r.classList.toggle("off", !!p.off);
        r.children[0].textContent = String(p.id || "-");

        var a = avatars[p.k];
        var whoSig = JSON.stringify([p.name, p.pr, p.off, p.me, a ? a.v : 0]);
        if (whoSig !== entry.whoSig) {
            entry.whoSig = whoSig;
            r.replaceChild(buildWho(p), r.children[1]);
        }
        var facSig = JSON.stringify(p.fac || null);
        if (facSig !== entry.facSig) {
            entry.facSig = facSig;
            r.replaceChild(buildFac(p.fac), r.children[2]);
        }
        var lvl = r.children[3];
        if (entry.lvl !== p.lvl) {
            lvl.textContent = p.lvl > 0 ? String(p.lvl) : "–";
            lvl.className = "lvl " + lvlTier(p.lvl);
            if (entry.lvl !== null && p.lvl > entry.lvl) {
                void lvl.offsetWidth;
                lvl.classList.add("pop");
            }
            entry.lvl = p.lvl;
        }
        setPing(r.children[4], p.ping || 0);
    }

    function render(data, animateAll) {
        $("server-name").textContent = data.server || "Thorium Roleplay";
        $("count").textContent = data.players.length;
        $("max").textContent = data.max || "?";
        var inFac = 0;
        var seen = {}, keys = [];
        data.players.forEach(function (p, i) {
            if (p.fac) inFac++;
            seen[p.k] = true;
            keys.push(p.k);
            var entry = rows[p.k];
            var isNew = !entry;
            if (isNew) entry = rows[p.k] = makeRow(p);
            updateRow(entry, p);
            if (isNew || animateAll) {
                entry.el.classList.remove("enter");
                void entry.el.offsetWidth;
                entry.el.style.animationDelay = animateAll ? (0.2 + Math.min(i, 14) * 0.035) + "s" : "0s";
                entry.el.classList.add("enter");
            }
        });
        $("in-factions").textContent = inFac;
        Object.keys(rows).forEach(function (k) {
            if (!seen[k]) { rows[k].el.remove(); delete rows[k]; }
        });
        var sig = keys.join(",");
        if (sig !== order) {
            order = sig;
            keys.forEach(function (k) { list.appendChild(rows[k].el); });
        }
        $("scroll-hint").hidden = list.scrollHeight <= list.clientHeight + 2;
    }

    function tickClock() {
        var d = new Date();
        $("clock").textContent = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2);
    }

    board.addEventListener("animationend", function (e) {
        if (e.target !== board) return;
        if (e.animationName === "boardClose") {
            board.hidden = true;
            board.classList.remove("closing");
            send("rp:scoreboard:ui:hidden");
        } else if (e.animationName === "boardOpen") {
            board.classList.remove("opening");
        }
    });

    /* ------------------------------------------------ editor */
    var PRESETS = ["#f2f4f8", "#f5a524", "#ff6a3d", "#ff4d6d", "#ff7eb6", "#c77dff", "#7b61ff", "#4dabf7",
        "#22d3ee", "#2dd4bf", "#4cd38a", "#a3e635", "#facc15", "#fb923c", "#e2b07a", "#94a3b8"];
    var ed = null, me = null;

    function edProfile() { return { c: ed.c, c2: ed.grad ? ed.c2 : false, e: ed.e, i: ed.i, f: ed.f, a: me.pr ? me.pr.a : 0 }; }

    function renderPreview() {
        var row = $("ed-row");
        row.textContent = "";
        var p = JSON.parse(JSON.stringify(me));
        p.pr = edProfile();
        var entry = makeRow(p);
        updateRow(entry, p);
        entry.el.classList.add("enter");
        row.appendChild(entry.el);
    }

    function swatches(box, current, onPick) {
        box.textContent = "";
        PRESETS.forEach(function (c) {
            var s = el("div", "sw" + (c === current ? " sel" : ""));
            s.style.background = c;
            s.addEventListener("click", function () { play("click", 0.3); onPick(c); });
            box.appendChild(s);
        });
    }

    function optGrid(box, items, current, build, onPick) {
        box.textContent = "";
        items.forEach(function (it) {
            var b = el("button", "opt" + (it.key === current ? " sel" : ""));
            if (it.name) b.setAttribute("data-tip", it.name);
            b.appendChild(build(it));
            b.addEventListener("click", function () { play("select", 0.3); onPick(it.key); });
            box.appendChild(b);
        });
    }

    function renderEditor() {
        swatches($("ed-colors"), ed.c, function (c) { ed.c = c; $("ed-hex").value = c; renderEditor(); });
        $("ed-hex").classList.remove("bad");
        $("ed-grad").checked = ed.grad;
        $("ed-grad-row").hidden = !ed.grad;
        swatches($("ed-colors2"), ed.c2, function (c) { ed.c2 = c; renderEditor(); });

        optGrid($("ed-effects"), catalog.effects, ed.e, function (fx) {
            var w = el("div");
            w.appendChild(buildName("Abc", { c: ed.c, c2: ed.grad ? ed.c2 : null, e: fx.key }));
            w.appendChild(el("div", "opt-name", fx.name));
            return w;
        }, function (k) { ed.e = k; renderEditor(); });
        $("ed-effects").querySelectorAll("[data-tip]").forEach(function (b) { b.removeAttribute("data-tip"); });

        optGrid($("ed-icons"), [{ key: "", name: "Ninguno" }].concat(catalog.icons), ed.i, function (ic) {
            return ic.key ? buildIcon(ic.key) : el("span", "opt-none", "∅");
        }, function (k) { ed.i = k; renderEditor(); });

        optGrid($("ed-flags"), [{ key: "", name: "Ninguna" }].concat(catalog.flags), ed.f, function (fl) {
            return fl.key ? buildFlag(fl.key) : el("span", "opt-none", "∅");
        }, function (k) { ed.f = k; renderEditor(); });

        renderPreview();
    }

    $("ed-hex").addEventListener("input", function () {
        var v = this.value.trim();
        if (v && v[0] !== "#") v = "#" + v;
        var ok = validHex(v);
        this.classList.toggle("bad", !ok);
        if (ok) { ed.c = v.toLowerCase(); swatches($("ed-colors"), ed.c, function (c) { ed.c = c; $("ed-hex").value = c; renderEditor(); }); renderPreview(); }
    });
    $("ed-grad").addEventListener("change", function () {
        ed.grad = this.checked;
        if (ed.grad && !validHex(ed.c2)) ed.c2 = "#ff6a3d";
        play("click", 0.3);
        renderEditor();
    });
    $("ed-save").addEventListener("click", function () {
        var p = edProfile();
        send("rp:scoreboard:ui:save", JSON.stringify({ c: p.c, c2: p.c2, e: p.e, i: p.i, f: p.f }));
        me.pr = p;
        play("save", 0.4);
        var b = this;
        b.classList.remove("saved"); void b.offsetWidth; b.classList.add("saved");
    });
    $("ed-reset").addEventListener("click", function () {
        ed = { c: catalog.defaultColor, c2: "#ff6a3d", grad: false, e: "none", i: "", f: "" };
        $("ed-hex").value = ed.c;
        play("click", 0.3);
        renderEditor();
    });
    $("ed-upload").addEventListener("click", function () {
        var url = $("ed-url").value.trim();
        if (!/^https:\/\/[^\s]+$/.test(url)) { $("ed-url").classList.add("bad"); play("error", 0.35); return; }
        $("ed-url").classList.remove("bad");
        send("rp:scoreboard:ui:avatar", url);
        var b = this;
        b.classList.add("busy");
        setTimeout(function () { b.classList.remove("busy"); }, 3000);
        play("click", 0.3);
    });
    $("ed-noavatar").addEventListener("click", function () {
        send("rp:scoreboard:ui:clearAvatar");
        if (me.pr) me.pr.a = 0;
        play("click", 0.3);
        renderPreview();
    });
    $("ed-close").addEventListener("click", function () { send("rp:scoreboard:ui:closeEditor"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" && !$("editor").hidden) send("rp:scoreboard:ui:closeEditor");
    });

    /* ------------------------------------------------ API para Lua */
    window.RP = {
        setCatalog: function (cat) {
            catalog = cat;
            iconByKey = {}; flagByKey = {};
            (cat.icons || []).forEach(function (i) { iconByKey[i.key] = i; });
            (cat.flags || []).forEach(function (f) { flagByKey[f.key] = f; });
        },
        open: function (data) {
            tickClock();
            board.hidden = false;
            board.classList.remove("closing", "opening");
            void board.offsetWidth;
            board.classList.add("opening");
            list.scrollTop = 0;
            render(data, true);
            play("open", 0.18);
        },
        update: function (data) {
            if (board.hidden) return;
            tickClock();
            render(data, false);
        },
        close: function () {
            if (board.hidden) return send("rp:scoreboard:ui:hidden");
            board.classList.remove("opening");
            void board.offsetWidth;
            board.classList.add("closing");
            play("close", 0.14);
        },
        scroll: function (dir) {
            list.scrollTop += dir * ROW_STEP * 3;
        },
        setAvatar: function (key, version, uri) {
            if (uri) avatars[key] = { v: version, uri: uri };
            else delete avatars[key];
            if (me && me.k === key) {
                if (me.pr) me.pr.a = uri ? version : 0;
                if (uri) { play("save", 0.35); $("ed-url").value = ""; }
                renderPreview();
            }
            var entry = rows[key];
            if (entry) entry.whoSig = null;      // se rehace en el proximo update
        },
        openEditor: function (myRow) {
            board.hidden = true;
            board.classList.remove("opening", "closing");
            me = myRow;
            var pr = me.pr || {};
            ed = {
                c: validHex(pr.c) ? pr.c : catalog.defaultColor,
                c2: validHex(pr.c2) ? pr.c2 : "#ff6a3d",
                grad: validHex(pr.c2),
                e: pr.e || "none", i: pr.i || "", f: pr.f || ""
            };
            $("ed-hex").value = ed.c;
            $("ed-url").value = "";
            $("editor").hidden = false;
            play("open", 0.3);
            renderEditor();
        },
        closeEditor: function () {
            $("editor").hidden = true;
            play("close", 0.25);
        }
    };

    /* ------------------------------------------------ demo sin MTA */
    if (!window.mta) {
        document.body.style.background = "linear-gradient(135deg, #2b3a4a, #57412b)";
        RP.setCatalog({
            defaultColor: "#f2f4f8",
            effects: [{ key: "none", name: "Sin efecto" }, { key: "shine", name: "Destello" }, { key: "rainbow", name: "Arcoíris" },
                { key: "wave", name: "Ola" }, { key: "glow", name: "Neón" }, { key: "glitch", name: "Glitch" },
                { key: "flicker", name: "Letrero roto" }, { key: "bounce", name: "Saltitos" }, { key: "type", name: "Máquina de escribir" }],
            icons: [{ key: "fire", emoji: "🔥", anim: "flame", name: "Fuego" }, { key: "star", emoji: "⭐", anim: "spin", name: "Estrella" },
                { key: "crown", emoji: "👑", anim: "float", name: "Corona" }, { key: "gem", emoji: "💎", anim: "shine", name: "Diamante" },
                { key: "heart", emoji: "❤️", anim: "beat", name: "Corazón" }, { key: "bolt", emoji: "⚡", anim: "flash", name: "Rayo" },
                { key: "skull", emoji: "💀", anim: "shake", name: "Calavera" }, { key: "car", emoji: "🚗", anim: "drive", name: "Auto" },
                { key: "dice", emoji: "🎲", anim: "roll", name: "Dados" }],
            flags: [{ key: "cl", name: "Chile" }, { key: "mx", name: "México" }, { key: "ar", name: "Argentina" },
                { key: "es", name: "España" }, { key: "co", name: "Colombia" }, { key: "pe", name: "Perú" }]
        });
        var demo = {
            server: "Thorium Roleplay", max: 64, players: [
                { k: "p1", id: 1, name: "Fabian Rojas", ping: 32, lvl: 34, me: true, fac: { tag: "LSPD", name: "Policía de Los Santos", color: "#4dabf7" }, pr: { c: "#f5a524", c2: "#ff6a3d", e: "shine", i: "crown", f: "cl", a: 0 } },
                { k: "p2", id: 2, name: "Carla Mendez", ping: 61, lvl: 22, fac: { tag: "LSMD", name: "Servicios Médicos", color: "#ff4d6d" }, pr: { c: "#ff7eb6", e: "wave", i: "heart", f: "mx", a: 0 } },
                { k: "p3", id: 3, name: "Tony Vercetti", ping: 140, lvl: 12, fac: { tag: "GSF", name: "Grove Street Families", color: "#4cd38a" }, pr: { c: "#4cd38a", e: "glitch", i: "skull", f: "ar", a: 0 } },
                { k: "p4", id: 4, name: "Lucia Paz", ping: 45, lvl: 7, fac: false, pr: { c: "#f2f4f8", e: "rainbow", i: "star", f: "es", a: 0 } },
                { k: "p5", id: 5, name: "Mario Gomez", ping: 260, lvl: 3, fac: false, pr: { c: "#22d3ee", e: "glow", i: "bolt", f: "co", a: 0 } },
                { k: "p6", id: 6, name: "Pedro Soto", ping: 90, lvl: 15, fac: { tag: "TAXI", name: "Downtown Cab Co.", color: "#facc15" }, pr: { c: "#facc15", e: "type", i: "car", f: "pe", a: 0 } },
                { k: "p7", id: 7, name: "Ana Rivas", ping: 70, lvl: 1, off: true, fac: false, pr: false }
            ]
        };
        if (location.hash === "#editor") RP.openEditor(demo.players[0]);
        else RP.open(demo);
    }
})();
