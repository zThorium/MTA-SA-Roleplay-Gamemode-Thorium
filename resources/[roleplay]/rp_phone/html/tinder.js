/*
 * rp_phone / tinder.js  (parte 1: perfil)
 * Lua -> RP.tinder.setProfile(perfil)
 * JS  -> mta.triggerEvent("rp:phone:ui:tinderOpen" | "rp:phone:ui:tinderSave", ...)
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
})();
