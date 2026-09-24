#language slang 2026
// bg-drift —— 会缓慢漂移的背景。无状态：动画是 d.timestamp 的纯函数。
//
// 只画在背景像素上（和墨痕用同一套掩码：跟 d.background 比颜色），字一个像素都不碰。
// 在它之前跑的墨痕留下的笔触也不会被盖掉——那些像素已经不是背景色了。
//
// 顺序有讲究（见 README）：必须在 ink-stroke 之后、在 layout-fade / window-fade 之前。
//   * 在墨痕之后：否则墨痕认不出背景，笔触会消失
//   * 在两个 fade 之前：否则那两层褪色管不到它，失焦时背景图案会留着彩色
//
// 代价：这个组常驻并申请周期性帧（animation_step 200 = 5fps），所以 kitty 不再空闲。
// 对几十秒级周期的漂移，5fps 肉眼看不出来——时间是精确的，只是画面每秒更新 5 次。

import kitty_custom_shader_types;

// 背景像素的判定容差：和 d.background 的通道最大差值小于它就算背景。
static const float BG_TOLERANCE = 0.02;

// 下面带 BG_ 前缀的会被 bg-drift.pipeline 里的 var 覆盖——调参改那边。
static const float BG_PEAK = 0.06;    // 最亮处往画面加多少（线性 RGB）
static const float BG_SPEED = 0.15;   // 相位每秒推进多少；0.15 约等于 42 秒一个周期
static const float BG_SCALE = 1.5;    // 空间频率：大约每屏几个起伏
static const float3 BG_COLOR_A = float3(0.42, 0.72, 1.00);  // 冷调
static const float3 BG_COLOR_B = float3(0.55, 0.95, 0.75);  // 暖调

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // 只画背景。
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    // 按窗口宽高比换算，图案不会被拉歪；以窗口中心为原点。
    float2 dims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 uv = (t.pos - 0.5) * float2(dims.x / max(dims.y, 1.0), 1.0) * BG_SCALE;

    // 两个不同频率、不同速度的行波叠加，慢慢 beat 出不规则感——
    // 比单一正弦耐看，又不需要噪声函数。
    float ph = d.timestamp * BG_SPEED;
    float w1 = sin(uv.x * 3.1 + ph) * cos(uv.y * 2.7 - ph * 0.8);
    float w2 = sin(uv.y * 4.3 - ph * 1.3) * cos(uv.x * 2.2 + ph * 0.6);
    float k = 0.5 + 0.5 * (0.65 * w1 + 0.35 * w2);   // 0..1

    float3 tint = lerp(BG_COLOR_A, BG_COLOR_B, k);
    // 亮度也随图案起伏，让"流动"不只体现在色相上。
    float amp = BG_PEAK * (0.35 + 0.65 * k);
    return float4(color.rgb + tint * (amp * bg), color.a);
}
