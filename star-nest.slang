#language slang 2026
// star-nest —— 深空星野背景
//
// 原作："Star Nest" by Pablo Roman Andrioli（Shadertoy）。用户给的 shader1.txt / shader2.txt
// 是它的两个改版：一个让 zoom 跟着时间呼吸、视角跟鼠标；一个是固定视角。两者本体相同。
// 这里是按原作思路重写的一版，非商业个人自用；署名、许可以原作为准。
//
// 和原作的三处刻意差别（都是为了"黑背景 + 不要大光斑"）：
//   1. 黑电平：a³ 先减掉 NEB_BLACK³，把原作糊满整屏的褐色雾按掉（低于这个值的像素纯黑）
//   2. 亮度上限：NEB_PEAK 压住最亮的那几团，不再出现爆白的光斑
//   3. 只画背景像素，亮度按 NEB_STRENGTH 混进背景，字一个像素都不碰
//
// 性能：
//   * 原作每个像素 20 步 × 17 次迭代 × 2 次 length = 680 次开方
//   * 这里 16 × 14 × 1 次 length（同一个 length 复用给 a 和 pa）= 224 次，约 1/3
//   * pipeline 里 animation_step 0：空闲不申请周期帧，只在内容重绘时跟着走
//
// 顺序：必须在 ink-stroke 之后（否则墨痕认不出背景）、两个 fade 之前（否则失焦不变淡）。
// 和 cloud-bg / bg-drift 三选一——都靠「和背景色比较」认背景。

import kitty_custom_shader_types;

// ── 可调参数（会被 star-nest.pipeline 里的 var 覆盖）──
static const int NEB_STEPS = 16;         // 步进数（原作 20）
static const int NEB_ITER = 14;          // 内层迭代（原作 17）；a 的量级会自动归一，不用跟着改 NEB_BLACK
static const float NEB_BLACK = 16.0;     // 黑电平，分形值单位：低于它的像素纯黑（原作 0）
static const float NEB_BRIGHT = 0.0004;  // 星云/星点亮度（原作 0.0015）
static const float NEB_HAZE = 0.02;      // 背景雾，原作的 `v += fade`（原作 1.0）
static const float NEB_PEAK = 0.35;      // 线性亮度上限（去光斑）
static const float NEB_SAT = 0.85;       // 饱和度（原作 0.85）
static const float NEB_STRENGTH = 1.0;   // 星野混进背景的程度，0 = 关闭
static const float NEB_SPEED = 0.001;    // 时间缩放（原作 shader1 0.001 / shader2 0.01）
static const float NEB_ZOOM = 0.8;       // 视场（原作 0.8）

// ── 实现细节（基本不用动）──
static const float NEB_TILE = 0.850;     // 平铺折叠的格子
static const float NEB_FORMU = 0.53;     // 原作 formuparam
static const float NEB_DARKMAT = 0.300;  // 原作 darkmatter
static const float NEB_DISTFADE = 0.730; // 原作 distfading
static const float NEB_STEP0 = 0.1;      // 原作 stepsize
static const float2 NEB_TILT = float2(0.5, 0.8); // 原作用鼠标算的相机倾角，这里固定
static const float NEB_COLOR_SCALE = 0.01;       // 原作最后的 v*0.01
static const float BG_TOLERANCE = 0.02;          // 判定「这是背景」的色彩容差（线性 RGB）
// 保险丝：极端像素（内层迭代里 dot(p,p) 趋近 0）会算出天文数字，钳一下省得整屏发白
static const float NEB_A_MAX = 100000.0;

// GLSL 的 mod 是 floor 语义（结果跟除数同号），HLSL/Slang 的 fmod 是截断语义。
// 这里 p 有负分量（相机在 -z 方向），所以必须显式写 floor 版。
static float3
glsl_mod(float3 x, float3 y) { return x - y * floor(x / y); }

// GLSL 里 `v.xy *= mat2(c,s,-s,c)` 是矩阵左乘向量。Slang 没有这个语法糖，显式写出来。
static float2
rot2(float a, float2 v) {
    float c = cos(a), s = sin(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // 只画背景像素。先判后算——字体像素直接走人，不跑那 200 多次开方。
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 res = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));
    float2 uv = t.pos - 0.5;
    uv.y *= res.y / res.x;
    float3 dir = float3(uv * NEB_ZOOM, 1.0);

    float time = d.timestamp * NEB_SPEED + 0.25;
    float a1 = NEB_TILT.x, a2 = NEB_TILT.y;
    dir.xz = rot2(a1, dir.xz);
    dir.xy = rot2(a2, dir.xy);

    // 相机起点，随 time 慢慢往前推（原作唯一的时间依赖就在这里）
    float3 frm = float3(1.0, 0.5, 0.5) + float3(time * 2.0, time, -2.0);
    frm.xz = rot2(a1, frm.xz);
    frm.xy = rot2(a2, frm.xy);

    float s = NEB_STEP0;
    float fade = 1.0;
    float3 v = float3(0.0);
    float blk3 = NEB_BLACK * NEB_BLACK * NEB_BLACK;
    // 迭代数变了，累加出来的 a 量级也跟着变（近似成正比），归一到 17 次的刻度上，
    // 这样 NEB_BLACK / NEB_ITER 可以各自单独调。
    float anorm = 17.0 / float(NEB_ITER);

    for (int r = 0; r < NEB_STEPS; r++) {
        float3 p = frm + (s * 0.5) * dir;
        p = abs(NEB_TILE - glsl_mod(p, 2.0 * NEB_TILE));   // 平铺折叠

        float pa = 0.0, a = 0.0;
        for (int i = 0; i < NEB_ITER; i++) {
            p = abs(p) / dot(p, p) - NEB_FORMU;
            float l = length(p);        // 只算一次：原作这里算了两次（a 和 pa 各一次）
            a += abs(l - pa);
            pa = l;
        }
        a *= anorm;
        // 兜底：NaN / inf / 负数都当成黑（NaN 的比较恒为 false，顺手也挡住了）
        if (!(a > 0.0)) a = 0.0;
        a = min(a, NEB_A_MAX);

        float dm = max(0.0, NEB_DARKMAT - a * a * 0.001);  // 原作 dark matter
        // 黑电平：a³ 减掉一个常数，低端直接归零 —— 这一行就是"黑背景"的来源
        float e = max(a * a * a - blk3, 0.0);
        if (r > 6) fade *= 1.0 - dm;
        v += float3(fade * NEB_HAZE);
        v += float3(s, s * s, s * s * s * s) * (e * NEB_BRIGHT * fade);  // 按距离上色（近处偏红，远处偏蓝）
        fade *= NEB_DISTFADE;
        s += NEB_STEP0;
    }

    v = lerp(float3(length(v)), v, NEB_SAT);   // 原作 saturation
    float3 col = clamp(v * NEB_COLOR_SCALE, 0.0, NEB_PEAK);
    return float4(lerp(color.rgb, col, bg * NEB_STRENGTH), color.a);
}
