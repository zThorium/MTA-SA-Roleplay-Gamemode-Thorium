/*
 * rp_map / icons.js
 * Iconos de categoria dibujados en SVG (24x24, trazo blanco). Se usan en el mapa 2D (DOM),
 * en el 3D (se pintan en un canvas para los sprites) y en los paneles.
 */
(function () {
    "use strict";
    var P = {
        hospital: "M10 4h4v6h6v4h-6v6h-4v-6H4v-4h6z",
        police: "M12 2l8 3v6c0 5-3.4 9.4-8 11-4.6-1.6-8-6-8-11V5l8-3zm0 5l-1.5 3.1-3.4.4 2.5 2.3-.7 3.4L12 14.6l3.1 1.6-.7-3.4 2.5-2.3-3.4-.4z",
        shop: "M6 7h12l1 13H5L6 7zm3 0a3 3 0 016 0h-2a1 1 0 00-2 0z",
        cart: "M3 4h2.5l2.2 10h9.8l2-7H8m1 11a1.5 1.5 0 110 .1M17 18a1.5 1.5 0 110 .1",
        food: "M7 3v8a2 2 0 002 2v8h2v-8a2 2 0 002-2V3h-1.5v6h-1V3h-1v6h-1V3zM16 3c2 0 3 2.5 3 6s-1 4-2 4v8h-2V3z",
        bar: "M5 4h14l-6 8v6h4v2H7v-2h4v-6z",
        music: "M9 17.5a2.5 2.5 0 11-1-2V6l11-3v11.5a2.5 2.5 0 11-1-2V7.2L9 9.4z",
        gym: "M2 10h2V8h2v8H4v-2H2zm20 0h-2V8h-2v8h2v-2h2zM7 6h2v12H7zm8 0h2v12h-2zM9 11h6v2H9z",
        fuel: "M5 3h9v18H5zm2 2v5h5V5zm9 3l3 3v7a1 1 0 01-2 0v-4h-1v-2h1a1 1 0 011 1V11l-2-2z",
        atm: "M3 6h18v12H3zm9 2.5a1 1 0 00-1 1v.3c-1.2.3-2 1.1-2 2.2 0 1.4 1.3 2 2.8 2.3.9.2 1.2.4 1.2.7s-.4.6-1.2.6c-.9 0-1.4-.3-1.6-.9l-1.8.6c.3.9 1.1 1.6 2.6 1.8v.4h2v-.4c1.3-.3 2-1.2 2-2.3 0-1.5-1.3-2-2.9-2.4-.9-.2-1.1-.4-1.1-.6 0-.3.3-.5 1-.5.6 0 1 .2 1.2.6l1.7-.7c-.3-.7-1-1.3-1.9-1.5z",
        car: "M5 11l2-5h10l2 5h1v6h-2v2h-2v-2H8v2H6v-2H4v-6zm2.6-1h8.8l-1-3H8.6zM7 13.5a1.2 1.2 0 100 .1zm10 0a1.2 1.2 0 100 .1z",
        wrench: "M14.7 3.3a5 5 0 00-6 6.4L3 15.4 5.6 18 11.3 12.3a5 5 0 006.4-6l-3 3-2.6-.7-.7-2.6z",
        plane: "M21 16v-2l-8-5V3.5a1.5 1.5 0 00-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5z",
        train: "M7 3h10a3 3 0 013 3v9a3 3 0 01-2 2.8l1.5 2.2h-2.3L16 18H8l-1.2 2H4.5L6 17.8A3 3 0 014 15V6a3 3 0 013-3zm-1 4v4h12V7zm2 7a1.3 1.3 0 100 .1zm8 0a1.3 1.3 0 100 .1z",
        job: "M9 4h6a2 2 0 012 2v1h4v12H3V7h4V6a2 2 0 012-2zm0 3h6V6H9zM3 12h18v1.5H3z",
        building: "M5 3h10v4h4v14H5zm3 3v2h2V6zm4 0v2h2V6zm-4 4v2h2v-2zm4 0v2h2v-2zm4 0v2h2v-2zm-8 4v2h2v-2zm4 0v2h2v-2zm4 0v2h2v-2zm-6 4v3h2v-3z",
        house: "M12 3l9 8h-3v9h-5v-6h-2v6H6v-9H3z",
        apartment: "M4 3h16v18h-6v-4h-4v4H4zm3 3v2h2V6zm4 0v2h2V6zm4 0v2h2V6zM7 10v2h2v-2zm4 0v2h2v-2zm4 0v2h2v-2zM7 14v2h2v-2zm8 0v2h2v-2z",
        star: "M12 2.5l2.9 6 6.6.8-4.9 4.6 1.3 6.6L12 17.3l-5.9 3.2 1.3-6.6-4.9-4.6 6.6-.8z",
        pin: "M12 2a7 7 0 017 7c0 5-7 13-7 13S5 14 5 9a7 7 0 017-7zm0 4.5a2.5 2.5 0 100 5 2.5 2.5 0 000-5z",
        flag: "M5 3h2v18H5zm3 1h11l-3 4 3 4H8z",
        gun: "M3 8h17v4h-4l-1 2h-3l-1 3H6l1-5H3z",
        dice: "M5 4h14a1 1 0 011 1v14a1 1 0 01-1 1H5a1 1 0 01-1-1V5a1 1 0 011-1zm3 3a1.3 1.3 0 100 .1zm8 0a1.3 1.3 0 100 .1zm-4 4a1.3 1.3 0 100 .1zm-4 4a1.3 1.3 0 100 .1zm8 0a1.3 1.3 0 100 .1z",
        boat: "M4 15h16l-2 5H6zm7-12h2v10H7z",
    };
    // Trazo en vez de relleno para los que son lineas
    var STROKE = { cart: true };

    window.ICONS = {
        names: Object.keys(P),
        svg: function (name, size) {
            var d = P[name] || P.pin;
            size = size || 18;
            var attrs = STROKE[name] ? 'fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"' : 'fill="#fff"';
            return '<svg viewBox="0 0 24 24" width="' + size + '" height="' + size + '"><path ' + attrs + ' d="' + d + '"/></svg>';
        },
        // Para Three.js: dibuja el icono en un canvas con un circulo de color
        canvas: function (name, color, px) {
            px = px || 64;
            var c = document.createElement("canvas");
            c.width = c.height = px;
            var g = c.getContext("2d");
            g.beginPath();
            g.arc(px / 2, px / 2, px / 2 - 3, 0, Math.PI * 2);
            g.fillStyle = color || "#f5a524";
            g.fill();
            g.lineWidth = 3;
            g.strokeStyle = "rgba(10,12,18,.9)";
            g.stroke();
            var path = new Path2D(P[name] || P.pin);
            var k = (px * 0.56) / 24;
            g.save();
            g.translate(px * 0.22, px * 0.22);
            g.scale(k, k);
            if (STROKE[name]) { g.strokeStyle = "#fff"; g.lineWidth = 2; g.stroke(path); }
            else { g.fillStyle = "#fff"; g.fill(path); }
            g.restore();
            return c;
        },
    };
})();
