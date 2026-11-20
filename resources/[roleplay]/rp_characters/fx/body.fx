//
// rp_characters / body.fx
//
// Altura y tono de piel de un personaje. Se aplica con
// engineApplyShaderToWorldTexture(shader, "*", ped) y, para lo que lleva pegado
// (cabeza de rp_heads, toys), otra instancia con sToneOn = 0.
//
//  - Altura: escala los vertices en el mundo alrededor de sPivot (los pies del
//    ped), asi el personaje crece o encoge sin hundirse ni flotar. Basado en el
//    ejemplo "ped morph" de la wiki de MTA (vertex shader sobre peds).
//  - Tono de piel: detecta los texeles con color de piel (calidos, saturacion
//    media) y los lleva al tono elegido conservando la luminancia (sombras,
//    arrugas). La ropa de colores frios, negra, blanca o gris no se toca.
//

float  sScale   = 1.0;                       // 1 = altura original
float3 sPivot   = float3(0, 0, 0);           // punto fijo de la escala (mundo)
float  sToneOn  = 0.0;                       // 0 = no tocar el color
float3 sTone    = float3(0.84, 0.64, 0.50);  // albedo objetivo de la piel
float  sToneRef = 0.33;                      // luminancia media de la piel original de CJ

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
};

PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;

    float3 world = MTACalcWorldPosition(VS.Position);
    world = sPivot + (world - sPivot) * sScale;
    PS.Position = mul(float4(world, 1), gViewProjection);

    PS.TexCoord = VS.TexCoord;
    PS.Diffuse = MTACalcGTABuildingDiffuse(VS.Diffuse);
    return PS;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 tex = tex2D(Sampler0, PS.TexCoord);
    float3 c = tex.rgb;

    // Mascara de piel: r >= g >= b, saturacion media, tono entre rojo y amarillo
    float mx  = max(c.r, max(c.g, c.b));
    float mn  = min(c.r, min(c.g, c.b));
    float sat = (mx - mn) / max(mx, 0.001);
    float hue = (c.g - c.b) / max(c.r - c.b, 0.001);   // 0 = rojo, 1 = amarillo
    float warm = step(c.b, c.g) * step(c.g, c.r);

    float mask = warm
        * smoothstep(0.12, 0.22, sat) * (1 - smoothstep(0.72, 0.86, sat))
        * smoothstep(0.15, 0.28, hue) * (1 - smoothstep(0.66, 0.80, hue))
        * smoothstep(0.05, 0.12, mx);

    float luma = dot(c, float3(0.2126, 0.7152, 0.0722));
    float3 toned = saturate(sTone * (luma / sToneRef));
    c = lerp(c, toned, mask * sToneOn);

    return float4(c, tex.a) * PS.Diffuse;
}

technique body
{
    pass P0
    {
        VertexShader = compile vs_2_0 VertexShaderFunction();
        PixelShader  = compile ps_2_0 PixelShaderFunction();
    }
}

// Tarjetas sin shaders: se dibuja normal (sin altura ni tono)
technique fallback
{
    pass P0
    {
    }
}
