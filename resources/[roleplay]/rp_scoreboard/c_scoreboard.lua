--[[
    rp_scoreboard / c_scoreboard.lua
    Mantener Tab para ver: nombre del servidor, jugadores conectados y la lista
    de jugadores (ID, nombre y ping) ordenada por ID. Rueda del raton para
    desplazarse si no caben.
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.8, math.min(1.25, screenH / 900))

local visible = false
local scroll = 0
local W = math.floor(520 * s)
local ROW = math.floor(30 * s)
local HEADER = math.floor(86 * s)
local MAX_ROWS = math.floor((screenH * 0.7 - HEADER) / ROW)

local function sortedPlayers()
    local list = getElementsByType("player")
    table.sort(list, function(a, b)
        return (tonumber(getElementData(a, "id")) or 9999) < (tonumber(getElementData(b, "id")) or 9999)
    end)
    return list
end

local function draw()
    local players = sortedPlayers()
    local rows = math.min(#players, MAX_ROWS)
    scroll = math.max(0, math.min(scroll, #players - rows))

    local h = HEADER + rows * ROW + 40 * s
    local x, y = (screenW - W) / 2, (screenH - h) / 2

    dxDrawRectangle(x, y, W, h, tocolor(12, 14, 20, 230))
    dxDrawRectangle(x, y, W, 3 * s, tocolor(245, 165, 36, 255))

    local name = getElementData(resourceRoot, "server:name") or "MTA Roleplay"
    local maxPlayers = getElementData(resourceRoot, "server:maxPlayers") or "?"
    dxDrawText(name, x + 20 * s, y + 14 * s, x + W - 20 * s, y + 44 * s, tocolor(242, 244, 248), 1.5 * s, "default-bold", "left", "center", true)
    dxDrawText(("Jugadores activos: %d / %s"):format(#players, tostring(maxPlayers)), x + 20 * s, y + 44 * s, x + W - 20 * s, y + 64 * s,
        tocolor(154, 163, 178), 1.0 * s, "default", "left", "center")

    -- Cabecera de columnas
    local cy = y + HEADER - 18 * s
    local colId, colName, colPing = x + 20 * s, x + 80 * s, x + W - 20 * s
    dxDrawText("ID", colId, cy, 0, 0, tocolor(111, 120, 136), 0.9 * s, "default-bold")
    dxDrawText("Nombre", colName, cy, 0, 0, tocolor(111, 120, 136), 0.9 * s, "default-bold")
    dxDrawText("Ping", 0, cy, colPing, 0, tocolor(111, 120, 136), 0.9 * s, "default-bold", "right")

    for i = 1, rows do
        local player = players[i + scroll]
        local ry = y + HEADER + (i - 1) * ROW
        if player == localPlayer then
            dxDrawRectangle(x + 8 * s, ry, W - 16 * s, ROW, tocolor(245, 165, 36, 40))
        elseif i % 2 == 0 then
            dxDrawRectangle(x + 8 * s, ry, W - 16 * s, ROW, tocolor(255, 255, 255, 8))
        end
        local id = getElementData(player, "id") or "-"
        local pname = getPlayerName(player):gsub("_", " ")
        local r, g, b = 242, 244, 248
        if not getElementData(player, "rp:characterId") and player ~= localPlayer then r, g, b = 154, 163, 178 end
        dxDrawText(tostring(id), colId, ry, colId + 50 * s, ry + ROW, tocolor(245, 165, 36), 1.0 * s, "default-bold", "left", "center")
        dxDrawText(pname, colName, ry, colPing - 60 * s, ry + ROW, tocolor(r, g, b), 1.0 * s, "default", "left", "center", true)
        dxDrawText(tostring(getPlayerPing(player)), 0, ry, colPing, ry + ROW, tocolor(154, 163, 178), 1.0 * s, "default", "right", "center")
    end

    if #players > rows then
        dxDrawText(("Mostrando %d-%d de %d  (rueda del raton)"):format(scroll + 1, scroll + rows, #players),
            x, y + h - 30 * s, x + W, y + h - 8 * s, tocolor(111, 120, 136), 0.9 * s, "default", "center", "center")
    end
end

local function onScroll(key)
    scroll = scroll + (key == "mouse_wheel_down" and 1 or -1)
end

local function show(_, state)
    visible = state == "down"
    if visible then
        addEventHandler("onClientRender", root, draw)
        bindKey("mouse_wheel_up", "down", onScroll)
        bindKey("mouse_wheel_down", "down", onScroll)
    else
        removeEventHandler("onClientRender", root, draw)
        unbindKey("mouse_wheel_up", "down", onScroll)
        unbindKey("mouse_wheel_down", "down", onScroll)
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("tab", "both", show)
end)
