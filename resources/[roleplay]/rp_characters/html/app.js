/*
 * rp_characters / app.js
 * Seleccion y creacion de personajes. Lua llama a window.RP.*; la interfaz
 * responde con mta.triggerEvent("rp:chars:ui:*", ...).
 *
 * Apariencia:
 *  - Hombre: raza + cabeza (rp_heads) + ropa de CJ (torso, piernas, zapatos)
 *    + complexion (grasa/musculo) y color de piel
 *  - Mujer: skin
 *  - Ambos: altura (se ve en la vista previa)
 */
(function () {
    "use strict";

    var LIMITS = { storyMin: 30, storyMax: 2000 };
    var BODY_DEFAULT = { height: 175, fat: 15, muscle: 15, tone: 2 };
    var NAME_RE = /^[A-Z][a-z]{1,14}$/;

    var state = {
        characters: [],
        maxSlots: 3,
        selectedId: null,
        busy: false,
        data: {
            male: [26], female: [12],
            races: ["Blanco", "Negro", "Latino", "Asiatico"],
            heads: { "1": [2], "2": [6], "3": [28], "4": [1] },
            clothes: { torso: 1, legs: 1, shoes: 1 },
            tones: [{ name: "Claro", hex: "#d7a582" }],
            toneByRace: { "1": 1 },
            body: { heightMin: 155, heightMax: 200, heightBase: 175, fatMax: 100, muscleMax: 100 }
        },
        body: Object.assign({}, BODY_DEFAULT),
        gender: 0,
        race: 1,
        index: { head: 0, torso: 0, legs: 0, shoes: 0, skin: 0 },
        camera: "body"
    };

    var $ = function (id) { return document.getElementById(id); };
    var form = $("form-create");

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") {
            mta.triggerEvent.apply(mta, args);
        } else {
            console.log("[mta]", args);   // vista previa fuera del juego
        }
    }

    // ---------------------------------------------------------- Sonidos
    var SOUNDS = {};
    ["click_002", "select_002", "error_004", "confirmation_003", "maximize_003", "minimize_003",
     "back_002", "toggle_002", "drop_002", "rollover2"].forEach(function (n) {
        SOUNDS[n] = new Audio("sounds/" + n + ".ogg");
    });
    function sfx(name, volume) {
        var a = SOUNDS[name];
        if (!a) return;
        a = a.cloneNode();
        a.volume = volume === undefined ? 0.6 : volume;
        a.play().catch(function () {});
    }

    // Sonido suave al pasar por botones y tarjetas (una vez por entrada)
    document.addEventListener("mouseover", function (e) {
        var target = e.target.closest && e.target.closest("button, .slot");
        if (target && !target.contains(e.relatedTarget)) sfx("rollover2", 0.2);
    });

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined) node.textContent = text;
        return node;
    }

    function setMessage(id, text, type) {
        var node = $(id);
        node.textContent = text || "";
        node.className = "message" + (type ? " " + type : "");
    }

    function setBusy(busy) {
        state.busy = busy;
        $("btn-create").disabled = busy;
        $("btn-create").textContent = busy ? "Creando..." : "Crear personaje";
        document.querySelectorAll(".slot-actions button").forEach(function (b) { b.disabled = busy; });
    }

    function showView(name) {
        document.querySelectorAll(".view").forEach(function (v) {
            v.classList.toggle("active", v.id === "view-" + name);
        });
        document.body.classList.toggle("creating", name === "create");
    }

    function setCamera(mode) {
        if (state.camera === mode) return;
        state.camera = mode;
        $("btn-zoom").textContent = mode === "face" ? "Ver cuerpo" : "Ver rostro";
        send("rp:chars:ui:camera", mode);
    }

    function displayName(name) { return String(name).replace(/_/g, " "); }

    function wrap(i, n) { return n > 0 ? ((i % n) + n) % n : 0; }

    // ---------------------------------------------------------- Vista previa
    function previewCharacter(c) {
        if (c.head) {
            send("rp:chars:ui:look", JSON.stringify({
                head: c.head, torso: c.clothes_torso || 0, legs: c.clothes_legs || 0, shoes: c.clothes_shoes || 0,
                fat: c.body_fat || 0, muscle: c.body_muscle || 0, height: c.height, tone: c.skin_tone || 0
            }));
        } else {
            send("rp:chars:ui:look", JSON.stringify({ skin: c.skin, height: c.height }));
        }
    }

    function currentLook() {
        if (state.gender === 0) {
            var heads = state.data.heads[String(state.race)] || [];
            return {
                race: state.race,
                head: heads[wrap(state.index.head, heads.length)],
                torso: wrap(state.index.torso, state.data.clothes.torso),
                legs: wrap(state.index.legs, state.data.clothes.legs),
                shoes: wrap(state.index.shoes, state.data.clothes.shoes),
                fat: state.body.fat,
                muscle: state.body.muscle,
                height: state.body.height,
                tone: state.body.tone
            };
        }
        var skins = state.data.female;
        return { skin: skins[wrap(state.index.skin, skins.length)], height: state.body.height };
    }

    function sendLook() {
        send("rp:chars:ui:look", JSON.stringify(currentLook()));
    }

    // Los sliders disparan muchos eventos: como mucho una vista previa cada 90 ms
    var lookTimer = null, lookPending = false;
    function sendLookSoon() {
        if (lookTimer) { lookPending = true; return; }
        sendLook();
        lookTimer = setTimeout(function () {
            lookTimer = null;
            if (lookPending) { lookPending = false; sendLookSoon(); }
        }, 90);
    }

    // ---------------------------------------------------------- Seleccion
    function renderSlots() {
        var container = $("slots");
        container.innerHTML = "";

        state.characters.forEach(function (c) {
            var card = el("div", "slot" + (c.id === state.selectedId ? " selected" : ""));
            card.appendChild(el("div", "slot-name", displayName(c.name)));

            var meta = el("div", "slot-meta");
            meta.appendChild(document.createTextNode(c.age + " anos · " + (c.gender == 1 ? "Mujer" : "Hombre") + " · "));
            meta.appendChild(el("span", "slot-money", "$" + Number(c.money).toLocaleString("es")));
            card.appendChild(meta);
            card.appendChild(el("div", "slot-meta", c.last_played ? "Ultima vez: " + c.last_played : "Nunca jugado"));

            var actions = el("div", "slot-actions");
            var play = el("button", "primary", "Jugar");
            play.type = "button";
            play.addEventListener("click", function (e) {
                e.stopPropagation();
                if (state.busy) return;
                sfx("confirmation_003", 0.7);
                setBusy(true);
                setMessage("select-message", "Entrando...", "success");
                document.body.classList.add("leaving");
                send("rp:chars:ui:play", c.id);
            });
            var del = el("button", "danger ghost", "Eliminar");
            del.type = "button";
            del.addEventListener("click", function (e) { e.stopPropagation(); sfx("minimize_003", 0.5); openDelete(c); });
            actions.appendChild(play);
            actions.appendChild(del);
            card.appendChild(actions);

            card.addEventListener("click", function () { selectCharacter(c); });
            container.appendChild(card);
        });

        for (var i = state.characters.length; i < state.maxSlots; i++) {
            var empty = el("div", "slot empty");
            empty.appendChild(el("span", "plus", "+"));
            empty.appendChild(el("span", null, "Crear personaje"));
            empty.addEventListener("click", function () { sfx("maximize_003"); openCreate(); });
            container.appendChild(empty);
        }

        var free = state.maxSlots - state.characters.length;
        $("slots-info").textContent = free > 0
            ? "Tienes " + free + " de " + state.maxSlots + " espacios libres"
            : "Todos tus espacios estan ocupados";
    }

    function selectCharacter(c) {
        if (state.selectedId !== c.id) sfx("select_002");
        state.selectedId = c.id;
        previewCharacter(c);
        renderSlots();
    }

    // ---------------------------------------------------------- Borrado
    var deleting = null;

    function openDelete(c) {
        deleting = c;
        $("delete-name").textContent = displayName(c.name);
        $("delete-input").value = "";
        $("delete-confirm").disabled = true;
        $("modal-delete").hidden = false;
        $("delete-input").focus();
    }

    function closeDelete() {
        deleting = null;
        $("modal-delete").hidden = true;
    }

    $("delete-input").addEventListener("input", function () {
        $("delete-confirm").disabled = !deleting || this.value.trim() !== displayName(deleting.name);
    });
    $("delete-cancel").addEventListener("click", function () { sfx("back_002", 0.5); closeDelete(); });
    $("delete-confirm").addEventListener("click", function () {
        if (!deleting) return;
        sfx("drop_002");
        setBusy(true);
        send("rp:chars:ui:delete", deleting.id);
        closeDelete();
    });

    // ---------------------------------------------------------- Apariencia
    function selectorRows() {
        if (state.gender === 1) {
            return [{ key: "skin", name: "Skin", total: state.data.female.length }];
        }
        var heads = state.data.heads[String(state.race)] || [];
        return [
            { key: "head", name: "Cabeza", total: heads.length, camera: "face" },
            { key: "torso", name: "Torso", total: state.data.clothes.torso, camera: "body" },
            { key: "legs", name: "Piernas", total: state.data.clothes.legs, camera: "body" },
            { key: "shoes", name: "Zapatos", total: state.data.clothes.shoes, camera: "body" }
        ];
    }

    function renderAppearance() {
        // Raza (solo hombres)
        $("race-field").hidden = state.gender !== 0;
        var raceBox = $("race");
        raceBox.innerHTML = "";
        state.data.races.forEach(function (name, i) {
            var race = i + 1;
            var b = el("button", race === state.race ? "active" : "", name);
            b.type = "button";
            b.addEventListener("click", function () {
                sfx("select_002", 0.5);
                state.race = race;
                state.index.head = 0;
                var tone = state.data.toneByRace[String(race)];
                if (tone) state.body.tone = tone;
                renderBody();
                setCamera("face");
                renderAppearance();
                sendLook();
            });
            raceBox.appendChild(b);
        });

        // Selectores
        var box = $("selectors");
        box.innerHTML = "";
        selectorRows().forEach(function (row) {
            var line = el("div", "selector");
            var value = el("span", "value", (wrap(state.index[row.key], row.total) + 1) + " / " + row.total);
            var prev = el("button", null, "◀");
            var next = el("button", null, "▶");
            prev.type = next.type = "button";

            function step(delta) {
                state.index[row.key] = wrap(state.index[row.key] + delta, row.total);
                value.textContent = (state.index[row.key] + 1) + " / " + row.total;
                sfx("click_002", 0.45);
                value.classList.remove("bump");
                void value.offsetWidth;   // reinicia la animacion
                value.classList.add("bump");
                if (row.camera) setCamera(row.camera);
                sendLook();
            }
            prev.addEventListener("click", function () { step(-1); });
            next.addEventListener("click", function () { step(1); });

            line.appendChild(el("span", "name", row.name));
            line.appendChild(prev);
            line.appendChild(value);
            line.appendChild(next);
            box.appendChild(line);
        });
    }

    function setGender(g) {
        state.gender = g;
        document.querySelectorAll("#gender button").forEach(function (b) {
            b.classList.toggle("active", Number(b.dataset.gender) === g);
        });
        renderAppearance();
        renderBody();
        sendLook();
    }

    // ---------------------------------------------------------- Cuerpo
    // Mismo calculo que estimateWeight() en shared/s_body.lua (el servidor guarda el suyo)
    function estimateWeight(height, fat, muscle) {
        var m = height / 100;
        return Math.round((19.5 + fat * 0.14 + muscle * 0.05) * m * m);
    }

    function fatLabel(v) {
        return v <= 12 ? "Delgado" : v <= 40 ? "Normal" : v <= 70 ? "Robusto" : "Obeso";
    }

    function muscleLabel(v) {
        return v <= 20 ? "Poca" : v <= 50 ? "Tonificado" : v <= 80 ? "Atletico" : "Musculoso";
    }

    var sliders = {
        height: $("body-height"),
        fat: $("body-fat"),
        muscle: $("body-muscle")
    };

    function renderBody() {
        var male = state.gender === 0;
        var b = state.body;
        var limits = state.data.body;

        sliders.height.min = limits.heightMin;
        sliders.height.max = limits.heightMax;
        sliders.fat.max = limits.fatMax;
        sliders.muscle.max = limits.muscleMax;
        sliders.height.value = b.height;
        sliders.fat.value = b.fat;
        sliders.muscle.value = b.muscle;

        $("height-value").textContent = b.height + " cm";
        $("fat-value").textContent = fatLabel(b.fat);
        $("muscle-value").textContent = muscleLabel(b.muscle);
        $("weight-value").textContent = "≈ " + estimateWeight(b.height, male ? b.fat : 15, male ? b.muscle : 15) + " kg";

        $("cj-body").hidden = !male;
        $("body-note").hidden = male;

        var box = $("tones");
        box.innerHTML = "";
        state.data.tones.forEach(function (tone, i) {
            var index = i + 1;
            var b2 = el("button", index === b.tone ? "active" : "");
            b2.type = "button";
            b2.title = tone.name;
            b2.style.background = tone.hex;
            b2.addEventListener("click", function () {
                sfx("toggle_002", 0.5);
                state.body.tone = index;
                setCamera("body");
                renderBody();
                sendLook();
            });
            box.appendChild(b2);
        });
        var current = state.data.tones[b.tone - 1];
        $("tone-name").textContent = current ? current.name : "";
    }

    Object.keys(sliders).forEach(function (key) {
        sliders[key].addEventListener("input", function () {
            state.body[key] = Number(this.value);
            setCamera("body");
            renderBody();
            sendLookSoon();
        });
        sliders[key].addEventListener("change", sendLook);
    });

    // ---------------------------------------------------------- Creacion
    function openCreate() {
        form.reset();
        form.querySelectorAll(".invalid").forEach(function (n) { n.classList.remove("invalid"); });
        state.race = 1;
        state.index = { head: 0, torso: 0, legs: 0, shoes: 0, skin: 0 };
        state.body = Object.assign({}, BODY_DEFAULT, { tone: state.data.toneByRace["1"] || BODY_DEFAULT.tone });
        updateStoryCount();
        setMessage("create-message", "");
        showView("create");
        setGender(0);
        form.firstName.focus();
    }

    function capitalize(value) {
        value = value.trim().toLowerCase();
        return value.charAt(0).toUpperCase() + value.slice(1);
    }

    function updateStoryCount() {
        var len = form.story.value.trim().length;
        var counter = $("story-count");
        counter.textContent = len < LIMITS.storyMin
            ? len + " / " + LIMITS.storyMax + " · faltan " + (LIMITS.storyMin - len) + " para el minimo (" + LIMITS.storyMin + ")"
            : len + " / " + LIMITS.storyMax;
        counter.className = len >= LIMITS.storyMin ? "ok" : "";
    }

    function readNumber(input, min, max) {
        var n = Number(input.value);
        return Number.isInteger(n) && n >= min && n <= max ? n : null;
    }

    function fail(input, message) {
        input.classList.add("invalid");
        input.focus();
        setMessage("create-message", message, "error");
        sfx("error_004");
        send("rp:chars:ui:notify", message, "error");
        return null;
    }

    function collect() {
        form.querySelectorAll(".invalid").forEach(function (n) { n.classList.remove("invalid"); });

        form.firstName.value = capitalize(form.firstName.value);
        form.lastName.value = capitalize(form.lastName.value);

        if (!NAME_RE.test(form.firstName.value)) return fail(form.firstName, "El nombre debe tener 2-15 letras, sin espacios ni tildes.");
        if (!NAME_RE.test(form.lastName.value)) return fail(form.lastName, "El apellido debe tener 2-15 letras, sin espacios ni tildes.");

        var age = readNumber(form.age, 16, 90);
        if (age === null) return fail(form.age, "La edad debe estar entre 16 y 90 anos.");

        var origin = form.origin.value.trim();
        if (origin.length < 3) return fail(form.origin, "Indica el lugar de origen de tu personaje.");

        var story = form.story.value.trim();
        if (story.length < LIMITS.storyMin) {
            return fail(form.story, "La historia debe tener al menos " + LIMITS.storyMin + " caracteres (llevas " + story.length + "). Basta con una o dos frases.");
        }

        var data = {
            firstName: form.firstName.value,
            lastName: form.lastName.value,
            gender: state.gender,
            age: age,
            origin: origin,
            story: story
        };
        var look = currentLook();
        Object.keys(look).forEach(function (k) { data[k] = look[k]; });
        return data;
    }

    form.addEventListener("submit", function (e) {
        e.preventDefault();
        if (state.busy) return;
        var data = collect();
        if (!data) return;
        sfx("click_002");
        setMessage("create-message", "");
        setBusy(true);
        send("rp:chars:ui:create", JSON.stringify(data));
    });

    form.story.addEventListener("input", updateStoryCount);
    $("btn-back").addEventListener("click", function () { sfx("back_002"); RP.showSelect(state.characters, state.maxSlots); });
    $("btn-zoom").addEventListener("click", function () { sfx("click_002", 0.5); setCamera(state.camera === "face" ? "body" : "face"); });
    document.querySelectorAll("#gender button").forEach(function (b) {
        b.addEventListener("click", function () { sfx("select_002", 0.5); setGender(Number(b.dataset.gender)); });
    });

    // ---------------------------------------------------------- Musica (la del login)
    var musicBtn = $("music");
    musicBtn.addEventListener("click", function () {
        sfx("toggle_002", 0.5);
        send("rp:chars:ui:music");
    });

    // ---------------------------------------------------------- Girar al personaje
    var dragging = false, lastX = 0;
    $("stage").addEventListener("mousedown", function (e) {
        dragging = true;
        lastX = e.clientX;
    });
    window.addEventListener("mouseup", function () { dragging = false; });
    window.addEventListener("mousemove", function (e) {
        if (!dragging) return;
        var dx = e.clientX - lastX;
        lastX = e.clientX;
        if (dx !== 0) send("rp:chars:ui:rotate", dx * 0.6);
    });

    // ---------------------------------------------------------- API para Lua
    window.RP = {
        setAppearance: function (data) {
            if (!data) return;
            ["male", "female", "races", "heads", "clothes", "tones", "toneByRace", "body"].forEach(function (k) {
                if (data[k]) state.data[k] = data[k];
            });
        },
        showSelect: function (characters, maxSlots) {
            var previousCount = state.characters.length;
            state.characters = Array.isArray(characters) ? characters : [];
            state.maxSlots = maxSlots || 3;
            setBusy(false);
            setCamera("body");
            showView("select");

            var stillThere = state.characters.some(function (c) { return c.id === state.selectedId; });
            if (state.characters.length > previousCount && previousCount > 0) {
                // recien creado: seleccionarlo (la lista va ordenada por id)
                state.selectedId = state.characters[state.characters.length - 1].id;
            } else if (!stillThere) {
                state.selectedId = state.characters.length ? state.characters[0].id : null;
            }
            var selected = state.characters.filter(function (c) { return c.id === state.selectedId; })[0];
            if (selected) previewCharacter(selected);
            renderSlots();
        },
        setMusic: function (on) {
            musicBtn.classList.toggle("off", !on);
            musicBtn.querySelector("small").textContent = "XNOVA · clic para " + (on ? "silenciar" : "activar");
        },
        onResult: function (ok, message) {
            setBusy(false);
            sfx(ok ? "confirmation_003" : "error_004");
            if (!ok) document.body.classList.remove("leaving");
            var creating = document.body.classList.contains("creating");
            setMessage(creating && !ok ? "create-message" : "select-message", message, ok ? "success" : "error");
        }
    };
})();
