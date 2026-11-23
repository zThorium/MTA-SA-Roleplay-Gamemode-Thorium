--[[
    rp_inventory / s_icons.lua (compartido)
    Iconos vectoriales (SVG) de items que tienen uno propio. Cada item puede llevar iconImg = ITEM_ICON_IMG.<id>;
    las interfaces CEF lo pintan como <img> y, si falta, usan el emoji de `icon`.
    Son data-URI, asi llegan a cualquier panel (inventario, tiendas, mochila) sin copiar archivos entre recursos.
    Los colores de las mochilas son los mismos que los de su shader (rp_backpacks/shared/s_config.lua).
]]

local function uri(svg)
    svg = svg:gsub("%s*\n%s*", "")
    return "data:image/svg+xml;utf8," .. (svg:gsub("[<>#\"]", function(c) return ("%%%02X"):format(c:byte()) end))
end

ITEM_ICON_IMG = {
    -- Mochila pequena: compacta, verde azulado, cremallera con tirador amarillo
    bp_small = uri([[<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'>
<path d='M25 15c0-7 14-7 14 0' fill='none' stroke='#0d4a45' stroke-width='3' stroke-linecap='round'/>
<rect x='17' y='15' width='30' height='42' rx='12' fill='#2bb3a3' stroke='#0d4a45' stroke-width='2.5'/>
<path d='M20 29h24' stroke='#0d4a45' stroke-width='2.5' stroke-linecap='round'/>
<circle cx='32' cy='29' r='2.8' fill='#ffd166' stroke='#0d4a45' stroke-width='1.2'/>
<rect x='23' y='36' width='18' height='15' rx='6' fill='#1f8f83' stroke='#0d4a45' stroke-width='2'/>
<path d='M28 43h8' stroke='#ffd166' stroke-width='2.5' stroke-linecap='round'/>
</svg>]]),

    -- Mochila escolar: azul marino con solapa, franja roja reflectante y bolsillos laterales
    bp_school = uri([[<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'>
<path d='M24 13c0-5 16-5 16 0' fill='none' stroke='#131f52' stroke-width='3' stroke-linecap='round'/>
<rect x='6' y='38' width='9' height='17' rx='4' fill='#22388a' stroke='#131f52' stroke-width='2'/>
<rect x='49' y='38' width='9' height='17' rx='4' fill='#22388a' stroke='#131f52' stroke-width='2'/>
<rect x='13' y='12' width='38' height='46' rx='9' fill='#2b44a0' stroke='#131f52' stroke-width='2.5'/>
<path d='M13 29h38v-9a8 8 0 0 0-8-8H21a8 8 0 0 0-8 8z' fill='#3a58c4' stroke='#131f52' stroke-width='2.5' stroke-linejoin='round'/>
<rect x='28' y='25' width='8' height='9' rx='2' fill='#e34550' stroke='#131f52' stroke-width='1.8'/>
<rect x='15' y='43' width='34' height='5' fill='#e34550'/>
<path d='M15 45.5h34' stroke='#ffd7da' stroke-width='1.2' stroke-dasharray='3 2'/>
</svg>]]),

    -- Mochila de senderismo: naranja con base verde, esterilla arriba y botella lateral
    bp_hiking = uri([[<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'>
<rect x='14' y='4' width='36' height='10' rx='5' fill='#b9c7a4' stroke='#4b5a3a' stroke-width='2.5'/>
<path d='M22 5v8M32 5v8M42 5v8' stroke='#4b5a3a' stroke-width='1.6'/>
<rect x='5' y='34' width='10' height='21' rx='5' fill='#2b5c38' stroke='#16301d' stroke-width='2'/>
<rect x='6.5' y='30' width='7' height='6' rx='2' fill='#6ec1e4' stroke='#16301d' stroke-width='1.5'/>
<rect x='15' y='13' width='34' height='46' rx='9' fill='#e87830' stroke='#6b2f0f' stroke-width='2.5'/>
<path d='M15 41h34v9a9 9 0 0 1-9 9H24a9 9 0 0 1-9-9z' fill='#2b5c38' stroke='#6b2f0f' stroke-width='2.5' stroke-linejoin='round'/>
<rect x='24' y='13' width='4' height='28' fill='#6b2f0f'/>
<rect x='36' y='13' width='4' height='28' fill='#6b2f0f'/>
<rect x='22' y='24' width='20' height='6' rx='2' fill='#f4a86b' stroke='#6b2f0f' stroke-width='1.6'/>
</svg>]]),

    -- Mochila tactica: camuflaje verde oliva, cinta MOLLE y bolsa frontal
    bp_tactical = uri([[<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'>
<defs><clipPath id='c'><rect x='13' y='11' width='38' height='47' rx='8'/></clipPath></defs>
<path d='M24 12c0-6 16-6 16 0' fill='none' stroke='#1a2113' stroke-width='3.5' stroke-linecap='round'/>
<rect x='13' y='11' width='38' height='47' rx='8' fill='#4a5736'/>
<g clip-path='url(%23c)'>
<ellipse cx='22' cy='20' rx='9' ry='5' fill='#948559'/>
<ellipse cx='44' cy='28' rx='8' ry='6' fill='#1a2113'/>
<ellipse cx='20' cy='38' rx='7' ry='6' fill='#1a2113'/>
<ellipse cx='42' cy='46' rx='9' ry='5' fill='#948559'/>
<ellipse cx='28' cy='54' rx='8' ry='4' fill='#1a2113'/>
</g>
<rect x='13' y='11' width='38' height='47' rx='8' fill='none' stroke='#1a2113' stroke-width='2.5'/>
<path d='M17 25h30M17 29h30' stroke='#cdbf8a' stroke-width='1.8' stroke-dasharray='4 2'/>
<rect x='19' y='34' width='26' height='17' rx='3' fill='#3b4528' stroke='#1a2113' stroke-width='2'/>
<rect x='29' y='34' width='6' height='5' fill='#1a2113'/>
<path d='M23 12v8M41 12v8' stroke='#1a2113' stroke-width='3'/>
</svg>]]),

    -- Mochila de expedicion: grande, gris carbon con ribetes amarillos, tapa, esterilla abajo y piolet
    bp_expedition = uri([[<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'>
<path d='M10 24c0-11 9-17 22-17s22 6 22 17z' fill='#3d4452' stroke='#101216' stroke-width='2.5' stroke-linejoin='round'/>
<path d='M13 21c3-8 10-11 19-11s16 3 19 11' fill='none' stroke='#f5b81a' stroke-width='2.4'/>
<rect x='9' y='23' width='46' height='33' rx='6' fill='#313642' stroke='#101216' stroke-width='2.5'/>
<path d='M9 35h46' stroke='#f5b81a' stroke-width='3.2'/>
<rect x='18' y='23' width='5' height='33' fill='#1c1f27'/>
<rect x='41' y='23' width='5' height='33' fill='#1c1f27'/>
<rect x='17' y='40' width='7' height='6' rx='1.5' fill='#f5b81a' stroke='#101216' stroke-width='1.4'/>
<rect x='40' y='40' width='7' height='6' rx='1.5' fill='#f5b81a' stroke='#101216' stroke-width='1.4'/>
<rect x='6' y='53' width='52' height='9' rx='4.5' fill='#f5b81a' stroke='#101216' stroke-width='2.5'/>
<path d='M58 14v38' stroke='#aeb6c4' stroke-width='3' stroke-linecap='round'/>
<path d='M52.5 16c2-3.5 8-3.5 10 0' fill='none' stroke='#aeb6c4' stroke-width='3' stroke-linecap='round'/>
</svg>]]),
}
