#language slang 2026
// Author: zxzx.
// Liquid nib: capped, tapered afterimage with a fine metallic rim.
// No texture history, displacement, extra samples or idle animation.
import kitty_custom_shader_types;

static const float INK_STRENGTH = 0.12;
static const float3 INK_COLOR = float3(1.0);
static const float TRAIL_LENGTH = 72.0;
static const float RIM_STRENGTH = 0.065;
static const float HALO_STRENGTH = 0.025;
static const float BG_TOLERANCE = 0.02;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float life = clamp(d.cursor_trail_state * d.cursor_trail_color.a, 0.0, 1.0);
    if (life <= 0.0) return color;
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 dims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 p = t.pos * dims;
    float2 cur = float2(d.cursor_trail_edge.x + d.cursor_trail_edge.y,
                        d.cursor_trail_edge.z + d.cursor_trail_edge.w) * 0.5 * dims;
    float2 prev = float2(d.cursor_trail_prev_edge.x + d.cursor_trail_prev_edge.y,
                         d.cursor_trail_prev_edge.z + d.cursor_trail_prev_edge.w) * 0.5 * dims;
    float valid = step(1e-5, dot(abs(d.cursor_trail_prev_edge), float4(1.0)));
    prev = lerp(cur, prev, valid);
    float2 delta = cur - prev;
    float distance = length(delta);
    float2 axis = delta / max(distance, 0.001);
    float2 normal = float2(-axis.y, axis.x);
    // Contract toward the true cursor as the trail expires. Never bridge a screen.
    float span = min(distance, TRAIL_LENGTH) * life;
    float2 start = cur - axis * span;
    float u = clamp(dot(p - start, axis) / max(span, 0.001), 0.0, 1.0);
    float2 offset = p - lerp(start, cur, u);
    float cell = abs(d.cursor_trail_edge.y - d.cursor_trail_edge.x) * dims.x;
    float radius = clamp(cell * 0.75, 4.0, 12.0);
    radius *= lerp(0.22, 1.0, u) * lerp(0.65, 1.0, life);
    float r = length(offset) / max(radius, 0.001);
    if (r >= 1.8) return color;

    float body = 1.0 - smoothstep(0.3, 1.0, r);
    float rim = smoothstep(0.40, 0.65, r) * (1.0 - smoothstep(0.65, 0.95, r));
    float side = clamp(0.5 + dot(offset, normal) / max(radius * 2.0, 0.001), 0.0, 1.0);
    float halo = (1.0 - smoothstep(0.9, 1.8, r)) * (1.0 - body);
    float amount = bg * life * (body * INK_STRENGTH + rim * side * RIM_STRENGTH
                               + halo * HALO_STRENGTH);
    // Respect the IM cursor hue while keeping a silver highlight.
    float3 pigment = lerp(INK_COLOR, d.cursor_trail_color.rgb, 0.40);
    float3 tint = lerp(pigment, float3(1.0), rim * side * 0.65);
    return float4(lerp(color.rgb, tint, clamp(amount, 0.0, 1.0)), color.a);
}
