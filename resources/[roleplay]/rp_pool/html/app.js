/*
 * rp_pool / app.js
 * Lua llama a RP.showTable(data), RP.setBoard(data) y RP.showBoardTab().
 * Eventos hacia Lua: rp:pool:ui:create(bet), join, leave, board, close.
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };

    var state = { data: null, bet: 0, board: null, tab: "table" };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);   // vista previa en un navegador normal
    }

    function el(tag, className, text) {
        var n = document.createElement(tag);
        if (className) n.className = className;
        if (text !== undefined) n.textContent = text;   // textContent: nunca innerHTML con datos de jugadores
        return n;
    }

    function money(n) {
        return "$" + Number(n || 0).toLocaleString("es");
    }

    function setTab(tab) {
        state.tab = tab;
        ["table", "wins", "money"].forEach(function (t) {
            $("view-" + t).classList.toggle("hidden", t !== tab);
            $("tab-" + t).classList.toggle("active", t === tab);
        });
        if (tab !== "table") send("rp:pool:ui:board");
    }

    function parseBet() {
        var raw = $("bet-input").value.replace(/[^0-9]/g, "");
        return raw === "" ? 0 : parseInt(raw, 10);
    }

    function refreshPot() {
        var d = state.data;
        if (!d) return;
        var bet = d.status === "idle" ? state.bet : d.bet;
        $("pot").textContent = money(bet * 2);
        $("money").textContent = money(d.money);
        var btn = $("btn-create");
        btn.disabled = state.bet > d.money || state.bet > d.maxBet;
        btn.textContent = state.bet > 0 ? "Crear partida (" + money(state.bet) + ")" : "Crear partida amistosa";
        Array.prototype.forEach.call(document.querySelectorAll(".chip"), function (c) {
            var v = parseInt(c.getAttribute("data-bet"), 10);
            c.classList.toggle("selected", v === state.bet);
            c.classList.toggle("disabled", v > d.money);
        });
    }

    function selectBet(v) {
        state.bet = v;
        $("bet-input").value = v > 0 ? String(v) : "";
        refreshPot();
    }

    function renderTable() {
        var d = state.data;
        if (!d) return;
        var status = $("table-status");
        status.textContent = "";
        $("subtitle").textContent = "Mesa #" + d.tableId;

        var showBet = false, showCreate = false, showJoin = false, showCancel = false;
        if (d.busyWith) {
            status.appendChild(el("span", null, "Ya estás en otra partida de pool."));
        } else if (d.status === "idle") {
            status.appendChild(el("span", null, "Mesa libre. Crea una partida y espera a que otro jugador acepte tu apuesta."));
            showBet = true; showCreate = true;
        } else if (d.status === "waiting" && d.mine === "waiting") {
            status.appendChild(el("span", null, "Esperando rival con apuesta de "));
            status.appendChild(el("b", null, money(d.bet)));
            status.appendChild(el("span", null, ". Puedes cancelar y se te devuelve el dinero."));
            showCancel = true;
        } else if (d.status === "waiting") {
            status.appendChild(el("b", null, d.waitingName || "Un jugador"));
            status.appendChild(el("span", null, " busca rival. Apuesta: "));
            status.appendChild(el("b", null, money(d.bet)));
            status.appendChild(el("span", null, ". Si aceptas, ambos ponéis la apuesta y el ganador se lleva " + money(d.bet * 2) + "."));
            showJoin = true;
        } else {
            status.appendChild(el("span", null, "Esta mesa está ocupada con una partida en curso."));
        }
        $("bet-box").style.display = showBet ? "" : "none";
        $("btn-create").style.display = showCreate ? "" : "none";
        $("btn-join").style.display = showJoin ? "" : "none";
        $("btn-cancel").style.display = showCancel ? "" : "none";
        if (showJoin) {
            $("btn-join").disabled = d.money < d.bet;
            $("btn-join").textContent = d.money < d.bet ? "No tienes " + money(d.bet) + " en mano" : "Aceptar apuesta y jugar (" + money(d.bet) + ")";
        }

        var chips = $("chips");
        chips.textContent = "";
        (d.bets || [0]).forEach(function (v) {
            var c = el("div", "chip", v === 0 ? "Amistoso" : money(v));
            c.setAttribute("data-bet", String(v));
            c.addEventListener("click", function () {
                if (v <= d.money) selectBet(v);
            });
            chips.appendChild(c);
        });
        refreshPot();
    }

    function rankRow(i, cols, mine) {
        var tr = el("tr", mine ? "mine" : "");
        tr.appendChild(el("td", "pos", String(i)));
        cols.forEach(function (c, idx) {
            var td = el("td", c.cls || "", c.text);
            tr.appendChild(td);
        });
        return tr;
    }

    function renderBoard() {
        var b = state.board;
        if (!b) return;
        var myName = b.me ? b.me.name : null;

        var tw = $("rank-wins").querySelector("tbody");
        tw.textContent = "";
        var wins = b.wins || [];
        wins.forEach(function (r, i) {
            var pct = r.games > 0 ? Math.round(r.wins * 100 / r.games) + "%" : "-";
            tw.appendChild(rankRow(i + 1, [
                { text: r.name },
                { text: String(r.wins), cls: "num" },
                { text: String(r.losses), cls: "num" },
                { text: pct, cls: "num" }
            ], r.name === myName));
        });
        if (!wins.length) {
            var e1 = el("tr"); var c1 = el("td", "empty", "Todavía nadie ha ganado partidas de pool."); c1.colSpan = 5; e1.appendChild(c1); tw.appendChild(e1);
        }

        var tm = $("rank-money").querySelector("tbody");
        tm.textContent = "";
        var rich = b.money || [];
        rich.forEach(function (r, i) {
            tm.appendChild(rankRow(i + 1, [
                { text: r.name },
                { text: money(r.money_won), cls: "num money" },
                { text: String(r.wins), cls: "num" },
                { text: String(r.games), cls: "num" }
            ], r.name === myName));
        });
        if (!rich.length) {
            var e2 = el("tr"); var c2 = el("td", "empty", "Todavía nadie ha ganado dinero apostando."); c2.colSpan = 5; e2.appendChild(c2); tm.appendChild(e2);
        }

        var me = b.me;
        var mw = $("me-wins"), mm = $("me-money");
        mw.textContent = ""; mm.textContent = "";
        if (me) {
            mw.appendChild(el("span", null, "Tu posición: "));
            mw.appendChild(el("b", null, "#" + me.rank_wins));
            mw.appendChild(el("span", null, "  ·  " + me.wins + " victorias, " + me.losses + " derrotas"));
            mm.appendChild(el("span", null, "Tu posición: "));
            mm.appendChild(el("b", null, "#" + me.rank_money));
            mm.appendChild(el("span", null, "  ·  ganado " + money(me.money_won) + ", perdido " + money(me.money_lost) + ", mejor apuesta ganada " + money(me.best_win)));
        } else {
            mw.textContent = "Aún no has jugado ninguna partida: gana una para entrar en el ranking.";
            mm.textContent = "Aún no has jugado ninguna partida: gana una apuesta para entrar en el ranking.";
        }
    }

    $("tab-table").addEventListener("click", function () { setTab("table"); });
    $("tab-wins").addEventListener("click", function () { setTab("wins"); });
    $("tab-money").addEventListener("click", function () { setTab("money"); });
    $("btn-close").addEventListener("click", function () { send("rp:pool:ui:close"); });
    $("btn-create").addEventListener("click", function () { send("rp:pool:ui:create", state.bet); });
    $("btn-join").addEventListener("click", function () { send("rp:pool:ui:join"); });
    $("btn-cancel").addEventListener("click", function () { send("rp:pool:ui:leave"); });
    $("bet-input").addEventListener("input", function () {
        var v = parseBet();
        if (state.data && v > state.data.maxBet) v = state.data.maxBet;
        state.bet = v;
        refreshPot();
    });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") send("rp:pool:ui:close");
    });

    window.RP = {
        showTable: function (data) {
            state.data = data;
            state.bet = 0;
            $("bet-input").value = "";
            setTab("table");
            renderTable();
        },
        showBoardTab: function () {
            $("tab-table").style.display = "none";
            setTab("wins");
        },
        setBoard: function (data) {
            state.board = data;
            renderBoard();
        }
    };

    // Vista previa en navegador normal
    if (!(window.mta && typeof mta.triggerEvent === "function")) {
        window.RP.showTable({ tableId: 1, status: "idle", mine: "none", bet: 0, money: 2500, bets: [0, 10, 50, 100, 250, 500, 1000, 5000], maxBet: 100000 });
        window.RP.setBoard({
            wins: [{ name: "Juan Pérez", wins: 12, losses: 4, games: 16, money_won: 4500 }, { name: "Ana Soto", wins: 9, losses: 2, games: 11, money_won: 6000 }],
            money: [{ name: "Ana Soto", wins: 9, games: 11, money_won: 6000 }, { name: "Juan Pérez", wins: 12, games: 16, money_won: 4500 }],
            me: { name: "Juan Pérez", wins: 12, losses: 4, games: 16, money_won: 4500, money_lost: 900, best_win: 1000, rank_wins: 1, rank_money: 2 }
        });
    }
})();
