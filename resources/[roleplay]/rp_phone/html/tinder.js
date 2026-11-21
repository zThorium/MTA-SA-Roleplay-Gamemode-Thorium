/*
 * rp_phone / tinder.js  (parte 1: perfil)
 * Lua -> RP.tinder.setProfile(perfil)
 * JS  -> mta.triggerEvent("rp:phone:ui:tinderOpen" | "rp:phone:ui:tinderSave", ...)
 * La foto se toma con la camara del telefono (rp:phone:ui:capture); RP.setPhoto se
 * intercepta mientras se espera la foto de perfil.
 */
(function () {
    "use strict";

    var $ = function (id) { return document.getElementById(id); };
    var st = { photo: null, interest: "a", waitingPhoto: false, profile: null };

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

    $("tinder-camera").addEventListener("click", function () {
        st.waitingPhoto = true;
        send("rp:phone:ui:capture");
    });

    $("tinder-save").addEventListener("click", function () {
        send("rp:phone:ui:tinderSave", $("tinder-bio").value.trim(), st.interest, $("tinder-active").checked, st.photo || "");
        st.photo = null;   // si no se cambio, el servidor conserva la anterior
    });

    // Intercepta la foto de la camara cuando es para el perfil
    var originalSetPhoto = window.RP.setPhoto;
    window.RP.setPhoto = function (base64) {
        if (!st.waitingPhoto) return originalSetPhoto(base64);
        st.waitingPhoto = false;
        st.photo = base64;
        renderPhoto(base64);
        window.RP.show("tinder");
    };

    window.RP.tinder = {
        setProfile: function (p) {
            st.profile = p || {};
            $("tinder-data").textContent = (p.name || "") + (p.age ? ", " + p.age + " anos" : "") + " (datos de tu personaje)";
            $("tinder-bio").value = p.bio || "";
            $("tinder-active").checked = p.active !== false;
            setInterest(p.interested || "a");
            if (!st.photo) renderPhoto(p.photo);
        }
    };
})();
