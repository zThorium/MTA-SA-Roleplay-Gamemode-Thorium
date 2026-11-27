--[[
    rp_metaldetector / c_fx.lua  (cliente)

    Efectos en el mundo:
    - Hoyos en la arena (decal plano que crece con cada palada y se desvanece).
    - Arena que salta al cavar (fxAddSand) y destellos (fxAddSparks).
    - Revelación del hallazgo: aro expansivo, el icono del objeto sale del hoyo girando con un brillo
      del color de su rareza, haz de luz para épicos/legendarios, chispas y destellos, y al final vuela
      hacia el jugador. Legendarios: plano cercano de cámara (HUD suprimido con setHudSuppressed).
    - Lo mismo, en pequeño, cuando otro jugador cercano encuentra algo bueno.
    API: MDX.fx.digHole(x,y,z,progress), MDX.fx.stroke(x,y,z,good), MDX.fx.reveal(data), MDX.fx.othersReveal(...)
]]

MDX = MDX or {}
MDX.fx = {}

local holes = {}     -- { x, y, z, size, target, born, fadeAt }
local reveals = {}   -- { x, y, z, item, rarity, start, dur, own, sparks = {} }
local closeup = nil  -- { x, y, z, start, dur, ang }
local flash = nil    -- { color, start, dur }

local HOLE_LIFE = 45000

----------------------------------------------------------------
-- Hoyos
----------------------------------------------------------------
local function holeAt(x, y)
    for _, h in ipairs(holes) do
        if getDistanceBetweenPoints2D(h.x, h.y, x, y) < 0.6 then return h end
    end
end

