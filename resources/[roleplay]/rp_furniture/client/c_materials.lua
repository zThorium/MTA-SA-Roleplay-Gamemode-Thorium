--[[
    rp_furniture / c_materials.lua
    Materiales procedurales (texturas de 128x128 generadas por pixel, sin archivos) y shader de
    tinte por mueble. API (global del cliente, la usan c_core.lua y c_editor.lua):
        FurnStyle.apply(obj, colorRGB|nil, matId|nil, alpha|nil)   aplica o quita el estilo
        FurnStyle.clear(obj)
        FurnStyle.getMaterialTexture(id)
]]

FurnStyle = {}

local SIZE = 128
local textures = {}      -- [matId] = textura
local shaders = {}       -- [obj] = shader
local shaderOk = true

----------------------------------------------------------------
-- Ruido y generadores (u, v en 0..1, deben repetirse sin costura)
----------------------------------------------------------------
local function hash(ix, iy, seed)
    local n = math.sin(ix * 127.1 + iy * 311.7 + (seed or 0) * 74.7) * 43758.5453
    return n - math.floor(n)
end

-- ruido de valor que se repite cada `period` celdas
local function vnoise(x, y, period, seed)
    local ix, iy = math.floor(x), math.floor(y)
    local fx, fy = x - ix, y - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    local function h(a, b) return hash(a % period, b % period, seed) end
    local a, b = h(ix, iy), h(ix + 1, iy)
    local c, d = h(ix, iy + 1), h(ix + 1, iy + 1)
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
end

local function mix(a, b, t) return a + (b - a) * t end
local function clamp(v) return math.max(0, math.min(255, v)) end

local GEN = {}

GEN.liso = function() return 235, 235, 235 end

GEN.madera = function(u, v)
    local planks = 4
    local pu = u * planks
    local id = math.floor(pu)
    local tone = 0.82 + 0.28 * hash(id, 3, 1)
    local grain = vnoise(pu * 3 + id * 11, v * 40, 24, 2) * 0.5 + vnoise(pu * 9, v * 9, 16, 3) * 0.5
    local gap = (pu - id < 0.04 or pu - id > 0.96) and 0.45 or 1
    local k = tone * (0.78 + 0.3 * grain) * gap
    return clamp(168 * k), clamp(118 * k), clamp(68 * k)
end

GEN.parquet = function(u, v)
    local n = 6
    local cu, cv = math.floor(u * n), math.floor(v * n)
    local fu, fv = u * n - cu, v * n - cv
    local horiz = (cu + cv) % 2 == 0
    local s = horiz and fv or fu
    local plank = math.floor(s * 3)
    local tone = 0.78 + 0.3 * hash(cu * 3 + plank, cv, 5)
    local edge = (math.abs((s * 3) % 1 - 0.5) > 0.46) and 0.55 or 1
    local g = 0.88 + 0.12 * vnoise((horiz and fu or fv) * 12, plank * 7, 12, 6)
    local k = tone * edge * g
    return clamp(176 * k), clamp(126 * k), clamp(78 * k)
end

GEN.baldosa = function(u, v)
    local n = 4
    local fu, fv = (u * n) % 1, (v * n) % 1
    local grout = (fu < 0.04 or fu > 0.96 or fv < 0.04 or fv > 0.96)
    local tone = 0.93 + 0.07 * hash(math.floor(u * n), math.floor(v * n), 7)
    if grout then return 120, 124, 128 end
    return clamp(232 * tone), clamp(234 * tone), clamp(238 * tone)
end

GEN.ajedrez = function(u, v)
    local n = 4
    local c = (math.floor(u * n) + math.floor(v * n)) % 2 == 0
    if c then return 238, 238, 238 end
    return 28, 28, 32
end

GEN.rayas = function(u)
    local n = 8
    if math.floor(u * n) % 2 == 0 then return 236, 232, 222 end
    return 168, 54, 62
end

GEN.ladrillo = function(u, v)
    local rows, cols = 8, 4
    local row = math.floor(v * rows)
    local su = u * cols + (row % 2) * 0.5
    local col = math.floor(su)
    local fu, fv = su - col, v * rows - row
    if fu < 0.06 or fv < 0.1 then return 196, 190, 180 end
    local tone = 0.78 + 0.3 * hash(col, row, 8)
    local g = 0.9 + 0.1 * vnoise(su * 9, v * 40, 24, 9)
    return clamp(170 * tone * g), clamp(78 * tone * g), clamp(58 * tone * g)
