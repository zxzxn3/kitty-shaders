#language slang 2026
// Author: zxzx.
// 共用去饱和 shader：WHOLE_WINDOW 选择整窗或非活动分屏。
// Kitty 按组分别编译；参数在各 pipeline 覆盖。

import kitty_custom_shader_types;

// 是否整窗变淡。默认 false；window-fade 的那一组会覆盖成 true。
static const bool WHOLE_WINDOW = false;
// 亮度系数，1 为不变。
static const float FADE_DIM = 1.0;
// 去饱和比例；不影响无色相的白字。
static const float FADE_DESAT = 0.20;
public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // outside = 这个像素该变淡的程度：1 表示它属于「不活跃」的部分。
    float outside = 1.0;
    if (!WHOLE_WINDOW) {
        float4 g = d.active_window_geometry;
        if (g.z > 0.0 && g.w > 0.0) {
            float2 dd = min(t.pos - g.xy, g.xy + g.zw - t.pos);
            float dmin = min(dd.x, dd.y);
            // 使用硬边界，避免活动分屏最外一像素被羽化褪色。
            outside = 1.0 - step(0.0, dmin);
        }
    }
    if (outside <= 0.0) return color;

    float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float3 faded = lerp(color.rgb, float3(lum), FADE_DESAT) * FADE_DIM;
    return float4(lerp(color.rgb, faded, outside), color.a);
}
