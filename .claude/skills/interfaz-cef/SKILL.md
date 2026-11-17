---
name: interfaz-cef
description: Crear o modificar una interfaz CEF (HTML/CSS/JS) de un recurso del gamemode Thorium con el patrón Lua cliente ↔ navegador ↔ servidor ya usado en rp_shops, rp_inventory y rp_login. Úsala para cualquier panel, menú o ventana nueva en el juego.
---

# Interfaz CEF

Referencias: `rp_shops` (ventana que se abre con E cerca de algo), `rp_inventory` (navegador
precreado que se muestra/oculta al instante), `rp_login` (pantalla completa al conectar).

## Flujo

```
JS (app.js) --mta.triggerEvent("rp:x:ui:accion")--> Lua cliente --triggerServerEvent("rp:x:accion")--> servidor
servidor --triggerClientEvent(player, "rp:x:show", resourceRoot, datos)--> Lua cliente --executeBrowserJavascript("RP.show(...)")--> JS
```

- El JS **nunca** habla con el servidor directo, y el servidor no confía en nada que venga de él (revalida todo).
- Eventos del CEF: `rp:<sistema>:ui:<accion>` con `addEvent(..., false)` (son locales del cliente).
- Eventos servidor→cliente: `addEvent(..., true)` en el cliente y handler sobre `resourceRoot`.

## Archivos

```
html/index.html   estructura, sin JS inline
html/style.css    paleta común
html/app.js       lógica; expone window.RP
```
Declarados con `<file src="html/..."/>` en `meta.xml`. Se cargan con `http://mta/local/html/index.html`.

## Lua cliente (patrón de rp_shops)

```lua
local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}

addEvent("rp:sistema:show", true)
addEvent("rp:sistema:ui:accion", false)
addEvent("rp:sistema:ui:close", false)

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

-- Strings a JS siempre escapados; tablas con toJSON(t, true) y [0]
local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function close()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
end

local function open()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
    showCursor(true)
    guiSetInputEnabled(true)
end

addEventHandler("rp:sistema:show", resourceRoot, function(titulo, lista)
    open()
    callJS(("RP.show(%s, %s[0])"):format(jsString(titulo), toJSON(lista or {}, true)))
end)

addEventHandler("rp:sistema:ui:accion", root, function(id)
    if type(id) ~= "string" then return end
    triggerServerEvent("rp:sistema:accion", resourceRoot, id)
end)

addEventHandler("rp:sistema:ui:close", root, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
addEventHandler("onClientResourceStop", resourceRoot, close)
```

- Con `guiSetInputEnabled(true)` los `bindKey` de MTA no se disparan: Esc y la tecla de cierre los escucha el JS.
- Si la UI se abre a menudo (inventario, teléfono), crea el navegador una vez al spawnear, ocúltalo con
  `guiSetVisible` y mantenlo sincronizado (ver `rp_inventory/client/c_inventory.lua`).
- Para pedir datos: el cliente dispara `rp:sistema:open` y el servidor valida y responde con `rp:sistema:show`.

## app.js

```js
/*
 * rp_sistema / app.js
 * Lua llama a RP.show(titulo, lista).
 */
(function () {
    "use strict";
    var $ = function (id) { return document.getElementById(id); };

    function send() {
        var args = Array.prototype.slice.call(arguments);
        if (window.mta && typeof mta.triggerEvent === "function") mta.triggerEvent.apply(mta, args);
        else console.log("[mta]", args);   // vista previa en un navegador normal
    }

    function el(tag, className, text) {
        var n = document.createElement(tag);
        if (className) n.className = className;
        if (text !== undefined) n.textContent = text;   // textContent, nunca innerHTML con datos
        return n;
    }

    $("btn-close").addEventListener("click", function () { send("rp:sistema:ui:close"); });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") send("rp:sistema:ui:close");
    });

    window.RP = {
        show: function (titulo, lista) { /* render */ }
    };
})();
```

- ES5 (`var`, `function`), sin frameworks ni CDNs: todo local en `html/`.
- Datos de jugadores siempre con `textContent` (nombres, notas, posts): evita inyección de HTML.
- Dinero con `"$" + Number(n).toLocaleString("es")`.

## Estilo

Copia las variables de `rp_shops/html/style.css`:

```css
:root {
    --bg: rgba(12, 14, 20, 0.95);
    --surface: rgba(255, 255, 255, 0.05);
    --surface-hover: rgba(255, 255, 255, 0.09);
    --border: rgba(255, 255, 255, 0.12);
    --text: #f2f4f8;
    --muted: #9aa3b2;
    --faint: #6f7888;
    --accent: #f5a524;
    --success: #4cd38a;
}
```

Ventana centrada (`.window`, borde 16px, sombra, animación `enter`), cabecera con título, pista de
teclas con `<kbd>` y botón `×`. Fuente `"Segoe UI", Roboto, Arial`. `user-select: none`. Textos en español.

## Probar

- Abre `html/index.html` en un navegador normal para maquetar (el `send` cae a `console.log`).
- En juego: abrir, cerrar con Esc y con `×`, morir con la UI abierta, reiniciar el recurso con la UI abierta.
