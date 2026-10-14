#language slang 2026
// Author: zxzx.
import kitty_custom_shader_types;

// Pipeline constants are specialised at compile time: only the selected material remains.
static const int MATERIAL = 0;
static const float STRENGTH = 1.0;

public float4 fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // Use original linear RGB, keeping glyphs, selection and coloured cells intact.
    float3 delta = abs(color.rgb - d.background.rgb);
    float background_mask = 1.0 - smoothstep(0.001, 0.009, max(delta.r, max(delta.g, delta.b)));
    if (background_mask < 0.001 || color.a < 0.001) return color;

    float2 uv = t.pos;
    float2 size = max(float2(d.viewport_size_pixels), float2(1.0));
    float3 cool = float3(0.12, 0.40, 0.52);
    float3 warm = float3(0.52, 0.29, 0.12);
    float3 violet = float3(0.30, 0.18, 0.46);
    float3 tint = float3(0.0);
    float amount = 0.0;

    if (MATERIAL == 0) {
        // Elliptic level sets: no iterative noise or trigonometry; antialias at pixel scale.
        float2 p = float2((uv.x - 1.06) * size.x / size.y, (uv.y - 0.88) * 1.28);
        float field = dot(p, p) * 7.0 + p.x * p.y * 1.4;
        float cell = frac(field);
        float edge = min(cell, 1.0 - cell);
        float aa = max(fwidth(field), 0.001);
        float line = 1.0 - smoothstep(aa * 0.35, aa * 1.35, edge);
        float envelope = saturate(1.0 - uv.x * 0.25 - (1.0 - uv.y) * 0.55);
        tint = lerp(cool, violet, uv.x) * (0.10 + line * envelope);
        amount = 0.065;
    } else {
        // Stable physical-pixel grain, with a restrained warm paper tone.
        float2 pixel = floor(uv * size);
        float grain = frac(52.9829189 * frac(dot(pixel, float2(0.06711056, 0.00583715))));
        tint = warm;
        amount = 0.048;
        tint += float3((grain - 0.5) * 0.055);
    }

    float light_theme = smoothstep(0.25, 0.65, dot(d.background.rgb, float3(0.2126, 0.7152, 0.0722)));
    float3 shaded = color.rgb + tint * amount * STRENGTH * lerp(1.0, -0.6, light_theme);
    return float4(saturate(lerp(color.rgb, shaded, background_mask)), color.a);
}