end

GEN.concreto = function(u, v)
    local a = vnoise(u * 16, v * 16, 16, 10)
    local b = vnoise(u * 48, v * 48, 48, 11)
    local k = 0.72 + 0.2 * a + 0.12 * b
    return clamp(170 * k), clamp(170 * k), clamp(172 * k)
end

GEN.alfombra = function(u, v)
    local a = vnoise(u * 64, v * 64, 64, 12)
    local weave = 0.92 + 0.08 * math.sin(u * 128 * math.pi) * math.sin(v * 128 * math.pi)
    local k = (0.8 + 0.25 * a) * weave
    return clamp(150 * k), clamp(138 * k), clamp(126 * k)
end

GEN.cuadros = function(u, v)
    local bandU = 0.5 + 0.5 * math.sin(u * 2 * math.pi * 4)
    local bandV = 0.5 + 0.5 * math.sin(v * 2 * math.pi * 4)
    local thin = (0.5 + 0.5 * math.sin(u * 2 * math.pi * 16)) * (0.5 + 0.5 * math.sin(v * 2 * math.pi * 16))
    local r = mix(210, 120, bandU * 0.7 + bandV * 0.7)
    local g = mix(200, 40, bandU * 0.9)
    local b = mix(190, 52, bandV * 0.9)
    local k = 0.85 + 0.15 * thin
    return clamp(r * k), clamp(g * k), clamp(b * k)
end

----------------------------------------------------------------
-- Texturas
----------------------------------------------------------------
function FurnStyle.getMaterialTexture(id)
    if textures[id] and isElement(textures[id]) then return textures[id] end
    local gen = GEN[id]
    if not gen then return nil end
    local tex = dxCreateTexture(SIZE, SIZE, "argb", "wrap")
    if not tex then return nil end
    local pixels = dxGetTexturePixels(tex)
    if not pixels then destroyElement(tex) return nil end
    for y = 0, SIZE - 1 do
        local v = y / SIZE
        for x = 0, SIZE - 1 do
            local r, g, b = gen(x / SIZE, v)
            dxSetPixelColor(pixels, x, y, r, g, b, 255)
        end
    end
    dxSetTexturePixels(tex, pixels)
    textures[id] = tex
    return tex
end

----------------------------------------------------------------
-- Shader por objeto
----------------------------------------------------------------
local function rgb(c)
    return (math.floor(c / 65536) % 256) / 255, (math.floor(c / 256) % 256) / 255, (c % 256) / 255
end

function FurnStyle.clear(obj)
    local sh = shaders[obj]
    if sh then
        if isElement(sh) then
            engineRemoveShaderFromWorldTexture(sh, "*", obj)
            destroyElement(sh)
        end
        shaders[obj] = nil
    end
end

function FurnStyle.apply(obj, color, matId, alpha)
    if not isElement(obj) then return end
    local plain = (not color or color == 0xFFFFFF) and (not matId or matId == "liso") and (not alpha or alpha >= 1)
    if plain then return FurnStyle.clear(obj) end
    if not shaderOk then return end

    local sh = shaders[obj]
    if not sh or not isElement(sh) then
        sh = dxCreateShader("fx/tint.fx", 0, 0, false, "object")
        if not sh then
            shaderOk = false
            outputDebugString("[rp_furniture] No se pudo compilar fx/tint.fx: los colores y materiales no se veran.", 2)
            return
        end
        shaders[obj] = sh
        engineApplyShaderToWorldTexture(sh, "*", obj)
    end
    local r, g, b = rgb(color or 0xFFFFFF)
    dxSetShaderValue(sh, "sTint", r, g, b)
    dxSetShaderValue(sh, "sAlpha", alpha or 1)
    local tex = matId and matId ~= "liso" and FurnStyle.getMaterialTexture(matId)
    if tex then
        dxSetShaderValue(sh, "sMatTex", tex)
        dxSetShaderValue(sh, "sUseMat", 1)
    else
        dxSetShaderValue(sh, "sUseMat", 0)
    end
end

addEventHandler("onClientElementDestroy", root, function()
    if shaders[source] then FurnStyle.clear(source) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for obj in pairs(shaders) do FurnStyle.clear(obj) end
end)
