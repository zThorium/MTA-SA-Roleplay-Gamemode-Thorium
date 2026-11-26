/*
 * rp_pizzeria / pizza.js
 * Dibujo en canvas: masa, salsa, queso, ingredientes, tostado y cortes.
 * Coordenadas de ingredientes normalizadas al centro (radio 1 = borde interior de la masa).
 */
(function () {
    "use strict";

    var NAMES = {
        pepperoni: "Pepperoni", mushroom: "Champiñones", olive: "Aceitunas", pepper: "Pimentón",
        onion: "Cebolla", ham: "Jamón", pineapple: "Piña", sausage: "Salchicha"
    };
    var ZONES = { whole: "entera", left: "mitad izq.", right: "mitad der." };
    var BAKE = { poco: "poco hecha", normal: "normal", bien: "bien hecha" };
    var SIDES = { fries: "Papas fritas", garlic: "Palitos de ajo" };

    // Semilla fija por pieza para que la rotacion no cambie al redibujar
    function rnd(x, y) { var s = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453; return s - Math.floor(s); }

    function circle(ctx, x, y, r, fill) { ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fillStyle = fill; ctx.fill(); }

    function topping(ctx, id, x, y, s) {
        var rot = rnd(x, y) * Math.PI * 2;
        ctx.save(); ctx.translate(x, y); ctx.rotate(rot);
        switch (id) {
        case "pepperoni":
            circle(ctx, 0, 0, s, "#b3261e"); circle(ctx, 0, 0, s * 0.82, "#cf3a2c");
            circle(ctx, -s * .35, -s * .2, s * .12, "#8f1d16"); circle(ctx, s * .3, s * .25, s * .1, "#8f1d16"); circle(ctx, s * .1, -s * .45, s * .09, "#8f1d16");
            break;
        case "mushroom":
            ctx.beginPath(); ctx.arc(0, -s * .1, s * .8, Math.PI, 0); ctx.fillStyle = "#e7d7bd"; ctx.fill();
            ctx.fillStyle = "#cdb48f"; ctx.fillRect(-s * .25, -s * .1, s * .5, s * .75);
            ctx.strokeStyle = "#a88a61"; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(0, -s * .1, s * .8, Math.PI, 0); ctx.stroke();
            break;
        case "olive":
            circle(ctx, 0, 0, s * .62, "#1d1d1f"); circle(ctx, 0, 0, s * .28, "#6b4a3a");
            break;
        case "pepper":
            ctx.strokeStyle = "#2f9e44"; ctx.lineWidth = s * .38; ctx.lineCap = "round";
            ctx.beginPath(); ctx.arc(0, s * .5, s * .9, Math.PI * 1.15, Math.PI * 1.85); ctx.stroke();
            break;
        case "onion":
            ctx.strokeStyle = "#9c5bb5"; ctx.lineWidth = s * .2;
            ctx.beginPath(); ctx.arc(0, 0, s * .75, 0, Math.PI * 1.6); ctx.stroke();
            ctx.strokeStyle = "#e4c9ee"; ctx.lineWidth = s * .1;
            ctx.beginPath(); ctx.arc(0, 0, s * .5, 0, Math.PI * 1.4); ctx.stroke();
            break;
        case "ham":
            ctx.fillStyle = "#f2a3a8"; ctx.fillRect(-s * .7, -s * .55, s * 1.4, s * 1.1);
            ctx.fillStyle = "#e48890"; ctx.fillRect(-s * .7, s * .3, s * 1.4, s * .25);
            break;
        case "pineapple":
            ctx.beginPath(); ctx.moveTo(0, -s * .8); ctx.lineTo(s * .75, s * .6); ctx.lineTo(-s * .75, s * .6); ctx.closePath();
            ctx.fillStyle = "#f6d25a"; ctx.fill(); ctx.strokeStyle = "#d9a920"; ctx.lineWidth = 2; ctx.stroke();
            break;
        case "sausage":
            circle(ctx, 0, 0, s * .7, "#7a4a2a"); circle(ctx, -s * .2, -s * .15, s * .15, "#a66a3f"); circle(ctx, s * .25, s * .2, s * .12, "#5a3420");
            break;
        }
        ctx.restore();
    }

    // Base completa. opts: { sauce: bool|cells, cheese: bool|cells, items, ratio (tostado), cuts, grid }
    function draw(ctx, cx, cy, R, opts) {
        opts = opts || {};
        var inner = R * 0.88;
        // masa y borde
        var crust = "#e9c48a", dough = "#f3dcae";
        var r = opts.ratio;
        if (r !== undefined && r !== null) {
            if (r < 0.85) { crust = "#efd6a6"; dough = "#f6e6c3"; }
            else if (r <= 1.2) { crust = "#d39a52"; dough = "#f0cf92"; }
            else if (r < 1.7) { crust = "#9c5f26"; dough = "#d9a865"; }
            else { crust = "#3b2a1e"; dough = "#6b4a2e"; }
        }
        circle(ctx, cx, cy, R, crust);
        circle(ctx, cx, cy, inner, dough);

        ctx.save();
        ctx.beginPath(); ctx.arc(cx, cy, inner, 0, Math.PI * 2); ctx.clip();
        layer(ctx, cx, cy, inner, opts.sauce, "#c8321f", "#b02a1a", opts.grid);
        layer(ctx, cx, cy, inner, opts.cheese, "#f8d76a", "#f2c94c", opts.grid);
        if (r !== undefined && r !== null && r >= 1.7) { ctx.fillStyle = "rgba(30,20,10,.55)"; ctx.fillRect(cx - R, cy - R, R * 2, R * 2); }
        ctx.restore();

        var s = R * 0.09;
        (opts.items || []).forEach(function (p) { topping(ctx, p.t, cx + p.x * inner, cy + p.y * inner, s); });

        if (opts.cuts) {
            ctx.save();
            ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.clip();
            ctx.strokeStyle = "rgba(60,30,10,.85)"; ctx.lineWidth = 3;
            opts.cuts.forEach(function (c) {
                ctx.beginPath(); ctx.moveTo(c.x1, c.y1); ctx.lineTo(c.x2, c.y2); ctx.stroke();
            });
            ctx.restore();
        }
    }

    // Capa de salsa o queso: true = completa; array de celdas pintadas = manchas
    function layer(ctx, cx, cy, inner, cells, a, b, grid) {
        if (!cells) return;
        if (cells === true) {
            circle(ctx, cx, cy, inner * 0.97, a);
            for (var i = 0; i < 40; i++) {
                var ang = rnd(i, 3) * Math.PI * 2, d = Math.sqrt(rnd(i, 7)) * inner * .9;
                circle(ctx, cx + Math.cos(ang) * d, cy + Math.sin(ang) * d, inner * .07, b);
            }
            return;
        }
        var n = grid, cell = (inner * 2) / n;
        for (var k in cells) {
            if (!cells.hasOwnProperty(k)) continue;
            var gx = k % n, gy = Math.floor(k / n);
            var x = cx - inner + (gx + .5) * cell, y = cy - inner + (gy + .5) * cell;
            circle(ctx, x, y, cell * 0.95, (gx + gy) % 3 === 0 ? b : a);
        }
    }

    // Mini pizza de comanda: ingredientes repartidos segun zona
    function mini(canvas, pizza) {
        var ctx = canvas.getContext("2d"), w = canvas.width, R = w / 2 - 2;
        ctx.clearRect(0, 0, w, w);
        var items = [];
        (pizza.toppings || []).forEach(function (t, ti) {
            for (var i = 0; i < t.count; i++) {
                var ang = rnd(i + ti * 10, ti + 1) * Math.PI * 2, d = 0.25 + rnd(ti, i + 3) * 0.6;
                var x = Math.cos(ang) * d, y = Math.sin(ang) * d;
                if (t.zone === "left") x = -Math.abs(x) - 0.08;
                if (t.zone === "right") x = Math.abs(x) + 0.08;
                items.push({ t: t.id, x: Math.max(-.85, Math.min(.85, x)), y: y });
            }
        });
        draw(ctx, w / 2, w / 2, R, { sauce: true, cheese: true, items: items });
        if ((pizza.toppings || []).some(function (t) { return t.zone !== "whole"; })) {
            ctx.strokeStyle = "rgba(0,0,0,.35)"; ctx.setLineDash([3, 3]);
            ctx.beginPath(); ctx.moveTo(w / 2, 2); ctx.lineTo(w / 2, w - 2); ctx.stroke(); ctx.setLineDash([]);
        }
    }

    function icon(canvas, id) {
        var ctx = canvas.getContext("2d"), w = canvas.width;
        ctx.clearRect(0, 0, w, w);
        if (id === "dough") { circle(ctx, w / 2, w / 2, w * .42, "#e9c48a"); circle(ctx, w / 2, w / 2, w * .34, "#f3dcae"); return; }
        if (id === "sauce") { circle(ctx, w / 2, w / 2, w * .4, "#c8321f"); circle(ctx, w * .4, w * .4, w * .1, "#e2553f"); return; }
        if (id === "cheese") {
            ctx.beginPath(); ctx.moveTo(w * .12, w * .75); ctx.lineTo(w * .88, w * .75); ctx.lineTo(w * .88, w * .4); ctx.closePath();
            ctx.fillStyle = "#f8d76a"; ctx.fill(); circle(ctx, w * .7, w * .6, w * .06, "#e3b93c"); return;
        }
        topping(ctx, id, w / 2, w / 2, w * .38);
    }

    window.PIZZA = { draw: draw, mini: mini, icon: icon, topping: topping, NAMES: NAMES, ZONES: ZONES, BAKE: BAKE, SIDES: SIDES };
})();
