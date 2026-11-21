/*
 * rp_jobs / games/farm.js
 *   sow    sembrar en el momento justo cuando la sembradora pasa sobre la tierra blanda
 *   pests  aplastar los bichos antes de que se coman las plantas
 *   water  regar la tierra seca arrastrando la manguera sin gastar el agua en charcos
 *   weeds  arrancar malas hierbas (arrastrar hacia arriba) sin arrancar el cultivo
 * Todos devuelven { score: 0..1 }
 */
(function () {
    "use strict";
    function clamp(v) { return Math.max(0, Math.min(1, v)); }

    JG.register("sow", {
        title: "Siembra a mano",
        help: "Haz clic (o pulsa Espacio) cuando la sembradora pase sobre la tierra blanda. Fallar desperdicia semillas.",
        start: function (stage, p, api) {
            var rows = p.rows || 3, seeds = p.seeds || 6, speed = (p.speed || 1) * 230;
            var row = 0, x = 0, planted = 0, misses = 0, spots = [], planter, furrow;
            var line = api.el("div", "hud-line");
            stage.appendChild(line);
            function info() { line.textContent = "Surco " + (row + 1) + "/" + rows + " · Sembradas " + planted + "/" + rows * seeds + " · Fallos " + misses; }

            function buildRow() {
                stage.querySelectorAll(".furrow").forEach(function (f) { f.style.opacity = 0.35; });
                furrow = api.el("div", "furrow");
                furrow.style.top = (140 + row * 110) + "px";
                stage.appendChild(furrow);
                spots = [];
                var width = 800 - 80;
                for (var i = 0; i < seeds; i++) {
                    var s = api.el("div", "soft");
                    var sx = 40 + (i + 0.5) * width / seeds + api.rand(-25, 25);
                    s.style.left = (sx - 40 - 27) + "px";
                    furrow.appendChild(s);
                    spots.push({ x: sx, node: s, done: false });
                }
                planter = api.el("div", "planter");
                planter.style.top = (130 + row * 110) + "px";
                stage.appendChild(planter);
                x = 20;
                info();
            }

            function plant() {
                var hit = null;
                spots.forEach(function (s) { if (!s.done && Math.abs(s.x - x) < 26) hit = s; });
                if (hit) {
                    hit.done = true; planted++;
                    hit.node.appendChild(api.el("div", "sprout emoji", p.crop || "🌱"));
                    api.sfx("hit");
                } else { misses++; api.sfx("miss"); }
                info();
            }

            function finish() {
                api.done({ score: clamp(planted / (rows * seeds) - misses * 0.04) });
            }

            buildRow();
            api.loop(function (dt) {
                x += speed * dt;
                planter.style.left = x + "px";
                if (x > 840) {
                    if (planter.parentNode) planter.parentNode.removeChild(planter);
                    row++;
                    if (row >= rows) return finish();
                    buildRow();
                }
            });
            api.on(stage, "mousedown", plant);
            api.on(document, "keydown", function (e) { if (e.code === "Space") { e.preventDefault(); plant(); } });
        }
    });

    JG.register("pests", {
        title: "¡Plaga!",
        help: "Haz clic sobre los bichos antes de que lleguen a las plantas.",
        start: function (stage, p, api) {
            var plants = [], bugs = [], spawned = 0, total = p.bugs || 16;
            for (var i = 0; i < 8; i++) {
                var n = api.el("div", "plant emoji", p.crop || "🌱");
                var px = 110 + (i % 4) * 180, py = 170 + Math.floor(i / 4) * 160;
                n.style.left = px + "px"; n.style.top = py + "px";
                var hp = api.el("div", "hp"), bar = api.el("div");
                bar.style.width = "100%"; hp.appendChild(bar); n.appendChild(hp);
                stage.appendChild(n);
                plants.push({ x: px + 35, y: py + 40, hp: 1, bar: bar });
            }
            var BUGS = ["🐛", "🦗", "🐌", "🐜"];
            function spawn() {
                if (spawned >= total) return;
                spawned++;
                var side = api.randInt(0, 3), x, y;
                if (side === 0) { x = -30; y = api.rand(120, 480); } else if (side === 1) { x = 890; y = api.rand(120, 480); }
                else if (side === 2) { x = api.rand(0, 860); y = 100; } else { x = api.rand(0, 860); y = 530; }
                var target = plants[api.randInt(0, plants.length - 1)];
                var n = api.el("div", "bug emoji", BUGS[api.randInt(0, BUGS.length - 1)]);
                stage.appendChild(n);
                var b = { x: x, y: y, t: target, node: n, alive: true, speed: api.rand(45, 85) };
                n.addEventListener("mousedown", function () {
                    if (!b.alive) return;
                    b.alive = false; n.classList.add("dead"); api.sfx("hit");
                });
                bugs.push(b);
            }
            api.every(900, spawn);
            spawn();
            api.loop(function (dt) {
                bugs.forEach(function (b) {
                    if (!b.alive) return;
                    var dx = b.t.x - b.x, dy = b.t.y - b.y, d = Math.sqrt(dx * dx + dy * dy);
                    if (d > 20) { b.x += dx / d * b.speed * dt; b.y += dy / d * b.speed * dt; }
                    else { b.t.hp = Math.max(0, b.t.hp - 0.25 * dt); b.t.bar.style.width = (b.t.hp * 100) + "%"; }
                    b.node.style.left = (b.x - 15) + "px"; b.node.style.top = (b.y - 15) + "px";
                });
            });
            function finish() {
                var sum = 0; plants.forEach(function (pl) { sum += pl.hp; });
                api.done({ score: clamp(sum / plants.length) });
            }
            api.timer(p.time || 20, finish);
        }
    });

    JG.register("water", {
        title: "Riego",
        help: "Mantén pulsado y pasa la manguera por la tierra seca. Si riegas dos veces el mismo sitio, se encharca y gastas agua.",
        start: function (stage, p, api) {
            var cells = [], n = p.cells || 24, cols = 6, water = 1, down = false;
            var hose = api.el("div", "hose hidden");
            for (var i = 0; i < n; i++) {
                var c = api.el("div", "cell");
                var cx = 70 + (i % cols) * 120, cy = 130 + Math.floor(i / cols) * 92;
                c.style.left = cx + "px"; c.style.top = cy + "px"; c.style.width = "108px"; c.style.height = "80px";
                stage.appendChild(c);
                cells.push({ node: c, x: cx, y: cy, wet: 0 });
            }
            var tank = api.el("div", "tank"), level = api.el("div");
            level.style.height = "100%"; tank.appendChild(level);
            stage.appendChild(tank); stage.appendChild(hose);
            api.on(stage, "mousedown", function () { down = true; hose.classList.remove("hidden"); });
            api.on(document, "mouseup", function () { down = false; hose.classList.add("hidden"); });
            api.on(stage, "mousemove", function (e) {
                var pos = api.pos(e);
                hose.style.left = pos.x + "px"; hose.style.top = pos.y + "px";
                if (!down || water <= 0) return;
                cells.forEach(function (c) {
                    if (pos.x > c.x && pos.x < c.x + 108 && pos.y > c.y && pos.y < c.y + 80) {
                        c.wet = Math.min(2, c.wet + 0.08);
                        water = Math.max(0, water - (c.wet > 1.4 ? 0.006 : 0.0025));
                    }
                });
            });
            api.loop(function (dt) {
                cells.forEach(function (c) {
                    if (c.wet > 0 && c.wet <= 1.4) c.wet = Math.max(0, c.wet - 0.02 * dt);   // el sol seca
                    c.node.className = "cell" + (c.wet > 1.4 ? " puddle" : (c.wet >= 0.8 ? " wet" : ""));
                });
                level.style.height = (water * 100) + "%";
            });
            function finish() {
                var good = 0;
                cells.forEach(function (c) { if (c.wet >= 0.8 && c.wet <= 1.4) good++; else if (c.wet > 1.4) good += 0.5; });
                api.done({ score: clamp(good / cells.length) });
            }
            api.timer(p.time || 20, finish);
        }
    });

    JG.register("weeds", {
        title: "Malas hierbas",
        help: "Agarra las malas hierbas 🌿 y arrástralas hacia arriba para arrancarlas. No arranques el cultivo.",
        start: function (stage, p, api) {
            var total = p.weeds || 10, pulled = 0, mistakes = 0, drag = null;
            var items = [];
            for (var i = 0; i < total + 8; i++) {
                var weed = i < total;
                var n = api.el("div", (weed ? "weed" : "crop") + " emoji", weed ? (Math.random() < 0.5 ? "🌿" : "☘️") : (p.crop || "🌱"));
                var x = api.rand(40, 800), y = api.rand(150, 460);
                n.style.left = x + "px"; n.style.top = y + "px";
                n._weed = weed; n._y = y;
                stage.appendChild(n);
                items.push(n);
            }
            var line = api.el("div", "hud-line");
            stage.appendChild(line);
            function info() { line.textContent = "Arrancadas " + pulled + "/" + total + (mistakes ? " · Cultivo dañado " + mistakes : ""); }
            info();
            api.on(stage, "mousedown", function (e) {
                if (typeof e.target._y !== "number") return;
                drag = { node: e.target, start: api.pos(e).y };
            });
            api.on(document, "mousemove", function (e) {
                if (!drag) return;
                var dy = drag.start - api.pos(e).y;
                drag.node.style.top = (drag.node._y - Math.max(0, Math.min(dy, 80))) + "px";
                if (dy > 70) {
                    var n = drag.node; drag = null;
                    n.style.transition = "all 0.3s"; n.style.opacity = 0; n.style.top = (n._y - 160) + "px";
                    if (n._weed) { pulled++; api.sfx("hit"); } else { mistakes++; api.sfx("bad"); api.flash("¡Era cultivo!", "bad"); }
                    n._y = null;
                    info();
                    if (pulled >= total) finish();
                }
            });
            api.on(document, "mouseup", function () {
                if (drag && typeof drag.node._y === "number") drag.node.style.top = drag.node._y + "px";
                drag = null;
            });
            function finish() { api.done({ score: clamp(pulled / total - mistakes * 0.15) }); }
            api.timer(p.time || 20, finish);
        }
    });

    window.JG_DEMOS = window.JG_DEMOS || {};
    window.JG_DEMOS.sow = { crop: "🌽", rows: 3, seeds: 6, speed: 1, jobColor: [230, 190, 60] };
    window.JG_DEMOS.pests = { crop: "🍅", bugs: 16, time: 20, jobColor: [230, 190, 60] };
    window.JG_DEMOS.water = { cells: 24, time: 20, jobColor: [230, 190, 60] };
    window.JG_DEMOS.weeds = { crop: "🥔", weeds: 10, time: 20, jobColor: [230, 190, 60] };
})();
