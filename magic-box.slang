#language slang 2026
// magic-box —— 魔盒分形背景（"深海潜流"版）
//
// 原作：用户给的这段 "Magic Box"（Shadertoy；作者署名我没核实，你要是有链接我补上）。
//
// 数学（照原作，一行没改）：
//   * 先把坐标折进一个 1×1×1 的镜子盒子：p = 1 - |1 - mod(p, 2)|
//   * 迭代 p = |p| / |p_上一轮|² - MAGIC，累加每次长度变化的绝对值 —— 累加值就是场值
//     **除的是上一轮的长度，不是当前 p 自己的长度**：这是它和 star-nest 那类分形最不一样
//     的地方，照抄成 dot(p,p) 会得到另一套花样。
//   * 相机沿一个固定旋转轴（原版那个 3×3 矩阵）朝盒子里飞，z 随时间推进
//
// 观感是我自己定的，和原作差得比较远（第一版照原作做出来是橙红"熔岩珊瑚"，太刺激）：
//   底色 —— 近黑的深海蓝，用一条极慢的正弦做出"深浅/洋流"，不是一块死板的纯色
//   细丝 —— 只在中间那一层浮现的带通，软边、淡青，像水下的暗流/浮沫
//   色彩 —— 随位置缓慢游走：同一屏里，左边偏钢蓝、右边偏青绿，飞过去时还会整体变色
//   也就是"低饱和、冷色、有变化"，而不是一片高饱和的红橙
//
// 移植/改造时处理的四件事：
//   1. 颜色空间：原版输出直接当显示值（≈sRGB），kitty 的 shader 输出是线性 RGB，
//      所以颜色做一次 pow(x, 2.2) 转换，否则会亮得发艳
//   2. 只画背景像素，按 MBOX_STRENGTH 混进背景（原版是整屏不透明）
//   3. 上色从原版的"高通"（低值铺满色、最高处挖黑）改成"低值留暗 + 中间带通"，于是黑底为主
//   4. 迭代 12 → 10：既省 17% 的算力，结构也更柔（对"冷静"这个方向是正收益）

import kitty_custom_shader_types;

// ── 旋钮（在 magic-box.pipeline 里覆盖）──
static const float MBOX_STRENGTH = 0.60;  // 混进背景的强度
static const float MBOX_SPEED = 0.05;     // 相机前进速度（原作 0.05）。0 = 完全静止
static const float MBOX_GATE = 0.34;      // 细丝的门槛：调小结构更多，调大只剩几缕

// ── 实现细节 ──
static const int MBOX_ITERS = 10;         // 原作 12；越多人越细、越贵
static const float MBOX_MAGIC = 0.77;     // 原作那个"魔法常数"，换值就是另一种分形
static const float MBOX_ZOOM = 0.25;      // 原作 0.25：越小越"放大"，大尺度重复越少
static const float MBOX_SCALE = 0.07;     // 原作把场值乘 0.07 之后再上色
// 上色用的几条边界（都在"场值×0.07"这个刻度上）
static const float MBOX_BASE_LO = 0.18;   // 底色起点
static const float MBOX_BASE_HI = 0.60;   // 底色到顶（再往上就是细丝的地盘）
static const float MBOX_RIM0 = 0.42;      // 细丝带的中心
static const float MBOX_RIM1 = 0.52;      // 细丝带的上沿（再往上是空腔）
static const float MBOX_FLOW = 0.45;      // "洋流"起伏的幅度
static const float MBOX_HUE_FREQ = 0.12;  // 色相游走的快慢（越小，同屏色差越少）
static const float3 MBOX_HUE_DIR = float3(0.55, 0.85, 0.42);   // 色相沿哪个方向走
static const float3 MBOX_FLOW_DIR = float3(0.21, -0.48, 0.30); // "洋流"沿哪个方向走
// 配色（sRGB，进 shader 后转线性）
static const float3 MBOX_DEEP = float3(0.015, 0.035, 0.060);   // 近黑深海蓝
static const float3 MBOX_MID = float3(0.060, 0.170, 0.240);    // 深青
static const float3 MBOX_ALT = float3(0.200, 0.360, 0.500);    // 钢蓝（和深青互为色相两端）
static const float3 MBOX_LIGHT = float3(0.450, 0.680, 0.720);  // 细丝的淡青
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
    float3 world = MBOX_ZOOM * mul(MBOX_M, float3(uv, z));

    float r = magic_box(world) * MBOX_SCALE;

    // 底色：低值区 = 近黑深海蓝，"洋流"让它有深浅起伏而不是一块死色
    float flow = 1.0 - 0.5 * MBOX_FLOW
               + 0.5 * MBOX_FLOW * sin(dot(world, normalize(MBOX_FLOW_DIR)) * 0.06 + 1.7);
    float base = smoothstep(MBOX_BASE_LO, MBOX_BASE_HI, r) * flow;
    // 细丝：带通，取平方让边更柔、丝更细
    float rim = smoothstep(MBOX_GATE, MBOX_RIM0, r) * (1.0 - smoothstep(MBOX_RIM0, MBOX_RIM1, r));
    rim *= rim;
    // 色相随位置缓慢游走：一屏之内既偏钢蓝也偏青绿，飞过去时整体还会变色
    float hue = 0.5 + 0.5 * sin(dot(world, normalize(MBOX_HUE_DIR)) * MBOX_HUE_FREQ);

    float3 col = pow(MBOX_DEEP, 2.2) * base
               + pow(lerp(MBOX_MID, MBOX_ALT, hue), 2.2) * (0.5 * base * base)
               + pow(MBOX_LIGHT, 2.2) * (rim * (0.6 + 0.4 * hue));

    return float4(lerp(color.rgb, col * MBOX_STRENGTH, bg), color.a);
}
