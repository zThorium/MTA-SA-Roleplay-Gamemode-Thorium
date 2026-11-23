/* rp_backpacks UI. Acciones via mta.triggerEvent: rp:bp:ui:put / take / drop / close. */
(function () {
    function send() {
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, arguments);
    }
    function $(id) { return document.getElementById(id); }

    // Icono vectorial (iconImg) o emoji
    function iconNode(item, className) {
        var node = document.createElement("span");
        node.className = className;
        if (item.iconImg) {
            var img = document.createElement("img");
            img.src = item.iconImg;
            img.draggable = false;
            node.appendChild(img);
        } else {
            node.textContent = item.icon || "";
        }
        return node;
    }

    function fill(listId, items, action, shift) {
        var list = $(listId);
        list.innerHTML = "";
        if (!items.length) {
            var empty = document.createElement("div");
            empty.className = "empty";
            empty.textContent = "Vacio";
            list.appendChild(empty);
            return;
        }
        items.forEach(function (item) {
            var row = document.createElement("div");
            row.className = "row";
            row.appendChild(iconNode(item, "ico"));
            [["span", "name", item.name], ["span", "qty", "x" + item.amount],
             ["span", "kg", (item.weight * item.amount).toFixed(2) + " kg"]].forEach(function (c) {
                var el = document.createElement(c[0]);
                el.className = c[1];
                el.textContent = c[2];
                row.appendChild(el);
            });
            row.addEventListener("click", function (e) { send(action, item.id, e.shiftKey ? item.amount : 1); });
            list.appendChild(row);
        });
    }

    window.RP = {
        render: function (d) {
            $("title").textContent = d.name;
            var head = $("bp-icon");
            head.innerHTML = "";
            head.appendChild(iconNode(d, "ico big"));
            $("weight-label").textContent = d.used.toFixed(1) + " / " + d.capacity + " kg";
            $("weight-bar").style.width = Math.min(100, d.capacity > 0 ? (d.used / d.capacity) * 100 : 0) + "%";
            fill("bp-list", d.items, "rp:bp:ui:take");
            fill("inv-list", d.inv, "rp:bp:ui:put");
        }
    };

    $("btn-close").addEventListener("click", function () { send("rp:bp:ui:close"); });
    $("btn-drop").addEventListener("click", function () { send("rp:bp:ui:drop"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" || e.key === "o" || e.key === "O") send("rp:bp:ui:close");
    });
})();
