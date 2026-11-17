/*
 * rp_clothing / editor.js
 * Lua llama a RP.init({ name, values, bones, limits, defaults }).
 * Cada cambio manda rp:toyed:change(JSON) para la vista previa en vivo.
 */
(function () {
    "use strict";

    var $ = function (id) { return document.getElementById(id); };
    var v = {}, defaults = {}, limits = { pos: 0.75, rot: 180, scaleMin: 0.25, scaleMax: 2.5 };
    var cam = { angle: 0, zoom: 1.6 };
    var inputs = {};

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);
    }
    function push() { send("rp:toyed:change", JSON.stringify([v])); }

    function slider(parent, key, label, min, max, step, decimals, onInput) {
        var row = document.createElement("div");
        row.className = "slider";
        var name = document.createElement("span");
        name.textContent = label;
        var input = document.createElement("input");
        input.type = "range"; input.min = min; input.max = max; input.step = step;
        var out = document.createElement("output");
        row.appendChild(name); row.appendChild(input); row.appendChild(out);
        parent.appendChild(row);
        function show() { out.textContent = Number(input.value).toFixed(decimals); }
        input.addEventListener("input", function () { show(); onInput(Number(input.value)); });
        inputs[key] = { input: input, show: show };
        return input;
    }

    function setValue(key, value) {
        var i = inputs[key];
        if (!i) return;
        i.input.value = value;
        i.show();
    }

    function build(bones) {
        var bone = $("bone");
        bones.forEach(function (b) {
            var o = document.createElement("option");
            o.value = b.id; o.textContent = b.name;
            bone.appendChild(o);
        });
        bone.addEventListener("change", function () { v.bone = Number(bone.value); push(); });

        [["x", "X"], ["y", "Y"], ["z", "Z"]].forEach(function (a) {
            slider($("pos"), a[0], a[1], -limits.pos, limits.pos, 0.005, 3, function (n) { v[a[0]] = n; push(); });
        });
        [["rx", "X"], ["ry", "Y"], ["rz", "Z"]].forEach(function (a) {
            slider($("rot"), a[0], a[1], -limits.rot, limits.rot, 1, 0, function (n) { v[a[0]] = n; push(); });
        });
        [["sx", "X"], ["sy", "Y"], ["sz", "Z"]].forEach(function (a) {
            slider($("scale"), a[0], a[1], limits.scaleMin, limits.scaleMax, 0.01, 2, function (n) {
                if ($("uniform").checked) {
                    v.sx = v.sy = v.sz = n;
                    ["sx", "sy", "sz"].forEach(function (k) { setValue(k, n); });
                } else {
                    v[a[0]] = n;
                }
                push();
            });
        });
        slider($("cam"), "angle", "Giro", -180, 180, 1, 0, function (n) { cam.angle = n; send("rp:toyed:camera", String(cam.angle), String(cam.zoom)); });
        slider($("cam"), "zoom", "Zoom", 0.8, 4, 0.05, 2, function (n) { cam.zoom = n; send("rp:toyed:camera", String(cam.angle), String(cam.zoom)); });
    }

    function fill() {
        $("bone").value = v.bone;
        ["x", "y", "z", "rx", "ry", "rz", "sx", "sy", "sz"].forEach(function (k) { setValue(k, v[k]); });
        setValue("angle", cam.angle);
        setValue("zoom", cam.zoom);
        $("uniform").checked = v.sx === v.sy && v.sy === v.sz;
    }

    $("btn-save").addEventListener("click", function () { send("rp:toyed:save"); });
    $("btn-cancel").addEventListener("click", function () { send("rp:toyed:cancel"); });
    $("btn-reset").addEventListener("click", function () {
        Object.keys(defaults).forEach(function (k) { v[k] = defaults[k]; });
        fill();
        push();
    });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") send("rp:toyed:cancel"); });

    window.RP = {
        init: function (d) {
            $("toy-name").textContent = d.name || "Accesorio";
            limits = d.limits || limits;
            defaults = d.defaults || {};
            v = d.values || {};
            build(d.bones || []);
            fill();
        }
    };
})();
