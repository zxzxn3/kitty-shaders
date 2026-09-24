#language slang 2026
// ink-stain —— 墨痕。光标像笔尖，走过的地方洇开一点白色水痕，然后慢慢干掉。
//
// 这一趟负责两件事：
//   1. 让已有的墨按真实经过的时间衰减（按秒算，不是按帧算，掉帧也不会算错）
//   2. 把当前这一笔点到墨迹图上
// 结果写进临时纹理 a，再由 commit 那一趟搬回 persist —— 同一趟里不能同时读和写
// persist，kitty 会把输入悄悄换成 backbuffer。

import kitty_custom_shader_types;

// 一笔墨彻底干掉需要的时间常数，秒。
// 注意：动画窗口（pipeline 里的 animation_stop）必须大于约 4 倍这个值，
// 否则窗口结束时墨还没干完，会被冻在屏幕上不再变化。
static const float DRY_TIME = 0.85;
// 笔尖半径，像素。往外是软边。
static const float NIB_RADIUS = 15.0;
// 笔尖中心这一圈占半径的比例，圈内是实心的。
static const float NIB_CORE = 0.25;
// 每次落笔的墨量，1.0 表示一笔就到最浓。
static const float NIB_STRENGTH = 0.55;
// 低于这个值就当已经干了。没有它，8 位纹理上的残值会永远挂在屏幕上。
static const float DRY_EPSILON = 0.020;
// 除了指数衰减，每秒再线性刮掉一点，让尾巴收得干净。
static const float DRAIN_PER_SECOND = 0.06;
// 墨洇上来的时间常数，秒。0 就是啪地出现，越大起笔越软。
static const float SOAK_TIME = 0.08;
// 判定「笔还在动」的时间窗，秒。
static const float MOVING_WINDOW = 0.09;

static float
seg_dist(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-7), 0.0, 1.0);
    return length(p - (a + ab * t));
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // 上一帧到现在过了多久。用真实时间，所以动画窗口里每一帧的衰减都算得对。
    float dt = max(d.timestamp - d.last_rendered_at, 0.0);

    // persist 是一块显存，第一次写之前内容不作保证：NaN、负值、越界一律当 0，
    // 并用 alpha 当「这块像素确实是我们写的」的标记（没有 alpha 通道时它恒为 1，无害）。
    float4 stored = t.persist.Sample(t.pos);
    float ink = stored.r;
    if (!(ink > 0.0) || stored.a < 0.999) ink = 0.0;
    ink = min(ink, 1.0);
    ink = max(ink * exp(-dt / DRY_TIME) - dt * DRAIN_PER_SECOND, 0.0);
    if (ink < DRY_EPSILON) ink = 0.0;

    // 只有笔尖正在移动时才落墨 —— 停在原地不该把那一处越积越浓。
    float moving = exp(-max(d.timestamp - d.cursor_trail_change_time, 0.0) / MOVING_WINDOW);
    float gate = moving * step(0.001, d.cursor_trail_state) * d.cursor_trail_color.a;

    if (gate > 0.0) {
        float2 dims = float2(d.viewport_size_pixels) * t.viewport.zw;
        float2 pen = t.pos * dims;
        float2 cur = float2((d.cursor_trail_edge.x + d.cursor_trail_edge.y) * 0.5,
                            (d.cursor_trail_edge.z + d.cursor_trail_edge.w) * 0.5) * dims;
        float2 prev = float2((d.cursor_trail_prev_edge.x + d.cursor_trail_prev_edge.y) * 0.5,
                             (d.cursor_trail_prev_edge.z + d.cursor_trail_prev_edge.w) * 0.5) * dims;
        // 光标第一次移动时 prev_edge 还是全零，直接用它会在左下角拉出一条长划。
        float prev_ok = step(1e-5, d.cursor_trail_prev_edge.x + d.cursor_trail_prev_edge.y
                                   + d.cursor_trail_prev_edge.z + d.cursor_trail_prev_edge.w);
        prev = lerp(cur, prev, prev_ok);

        // 笔尖粗细跟着光标本身的大小走，但不小于一个下限。
        float nib = max(NIB_RADIUS, (d.cursor_trail_edge.y - d.cursor_trail_edge.x) * dims.x * 1.5);
        float deposit = (1.0 - smoothstep(nib * NIB_CORE, nib, seg_dist(pen, prev, cur)))
                      * NIB_STRENGTH * gate;
        // 让墨渗上来而不是「啪」地出现：按真实时间做指数逼近，帧率无关。
        float rise = 1.0 - exp(-dt / SOAK_TIME);
        float target = max(ink, deposit);
        if (target > ink) ink = lerp(ink, target, rise);
    }

    return float4(ink, 0.0, 0.0, 1.0);
}
