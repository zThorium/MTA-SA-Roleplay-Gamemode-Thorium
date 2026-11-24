/*
 * rp_phone / music.js
 * App Musica dentro del telefono. El servidor entrega keys, metadatos y estado.
 */
(function () {
    "use strict";

    var catalog = [];
    var results = [];
    var state = null;
    var favorites = {};
    var library = [];
    var history = [];
    var tab = "explore";

    var $ = function (id) { return document.getElementById(id); };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined) node.textContent = text;
        return node;
    }

    function findTrack(key) {
        for (var i = 0; i < catalog.length; i++) {
            if (catalog[i].key === key) return catalog[i];
        }
        for (var j = 0; j < results.length; j++) {
            if (results[j].key === key) return results[j];
        }
        return null;
    }

    function makeCover(track) {
        var cover = el("div", "music-cover");
        if (track && track.artwork) {
            var img = document.createElement("img");
            img.src = track.artwork;
            img.alt = "";
            cover.appendChild(img);
        } else {
            cover.textContent = "♫";
        }
        return cover;
    }

    function renderResults(list) {
        var box = $("music-results");
        box.textContent = "";
        if (!list || !list.length) {
            box.appendChild(el("p", "music-empty", "No hay resultados."));
            return;
        }
        list.forEach(function (track) {
            var row = el("div", "music-track");
            row.appendChild(makeCover(track));
            var meta = el("div", "music-track-meta");
            meta.appendChild(el("strong", null, track.title));
            meta.appendChild(el("span", null, track.artist));
            row.appendChild(meta);
            var favorite = el("button", "music-favorite", favorites[track.key] ? "♥" : "♡");
            favorite.setAttribute("type", "button");
            favorite.setAttribute("aria-label", "Guardar en biblioteca");
            favorite.addEventListener("click", function () {
                send("rp:phone:ui:musicFavorite", track.key);
            });
            row.appendChild(favorite);
            var play = el("button", null, "▶");
            play.setAttribute("type", "button");
            play.addEventListener("click", function () {
                send("rp:phone:ui:musicPlay", track.key);
            });
            row.appendChild(play);
            box.appendChild(row);
        });
    }

    function refreshPlayer() {
        var player = $("music-player");
        var modes = $("music-modes");
        if (!state || !state.trackKey) {
            player.hidden = true;
            modes.hidden = true;
            $("view-music").classList.remove("playing");
            return;
        }
        var track = findTrack(state.trackKey);
        player.hidden = false;
        modes.hidden = false;
        $("view-music").classList.add("playing");
        $("music-now-title").textContent = track ? track.title : "Reproduciendo";
        $("music-now-artist").textContent = track ? track.artist : "";
        var cover = $("music-cover");
        cover.textContent = "";
        cover.appendChild(makeCover(track));
        $("music-play").textContent = state.paused ? "▶" : "Ⅱ";
        $("music-play").setAttribute("aria-label", state.paused ? "Reanudar" : "Pausar");
        $("music-play").title = state.paused ? "Reanudar" : "Pausar";

        var speaker = $("music-speaker");
        speaker.textContent = state.speaker ? "Altavoz encendido" : "Altavoz apagado";
        speaker.classList.toggle("active", state.speaker === true);

        $("music-volume").value = String(state.volume || 60);

        var vehicle = $("music-vehicle");
        vehicle.hidden = false;
        vehicle.textContent = state.origin === "vehicle" ? "Usar telefono" : "Radio del vehiculo";
        vehicle.classList.toggle("active", state.origin === "vehicle");
    }

    function search() {
        var query = String($("music-search-input").value || "").replace(/^\s+|\s+$/g, "");
        send("rp:phone:ui:musicSearch", query);
    }

    $("music-search-go").addEventListener("click", search);
    $("music-search-input").addEventListener("keydown", function (event) {
        if (event.key === "Enter") search();
    });
    document.querySelectorAll("[data-music-tab]").forEach(function (button) {
        button.addEventListener("click", function () {
            tab = button.dataset.musicTab;
            document.querySelectorAll("[data-music-tab]").forEach(function (item) {
                item.classList.toggle("active", item === button);
            });
            if (tab === "library") renderResults(library);
            else if (tab === "history") renderResults(history);
            else renderResults(results.length ? results : catalog);
        });
    });
    $("music-stop").addEventListener("click", function () {
        send("rp:phone:ui:musicStop");
    });
    $("music-play").addEventListener("click", function () {
        if (state && state.trackKey) send("rp:phone:ui:musicPause", !state.paused);
    });
    $("music-speaker").addEventListener("click", function () {
        send("rp:phone:ui:musicSpeaker", !(state && state.speaker));
    });
    $("music-volume").addEventListener("input", function () {
        send("rp:phone:ui:musicVolume", Number(this.value));
    });
    $("music-vehicle").addEventListener("click", function () {
        send("rp:phone:ui:musicVehicle", !(state && state.origin === "vehicle"));
    });

    window.Music = {
        onShow: function (name) {
            if (name !== "music") return;
            send("rp:phone:ui:musicLibrary");
        },
        setCatalog: function (items) {
            catalog = items || [];
            if (!results.length && tab === "explore") renderResults(catalog);
            refreshPlayer();
        },
        setSearchResults: function (items) {
            results = items || [];
            tab = "explore";
            document.querySelectorAll("[data-music-tab]").forEach(function (item) {
                item.classList.toggle("active", item.dataset.musicTab === "explore");
            });
            renderResults(results);
        },
        setState: function (next) {
            state = next || null;
            refreshPlayer();
        },
        setFavorite: function (trackKey, favorite) {
            favorites[trackKey] = favorite === true;
            send("rp:phone:ui:musicLibrary");
        },
        setLibrary: function (favoriteItems, historyItems) {
            library = favoriteItems || [];
            history = historyItems || [];
            favorites = {};
            library.forEach(function (track) { favorites[track.key] = true; });
            if (tab === "library") renderResults(library);
            else if (tab === "history") renderResults(history);
        }
    };

    window.RP.music = window.RP.music || window.Music;
})();
