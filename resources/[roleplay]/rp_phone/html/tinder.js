/*
 * rp_phone / tinder.js  (parte 1: perfil, parte 2: swipe, parte 3: matches)
 * Lua -> RP.tinder.setProfile(perfil)
 * JS  -> mta.triggerEvent("rp:phone:ui:tinderOpen" | "rp:phone:ui:tinderSave", ...)
 * Swipe: Lua -> RP.tinder.setCard(carta|{empty:true}|null) / RP.tinder.matched({name})
 *        JS  -> rp:phone:ui:tinderDeck(excluir[]) / rp:phone:ui:tinderSwipe(id, like)
 * La foto se toma con la camara del telefono (rp:phone:ui:capture); RP.setPhoto se
 * intercepta mientras se espera la foto de perfil.
 * La foto de perfil se toma con la camara o se elige de la galeria (gallery.js).
 */
(function () {
    "use strict";

    var $ = function (id) { return document.getElementById(id); };
    var st = { photo: null, interest: "a", draft: null, profile: null };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    function renderPhoto(base64) {
        var box = $("tinder-photo");
        box.innerHTML = "";
        if (!base64) { var s = document.createElement("span"); s.textContent = "Sin foto"; box.appendChild(s); return; }
        var img = document.createElement("img");
        img.src = "data:image/jpeg;base64," + base64;
        box.appendChild(img);
    }

    function setInterest(v) {
        st.interest = v;
        document.querySelectorAll("[data-interest]").forEach(function (b) { b.classList.toggle("active", b.dataset.interest === v); });
    }

    document.querySelectorAll("[data-interest]").forEach(function (b) {
        b.addEventListener("click", function () { setInterest(b.dataset.interest); });
    });

    // Al ir a la camara o a la galeria se guarda lo escrito: al volver, tinderOpen recarga el perfil del servidor
    function setPhoto(base64) {
        st.photo = base64;
        window.Phone.show("tinder");
        renderPhoto(base64);
    }
    function keepDraft() { st.draft = { bio: $("tinder-bio").value, interest: st.interest, active: $("tinder-active").checked }; }
    $("tinder-camera").addEventListener("click", function () {
        keepDraft();
        Gallery.takePhoto(setPhoto);
    });
    $("tinder-gallery").addEventListener("click", function () {
        keepDraft();
        Gallery.pick("Foto de perfil", setPhoto);
    });

    $("tinder-save").addEventListener("click", function () {
        send("rp:phone:ui:tinderSave", $("tinder-bio").value.trim(), st.interest, $("tinder-active").checked, st.photo || "");
        st.photo = null;   // si no se cambio, el servidor conserva la anterior
    });

    window.RP.tinder = {
        setProfile: function (p) {
            st.profile = p || {};
            $("tinder-data").textContent = (p.name || "") + (p.age ? ", " + p.age + " anos" : "") + " (datos de tu personaje)";
            $("tinder-bio").value = p.bio || "";
            $("tinder-active").checked = p.active !== false;
            setInterest(p.interested || "a");
            if (st.draft) {   // cambios sin guardar de antes de ir a la camara o galeria
                $("tinder-bio").value = st.draft.bio;
                $("tinder-active").checked = st.draft.active;
                setInterest(st.draft.interest);
                st.draft = null;
            }
            renderPhoto(st.photo || p.photo);
        }
    };

    // ---------------------------------------------------------------- Swipe
    var deck = { queue: [], seen: [], loading: false, empty: false, matchOpen: false };

    function requestCard() {
        if (deck.loading || deck.empty || deck.queue.length >= 2) return;
        deck.loading = true;
        send("rp:phone:ui:tinderDeck", deck.queue.map(function (c) { return c.id; }).concat(deck.seen.slice(-3)));
        setTimeout(function () { deck.loading = false; }, 4000);   // por si la respuesta se pierde
    }

    function renderCard() {
        var box = $("tinder-card"), msg = $("tinder-msg");
        box.innerHTML = "";
        var c = deck.queue[0];
        $("tinder-like").disabled = $("tinder-nope").disabled = !c;
        if (!c) {
            msg.textContent = deck.empty ? "No hay mas personas por ahora. Vuelve mas tarde." : "Buscando personas...";
            msg.hidden = false;
            return;
        }
        msg.hidden = true;
        var img = document.createElement("img");
        img.src = "data:image/jpeg;base64," + c.photo;
        box.appendChild(img);
        var info = document.createElement("div");
        info.className = "tinder-info";
        var h = document.createElement("strong");
        h.textContent = c.name + (c.age ? ", " + c.age : "");
        var p = document.createElement("span");
        p.textContent = c.bio || "";
        info.appendChild(h); info.appendChild(p);
        box.appendChild(info);
        box.className = "tinder-card";
    }

    function swipe(like) {
        var c = deck.queue.shift();
        if (!c || deck.matchOpen) return;
        deck.seen.push(c.id);
        send("rp:phone:ui:tinderSwipe", c.id, like);
        var box = $("tinder-card");
        box.classList.add(like ? "out-right" : "out-left");
        setTimeout(function () { renderCard(); requestCard(); }, 160);
    }

    $("tinder-like").addEventListener("click", function () { swipe(true); });
    $("tinder-nope").addEventListener("click", function () { swipe(false); });
    $("tinder-discover").addEventListener("click", function () {
        deck.queue = []; deck.empty = false; deck.loading = false;
        window.RP.show("tinder-swipe");
        renderCard();
        requestCard();
    });
    $("tinder-match-close").addEventListener("click", function () {
        deck.matchOpen = false;
        $("tinder-match").hidden = true;
    });

    window.RP.tinder.setCard = function (c) {
        deck.loading = false;
        if (c && c.empty) { deck.empty = true; }
        else if (c && c.id && c.photo) {
            if (!deck.queue.some(function (q) { return q.id === c.id; })) deck.queue.push(c);
        }
        if (!deck.queue.length || deck.queue.length === 1) renderCardIfIdle();
        requestCard();
    };

    function renderCardIfIdle() {
        var box = $("tinder-card");
        // Solo repinta si no hay tarjeta visible (primera carga o se acabo la cola)
        if (!box.firstChild || !deck.queue.length) renderCard();
    }

    window.RP.tinder.matched = function (m) {
        deck.matchOpen = true;
        $("tinder-match-text").textContent = "Tu y " + (m && m.name ? m.name : "esa persona") + " se gustaron mutuamente.";
        $("tinder-match").hidden = false;
    };

    // ---------------------------------------------------------------- Matches (parte 3)
    // Lua -> RP.tinder.setMatches([{id,name,age,bio,online}]|null) / setMatchPhoto(id, base64) / unmatched(id)
    // JS  -> rp:phone:ui:tinderMatches / tinderMatchPhoto(id) / tinderUnmatch(id)
    var matches = { list: [], photos: {}, pending: [] };

    function nextMatchPhoto() {
        var id = matches.pending.shift();
        if (id) send("rp:phone:ui:tinderMatchPhoto", id);
    }

    function renderMatches() {
        var box = $("tinder-matches-list"), msg = $("tinder-matches-msg");
        box.innerHTML = "";
        msg.hidden = matches.list.length > 0;
        msg.textContent = "Aun no tienes matches. Sigue descubriendo personas.";
        matches.list.forEach(function (m) {
            var row = document.createElement("div"); row.className = "tinder-match-row";
            var av = document.createElement("div"); av.className = "tinder-match-avatar"; av.dataset.id = m.id;
            if (matches.photos[m.id]) { var img = document.createElement("img"); img.src = "data:image/jpeg;base64," + matches.photos[m.id]; av.appendChild(img); }
            var tx = document.createElement("div"); tx.className = "tinder-match-text";
            var h = document.createElement("strong"); h.textContent = m.name + (m.age ? ", " + m.age : "");
            if (m.online) { var d = document.createElement("i"); d.className = "dot"; h.appendChild(d); }
            var b = document.createElement("span"); b.textContent = m.bio || "";
            tx.appendChild(h); tx.appendChild(b);
            var x = document.createElement("button"); x.type = "button"; x.title = "Deshacer match"; x.textContent = "\u2715";
            x.addEventListener("click", function () {
                if (window.confirm("¿Deshacer el match con " + m.name + "?")) send("rp:phone:ui:tinderUnmatch", m.id);
            });
            row.appendChild(av); row.appendChild(tx); row.appendChild(x);
            box.appendChild(row);
        });
    }

    $("tinder-matches-btn").addEventListener("click", function () {
        window.RP.show("tinder-matches");
        $("tinder-matches-msg").hidden = false;
        $("tinder-matches-msg").textContent = "Cargando...";
        send("rp:phone:ui:tinderMatches");
    });

    window.RP.tinder.setMatches = function (list) {
        if (!list) { $("tinder-matches-msg").hidden = false; $("tinder-matches-msg").textContent = "No se pudieron cargar tus matches."; return; }
        matches.list = list;
        matches.pending = list.filter(function (m) { return !matches.photos[m.id]; }).map(function (m) { return m.id; });
        renderMatches();
        nextMatchPhoto();
    };
    window.RP.tinder.setMatchPhoto = function (id, base64) {
        matches.photos[id] = base64;
        var av = document.querySelector('.tinder-match-avatar[data-id="' + id + '"]');
        if (av && !av.firstChild) { var img = document.createElement("img"); img.src = "data:image/jpeg;base64," + base64; av.appendChild(img); }
        nextMatchPhoto();
    };
    window.RP.tinder.unmatched = function (id) {
        matches.list = matches.list.filter(function (m) { return m.id !== id; });
        delete matches.photos[id];
        renderMatches();
    };
})();
