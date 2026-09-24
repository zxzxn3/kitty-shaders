#language slang 2026
// ink-stain —— 把 accumulate 算好的墨迹图从临时纹理 a 搬回 persist。
// 单独一趟是必须的：同一趟里读写的命名纹理会互相打架，kitty 会把输入换成 backbuffer。
// 通道约定：.r = 墨量（本效果），.g = 褪色程度（pane-fade），.b = 空闲，.a = 1.0 哨兵。
// 这一趟只更新 .r，其余通道从 persist 原样带走，免得抹掉别的效果的状态。

import kitty_custom_shader_types;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 prev = t.persist.Sample(t.pos);
    return float4(t.a.Sample(t.pos).r, prev.g, prev.b, 1.0);
}
