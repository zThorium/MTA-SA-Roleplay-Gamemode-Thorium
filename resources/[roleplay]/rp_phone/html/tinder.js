/*
 * rp_phone / tinder.js  -  App Tinder
 * JS  -> mta.triggerEvent("rp:phone:ui:tinder", accion, ...)   (client/c_tinder.lua)
 * Lua -> RP.tinder.on(evento, [args])  eventos: profile, deck, card, rewound, quota, outOfLikes,
 *        needGold, match, matches, chat, message, typing, read, unmatched, likes, badge
 * Pestañas: Descubrir (mazo arrastrable), Le gustas, Mensajes (matches y chat) y Perfil.
 * Teclas en Descubrir: ← no, → me gusta, ↑ super like, ↓ perfil completo, Espacio siguiente foto.
 */
(function () {
    "use strict";

    var $ = function (id) { return document.getElementById(id); };
    var S = {
        profile: null, draft: null, tab: "discover", queue: [], seen: [], loading: false, empty: false, needPhoto: false,
        photoIdx: {}, likesLeft: 0, supersLeft: 0, gold: false, matches: [], chat: null, likes: null,
        sheet: null, sheetMode: null, pendingSheet: "view", badge: { unread: 0, likes: 0 }, tutorialShown: false,
        renderedTop: null, busyFly: false, uploading: 0, chatRefresh: null,
    };

    function send() {
        var args = ["rp:phone:ui:tinder"].concat(Array.prototype.slice.call(arguments));
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    // ---------------------------------------------------------------- Sonidos (Kenney CC0)
    var SND = {
        like: "sounds/tinder/select_002.ogg", nope: "sounds/tinder/drop_002.ogg", super: "sounds/tinder/bong_001.ogg",
        match: "sounds/tinder/confirmation_003.ogg", message: "sounds/tinder/glass_001.ogg", sent: "sounds/tinder/click_002.ogg",
        error: "sounds/tinder/error_004.ogg", step: "sounds/tinder/pluck_001.ogg", open: "sounds/tinder/maximize_003.ogg",
    };
    function play(name) {
        try {
            var a = new Audio(SND[name]); a.volume = 0.45;
            var pr = a.play(); if (pr && pr.catch) pr.catch(function () { /* sin audio */ });
        } catch (e) { /* sin audio */ }
    }

    // ---------------------------------------------------------------- Utilidades
    function el(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text !== undefined && text !== null) n.textContent = text;
        return n;
    }
    function jpg(b64) { return "data:image/jpeg;base64," + b64; }

    // Fondo dibujado para las fotos de NPC que el estudio aun no saco
    var SCENE_ART = {
        beach_sunset: ["sunset", "🌅"], pier_sunset: ["sunset", "🎡"], verona_day: ["day", "🏖️"], grove: ["city", "🏘️"],
        ganton_gym: ["city", "🏋️"], vinewood_view: ["sunset", "🌇"], vinewood_night: ["night", "🌃"], pershing: ["city", "🏛️"],
        rodeo_shops: ["day", "🛍️"], unity: ["city", "🚉"], chiliad_top: ["forest", "🏔️"], angel_forest: ["forest", "🌲"],
        sf_cranberry: ["city", "🚋"], sf_downtown: ["city", "🌉"], bayside_dock: ["sunset", "⛵"], lv_strip: ["night", "🎰"],
        lv_dragons: ["night", "🐉"], lv_golf: ["day", "⛳"], blueberry: ["forest", "🌾"], palomino: ["sunset", "🏞️"], fort_carson: ["sunset", "🌵"],
    };
    function sceneArt(scene, label) {
        var a = SCENE_ART[scene] || ["sunset", "📷"];
        var d = el("div", "tn-art " + a[0], a[1]);
        if (label) d.appendChild(el("small", null, label));
        return d;
    }
    function photoNode(p) {
        if (p && p.img) { var i = el("img"); i.src = jpg(p.img); i.alt = ""; return i; }
        return sceneArt(p && p.scene, p && p.label);
    }
    function fillAvatar(node, thumb, scene, name) {
        node.innerHTML = "";
        node.style.background = "";
        if (thumb) { var i = el("img"); i.src = jpg(thumb); node.appendChild(i); }
        else if (scene) node.appendChild(sceneArt(scene));
        else { node.textContent = (name || "?").charAt(0).toUpperCase(); node.style.background = "linear-gradient(45deg,#fd267a,#ff7854)"; }
        return node;
    }
    function interestOf(id) {
        var cat = (S.profile && S.profile.catalog) || [];
        for (var i = 0; i < cat.length; i++) if (cat[i].id === id) return cat[i];
        return { id: id, label: id, icon: "" };
    }
    function hhmm(ts) {
        var d = new Date(ts * 1000);
        return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
    }
    function dayLabel(ts) {
        var d = new Date(ts * 1000), now = new Date();
        var days = Math.floor((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000);
        if (days === 0) return "Hoy " + hhmm(ts);
        if (days === 1) return "Ayer " + hhmm(ts);
        return d.getDate() + "/" + (d.getMonth() + 1) + " " + hhmm(ts);
    }
    function overlayOpen() {
        return !$("tn-sheet").hidden || !$("tn-chat").hidden || !$("tn-match").hidden || !$("tn-modal").hidden || !$("tn-tutorial").hidden;
    }
    function isActive() { return $("view-tinder").classList.contains("active"); }

    // ---------------------------------------------------------------- Aviso flotante
    var toastTimer = null;
    function toast(text, opts) {
        opts = opts || {};
        var t = $("tn-toast");
        t.innerHTML = "";
        if (opts.avatar) t.appendChild(fillAvatar(el("div", "tn-avatar"), opts.avatar.thumb, opts.avatar.scene, opts.avatar.name));
        t.appendChild(el("span", null, text));
        t.onclick = function () { t.hidden = true; if (opts.onClick) opts.onClick(); };
        t.hidden = false;
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { t.hidden = true; }, opts.time || 4000);
    }

    // ---------------------------------------------------------------- Modal
    function modal(title, text, buttons) {
        $("tn-modal-title").textContent = title;
        $("tn-modal-text").textContent = text;
        var box = $("tn-modal-btns");
        box.innerHTML = "";
        (buttons || [{ label: "Entendido" }]).forEach(function (b) {
            var btn = el("button", b.cls || "", b.label);
            btn.type = "button";
            btn.addEventListener("click", function () { $("tn-modal").hidden = true; if (b.fn) b.fn(); });
            box.appendChild(btn);
        });
        $("tn-modal").hidden = false;
    }
    function goldModal(reason) {
        var p = S.profile || {};
        var why = { rewind: "Deshacer tu último «No» es de Tinder Gold.", likes: "Con Tinder Gold ves quién te dio like y haces match al instante." }[reason]
            || "Likes ilimitados, 5 Super Likes al día, ver quién te dio like y deshacer.";
        modal("Tinder Gold", why + " Cuesta $" + (p.goldPrice || 300) + " por " + (p.goldDaysBuy || 7) + " días (se cobra del banco).", [
            { label: "Obtener Gold", cls: "gold", fn: function () { send("gold"); } },
            { label: "Ahora no" },
        ]);
    }
    function outOfLikes(kind) {
        play("error");
        var now = new Date(), mid = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
        var h = Math.floor((mid - now) / 3600000), m = Math.floor(((mid - now) % 3600000) / 60000);
        if (kind === "supers") {
            modal("Sin Super Likes", "Ya usaste tu Super Like de hoy. Vuelve en " + h + " h " + m + " min o consigue más con Gold.", [
                { label: "Obtener Gold", cls: "gold", fn: function () { goldModal(); } }, { label: "Entendido" }]);
        } else {
            modal("Te quedaste sin likes", "Hoy ya diste todos tus likes gratis. Vuelven en " + h + " h " + m + " min.", [
                { label: "Likes ilimitados con Gold", cls: "gold", fn: function () { goldModal(); } }, { label: "Esperar" }]);
        }
    }

    // ---------------------------------------------------------------- Pestañas
    function setTab(tab) {
        S.tab = tab;
        ["discover", "likes", "messages", "profile"].forEach(function (t) { $("tn-page-" + t).hidden = t !== tab; });
        document.querySelectorAll(".tn-nav [data-tn]").forEach(function (b) { b.classList.toggle("active", b.dataset.tn === tab); });
        if (tab === "discover") { renderStack(); requestCard(); }
        if (tab === "likes") send("likes");
        if (tab === "messages") send("matches");
        if (tab === "profile") renderProfile();
    }
    document.querySelectorAll(".tn-nav [data-tn]").forEach(function (b) {
        b.addEventListener("click", function () { setTab(b.dataset.tn); });
    });
    $("tn-home").addEventListener("click", function () { window.Phone.show("home"); });
    $("tn-help").addEventListener("click", function () { startTutorial(); });

    // ---------------------------------------------------------------- Perfil
    function currentDraft() {
        return {
            bio: $("tn-bio").value, job: $("tn-job").value, interests: Array.prototype.map.call(document.querySelectorAll("#tn-interests .tn-chip.on"), function (c) { return c.dataset.id; }),
            interested: (document.querySelector("#tn-interested .on") || {}).dataset ? document.querySelector("#tn-interested .on").dataset.v : "a",
            ageMin: Number($("tn-age-min").value), ageMax: Number($("tn-age-max").value), active: $("tn-active").checked,
        };
    }
    function qualityTip(p) {
        if (!p.photos[0]) return "Pon una foto principal: sin foto nadie te ve.";
        var n = p.photos.filter(Boolean).length;
        if (n < 3) return "Con 3 o más fotos recibes muchos más likes.";
        if ((p.bio || "").length < 30) return "Escribe algo sobre ti: las personas leen tu descripción.";
        if ((p.interests || []).length < 3) return "Elige al menos 3 pasiones: los gustos en común dan matches.";
        if (!p.job) return "Pon a qué te dedicas.";
        return "¡Tu perfil está genial!";
    }
    function renderPhotos(p) {
        var box = $("tn-photos");
        box.innerHTML = "";
        for (var i = 0; i < 4; i++) {
            (function (slot) {
                var img = p.photos[slot - 1];
                var s = el("div", "tn-slot" + (img ? " filled" : ""));
                if (img) {
                    var im = el("img"); im.src = jpg(img); s.appendChild(im);
                    if (slot === 1) s.appendChild(el("span", "main", "PRINCIPAL"));
                    if (slot > 1) {
                        var x = el("button", "x", "✕"); x.type = "button"; x.title = "Quitar";
                        x.addEventListener("click", function (e) { e.stopPropagation(); send("photoRemove", slot); });
                        s.appendChild(x);
                    }
                } else s.textContent = "+";
                if (S.uploading === slot) s.textContent = "⏳";
                s.addEventListener("click", function () { choosePhoto(slot, !!img); });
                box.appendChild(s);
            })(i + 1);
        }
    }
    function renderProfile() {
        var p = S.profile;
        if (!p) return;
        var d = S.draft || { bio: p.bio, job: p.job, interests: p.interests || [], interested: p.interested, ageMin: p.ageMin, ageMax: p.ageMax, active: p.active };
        $("tn-quality").textContent = (p.quality || 0) + "%";
        $("tn-quality-bar").style.width = (p.quality || 0) + "%";
        $("tn-quality-tip").textContent = qualityTip(p);
        renderPhotos(p);
        $("tn-data").textContent = p.first + ", " + p.age + " · datos de tu personaje";
        $("tn-bio").value = d.bio || "";
        $("tn-bio-count").textContent = ($("tn-bio").value.length) + "/300";
        $("tn-job").value = d.job || "";
        var box = $("tn-interests");
        box.innerHTML = "";
        (p.catalog || []).forEach(function (it) {
            var c = el("span", "tn-chip" + (d.interests.indexOf(it.id) >= 0 ? " on" : ""), it.icon + " " + it.label);
            c.dataset.id = it.id;
            c.addEventListener("click", function () {
                var on = document.querySelectorAll("#tn-interests .tn-chip.on").length;
                if (!c.classList.contains("on") && on >= 5) { play("error"); return toast("Máximo 5 pasiones."); }
                c.classList.toggle("on");
                $("tn-int-count").textContent = document.querySelectorAll("#tn-interests .tn-chip.on").length + "/5";
            });
            box.appendChild(c);
        });
        $("tn-int-count").textContent = d.interests.length + "/5";
        document.querySelectorAll("#tn-interested button").forEach(function (b) { b.classList.toggle("on", b.dataset.v === (d.interested || "a")); });
        $("tn-age-min").value = d.ageMin || 18;
        $("tn-age-max").value = d.ageMax || 70;
        ageText();
        $("tn-active").checked = d.active !== false;
        $("tn-gold-buy").disabled = !!p.gold;
        $("tn-gold-buy").textContent = p.gold ? "Gold activo · " + p.goldDays + " días" : "Obtener Gold · $" + p.goldPrice + " / " + p.goldDaysBuy + " días";
    }
    function ageText() {
        var a = Number($("tn-age-min").value), b = Number($("tn-age-max").value);
        if (a > b) { var t = a; a = b; b = t; }
        $("tn-age-text").textContent = a + " - " + b;
    }
    $("tn-age-min").addEventListener("input", ageText);
    $("tn-age-max").addEventListener("input", ageText);
    $("tn-bio").addEventListener("input", function () { $("tn-bio-count").textContent = $("tn-bio").value.length + "/300"; });
    document.querySelectorAll("#tn-interested button").forEach(function (b) {
        b.addEventListener("click", function () {
            document.querySelectorAll("#tn-interested button").forEach(function (x) { x.classList.toggle("on", x === b); });
        });
    });
    $("tn-save").addEventListener("click", function () {
        var d = currentDraft();
        var a = Math.min(d.ageMin, d.ageMax), b = Math.max(d.ageMin, d.ageMax);
        d.ageMin = a; d.ageMax = b;
        S.draft = null;
        send("save", "[" + JSON.stringify(d) + "]");
        play("sent");
        // Preferencias nuevas: el mazo se vuelve a armar
        S.queue = []; S.empty = false; S.renderedTop = null;
    });
    $("tn-gold-buy").addEventListener("click", function () { goldModal(); });
    $("tn-likes-gold").addEventListener("click", function () { goldModal("likes"); });
    $("tn-tutorial-again").addEventListener("click", function () { startTutorial(); });

    // Miniatura 120x150 para las listas (solo la foto principal)
    function makeThumb(b64, cb) {
        var img = new Image();
        img.onload = function () {
            var c = document.createElement("canvas"); c.width = 120; c.height = 150;
            var g = c.getContext("2d");
            var r = Math.max(120 / img.width, 150 / img.height), w = img.width * r, h = img.height * r;
            g.drawImage(img, (120 - w) / 2, (150 - h) / 2, w, h);
            cb(c.toDataURL("image/jpeg", 0.8).split(",")[1]);
        };
        img.onerror = function () { cb(null); };
        img.src = jpg(b64);
    }
    function choosePhoto(slot, replacing) {
        var upload = function (b64) {
            S.draft = currentDraft();
            window.Phone.show("tinder");
            setTab("profile");
            if (!b64) return;
            S.uploading = slot;
            renderPhotos(S.profile);
            var go = function (thumb) { send("photo", slot, b64, thumb || ""); };
            if (slot === 1) makeThumb(b64, go); else go(null);
        };
        modal(replacing ? "Cambiar foto" : "Añadir foto", slot === 1 ? "Tu foto principal es la primera que ve todo el mundo." : "Las fotos extra muestran más de ti.", [
            { label: "📷 Tomar foto", cls: "primary", fn: function () { S.draft = currentDraft(); Gallery.takePhoto(upload); } },
            { label: "🖼️ Elegir de la galería", fn: function () { S.draft = currentDraft(); Gallery.pick("Foto de Tinder", upload); } },
            { label: "Cancelar" },
        ]);
    }

    // ---------------------------------------------------------------- Mazo
    function requestCard() {
        if (S.loading || S.empty || S.needPhoto || S.queue.length >= 2 || !S.profile) return;
        S.loading = true;
        var exclude = S.queue.map(function (c) { return c.key; }).concat(S.seen.slice(-8));
        send("deck", exclude.join(","));
        setTimeout(function () { S.loading = false; }, 6000);
    }

    function renderState() {
        var st = $("tn-state"), btn = $("tn-state-btn");
        var none = S.queue.length === 0;
        st.hidden = !none;
        ["tn-nope", "tn-like", "tn-super"].forEach(function (id) { $(id).disabled = none; });
        $("tn-rewind").disabled = false;
        if (!none) return;
        var me = $("tn-radar-me");
        me.style.backgroundImage = S.profile && S.profile.photos[0] ? "url(" + jpg(S.profile.photos[0]) + ")" : "";
        btn.hidden = true;
        if (S.needPhoto) {
            $("tn-state-text").textContent = "Pon una foto principal para que la gente te vea y empezar a descubrir personas.";
            btn.textContent = "Ir a mi perfil"; btn.hidden = false; btn.onclick = function () { setTab("profile"); };
        } else if (S.empty) {
            $("tn-state-text").textContent = "No hay nadie nuevo por ahora. Vuelve más tarde o amplía tu rango de edad.";
            btn.textContent = "Ajustar preferencias"; btn.hidden = false; btn.onclick = function () { setTab("profile"); };
        } else {
            $("tn-state-text").textContent = "Buscando personas cerca...";
        }
    }

    function buildCard(card, top) {
        var c = el("div", "tn-card" + (top ? "" : " behind"));
        c.dataset.key = card.key;
        var wrap = el("div", "tn-photo-wrap");
        var bars = el("div", "tn-bars");
        var photos = card.photos && card.photos.length ? card.photos : [{ scene: null }];
        var idx = S.photoIdx[card.key] || 0;
        function showPhoto(i) {
            idx = Math.max(0, Math.min(photos.length - 1, i));
            S.photoIdx[card.key] = idx;
            wrap.innerHTML = "";
            wrap.appendChild(photoNode(photos[idx]));
            bars.innerHTML = "";
            if (photos.length > 1) photos.forEach(function (_, j) { bars.appendChild(el("i", j === idx ? "on" : "")); });
        }
        showPhoto(idx);
        c.showPhoto = function (step) { showPhoto(idx + step); };
        c.appendChild(wrap);
        c.appendChild(bars);
        if (card.superLiked) c.appendChild(el("div", "tn-super-badge", "⭐ Te dio Super Like"));
        ["like", "nope", "super"].forEach(function (k) { c.appendChild(el("div", "tn-stamp " + k, { like: "LIKE", nope: "NOPE", super: "SUPER\nLIKE" }[k])); });

        var info = el("div", "tn-card-info");
        var name = el("div", "tn-card-name", card.name);
        name.appendChild(el("span", null, card.age));
        if (card.verified) name.appendChild(el("i", "tn-verified", "✓"));
        info.appendChild(name);
        if (card.active) {
            var act = el("div", "tn-card-line");
            if (card.online) act.appendChild(el("i", "tn-online"));
            act.appendChild(el("span", null, card.active));
            info.appendChild(act);
        }
        if (card.job) info.appendChild(el("div", "tn-card-line", "💼 " + card.job));
        var where = card.km ? "📍 a " + card.km + " km" : (card.zone ? "🏠 Vive en " + card.zone : "");
        if (where) info.appendChild(el("div", "tn-card-line", where));
        if (card.bio) info.appendChild(el("div", "tn-card-bio", card.bio));
        var chips = el("div", "tn-chips");
        var shared = card.shared || [];
        (card.interests || []).slice().sort(function (a, b) { return (shared.indexOf(b) >= 0) - (shared.indexOf(a) >= 0); }).slice(0, 4).forEach(function (id) {
            var it = interestOf(id);
            chips.appendChild(el("span", "tn-chip" + (shared.indexOf(id) >= 0 ? " shared" : ""), it.icon + " " + it.label));
        });
        info.appendChild(chips);
        c.appendChild(info);
        var ib = el("button", "tn-info-btn", "i");
        ib.type = "button";
        ib.title = "Ver perfil (↓)";
        ib.addEventListener("mousedown", function (e) { e.stopPropagation(); });
        ib.addEventListener("click", function (e) { e.stopPropagation(); openSheet(card, "deck"); });
        c.appendChild(ib);
        if (top) attachDrag(c, card);
        return c;
    }

    function renderStack() {
        renderState();
        var stack = $("tn-stack");
        var top = S.queue[0], next = S.queue[1];
        if (!top) { stack.innerHTML = ""; S.renderedTop = null; return; }
        if (S.renderedTop === top.key && stack.querySelector(".tn-card:not(.behind)")) {
            if (next && !stack.querySelector(".tn-card.behind")) stack.insertBefore(buildCard(next, false), stack.firstChild);
            return;
        }
        stack.innerHTML = "";
        if (next) stack.appendChild(buildCard(next, false));
        stack.appendChild(buildCard(top, true));
        S.renderedTop = top.key;
    }

    function setStamps(c, dx, dy) {
        var like = Math.max(0, Math.min(1, dx / 100)), nope = Math.max(0, Math.min(1, -dx / 100));
        var sup = dy < 0 && Math.abs(dy) > Math.abs(dx) ? Math.max(0, Math.min(1, -dy / 110)) : 0;
        c.querySelector(".tn-stamp.like").style.opacity = sup ? 0 : like;
        c.querySelector(".tn-stamp.nope").style.opacity = sup ? 0 : nope;
        c.querySelector(".tn-stamp.super").style.opacity = sup;
    }

    function attachDrag(c, card) {
        c.addEventListener("mousedown", function (e) {
            if (e.button !== 0 || S.busyFly) return;
            var sx = e.clientX, sy = e.clientY, dx = 0, dy = 0, moved = false;
            c.classList.add("dragging");
            function move(ev) {
                dx = ev.clientX - sx; dy = ev.clientY - sy;
                if (Math.abs(dx) + Math.abs(dy) > 6) moved = true;
                c.style.transform = "translate(" + dx + "px," + dy + "px) rotate(" + (dx * 0.07) + "deg)";
                setStamps(c, dx, dy);
            }
            function up(ev) {
                document.removeEventListener("mousemove", move);
                document.removeEventListener("mouseup", up);
                c.classList.remove("dragging");
                if (!moved) {
                    // Clic: mitad izquierda = foto anterior, derecha = siguiente
                    var r = c.getBoundingClientRect();
                    c.showPhoto(ev.clientX - r.left < r.width / 2 ? -1 : 1);
                    return;
                }
                if (dx > 110) return swipe("like");
                if (dx < -110) return swipe("nope");
                if (dy < -120 && Math.abs(dy) > Math.abs(dx)) return swipe("super");
                c.classList.add("back");
                c.style.transform = "";
                setStamps(c, 0, 0);
                setTimeout(function () { c.classList.remove("back"); }, 260);
            }
            document.addEventListener("mousemove", move);
            document.addEventListener("mouseup", up);
        });
    }

    function swipe(action) {
        var card = S.queue[0];
        if (!card || S.busyFly) return;
        if (action === "like" && S.likesLeft <= 0) { resetTop(); return outOfLikes("likes"); }
        if (action === "super" && S.supersLeft <= 0) { resetTop(); return outOfLikes("supers"); }
        var c = $("tn-stack").querySelector(".tn-card:not(.behind)");
        S.busyFly = true;
        if (c) {
            c.classList.remove("dragging");
            c.classList.add("fly");
            setStamps(c, action === "like" ? 120 : action === "nope" ? -120 : 0, action === "super" ? -150 : 0);
            c.style.transform = action === "like" ? "translate(160%, 40px) rotate(28deg)"
                : action === "nope" ? "translate(-160%, 40px) rotate(-28deg)" : "translate(0, -150%)";
            c.style.opacity = "0.4";
        }
        play(action);
        if (action === "like") S.likesLeft--;
        if (action === "super") S.supersLeft--;
        send("swipe", card.key, action);
        setTimeout(function () {
            S.busyFly = false;
            S.queue.shift();
            S.seen.push(card.key);
            if (S.seen.length > 30) S.seen.shift();
            delete S.photoIdx[card.key];
            var behind = $("tn-stack").querySelector(".tn-card.behind");
            if (behind) { behind.classList.remove("behind"); }
            S.renderedTop = null;
            renderStack();
            requestCard();
        }, 300);
    }
    function resetTop() {
        var c = $("tn-stack").querySelector(".tn-card:not(.behind)");
        if (c) { c.classList.add("back"); c.style.transform = ""; setStamps(c, 0, 0); }
    }

    $("tn-like").addEventListener("click", function () { swipe("like"); });
    $("tn-nope").addEventListener("click", function () { swipe("nope"); });
    $("tn-super").addEventListener("click", function () { swipe("super"); });
    $("tn-rewind").addEventListener("click", function () {
        if (!S.gold) return goldModal("rewind");
        send("rewind");
    });

    // ---------------------------------------------------------------- Perfil completo
    function openSheet(card, mode) {
        S.sheet = card;
        S.sheetMode = mode;
        var body = $("tn-sheet-body");
        body.innerHTML = "";
        var ph = el("div", "tn-sheet-photo");
        var photos = card.photos && card.photos.length ? card.photos : [{}];
        var idx = 0, bars = el("div", "tn-bars"), wrap = el("div", "tn-photo-wrap");
        function show(i) {
            idx = (i + photos.length) % photos.length;
            wrap.innerHTML = ""; wrap.appendChild(photoNode(photos[idx]));
            bars.innerHTML = "";
            if (photos.length > 1) photos.forEach(function (_, j) { bars.appendChild(el("i", j === idx ? "on" : "")); });
        }
        show(S.photoIdx[card.key] || 0);
        ph.appendChild(wrap); ph.appendChild(bars);
        ph.addEventListener("click", function (e) {
            var r = ph.getBoundingClientRect();
            show(idx + (e.clientX - r.left < r.width / 2 ? -1 : 1));
        });
        body.appendChild(ph);
        var head = el("div", "tn-sheet-head");
        var h = el("h3", null, card.name); h.appendChild(el("span", null, card.age));
        if (card.verified) h.appendChild(el("i", "tn-verified", "✓"));
        head.appendChild(h);
        body.appendChild(head);
        if (card.job) body.appendChild(el("div", "tn-sheet-row", "💼 " + card.job));
        if (card.zone) body.appendChild(el("div", "tn-sheet-row", "🏠 Vive en " + card.zone + (card.city ? ", " + card.city : "")));
        if (card.km) body.appendChild(el("div", "tn-sheet-row", "📍 a " + card.km + " km de ti"));
        if (card.active) body.appendChild(el("div", "tn-sheet-row", (card.online ? "🟢 " : "🕒 ") + card.active));
        if (card.bio) {
            var sec = el("div", "tn-sheet-sec");
            sec.appendChild(el("h4", null, "Sobre mí"));
            sec.appendChild(el("div", null, card.bio));
            body.appendChild(sec);
        }
        (card.prompts || []).forEach(function (pr) {
            var s = el("div", "tn-sheet-sec tn-prompt");
            s.appendChild(el("b", null, pr.q));
            s.appendChild(el("p", null, pr.a));
            body.appendChild(s);
        });
        if ((card.interests || []).length) {
            var sec2 = el("div", "tn-sheet-sec");
            sec2.appendChild(el("h4", null, "Pasiones" + ((card.shared || []).length ? " · " + card.shared.length + " en común" : "")));
            var chips = el("div", "tn-chips");
            card.interests.forEach(function (id) {
                var it = interestOf(id);
                chips.appendChild(el("span", "tn-chip" + ((card.shared || []).indexOf(id) >= 0 ? " shared" : ""), it.icon + " " + it.label));
            });
            sec2.appendChild(chips);
            body.appendChild(sec2);
        }
        $("tn-sheet-actions").hidden = mode === "view";
        $("tn-sheet").hidden = false;
        body.scrollTop = 0;
    }
    function closeSheet() { $("tn-sheet").hidden = true; S.sheet = null; }
    $("tn-sheet-close").addEventListener("click", closeSheet);
    document.querySelectorAll("[data-sa]").forEach(function (b) {
        b.addEventListener("click", function () {
            var action = b.dataset.sa, card = S.sheet;
            if (!card) return;
            closeSheet();
            if (S.sheetMode === "deck") return swipe(action);
            // Desde "Le gustas"
            if (action === "like" && S.likesLeft <= 0) return outOfLikes("likes");
            play(action);
            send("swipe", card.key, action);
            S.seen.push(card.key);
            setTimeout(function () { send("likes"); }, 600);
        });
    });

    // ---------------------------------------------------------------- Le gustas
    function renderLikes(data) {
        S.likes = data;
        var list = data.list || [];
        $("tn-likes-title").textContent = list.length === 1 ? "Le gustas a 1 persona" : "Le gustas a " + list.length + " personas";
        $("tn-likes-sub").textContent = data.gold ? "Toca a alguien para ver su perfil y hacer match." :
            (list.length ? "Desliza a la derecha en Descubrir: si le das like a quien te dio like, es match al instante." : "Cuando alguien te dé like aparecerá aquí. Un buen perfil ayuda.");
        $("tn-likes-gold").hidden = !!data.gold || !list.length;
        var grid = $("tn-likes-grid");
        grid.innerHTML = "";
        list.forEach(function (m) {
            var t = el("div", "tn-like-tile" + (data.gold ? "" : " blur"));
            if (m.thumb) { var i = el("img"); i.src = jpg(m.thumb); t.appendChild(i); } else t.appendChild(sceneArt(m.scene));
            if (data.gold) t.appendChild(el("b", null, m.name + ", " + m.age));
            if (m.super) t.appendChild(el("span", "star", "★"));
            t.addEventListener("click", function () {
                if (!data.gold) return goldModal("likes");
                S.pendingSheet = "likes";
                send("card", m.key);
            });
            grid.appendChild(t);
        });
    }

    // ---------------------------------------------------------------- Mensajes
    function renderMatches(list) {
        S.matches = list || [];
        var nm = $("tn-new-matches"), cv = $("tn-convos");
        nm.innerHTML = ""; cv.innerHTML = "";
        var fresh = S.matches.filter(function (m) { return !m.last; });
        var talks = S.matches.filter(function (m) { return m.last; });
        if (!fresh.length) nm.appendChild(el("p", "tn-empty", "Tus matches nuevos aparecerán aquí."));
        fresh.forEach(function (m) {
            var d = el("div", "tn-nm" + (m.unread ? " unread" : ""));
            d.appendChild(fillAvatar(el("div", "tn-avatar"), m.thumb, m.scene, m.name));
            d.appendChild(el("span", null, m.name));
            d.addEventListener("click", function () { openChat(m); });
            nm.appendChild(d);
        });
        if (!talks.length) cv.appendChild(el("p", "tn-empty", "Aún no tienes conversaciones. ¡Escríbele a un match!"));
        talks.forEach(function (m) {
            var row = el("div", "tn-convo" + (m.unread ? " unread" : ""));
            var av = fillAvatar(el("div", "tn-avatar"), m.thumb, m.scene, m.name);
            if (m.online) av.appendChild(el("i", "tn-online"));
            row.appendChild(av);
            var tx = el("div");
            var nameEl = el("strong", null, m.name);
            if (!m.lastMine) nameEl.appendChild(el("span", "tn-turn", "Tu turno"));
            tx.appendChild(nameEl);
            tx.appendChild(el("small", null, (m.lastMine ? "Tú: " : "") + m.last));
            row.appendChild(tx);
            row.addEventListener("click", function () { openChat(m); });
            cv.appendChild(row);
        });
    }
    function matchByKey(key) {
        for (var i = 0; i < S.matches.length; i++) if (S.matches[i].key === key) return S.matches[i];
        return null;
    }

    // ---------------------------------------------------------------- Chat
    function openChat(m) {
        S.chat = { key: m.key, name: m.name, thumb: m.thumb, scene: m.scene, messages: [], typing: false };
        $("tn-chat-name").textContent = m.name || "";
        $("tn-chat-active").textContent = "";
        fillAvatar($("tn-chat-avatar"), m.thumb, m.scene, m.name);
        $("tn-msgs").innerHTML = "";
        $("tn-msgs").appendChild(el("p", "tn-empty", "Cargando..."));
        $("tn-suggest").hidden = true;
        $("tn-number").hidden = true;
        $("tn-menu").hidden = true;
        $("tn-chat").hidden = false;
        $("tn-input").value = "";
        send("chat", m.key);
        setTimeout(function () { $("tn-input").focus(); }, 200);
    }
    function closeChat() {
        $("tn-chat").hidden = true;
        S.chat = null;
        if (S.tab === "messages") send("matches");
        send("badge");
    }
    $("tn-chat-back").addEventListener("click", closeChat);
    $("tn-chat-menu").addEventListener("click", function () { $("tn-menu").hidden = !$("tn-menu").hidden; });
    $("tn-menu-profile").addEventListener("click", function () {
        $("tn-menu").hidden = true;
        if (S.chat) { S.pendingSheet = "view"; send("card", S.chat.key); }
    });
    $("tn-menu-unmatch").addEventListener("click", function () {
        $("tn-menu").hidden = true;
        if (!S.chat) return;
        var key = S.chat.key, name = S.chat.name;
        modal("¿Deshacer el match?", "Ya no podrán escribirse y " + name + " desaparecerá de tus mensajes.", [
            { label: "Deshacer match", cls: "primary", fn: function () { send("unmatch", key); } }, { label: "Cancelar" }]);
    });

    function renderChat() {
        var c = S.chat, box = $("tn-msgs");
        if (!c) return;
        box.innerHTML = "";
        var intro = el("div", "matched");
        intro.appendChild(fillAvatar(el("div", "tn-avatar"), c.thumb, c.scene, c.name));
        intro.appendChild(el("div", null, "Hiciste match con " + c.name));
        box.appendChild(intro);
        var lastTs = 0, lastMineIdx = -1;
        c.messages.forEach(function (m, i) { if (m.mine) lastMineIdx = i; });
        c.messages.forEach(function (m, i) {
            if (m.ts && m.ts - lastTs > 3600) box.appendChild(el("div", "when", dayLabel(m.ts)));
            lastTs = m.ts || lastTs;
            box.appendChild(el("div", "tn-bubble " + (m.mine ? "mine" : "them"), m.body));
            if (i === lastMineIdx && m.read && i === c.messages.length - 1) box.appendChild(el("div", "tn-seen", "Visto"));
        });
        if (c.typing) {
            var t = el("div", "tn-typing");
            t.appendChild(el("i")); t.appendChild(el("i")); t.appendChild(el("i"));
            box.appendChild(t);
        }
        box.scrollTop = box.scrollHeight;
    }
    function setNumber(number) {
        var b = $("tn-number");
        if (!number) { b.hidden = true; return; }
        var pretty = String(number).replace(/^(\d{3})(\d{4})$/, "$1-$2");
        b.innerHTML = "";
        b.appendChild(el("span", null, "📞 " + (S.chat ? S.chat.name : "") + " te dio su número: " + pretty));
        var call = el("button", null, "Llamar");
        call.type = "button";
        call.addEventListener("click", function () { if (window.Phone.call) window.Phone.call(String(number)); });
        b.appendChild(call);
        b.hidden = false;
    }
    function sendChat(text) {
        text = (text || "").trim();
        if (!text || !S.chat) return;
        send("send", S.chat.key, text);
        play("sent");
        $("tn-suggest").hidden = true;
    }
    $("tn-compose").addEventListener("submit", function (e) {
        e.preventDefault();
        sendChat($("tn-input").value);
        $("tn-input").value = "";
    });

    // ---------------------------------------------------------------- Match
    var lastMatch = null;
    function showMatch(info) {
        lastMatch = info;
        play("match");
        $("tn-match-text").textContent = "Tú y " + info.name + " se gustaron.";
        fillAvatar($("tn-match-me"), S.profile && S.profile.photos[0], null, S.profile && S.profile.first);
        fillAvatar($("tn-match-them"), info.thumb, info.scene, info.name);
        $("tn-match-input").value = "";
        $("tn-match").hidden = false;
    }
    $("tn-match-close").addEventListener("click", function () { $("tn-match").hidden = true; });
    $("tn-match-form").addEventListener("submit", function (e) {
        e.preventDefault();
        var text = $("tn-match-input").value.trim();
        $("tn-match").hidden = true;
        if (!lastMatch) return;
        openChat(lastMatch);
        if (text) setTimeout(function () { sendChat(text); }, 300);
    });

    // ---------------------------------------------------------------- Tutorial
    var TUT = [
        { art: '<div class="mini-card"></div><img src="img/mouse_move.png" alt="">', title: "Desliza para decidir",
          text: "Arrastra la tarjeta a la derecha si te gusta y a la izquierda si no. También con las flechas ← y →." },
        { art: '<span style="color:#1786ff">★</span><img src="img/keyboard_arrow_up.png" alt=""><img src="img/mouse_left.png" alt="">', title: "Super Like y fotos",
          text: "Con ↑ mandas un Super Like: esa persona sabrá que te encantó. Haz clic en la foto para ver las demás y pulsa ↓ o ⓘ para ver su perfil completo." },
        { art: "💬", title: "Match y chat",
          text: "Si los dos se dan like, ¡es un match! Escríbele en 💬. Cada persona es distinta: algunas tardan en contestar, otras escriben primero... y si eres grosero o aburrido, se van." },
        { art: "👤", title: "Tu perfil",
          text: "Sin foto nadie te ve. Con varias fotos, una buena descripción y tus pasiones recibirás muchos más likes." },
    ];
    var tutStep = 0;
    function renderTut() {
        var s = TUT[tutStep];
        $("tn-tut-art").innerHTML = s.art;   // contenido fijo del tutorial, sin datos del jugador
        $("tn-tut-title").textContent = s.title;
        $("tn-tut-text").textContent = s.text;
        var dots = $("tn-tut-dots"); dots.innerHTML = "";
        TUT.forEach(function (_, i) { dots.appendChild(el("i", i === tutStep ? "on" : "")); });
        $("tn-tut-next").textContent = tutStep === TUT.length - 1 ? "¡A deslizar!" : "Siguiente";
        play("step");
    }
    function startTutorial() { tutStep = 0; $("tn-tutorial").hidden = false; renderTut(); }
    $("tn-tut-next").addEventListener("click", function () {
        tutStep++;
        if (tutStep < TUT.length) return renderTut();
        $("tn-tutorial").hidden = true;
        send("tutorial");
        if (S.profile) S.profile.tutorial = true;
        if (S.profile && !S.profile.photos[0]) setTab("profile");
    });

    // ---------------------------------------------------------------- Teclado
    document.addEventListener("keydown", function (e) {
        if (!isActive()) return;
        var tag = document.activeElement && document.activeElement.tagName;
        // Esc cierra primero lo que este abierto en la app (antes que el telefono)
        if (e.key === "Escape" && overlayOpen()) {
            e.preventDefault(); e.stopImmediatePropagation();
            if (!$("tn-modal").hidden) $("tn-modal").hidden = true;
            else if (!$("tn-tutorial").hidden) { $("tn-tutorial").hidden = true; send("tutorial"); }
            else if (!$("tn-match").hidden) $("tn-match").hidden = true;
            else if (!$("tn-sheet").hidden) closeSheet();
            else if (!$("tn-chat").hidden) closeChat();
            return;
        }
        if (tag === "INPUT" || tag === "TEXTAREA") return;
        if (S.tab !== "discover" || !$("tn-chat").hidden || !$("tn-match").hidden || !$("tn-modal").hidden || !$("tn-tutorial").hidden) return;
        var sheet = !$("tn-sheet").hidden;
        if (e.key === "ArrowLeft") { e.preventDefault(); sheet ? document.querySelector('[data-sa="nope"]').click() : swipe("nope"); }
        else if (e.key === "ArrowRight") { e.preventDefault(); sheet ? document.querySelector('[data-sa="like"]').click() : swipe("like"); }
        else if (e.key === "ArrowUp") { e.preventDefault(); sheet ? document.querySelector('[data-sa="super"]').click() : swipe("super"); }
        else if (e.key === "ArrowDown") {
            e.preventDefault();
            if (sheet) closeSheet(); else if (S.queue[0]) openSheet(S.queue[0], "deck");
        } else if (e.key === " " && !sheet) {
            e.preventDefault();
            var c = $("tn-stack").querySelector(".tn-card:not(.behind)");
            if (c) c.showPhoto(1);
        }
    }, true);

    // ---------------------------------------------------------------- Insignias
    function setBadge(b) {
        S.badge = b || S.badge;
        var badge = $("tinder-badge");
        badge.hidden = !S.badge.unread;
        badge.textContent = S.badge.unread > 9 ? "9+" : String(S.badge.unread || "");
        $("tn-nav-msgs").hidden = !S.badge.unread;
        $("tn-nav-likes").hidden = !S.badge.likes;
    }

    // ---------------------------------------------------------------- Eventos de Lua
    var ON = {
        profile: function (p) {
            var first = !S.profile;
            S.profile = p;
            S.uploading = 0;
            S.gold = !!p.gold;
            S.likesLeft = p.likesLeft; S.supersLeft = p.supersLeft;
            S.needPhoto = !p.photos[0];
            $("tn-gold-tag").hidden = !p.gold;
            if (S.tab === "profile") renderProfile();
            if (S.tab === "discover") { renderState(); requestCard(); }
            if (first && !p.tutorial && !S.tutorialShown) { S.tutorialShown = true; startTutorial(); }
        },
        deck: function (card) {
            S.loading = false;
            if (!card) return;
            if (card.needPhoto) { S.needPhoto = true; return renderStack(); }
            if (card.empty) { S.empty = true; return renderStack(); }
            if (S.queue.some(function (q) { return q.key === card.key; })) return;
            S.queue.push(card);
            renderStack();
            requestCard();
        },
        card: function (card) {
            if (card) openSheet(card, S.pendingSheet || "view");
            S.pendingSheet = "view";
        },
        rewound: function (card) {
            if (!card) return;
            S.queue.unshift(card);
            S.renderedTop = null;
            play("step");
            renderStack();
        },
        quota: function (likes, supers) { S.likesLeft = likes; S.supersLeft = supers; },
        outOfLikes: function (kind) { outOfLikes(kind); },
        needGold: function (what) { goldModal(what); },
        match: function (info) {
            if (!info) return;
            if (!$("tn-chat").hidden && S.chat && S.chat.key === info.key) return;
            showMatch(info);
            if (S.tab === "messages") send("matches");
        },
        matches: function (list) { renderMatches(list); },
        chat: function (data) {
            if (!data || !S.chat || S.chat.key !== data.key) return;
            S.chat.messages = data.messages || [];
            S.chat.typing = !!data.typing;
            S.chat.name = data.name || S.chat.name;
            S.chat.thumb = data.thumb || S.chat.thumb;
            S.chat.scene = data.scene || S.chat.scene;
            $("tn-chat-name").textContent = S.chat.name;
            $("tn-chat-active").textContent = data.online ? "🟢 En línea" : (data.active || "");
            fillAvatar($("tn-chat-avatar"), S.chat.thumb, S.chat.scene, S.chat.name);
            setNumber(data.number);
            var sug = $("tn-suggest");
            sug.innerHTML = "";
            if (data.suggestions && data.suggestions.length) {
                data.suggestions.forEach(function (s) {
                    var b = el("button", null, s);
                    b.type = "button";
                    b.addEventListener("click", function () { sendChat(s); });
                    sug.appendChild(b);
                });
                sug.hidden = false;
            } else sug.hidden = true;
            renderChat();
            send("badge");
        },
        message: function (key, msg) {
            if (!msg) return;
            if (S.chat && S.chat.key === key && !$("tn-chat").hidden) {
                S.chat.messages.push(msg);
                if (!msg.mine) {
                    S.chat.typing = false;
                    play("message");
                    // Marca como leido en el servidor (refresca el chat)
                    clearTimeout(S.chatRefresh);
                    S.chatRefresh = setTimeout(function () { if (S.chat && S.chat.key === key) send("chat", key); }, 900);
                }
                return renderChat();
            }
            if (msg.mine) return;
            play("message");
            var m = matchByKey(key) || { key: key, name: msg.name };
            toast((msg.name || m.name || "Alguien") + ": " + msg.body, {
                avatar: { thumb: m.thumb, scene: m.scene, name: msg.name || m.name },
                onClick: function () { setTab("messages"); openChat({ key: key, name: msg.name || m.name, thumb: m.thumb, scene: m.scene }); },
            });
            S.badge.unread = (S.badge.unread || 0) + 1;
            setBadge();
            if (S.tab === "messages") send("matches");
        },
        typing: function (key, on) {
            if (S.chat && S.chat.key === key) { S.chat.typing = !!on; renderChat(); }
        },
        read: function (key) {
            if (S.chat && S.chat.key === key) {
                S.chat.messages.forEach(function (m) { if (m.mine) m.read = true; });
                renderChat();
            }
        },
        unmatched: function (key) {
            if (S.chat && S.chat.key === key) {
                $("tn-chat").hidden = true;
                S.chat = null;
                toast("Esta conversación ya no está disponible.");
            }
            S.matches = S.matches.filter(function (m) { return m.key !== key; });
            if (S.tab === "messages") renderMatches(S.matches);
        },
        likes: function (data) { renderLikes(data || { list: [] }); },
        badge: function (b) { setBadge(b); },
    };

    window.RP = window.RP || {};
    RP.tinder = {
        on: function (name, args) {
            var fn = ON[name];
            if (fn) fn.apply(null, Array.isArray(args) ? args : [args]);
        },
    };

    // Llamado por app.js al cambiar de vista
    window.TinderApp = {
        onShow: function (name) {
            if (name !== "tinder") return;
            play("open");
            send("open");
            send("badge");
            setTab(S.tab);
        },
    };

    // Al abrir el telefono: globo de no leidos en el icono
    setTimeout(function () { send("badge"); }, 400);
})();
