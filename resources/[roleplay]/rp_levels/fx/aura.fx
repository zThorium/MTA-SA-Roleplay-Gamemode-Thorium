//
// rp_levels / aura.fx
//
// Aura dorada al subir de nivel (solo en el cliente del propio jugador).
// Shader EN CAPA (layered): no sustituye al de rp_characters (altura y tono de
// piel), dibuja una pasada extra que SUMA luz dorada encima:
//   - un velo dorado suave sobre todo el cuerpo, y
//   - un borde luminoso (rim) donde la superficie se ve de canto, que da el
//     efecto de aura magica.
// Repite la escala de altura de rp_characters/fx/body.fx (sScale, sPivot) para
// que la capa coincida con el cuerpo escalado.
//

float  sScale    = 1.0;                      // misma escala que body.fx
float3 sPivot    = float3(0, 0, 0);          // pies del ped (mundo)
float  sStrength = 0.0;                      // 0 = sin aura, 1 = maxima
float3 sColor    = float3(1.0, 0.78, 0.30);  // dorado

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
    float  Rim      : TEXCOORD1;
};

PSInput AuraVS(VSInput VS)
{
    PSInput PS = (PSInput)0;
    float3 world = MTACalcWorldPosition(VS.Position);
    world = sPivot + (world - sPivot) * sScale;
    PS.Position = mul(float4(world, 1), gViewProjection);

    float3 n = normalize(MTACalcWorldNormal(VS.Normal));
    float3 v = normalize(gCameraPosition - world);
    float facing = saturate(abs(dot(n, v)));
    PS.Rim = (1 - facing) * (1 - facing);
    PS.TexCoord = VS.TexCoord;
    return PS;
}

float4 AuraPS(PSInput PS) : COLOR0
{
    float alpha = tex2D(Sampler0, PS.TexCoord).a;
    float k = sStrength * (0.28 + 1.25 * PS.Rim);
    return float4(sColor, saturate(alpha * k));
}

technique aura
{
    pass P0
    {
        AlphaBlendEnable = true;
        SrcBlend         = SrcAlpha;
        DestBlend        = One;        // suma luz (aditivo)
        ZWriteEnable     = false;
        VertexShader     = compile vs_2_0 AuraVS();
        PixelShader      = compile ps_2_0 AuraPS();
    }
}

// Tarjetas sin shaders: sin capa (el resto del efecto se ve igual)
technique fallback
{
    pass P0
    {
        AlphaBlendEnable = true;
        SrcBlend         = Zero;
        DestBlend        = One;
    }
}
