--[[
    rp_clothing / c_gizmo.lua
    Gizmo 3D estilo Blender para colocar un accesorio pegado a un hueso (bone_attach).

      Mover   (G): tres flechas en los ejes del HUESO. Arrastrar una flecha mueve el
                   accesorio solo en ese eje (el offset x/y/z de bone_attach es justo eso).
      Rotar   (R): tres anillos alrededor de los ejes del OBJETO. Arrastrar un anillo lo
                   gira sobre ese eje; se pasa a los angulos rx/ry/rz de bone_attach.
      Escalar (S): tres cubos en los ejes del objeto (un eje) y uno blanco en el centro (todo).
      Shift = precision (10 veces mas lento) · Ctrl = encajar (1 cm, 15 grados, 5 %).

    Matematica (misma convencion que bone_attach/bone_pos_rot_fixed.lua, matrices por filas):
      B = matriz del hueso (filas = ejes X, Y, Z del hueso en el mundo)
      R = matriz de los angulos rx, ry, rz del accesorio
      posicion = hueso + x*B1 + y*B2 + z*B3      orientacion del objeto T = R * B
      Girar el objeto sobre su eje local i un angulo a:  R' = Q_i(a) * R

    Todo se dibuja en 2D (proyectando los puntos) para que siempre quede por encima
    del personaje y el clic se compruebe en pantalla, igual que lo que se ve.

    API: Gizmo.start{ ped, object, values, onChange(values), onCommit(antes) }, Gizmo.stop(),
         Gizmo.setMode(m), Gizmo.getMode(), Gizmo.press(x, y), Gizmo.move(x, y), Gizmo.release(),
         Gizmo.isDragging(), Gizmo.getOrigin(), Gizmo.render()
]]

Gizmo = {}

local screenW, screenH = guiGetScreenSize()
local G = nil   -- { ped, object, values, onChange, onCommit, mode, hover, drag, frame }

local AXIS_COLOR = {
    tocolor(235, 70, 70), tocolor(110, 205, 80), tocolor(70, 140, 255),
}
local HOVER_COLOR = tocolor(255, 214, 60)
local CENTER_COLOR = tocolor(240, 240, 240)
local KEYS_POS = { "x", "y", "z" }
local KEYS_ROT = { "rx", "ry", "rz" }
local KEYS_SCALE = { "sx", "sy", "sz" }
local HIT_PX = 10
local RING_SEGMENTS = 48

----------------------------------------------------------------
-- Matematica
----------------------------------------------------------------
local function matrixFromEuler(x, y, z)
    x, y, z = math.rad(x), math.rad(y), math.rad(z)
    local sx, cx, sy, cy, sz, cz = math.sin(x), math.cos(x), math.sin(y), math.cos(y), math.sin(z), math.cos(z)
    return {
        { cy * cz - sy * sx * sz, cy * sz + sy * sx * cz, -sy * cx },
        { -cx * sz, cx * cz, sx },
        { sy * cz + cy * sx * sz, sy * sz - cy * sx * cz, cy * cx },
    }
end

local function eulerFromMatrix(m)
    local x1, y1, z1 = m[1][1], m[1][2], m[1][3]
    local x2, y2, z2 = m[2][1], m[2][2], m[2][3]
    local x3, y3, z3 = m[3][1], m[3][2], m[3][3]
    z2 = math.max(-1, math.min(1, z2))
    local nz3 = math.sqrt(x2 * x2 + y2 * y2)
    if nz3 < 1e-6 then nz3 = 1e-6 end
    local nz1, nz2 = -x2 * z2 / nz3, -y2 * z2 / nz3
    local vx = nz1 * x1 + nz2 * y1 + nz3 * z1
    local vz = nz1 * x3 + nz2 * y3 + nz3 * z3
    return math.deg(math.asin(z2)), -math.deg(math.atan2(vx, vz)), -math.deg(math.atan2(x2, y2))
end

