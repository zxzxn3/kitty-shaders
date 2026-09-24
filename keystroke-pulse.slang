#language slang 2026
// keystroke-pulse —— 敲键盘时，内容区边缘有一次很轻的"呼吸"。
//
// 单组、事件驱动、无状态：触发用户活动，600ms 一条 envelope（平滑起手、随后落下），
// 强度按到边缘的距离衰减成一条带。没有 persist，没有跨帧状态。
//
// 连续打字时每次按键都会重启这条动画，所以它会稳定在一个较低的水平上，
// 停下来后 600ms 内收干净——这是"呼吸"，不是"闪烁"。

import kitty_custom_shader_types;

// 最亮时往当前颜色上叠多少。0.05 线性约等于 sRGB 0.24，是很淡的一层。
static const float PEAK = 0.05;
// 从边缘往里多少像素衰减到没有。给得大一点就是柔和的渐变而不是一条边。
static const float BAND_PX = 48.0;
// 起手用掉整段动画的多大比例。0.12 × 600ms ≈ 70ms，够平滑又不会觉得慢。
static const float ATTACK = 0.12;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 area = d.central_area;
    if (area.z <= 0.0 || area.w <= 0.0) return color;

    // 到内容区四条边的距离。x/y 分开换算成像素，非等比窗口下带宽才不会被拉歪。
    float2 dd = min(t.pos - area.xy, area.xy + area.zw - t.pos) * float2(d.viewport_size_pixels);
    float dmin = min(dd.x, dd.y);
    if (dmin <= 0.0) return color;   // 内容区之外（标签栏所在的那条）不加

    float band = 1.0 - smoothstep(0.0, BAND_PX, dmin);
    if (band <= 0.0) return color;

    // envelope：平滑起手，然后落到 0。progress 由 pipeline 给成线性的，
    // 所以这里的形状就是最终看到的形状。
    float p = clamp(t.animation_progress, 0.0, 1.0);
    float env = (1.0 - p) * smoothstep(0.0, ATTACK, p);
    if (env <= 0.0) return color;

    return float4(color.rgb + float3(band * env * PEAK), color.a);
}
