#language slang 2026
// ink-stain —— 把墨洇进背景。只动背景，不动字，所以整屏不会糊。
// 这是管线里最后一个组，也是唯一写回 backbuffer 的组。

import kitty_custom_shader_types;

// 墨色。换颜色改这一行，或者在 pipeline 里用 var 覆盖。
static const float3 INK_COLOR = float3(1.0, 1.0, 1.0);
// 最浓时往墨色混多少。0.42 是一层薄雾，1.0 就是实心白。
static const float INK_STRENGTH = 0.20;
// 墨落在玻璃上而不是纸背后：积墨的地方不透明度也往 1 靠，会盖掉一点背景透明度。
static const float INK_ALPHA_BOOST = 0.40;
// 认定「这是背景」的色彩容差（线性 RGB）。字和自绘的背景色都会被排除在外。
static const float BG_TOLERANCE = 0.02;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 stored = t.persist.Sample(t.pos);
    float ink = stored.r;
    // 和 accumulate 那边同样的守卫：没写过的像素当作没墨。
    if (!(ink > 0.0) || stored.a < 0.999) return color;
    ink = min(ink, 1.0);

    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float k = ink * INK_STRENGTH * bg;
    return float4(lerp(color.rgb, INK_COLOR, k), lerp(color.a, 1.0, k * INK_ALPHA_BOOST));
}