local function mul(a, b)   -- a * b (3x3)
    local r = {}
    for i = 1, 3 do
        r[i] = {}
        for j = 1, 3 do r[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end
    end
    return r
end

local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end

-- Gira el vector v sobre el eje unitario k un angulo a (Rodrigues)
local function rotateVec(v, k, a)
    local c, s = math.cos(a), math.sin(a)
    local kxv, kv = cross(k, v), dot(k, v) * (1 - c)
    return { v[1] * c + kxv[1] * s + k[1] * kv, v[2] * c + kxv[2] * s + k[2] * kv, v[3] * c + kxv[3] * s + k[3] * kv }
end

-- Q_i(a): base estandar girada sobre el eje i
local function localRotation(i, a)
    local e = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
    return { rotateVec(e[1], e[i], a), rotateVec(e[2], e[i], a), rotateVec(e[3], e[i], a) }
end

local function project(x, y, z)
    local sx, sy = getScreenFromWorldPosition(x, y, z, 0, false)
    return sx, sy
end

local function distToSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = len2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
    local cx, cy = ax + dx * t, ay + dy * t
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

local function clamp(n, a, b) return math.max(a, math.min(b, n)) end
local function copy(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end

----------------------------------------------------------------
-- Marco actual: hueso, orientacion del objeto, origen y tamano
----------------------------------------------------------------
local function computeFrame()
    local v = G.values
    local bx, by, bz, B
    -- Cabeza custom (rp_heads): el accesorio va pegado al objeto cabeza, el gizmo tambien
    local lo, LB = HeadLink.getFrame(G.ped, v.bone)
    if lo then
        bx, by, bz, B = lo[1], lo[2], lo[3], LB
    else
        local brx, bry, brz
        bx, by, bz, brx, bry, brz = exports.bone_attach:getBonePositionAndRotation(G.ped, v.bone)
        if not bx or bx ~= bx or brx ~= brx then return nil end
        B = matrixFromEuler(brx, bry, brz)
    end
    local function place(M)
        return bx + v.x * M[1][1] + v.y * M[2][1] + v.z * M[3][1],
               by + v.x * M[1][2] + v.y * M[2][2] + v.z * M[3][2],
               bz + v.x * M[1][3] + v.y * M[2][3] + v.z * M[3][3]
    end
    local ox, oy, oz = place(B)
    -- bone_attach corrige el signo del cuello (hueso 2) y su export no: se elige la base que
    -- deja el gizmo donde esta de verdad el objeto.
    if v.bone == 2 and isElement(G.object) and (math.abs(v.x) + math.abs(v.y)) > 0.01 then
        local ax, ay, az = getElementPosition(G.object)
        local F = { { -B[1][1], -B[1][2], -B[1][3] }, { -B[2][1], -B[2][2], -B[2][3] }, B[3] }
        local fx, fy, fz = place(F)
        if getDistanceBetweenPoints3D(ax, ay, az, fx, fy, fz) < getDistanceBetweenPoints3D(ax, ay, az, ox, oy, oz) then
            B, ox, oy, oz = F, fx, fy, fz
        end
    end
    local R = matrixFromEuler(v.rx, v.ry, v.rz)
    local T = mul(R, B)
    local cx, cy, cz = getCameraMatrix()
    local size = getDistanceBetweenPoints3D(cx, cy, cz, ox, oy, oz) * 0.16
    return { B = B, R = R, T = T, o = { ox, oy, oz }, size = size, cam = { cx, cy, cz } }
end

----------------------------------------------------------------
-- Piezas del gizmo en pantalla
----------------------------------------------------------------
-- Devuelve la lista de piezas: { kind, axis, pts = {{x,y},...} o seg, ... }
local function handles(f)
    local list = {}
    local o, s = f.o, f.size
    local so = { project(o[1], o[2], o[3]) }
    if not so[1] then return list, nil end
    local mode = G.mode
    if mode == "move" or mode == "scale" then
        local axes = mode == "move" and f.B or f.T
        for i = 1, 3 do
            local a = axes[i]
            local ex, ey = project(o[1] + a[1] * s, o[2] + a[2] * s, o[3] + a[3] * s)
            if ex then list[#list + 1] = { kind = "axis", axis = i, a = so, b = { ex, ey }, dir = a } end
        end
        if mode == "scale" then list[#list + 1] = { kind = "center", a = so } end
    else
        for i = 1, 3 do
            local u, w = f.T[i % 3 + 1], f.T[(i + 1) % 3 + 1]
            local pts = {}
            for k = 0, RING_SEGMENTS do
                local t = k / RING_SEGMENTS * math.pi * 2
                local c, sn = math.cos(t) * s * 0.85, math.sin(t) * s * 0.85
                local px, py = project(o[1] + u[1] * c + w[1] * sn, o[2] + u[2] * c + w[2] * sn, o[3] + u[3] * c + w[3] * sn)
                pts[#pts + 1] = px and { px, py } or false
            end
            list[#list + 1] = { kind = "ring", axis = i, pts = pts, dir = f.T[i] }
        end
    end
    return list, so
end

local function hitTest(list, mx, my)
    local best, bestD = nil, HIT_PX
    for _, h in ipairs(list) do
        local d = math.huge
        if h.kind == "axis" then
            d = distToSegment(mx, my, h.a[1], h.a[2], h.b[1], h.b[2])
            -- la punta cuenta mas: se prefiere a la flecha que pasa por el centro
            local tip = math.sqrt((mx - h.b[1]) ^ 2 + (my - h.b[2]) ^ 2)
            if tip < HIT_PX + 4 then d = tip * 0.5 end
        elseif h.kind == "center" then
            d = math.sqrt((mx - h.a[1]) ^ 2 + (my - h.a[2]) ^ 2) - 4
        else
            for k = 1, #h.pts - 1 do
                local p, q = h.pts[k], h.pts[k + 1]
                if p and q then d = math.min(d, distToSegment(mx, my, p[1], p[2], q[1], q[2])) end
            end
        end
        if d < bestD then best, bestD = h, d end
    end
    return best
end

local function same(a, b)
    return a and b and a.kind == b.kind and a.axis == b.axis
end

local function drawSquare(x, y, r, color)
    dxDrawRectangle(x - r, y - r, r * 2, r * 2, tocolor(10, 10, 14, 200))
    dxDrawRectangle(x - r + 1.5, y - r + 1.5, r * 2 - 3, r * 2 - 3, color)
end

local function drawArrowHead(a, b, color, size)
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    dx, dy = dx / len, dy / len
    local tipX, tipY = b[1] + dx * size, b[2] + dy * size
    local lx, ly = b[1] - dy * size * 0.55, b[2] + dx * size * 0.55
    local rx, ry = b[1] + dy * size * 0.55, b[2] - dx * size * 0.55
    dxDrawPrimitive("trianglelist", false, { tipX, tipY, color }, { lx, ly, color }, { rx, ry, color })
end

local function drawHandles(list, so)
    local active = G.drag and G.drag.handle or G.hover
    for _, h in ipairs(list) do
        local hot = same(h, active)
        local color = hot and HOVER_COLOR or (h.kind == "center" and CENTER_COLOR or AXIS_COLOR[h.axis])
        local faded = G.drag and not hot
        if faded then color = tocolor(150, 150, 150, 120) end
        if h.kind == "axis" then
            dxDrawLine(h.a[1], h.a[2], h.b[1], h.b[2], tocolor(10, 10, 14, 160), hot and 7 or 5)
            dxDrawLine(h.a[1], h.a[2], h.b[1], h.b[2], color, hot and 4 or 2.5)
            if G.mode == "move" then drawArrowHead(h.a, h.b, color, hot and 15 or 12)
            else drawSquare(h.b[1], h.b[2], hot and 7 or 5.5, color) end
        elseif h.kind == "center" then
            drawSquare(h.a[1], h.a[2], hot and 8 or 6.5, color)
        else
            for k = 1, #h.pts - 1 do
                local p, q = h.pts[k], h.pts[k + 1]
                if p and q then dxDrawLine(p[1], p[2], q[1], q[2], color, hot and 4 or 2.5) end
            end
        end
    end
    if so then dxDrawRectangle(so[1] - 2, so[2] - 2, 4, 4, tocolor(255, 255, 255, 220)) end
end

----------------------------------------------------------------
-- API
----------------------------------------------------------------
function Gizmo.start(opts)
    G = {
        ped = opts.ped, object = opts.object, values = opts.values,
        onChange = opts.onChange, onCommit = opts.onCommit,
        mode = "move", hover = nil, drag = nil, frame = nil,
    }
end

function Gizmo.stop() G = nil end
function Gizmo.active() return G ~= nil end
function Gizmo.isDragging() return G ~= nil and G.drag ~= nil end
function Gizmo.getMode() return G and G.mode end

function Gizmo.setMode(m)
    if G and (m == "move" or m == "rotate" or m == "scale") and not G.drag then
        G.mode, G.hover = m, nil
    end
end

function Gizmo.setValues(values)
    if G then G.values = values end
end

function Gizmo.getOrigin()
    if G and G.frame then return G.frame.o[1], G.frame.o[2], G.frame.o[3] end
end

-- Clic en (mx, my): true si agarra una pieza del gizmo
function Gizmo.press(mx, my)
    if not G or G.drag then return false end
    local f = computeFrame()
    if not f then return false end
    local list, so = handles(f)
    local h = hitTest(list, mx, my)
    if not h then return false end
    local d = { handle = h, start = copy(G.values), m0 = { mx, my }, frame = f, so = so }
    if h.kind == "axis" then
        local dx, dy = h.b[1] - h.a[1], h.b[2] - h.a[2]
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 6 then return false end   -- eje apuntando a la camara: no se puede arrastrar bien
        d.ux, d.uy, d.pxPerMeter = dx / len, dy / len, len / f.size
    elseif h.kind == "ring" then
        d.last = math.atan2(my - so[2], mx - so[1])
        d.total = 0
        local o, c = f.o, f.cam
        d.toward = dot(h.dir, { c[1] - o[1], c[2] - o[2], c[3] - o[3] }) > 0
    end
    G.drag = d
    return true
end

function Gizmo.move(mx, my)
    local d = G and G.drag
    if not d then return end
    local v, s0, L = G.values, d.start, CLOTHING.LIMITS
    local precise = getKeyState("lshift") or getKeyState("rshift")
    local snap = getKeyState("lctrl") or getKeyState("rctrl")
    local k = precise and 0.1 or 1
    local h = d.handle

    if G.mode == "move" and h.kind == "axis" then
        local meters = ((mx - d.m0[1]) * d.ux + (my - d.m0[2]) * d.uy) / d.pxPerMeter * k
        local key = KEYS_POS[h.axis]
        local n = s0[key] + meters
        if snap then n = math.floor(n / 0.01 + 0.5) * 0.01 end
        v[key] = clamp(n, -L.pos, L.pos)
    elseif G.mode == "scale" then
        local f
        if h.kind == "center" then
            f = 1 + (d.m0[2] - my) / 160 * k
        else
            f = 1 + ((mx - d.m0[1]) * d.ux + (my - d.m0[2]) * d.uy) / d.pxPerMeter / d.frame.size * k
        end
        f = math.max(0.05, f)
        local keys = h.kind == "center" and KEYS_SCALE or { KEYS_SCALE[h.axis] }
        for _, key in ipairs(keys) do
            local n = s0[key] * f
            if snap then n = math.floor(n / 0.05 + 0.5) * 0.05 end
            v[key] = clamp(n, L.scaleMin, L.scaleMax)
        end
    elseif G.mode == "rotate" and h.kind == "ring" then
        local a = math.atan2(my - d.so[2], mx - d.so[1])
        local diff = a - d.last
        if diff > math.pi then diff = diff - 2 * math.pi elseif diff < -math.pi then diff = diff + 2 * math.pi end
        d.last = a
        d.total = d.total + diff * k
        -- En pantalla la Y crece hacia abajo: un giro "a favor" del raton es horario. Si el eje
        -- apunta a la camara, el giro positivo (mano derecha) se ve antihorario.
        local angle = d.toward and -d.total or d.total
        if snap then angle = math.floor(math.deg(angle) / 15 + 0.5) * math.rad(15) end
        local R = mul(localRotation(h.axis, angle), matrixFromEuler(s0.rx, s0.ry, s0.rz))
        v.rx, v.ry, v.rz = eulerFromMatrix(R)
    end
    if G.onChange then G.onChange(v) end
end

function Gizmo.release()
    local d = G and G.drag
    if not d then return end
    G.drag = nil
    local changed = false
    for k, n in pairs(d.start) do if G.values[k] ~= n then changed = true break end end
    if changed and G.onCommit then G.onCommit(d.start, G.mode) end
end

-- Se llama cada frame (onClientRender) mientras se edita
function Gizmo.render()
    if not G or not isElement(G.ped) then return end
    local f = computeFrame()
    G.frame = f
    if not f then return end
    local list, so = handles(f)
    if not G.drag and isCursorShowing() then
        local cx, cy = getCursorPosition()
        G.hover = cx and hitTest(list, cx * screenW, cy * screenH) or nil
    end
    drawHandles(list, so)
end

function Gizmo.isHovering() return G ~= nil and G.hover ~= nil end
