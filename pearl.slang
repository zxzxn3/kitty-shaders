#language slang 2026
// Author: zxzx.
import kitty_custom_shader_types;
static const float PEARL_STRENGTH = 1.0;

public float4 fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // Color-key mask, not a semantic glyph/image mask. Preserve original alpha.
    float3 delta = abs(color.rgb - d.background.rgb);
    float mask = 1.0 - smoothstep(0.001, 0.009, max(delta.r, max(delta.g, delta.b)));
    if (mask < 0.001 || color.a < 0.001) return color;
    float2 uv = t.pos;
    // Broad, stationary curved sheen: no visible stripes or travelling lights.
    float curve = uv.x * 0.70 + uv.y * 0.38 + (uv.y - 0.5) * (uv.y - 0.5) * 0.25;
    float ridge = 1.0 - smoothstep(0.0, 0.48, abs(curve - 0.53));
    ridge *= ridge;
    float hue = smoothstep(0.1, 0.95, curve);
    float3 pearl = lerp(float3(0.035, 0.19, 0.23), float3(0.21, 0.085, 0.27), hue);
    pearl = lerp(pearl, float3(0.24, 0.22, 0.18), ridge * 0.28);
    float2 pixel = floor(uv * max(float2(d.viewport_size_pixels), float2(1.0)));
    float grain = frac(52.9829189 * frac(dot(pixel, float2(0.06711056, 0.00583715))));
    float light = smoothstep(0.25, 0.65, dot(d.background.rgb, float3(0.2126, 0.7152, 0.0722)));
    float3 shift = pearl * (0.055 + ridge * 0.095) + float3((grain - 0.5) * 0.0015);
    float3 shaded = saturate(color.rgb + shift * PEARL_STRENGTH * lerp(1.0, -0.55, light));
    return float4(lerp(color.rgb, shaded, mask), color.a);
}
