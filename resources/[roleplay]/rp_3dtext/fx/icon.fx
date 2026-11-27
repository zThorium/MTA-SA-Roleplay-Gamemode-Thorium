//
// rp_3dtext / icon.fx
//
// Material del icono de info (modelo 1239). Ignora la luz del mundo (siempre brillante, de dia y
// de noche) y lo tine de dorado con:
//  - pulso suave de brillo
//  - un reflejo diagonal que recorre el icono
//  - borde luminoso (fresnel): los lados que miran de canto a la camara brillan mas
//
//  sTint    color base (dorado)
//  sGlow    color del borde y del reflejo
//  sBoost   multiplicador de brillo
//

float3 sTint  = float3(1.00, 0.80, 0.22);
float3 sGlow  = float3(1.00, 0.95, 0.70);
float  sBoost = 1.35;

#include "mta-helper.fx"

sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

struct VSInput
{
    float3 Position : POSITION0;
    float3 Normal   : NORMAL0;
    float2 TexCoord : TEXCOORD0;
};

struct PSInput
{
    float4 Position : POSITION0;
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
    return PS;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 tex  = tex2D(Sampler0, PS.TexCoord);
    float  luma = dot(tex.rgb, float3(0.299, 0.587, 0.114));

    // La textura original solo aporta detalle; el color lo pone el shader
    float3 col = sTint * (0.65 + 0.55 * luma) * sBoost;

    // Pulso
    col *= 0.88 + 0.12 * sin(gTime * 3.0);

    // Reflejo que sube en diagonal por el icono (en coordenadas de mundo: no depende del UV del modelo)
    float s    = frac((PS.World.z * 1.6 + PS.World.x * 0.4 + PS.World.y * 0.4) - gTime * 0.55);
    float band = saturate(1.0 - abs(s - 0.5) * 9.0);
    col += sGlow * band * band * 0.9;

    // Borde luminoso
    float3 n = normalize(PS.Normal);
    float3 v = normalize(PS.View);
    float rim = pow(1.0 - saturate(abs(dot(n, v))), 2.5);
    col += sGlow * rim * 0.8;

    return float4(col, tex.a);
}

technique icon
{
    pass P0
    {
        Lighting = false;
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader  = compile ps_3_0 PixelShaderFunction();
    }
}

// Tarjeta grafica sin shader model 3: se ve el icono original
technique fallback
{
    pass P0
    {
    }
}
