#language slang 2026
// Author: zxzx.
// Stateless background-only ink trail; cursor_trail_decay controls fading.

import kitty_custom_shader_types;

// Maximum ink blend; overridden by the matching pipeline variable.
static const float INK_STRENGTH = 0.12;
// Ink color.
static const float3 INK_COLOR = float3(1.0);
// Nib radius in pixels, with a soft outer edge.
static const float NIB_RADIUS = 15.0;
// Solid nib core as a fraction of its radius.
static const float NIB_CORE = 0.25;
// Background color tolerance in linear RGB.
static const float BG_TOLERANCE = 0.02;
// How strongly inked pixels approach full opacity.
static const float INK_ALPHA_BOOST = 0.50;

static float
seg_dist(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-7), 0.0, 1.0);
    return length(p - (a + ab * t));
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // Cursor geometry is available while the trail is active; its decay determines stroke opacity.
    float life = d.cursor_trail_state * d.cursor_trail_color.a;
    if (life <= 0.0) return color;

    // Apply only to background pixels, leaving text unchanged.
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 dims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 pen = t.pos * dims;
    float2 cur = float2((d.cursor_trail_edge.x + d.cursor_trail_edge.y) * 0.5,
                        (d.cursor_trail_edge.z + d.cursor_trail_edge.w) * 0.5) * dims;
    float2 prev = float2((d.cursor_trail_prev_edge.x + d.cursor_trail_prev_edge.y) * 0.5,
                         (d.cursor_trail_prev_edge.z + d.cursor_trail_prev_edge.w) * 0.5) * dims;
    // On the first cursor movement prev_edge is zero; ignore it to avoid a long stroke from the lower-left corner.
    float prev_ok = step(1e-5, d.cursor_trail_prev_edge.x + d.cursor_trail_prev_edge.y
                               + d.cursor_trail_prev_edge.z + d.cursor_trail_prev_edge.w);
    prev = lerp(cur, prev, prev_ok);

    // Scale the nib with the cursor, with a minimum radius.
    float nib = max(NIB_RADIUS, (d.cursor_trail_edge.y - d.cursor_trail_edge.x) * dims.x * 1.5);
    float k = (1.0 - smoothstep(nib * NIB_CORE, nib, seg_dist(pen, prev, cur))) * INK_STRENGTH * life;
    if (k <= 0.0) return color;
    return float4(lerp(color.rgb, INK_COLOR, k), lerp(color.a, 1.0, k * INK_ALPHA_BOOST));
}
