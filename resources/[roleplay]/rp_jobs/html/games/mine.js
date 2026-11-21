/*
 * rp_jobs / games/mine.js
 *   vein    golpear las grietas que brillan antes de que se apaguen; los golpes en roca sana
 *           cansan. Dinamita opcional (desde nivel 2): retírate cuando la mecha esté en verde.
 *           -> { hits, misses, total, dynamite, dynamiteGood }
 *   cavein  derrumbe: pulsa las teclas en orden antes de que caigan las rocas -> { ok }
 */
(function () {
    "use strict";
    JG.register("vein", {
        title: "Picar la veta",
        help: "Haz clic en las grietas brillantes antes de que se apaguen. Golpear roca sana te cansa.",
        start: function (stage, p, api) {
            var face = api.el("div", "rockface");
            stage.appendChild(face);
            for (var i = 0; i < 26; i++) {
                var s = api.el("div", "ore-spark");
                s.style.background = p.color || "#999";
                s.style.left = api.rand(120, 760) + "px"; s.style.top = api.rand(70, 440) + "px";
                s.style.transform = "scale(" + api.rand(0.6, 1.8) + ")";
                stage.appendChild(s);
            }
            var stamina = api.el("div", "stamina"), sf = api.el("div");
            sf.style.width = "100%"; stamina.appendChild(sf); stage.appendChild(stamina);
            var line = api.el("div", "hud-line");
            stage.appendChild(line);
            var total = p.cracks || 10, shown = 0, hits = 0, misses = 0, energy = 1, active = 0, dyn = false, dynGood = false, ended = false;
            function info() { line.textContent = "Grietas " + hits + "/" + total + (misses ? " · Golpes en vano " + misses : ""); }
            info();

            function chips(x, y) {
                for (var i = 0; i < 6; i++) {
                    var c = api.el("div", "chip");
                    c.style.left = x + "px"; c.style.top = y + "px";
                    c.style.setProperty("--cx", api.rand(-60, 60) + "px"); c.style.setProperty("--cy", api.rand(-60, 40) + "px");
                    stage.appendChild(c);
                    setTimeout((function (n) { return function () { if (n.parentNode) n.parentNode.removeChild(n); }; })(c), 650);
                }
            }

            function spawnCrack() {
                if (ended || shown >= total) return;
                shown++; active++;
                var c = api.el("div", "crack");
                c.style.left = api.rand(160, 720) + "px"; c.style.top = api.rand(100, 420) + "px";
                c.style.transform = "rotate(" + api.randInt(-60, 60) + "deg)";
                c._crack = true;
                stage.appendChild(c);
                var life = Math.max(700, 1500 - shown * 40);
                setTimeout(function () {
                    if (c.parentNode) { c.parentNode.removeChild(c); active--; checkEnd(); }
                }, life);
            }

            function checkEnd() {
                if (!ended && shown >= total && active <= 0) finish();
            }
            function finish() {
                if (ended) return;
                ended = true;
                api.done({ hits: hits, misses: misses, total: total, dynamite: dyn, dynamiteGood: dynGood });
            }

            api.on(stage, "mousedown", function (e) {
                if (ended || e.target.closest(".fuse") || e.target.tagName === "BUTTON") return;
                var q = api.pos(e);
                if (e.target._crack) {
                    hits++; active--; api.sfx("hit"); chips(q.x, q.y);
                    e.target.parentNode.removeChild(e.target);
                    checkEnd();
                } else {
                    misses++; energy = Math.max(0, energy - 0.08); api.sfx("miss"); chips(q.x, q.y);
                    sf.style.width = (energy * 100) + "%";
                    if (energy <= 0) { api.flash("Agotado", "bad"); finish(); }
                }
                info();
            });
            api.every(650, spawnCrack);
            spawnCrack();

            var foot = [];
            if (p.dynamite) {
                var b = api.el("button", "btn", "🧨 Poner dinamita");
                b.addEventListener("click", function () { if (!dyn && !ended) { b.disabled = true; dynamite(); } });
                foot.push(b);
            }
            api.foot(foot);

            function dynamite() {
                dyn = true;
                var fuse = api.el("div", "fuse"), safe = api.el("div", "safe"), spark = api.el("div", "spark");
                var sx = api.rand(0.45, 0.7);
                safe.style.left = (sx * 100) + "%"; safe.style.width = "18%";
                fuse.appendChild(safe); fuse.appendChild(spark); stage.appendChild(fuse);
                var run = api.el("button", "big-btn", "¡Atrás!");
                run.style.left = "50%"; run.style.bottom = "100px"; run.style.transform = "translateX(-50%)"; run.style.zIndex = 40;
                stage.appendChild(run);
                var pos = 0, decided = false;
                api.loop(function (dt) {
                    if (decided) return;
                    pos += dt * 0.38;
                    spark.style.left = (pos * 100) + "%";
                    if (pos >= 1) decide();
                });
                function decide() {
                    if (decided) return;
                    decided = true;
                    dynGood = pos >= sx && pos <= sx + 0.18;
                    api.sfx("shot");
                    api.flash(dynGood ? "¡BOOM! Buena voladura" : (pos < sx ? "Demasiado pronto: la mecha se apagó" : "¡Muy cerca!"), dynGood ? "good" : "bad");
                    if (!dynGood && pos > sx) { energy = Math.max(0, energy - 0.3); sf.style.width = (energy * 100) + "%"; }
                    if (fuse.parentNode) fuse.parentNode.removeChild(fuse);
                    if (run.parentNode) run.parentNode.removeChild(run);
                }
                run.addEventListener("click", decide);
            }
            api.timer(p.time || 22, finish);
        }
    });

    JG.register("cavein", {
        title: "¡DERRUMBE!",
        help: "¡Pulsa las teclas en orden para salir corriendo!",
        start: function (stage, p, api) {
            stage.classList.add("shaking");
            var keys = p.keys || ["W", "A", "S", "D", "W"], idx = 0;
            var row = api.el("div", "keys"), nodes = [];
            keys.forEach(function (k, i) {
                var n = api.el("div", "key" + (i === 0 ? " next" : ""), k);
                row.appendChild(n); nodes.push(n);
            });
            stage.appendChild(row);
            api.every(160, function () {
                var r = api.el("div", "rock-fall emoji", "🪨");
                r.style.left = api.rand(0, 860) + "px";
                stage.appendChild(r);
                setTimeout(function () { if (r.parentNode) r.parentNode.removeChild(r); }, 1200);
            });
            api.on(document, "keydown", function (e) {
                var k = (e.key || "").toUpperCase();
                if (k.length !== 1) return;
                if (k === keys[idx]) {
                    nodes[idx].classList.remove("next"); nodes[idx].classList.add("done"); idx++;
                    api.sfx("hit");
                    if (idx >= keys.length) { stage.classList.remove("shaking"); api.flash("¡A salvo!", "good"); api.done({ ok: true }); }
                    else nodes[idx].classList.add("next");
                } else { api.sfx("miss"); }
            });
            api.after(p.time || 4200, function () { api.flash("¡Te alcanzaron las rocas!", "bad"); api.done({ ok: false }); });
        }
    });

    window.JG_DEMOS = window.JG_DEMOS || {};
    window.JG_DEMOS.vein = { ore: "ore_gold", color: "#f5c542", cracks: 10, dynamite: true, time: 22, jobColor: [160, 160, 180] };
    window.JG_DEMOS.cavein = { keys: ["W", "A", "S", "D", "Q", "E"], time: 4200, jobColor: [160, 160, 180] };
    window.JG_DEMOS.panel = {
        job: { id: "fisher", name: "Pescador", icon: "🎣", color: [70, 170, 230], locationName: "Muelle de Santa Maria Beach",
            description: "Pesca desde el muelle o sal en barco a los bancos de peces.", pay: "Según la especie: $15-400 por pieza en la lonja." },
        myJob: "fisher", onShift: false, canHire: false, level: 2, xp: 180, levelXP: 120, nextXP: 320, tasks: 41, earned: 2310, best: 640, bonus: 8,
        options: [{ id: "pier", label: "Pescar en el muelle", enabled: true }, { id: "boat", label: "Salir en barco", enabled: true }],
        perks: ["Con nivel 2 puedes salir en barco a los bancos de peces.", "En el mar hay atunes y, desde nivel 3, peces espada."]
    };
    window.JG_DEMOS.market = { id: "fishmarket", name: "Lonja del puerto", icon: "🐟", money: 1250, items: [
        { id: "fish_tuna", name: "Atún", icon: "🐟", price: 131, base: 120, trend: 1, have: 3 },
        { id: "fish_bass", name: "Lubina", icon: "🐟", price: 39, base: 45, trend: -1, have: 5 },
        { id: "fish_sardine", name: "Sardina", icon: "🐟", price: 15, base: 15, trend: 0, have: 0 },
        { id: "fish_swordfish", name: "Pez espada", icon: "🐟", price: 402, base: 380, trend: 1, have: 0 }] };
})();
