#language slang 2026
// ink-stain —— 把 accumulate 算好的墨迹图从临时纹理 a 搬回 persist。
// 单独一趟是必须的：同一趟里读写的命名纹理会互相打架，kitty 会把输入换成 backbuffer。

import kitty_custom_shader_types;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    return float4(t.a.Sample(t.pos).r, 0.0, 0.0, 1.0);
}
