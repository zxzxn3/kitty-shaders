#language slang 2026
// Kitty integration and interpolation by zxzx.
// 按行插值 cloud-bg 的纹理 a，再混合背景。
// 采样位置须落在已计算行的 texel 中心，行号算法与第一趟一致。

import kitty_custom_shader_types;

// 必须和 cloud-bg.slang 里的同名常量一致；这两个会被 cloud-bg.pipeline 的 var 覆盖。
static const int CLOUD_ROW_STRIDE = 4;
static const float CLOUD_STRENGTH = 0.12;
static const float CLOUD_MIX = 1.0;

static const float BG_TOLERANCE = 0.02;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // 第一趟只写纹理 a，此处 backbuffer 仍可用于背景比色。
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 res = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));
    float yrow = floor(t.pos.y * res.y);
    float stride = max(float(CLOUD_ROW_STRIDE), 1.0);

    float y0 = yrow - fmod(yrow, stride);   // fmod：行号恒非负，等价于 GLSL 的 mod
    // 往上夹到「最后一条算过的行」，别落到没算过的行上去。
    float ymax = floor((res.y - 1.0) / stride) * stride;
    float y1 = min(y0 + stride, ymax);
    float f = clamp((yrow - y0) / stride, 0.0, 1.0);

    float3 c0 = t.a.Sample(float2(t.pos.x, (y0 + 0.5) / res.y)).rgb;
    float3 c1 = t.a.Sample(float2(t.pos.x, (y1 + 0.5) / res.y)).rgb;
    float3 col = lerp(c0, c1, f);

    // 应用亮度和背景混合比例。
    return float4(lerp(color.rgb, col * CLOUD_STRENGTH, bg * CLOUD_MIX), color.a);
}
