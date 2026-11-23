/*
 * rp_phone / gallery.js
 * App Camara (abre la camara de Fotogram y la foto va a la galeria) y app Galeria.
 * Toda foto tomada, venga de donde venga, se guarda en la galeria (Gallery.onShot).
 * JS  -> mta.triggerEvent("rp:phone:ui:gallery", accion, dato)
 * Lua -> RP.gallery.list / saved / image / deleted (client/c_gallery.lua)
 * Otras apps: Gallery.pick(titulo, cb) para elegir una foto, Gallery.takePhoto(cb) para tomar una nueva.
 */
(function () {
    "use strict";

    var P = window.Phone;
    var $ = P.$, el = P.el, send = P.send;
    var st = { after: null, picker: null, pickerTitle: "", list: [], current: 0, queue: [], loading: 0 };
    var cache = {};   // id -> base64

    function gallery(action, arg) { send("rp:phone:ui:gallery", action, arg); }

    function fmtDate(ts) {
        var d = new Date(ts * 1000);
        return d.getDate() + "/" + (d.getMonth() + 1) + "/" + d.getFullYear() + " " +
            String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
    }

    function dataUrl(b64) { return "data:image/jpeg;base64," + b64; }

    // ---------------------------------------------------------------- Cuadricula
    // Las fotos se piden de a una: la siguiente solo cuando llega la anterior
    function pump() {
        if (st.loading || !st.queue.length) return;
        st.loading = st.queue.shift();
        gallery("get", st.loading);
        // Si el servidor ignora la peticion (limite de ritmo), no se queda trabado
        var asked = st.loading;
        setTimeout(function () { if (st.loading === asked) { st.loading = 0; pump(); } }, 8000);
    }

    function fill(id, b64) {
        document.querySelectorAll('[data-photo="' + id + '"]').forEach(function (img) { img.src = dataUrl(b64); img.classList.add("loaded"); });
    }

    function request(id) {
        if (cache[id]) return fill(id, cache[id]);
        if (st.queue.indexOf(id) < 0 && st.loading !== id) st.queue.push(id);
        pump();
    }

    function render() {
        var grid = $("gallery-grid");
        grid.innerHTML = "";
        $("gallery-empty").hidden = st.list.length > 0;
        st.list.forEach(function (ph) {
            var cell = el("button", "gallery-cell");
            cell.type = "button";
            var img = el("img");
            img.dataset.photo = ph.id;
            img.alt = "";
            cell.appendChild(img);
            cell.addEventListener("click", function () {
                if (!st.picker) return openPhoto(ph);
                if (!cache[ph.id]) return;   // aun no cargo
                var cb = st.picker;
                st.picker = null;
                cb(cache[ph.id]);
            });
            grid.appendChild(cell);
            request(ph.id);
        });
    }

    function openPhoto(ph) {
        st.current = ph.id;
        $("gallery-photo-date").textContent = fmtDate(ph.ts);
        var img = $("gallery-photo");
        img.removeAttribute("src");
        img.classList.remove("loaded");
        img.dataset.photo = ph.id;
        P.show("gallery-photo");
        request(ph.id);
    }

    // ---------------------------------------------------------------- Botones
    function takeToGallery() { Gallery.takePhoto(function () { P.show("gallery"); }); }
    $("app-camera").addEventListener("click", takeToGallery);
    $("gallery-new").addEventListener("click", takeToGallery);
    $("gallery-delete").addEventListener("click", function () {
        if (st.current) gallery("delete", st.current);
    });

    // ---------------------------------------------------------------- API
    window.Gallery = {
        cache: cache,
        onShow: function (name) {
            if (name === "gallery") {
                $("gallery-title").textContent = st.picker ? st.pickerTitle : "Galeria";
                gallery("list");
            } else if (name !== "gallery-photo") st.picker = null;   // se salio sin elegir
        },
        // Abre la camara; al disparar se llama cb(base64) en vez de ir al editor de Fotogram
        takePhoto: function (cb) {
            st.after = cb;
            send("rp:phone:ui:camera", "open", "rear");
        },
        // Muestra la galeria para elegir una foto: cb(base64)
        pick: function (title, cb) {
            st.picker = cb;
            st.pickerTitle = title;
            P.show("gallery");
        },
        // Camara cerrada sin disparar
        cancel: function () { st.after = null; },
        // Guarda la foto; devuelve quien la pidio (o null si es de Fotogram)
        onShot: function (b64) {
            gallery("save", b64);
            var cb = st.after;
            st.after = null;
            return cb;
        }
    };

    window.RP = window.RP || {};
    RP.gallery = {
        list: function (rows) {
            st.list = (rows || []).map(function (r) { return { id: Number(r.id), ts: Number(r.ts) }; });
            // Descarta ids que ya no existen
            Object.keys(cache).forEach(function (k) { if (!st.list.some(function (p) { return p.id === Number(k); })) delete cache[k]; });
            if ($("view-gallery").classList.contains("active")) render();
        },
        saved: function () {
            if ($("view-gallery").classList.contains("active")) gallery("list");
        },
        image: function (id, b64) {
            id = Number(id);
            cache[id] = b64;
            fill(id, b64);
            if (st.loading === id) { st.loading = 0; pump(); }
        },
        deleted: function (id) {
            id = Number(id);
            delete cache[id];
            st.list = st.list.filter(function (p) { return p.id !== id; });
            if (st.current === id) { st.current = 0; P.show("gallery"); }
            else render();
        }
    };
})();
