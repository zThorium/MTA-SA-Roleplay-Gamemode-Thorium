--[[
    rp_wasted / c_wasted.lua

    Muerte definitiva del personaje: el juego se ralentiza, la pantalla pasa a rojo
    con vineta oscura y aparece "wasted" en blanco al centro. Solo cliente.

    Con rp_injury la primera caida deja abatido (no es muerte): solo se muestra cuando
    "rp:downed" == "dying" (murio desangrado o por disparo en la cabeza).
    Sin rp_injury, cualquier muerte lo muestra.
]]

local CFG = {
    SPEED      = 0.25,   -- velocidad del juego al morir (1 = normal)
    FADE_IN    = 1200,   -- ms hasta tinte y camara lenta completos
    FADE_OUT   = 600,    -- ms al reaparecer
    TEXT_DELAY = 500,    -- ms antes de que aparezca el texto
    TEXT_SCALE = 3.2,
}

local SHADER_SRC = [[
texture ScreenTexture;
float Amount = 0;
sampler S = sampler_state { Texture = (ScreenTexture); };
float4 PS(float2 uv : TEXCOORD0) : COLOR0
{
    float4 c = tex2D(S, uv);
    float l = dot(c.rgb, float3(0.3, 0.59, 0.11));
    l = saturate((l - 0.5) * 1.3 + 0.5);
    float3 red = float3(l * 1.15 + 0.05, l * 0.12, l * 0.2);
    float v = 1.0 - smoothstep(0.25, 0.85, distance(uv, float2(0.5, 0.5))) * 0.7;
    return float4(lerp(c.rgb, red * v, Amount), 1);
}
technique T { pass P0 { PixelShader = compile ps_2_0 PS(); } }
]]

local sw, sh = guiGetScreenSize()
local shader, source
local active, startTick, endTick = false, 0, nil

local function injuryRunning()
    local res = getResourceFromName("rp_injury")
    return res and getResourceState(res) == "running"
end

local function stop()
    if active then removeEventHandler("onClientRender", root, render) end
    active, endTick = false, nil
    setGameSpeed(1)
    if isElement(shader) then destroyElement(shader) end
    if isElement(source) then destroyElement(source) end
    shader, source = nil, nil
end

function render()
    local now = getTickCount()
    local k = math.min((now - startTick) / CFG.FADE_IN, 1)
    if endTick then k = k * (1 - math.min((now - endTick) / CFG.FADE_OUT, 1)) end
    if endTick and now - endTick >= CFG.FADE_OUT then return stop() end
    setGameSpeed(1 - (1 - CFG.SPEED) * k)

    dxUpdateScreenSource(source)
    dxSetShaderValue(shader, "ScreenTexture", source)
    dxSetShaderValue(shader, "Amount", k)
    dxDrawImage(0, 0, sw, sh, shader)

    local t = math.min(math.max((now - startTick - CFG.TEXT_DELAY) / 800, 0), 1)
    if t > 0 then
        local a = math.floor(255 * t * (endTick and k or 1))
        local scale = CFG.TEXT_SCALE * (1.12 - 0.12 * t)   -- se asienta al aparecer
        dxDrawText("wasted", 3, 3, sw + 3, sh + 3, tocolor(0, 0, 0, a * 0.6), scale, "pricedown", "center", "center")
        dxDrawText("wasted", 0, 0, sw, sh, tocolor(255, 255, 255, a), scale, "pricedown", "center", "center")
    end
end

local function start()
    if active then return end
    shader = dxCreateShader(SHADER_SRC)
    source = dxCreateScreenSource(sw, sh)
    if not shader or not source then return stop() end
    active, startTick = true, getTickCount()
    addEventHandler("onClientRender", root, render)
end

addEventHandler("onClientPlayerWasted", localPlayer, function()
    if injuryRunning() and getElementData(localPlayer, "rp:downed") ~= "dying" then return end
    start()
end)

addEventHandler("onClientPlayerSpawn", localPlayer, function()
    if active then endTick = getTickCount() end
end)

addEventHandler("onClientResourceStop", resourceRoot, stop)
