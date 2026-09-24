#language slang 2026
// pane-fade —— 只有当前分屏正常显示，其它分屏的颜色变淡（去饱和）。
//
// 无状态：每帧直接看 active_window_geometry 判断这个像素在不在当前分屏里，
// 不需要 persist，也不需要任何事件。
//
// 背景不动。你的背景是纯黑，去饱和在黑色上算出来还是黑色，所以效果
// 自然只落在有颜色的内容上——正是你想要的样子，不用额外做背景判定。

import kitty_custom_shader_types;

// 非活动分屏去掉多少饱和度。1.0 = 完全变灰，0.0 = 完全不变。
static const float INACTIVE_DESAT = 0.75;
// 边界羽化多少像素，免得分屏交界处出现硬边。
static const float EDGE_FEATHER_PX = 1.5;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 g = d.active_window_geometry;
    // 拿不到活动窗口几何（首帧，或这一帧没渲染活动窗口）就整屏不动。
    if (g.z <= 0.0 || g.w <= 0.0) return color;

    // 到活动分屏四条边的距离，UV 单位。负值表示落在分屏外面。
    float2 dd = min(t.pos - g.xy, g.xy + g.zw - t.pos);
    float dmin = min(dd.x, dd.y);
    // 用屏幕导数把 UV 距离换算成像素，再按像素羽化。
    float feather = max(fwidth(dmin) * EDGE_FEATHER_PX, 1e-6);
    float inside = smoothstep(0.0, feather, dmin);

    float desat = INACTIVE_DESAT * (1.0 - inside);
    if (desat <= 0.0) return color;

    float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    return float4(lerp(color.rgb, float3(lum), desat), color.a);
}
