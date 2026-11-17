// rp_injury / downed.fx
// Pantalla en escala de grises con vinyeta oscura y un latido rojo en los bordes.

texture ScreenTexture;
float Saturation = 0.0;   // 1 = color normal, 0 = gris total
float Darkness = 0.35;    // fuerza de la vinyeta (sube con el tiempo)
float Pulse = 0.0;        // 0..1 latido rojo en los bordes

sampler ScreenSampler = sampler_state
{
    Texture = <ScreenTexture>;
    AddressU = Clamp;
    AddressV = Clamp;
};

float4 PixelShaderFunction(float2 uv : TEXCOORD0) : COLOR0
{
    // Leve desenfoque horizontal/vertical para dar sensacion de mareo
    float2 o = float2(0.0015, 0.0015);
    float3 c = tex2D(ScreenSampler, uv).rgb * 0.4
             + tex2D(ScreenSampler, uv + float2( o.x, 0)).rgb * 0.15
             + tex2D(ScreenSampler, uv + float2(-o.x, 0)).rgb * 0.15
             + tex2D(ScreenSampler, uv + float2(0,  o.y)).rgb * 0.15
             + tex2D(ScreenSampler, uv + float2(0, -o.y)).rgb * 0.15;

    float gray = dot(c, float3(0.299, 0.587, 0.114));
    float3 col = lerp(float3(gray, gray, gray), c, Saturation);

    float2 d = uv - 0.5;
    float edge = saturate(dot(d, d) * 2.6);           // 0 en el centro, 1 en las esquinas
    col *= 1.0 - edge * Darkness;
    col = lerp(col, float3(0.42, 0.0, 0.0), edge * Pulse * 0.55);

    return float4(col, 1.0);
}

technique Downed
{
    pass P0
    {
        PixelShader = compile ps_2_0 PixelShaderFunction();
    }
}