function MDX.fx.digHole(x, y, z, progress)
    local h = holeAt(x, y)
    if not h then
        h = { x = x, y = y, z = z, size = 0.2, born = getTickCount() }
        holes[#holes + 1] = h
        if #holes > 12 then table.remove(holes, 1) end
    end
    h.target = 0.35 + 0.75 * MDX.clamp(progress or 0, 0, 1)
    h.fadeAt = getTickCount() + HOLE_LIFE
end

-- Una palada: arena volando hacia un lado y un poco de polvo
function MDX.fx.stroke(x, y, z, good)
    local px, py = getElementPosition(localPlayer)
    local ax, ay = x - px, y - py
    local len = math.max(0.01, math.sqrt(ax * ax + ay * ay))
    ax, ay = ax / len, ay / len
    local n = good and 28 or 12
    for _ = 1, 3 do
        fxAddSand(x, y, z + 0.1, -ay * 0.6 + (math.random() - 0.5) * 0.4, ax * 0.6 + (math.random() - 0.5) * 0.4, 0.9 + math.random() * 0.6, n, 1)
    end
end

----------------------------------------------------------------
-- Revelación
----------------------------------------------------------------
function MDX.fx.reveal(data, own)
    local rarity = METALDETECTOR.RARITIES[data.rarity] or METALDETECTOR.RARITIES.common
    local r = {
        x = data.x, y = data.y, z = data.z, item = data.item, rarity = rarity, start = getTickCount(),
        dur = own and (rarity.closeup and 4000 or 2400) or 3000, own = own, sparks = {},
    }
    reveals[#reveals + 1] = r
    MDX.fx.digHole(data.x, data.y, data.z, 1)

    -- Explosión de arena y, en lo bueno, chispas doradas
    for _ = 1, 4 do
        fxAddSand(r.x, r.y, r.z + 0.1, (math.random() - 0.5) * 1.4, (math.random() - 0.5) * 1.4, 1.2 + math.random(), 40, 1)
    end
    if rarity.order >= 3 then
        fxAddSparks(r.x, r.y, r.z + 0.2, 0, 0, 1.5, 1.2, 25 * rarity.order, 0, 0, 0, true, 2, 1.2)
    end
    -- Destellos que suben girando alrededor del objeto
    for i = 1, 6 + rarity.order * 4 do
        r.sparks[i] = { a = math.random() * math.pi * 2, rad = 0.25 + math.random() * 0.5, speed = 0.6 + math.random() * 1.4,
            delay = math.random(0, 900), size = 0.08 + math.random() * 0.12 }
    end

    if own then
        flash = { color = rarity.color, start = getTickCount(), dur = rarity.order >= 4 and 900 or 500 }
        if rarity.closeup then
            local px, py = getElementPosition(localPlayer)
            closeup = { x = r.x, y = r.y, z = r.z, start = getTickCount(), dur = 3400, ang = math.atan2(py - r.y, px - r.x) + 0.6 }
            exports.rp_hud:setHudSuppressed("rp_metaldetector", true)
        end
    end
    return r
end

function MDX.fx.othersReveal(x, y, z, item, rarity)
    MDX.fx.reveal({ x = x, y = y, z = z, item = item, rarity = rarity }, false)
    MDX.sound3D(rarity == "legendary" and "reveal_legendary" or "sparkle", x, y, z, 0.7, 80)
end

local function endCloseup()
    if not closeup then return end
    closeup = nil
    setCameraTarget(localPlayer)
    exports.rp_hud:setHudSuppressed("rp_metaldetector", false)
end
MDX.fx.endCloseup = endCloseup
function MDX.fx.closeupActive() return closeup ~= nil end

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function flatQuad(tex, x, y, z, size, color)
    dxDrawMaterialLine3D(x, y - size / 2, z, x, y + size / 2, z, tex, size, color, x, y, z + 10)
end

local function drawHoles(now)
    local tex = MDX.tex("images/fx/hole.png")
    if not tex then return end
    for i = #holes, 1, -1 do
        local h = holes[i]
        h.size = h.size + ((h.target or h.size) - h.size) * 0.12
        local a = 1
        if now > h.fadeAt then a = 1 - (now - h.fadeAt) / 4000 end
        if a <= 0 then
            table.remove(holes, i)
        else
            flatQuad(tex, h.x, h.y, h.z + 0.04, h.size, tocolor(255, 255, 255, 255 * a))
        end
    end
end

local function drawReveal(r, now)
    local t = now - r.start
    if t > r.dur + 600 then return false end
    local c = r.rarity.color
    local glow, ring, sparkle = MDX.tex("images/fx/glow.png"), MDX.tex("images/fx/ring.png"), MDX.tex("images/fx/sparkle.png")
    local itemTex = MDX.itemTex(r.item)

    -- Aro expansivo en el suelo
    if ring and t < 900 then
        local k = t / 900
        flatQuad(ring, r.x, r.y, r.z + 0.06, 0.5 + 4 * MDX.easeOutCubic(k), MDX.rgba(c, 220 * (1 - k)))
    end

    -- Haz de luz (épico y legendario)
    if r.rarity.beam and glow then
        local a = MDX.clamp(t / 400, 0, 1) * MDX.clamp((r.dur + 600 - t) / 800, 0, 1)
        dxDrawMaterialLine3D(r.x, r.y, r.z, r.x, r.y, r.z + 30, glow, 0.9 + 0.2 * math.sin(t / 120), MDX.rgba(c, 120 * a))
        dxDrawMaterialLine3D(r.x, r.y, r.z, r.x, r.y, r.z + 6, glow, 0.35, tocolor(255, 255, 255, 160 * a))
    end

    -- El objeto sube girando, flota y al final vuela hacia el jugador
    local rise = MDX.easeOutBack(MDX.clamp(t / 900, 0, 1))
    local ix, iy, iz = r.x, r.y, r.z - 0.25 + 1.35 * rise + 0.06 * math.sin(t / 260)
    local scale = 0.55 + 0.1 * r.rarity.order / 5
    local flyT = r.own and MDX.clamp((t - r.dur) / 500, 0, 1) or 0
    if flyT > 0 then
        local px, py, pz = getPedBonePosition(localPlayer, 3)
        local e = flyT * flyT
        ix, iy, iz = MDX.lerp(ix, px, e), MDX.lerp(iy, py, e), MDX.lerp(iz, pz, e)
        scale = scale * (1 - 0.85 * e)
    end
    local fade = r.own and 1 or MDX.clamp((r.dur + 600 - t) / 600, 0, 1)

    if glow then
        local gs = (0.9 + 0.15 * math.sin(t / 150)) * (1.2 + 0.25 * r.rarity.order) * (1 - flyT * 0.8)
        dxDrawMaterialLine3D(ix, iy, iz + gs / 2, ix, iy, iz - gs / 2, glow, gs, MDX.rgba(c, 200 * fade))
    end
    if itemTex then
        local spin = math.abs(math.cos(t / 420))
        local w = scale * (0.18 + 0.82 * spin)
        dxDrawMaterialLine3D(ix, iy, iz + scale / 2, ix, iy, iz - scale / 2, itemTex, w, tocolor(255, 255, 255, 255 * fade))
    end

    -- Destellos
    if sparkle and flyT < 1 then
        for _, s in ipairs(r.sparks) do
            local st = t - s.delay
            if st > 0 then
                local k = (st % 1400) / 1400
                local a = s.a + st / 1000 * s.speed
                local sx, sy = r.x + math.cos(a) * s.rad, r.y + math.sin(a) * s.rad
                local sz = r.z + 0.2 + k * 1.8
                local sa = math.sin(k * math.pi) * fade
                local size = s.size * (0.6 + 0.4 * math.sin(st / 90))
                dxDrawMaterialLine3D(sx, sy, sz + size / 2, sx, sy, sz - size / 2, sparkle, size, MDX.rgba(c, 255 * sa))
            end
        end
    end
    return true
end

local function drawCloseup(now)
    if not closeup then return end
    local t = now - closeup.start
    if t > closeup.dur then return endCloseup() end
    local k = t / closeup.dur
    local ang = closeup.ang + k * 0.9
    local dist = 3.4 - 1.0 * MDX.easeOutCubic(k)
    local cx, cy = closeup.x + math.cos(ang) * dist, closeup.y + math.sin(ang) * dist
    setCameraMatrix(cx, cy, closeup.z + 0.9 + 0.3 * k, closeup.x, closeup.y, closeup.z + 0.9, 0, 70)
end

local function drawFlash(now)
    if not flash then return end
    local t = now - flash.start
    if t > flash.dur then flash = nil return end
    local tex = MDX.tex("images/fx/vignette.png")
    if tex then
        dxDrawImage(0, 0, MDX.sw, MDX.sh, tex, 0, 0, 0, MDX.rgba(flash.color, 220 * (1 - t / flash.dur)))
    end
end

addEventHandler("onClientPreRender", root, function()
    local now = getTickCount()
    if #holes > 0 then drawHoles(now) end
    for i = #reveals, 1, -1 do
        if not drawReveal(reveals[i], now) then table.remove(reveals, i) end
    end
    drawCloseup(now)
end)

addEventHandler("onClientRender", root, function()
    if flash then drawFlash(getTickCount()) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    endCloseup()
end)
