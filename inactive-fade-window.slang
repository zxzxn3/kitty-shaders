#language slang 2026
// inactive-fade —— 窗口那一维：这个 OS 窗口失去焦点后，整窗慢慢褪色。
//
// 用 animation_progress 直接当褪色程度：它来自 kitty 的时钟，跟「有没有帧」无关。
// 这点对失焦窗口很重要——失焦窗口可能很少被重绘，要是按帧累加，褪色会卡在半路。
// 这个组本身也带 animation_step 50，所以真被重绘时是以 20fps 走的，渐变看得见；
// 万一不重绘，等下次重绘时 level 依然是「按真实时间算出来的正确值」。
//
// 交回焦点不需要这一组做任何事：inactive-fade-panes 的规则是「活动分屏内一律清零」，
// 它由 os-window-focus-in 触发，会立刻把这一组的成果抹掉。

import kitty_custom_shader_types;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    return float4(0.0, t.animation_progress, 0.0, 1.0);
}
