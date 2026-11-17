/*
 * rp_login / app.js
 * Logica de la interfaz. Se comunica con Lua mediante mta.triggerEvent
 * y recibe respuestas a traves de window.RP (llamado por executeBrowserJavascript).
 */
(function () {
    "use strict";

    var USERNAME_RE = /^[A-Za-z][A-Za-z0-9_]{2,23}$/;
    var forms = {
        login: document.getElementById("form-login"),
        register: document.getElementById("form-register")
    };

    function send(eventName, a, b) {
        if (window.mta && typeof mta.triggerEvent === "function") {
            mta.triggerEvent(eventName, a, b);
        } else {
            // Fuera del juego (vista previa en un navegador normal)
            console.log("[mta]", eventName, a);
        }
    }

    function setMessage(form, text, type) {
        var el = forms[form].querySelector(".message");
        el.textContent = text || "";
        el.className = "message" + (type ? " " + type : "");
    }

    function setBusy(form, busy) {
        var btn = forms[form].querySelector("button[type=submit]");
        btn.disabled = busy;
        btn.dataset.label = btn.dataset.label || btn.textContent;
        btn.textContent = busy ? "Procesando..." : btn.dataset.label;
    }

    function switchTab(name) {
        document.querySelectorAll(".tab").forEach(function (t) {
            t.classList.toggle("active", t.dataset.tab === name);
        });
        Object.keys(forms).forEach(function (key) {
            forms[key].classList.toggle("active", key === name);
        });
        setMessage(name, "");
        forms[name].querySelector("input").focus();
    }

    document.querySelectorAll(".tab").forEach(function (tab) {
        tab.addEventListener("click", function () { switchTab(tab.dataset.tab); });
    });

    forms.login.addEventListener("submit", function (e) {
        e.preventDefault();
        var user = this.username.value.trim();
        var pass = this.password.value;
        if (!user || !pass) {
            return setMessage("login", "Completa usuario y contrasena.", "error");
        }
        setMessage("login", "");
        setBusy("login", true);
        send("rp:ui:login", user, pass);
    });

    forms.register.addEventListener("submit", function (e) {
        e.preventDefault();
        var user = this.username.value.trim();
        var pass = this.password.value;
        if (!USERNAME_RE.test(user)) {
            return setMessage("register", "Usuario no valido: 3-24 caracteres, letras, numeros o _, empezando por letra.", "error");
        }
        if (pass.length < 6 || pass.length > 64) {
            return setMessage("register", "La contrasena debe tener entre 6 y 64 caracteres.", "error");
        }
        if (pass !== this.confirm.value) {
            return setMessage("register", "Las contrasenas no coinciden.", "error");
        }
        setMessage("register", "");
        setBusy("register", true);
        send("rp:ui:register", user, pass);
    });

    // API llamada desde Lua
    window.RP = {
        onResult: function (ok, message, form) {
            form = forms[form] ? form : "login";
            setBusy(form, false);
            setMessage(form, message, ok ? "success" : "error");
            if (!ok) {
                var pass = forms[form].password;
                pass.value = "";
                pass.focus();
            }
        },
        onSuccess: function (username) {
            ["login", "register"].forEach(function (f) { setMessage(f, "Bienvenido, " + username + "!", "success"); });
            document.getElementById("panel").classList.add("leaving");
        }
    };
})();
