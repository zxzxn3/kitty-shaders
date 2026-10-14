#language slang 2026
// Kitty adaptation by zxzx; curvature formula retained from Kitty's crt.slang by Kovid Goyal.
// Source: https://github.com/kovidgoyal/kitty/blob/master/kitty/shaders/custom/crt.slang (GPLv3).
// Kitty credits https://www.shadertoy.com/view/WsVSzV (CC BY-NC-SA 3.0) as its original source.
// Remove scanlines and tint; retain warped sampling alpha for transparent windows.
// Expose horizontal/vertical curvature independently; use event-driven rather than periodic redraws.

import kitty_custom_shader_types;

// 曲率强度。kitty 自带 crt 的默认值就是 0.25。
static const float WARP = 0.25f;
// 横向 / 纵向弯曲比例。
static const float WARP_X = 0.3f;
static const float WARP_Y = 0.4f;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // 视口内的 UV，0..1。
    float2 uv = t.pos;

    // 到中心的距离平方：离中心越远推得越狠，这就是"视场被扭起来"的来源。
    float2 dc = abs(0.5f - uv);
    dc *= dc;

    uv.x = 0.5f + (uv.x - 0.5f) * (1.0f + dc.y * WARP_X * WARP);
    uv.y = 0.5f + (uv.y - 0.5f) * (1.0f + dc.x * WARP_Y * WARP);

    // 视口外采样由 sampler clamp，边缘延展而非黑边。
    return t.backbuffer.Sample(uv);
}
