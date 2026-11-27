/*
 * rp_login / app.js
 * Logica de la interfaz. Se comunica con Lua mediante mta.triggerEvent
 * (todos los argumentos llegan a Lua como texto) y recibe respuestas a
 * traves de window.RP (llamado por executeBrowserJavascript).
 */
(function () {
    "use strict";

    var USERNAME_RE = /^[A-Za-z][A-Za-z0-9_]{2,23}$/;
    var forms = {
        login: document.getElementById("form-login"),
        register: document.getElementById("form-register")
    };
    var panel = document.getElementById("panel");

    // ---------------------------------------------------------- Sonidos
    var SOUNDS = {};
    ["click_002", "select_002", "error_004", "confirmation_003", "maximize_003", "toggle_002", "rollover2"].forEach(function (n) {
        SOUNDS[n] = new Audio("sounds/" + n + ".ogg");
    });
    function sfx(name, volume) {
        var a = SOUNDS[name];
        if (!a) return;
        a = a.cloneNode();
        a.volume = volume === undefined ? 0.6 : volume;
        a.play().catch(function () {});
    }

    function send(eventName, a, b, c) {
        if (window.mta && typeof mta.triggerEvent === "function") {
            mta.triggerEvent(eventName, a, b, c);
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
        btn.classList.toggle("busy", busy);
    }

    function fail(form, text, input) {
        setMessage(form, text, "error");
        sfx("error_004");
        panel.classList.remove("shake");
        void panel.offsetWidth;   // reinicia la animacion
        panel.classList.add("shake");
        if (input) {
            input.classList.add("invalid");
            input.focus();
        }
    }

    function switchTab(name) {
        document.querySelector(".tabs").classList.toggle("register", name === "register");
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
        tab.addEventListener("click", function () {
            if (tab.classList.contains("active")) return;
            sfx("select_002");
            switchTab(tab.dataset.tab);
        });
    });

    // Sonido suave al pasar por botones; onda al pulsar
    document.querySelectorAll("button, .remember").forEach(function (b) {
        b.addEventListener("mouseenter", function () { sfx("rollover2", 0.25); });
    });
    document.querySelectorAll(".primary").forEach(function (b) {
        b.addEventListener("mousedown", function (e) {
            var r = b.getBoundingClientRect();
            var dot = document.createElement("span");
            dot.className = "ripple";
            dot.style.left = (e.clientX - r.left) + "px";
            dot.style.top = (e.clientY - r.top) + "px";
            b.appendChild(dot);
            setTimeout(function () { dot.remove(); }, 650);
        });
    });

    document.querySelectorAll("input").forEach(function (input) {
        input.addEventListener("input", function () { input.classList.remove("invalid"); });
    });
    forms.login.remember.addEventListener("change", function () { sfx("toggle_002", 0.5); });

    document.querySelectorAll(".reveal").forEach(function (b) {
        b.addEventListener("click", function () {
            var input = b.parentNode.querySelector("input");
            var show = input.type === "password";
            input.type = show ? "text" : "password";
            b.classList.toggle("on", show);
            sfx("click_002", 0.4);
        });
    });

    // Barra de fuerza de la contrasena (orientativa)
    forms.register.password.addEventListener("input", function () {
        var p = this.value, score = 0;
        if (p.length >= 6) score++;
        if (p.length >= 10) score++;
        if (/[A-Z]/.test(p) && /[a-z]/.test(p)) score++;
        if (/\d/.test(p) && /[^A-Za-z0-9]/.test(p)) score++;
        var bar = forms.register.querySelector(".strength i");
        bar.style.width = (p.length ? Math.max(12, score * 25) : 0) + "%";
        bar.style.background = ["#ff6b6b", "#ff6b6b", "#f5a524", "#c8d84c", "#4cd38a"][score];
    });

    forms.login.addEventListener("submit", function (e) {
        e.preventDefault();
        var user = this.username.value.trim();
        var pass = this.password.value;
        if (!user) return fail("login", "Escribe tu usuario.", this.username);
        if (!pass) return fail("login", "Escribe tu contraseña.", this.password);
        sfx("click_002");
        setMessage("login", "");
        setBusy("login", true);
        send("rp:ui:login", user, pass, this.remember.checked ? "true" : "false");
    });

    forms.register.addEventListener("submit", function (e) {
        e.preventDefault();
        var user = this.username.value.trim();
        var pass = this.password.value;
        if (!USERNAME_RE.test(user)) {
            return fail("register", "Usuario no válido: 3-24 caracteres, letras, números o _, empezando por letra.", this.username);
        }
        if (pass.length < 6 || pass.length > 64) {
            return fail("register", "La contraseña debe tener entre 6 y 64 caracteres.", this.password);
        }
        if (pass !== this.confirm.value) {
            return fail("register", "Las contraseñas no coinciden.", this.confirm);
        }
        sfx("click_002");
        setMessage("register", "");
        setBusy("register", true);
        send("rp:ui:register", user, pass);
    });

    // ---------------------------------------------------------- Musica
    var musicBtn = document.getElementById("music");
    musicBtn.addEventListener("click", function () {
        sfx("toggle_002", 0.5);
        send("rp:ui:music");
    });

    // ---------------------------------------------------------- API llamada desde Lua
    window.RP = {
        // Credenciales guardadas: rellena el formulario de login
        setSaved: function (user, pass) {
            forms.login.username.value = user;
            forms.login.password.value = pass;
            forms.login.remember.checked = true;
            forms.login.querySelector("button[type=submit]").focus();
        },
        setMusic: function (on) {
            musicBtn.classList.toggle("off", !on);
            musicBtn.querySelector("small").textContent = "XNOVA · clic para " + (on ? "silenciar" : "activar");
        },
        // Nombre del lugar que muestra el plano actual de la camara
        setLocation: function (name) {
            var box = document.getElementById("location");
            box.querySelector(".loc-name").textContent = name;
            box.classList.remove("show");
            void box.offsetWidth;
            box.classList.add("show");
        },
        onResult: function (ok, message, form) {
            form = forms[form] ? form : "login";
            setBusy(form, false);
            if (ok) {
                setMessage(form, message, "success");
                sfx("confirmation_003");
                return;
            }
            var pass = forms[form].password;
            pass.value = "";
            fail(form, message, pass);
        },
        onSuccess: function (username) {
            ["login", "register"].forEach(function (f) {
                setBusy(f, false);
                setMessage(f, "¡Bienvenido, " + username + "!", "success");
            });
            sfx("confirmation_003", 0.7);
            document.getElementById("flash").classList.add("on");
            panel.classList.add("leaving");
        }
    };

    sfx("maximize_003", 0.45);
})();
