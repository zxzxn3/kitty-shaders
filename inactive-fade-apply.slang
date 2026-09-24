#language slang 2026
// inactive-fade —— 把褪色程度应用上去。整条管线的最后一个组，唯一写回 backbuffer 的组。
//
// 常驻，但 pipeline 里给了 animation_step 0，也就是「不申请周期性帧」，
// 只在别的原因触发重绘时跟着走，所以空闲时不空转。
//
// 为什么要压亮度：白色没有色相，把白字去饱和算出来还是白字，一点变化都看不出来。
// 只有屏幕上真有彩色内容（ls 的颜色、语法高亮、彩色提示符）时去饱和才有效，
// 所以「马上能看出来」靠压暗，去饱和负责后面几秒慢慢走到没有颜色。

import kitty_custom_shader_types;

// 刚失去焦点/离开分屏时：马上去掉这么多饱和、压暗到这个亮度。
static const float DESAT_START = 0.35;
static const float DIM_START = 0.68;
// 褪色程度到 1 时：完全没有颜色，再暗一点。
static const float DESAT_END = 1.0;
static const float DIM_END = 0.50;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 stored = t.persist.Sample(t.pos);
    float level = stored.a > 0.999 ? clamp(stored.g, 0.0, 1.0) : 0.0;
    if (level <= 0.0) return color;

    float desat = lerp(DESAT_START, DESAT_END, level);
    float dim = lerp(DIM_START, DIM_END, level);
    float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float3 faded = lerp(color.rgb, float3(lum), desat) * dim;
    return float4(faded, color.a);
}
