#language slang 2026
// Author: zxzx.
import kitty_custom_shader_types;

public float4 fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float progress = t.animation_progress;
    if (progress <= 0.0 || progress >= 1.0) return color;
    float3 delta = abs(color.rgb - d.background.rgb);
    float mask = 1.0 - smoothstep(0.001, 0.012, max(delta.r, max(delta.g, delta.b)));
    float2 px = t.pos * float2(d.viewport_size_pixels);
    float2 far_edge = float2(d.viewport_size_pixels) - px;
    float edge = min(min(px.x, far_edge.x), min(px.y, far_edge.y));
    float rim = saturate(1.0 - edge / 24.0);
    rim *= rim;
    // A quick light settling into the upper-right edge, then fully disappearing.
    float envelope = 4.0 * progress * (1.0 - progress);
    envelope *= (1.0 - progress);
    float corner = t.pos.x * t.pos.y;
    float3 light = lerp(float3(0.08, 0.32, 0.46), float3(0.40, 0.22, 0.11), t.pos.x);
    return float4(saturate(color.rgb + light * rim * envelope * (0.20 + corner) * mask * 0.14), color.a);
}
