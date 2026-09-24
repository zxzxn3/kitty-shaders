#language slang 2026
// sleep-wake —— 把睡意应用到画面上。这是整条管线的最后一个组，
// 也是唯一写回 backbuffer 的组。
//
// 它常驻，但 pipeline 里给了 animation_step 0，意思是「不申请周期性帧」，
// 只在有内容变化或事件时跟着重画，所以空闲时不会占着 GPU 空转。

import kitty_custom_shader_types;

// 睡着时内容保留多少亮度。
static const float SLEEP_DIM = 0.80;
// 睡着时去掉多少饱和度。黑背景去饱和看不出变化，效果全在文字上。
static const float SLEEP_DESAT = 0.55;
// 睡着时往这个颜色偏一点。纯白 float3(1.0) 就是不偏。
static const float3 SLEEP_TINT = float3(0.96, 0.98, 1.0);
// 刚醒来那一下内容亮多少（睡意为负时生效）。设成 0 就没有这记过冲。
static const float WAKE_GAIN = 0.08;
// 认定「这是背景」的色彩容差（线性 RGB）。
static const float BG_TOLERANCE = 0.02;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 stored = t.persist.Sample(t.pos);
    if (!(stored.a > 0.999)) return color;
    float sleep = stored.g;
    if (abs(sleep) < 0.002) return color;

    // 背景不动。你的背景是纯黑，压暗去饱和都没有意义，只会破坏透明感。
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg > 0.0) return color;

    if (sleep > 0.0) {
        float k = min(sleep, 1.0);
        float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
        float3 asleep = lerp(color.rgb, float3(lum), SLEEP_DESAT) * SLEEP_TINT * SLEEP_DIM;
        return float4(lerp(color.rgb, asleep, k), color.a);
    }
    return float4(color.rgb * (1.0 + min(-sleep, 1.0) * WAKE_GAIN), color.a);
}
