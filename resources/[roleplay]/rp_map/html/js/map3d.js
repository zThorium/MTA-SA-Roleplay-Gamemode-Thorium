/*
 * rp_map / map3d.js
 * Vista 3D (Three.js r147, WebGL) del mismo mundo que el 2D:
 *   - relieve real aproximado (data/terrain.js) con la textura del mapa 2D y su niebla;
 *   - edificios con su volumen, posicion, giro y altura sacados del juego (data/buildings.js:
 *     IPL + caja de colision de cada modelo), dibujados como InstancedMesh (una sola llamada);
 *     solo se ven los de celdas exploradas;
 *   - iconos, marcadores, jugador y ruta GPS compartidos con el 2D.
 * Ejes: X = x del mundo, Y = altura, Z = -y del mundo (norte hacia -Z).
 * Controles: izquierdo arrastra, derecho gira e inclina, rueda acerca. Clic selecciona.
 */
(function () {
    "use strict";
    var HALF = 3000, N = 120;
    var T = window.THREE;
    var container, hooks = {}, inited = false, active = false, raf = null;
    var renderer, scene, camera, controls, raycaster, pointer;
    var terrainMesh, texCanvas, texture, bldMesh, bldIndex = [], highlight;
    var placeGroup, markerGroup, playerMesh, routeMesh, destMesh;
    var heights = null, gsize = 121;
    var spriteCache = {};
    var fogState = { cells: {}, start: {}, on: true };

    function groundAt(x, y) {
        if (!heights) return 0;
        var gx = (x + HALF) / 50, gy = (HALF - y) / 50;
        var x0 = Math.max(0, Math.min(gsize - 2, Math.floor(gx))), y0 = Math.max(0, Math.min(gsize - 2, Math.floor(gy)));
        var fx = Math.max(0, Math.min(1, gx - x0)), fy = Math.max(0, Math.min(1, gy - y0));
        var h00 = heights[y0 * gsize + x0], h10 = heights[y0 * gsize + x0 + 1];
        var h01 = heights[(y0 + 1) * gsize + x0], h11 = heights[(y0 + 1) * gsize + x0 + 1];
        return (h00 * (1 - fx) + h10 * fx) * (1 - fy) + (h01 * (1 - fx) + h11 * fx) * fy;
    }

    function cellOf(x, y) {
        var cx = Math.floor((x + HALF) / 50), cy = Math.floor((HALF - y) / 50);
        if (cx < 0 || cy < 0 || cx >= N || cy >= N) return 0;
        return cy * N + cx + 1;
    }
    function seen(x, y) {
        if (!fogState.on) return true;
        var c = cellOf(x, y);
        return !!(fogState.cells[c] || fogState.start[c]);
    }

    // ---------------------------------------------------------------- escena
    function buildTerrain() {
        var tr = window.MAP_TERRAIN;
        heights = tr ? tr.h : null;
        gsize = tr ? tr.size : 121;
        var geo = new T.PlaneGeometry(6000, 6000, gsize - 1, gsize - 1);
        geo.rotateX(-Math.PI / 2);
        var pos = geo.attributes.position;
        for (var i = 0; i < pos.count; i++) pos.setY(i, heights ? heights[i] : 0);
        geo.computeVertexNormals();
        texCanvas = document.createElement("canvas");
        texCanvas.width = texCanvas.height = 4096;
        texture = new T.CanvasTexture(texCanvas);
        texture.anisotropy = renderer.capabilities.getMaxAnisotropy();
        texture.encoding = T.sRGBEncoding;
        terrainMesh = new T.Mesh(geo, new T.MeshLambertMaterial({ map: texture }));
        scene.add(terrainMesh);
        // mar alrededor del mundo
        var sea = new T.Mesh(new T.PlaneGeometry(30000, 30000), new T.MeshBasicMaterial({ color: 0x0a1424 }));
        sea.rotateX(-Math.PI / 2);
        sea.position.y = -3;
        scene.add(sea);
    }

    function paintTexture() {
        if (!texCanvas) return;
        var g = texCanvas.getContext("2d");
        var base = window.Map2D.getBase(), fog = window.Map2D.getFog();
        g.fillStyle = "#0d1420";
        g.fillRect(0, 0, 4096, 4096);
        if (base) g.drawImage(base, 0, 0, 4096, 4096);
        if (fog && fogState.on) { g.imageSmoothingEnabled = true; g.drawImage(fog, 0, 0, 4096, 4096); }
        texture.needsUpdate = true;
    }

    function buildBuildings() {
        var B = window.MAP_BUILDINGS;
        if (!B) return;
        var count = B.b.length / 8;
        var geo = new T.BoxGeometry(1, 1, 1);
        geo.translate(0, 0.5, 0);
        var mat = new T.MeshLambertMaterial({ color: 0xffffff });
        bldMesh = new T.InstancedMesh(geo, mat, count);
        bldMesh.instanceMatrix.setUsage(T.DynamicDrawUsage);
        var col = new T.Color();
        for (var k = 0; k < count; k++) {
            var i = k * 8;
            var cx = B.b[i], cy = B.b[i + 1], hx = B.b[i + 2], hy = B.b[i + 3], yaw = B.b[i + 4], bz = B.b[i + 5], tz = B.b[i + 6];
            var ground = groundAt(cx, cy);
            var bottom = Math.min(bz, ground) - 1, top = Math.max(tz, ground + 4);
            bldIndex.push({ x: cx, y: cy, hx: hx, hy: hy, yaw: yaw, bottom: bottom, top: top, model: B.m[B.b[i + 7]] || "" });
            // color por altura: bajos azul pizarra, altos claros
            var h = Math.min(1, (top - bottom) / 120);
            col.setRGB(0.09 + 0.20 * h, 0.10 + 0.21 * h, 0.15 + 0.24 * h);
            bldMesh.setColorAt(k, col);
        }
        bldMesh.instanceColor.needsUpdate = true;
        scene.add(bldMesh);
        var hl = new T.LineSegments(new T.EdgesGeometry(geo), new T.LineBasicMaterial({ color: 0xf5a524 }));
        hl.visible = false;
        highlight = hl;
        scene.add(hl);
        updateBuildings();
    }

    var dummy = null;
    function updateBuildings() {
        if (!bldMesh) return;
        dummy = dummy || new T.Object3D();
        for (var k = 0; k < bldIndex.length; k++) {
            var b = bldIndex[k];
            dummy.position.set(b.x, b.bottom, -b.y);
            dummy.rotation.set(0, b.yaw, 0);
            if (seen(b.x, b.y)) dummy.scale.set(b.hx * 2, b.top - b.bottom, b.hy * 2);
            else dummy.scale.set(0.0001, 0.0001, 0.0001);
            dummy.updateMatrix();
            bldMesh.setMatrixAt(k, dummy.matrix);
        }
        bldMesh.instanceMatrix.needsUpdate = true;
        bldMesh.frustumCulled = false;   // las instancias cubren todo el mundo
    }

    function iconSprite(icon, color, scale) {
        var key = icon + color;
        var mat = spriteCache[key];
        if (!mat) {
            var tex = new T.CanvasTexture(window.ICONS.canvas(icon, color, 96));
            tex.encoding = T.sRGBEncoding;
            mat = spriteCache[key] = new T.SpriteMaterial({ map: tex, sizeAttenuation: false, depthTest: false, transparent: true });
        }
        var s = new T.Sprite(mat);
        s.scale.set(scale || 0.045, scale || 0.045, 1);
        s.renderOrder = 10;
        return s;
    }

    function topNear(x, y) {
        var best = groundAt(x, y);
        for (var k = 0; k < bldIndex.length; k++) {
            var b = bldIndex[k];
            if (Math.abs(b.x - x) < b.hx + 8 && Math.abs(b.y - y) < b.hy + 8 && seen(b.x, b.y)) best = Math.max(best, b.top);
        }
        return best;
    }

    // ---------------------------------------------------------------- bucle
    function loop() {
        raf = null;
        if (!active) return;
        controls.update();
        renderer.render(scene, camera);
        raf = requestAnimationFrame(loop);
    }

    function resize() {
        if (!inited) return;
        var r = container.getBoundingClientRect();
        renderer.setSize(Math.max(1, r.width), Math.max(1, r.height), false);
        camera.aspect = Math.max(1, r.width) / Math.max(1, r.height);
        camera.updateProjectionMatrix();
    }

    function pick(ev) {
        var r = renderer.domElement.getBoundingClientRect();
        pointer.x = ((ev.clientX - r.left) / r.width) * 2 - 1;
        pointer.y = -((ev.clientY - r.top) / r.height) * 2 + 1;
        raycaster.setFromCamera(pointer, camera);
        var hits = raycaster.intersectObjects([placeGroup, markerGroup], true);
        if (hits.length) {
            var o = hits[0].object;
            if (o.userData.place !== undefined && hooks.onPlace) return hooks.onPlace(o.userData.place);
            if (o.userData.marker !== undefined && hooks.onMarker) return hooks.onMarker(o.userData.marker);
        }
        hits = raycaster.intersectObject(bldMesh || terrainMesh, false);
        if (hits.length && hits[0].instanceId !== undefined) {
            var b = bldIndex[hits[0].instanceId];
            if (b && seen(b.x, b.y)) {
                highlight.position.set(b.x, b.bottom, -b.y);
                highlight.rotation.set(0, b.yaw, 0);
                highlight.scale.set(b.hx * 2 + 0.5, b.top - b.bottom + 0.5, b.hy * 2 + 0.5);
                highlight.visible = true;
                if (hooks.onBuilding) hooks.onBuilding({ x: b.x, y: b.y, height: Math.round(b.top - b.bottom), floors: Math.max(1, Math.round((b.top - b.bottom) / 3.5)), model: b.model });
                return;
            }
        }
        highlight.visible = false;
        hits = raycaster.intersectObject(terrainMesh, false);
        if (hits.length && hooks.onClick) {
            var p = hits[0].point;
            hooks.onClick(p.x, -p.z);
        }
    }

    function init() {
        if (inited || !T) return;
        inited = true;
        renderer = new T.WebGLRenderer({ antialias: true });
        renderer.setPixelRatio(window.devicePixelRatio || 1);
        renderer.outputEncoding = T.sRGBEncoding;
        container.appendChild(renderer.domElement);
        scene = new T.Scene();
        scene.background = new T.Color(0x0b0f16);
        scene.fog = new T.Fog(0x0b0f16, 4500, 12000);
        camera = new T.PerspectiveCamera(45, 1, 5, 30000);
        camera.position.set(1500, 1400, 2900);
        controls = new T.MapControls(camera, renderer.domElement);
        controls.enableDamping = true;
        controls.dampingFactor = 0.12;
        controls.screenSpacePanning = false;
        controls.maxPolarAngle = 1.35;
        controls.minDistance = 80;
        controls.maxDistance = 7500;
        controls.zoomSpeed = 1.2;
        controls.target.set(1500, 0, 1700);
        scene.add(new T.HemisphereLight(0xc4d0ff, 0x1d1712, 0.95));
        var sun = new T.DirectionalLight(0xffe3c4, 0.85);
        sun.position.set(-2500, 3500, 1500);
        scene.add(sun);
        raycaster = new T.Raycaster();
        pointer = new T.Vector2();
        buildTerrain();
        buildBuildings();
        placeGroup = new T.Group(); markerGroup = new T.Group();
        scene.add(placeGroup); scene.add(markerGroup);
        playerMesh = new T.Group();
        var cone = new T.Mesh(new T.ConeGeometry(12, 34, 3), new T.MeshBasicMaterial({ color: 0xf5a524 }));
        cone.rotation.x = -Math.PI / 2;   // punta hacia -Z (norte)
        playerMesh.add(cone);
        var beam = new T.Mesh(new T.CylinderGeometry(2.5, 2.5, 400, 8, 1, true),
            new T.MeshBasicMaterial({ color: 0xf5a524, transparent: true, opacity: 0.35, depthWrite: false }));
        beam.position.y = 200;
        playerMesh.add(beam);
        scene.add(playerMesh);
        destMesh = new T.Mesh(new T.CylinderGeometry(4, 4, 500, 8, 1, true),
            new T.MeshBasicMaterial({ color: 0xc55cff, transparent: true, opacity: 0.45, depthWrite: false }));
        destMesh.visible = false;
        scene.add(destMesh);
        var down = null;
        renderer.domElement.addEventListener("pointerdown", function (ev) { down = { x: ev.clientX, y: ev.clientY, b: ev.button }; });
        renderer.domElement.addEventListener("pointerup", function (ev) {
            var still = down && Math.abs(ev.clientX - down.x) + Math.abs(ev.clientY - down.y) < 5;
            if (still && down.b === 0) pick(ev);
            // clic derecho sin arrastrar (arrastrar con derecho desplaza la cámara): quita el destino
            else if (still && down.b === 2 && hooks.onRightClick) hooks.onRightClick();
            down = null;
        });
        window.addEventListener("resize", resize);
        paintTexture();
    }

    // ---------------------------------------------------------------- API
    window.Map3D = {
        setup: function (el, h) { container = el; hooks = h || {}; },
        available: function () {
            if (!T) return false;
            try { var c = document.createElement("canvas"); return !!(c.getContext("webgl") || c.getContext("experimental-webgl")); }
            catch (e) { return false; }
        },
        setActive: function (on) {
            if (on) init();
            active = on && inited;
            if (active) { resize(); if (!raf) raf = requestAnimationFrame(loop); }
        },
        setFog: function (cells, start, on) {
            fogState = { cells: cells, start: start, on: on };
            if (!inited) return;
            paintTexture();
            updateBuildings();
        },
        refreshTexture: function () { if (inited) paintTexture(); },
        setPlaces: function (list, cats, hidden) {
            if (!inited) return;
            while (placeGroup.children.length) placeGroup.remove(placeGroup.children[0]);
            for (var i = 0; i < list.length; i++) {
                var pl = list[i], c = cats[pl.cat];
                if (!c || hidden[pl.cat]) continue;
                var s = iconSprite(c.icon, c.color, 0.04);
                s.position.set(pl.x, topNear(pl.x, pl.y) + 18, -pl.y);
                s.userData.place = pl.id;
                placeGroup.add(s);
            }
        },
        setMarkers: function (list) {
            if (!inited) return;
            while (markerGroup.children.length) markerGroup.remove(markerGroup.children[0]);
            for (var i = 0; i < (list || []).length; i++) {
                var m = list[i];
                var s = iconSprite("pin", m.favorite ? "#f5a524" : "#4fd1ff", 0.04);
                s.position.set(m.x, groundAt(m.x, m.y) + 22, -m.y);
                s.userData.marker = m.id;
                markerGroup.add(s);
            }
        },
        setPlayer: function (p) {
            if (!inited || !p) return;
            playerMesh.visible = !p.inside;
            playerMesh.position.set(p.x, groundAt(p.x, p.y) + 20, -p.y);
            playerMesh.rotation.y = (p.rot || 0) * Math.PI / 180;
        },
        setRoute: function (pts, d) {
            if (!inited) return;
            if (routeMesh) { scene.remove(routeMesh); routeMesh.geometry.dispose(); routeMesh = null; }
            destMesh.visible = !!d;
            if (d) destMesh.position.set(d[0], groundAt(d[0], d[1]) + 250, -d[1]);
            if (!pts || pts.length < 4) return;
            var path = new T.CurvePath();
            var prev = null;
            for (var i = 0; i < pts.length; i += 2) {
                var v = new T.Vector3(pts[i], groundAt(pts[i], pts[i + 1]) + 5, -pts[i + 1]);
                if (prev && prev.distanceTo(v) > 0.5) path.add(new T.LineCurve3(prev, v));
                prev = v;
            }
            if (!path.curves.length) return;
            var geo = new T.TubeGeometry(path, Math.min(4000, path.curves.length * 2), 5, 6, false);
            routeMesh = new T.Mesh(geo, new T.MeshBasicMaterial({ color: 0xc55cff }));
            scene.add(routeMesh);
        },
        focus: function (x, y, dist) {
            if (!inited) return;
            var off = camera.position.clone().sub(controls.target);
            var len = dist || Math.min(off.length(), 1600);
            off.setLength(len);
            controls.target.set(x, groundAt(x, y), -y);
            camera.position.copy(controls.target).add(off);
        },
        zoom: function (k) {
            if (!inited) return;
            var off = camera.position.clone().sub(controls.target);
            off.setLength(Math.max(controls.minDistance, Math.min(controls.maxDistance, off.length() / k)));
            camera.position.copy(controls.target).add(off);
        },
        clearHighlight: function () { if (highlight) highlight.visible = false; },
        groundAt: groundAt,
    };
})();
