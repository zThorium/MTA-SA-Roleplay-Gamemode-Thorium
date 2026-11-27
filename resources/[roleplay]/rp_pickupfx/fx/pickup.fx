//
// rp_pickupfx / pickup.fx
//
// Material de los pickups del juego (casas, estrellas, camiseta, fajos...). Se aplica por nombre
// de textura (las de cada modelo, sacadas con engineGetModelTextureNames). Conserva el color
// original y le suma:
//  - brillo propio (no depende de la luz del mundo) con pulso suave
//  - un reflejo que sube en diagonal (en coordenadas de mundo)
//  - borde luminoso (fresnel) con el color del estilo
//
//  sGlow    color del reflejo y del borde (el del estilo)
//  sBoost   multiplicador de brillo
//  sTint    cuanto se tine el modelo del color del estilo (0 = original, 1 = todo del color)
//

float3 sGlow  = float3(1.0, 1.0, 1.0);
float  sBoost = 1.3;
float  sTint  = 0.35;

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
    float3 World    : TEXCOORD3;
};

PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
    float3 world = MTACalcWorldPosition(VS.Position);
    PS.Position = mul(float4(world, 1), gViewProjection);
    PS.TexCoord = VS.TexCoord;
    PS.Normal   = MTACalcWorldNormal(VS.Normal);
    PS.View     = gCameraPosition - world;
    PS.World    = world;
    PS.Diffuse  = VS.Diffuse;
    return PS;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 tex = tex2D(Sampler0, PS.TexCoord);
    // color del material del modelo (no la luz del mundo); si no lo trae, el de la textura
    float3 mat  = gMaterialDiffuse.rgb;
    float3 base = tex.rgb * (dot(mat, float3(1, 1, 1)) > 0.05 ? mat : float3(1, 1, 1));

    float  luma = dot(base, float3(0.299, 0.587, 0.114));
    base = lerp(base, sGlow * (0.4 + 0.8 * luma), sTint);
    float3 col = base * sBoost * (0.85 + 0.15 * sin(gTime * 3.0));

    float s    = frac((PS.World.z * 1.6 + PS.World.x * 0.4 + PS.World.y * 0.4) - gTime * 0.55);
    float band = saturate(1.0 - abs(s - 0.5) * 9.0);
    col += sGlow * band * band * 0.9;

    float nl = length(PS.Normal);
    if (nl > 0.01)
    {
        float rim = pow(1.0 - saturate(abs(dot(PS.Normal / nl, normalize(PS.View)))), 2.5);
        col += sGlow * rim * 0.9;
    }
    return float4(col, tex.a);
}

technique pickup
{
    pass P0
    {
        Lighting = false;
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
