#language slang 2026
// magic-box —— 魔盒分形背景
//
// 原作：用户给的这段 "Magic Box"（Shadertoy；作者署名我没核实，你要是有链接我补上）。
//
// 数学（照原作）：
//   * 先把坐标折进一个 1×1×1 的镜子盒子：p = 1 - |1 - mod(p, 2)|
//   * 迭代 p = |p| / |p_上一轮|² - MAGIC，累加每次长度变化的绝对值 —— 这个累加值就是场值
//     **除的是上一轮的长度，不是当前 p 自己的长度**。这是它和 star-nest 那类分形最不一样
//     的地方，照抄成 dot(p,p) 会得到另一种花样。
//   * 相机沿一个固定的旋转轴（原版那个 3×3 矩阵）朝盒子里飞，z 随时间推进
//   * 原版上色：暗紫 → 橙红 → 最亮处归黑（所以结构是"镂空的珊瑚/蕾丝"）
//
// 移植时改了三处（都是为了当终端背景）：
//   1. 原版颜色是直接显示的（≈sRGB），kitty 的 shader 输出是线性 RGB —— 这里把颜色做了
//      一次 sRGB→线性 转换，否则会亮得发艳
//   2. 只画背景像素，并按 MBOX_STRENGTH 混进背景（原版是整屏不透明）
//   3. 上色改成"带通"：原版是低值区铺满橙色、只把最高的地方挖黑，整屏都是珊瑚；这里
//      反过来——低值区留黑，只让中间那一层发光，于是黑色宇宙为主、橙红结构是细丝

import kitty_custom_shader_types;

// ── 旋钮（在 magic-box.pipeline 里覆盖）──
static const float MBOX_STRENGTH = 0.60;  // 混进背景的强度
static const float MBOX_SPEED = 0.05;     // 相机前进速度（原作 0.05）。0 = 完全静止
static const float MBOX_GATE = 0.28;      // 门槛：场值超过它才发光。调小结构更多，调大只剩细丝

// ── 实现细节 ──
static const int MBOX_ITERS = 12;         // 原作 12；越多人越细、越贵
static const float MBOX_MAGIC = 0.77;     // 原作那个"魔法常数"，换值就是另一种分形
static const float MBOX_ZOOM = 0.25;      // 原作 0.25：越小越"放大"，大尺度重复越少
static const float MBOX_SCALE = 0.07;     // 原作把场值乘 0.07 之后再上色
static const float MBOX_HOLLOW = 0.51;    // 原作 smoothstep(.4,.51)：最亮处挖成黑（空腔）
static const float MBOX_BAND = 0.40;      // 发光带的上沿
static const float3 MBOX_WARM = float3(0.90, 0.20, 0.00);  // 橙红（sRGB，下面转线性）
static const float3 MBOX_COOL = float3(0.10, 0.05, 0.15);  // 暗紫（sRGB）
static const float MBOX_COOL_MIX = 0.55;  // 空腔里透出多少紫
static const float BG_TOLERANCE = 0.02;

// 原版那个矩阵：GLSL 的 mat3 字面是**列主序**，所以行主序写出来是它的转置。
static const float3x3 MBOX_M = float3x3(
     0.288,  0.069, -0.954,
     0.699,  0.665,  0.260,
     0.653, -0.743,  0.143);

// 场值：折进镜子盒子 + 迭代累加
static float
magic_box(float3 p) {
    p = 1.0 - abs(1.0 - (p - 2.0 * floor(p * 0.5)));   // GLSL mod(p,2) 的 floor 语义
    float last = length(p);
    float tot = 0.0;
    for (int i = 0; i < MBOX_ITERS; i++) {
        p = abs(p) / max(last * last, 1e-9) - MBOX_MAGIC;
        float now_len = length(p);
        tot += abs(now_len - last);
        last = now_len;
    }
    return tot;
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 res = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));
    // 原版 uv = fragCoord / iResolution.yy：纵向 0..1，横向 0..宽高比，不居中
    float2 uv = float2(t.pos.x * res.x / res.y, t.pos.y);
    float z = d.timestamp * MBOX_SPEED + 100.0;         // 原版的 100.0 是相机的起始深度
    float3 p = MBOX_ZOOM * mul(MBOX_M, float3(uv, z));

    float r = magic_box(p) * MBOX_SCALE;
    float lower = smoothstep(MBOX_GATE, MBOX_BAND, r);  // 发光带的下沿 → 上沿
    float hollow = smoothstep(MBOX_BAND, MBOX_HOLLOW, r); // 最亮处挖黑
    float vein = lower * (1.0 - hollow);
    // 原版颜色是在 sRGB 空间里挑的，kitty 这边要线性：pow(x, 2.2)
    float3 col = pow(MBOX_WARM, 2.2) * vein + pow(MBOX_COOL, 2.2) * (MBOX_COOL_MIX * hollow);

    return float4(lerp(color.rgb, col * MBOX_STRENGTH, bg), color.a);
}
