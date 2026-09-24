#language slang 2026
// fade —— 把颜色往黑白去，不动亮度。给两个维度共用：
//   WHOLE_WINDOW = true  → 整个窗口都变淡（window-fade 用：这个 OS 窗口失焦）
//   WHOLE_WINDOW = false → 只有活动分屏外面变淡（layout-fade 用：窗口有焦点）
//
// 两条管线各自引用这个文件，kitty 会按「组 + shader」分别编译，所以两种行为是
// 两份独立特化，不是运行时分支。开关用组内 var 覆盖，不需要改这个文件。
//
// 带 FADE_ 前缀的常量会被 pipeline 里的 var 覆盖——调参改那边。

import kitty_custom_shader_types;

// 是否整窗变淡。默认 false；window-fade 的那一组会覆盖成 true。
static const bool WHOLE_WINDOW = false;
// 亮度系数。1.0 = 完全不动亮度，就是现在这档：颜色只往黑白去，不变暗。
// 想额外压暗再往下调（0.92 是很轻的一档，0.8 明显）。
static const float FADE_DIM = 1.0;
// 去多少饱和。0.0 = 不动，1.0 = 彻底黑白。
// 含义是「保留 (1 - FADE_DESAT) 的色度」：0.1 保留 90%（基本看不出），
// 0.5 保留 50%（明显但不刺眼），0.85 保留 15%（接近黑白）。
// 注意白字没有色相，去饱和对它完全没影响——这个效果只落在有颜色的内容上
// （ls 的颜色、语法高亮、彩色提示符、图片）。
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
            // 硬边界：dmin 在活动分屏内为正、外面为负。
            // 不羽化是刻意的——分屏之间的空白区本来就是背景色，里面外面看起来一样；
            // 羽化唯一可见的效果反而是把活动分屏最外面那 1 像素轻微褪色。
            // 哪天看到接缝发毛，把这行换回 smoothstep 版本即可。
            outside = 1.0 - step(0.0, dmin);
        }
    }
    if (outside <= 0.0) return color;

    float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float3 faded = lerp(color.rgb, float3(lum), FADE_DESAT) * FADE_DIM;
    return float4(lerp(color.rgb, faded, outside), color.a);
}
