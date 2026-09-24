#language slang 2026
// sleep-wake —— 醒来那一段：OS 窗口聚焦后约 0.38 秒，把睡意拉回 0。
//
// 这一趟用的曲线带过冲（cubic-bezier 的 y 允许超过 1），所以 1 - progress
// 会在末尾掉到 0 以下，睡意跟着变成负数 —— apply 那趟把负值解释成
// 「刚醒来，内容亮一点点」。过冲幅度被 DIP_MAX 限住。

import kitty_custom_shader_types;

static const float DIP_MAX = 0.30;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 stored = t.persist.Sample(t.pos);
    float cur = stored.a > 0.999 ? clamp(stored.g, -DIP_MAX, 1.0) : 0.0;
    // 动画进度在 t（KittyTextures）上，不在 d 上。
    float p = t.animation_progress > 0.98 ? 1.0 : t.animation_progress;
    float sleep = max(min(cur, 1.0 - p), -DIP_MAX);
    return float4(0.0, sleep, 0.0, 1.0);
}
