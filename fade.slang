#language slang 2026
// Author: zxzx.
// Shared desaturation shader; WHOLE_WINDOW selects the entire window or inactive splits.
// Kitty compiles each group separately; pipeline variables override defaults.

import kitty_custom_shader_types;

// Fade the entire window; default false, overridden to true by window-fade.
static const bool WHOLE_WINDOW = false;
// Brightness multiplier; 1 leaves brightness unchanged.
static const float FADE_DIM = 1.0;
// Desaturation strength; achromatic white text is unaffected.
static const float FADE_DESAT = 0.20;
public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // outside is the fade weight; 1 indicates an inactive region.
    float outside = 1.0;
    if (!WHOLE_WINDOW) {
        float4 g = d.active_window_geometry;
        if (g.z > 0.0 && g.w > 0.0) {
            float2 dd = min(t.pos - g.xy, g.xy + g.zw - t.pos);
            float dmin = min(dd.x, dd.y);
            // Use hard boundaries so the active split's edge pixels do not fade.
            outside = 1.0 - step(0.0, dmin);
        }
    }
    if (outside <= 0.0) return color;

    float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float3 faded = lerp(color.rgb, float3(lum), FADE_DESAT) * FADE_DIM;
    return float4(lerp(color.rgb, faded, outside), color.a);
}
