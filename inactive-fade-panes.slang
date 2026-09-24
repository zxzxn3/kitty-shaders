#language slang 2026
// inactive-fade —— 分屏那一维：只有当前分屏正常，其它分屏慢慢褪色。
//
// 每个像素自己按真实时间累加，所以 3 个以上分屏来回切时，早就淡下去的分屏
// 不会被「重新开始计时」拉回来重来一遍。
//
// 边界不写死成 0/1：用 fwidth 把 UV 距离换算成像素，在 1.5 像素内平滑过渡，
// 过渡带上的像素最终只褪到对应的比例（比如边缘 50% 处只褪一半），
// 所以分屏交界处不会出现生硬的直线。
//
// 通道约定：persist.r = 墨量（ink-stain），persist.g = 褪色程度（本效果），
// .a = 1.0 哨兵。本趟只算 .g，输出到临时纹理 b，由 commit 并回 persist。

import kitty_custom_shader_types;

// 从「刚失去注意力」到「完全没颜色」需要的时间，秒。
// 要和 pipeline 里的 animation_stop 保持一致。
static const float FADE_TIME = 5.0;
// 边界羽化多少像素。
static const float EDGE_FEATHER_PX = 1.5;
// 单帧最多算作多少秒。终端空闲很久之后的第一帧 dt 会很大，
// 不夹住的话褪色会一步到位，5 秒的渐变就白做了。
static const float MAX_STEP = 0.1;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 stored = t.persist.Sample(t.pos);
    float prev = stored.a > 0.999 ? clamp(stored.g, 0.0, 1.0) : 0.0;

    // 目标：在活动分屏里是 0（正常显示），在外面是 1（该褪到底），边界上是中间值。
    float4 g = d.active_window_geometry;
    float target = 1.0;
    if (g.z > 0.0 && g.w > 0.0) {
        float2 dd = min(t.pos - g.xy, g.xy + g.zw - t.pos);
        float dmin = min(dd.x, dd.y);
        float feather = max(fwidth(dmin) * EDGE_FEATHER_PX, 1e-6);
        target = 1.0 - smoothstep(0.0, feather, dmin);
    }

    // 往上爬有速度限制，往下（重新聚焦）立刻到位。
    float dt = clamp(d.timestamp - d.last_rendered_at, 0.0, MAX_STEP);
    float level = target < prev ? target : min(prev + dt / FADE_TIME, target);
    return float4(0.0, level, 0.0, 1.0);
}
