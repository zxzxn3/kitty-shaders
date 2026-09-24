#language slang 2026
// inactive-fade —— 把临时纹理 b 里的褪色程度并回 persist 的 .g 通道。
// .r 是 ink-stain 的墨量、.b 以后留给别的效果，都从 persist 原样带走。
// 单独一趟是必须的：同一趟里读写的命名纹理会互相打架，kitty 会把输入换成 backbuffer。

import kitty_custom_shader_types;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 prev = t.persist.Sample(t.pos);
    return float4(prev.r, t.b.Sample(t.pos).g, prev.b, 1.0);
}
