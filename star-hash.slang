#language slang 2026
// star-hash —— 哈希星场背景
//
// 和 star-nest 完全不同的做法：不做分形、不做光线步进，就是"格子哈希撒星星"。
//   1. 把像素坐标按 STAR_CELL 切成格子
//   2. 每个格子用哈希决定：这颗星存不存在、放在格子里的哪一点、多亮、多大、偏冷还是偏暖
//   3. 只算 3×3 邻域（星点半径远小于格子边长，其实 2×2 都够），按距离衰减成一个小圆点
//
// 它买到的东西（star-nest 给不了的）：
//   * 密度、亮度、大小都是直接控制的，不随窗口形状/视线方向漂移
//   * 不会有"大光斑"——星点半径上限就 2~3 像素，天然没有大团块
//   * 便宜得多：每像素 9 次哈希，没有循环累积，没有开方
//   * 漂移是真正的平移，看着是星星在缓慢滑过，而不是像素在"沸腾"
// 它放弃的：分形那种大尺度的星云絮状结构，所以整体是"纯星场"而不是"深空"。
//
// 哈希函数来自 Dave Hoskins 的 "Hash without Sine"（MIT）：
//   https://www.shadertoy.com/view/4djSRW
//
// 只画背景像素（和背景色比色），所以和 cloud-bg / star-nest / bg-drift 一样是互斥的背景。

import kitty_custom_shader_types;

// ── 四个旋钮（在 star-hash.pipeline 里覆盖）──
static const float STAR_CELL = 22.0;     // 格子边长（像素）。越小星越密
static const float STAR_DENSITY = 0.35;  // 有多大比例的格子有星
static const float STAR_BRIGHT = 0.50;   // 最亮的星（线性亮度，叠在背景上）
static const float STAR_SPEED = 12.0;    // 漂移速度（像素/秒），0 = 完全静止

// ── 实现细节 ──
static const float STAR_RADIUS = 1.7;    // 星点基准半径（像素）
static const float STAR_BAND = 0.45;     // 银河带强弱：让疏密有大尺度变化，不至于像噪点
static const float BG_TOLERANCE = 0.02;

static float
hash21(float2 p) {
    float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

static float3
star_tint(float t) {
    // 0 = 暖白（偏橘），1 = 冷白（偏蓝）
    return lerp(float3(1.0, 0.86, 0.70), float3(0.78, 0.88, 1.0), t);
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 res = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));
    // 星场坐标就锚在像素上（各向同性、分辨率无关），只按时间整体平移
    float2 sky = t.pos * res + float2(-0.35, -0.94) * (d.timestamp * STAR_SPEED);

    float2 cell = floor(sky / STAR_CELL);
    float3 stars = float3(0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 c = cell + float2(i, j);
            if (hash21(c) > STAR_DENSITY) continue;              // 大部分格子是空的
            float2 jitter = float2(hash21(c + 11.7), hash21(c + 23.1));
            float2 delta = sky - (c + jitter) * STAR_CELL;
            float mag = hash21(c + 53.9);
            float radius = STAR_RADIUS * (0.55 + 0.75 * mag);    // 亮的也大一点
            float d2 = dot(delta, delta);
            if (d2 > radius * radius) continue;                  // 够不着，早退
            // 三次衰减的小圆点：中心最亮、边缘平滑收到 0
            float profile = 1.0 - d2 / (radius * radius);
            stars += (profile * profile * profile) * (0.22 + 0.78 * mag * mag * mag)
                     * star_tint(hash21(c + 71.3));
        }
    }

    // 大尺度的疏密变化：几个低频正弦叠出来的"银河带"，比均匀撒点耐看
    float2 q = sky / 700.0;
    float band = 1.0 + STAR_BAND * (sin(q.x * 2.1 + 1.7) * cos(q.y * 1.7 - 0.4)
                                    + 0.5 * sin((q.x + q.y) * 3.1));

    // 加法叠在背景上：背景该多黑还是多黑，星星浮在上面
    return float4(lerp(color.rgb, color.rgb + stars * (STAR_BRIGHT * band), bg), color.a);
}
