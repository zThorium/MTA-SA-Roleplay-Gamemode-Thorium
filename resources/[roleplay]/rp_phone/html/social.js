/*
 * rp_phone / social.js  -  Fotogram (estilo Instagram) y la camara del telefono
 *
 * Lua -> RP.social.<metodo>(...)  (respuestas del servidor, ver client/c_social.lua)
 *        RP.camera.open / state / shot  (client/c_camera.lua)
 * JS  -> mta.triggerEvent("rp:phone:ui:social", accion, ...)
 *        mta.triggerEvent("rp:phone:ui:socialPost", pie, jpegBase64, filtro)
 *        mta.triggerEvent("rp:phone:ui:camera", accion, ...)
 *
 * Los textos de otros jugadores siempre con textContent (nunca innerHTML).
 */
(function () {
    "use strict";

    var P = window.Phone;
    var $ = P.$, el = P.el, send = P.send;

    function social() { send.apply(null, ["rp:phone:ui:social"].concat([].slice.call(arguments))); }
    function camera() { send.apply(null, ["rp:phone:ui:camera"].concat([].slice.call(arguments))); }

    var me = { id: 0, username: "", avatar: 0, unread: 0 };
    var fg = {
        stack: [],              // pantallas abiertas: { screen, arg }
        feedMode: "following",
        feed: [],
        feedLoading: false,
        profile: null,          // perfil mostrado
        commentsPost: 0,
        commentsOldest: 0,
        pendingUsername: null,  // al tocar una @mencion
        searchTimer: null,
    };

    // ================================================================ Imagenes (cache por id de publicacion)
    var Images = {
        cache: {}, missing: {}, queue: [], inFlight: {}, active: 0, MAX: 4,
        src: function (id) { return this.cache[id] ? "data:image/jpeg;base64," + this.cache[id] : ""; },
        // Pone la foto en el <img> (ya o cuando llegue)
        bind: function (img, id) {
            id = Number(id) || 0;
            img.dataset.img = id;
            if (!id) return;
            if (this.cache[id]) { img.src = this.src(id); img.classList.add("loaded"); return; }
            this.request(id);
        },
        request: function (id) {
            if (this.cache[id] || this.inFlight[id] || this.missing[id] || this.queue.indexOf(id) !== -1) return;
            this.queue.push(id);
            this.pump();
        },
        pump: function () {
            var self = this;
            while (this.active < this.MAX && this.queue.length) {
                var id = this.queue.shift();
                this.active++;
                this.inFlight[id] = setTimeout((function (pid) {
                    return function () { self.done(pid); };   // sin respuesta en 20 s: se libera el hueco
                })(id), 20000);
                social("image", id);
            }
        },
        done: function (id) {
            if (this.inFlight[id] === undefined) return;
            clearTimeout(this.inFlight[id]);
            delete this.inFlight[id];
            this.active = Math.max(0, this.active - 1);
            this.pump();
        },
        receive: function (id, data, throttled) {
            this.done(id);
            if (!data) {
                if (throttled) { var self = this; setTimeout(function () { self.request(id); }, 2500); }
                else this.missing[id] = true;
                return;
            }
            this.cache[id] = data;
            var src = this.src(id);
            document.querySelectorAll('img[data-img="' + id + '"]').forEach(function (img) { img.src = src; img.classList.add("loaded"); });
        },
        forget: function (id) { delete this.cache[id]; this.missing[id] = true; }
    };

    // ================================================================ Piezas comunes
    function avatar(postId, username, size) {
        var a = el("span", "fg-avatar" + (size ? " " + size : ""));
        if (postId) {
            var img = el("img");
            Images.bind(img, postId);
            a.appendChild(img);
        } else {
            a.textContent = String(username || "?").charAt(0).toUpperCase();
        }
        return a;
    }

    function setAvatarInto(node, postId, username) {
        node.innerHTML = "";
        node.className = node.className.replace(/\bhas-img\b/, "").trim();
        if (postId) {
            var img = el("img");
            Images.bind(img, postId);
            node.appendChild(img);
            node.classList.add("has-img");
        } else {
            node.textContent = String(username || "?").charAt(0).toUpperCase();
        }
    }

    function userLink(username, id) {
        var b = el("b", "fg-user", username);
        b.addEventListener("click", function (e) { e.stopPropagation(); openProfile(id); });
        return b;
    }

    // Texto con @menciones y #etiquetas resaltadas (siempre como nodos de texto)
    function richText(parent, text) {
        String(text || "").split(/([@#][A-Za-z0-9._]+)/).forEach(function (part) {
            if (!part) return;
            if (part.charAt(0) === "@" && part.length > 1) {
                var m = el("span", "fg-mention", part);
                m.addEventListener("click", function (e) { e.stopPropagation(); openProfileByUsername(part.slice(1)); });
                parent.appendChild(m);
            } else if (part.charAt(0) === "#" && part.length > 1) {
                parent.appendChild(el("span", "fg-tag", part));
            } else {
                parent.appendChild(document.createTextNode(part));
            }
        });
    }

    function plural(n, one, many) { return n + " " + (Number(n) === 1 ? one : many); }

    function heartBurst(wrap) {
        var h = el("span", "fg-burst", "♥");
        wrap.appendChild(h);
        setTimeout(function () { h.remove(); }, 900);
    }

    // ================================================================ Navegacion interna
    var TITLES = {
        feed: "Fotogram", search: "Buscar", notifs: "Notificaciones", profile: "", post: "Publicacion",
        comments: "Comentarios", follows: "", edit: "Editar perfil", editor: "Editar", publish: "Nueva publicacion"
    };
    var TABS = { feed: "feed", search: "search", notifs: "notifs" };

    function current() { return fg.stack[fg.stack.length - 1] || { screen: "feed" }; }

    function render(screenName, title) {
        document.querySelectorAll("#view-social .fg-screen").forEach(function (s) {
            s.classList.toggle("active", s.dataset.screen === screenName);
        });
        var t = $("fg-title");
        t.textContent = title !== undefined ? title : (TITLES[screenName] || "");
        t.classList.toggle("logo-text", screenName === "feed");
        $("fg-back").textContent = fg.stack.length > 1 ? "‹" : "‹ Inicio";
        var view = $("view-social");
        view.classList.toggle("no-tabs", screenName === "editor" || screenName === "publish" || screenName === "comments");
        view.classList.toggle("dark", screenName === "editor");
        document.querySelector(".screen").classList.toggle("dark-status", screenName === "editor");
        var tab = TABS[screenName] || (screenName === "profile" && fg.profile && fg.profile.mine ? "profile" : null);
        document.querySelectorAll(".fg-tabs [data-tab]").forEach(function (b) { b.classList.toggle("active", b.dataset.tab === tab); });
        // Boton de la derecha de la cabecera segun la pantalla
        var action = $("fg-action");
        action.textContent = { feed: "📷", editor: "Siguiente", edit: "Listo" }[screenName] || "";
        action.dataset.act = screenName;
    }

    function go(screenName, arg, replace) {
        if (replace) fg.stack = [];
        fg.stack.push({ screen: screenName, arg: arg });
        render(screenName);
        enter(screenName, arg);
    }

    function back() {
        if (fg.stack.length <= 1) { fg.stack = []; P.show("home"); return; }
        var leaving = fg.stack.pop();
        if (leaving.screen === "editor") Editor.reset();
        var c = current();
        render(c.screen, c.screen === "profile" || c.screen === "follows" ? undefined : undefined);
        enter(c.screen, c.arg, true);
    }

    // Que pedir al entrar en cada pantalla
    function enter(screenName, arg, returning) {
        if (screenName === "feed") { if (!returning || !fg.feed.length) loadFeed(); }
        else if (screenName === "search") { if (!returning) { $("fg-search-input").value = ""; $("fg-search-results").innerHTML = ""; } social("explore"); }
        else if (screenName === "notifs") { social("notifications"); }
        else if (screenName === "profile") { $("fg-title").textContent = ""; social("profile", arg || 0); }
        else if (screenName === "post") { $("fg-post").innerHTML = ""; social("getPost", arg); }
        else if (screenName === "comments") { openComments(arg); }
        else if (screenName === "follows") { $("fg-follows").innerHTML = ""; $("fg-title").textContent = arg.which === "following" ? "Seguidos" : "Seguidores"; social("follows", arg.id, arg.which); }
        else if (screenName === "edit") { fillEdit(); }
    }

    function openProfile(id) { go("profile", id); }
    function openProfileByUsername(username) {
        fg.pendingUsername = String(username).toLowerCase().replace(/\.+$/, "");
        social("search", fg.pendingUsername);
    }

    $("fg-back").addEventListener("click", back);
    $("fg-action").addEventListener("click", function () {
        var act = this.dataset.act;
        if (act === "feed") openCamera("selfie");
        else if (act === "editor") Editor.next();
        else if (act === "edit") saveEdit();
    });
    document.querySelectorAll(".fg-tabs [data-tab]").forEach(function (b) {
        b.addEventListener("click", function () {
            var tab = b.dataset.tab;
            if (tab === "camera") return openCamera("selfie");
            if (tab === "profile") return go("profile", me.id, true);
            go(tab, null, true);
        });
    });

    // ================================================================ Feed
    function loadFeed(more) {
        if (fg.feedLoading) return;
        fg.feedLoading = true;
        var before = more && fg.feed.length ? fg.feed[fg.feed.length - 1].id : 0;
        if (!more) { $("fg-feed").innerHTML = ""; $("fg-feed").appendChild(el("p", "fg-empty", "Cargando...")); }
        social("feed", fg.feedMode, before);
    }

    document.querySelectorAll("[data-feed]").forEach(function (b) {
        b.addEventListener("click", function () {
            fg.feedMode = b.dataset.feed;
            document.querySelectorAll("[data-feed]").forEach(function (x) { x.classList.toggle("active", x === b); });
            fg.feed = [];
            loadFeed();
        });
    });
    $("fg-feed-more").addEventListener("click", function () { loadFeed(true); });
    $("fg-feed-scroll").addEventListener("scroll", function () {
        var s = this;
        if (!$("fg-feed-more").hidden && s.scrollTop + s.clientHeight > s.scrollHeight - 120) loadFeed(true);
    });

    function postCard(p) {
        var post = el("article", "fg-post");
        post.dataset.post = p.id;

        var head = el("div", "fg-post-head");
        head.appendChild(avatar(p.avatar, p.username, "sm"));
        var who = el("div", "fg-post-who");
        who.appendChild(userLink(p.username, p.authorId));
        who.appendChild(el("small", null, p.author));
        head.appendChild(who);
        if (p.mine) {
            var menu = el("button", "fg-menu", "⋯");
            menu.type = "button";
            menu.addEventListener("click", function () { postMenu(post, p); });
            head.appendChild(menu);
        }
        post.appendChild(head);

        var wrap = el("div", "fg-photo");
        var img = el("img");
        Images.bind(img, p.id);
        wrap.appendChild(img);
        wrap.addEventListener("dblclick", function () {
            heartBurst(wrap);
            if (!p.liked) toggleLike(p);
        });
        post.appendChild(wrap);

        var actions = el("div", "fg-actions");
        var like = el("button", "fg-like" + (p.liked ? " on" : ""), p.liked ? "♥" : "♡");
        like.type = "button";
        like.addEventListener("click", function () { toggleLike(p); });
        var cmt = el("button", "fg-cmt", "💬");
        cmt.type = "button";
        cmt.addEventListener("click", function () { go("comments", p.id); });
        actions.appendChild(like);
        actions.appendChild(cmt);
        post.appendChild(actions);

        post.appendChild(el("div", "fg-likes", plural(p.likes, "Me gusta", "Me gusta")));
        if (p.caption) {
            var cap = el("div", "fg-caption");
            cap.appendChild(userLink(p.username, p.authorId));
            cap.appendChild(document.createTextNode(" "));
            richText(cap, p.caption);
            post.appendChild(cap);
        }
        if (p.comments > 0) {
            var all = el("button", "fg-view-comments", p.comments === 1 ? "Ver 1 comentario" : "Ver los " + p.comments + " comentarios");
            all.type = "button";
            all.addEventListener("click", function () { go("comments", p.id); });
            post.appendChild(all);
        }
        var filter = p.filter && p.filter !== "original" && FILTER_NAMES[p.filter] ? " · " + FILTER_NAMES[p.filter] : "";
        post.appendChild(el("div", "fg-date", p.date + filter));
        post._data = p;
        return post;
    }

    function toggleLike(p) {
        p.liked = !p.liked;
        p.likes = Math.max(0, Number(p.likes) + (p.liked ? 1 : -1));
        updateLikeUI(p.id, p.liked, p.likes);
        social("like", p.id);
    }

    function updateLikeUI(id, liked, likes) {
        document.querySelectorAll('.fg-post[data-post="' + id + '"]').forEach(function (post) {
            if (post._data) { post._data.liked = liked; post._data.likes = likes; }
            var b = post.querySelector(".fg-like");
            b.textContent = liked ? "♥" : "♡";
            b.classList.toggle("on", liked);
            if (liked) { b.classList.remove("pop"); void b.offsetWidth; b.classList.add("pop"); }
            post.querySelector(".fg-likes").textContent = plural(likes, "Me gusta", "Me gusta");
        });
    }

    // Hoja de acciones de una foto propia
    function postMenu(post, p) {
        closeSheet();
        var sheet = el("div", "fg-sheet");
        sheet.id = "fg-sheet";
        var box = el("div", "fg-sheet-box");
        function item(text, cls, fn) {
            var b = el("button", cls, text);
            b.type = "button";
            b.addEventListener("click", function () { closeSheet(); fn(); });
            box.appendChild(b);
        }
        item("Usar como foto de perfil", "", function () { social("setAvatar", p.id); });
        item("Eliminar publicacion", "danger-text", function () {
            closeSheet();
            confirmSheet("¿Eliminar esta foto? Se borran tambien sus comentarios.", "Eliminar", function () { social("deletePost", p.id); });
        });
        item("Cancelar", "muted", function () {});
        sheet.appendChild(box);
        sheet.addEventListener("click", function (e) { if (e.target === sheet) closeSheet(); });
        $("view-social").appendChild(sheet);
    }
    function confirmSheet(text, okText, fn) {
        var sheet = el("div", "fg-sheet");
        sheet.id = "fg-sheet";
        var box = el("div", "fg-sheet-box");
        box.appendChild(el("p", null, text));
        var ok = el("button", "danger-text", okText);
        ok.type = "button";
        ok.addEventListener("click", function () { closeSheet(); fn(); });
        var no = el("button", "muted", "Cancelar");
        no.type = "button";
        no.addEventListener("click", closeSheet);
        box.appendChild(ok);
        box.appendChild(no);
        sheet.appendChild(box);
        $("view-social").appendChild(sheet);
    }
    function closeSheet() { var s = $("fg-sheet"); if (s) s.remove(); }

    // ================================================================ Comentarios
    function openComments(postId) {
        fg.commentsPost = postId;
        fg.commentsOldest = 0;
        $("fg-comments").innerHTML = "";
        $("fg-comments").appendChild(el("li", "fg-empty", "Cargando..."));
        $("fg-comments-more").hidden = true;
        $("fg-comment-input").value = "";
        setAvatarInto($("fg-composer-avatar"), me.avatar, me.username);
        social("comments", postId, 0);
        setTimeout(function () { $("fg-comment-input").focus(); }, 50);
    }

    function commentItem(c) {
        var li = el("li", "fg-comment");
        li.appendChild(avatar(c.avatar, c.username, "sm"));
        var body = el("div", "fg-comment-body");
        var line = el("div");
        line.appendChild(userLink(c.username, c.authorId));
        line.appendChild(document.createTextNode(" "));
        richText(line, c.body);
        body.appendChild(line);
        var meta = el("div", "fg-comment-meta");
        meta.appendChild(el("span", null, c.date));
        var reply = el("button", null, "Responder");
        reply.type = "button";
        reply.addEventListener("click", function () {
            var input = $("fg-comment-input");
            input.value = "@" + c.username + " ";
            input.focus();
        });
        meta.appendChild(reply);
        if (c.canDelete) {
            var del = el("button", "danger-text", "Eliminar");
            del.type = "button";
            del.addEventListener("click", function () { social("deleteComment", c.id); });
            meta.appendChild(del);
        }
        body.appendChild(meta);
        li.appendChild(body);
        return li;
    }

    function sendComment() {
        var input = $("fg-comment-input");
        var text = input.value.trim();
        if (!text || !fg.commentsPost) return;
        social("comment", fg.commentsPost, text);
        input.value = "";
    }
    $("fg-comment-send").addEventListener("click", sendComment);
    $("fg-comment-input").addEventListener("keydown", function (e) { if (e.key === "Enter") { e.preventDefault(); sendComment(); } });
    $("fg-comments-more").addEventListener("click", function () { social("comments", fg.commentsPost, fg.commentsOldest); });

    // ================================================================ Perfil
    function renderProfile(p) {
        fg.profile = p;
        var box = $("fg-profile");
        box.innerHTML = "";
        if (current().screen === "profile") {
            $("fg-title").textContent = p.username;
            render("profile", p.username);
        }

        var top = el("div", "fg-profile-top");
        top.appendChild(avatar(p.avatar, p.username, "lg"));
        var stats = el("div", "fg-stats");
        function stat(n, label, which) {
            var s = el("button", "fg-stat");
            s.type = "button";
            s.appendChild(el("b", null, String(n)));
            s.appendChild(el("span", null, label));
            if (which) s.addEventListener("click", function () { go("follows", { id: p.id, which: which }); });
            stats.appendChild(s);
        }
        stat(p.posts, p.posts === 1 ? "publicacion" : "publicaciones");
        stat(p.followers, p.followers === 1 ? "seguidor" : "seguidores", "followers");
        stat(p.following, "seguidos", "following");
        top.appendChild(stats);
        box.appendChild(top);

        var info = el("div", "fg-profile-info");
        info.appendChild(el("b", null, p.name));
        if (p.bio) { var bio = el("p"); richText(bio, p.bio); info.appendChild(bio); }
        if (p.followsYou && !p.mine) info.appendChild(el("span", "fg-follows-you", "Te sigue"));
        box.appendChild(info);

        var buttons = el("div", "fg-profile-buttons");
        if (p.mine) {
            var edit = el("button", "fg-btn", "Editar perfil");
            edit.type = "button";
            edit.addEventListener("click", function () { go("edit"); });
            buttons.appendChild(edit);
        } else {
            buttons.appendChild(followButton(p.id, p.isFollowing, p.followsYou));
        }
        box.appendChild(buttons);

        var grid = el("div", "fg-grid");
        if (!p.grid || !p.grid.length) {
            box.appendChild(el("p", "fg-empty", p.mine ? "Aun no publicaste fotos. Pulsa ＋ para la primera." : "Todavia no hay publicaciones."));
        }
        (p.grid || []).forEach(function (g) { grid.appendChild(gridCell(g)); });
        box.appendChild(grid);
    }

    function gridCell(g) {
        var cell = el("button", "fg-cell");
        cell.type = "button";
        var img = el("img");
        Images.bind(img, g.id);
        cell.appendChild(img);
        var over = el("span", "fg-cell-over", "♥ " + g.likes + "   💬 " + g.comments);
        cell.appendChild(over);
        cell.addEventListener("click", function () { go("post", g.id); });
        return cell;
    }

    function followButton(id, following, followsYou) {
        var b = el("button", "fg-btn fg-follow" + (following ? "" : " primary-btn"));
        b.type = "button";
        b.dataset.follow = id;
        b.textContent = following ? "Siguiendo" : (followsYou ? "Seguir tambien" : "Seguir");
        b.addEventListener("click", function () {
            var now = b.classList.contains("primary-btn");   // estaba en "Seguir"
            social("follow", id, now);
            b.disabled = true;
        });
        return b;
    }

    function fillEdit() {
        $("fg-edit-username").value = me.username || "";
        $("fg-edit-bio").value = fg.profile && fg.profile.mine ? (fg.profile.bio || "") : "";
        var a = $("fg-edit-avatar");
        a.innerHTML = "";
        a.appendChild(avatar(me.avatar, me.username, "lg"));
        $("fg-avatar-remove").hidden = !me.avatar;
    }
    function saveEdit() {
        var u = $("fg-edit-username").value.trim().toLowerCase().replace(/^@/, "");
        if (!/^[a-z0-9._]{3,24}$/.test(u)) { $("fg-edit-username").focus(); $("fg-edit-username").classList.add("invalid"); return; }
        $("fg-edit-username").classList.remove("invalid");
        social("editProfile", u, $("fg-edit-bio").value);
    }
    $("fg-avatar-remove").addEventListener("click", function () { social("setAvatar", 0); });

    // ================================================================ Busqueda y Explorar
    $("fg-search-input").addEventListener("input", function () {
        var q = this.value.trim();
        clearTimeout(fg.searchTimer);
        $("fg-explore-wrap").hidden = q.length >= 2;
        if (q.length < 2) { $("fg-search-results").innerHTML = ""; return; }
        fg.searchTimer = setTimeout(function () { social("search", q); }, 350);
    });

    function userRow(u) {
        var li = el("li", "fg-user-row");
        li.appendChild(avatar(u.avatar, u.username, "md"));
        var text = el("div", "fg-user-text");
        text.appendChild(el("b", null, u.username));
        text.appendChild(el("span", null, u.name + (u.followers !== undefined ? " · " + plural(u.followers, "seguidor", "seguidores") : "")));
        li.appendChild(text);
        if (!u.me) li.appendChild(followButton(u.id, u.following, false));
        li.addEventListener("click", function (e) { if (e.target.tagName !== "BUTTON") openProfile(u.id); });
        return li;
    }

    // ================================================================ Notificaciones
    var NOTIF_TEXT = {
        like: "le gusto tu foto.", comment: "comento:", follow: "empezo a seguirte.", mention: "te menciono:"
    };
    function notifItem(n) {
        var li = el("li", "fg-notif" + (n.read ? "" : " unread"));
        li.appendChild(avatar(n.avatar, n.username, "md"));
        var text = el("div", "fg-notif-text");
        text.appendChild(userLink(n.username, n.actorId));
        text.appendChild(document.createTextNode(" " + (NOTIF_TEXT[n.type] || "") + " "));
        if (n.text && (n.type === "comment" || n.type === "mention")) {
            var q = el("span", "fg-quote");
            richText(q, n.text.length > 70 ? n.text.slice(0, 70) + "..." : n.text);
            text.appendChild(q);
        }
        text.appendChild(el("small", null, " " + n.date));
        li.appendChild(text);
        if (n.type === "follow") {
            li.appendChild(followButton(n.actorId, n.following, true));
        } else if (n.postId) {
            var thumb = el("img", "fg-notif-thumb");
            Images.bind(thumb, n.postId);
            li.appendChild(thumb);
        }
        li.addEventListener("click", function (e) {
            if (e.target.tagName === "BUTTON") return;
            if (n.type === "comment" || n.type === "mention") go("comments", n.postId);
            else if (n.postId) go("post", n.postId);
            else openProfile(n.actorId);
        });
        return li;
    }

    function setBadge(n) {
        me.unread = Number(n) || 0;
        var badge = $("fg-badge");
        badge.hidden = me.unread <= 0;
        badge.textContent = me.unread > 9 ? "9+" : String(me.unread);
        document.querySelectorAll(".app-badge").forEach(function (b) {
            b.hidden = me.unread <= 0;
            b.textContent = badge.textContent;
        });
    }

    // ================================================================ Editor de fotos (filtros en canvas)
    var FILTERS = [
        { id: "original", name: "Original", p: {} },
        { id: "vivido", name: "Vivido", p: { contrast: 1.15, saturate: 1.45, brightness: 1.03 } },
        { id: "calido", name: "Calido", p: { saturate: 1.15, sepia: 0.12, brightness: 1.03, tint: ["#ff9a3c", 0.22, "soft-light"] } },
        { id: "frio", name: "Frio", p: { saturate: 0.95, hue: -6, tint: ["#3c8dff", 0.25, "soft-light"] } },
        { id: "vintage", name: "Vintage", p: { sepia: 0.35, contrast: 0.92, saturate: 0.8, fade: 0.35, vignette: 0.45, grain: 0.3, tint: ["#ffd9a0", 0.18, "multiply"] } },
        { id: "noir", name: "Noir", p: { grayscale: 1, contrast: 1.3, brightness: 0.95, vignette: 0.35, grain: 0.15 } },
        { id: "sepia", name: "Sepia", p: { sepia: 0.85, contrast: 1.05, vignette: 0.2 } },
        { id: "atardecer", name: "Atardecer", p: { saturate: 1.25, brightness: 1.02, vignette: 0.25, tint: ["#ff5e62", 0.25, "soft-light"] } },
        { id: "neon", name: "Neon", p: { saturate: 1.8, contrast: 1.2, hue: 12, tint: ["#b621fe", 0.2, "screen"] } },
        { id: "desvanecido", name: "Desvanecido", p: { contrast: 0.85, saturate: 0.75, brightness: 1.05, fade: 0.5 } },
        { id: "drama", name: "Drama", p: { contrast: 1.45, saturate: 0.85, brightness: 0.92, vignette: 0.6 } },
        { id: "pastel", name: "Pastel", p: { saturate: 0.7, brightness: 1.12, contrast: 0.88, fade: 0.25, tint: ["#ffc0e0", 0.2, "soft-light"] } }
    ];
    var FILTER_NAMES = {};
    FILTERS.forEach(function (f) { FILTER_NAMES[f.id] = f.name; });

    var ADJUST = [
        { id: "brightness", name: "Brillo", min: -100, max: 100 },
        { id: "contrast", name: "Contraste", min: -100, max: 100 },
        { id: "saturate", name: "Saturacion", min: -100, max: 100 },
        { id: "warmth", name: "Calidez", min: -100, max: 100 },
        { id: "fade", name: "Desvanecer", min: 0, max: 100 },
        { id: "vignette", name: "Vineta", min: 0, max: 100 },
        { id: "grain", name: "Grano", min: 0, max: 100 }
    ];

    var noiseCanvas = null;
    function noise() {
        if (noiseCanvas) return noiseCanvas;
        noiseCanvas = document.createElement("canvas");
        noiseCanvas.width = noiseCanvas.height = 128;
        var c = noiseCanvas.getContext("2d");
        var d = c.createImageData(128, 128);
        for (var i = 0; i < d.data.length; i += 4) {
            var v = 128 + (Math.random() - 0.5) * 255;
            d.data[i] = d.data[i + 1] = d.data[i + 2] = v;
            d.data[i + 3] = 255;
        }
        c.putImageData(d, 0, 0);
        return noiseCanvas;
    }

    // Mezcla el filtro (con su intensidad) y los ajustes en un juego de parametros
    function params(filter, intensity, adj) {
        var f = filter.p, t = intensity;
        function mix(key, neutral) { return f[key] === undefined ? neutral : neutral + (f[key] - neutral) * t; }
        var r = {
            brightness: mix("brightness", 1) * (1 + adj.brightness / 250),
            contrast: mix("contrast", 1) * (1 + adj.contrast / 200),
            saturate: mix("saturate", 1) * (1 + adj.saturate / 100),
            sepia: mix("sepia", 0), grayscale: mix("grayscale", 0), hue: mix("hue", 0),
            fade: Math.min(1, mix("fade", 0) + adj.fade / 100),
            vignette: Math.min(1, mix("vignette", 0) + adj.vignette / 100),
            grain: Math.min(1, mix("grain", 0) + adj.grain / 100),
            tints: []
        };
        if (f.tint) r.tints.push([f.tint[0], f.tint[1] * t, f.tint[2]]);
        if (adj.warmth) r.tints.push([adj.warmth > 0 ? "#ff8c2a" : "#2a8cff", Math.abs(adj.warmth) / 100 * 0.35, "soft-light"]);
        return r;
    }

    function paint(canvas, img, pr) {
        var w = canvas.width, h = canvas.height, ctx = canvas.getContext("2d");
        ctx.save();
        ctx.globalCompositeOperation = "source-over";
        ctx.globalAlpha = 1;
        ctx.filter = "brightness(" + pr.brightness + ") contrast(" + pr.contrast + ") saturate(" + pr.saturate + ") sepia(" + pr.sepia +
            ") grayscale(" + pr.grayscale + ") hue-rotate(" + pr.hue + "deg)";
        ctx.drawImage(img, 0, 0, w, h);
        ctx.filter = "none";
        pr.tints.forEach(function (tn) {
            if (tn[1] <= 0) return;
            ctx.globalCompositeOperation = tn[2];
            ctx.globalAlpha = Math.min(1, tn[1]);
            ctx.fillStyle = tn[0];
            ctx.fillRect(0, 0, w, h);
        });
        if (pr.fade > 0) {
            ctx.globalCompositeOperation = "screen";
            ctx.globalAlpha = pr.fade * 0.8;
            ctx.fillStyle = "#4a4a4a";
            ctx.fillRect(0, 0, w, h);
        }
        if (pr.vignette > 0) {
            ctx.globalCompositeOperation = "source-over";
            ctx.globalAlpha = 1;
            var g = ctx.createRadialGradient(w / 2, h / 2, Math.min(w, h) * 0.35, w / 2, h / 2, Math.max(w, h) * 0.72);
            g.addColorStop(0, "rgba(0,0,0,0)");
            g.addColorStop(1, "rgba(0,0,0," + (pr.vignette * 0.85) + ")");
            ctx.fillStyle = g;
            ctx.fillRect(0, 0, w, h);
        }
        if (pr.grain > 0) {
            ctx.globalCompositeOperation = "overlay";
            ctx.globalAlpha = pr.grain * 0.45;
            ctx.fillStyle = ctx.createPattern(noise(), "repeat");
            ctx.fillRect(0, 0, w, h);
        }
        ctx.restore();
    }

    var Editor = {
        img: null, raw: null, filter: FILTERS[0], intensity: 1, adj: null, tool: "filters", jpeg: null,
        resetAdj: function () { this.adj = { brightness: 0, contrast: 0, saturate: 0, warmth: 0, fade: 0, vignette: 0, grain: 0 }; },
        reset: function () { this.img = null; this.raw = null; this.jpeg = null; },
        open: function (base64) {
            var self = this;
            this.raw = base64;
            this.filter = FILTERS[0];
            this.intensity = 1;
            this.resetAdj();
            $("fg-intensity").value = 100;
            ADJUST.forEach(function (a) { var s = $("fg-adj-" + a.id); if (s) { s.value = 0; s.nextSibling.textContent = "0"; } });
            this.setTool("filters");
            var img = new Image();
            img.onload = function () { self.img = img; self.buildThumbs(); self.draw(); };
            img.src = "data:image/jpeg;base64," + base64;
            go("editor");
        },
        draw: function () {
            if (!this.img) return;
            paint($("fg-canvas"), this.img, params(this.filter, this.intensity, this.adj));
        },
        buildThumbs: function () {
            var self = this, box = $("fg-filters");
            box.innerHTML = "";
            FILTERS.forEach(function (f) {
                var b = el("button", "fg-filter" + (f === self.filter ? " active" : ""));
                b.type = "button";
                var c = document.createElement("canvas");
                c.width = 64; c.height = 80;
                paint(c, self.img, params(f, 1, { brightness: 0, contrast: 0, saturate: 0, warmth: 0, fade: 0, vignette: 0, grain: 0 }));
                b.appendChild(el("span", null, f.name));
                b.appendChild(c);
                b.addEventListener("click", function () {
                    if (self.filter === f) { self.intensity = self.intensity > 0 ? self.intensity : 1; }
                    self.filter = f;
                    box.querySelectorAll(".fg-filter").forEach(function (x) { x.classList.toggle("active", x === b); });
                    self.draw();
                });
                box.appendChild(b);
            });
        },
        setTool: function (tool) {
            this.tool = tool;
            document.querySelectorAll("[data-tool]").forEach(function (x) { x.hidden = x.dataset.tool !== tool; });
            document.querySelectorAll("[data-tooltab]").forEach(function (x) { x.classList.toggle("active", x.dataset.tooltab === tool); });
        },
        // Exporta a JPEG; baja la calidad si pasa del limite del servidor
        exportJpeg: function () {
            var out = document.createElement("canvas");
            out.width = 576; out.height = 720;
            paint(out, this.img, params(this.filter, this.intensity, this.adj));
            var q = 0.86, data = "";
            do {
                data = out.toDataURL("image/jpeg", q).replace(/^data:image\/jpeg;base64,/, "");
                q -= 0.12;
            } while (data.length > 330000 && q > 0.3);
            return data;
        },
        next: function () {
            if (!this.img) return;
            this.jpeg = this.exportJpeg();
            $("fg-publish-preview").src = "data:image/jpeg;base64," + this.jpeg;
            $("fg-caption").value = "";
            $("fg-publish-filter").textContent = this.filter.id === "original" ? "" : "Filtro: " + this.filter.name;
            $("fg-share").disabled = false;
            $("fg-share").textContent = "Compartir";
            go("publish");
        }
    };
    Editor.resetAdj();

    // Controles del editor
    (function buildAdjust() {
        var box = $("fg-adjust");
        ADJUST.forEach(function (a) {
            var row = el("div", "fg-slider");
            row.appendChild(el("span", null, a.name));
            var input = el("input");
            input.type = "range"; input.min = a.min; input.max = a.max; input.value = 0;
            input.id = "fg-adj-" + a.id;
            var val = el("em", null, "0");
            input.addEventListener("input", function () {
                Editor.adj[a.id] = Number(input.value);
                val.textContent = input.value;
                Editor.draw();
            });
            input.addEventListener("dblclick", function () { input.value = 0; Editor.adj[a.id] = 0; val.textContent = "0"; Editor.draw(); });
            row.appendChild(input);
            row.appendChild(val);
            box.appendChild(row);
        });
    })();
    $("fg-intensity").addEventListener("input", function () { Editor.intensity = Number(this.value) / 100; Editor.draw(); });
    document.querySelectorAll("[data-tooltab]").forEach(function (b) {
        b.addEventListener("click", function () { Editor.setTool(b.dataset.tooltab); });
    });
    // Mantener pulsada la foto muestra el original
    $("fg-canvas").addEventListener("mousedown", function () {
        if (Editor.img) paint($("fg-canvas"), Editor.img, params(FILTERS[0], 0, { brightness: 0, contrast: 0, saturate: 0, warmth: 0, fade: 0, vignette: 0, grain: 0 }));
    });
    document.addEventListener("mouseup", function () { if (current().screen === "editor") Editor.draw(); });

    $("fg-share").addEventListener("click", function () {
        if (!Editor.jpeg) return;
        this.disabled = true;
        this.textContent = "Publicando...";
        send("rp:phone:ui:socialPost", $("fg-caption").value.trim(), Editor.jpeg, Editor.filter.id);
    });
    $("fg-retake").addEventListener("click", function () { openCamera(Cam.mode || "selfie"); });

    // ================================================================ Camara (HUD)
    var Cam = { mode: "selfie", timer: 0, grid: false, counting: null, keys: {} };
    var TIMERS = [0, 3, 10];
    var KEYMAP = {
        a: "left", arrowleft: "left", d: "right", arrowright: "right",
        w: "up", arrowup: "up", s: "down", arrowdown: "down"
    };

    function openCamera(mode) { camera("open", mode || "selfie"); }

    function closeCameraHud() {
        cancelCountdown();
        releaseKeys();
        document.body.classList.remove("camera-mode");
        $("camera-hud").hidden = true;
    }

    function releaseKeys() {
        if (Object.keys(Cam.keys).length) camera("release");
        Cam.keys = {};
    }

    function cancelCountdown() {
        if (Cam.counting) { clearInterval(Cam.counting); Cam.counting = null; }
        $("cam-count").hidden = true;
    }

    function shoot() {
        if (Cam.counting) return;
        if (!Cam.timer) return fire();
        var left = Cam.timer;
        var count = $("cam-count");
        count.hidden = false;
        count.textContent = left;
        Cam.counting = setInterval(function () {
            left--;
            if (left <= 0) { cancelCountdown(); fire(); return; }
            count.textContent = left;
            count.classList.remove("tick"); void count.offsetWidth; count.classList.add("tick");
        }, 1000);
    }
    function fire() { releaseKeys(); camera("shoot"); }

    $("cam-shutter").addEventListener("click", shoot);
    $("cam-close").addEventListener("click", function () { closeCameraHud(); camera("close"); });
    $("cam-flip").addEventListener("click", function () { camera("flip"); });
    $("cam-timer").addEventListener("click", function () {
        Cam.timer = TIMERS[(TIMERS.indexOf(Cam.timer) + 1) % TIMERS.length];
        $("cam-timer-label").textContent = Cam.timer ? Cam.timer + "s" : "";
        this.classList.toggle("on", Cam.timer > 0);
    });
    $("cam-grid-btn").addEventListener("click", function () {
        Cam.grid = !Cam.grid;
        $("cam-grid").hidden = !Cam.grid;
        this.classList.toggle("on", Cam.grid);
    });
    $("cam-zoom").addEventListener("input", function () { camera("zoomTo", Number(this.value) / 100); });
    $("camera-hud").addEventListener("wheel", function (e) {
        e.preventDefault();
        camera("zoom", e.deltaY < 0 ? 1 : -1);
    }, { passive: false });

    document.addEventListener("keydown", function (e) {
        if (!document.body.classList.contains("camera-mode")) return;
        var k = e.key.toLowerCase();
        e.preventDefault();
        if (KEYMAP[k]) { if (!Cam.keys[KEYMAP[k]]) { Cam.keys[KEYMAP[k]] = true; camera("key", KEYMAP[k], true); } return; }
        if (e.repeat) return;
        if (k === "escape" || k === "backspace") { closeCameraHud(); camera("close"); }
        else if (k === " " || k === "enter") shoot();
        else if (k === "f") camera("flip");
        else if (k === "q") camera("nextPose", -1);
        else if (k === "e") camera("nextPose", 1);
        else if (k === "+" || k === "=") camera("zoom", 1);
        else if (k === "-") camera("zoom", -1);
        else if (k === "t") $("cam-timer").click();
        else if (k === "g") $("cam-grid-btn").click();
    });
    document.addEventListener("keyup", function (e) {
        if (!document.body.classList.contains("camera-mode")) return;
        var key = KEYMAP[e.key.toLowerCase()];
        if (key && Cam.keys[key]) { delete Cam.keys[key]; camera("key", key, false); }
    });
    window.addEventListener("blur", releaseKeys);

    // ================================================================ API para Lua
    window.RP = window.RP || {};

    RP.camera = {
        open: function (frame) {
            var f = $("cam-frame");
            f.style.left = frame.x + "px";
            f.style.top = frame.y + "px";
            f.style.width = frame.w + "px";
            f.style.height = frame.h + "px";
            $("camera-hud").hidden = false;
            document.body.classList.add("camera-mode");
            cancelCountdown();
            document.activeElement && document.activeElement.blur && document.activeElement.blur();
        },
        state: function (s) {
            Cam.mode = s.mode;
            $("cam-mode").textContent = s.mode === "selfie" ? "Selfie" : "Camara trasera";
            $("cam-frame").classList.toggle("selfie", s.mode === "selfie");
            $("cam-zoom").value = Math.round((s.zoom || 0) * 100);
            var box = $("cam-poses");
            box.innerHTML = "";
            box.hidden = !s.canPose;
            (s.poses || []).forEach(function (p) {
                var b = el("button", "cam-pose" + (p.id === s.pose ? " active" : ""));
                b.type = "button";
                b.appendChild(el("span", "cam-pose-icon", p.icon));
                b.appendChild(el("small", null, p.name));
                b.addEventListener("click", function () { camera("pose", p.id); });
                box.appendChild(b);
                if (p.id === s.pose) setTimeout(function () { b.scrollIntoView({ inline: "center", block: "nearest" }); }, 0);
            });
        },
        shot: function (base64) {
            var flash = $("cam-flash");
            flash.classList.remove("go"); void flash.offsetWidth; flash.classList.add("go");
            setTimeout(function () {
                closeCameraHud();
                P.show("social");
                Editor.open(base64);
            }, 220);
        }
    };

    RP.social = {
        me: function (d) {
            me = d;
            setAvatarInto($("fg-tab-avatar"), me.avatar, me.username);
            setBadge(d.unread);
        },
        feed: function (list, mode, append) {
            fg.feedLoading = false;
            if (mode !== fg.feedMode) return;
            var box = $("fg-feed");
            if (!append) { box.innerHTML = ""; fg.feed = []; }
            list = list || [];
            list.forEach(function (p) { fg.feed.push(p); box.appendChild(postCard(p)); });
            if (!fg.feed.length) {
                box.appendChild(el("p", "fg-empty", mode === "following"
                    ? "Aqui veras tus fotos y las de quien sigues. Busca gente en ⌕ o mira \"Para ti\"."
                    : "Todavia no hay publicaciones. Pulsa ＋ para subir la primera."));
            }
            $("fg-feed-more").hidden = list.length < 8;
        },
        image: function (id, data, throttled) { Images.receive(Number(id), data, throttled); },
        posted: function (id) {
            if (!id) { $("fg-share").disabled = false; $("fg-share").textContent = "Compartir"; return; }
            Editor.reset();
            if (Editor.jpegCache !== undefined) delete Editor.jpegCache;
            fg.feedMode = "following";
            document.querySelectorAll("[data-feed]").forEach(function (x) { x.classList.toggle("active", x.dataset.feed === "following"); });
            fg.feed = [];
            go("feed", null, true);
        },
        likeState: function (r) { updateLikeUI(r.id, r.liked, r.likes); },
        postDeleted: function (r) {
            Images.forget(r.id);
            document.querySelectorAll('.fg-post[data-post="' + r.id + '"]').forEach(function (n) { n.remove(); });
            fg.feed = fg.feed.filter(function (p) { return p.id !== r.id; });
            if (current().screen === "post") back();
            if (me.avatar === r.id) { me.avatar = 0; setAvatarInto($("fg-tab-avatar"), 0, me.username); }
            if (current().screen === "profile") social("profile", current().arg || 0);
        },
        post: function (p) {
            var box = $("fg-post");
            box.innerHTML = "";
            box.appendChild(postCard(p));
        },
        comments: function (r) {
            if (r.postId !== fg.commentsPost) return;
            var list = $("fg-comments");
            var items = (r.comments || []).slice().reverse();   // llegan del mas nuevo al mas viejo
            if (!r.append) list.innerHTML = "";
            var empty = list.querySelector(".fg-empty");
            if (empty) empty.remove();
            var first = list.firstChild;
            items.forEach(function (c) { list.insertBefore(commentItem(c), first); });
            if (r.comments && r.comments.length) fg.commentsOldest = r.comments[r.comments.length - 1].id;
            $("fg-comments-more").hidden = !r.more;
            if (!list.children.length) list.appendChild(el("li", "fg-empty", "Aun no hay comentarios. ¡Se el primero!"));
            if (!r.append) { var sc = $("fg-comments-scroll"); sc.scrollTop = sc.scrollHeight; }
            // Actualiza el contador en las tarjetas
            document.querySelectorAll('.fg-post[data-post="' + r.postId + '"]').forEach(function (post) {
                if (!r.append && post._data) post._data.comments = Math.max(post._data.comments, r.comments.length);
            });
        },
        profile: function (p) {
            if (p.mine) {
                me.username = p.username;
                me.avatar = p.avatar;
                setAvatarInto($("fg-tab-avatar"), me.avatar, me.username);
                if (current().screen === "edit") { back(); return; }
            }
            var c = current();
            if (c.screen === "profile" && (Number(c.arg || me.id) === p.id || (!c.arg && p.mine))) renderProfile(p);
        },
        followState: function (r) {
            document.querySelectorAll('[data-follow="' + r.id + '"]').forEach(function (b) {
                b.disabled = false;
                b.textContent = r.following ? "Siguiendo" : "Seguir";
                b.classList.toggle("primary-btn", !r.following);
            });
            if (fg.profile && fg.profile.id === r.id && current().screen === "profile") {
                fg.profile.isFollowing = r.following;
                fg.profile.followers = r.followers;
                renderProfile(fg.profile);
            }
        },
        follows: function (r) {
            var list = $("fg-follows");
            list.innerHTML = "";
            if (!r.list.length) list.appendChild(el("li", "fg-empty", r.which === "following" ? "No sigue a nadie todavia." : "Aun no tiene seguidores."));
            r.list.forEach(function (u) { list.appendChild(userRow(u)); });
        },
        search: function (q, list) {
            if (fg.pendingUsername) {
                var wanted = fg.pendingUsername;
                fg.pendingUsername = null;
                var hit = (list || []).filter(function (u) { return u.username === wanted; })[0];
                if (hit) openProfile(hit.id);
                return;
            }
            if (q !== $("fg-search-input").value.trim()) return;
            var box = $("fg-search-results");
            box.innerHTML = "";
            if (!list.length) box.appendChild(el("li", "fg-empty", "Sin resultados para \"" + q + "\""));
            list.forEach(function (u) { box.appendChild(userRow(u)); });
        },
        explore: function (list) {
            var grid = $("fg-explore");
            grid.innerHTML = "";
            if (!list.length) grid.appendChild(el("p", "fg-empty", "Aun no hay fotos."));
            list.forEach(function (g) { grid.appendChild(gridCell(g)); });
        },
        notifications: function (list) {
            var box = $("fg-notifs");
            box.innerHTML = "";
            if (!list.length) box.appendChild(el("li", "fg-empty", "Cuando alguien te siga, comente o le guste tu foto lo veras aqui."));
            list.forEach(function (n) { box.appendChild(notifItem(n)); });
        },
        badge: function (n) { setBadge(n); }
    };

    // ================================================================ Entrada desde el telefono
    window.Fotogram = {
        onShow: function (name) {
            if (name !== "social") return;
            if (!fg.stack.length) go("feed", null, true);
            else { var c = current(); render(c.screen); enter(c.screen, c.arg, true); }
        }
    };
})();
