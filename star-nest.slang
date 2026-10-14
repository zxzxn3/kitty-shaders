#language slang 2026
// Slang port and Kitty adaptation by zxzx; original Star Nest by Pablo Roman Andrioli.
// Source: https://www.shadertoy.com/view/XlfGRj; retain the original source attribution.
// Preserve the tiled fractal recurrence and distance-based color accumulation.
// Reduce volume steps 20 -> 16 and fractal iterations 17 -> 14; normalize iteration strength.
// Add background-only masking, black level, reduced haze, exponential brightness cap and NaN guards.
// Preserve alpha; use floor-based GLSL modulo and expose slow camera drift through the pipeline.

import kitty_custom_shader_types;

// ── 三个旋钮（在 star-nest.pipeline 里覆盖）──
static const float NEB_BLACK = 18.0;     // 黑电平：分形值低于它的像素纯黑（越大越黑）
static const float NEB_BRIGHT = 0.0004;  // 星云/星点亮度
static const float NEB_SPEED = 0.0025;   // 漂移速度，0 = 完全静止

// ── 实现细节 ──
static const int NEB_STEPS = 16;
static const int NEB_ITER = 14;
// 按迭代数换算回原作 17 次迭代刻度，保持黑电平含义。
static const float NEB_ANORM = 17.0 / 14.0;
static const float NEB_HAZE = 0.02;    // 原作那层让整屏发灰的底噪（原值 1.0），只留一点
static const float NEB_SAT = 0.85;     // 原作 saturation
static const float NEB_ZOOM = 0.8;     // 原作视场
static const float NEB_PEAK = 0.35;    // 亮度上限，指数软压缩
static const float NEB_SCALE = 0.01;   // 原作最后的 v*0.01
static const float NEB_TILE = 0.850;
static const float NEB_FORMU = 0.53;
static const float NEB_DARKMAT = 0.300;
static const float NEB_DISTFADE = 0.730;
static const float NEB_STEP0 = 0.1;
static const float NEB_A_MAX = 1.0e5;  // 保险丝：极端像素别算成 inf
static const float BG_TOLERANCE = 0.02;

// GLSL 的 mod 是 floor 语义（结果跟除数同号），HLSL/Slang 的 fmod 是截断语义。必须显式写。
static float3
glsl_mod(float3 x, float3 y) { return x - y * floor(x / y); }

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // 只画背景像素。先判后算：字体像素直接走人，不跑那两百多次开方。
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 res = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));
    float2 uv = t.pos - 0.5;
    uv.y *= res.y / res.x;               // 长宽比校正，星点是各向同性的
    float3 dir = float3(uv * NEB_ZOOM, 1.0);

    // 相机沿固定方向漂移。
    float time = d.timestamp * NEB_SPEED + 0.25;
    float3 frm = float3(1.0 + 2.0 * time, 0.5 + time, 0.5 - 2.0 * time);

    float s = NEB_STEP0, fade = 1.0;
    float3 v = float3(0.0);
    float blk3 = NEB_BLACK * NEB_BLACK * NEB_BLACK;
    for (int r = 0; r < NEB_STEPS; r++) {
        float3 p = abs(NEB_TILE - glsl_mod(frm + (s * 0.5) * dir, 2.0 * NEB_TILE));
        float pa = 0.0, a = 0.0;
        for (int i = 0; i < NEB_ITER; i++) {
            p = abs(p) / dot(p, p) - NEB_FORMU;
            float l = length(p);         // 原版这里算了两次（a 和 pa 各一次），是同一个值
            a += abs(l - pa);
            pa = l;
        }
        a *= NEB_ANORM;
        if (!(a > 0.0)) a = 0.0;         // NaN / 负值兜底（NaN 比较恒假，顺手也挡了）
        a = min(a, NEB_A_MAX);

        float dm = max(0.0, NEB_DARKMAT - a * a * 0.001);   // 原作 dark matter
        // 黑电平：a³ 减掉一个常数，低端直接归零 —— "黑色宇宙背景"就是这一行
        float e = max(a * a * a - blk3, 0.0);
        if (r > 6) fade *= 1.0 - dm;
        // 按距离上色：近处偏红、远处偏蓝（原作那条 (s, s², s⁴) 曲线）
        v += float3(fade * NEB_HAZE) + float3(s, s * s, s * s * s * s) * (e * NEB_BRIGHT * fade);
        fade *= NEB_DISTFADE;
        s += NEB_STEP0;
    }

    v = lerp(float3(length(v)), v, NEB_SAT);
    // 指数软上限避免亮部形成实心白斑。
    float3 col = NEB_PEAK * (1.0 - exp(-v * NEB_SCALE / NEB_PEAK));
    return float4(lerp(color.rgb, col, bg), color.a);
}
