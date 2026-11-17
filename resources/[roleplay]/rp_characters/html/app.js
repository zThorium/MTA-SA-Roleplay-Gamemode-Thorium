/*
 * rp_characters / app.js
 * Seleccion y creacion de personajes. Lua llama a window.RP.*; la interfaz
 * responde con mta.triggerEvent("rp:chars:ui:*", ...).
 *
 * Apariencia:
 *  - Hombre: raza + cabeza (rp_heads) + ropa de CJ (torso, piernas, zapatos)
 *  - Mujer: skin
 */
(function () {
    "use strict";

    var LIMITS = { storyMin: 100, storyMax: 2000 };
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
            clothes: { torso: 1, legs: 1, shoes: 1 }
        },
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
                head: c.head, torso: c.clothes_torso || 0, legs: c.clothes_legs || 0, shoes: c.clothes_shoes || 0
            }));
        } else {
            send("rp:chars:ui:look", JSON.stringify({ skin: c.skin }));
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
                shoes: wrap(state.index.shoes, state.data.clothes.shoes)
            };
        }
        var skins = state.data.female;
        return { skin: skins[wrap(state.index.skin, skins.length)] };
    }

    function sendLook() {
        send("rp:chars:ui:look", JSON.stringify(currentLook()));
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
                setBusy(true);
                setMessage("select-message", "Entrando...", "success");
                send("rp:chars:ui:play", c.id);
            });
            var del = el("button", "danger ghost", "Eliminar");
            del.type = "button";
            del.addEventListener("click", function (e) { e.stopPropagation(); openDelete(c); });
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
            empty.addEventListener("click", openCreate);
            container.appendChild(empty);
        }

        var free = state.maxSlots - state.characters.length;
        $("slots-info").textContent = free > 0
            ? "Tienes " + free + " de " + state.maxSlots + " espacios libres"
            : "Todos tus espacios estan ocupados";
    }

    function selectCharacter(c) {
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
    $("delete-cancel").addEventListener("click", closeDelete);
    $("delete-confirm").addEventListener("click", function () {
        if (!deleting) return;
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
                state.race = race;
                state.index.head = 0;
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
        sendLook();
    }

    // ---------------------------------------------------------- Creacion
    function openCreate() {
        form.reset();
        form.querySelectorAll(".invalid").forEach(function (n) { n.classList.remove("invalid"); });
        state.race = 1;
        state.index = { head: 0, torso: 0, legs: 0, shoes: 0, skin: 0 };
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
        var len = form.story.value.length;
        var counter = $("story-count");
        counter.textContent = len + " / " + LIMITS.storyMax + (len < LIMITS.storyMin ? " (minimo " + LIMITS.storyMin + ")" : "");
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
        var weight = readNumber(form.weight, 40, 200);
        if (weight === null) return fail(form.weight, "El peso debe estar entre 40 y 200 kg.");
        var height = readNumber(form.height, 140, 220);
        if (height === null) return fail(form.height, "La altura debe estar entre 140 y 220 cm.");

        var origin = form.origin.value.trim();
        if (origin.length < 3) return fail(form.origin, "Indica el lugar de origen de tu personaje.");

        var story = form.story.value.trim();
        if (story.length < LIMITS.storyMin) return fail(form.story, "La historia debe tener al menos " + LIMITS.storyMin + " caracteres.");

        var data = {
            firstName: form.firstName.value,
            lastName: form.lastName.value,
            gender: state.gender,
            age: age,
            weight: weight,
            height: height,
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
        setMessage("create-message", "");
        setBusy(true);
        send("rp:chars:ui:create", JSON.stringify(data));
    });

    form.story.addEventListener("input", updateStoryCount);
    $("btn-back").addEventListener("click", function () { RP.showSelect(state.characters, state.maxSlots); });
    $("btn-zoom").addEventListener("click", function () { setCamera(state.camera === "face" ? "body" : "face"); });
    document.querySelectorAll("#gender button").forEach(function (b) {
        b.addEventListener("click", function () { setGender(Number(b.dataset.gender)); });
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
            ["male", "female", "races", "heads", "clothes"].forEach(function (k) {
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
        onResult: function (ok, message) {
            setBusy(false);
            var creating = document.body.classList.contains("creating");
            setMessage(creating && !ok ? "create-message" : "select-message", message, ok ? "success" : "error");
        }
    };
})();
