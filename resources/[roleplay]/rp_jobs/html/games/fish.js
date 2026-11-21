/*
 * rp_jobs / games/fish.js
 *   fish  1) lanzar: mantén pulsado y suelta con la barra en la zona verde
 *         2) esperar: no piques a los amagos; cuando se hunda la boya, ¡clic!
 *         3) recoger: mantén pulsado para subir la zona verde y que el pez quede dentro
 *   -> { caught, reason: "early"|"late"|"escaped"|"line" }
 *   Con params.reelOnly (lo normal en el juego: el lanzamiento y la picada se hacen en el mundo)
 *   empieza directamente en la fase 3.
 */
(function () {
    "use strict";
    JG.register("fish", {
        title: "Pescando",
        help: "Mantén pulsado para cargar el lanzamiento y suelta en la zona verde.",
        start: function (stage, p, api) {
            if (p.sea) stage.classList.add("sea");
            var diff = p.difficulty || 0.4, phase = "cast", power = 0, dirUp = true, down = false;
            var pw = api.el("div", "power"), good = api.el("div", "good"), fill = api.el("div", "fill");
            good.style.bottom = "70%"; good.style.height = "20%";
            pw.appendChild(good); pw.appendChild(fill); stage.appendChild(pw);
            var bobber = api.el("div", "bobber"), quality = 0.5;

            api.on(stage, "mousedown", function () {
                down = true;
                if (phase === "wait") return strike();
            });
            api.on(document, "mouseup", function () {
                down = false;
                if (phase === "cast" && power > 0.02) cast();
            });

            function cast() {
                phase = "flying";
                quality = (power >= 0.7 && power <= 0.9) ? 1 : (1 - Math.min(1, Math.abs(power - 0.8) * 2));
                api.flash(quality >= 1 ? "¡Lanzamiento perfecto!" : "Lanzamiento", quality >= 1 ? "good" : "");
                pw.parentNode.removeChild(pw);
                var bx = 300 + power * 400;
                bobber.style.left = bx + "px"; bobber.style.top = "160px";
                stage.appendChild(bobber);
                api.sfx("splash");
                ripple(bx);
                api.after(500, wait);
            }

            function ripple(x) {
                var r = api.el("div", "ripple");
                r.style.left = x + "px"; r.style.top = "180px";
                stage.appendChild(r);
                setTimeout(function () { if (r.parentNode) r.parentNode.removeChild(r); }, 1000);
            }

            var biteAt = 0, realBite = false;
            function wait() {
                phase = "wait";
                api.help("Espera a que la boya se hunda del todo. Si pica de mentira y tiras, se espanta.");
                var fakes = p.fakes || 0, delay = 0;
                for (var i = 0; i < fakes; i++) {
                    delay += api.rand(900, 2000);
                    api.after(delay, function () { bobber.style.top = "166px"; ripple(parseFloat(bobber.style.left)); api.after(160, function () { bobber.style.top = "160px"; }); });
                }
                delay += api.rand(1200, 3200);
                api.after(delay, function () {
                    realBite = true; biteAt = performance.now();
                    bobber.style.top = "184px";
                    var b = api.el("div", "bite", "!");
                    b.style.left = (parseFloat(bobber.style.left) - 10) + "px"; b.style.top = "80px";
                    stage.appendChild(b);
                    api.sfx("tick");
                    api.after(p.biteWindow || 800, function () {
                        if (phase === "wait") { phase = "end"; api.flash("Se escapó", "bad"); api.done({ caught: false, reason: "late" }); }
                    });
                });
            }

            function strike() {
                if (!realBite) { phase = "end"; api.flash("¡Muy pronto!", "bad"); return api.done({ caught: false, reason: "early" }); }
                if (performance.now() - biteAt > (p.biteWindow || 800)) return;
                stage.querySelectorAll(".bite").forEach(function (n) { n.parentNode.removeChild(n); });
                reel();
            }

            function reel() {
                phase = "reel";
                api.help("Mantén pulsado para subir la zona verde y que el pez quede dentro. Si lo pierdes, la barra baja.");
                var bar = api.el("div", "reel"), zone = api.el("div", "zone"), fishy = api.el("div", "fishy emoji", "🐟");
                var prog = api.el("div", "progress"), pfill = api.el("div");
                bar.appendChild(zone); bar.appendChild(fishy); prog.appendChild(pfill);
                stage.appendChild(bar); stage.appendChild(prog);
                var H = 420, zh = 70 + quality * 40 - diff * 20, zy = H - zh, zv = 0;
                var fy = H / 2, ftarget = fy, progress = 0.3, tension = 0;
                api.loop(function (dt) {
                    // zona verde con física simple
                    zv += (down ? -900 : 700) * dt;
                    zv = Math.max(-420, Math.min(420, zv));
                    zy += zv * dt;
                    if (zy < 0) { zy = 0; zv = 0; } if (zy > H - zh) { zy = H - zh; zv = 0; }
                    // el pez se mueve más nervioso según la dificultad
                    if (Math.random() < 0.02 + diff * 0.05) ftarget = api.rand(15, H - 15);
                    fy += (ftarget - fy) * Math.min(1, dt * (1.5 + diff * 5));
                    zone.style.top = zy + "px"; zone.style.height = zh + "px";
                    fishy.style.top = fy + "px";
                    var inside = fy >= zy && fy <= zy + zh;
                    progress += (inside ? 0.28 : -0.2 - diff * 0.1) * dt;
                    // tirar con el pez fuera de la zona tensa el sedal
                    tension = Math.max(0, tension + ((down && !inside) ? 0.5 : -0.4) * dt);
                    pfill.style.height = (Math.max(0, Math.min(1, progress)) * 100) + "%";
                    if (progress >= 1) { phase = "end"; api.sfx("good"); api.flash("¡Lo tienes!", "good"); api.done({ caught: true }); }
                    else if (tension >= 1) { phase = "end"; api.sfx("bad"); api.flash("¡Se rompió el sedal!", "bad"); api.done({ caught: false, reason: "line" }); }
                    else if (progress <= 0) { phase = "end"; api.flash("Se escapó", "bad"); api.done({ caught: false, reason: "escaped" }); }
                });
            }

            api.loop(function (dt) {
                if (phase !== "cast") return;
                if (down) {
                    power += (dirUp ? 1 : -1) * dt * 0.9;
                    if (power >= 1) { power = 1; dirUp = false; } if (power <= 0) { power = 0; dirUp = true; }
                }
                fill.style.height = (power * 100) + "%";
            });
            if (p.reelOnly) { pw.parentNode.removeChild(pw); reel(); }
            api.timer(45, function () { if (phase !== "end") api.done({ caught: false, reason: "escaped" }); });
        }
    });

    window.JG_DEMOS = window.JG_DEMOS || {};
    window.JG_DEMOS.fish = { difficulty: 0.5, sea: false, biteWindow: 900, fakes: 1, reelOnly: true, jobColor: [70, 170, 230] };
})();
