#language slang 2026
// inactive-fade —— 不活跃的部分暗一档。没有渐变、没有计时、没有跨帧状态。
//
// 同一个文件被两个组复用，差别只有 WHOLE_WINDOW 这一个开关：
//   true  → 整个窗口都暗（这个 OS 窗口失焦时用）
//   false → 只有活动分屏外面暗（窗口有焦点时用）
// 开关在 pipeline 里按组覆盖，不需要改这个文件，也不需要第二份 shader。
//
// 为什么要压亮度：白色没有色相，把白字去饱和算出来还是白字，一点变化都看不出来。
// 只有屏幕上真有彩色内容（ls 的颜色、语法高亮、彩色提示符）时去饱和才有效。

import kitty_custom_shader_types;

// 是否整窗变暗。默认 false，pipeline 里的失焦组会覆盖成 true。
static const bool WHOLE_WINDOW = false;
// 暗到什么程度：0.68 表示保留 68% 亮度。
static const float DIM = 0.68;
// 顺带去多少饱和。设成 0 就是纯粹压暗。
static const float DESAT = 0.35;
// 分屏边界羽化多少像素，免得交界处出现硬边。
static const float EDGE_FEATHER_PX = 1.5;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // outside = 这个像素该变暗的程度：1 表示它属于「不活跃」的部分。
    float outside = 1.0;
    if (!WHOLE_WINDOW) {
        float4 g = d.active_window_geometry;
        if (g.z > 0.0 && g.w > 0.0) {
            float2 dd = min(t.pos - g.xy, g.xy + g.zw - t.pos);
            float dmin = min(dd.x, dd.y);
            float feather = max(fwidth(dmin) * EDGE_FEATHER_PX, 1e-6);
            outside = 1.0 - smoothstep(0.0, feather, dmin);
        }
    }
    if (outside <= 0.0) return color;

    float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float3 dimmed = lerp(color.rgb, float3(lum), DESAT) * DIM;
    return float4(lerp(color.rgb, dimmed, outside), color.a);
}
