#language slang 2026
// sleep-wake —— 入睡那一段：OS 窗口失焦后约 0.85 秒，把「睡意」从当前值推到 1。
//
// 通道约定（两个效果共用同一块 persist 纹理）：
//   .r = 墨量（ink-stain 用）  .g = 睡意（本效果）  .b = 空闲  .a = 1.0 哨兵
// 这一趟只算 .g，输出到临时纹理 b，再由 commit 那趟并回 persist。

import kitty_custom_shader_types;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 stored = t.persist.Sample(t.pos);
    // 从没写过（或者读到垃圾）就当完全清醒。
    float cur = stored.a > 0.999 ? clamp(stored.g, 0.0, 1.0) : 0.0;
    // 收尾那一帧的 progress 未必正好是 1，补一个台阶，保证睡意精确落在 1。
    // 注意动画进度在 t（KittyTextures）上，不在 d 上。
    float target = t.animation_progress > 0.98 ? 1.0 : t.animation_progress;
    // 只往更睡的方向走。醒来是 rise 那一趟的事，这里绝不自己醒。
    float sleep = max(cur, target);
    return float4(0.0, sleep, 0.0, 1.0);
}
