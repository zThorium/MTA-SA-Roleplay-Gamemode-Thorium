/*
 * rp_jobs / games/garbage.js
 * "compactor": vista del interior del camión. Arrastra las bolsas al compactador, los
 * reciclables al contenedor verde y lo de valor (escondido bajo las bolsas) a tu bolsillo.
 * No toques las jeringas. Resultado: { compacted, recycled, hazards, found: [índices] }
 */
(function () {
    "use strict";
    var LOOSE = ["🥫", "🧴", "🍾", "📦", "🥤"];

    JG.register("compactor", {
        title: "Interior del camión",
        help: "Arrastra las bolsas al compactador y los reciclables al contenedor verde. Lo que brille, a tu bolsillo. ¡No toques las jeringas!",
        start: function (stage, p, api) {
            var el = api.el;
            var stats = { compacted: 0, recycled: 0, hazards: 0, found: [] };
            var remaining = 0, dragging = null, z = 10;

            stage.appendChild(el("div", "cmp-ribs"));
            var press = el("div", "cmp-zone cmp-press", "Compactador");
            var plate = el("div", "cmp-plate");
            var count = el("div", "cmp-count", "0");
            press.appendChild(plate); press.appendChild(count);
            var recycle = el("div", "cmp-zone cmp-recycle", "♻ Reciclaje");
            var pocket = el("div", "cmp-zone cmp-pocket", "💼 Tu bolsillo");
            stage.appendChild(press); stage.appendChild(recycle); stage.appendChild(pocket);
            var line = el("div", "hud-line");
            stage.appendChild(line);

            function updateLine() {
                line.innerHTML = "";
                line.appendChild(document.createTextNode("Compactado "));
                line.appendChild(el("b", null, String(stats.compacted)));
                line.appendChild(document.createTextNode(" · Reciclado "));
                line.appendChild(el("b", null, String(stats.recycled)));
                if (stats.found.length) {
                    line.appendChild(document.createTextNode(" · Hallazgos "));
                    line.appendChild(el("b", null, String(stats.found.length)));
                }
            }
            updateLine();

            // Zona de la pila: x 170..560, y 40..470
            function spot(w, h) { return { x: api.rand(175, 560 - w), y: api.rand(50, 460 - h) }; }
            function place(node, kind, data, w, h, zi) {
                var s = spot(w, h);
                node.style.left = s.x + "px"; node.style.top = s.y + "px";
                node.style.zIndex = zi;
                node._kind = kind; node._data = data;
                stage.appendChild(node);
                return node;
            }

            // Hallazgos y jeringas debajo; bolsas encima (hay que moverlas para ver)
            (p.finds || []).forEach(function (f, i) {
                var n = el("div", "cmp-item cmp-find emoji", f.icon || "❔");
                n.title = f.name || "";
                place(n, "find", i + 1, 60, 60, 2);
            });
            for (var h = 0; h < (p.hazards || 0); h++) place(el("div", "cmp-item cmp-hazard emoji", "💉"), "hazard", null, 50, 50, 3);
            for (var r = 0; r < (p.recyclables || 0); r++) {
                place(el("div", "cmp-item cmp-loose emoji", LOOSE[api.randInt(0, LOOSE.length - 1)]), "recycle", null, 56, 56, 5 + r);
                remaining++;
            }
            for (var b = 0; b < (p.bags || 3); b++) {
                place(el("div", "cmp-item cmp-bag" + (Math.random() < 0.35 ? " green" : "")), "bag", null, 92, 82, 20 + b);
                remaining++;
            }
            // Asegura que cada hallazgo quede tapado por una bolsa
            var bags = stage.querySelectorAll(".cmp-bag");
            Array.prototype.forEach.call(stage.querySelectorAll(".cmp-find"), function (f, i) {
                var bag = bags[i % bags.length];
                if (bag) { f.style.left = (parseFloat(bag.style.left) + 16) + "px"; f.style.top = (parseFloat(bag.style.top) + 12) + "px"; }
            });

            function zoneAt(x, y) {
                var zones = [[press, "press"], [recycle, "recycle"], [pocket, "pocket"]];
                for (var i = 0; i < zones.length; i++) {
                    var r = zones[i][0].getBoundingClientRect();
                    if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return zones[i];
                }
                return null;
            }

            function squash() {
                press.classList.add("squash");
                api.sfx("squish");
                setTimeout(function () { press.classList.remove("squash"); }, 300);
                count.textContent = String(stats.compacted);
            }

            function remove(node) { if (node.parentNode) node.parentNode.removeChild(node); }

            function checkEnd() {
                var findsLeft = stage.querySelectorAll(".cmp-find").length;
                if (remaining <= 0 && findsLeft === 0) finish();
            }

            function finish() {
                api.flash("¡Listo!", "good");
                api.done(stats);
            }

            api.on(stage, "mousedown", function (e) {
                var t = e.target.closest ? e.target.closest(".cmp-item") : null;
                if (!t) return;
                if (t._kind === "hazard") {
                    stats.hazards++;
                    t.classList.remove("hurt"); void t.offsetWidth; t.classList.add("hurt");
                    api.sfx("bad");
                    api.flash("¡Te pinchaste!", "bad");
                    t._kind = "spent";
                    return;
                }
                if (t._kind === "spent") return;
                var pos = api.pos(e);
                dragging = { node: t, dx: pos.x - parseFloat(t.style.left), dy: pos.y - parseFloat(t.style.top) };
                t.classList.add("dragging");
                t.style.zIndex = ++z + 100;
                e.preventDefault();
            });
            api.on(document, "mousemove", function (e) {
                if (!dragging) return;
                var pos = api.pos(e);
                dragging.node.style.left = (pos.x - dragging.dx) + "px";
                dragging.node.style.top = (pos.y - dragging.dy) + "px";
                [press, recycle, pocket].forEach(function (zn) { zn.classList.remove("over"); });
                var zn = zoneAt(e.clientX, e.clientY);
                if (zn) zn[0].classList.add("over");
            });
            api.on(document, "mouseup", function (e) {
                if (!dragging) return;
                var node = dragging.node;
                dragging = null;
                node.classList.remove("dragging");
                [press, recycle, pocket].forEach(function (zn) { zn.classList.remove("over"); });
                var zn = zoneAt(e.clientX, e.clientY);
                if (!zn) return;
                var kind = node._kind, target = zn[1];
                if (kind === "bag" && target === "press") { stats.compacted++; remaining--; remove(node); squash(); }
                else if (kind === "recycle" && target === "recycle") { stats.recycled++; remaining--; remove(node); api.sfx("good"); }
                else if (kind === "recycle" && target === "press") { stats.compacted++; remaining--; remove(node); squash(); }
                else if (kind === "find" && target === "pocket") { stats.found.push(node._data); remove(node); api.sfx("good"); api.flash("¡Algo de valor!", "good"); }
                else if (kind === "find" && target === "press") { remove(node); squash(); api.flash("Lo aplastaste...", "bad"); }
                else { api.sfx("miss"); return; }
                updateLine();
                checkEnd();
            });

            var done = el("button", "btn primary", "Cerrar la compuerta");
            done.addEventListener("click", finish);
            api.foot([done]);
            api.timer(p.time || 30, finish);
        }
    });

    window.JG_DEMOS = window.JG_DEMOS || {};
    window.JG_DEMOS.compactor = { bags: 5, recyclables: 3, hazards: 2, time: 30, jobColor: [120, 200, 90],
        finds: [{ item: "gold_ring", icon: "💍", name: "Anillo de oro" }, { cash: 120, icon: "💵", name: "Fajo" }] };
})();
