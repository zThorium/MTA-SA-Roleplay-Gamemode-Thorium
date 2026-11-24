//
// rp_furniture / tint.fx
//
// Tinte y material de un mueble. Se aplica con engineApplyShaderToWorldTexture(shader, "*", objeto).
//  - sTint    color RGB multiplicador (blanco = sin cambio)
//  - sUseMat  1 = usa la textura sMatTex (material procedural) en lugar de la original
//  - sTile    metros por repeticion del material (mapeo triplanar por posicion mundial,
//             asi el material se ve igual en cualquier escala del objeto)
//  - sAlpha   opacidad (para el fantasma del editor)
//

float3 sTint   = float3(1.0, 1.0, 1.0);
float  sUseMat = 0.0;
float  sTile   = 1.5;
float  sAlpha  = 1.0;
texture sMatTex;

#include "mta-helper.fx"

sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

sampler SamplerMat = sampler_state
{
    Texture = (sMatTex);
    AddressU = Wrap;
    AddressV = Wrap;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
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
    float3 World    : TEXCOORD2;
};

PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
    float3 world = MTACalcWorldPosition(VS.Position);
    PS.Position = mul(float4(world, 1), gViewProjection);
    PS.TexCoord = VS.TexCoord;
    PS.Normal   = MTACalcWorldNormal(VS.Normal);
    PS.World    = world;
    PS.Diffuse  = MTACalcGTABuildingDiffuse(VS.Diffuse);
    return PS;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 tex = tex2D(Sampler0, PS.TexCoord);

    if (sUseMat > 0.5)
    {
        float3 n = abs(normalize(PS.Normal));
        float2 uv = PS.World.xy;
        if (n.x > n.y && n.x > n.z) uv = PS.World.yz;
        else if (n.y > n.z)         uv = PS.World.xz;
        float4 m = tex2D(SamplerMat, uv / sTile);
        // el detalle de la textura original (bordes, costuras) se conserva con poca fuerza
        float luma = dot(tex.rgb, float3(0.299, 0.587, 0.114));
        tex.rgb = m.rgb * (0.78 + 0.35 * saturate(luma));
    }

    tex.rgb *= sTint;
    float4 col = tex * PS.Diffuse;
    col.a *= sAlpha;
    return col;
}

technique tint
{
    pass P0
    {
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader  = compile ps_3_0 PixelShaderFunction();
    }
}

technique fallback
{
    pass P0
    {
    }
}
