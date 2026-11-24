//
// rp_backpacks / backpack.fx
//
// Material de las mochilas. El modelo 3026 (para_pack) es el unico de vanilla y su textura
// "parapak" es azul oscuro con venas rojas, asi que el color y el tejido se generan aqui:
// una instancia del shader por tipo de mochila, con la receta de shared/s_config.lua
// (BACKPACKS[id].look.shader) enviada con dxSetShaderValue.
//
//  - sBody / sAccent / sDark   tres tonos de la mochila (el camuflaje usa los tres)
//  - sPattern                  pesos de las tramas: x nylon, y ripstop, z camuflaje, w lona
//  - sTile                     densidad de la trama
//  - sBandV / sBandW           banda de contraste (centro y mitad de ancho en v; 0 = sin banda)
//  - sSheen                    brillo de borde (nylon satinado)
//  - sReflect                  franjas reflectantes que brillan de lado
//  - sSeed                     desplaza el camuflaje
//  - sScale / sPivot           escala de altura del personaje y punto fijo (pies); c_visual.lua los actualiza.
//                              Hace lo que body.fx hace con lo pegado al personaje, para que la mochila siga su cuerpo.
//  La luminancia de la textura original se usa solo como detalle (costuras y bordes).
//

float3 sBody    = float3(0.30, 0.30, 0.30);
float3 sAccent  = float3(0.80, 0.80, 0.80);
float3 sDark    = float3(0.08, 0.08, 0.08);
float4 sPattern = float4(0.0, 0.0, 0.0, 0.0);
float  sTile    = 40.0;
float  sBandV   = 0.5;
float  sBandW   = 0.0;
float  sSheen   = 0.2;
float  sReflect = 0.0;
float  sSeed    = 0.0;
float  sScale   = 1.0;                // altura del personaje respecto a la base (1 = sin cambio)
float3 sPivot   = float3(0, 0, 0);    // punto fijo de esa escala: los pies del personaje (mundo)

#include "mta-helper.fx"

sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

struct VSInput
{
    float3 Position : POSITION0;
    float3 Normal   : NORMAL0;
    float4 Diffuse  : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

struct PSInput
{
    float4 Position : POSITION0;
    float4 Diffuse  : COLOR0;
    float2 TexCoord : TEXCOORD0;
    float3 Normal   : TEXCOORD1;
    float3 View     : TEXCOORD2;
};

PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;

    float3 world = MTACalcWorldPosition(VS.Position);
    world = sPivot + (world - sPivot) * sScale;   // misma escala que el personaje (rp_characters/fx/body.fx)
    PS.Position = mul(float4(world, 1), gViewProjection);
    PS.TexCoord = VS.TexCoord;
    PS.Normal   = MTACalcWorldNormal(VS.Normal);
    PS.View     = gCameraPosition - world;
    PS.Diffuse  = MTACalcGTABuildingDiffuse(VS.Diffuse);
    return PS;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 tex = tex2D(Sampler0, PS.TexCoord);
    float  luma = dot(tex.rgb, float3(0.299, 0.587, 0.114));
    float2 uv = PS.TexCoord;

    // Camuflaje: tres capas de ondas deformadas, cortadas en dos umbrales
    float n = sin(uv.x * 9.0 + sin(uv.y * 7.0 + sSeed) * 2.0)
            + sin(uv.y * 11.0 + sin(uv.x * 6.0 - sSeed) * 2.0)
            + sin((uv.x + uv.y) * 5.0 + sSeed);
    float camo1 = step(0.15, n);
    float camo2 = step(1.25, n);

    float3 col = sBody;
    col = lerp(col, sAccent, camo1 * sPattern.z);
    col = lerp(col, sDark,   camo2 * sPattern.z);

    // Banda de contraste (paneles de color distinto)
    float band = (1.0 - smoothstep(sBandW, sBandW + 0.03, abs(uv.y - sBandV))) * step(0.001, sBandW);
    col = lerp(col, sAccent, band);

    // Tramas: nylon (cuadricula fina), ripstop (hilos de refuerzo), lona (hilado grueso)
    float2 g = uv * sTile * 6.2831853;
    float weave  = sin(g.x) * sin(g.y);
    float2 f = frac(uv * sTile * 0.25);
    float ripstop = saturate(step(0.9, f.x) + step(0.9, f.y));
    float canvas = sin(g.x * 3.0) * sin(g.y * 3.0) * 0.5 + sin(uv.x * 23.0 + uv.y * 17.0) * 0.5;

    float shade = 1.0 + sPattern.x * 0.16 * weave
                      + sPattern.y * (ripstop * 0.30 - 0.05)
                      + sPattern.w * 0.14 * canvas;

    // Detalle de la textura original: costuras y bordes
    shade *= 0.80 + saturate(luma * 1.6);
    col *= shade;

    // Brillo de borde + franjas reflectantes (solo donde hay luz)
    float3 N = normalize(PS.Normal);
    float3 V = normalize(PS.View);
    float rim = pow(1.0 - saturate(dot(N, V)), 3.0);
    float stripe = step(0.46, frac(uv.y * 3.0)) * step(frac(uv.y * 3.0), 0.54);
    float3 lit = col * PS.Diffuse.rgb;
    lit += PS.Diffuse.rgb * (sSheen * 0.35 * rim);
    lit += float3(0.85, 0.88, 0.95) * sReflect * stripe * (0.25 + 1.6 * rim) * (0.4 + 0.6 * PS.Diffuse.r);

    return float4(saturate(lit), tex.a * PS.Diffuse.a);
}

technique backpack
{
    pass P0
    {
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader  = compile ps_3_0 PixelShaderFunction();
    }
}

// Tarjetas sin shaders: se dibuja la textura normal
technique fallback
{
    pass P0
    {
    }
}
