/*
 * rp_jobs / games/hunt.js
 *   tracks  elegir la huella fresca entre tres -> { correct }
 *   scope   mira telescópica con balanceo, respiración, viento y caída de la bala -> { hit: "vital"|"body"|"miss" }
 *   skin    recorrer los puntos con el cuchillo sin salirse de la línea -> { accuracy }
 */
(function () {
    "use strict";
    var ICON = { rabbit: "🐇", deer: "🦌", boar: "🐗", bear: "🐻" };

    JG.register("tracks", {
        title: "Examinar huellas",
        help: "¿Cuál es la huella fresca? Las frescas tienen bordes nítidos y tierra oscura y húmeda; las viejas están secas, borrosas o con hojas encima.",
        start: function (stage, p, api) {
            var fresh = api.randInt(0, 2), subtle = p.difficulty || 0.4;
            for (var i = 0; i < 3; i++) {
                var box = api.el("div", "print");
                box.style.left = (60 + i * 270) + "px";
                var mark = api.el("div", "mark emoji", "🐾");
                var isFresh = i === fresh;
                var blur = isFresh ? 0 : api.rand(1.2, 3.5) * (1.2 - subtle);
                var light = isFresh ? 0.55 : api.rand(0.85, 1.15);
                mark.style.filter = "blur(" + blur.toFixed(1) + "px) brightness(" + light.toFixed(2) + ") sepia(" + (isFresh ? 0.2 : 0.7) + ")";
                mark.style.transform = "rotate(" + api.randInt(-30, 30) + "deg)";
                box.appendChild(mark);
                if (!isFresh) {
                    var cue = api.randInt(0, 2);
                    if (cue === 0) { var leaf = api.el("div", "leaf emoji", "🍂"); leaf.style.left = api.rand(30, 120) + "px"; leaf.style.top = api.rand(40, 150) + "px"; box.appendChild(leaf); }
                    else if (cue === 1) { var w = api.el("div", "water"); w.style.left = "55px"; w.style.top = "90px"; box.appendChild(w); }
                }
                (function (ok) {
                    box.addEventListener("click", function () {
                        api.sfx(ok ? "good" : "bad");
                        api.flash(ok ? "¡Fresca!" : "Era vieja", ok ? "good" : "bad");
                        api.done({ correct: ok });
                    });
                })(isFresh);
                stage.appendChild(box);
            }
            var hint = api.el("div", "hud-line", "Rastro de " + ({ rabbit: "conejo", deer: "ciervo", boar: "jabalí", bear: "oso" }[p.animal] || "animal"));
            stage.appendChild(hint);
            api.timer(12, function () { api.done({ correct: false }); });
        }
    });

    JG.register("scope", {
        title: "Mira telescópica",
        help: "Apunta al pecho para un disparo limpio. Mantén Shift (o el botón derecho) para contener la respiración. Ten en cuenta el viento y la distancia.",
        start: function (stage, p, api) {
            var world = api.el("div", "scope-world");
            stage.appendChild(world);
            for (var i = 0; i < 7; i++) {
                var t = api.el("div", "scope-tree emoji", Math.random() < 0.5 ? "🌲" : "🌳");
                t.style.left = api.rand(-20, 840) + "px"; t.style.bottom = api.rand(110, 200) + "px";
                t.style.fontSize = api.rand(60, 120) + "px";
                world.appendChild(t);
            }
            var animal = api.el("div", "scope-animal emoji", ICON[p.animal] || "🦌");
            world.appendChild(animal);
            var mask = api.el("div", "scope-mask"), cross = api.el("div", "scope-cross");
            stage.appendChild(mask); stage.appendChild(cross);
            var info = api.el("div", "scope-info");
            var wind = p.wind || 0, dist = p.distance || 120;
            info.textContent = "Distancia " + dist + " m · Viento " + (wind > 0 ? "→ " : "← ") + Math.abs(Math.round(wind * 20)) + " km/h";
            stage.appendChild(info);
            var breath = api.el("div", "breath"), breathFill = api.el("div");
            breath.appendChild(breathFill); stage.appendChild(breath);

            var ax = api.rand(200, 600), ay = 330, avx = 0, pause = 0, flip = 1;
            var mx = 440, my = 260, hold = false, stamina = 1, t = 0, shot = false;
            var diff = p.difficulty || 0.5;
            api.on(stage, "mousemove", function (e) { var q = api.pos(e); mx = q.x; my = q.y; });
            api.on(document, "keydown", function (e) { if (e.key === "Shift") hold = true; });
            api.on(document, "keyup", function (e) { if (e.key === "Shift") hold = false; });
            api.on(stage, "contextmenu", function (e) { e.preventDefault(); });
            api.on(stage, "mousedown", function (e) {
                if (e.button === 2) { hold = true; return; }
                fire();
            });
            api.on(document, "mouseup", function (e) { if (e.button === 2) hold = false; });

            var sx = 0, sy = 0;
            api.loop(function (dt) {
                t += dt;
                // animal: camina, se para y a veces corre
                if (pause > 0) { pause -= dt; avx = 0; }
                else {
                    if (Math.random() < 0.01) pause = api.rand(0.6, 2.0);
                    if (Math.random() < 0.006) flip = -flip;
                    avx = flip * (40 + diff * 90) * (Math.random() < 0.004 ? 4 : 1);
                }
                ax += avx * dt;
                if (ax < 40) { ax = 40; flip = 1; } if (ax > 760) { ax = 760; flip = -1; }
                animal.style.left = ax + "px";
                animal.style.transform = "scaleX(" + (flip > 0 ? -1 : 1) + ")";
                // balanceo de la mira
                var steady = hold && stamina > 0;
                stamina = Math.max(0, Math.min(1, stamina + (steady ? -0.35 : 0.18) * dt));
                breathFill.style.width = (stamina * 100) + "%";
                var amp = steady ? 4 : 22;
                sx = Math.sin(t * 1.3) * amp + Math.sin(t * 3.1) * amp * 0.4;
                sy = Math.cos(t * 1.7) * amp * 0.7;
                var cx = mx + sx, cy = my + sy;
                cross.style.left = cx + "px"; cross.style.top = cy + "px";
                mask.style.setProperty("--sx", cx + "px"); mask.style.setProperty("--sy", cy + "px");
            });

            function fire() {
                if (shot) return;
                shot = true;
                api.sfx("shot");
                // la bala se desvía con el viento y cae con la distancia
                var ix = mx + sx + wind * dist * 0.35;
                var iy = my + sy + (dist - 60) * 0.18;
                var r = animal.getBoundingClientRect(), s = stage.getBoundingClientRect();
                var left = r.left - s.left, top = r.top - s.top, w = r.width, h = r.height;
                var chestX = left + w * (flip > 0 ? 0.62 : 0.38), chestY = top + h * 0.55;
                var hit = "miss";
                if (Math.abs(ix - chestX) < w * 0.14 && Math.abs(iy - chestY) < h * 0.16) hit = "vital";
                else if (ix > left + w * 0.1 && ix < left + w * 0.9 && iy > top + h * 0.25 && iy < top + h * 0.95) hit = "body";
                api.flash(hit === "vital" ? "¡Disparo limpio!" : (hit === "body" ? "Herido" : "¡Fallaste!"), hit === "miss" ? "bad" : "good");
                if (hit !== "miss") animal.style.transform += " rotate(90deg)";
                api.done({ hit: hit, delay: 1000 });
            }
            api.timer(25, function () { api.done({ hit: "miss" }); });
        }
    });

    JG.register("skin", {
        title: "Preparar la pieza",
        help: "Mantén pulsado y pasa el cuchillo por los puntos en orden, sin salirte de la línea.",
        start: function (stage, p, api) {
            stage.appendChild(api.el("div", "hide-shape"));
            var NS = "http://www.w3.org/2000/svg";
            var svg = document.createElementNS(NS, "svg");
            svg.setAttribute("class", "saw-svg"); svg.setAttribute("width", "880"); svg.setAttribute("height", "520");
            stage.appendChild(svg);
            var n = p.points || 7, pts = [], next = 0, down = false, samples = 0, error = 0;
            var x = 200, y = api.rand(180, 340);
            for (var i = 0; i < n; i++) {
                pts.push({ x: x, y: y });
                x += 480 / (n - 1);
                y = Math.max(110, Math.min(410, y + api.rand(-70, 70)));
            }
            var d = "";
            pts.forEach(function (q, i) {
                d += (i ? " L " : "M ") + q.x + " " + q.y;
                var dot = api.el("div", "skin-dot", String(i + 1));
                dot.style.left = q.x + "px"; dot.style.top = q.y + "px";
                q.node = dot; stage.appendChild(dot);
            });
            var path = document.createElementNS(NS, "path");
            path.setAttribute("d", d); path.setAttribute("fill", "none"); path.setAttribute("stroke", "rgba(255,255,255,0.7)");
            path.setAttribute("stroke-width", "3"); path.setAttribute("stroke-dasharray", "8 8");
            svg.appendChild(path);

            function segDist(px, py, a, b) {
                var vx = b.x - a.x, vy = b.y - a.y, wx = px - a.x, wy = py - a.y;
                var t = Math.max(0, Math.min(1, (vx * wx + vy * wy) / (vx * vx + vy * vy)));
                var dx = a.x + vx * t - px, dy = a.y + vy * t - py;
                return Math.sqrt(dx * dx + dy * dy);
            }
            function finish() {
                var reached = next / n;
                var acc = samples ? 1 - error / samples : 0;
                api.done({ accuracy: Math.max(0, Math.min(1, acc * reached)) });
            }
            api.on(stage, "mousedown", function () { down = true; });
            api.on(document, "mouseup", function () { down = false; });
            api.on(stage, "mousemove", function (e) {
                if (!down) return;
                var q = api.pos(e);
                if (next > 0 && next < n) {
                    samples++;
                    error += Math.min(1, segDist(q.x, q.y, pts[next - 1], pts[next]) / 35);
                }
                var target = pts[next];
                if (target && Math.abs(q.x - target.x) < 18 && Math.abs(q.y - target.y) < 18) {
                    target.node.classList.add("hit"); api.sfx("tick"); next++;
                    if (next >= n) finish();
                }
            });
            api.timer(15, finish);
        }
    });

    window.JG_DEMOS = window.JG_DEMOS || {};
    window.JG_DEMOS.tracks = { animal: "deer", difficulty: 0.4, jobColor: [200, 140, 80] };
    window.JG_DEMOS.scope = { animal: "deer", name: "Ciervo", difficulty: 0.5, wind: 0.4, distance: 120, jobColor: [200, 140, 80] };
    window.JG_DEMOS.skin = { animal: "deer", points: 7, jobColor: [200, 140, 80] };
})();
