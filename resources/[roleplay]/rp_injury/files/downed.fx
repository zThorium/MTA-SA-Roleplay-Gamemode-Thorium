// rp_injury / downed.fx
// Postproceso del estado abatido (solo en la pantalla del jugador abatido):
//   - Escala de grises: Saturation 1 = color original, 0 = gris total (0 % de saturacion).
//   - Desenfoque direccional: BlurDir es el desplazamiento total en coordenadas UV a lo
//     largo del cual se promedian 9 muestras. Lo calcula Lua a partir del giro de la
//     camara (mas rapido = mas largo) mas un pequeno resto que se tambalea en reposo.
// Una sola pasada, 9 lecturas de textura: compatible con ps_2_0.

texture ScreenTexture;
float Saturation = 1.0;
float2 BlurDir = float2(0, 0);

sampler ScreenSampler = sampler_state
{
    Texture = <ScreenTexture>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Clamp;
    AddressV = Clamp;
};

static const float3 LUMA = float3(0.299, 0.587, 0.114);

float4 PixelShaderFunction(float2 uv : TEXCOORD0) : COLOR0
{
    // Muestras simetricas a lo largo de BlurDir; los pesos suman 1
    float3 c = tex2D(ScreenSampler, uv).rgb * 0.20;
    c += tex2D(ScreenSampler, uv + BlurDir * 0.25).rgb * 0.14;
    c += tex2D(ScreenSampler, uv - BlurDir * 0.25).rgb * 0.14;
    c += tex2D(ScreenSampler, uv + BlurDir * 0.50).rgb * 0.12;
    c += tex2D(ScreenSampler, uv - BlurDir * 0.50).rgb * 0.12;
    c += tex2D(ScreenSampler, uv + BlurDir * 0.75).rgb * 0.09;
    c += tex2D(ScreenSampler, uv - BlurDir * 0.75).rgb * 0.09;
    c += tex2D(ScreenSampler, uv + BlurDir).rgb * 0.05;
    c += tex2D(ScreenSampler, uv - BlurDir).rgb * 0.05;

    float gray = dot(c, LUMA);
    c = lerp(float3(gray, gray, gray), c, saturate(Saturation));
    return float4(c, 1.0);
}

technique InjuryScreen
{
    pass P0
    {
        PixelShader = compile ps_2_0 PixelShaderFunction();
    }
}

// Si la tarjeta no acepta la tecnica anterior, MTA prueba esta (sin efecto: pantalla tal cual)
technique Fallback
{
    pass P0
    {
        Texture[0] = ScreenTexture;
    }
}
