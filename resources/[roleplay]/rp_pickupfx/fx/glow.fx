//
// rp_pickupfx / glow.fx (copia de rp_3dtext)
//
// Brillo procedural (sin textura) para dibujar con dxDrawMaterialLine3D en mezcla aditiva.
// El color y la opacidad llegan en el color del dibujo (COLOR0).
//  sMode 0 = disco suave (halo, chispas)
//        1 = anillo (en el suelo)
//        2 = haz vertical (columna de luz que se desvanece hacia arriba)
//

float sMode = 0;

struct PSInput
{
    float4 Position : POSITION0;
    float4 Diffuse  : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float2 p = PS.TexCoord - 0.5;
    float  d = length(p) * 2.0;
    float  a;
    if (sMode < 0.5)
    {
        a = saturate(1.0 - d);
        a = a * a;
    }
    else if (sMode < 1.5)
    {
        a = saturate(1.0 - abs(d - 0.78) * 7.0) + saturate(1.0 - d) * 0.15;
    }
    else
    {
        float h = saturate(1.0 - abs(p.x) * 2.0);
        a = h * h * sin(PS.TexCoord.y * 3.14159);
    }
    return float4(PS.Diffuse.rgb, PS.Diffuse.a * a);
}

technique glow
{
    pass P0
    {
        AlphaBlendEnable = true;
        SrcBlend = SrcAlpha;
        DestBlend = One;
        ZWriteEnable = false;
        PixelShader = compile ps_2_0 PixelShaderFunction();
    }
}
