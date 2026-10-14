#language slang 2026
// Kitty integration and interpolation by zxzx.
// Distributed under CC BY-NC-SA 3.0; see LICENSES/CC-BY-NC-SA-3.0.txt.
// Interpolate cloud-bg texture a between sampled rows, then blend with the background.
// Sample computed-row texel centers; use the same row indexing as the first pass.

import kitty_custom_shader_types;

// Keep these defaults consistent with cloud-bg.slang; cloud-bg.pipeline overrides both.
static const int CLOUD_ROW_STRIDE = 4;
static const float CLOUD_STRENGTH = 0.12;
static const float CLOUD_MIX = 1.0;

static const float BG_TOLERANCE = 0.02;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // The first pass writes only texture a, so the backbuffer is still available for background matching.
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 res = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));
    float yrow = floor(t.pos.y * res.y);
    float stride = max(float(CLOUD_ROW_STRIDE), 1.0);

    float y0 = yrow - fmod(yrow, stride);   // fmod matches GLSL mod here because row indices are nonnegative.
    // Clamp to the last computed row to avoid sampling uncomputed rows.
    float ymax = floor((res.y - 1.0) / stride) * stride;
    float y1 = min(y0 + stride, ymax);
    float f = clamp((yrow - y0) / stride, 0.0, 1.0);

    float3 c0 = t.a.Sample(float2(t.pos.x, (y0 + 0.5) / res.y)).rgb;
    float3 c1 = t.a.Sample(float2(t.pos.x, (y1 + 0.5) / res.y)).rgb;
    float3 col = lerp(c0, c1, f);

    // Apply brightness and background blending.
    return float4(lerp(color.rgb, col * CLOUD_STRENGTH, bg * CLOUD_MIX), color.a);
}
