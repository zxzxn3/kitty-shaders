#language slang 2026
// Author: zxzx.
// 聚焦时边缘脉动；Kitty 重载后的首帧也会触发。参数见 pipeline。

import kitty_custom_shader_types;

// 下面三个会被 focus-pulse.pipeline 的组内 var 覆盖
static const float PULSE_PEAK = 0.05;      // 最亮时叠多少（线性）
static const float PULSE_BAND_PX = 48.0;   // 从边缘往里多少像素衰减到没有
static const float PULSE_ATTACK = 0.12;    // 起手用掉整段动画的比例

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 area = d.central_area;
    if (area.z <= 0.0 || area.w <= 0.0) return color;

    // 到内容区四条边的距离。x/y 分开换算成像素，非等比窗口下带宽才不会被拉歪。
    float2 dd = min(t.pos - area.xy, area.xy + area.zw - t.pos) * float2(d.viewport_size_pixels);
    float dmin = min(dd.x, dd.y);
    if (dmin <= 0.0) return color;   // 内容区之外（标签栏所在的那条）不加

    float band = 1.0 - smoothstep(0.0, PULSE_BAND_PX, dmin);
    if (band <= 0.0) return color;

    // 对 pipeline 的线性 progress 应用渐入、渐出包络。
    float p = clamp(t.animation_progress, 0.0, 1.0);
    float env = (1.0 - p) * smoothstep(0.0, PULSE_ATTACK, p);
    if (env <= 0.0) return color;

    return float4(color.rgb + float3(band * env * PULSE_PEAK), color.a);
}
