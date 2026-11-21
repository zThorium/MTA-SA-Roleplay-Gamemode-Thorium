/*
 * rp_jobs / games/lumber.js
 *   fell  elegir hacia dónde cae el árbol (evitando obstáculos) y talar en el momento justo
 *         -> { dir: 0..7, hits, misses }
 *   saw   seguir la línea de corte con la sierra moviendo el ratón -> { cuts: [0..1 por tronco] }
 */
(function () {
    "use strict";
    var OBST = { road: "🛣️", cabin: "🏠", tree: "🌲", powerline: "⚡", rocks: "🪨", creek: "🏞️" };
    var NAMES = { road: "camino", cabin: "cabaña", tree: "otro árbol", powerline: "tendido eléctrico", rocks: "rocas", creek: "arroyo" };
    var ARROWS = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"];

    JG.register("fell", {
        title: "Talar el árbol",
        help: "Primero elige hacia dónde caerá: evita el camino, la cabaña, los cables y lo que haya alrededor.",
        start: function (stage, p, api) {
            var dir = null, hits = 0, misses = 0, need = p.hits || 5;
            var compass = api.el("div", "compass");
            compass.appendChild(api.el("div", "trunk"));
            (p.dirs || []).forEach(function (d) {
                var a = d.dir * Math.PI / 4;
                var b = api.el("div", "dir emoji", d.obstacle ? OBST[d.obstacle] : "");
                b.style.left = (200 + Math.sin(a) * 150) + "px";
                b.style.top = (200 - Math.cos(a) * 150) + "px";
                b.title = d.obstacle ? ("Hay " + NAMES[d.obstacle]) : "Libre";
                var ar = api.el("div", "arrow", ARROWS[d.dir]);
                ar.style.top = "-18px";
                b.appendChild(ar);
                b.addEventListener("click", function () { choose(d); });
                compass.appendChild(b);
            });
            stage.appendChild(compass);

            function choose(d) {
                dir = d.dir;
                if (d.obstacle) api.flash("Caerá sobre " + NAMES[d.obstacle] + "...", "bad"); else api.flash("Buena dirección", "good");
                compass.parentNode.removeChild(compass);
                chop();
            }

            function chop() {
                api.help("Haz clic o pulsa Espacio cuando la aguja esté en la zona verde. Necesitas " + need + " hachazos buenos.");
                var trunk = api.el("div", "trunk-side");
                var notch = api.el("div", "notch");
                trunk.appendChild(notch);
                stage.appendChild(trunk);
                var wrap = api.el("div", "chop-wrap"), bar = api.el("div", "chop-bar");
                var zone = api.el("div", "chop-zone"), needle = api.el("div", "chop-needle");
                bar.appendChild(zone); bar.appendChild(needle); wrap.appendChild(bar);
                stage.appendChild(wrap);
                var zx = 0, zw = 0.22, t = 0, speed = 1.1 * (p.speed || 1);
                function newZone() { zw = Math.max(0.08, 0.22 - hits * 0.025); zx = api.rand(0.05, 0.95 - zw); zone.style.left = (zx * 100) + "%"; zone.style.width = (zw * 100) + "%"; }
                newZone();
                var pos = 0;
                api.loop(function (dt) {
                    t += dt * speed;
                    pos = (Math.sin(t * 2.2) + 1) / 2;
                    needle.style.left = (pos * 100) + "%";
                });
                function swing() {
                    if (pos >= zx && pos <= zx + zw) { hits++; api.sfx("hit"); notch.style.width = (hits / need * 75) + "px"; newZone(); speed += 0.12; }
                    else { misses++; api.sfx("miss"); api.flash("¡Fallo!", "bad"); }
                    if (hits >= need) { api.flash("¡Madera va!", "good"); api.done({ dir: dir, hits: hits, misses: misses, delay: 900 }); }
                }
                api.on(stage, "mousedown", swing);
                api.on(document, "keydown", function (e) { if (e.code === "Space") { e.preventDefault(); swing(); } });
                api.timer(25, function () { api.done({ dir: dir, hits: hits, misses: misses + (need - hits) }); });
            }
        }
    });

    JG.register("saw", {
        title: "Aserradero",
        help: "Mueve el ratón arriba y abajo para que la sierra siga la línea de corte de cada tronco.",
        start: function (stage, p, api) {
            var logs = p.logs || 3, index = 0, cuts = [], mouseY = 260, samples = 0, error = 0, offset = 0;
            var NS = "http://www.w3.org/2000/svg";
            var log = api.el("div", "saw-log");
            stage.appendChild(log);
            var svg = document.createElementNS(NS, "svg");
            svg.setAttribute("class", "saw-svg"); svg.setAttribute("width", "880"); svg.setAttribute("height", "520");
            var path = document.createElementNS(NS, "path");
            path.setAttribute("fill", "none"); path.setAttribute("stroke", "#fff"); path.setAttribute("stroke-width", "3"); path.setAttribute("stroke-dasharray", "10 8");
            svg.appendChild(path); stage.appendChild(svg);
            var blade = api.el("div", "saw-blade");
            stage.appendChild(blade);
            var line = api.el("div", "hud-line");
            stage.appendChild(line);
            var amp, freq, phase;
            function newLog() {
                amp = api.rand(25, 70); freq = api.rand(0.006, 0.013) * (p.speed || 1); phase = api.rand(0, 6);
                offset = -900; samples = 0; error = 0;
                line.textContent = "Tronco " + (index + 1) + "/" + logs;
            }
            function curveY(worldX) { return 260 + Math.sin(worldX * freq + phase) * amp; }
            newLog();
            api.on(stage, "mousemove", function (e) { mouseY = api.pos(e).y; });
            api.loop(function (dt) {
                offset += 180 * dt;
                log.style.left = (-offset + 0) + "px"; log.style.width = "900px";
                var d = "";
                for (var x = 0; x <= 880; x += 10) {
                    var wx = x + offset;
                    if (wx < 0 || wx > 900) continue;
                    d += (d ? " L " : "M ") + x + " " + curveY(wx).toFixed(1);
                }
                path.setAttribute("d", d);
                blade.style.top = mouseY + "px";
                var bx = 180 + offset;
                if (bx >= 0 && bx <= 900) { samples++; error += Math.min(1, Math.abs(mouseY - curveY(bx)) / 60); }
                if (offset > 900 - 180 + 40) {
                    var acc = samples ? 1 - error / samples : 0;
                    cuts.push(Math.max(0, Math.round(acc * 100) / 100));
                    api.flash(Math.round(acc * 100) + "%", acc > 0.7 ? "good" : "bad");
                    index++;
                    if (index >= logs) return api.done({ cuts: cuts, delay: 900 });
                    newLog();
                }
            });
        }
    });

    window.JG_DEMOS = window.JG_DEMOS || {};
    window.JG_DEMOS.fell = { hits: 5, speed: 1, jobColor: [170, 120, 70], dirs: [
        { dir: 0, obstacle: "powerline" }, { dir: 1, obstacle: false }, { dir: 2, obstacle: "road" }, { dir: 3, obstacle: false },
        { dir: 4, obstacle: "cabin" }, { dir: 5, obstacle: false }, { dir: 6, obstacle: "tree" }, { dir: 7, obstacle: false }] };
    window.JG_DEMOS.saw = { logs: 3, speed: 1, jobColor: [170, 120, 70] };
})();
