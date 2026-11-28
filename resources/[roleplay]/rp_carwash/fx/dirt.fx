//
// rp_carwash / dirt.fx
//
// Suciedad sobre la carrocería. Se aplica con engineApplyShaderToWorldTexture(shader, "vehiclegrunge256", vehiculo).
//  - gDirt       0 = limpio, 1 = cubierto de barro
//  - gDirtColor  color del barro (lo ilumina la luz de la escena, no lo tiñe la pintura)
// El barro sale en manchas (ruido 3D en el espacio del modelo) y sube desde abajo: con poca suciedad solo se
// ensucian los bajos; con mucha, todo el auto.
//

float  gDirt      = 0.0;
float3 gDirtColor = float3(0.36, 0.29, 0.21);

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
    float3 Local    : TEXCOORD1;
    float3 Light    : TEXCOORD2;
};

PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
    PS.Position = MTACalcScreenPosition(VS.Position);
    PS.TexCoord = VS.TexCoord;
    float3 n = MTACalcWorldNormal(VS.Normal);
    PS.Diffuse = MTACalcGTAVehicleDiffuse(n, VS.Diffuse);
    // luz sola (sin el color de la pintura) para el barro
    float dirf = max(0, dot(n, -gLightDirection));
    PS.Light = saturate(gGlobalAmbient.rgb + gLightAmbient.rgb + gLightDiffuse.rgb * dirf);
    PS.Local = VS.Position;
    return PS;
}

float hash(float3 p)
{
    p = frac(p * 0.3183099 + 0.1);
    p *= 17.0;
    return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(float3 x)
{
    float3 i = floor(x);
    float3 f = frac(x);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(lerp(hash(i + float3(0, 0, 0)), hash(i + float3(1, 0, 0)), f.x),
                     lerp(hash(i + float3(0, 1, 0)), hash(i + float3(1, 1, 0)), f.x), f.y),
                lerp(lerp(hash(i + float3(0, 0, 1)), hash(i + float3(1, 0, 1)), f.x),
                     lerp(hash(i + float3(0, 1, 1)), hash(i + float3(1, 1, 1)), f.x), f.y), f.z);
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 col = tex2D(Sampler0, PS.TexCoord) * PS.Diffuse;
    float n = vnoise(PS.Local * 2.2) * 0.6 + vnoise(PS.Local * 7.0) * 0.3 + vnoise(PS.Local * 19.0) * 0.1;
    // los bajos (z del modelo ~ -0.9) se ensucian primero; el techo (~ +0.8) al final
    float cover = gDirt * 1.3 - saturate((PS.Local.z + 0.9) * 0.45);
    float a = saturate((cover + n - 0.75) * 2.5) * 0.85;
    float3 mud = gDirtColor * (0.75 + 0.5 * n) * PS.Light;
    col.rgb = lerp(col.rgb, mud, a);
    return col;
}

technique dirt
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
