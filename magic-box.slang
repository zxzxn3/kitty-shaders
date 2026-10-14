#language slang 2026
// Kitty adaptation and cold-color redesign by zxzx; original Magic Box source remains unverified.
// Retain the fractal recurrence and reference matrix; do not claim authorship of that core.
// Reduce iterations 12 -> 10; add background masking, flow/hue modulation, cool colors and alpha preservation.

import kitty_custom_shader_types;

// Controls overridden by magic-box.pipeline.
static const float MBOX_STRENGTH = 0.60;  // Background blending strength.
static const float MBOX_SPEED = 0.05;     // Forward camera speed; original value: 0.05. Set 0 for no drift.
static const float MBOX_GATE = 0.34;      // Filament threshold: lower reveals more structure, higher keeps fewer strands.

// Implementation details.
static const int MBOX_ITERS = 10;         // Original value: 12; more iterations add detail and cost.
static const float MBOX_MAGIC = 0.77;     // Original fractal constant; changing it changes the fractal.
static const float MBOX_ZOOM = 0.25;      // Original value: 0.25; lower values zoom in and reduce large-scale repetition.
static const float MBOX_SCALE = 0.07;     // The original scales the field by 0.07 before coloring.
// Color thresholds expressed on the field * 0.07 scale.
static const float MBOX_BASE_LO = 0.18;   // Start of the base-color range.
static const float MBOX_BASE_HI = 0.60;   // End of the base-color range, followed by filaments.
static const float MBOX_RIM0 = 0.42;      // Center of the filament band.
static const float MBOX_RIM1 = 0.52;      // Upper edge of the filament band, followed by cavities.
static const float MBOX_FLOW = 0.45;      // Flow modulation amplitude.
static const float MBOX_HUE_FREQ = 0.12;  // Hue variation frequency; lower values reduce color variation within one frame.
static const float3 MBOX_HUE_DIR = float3(0.55, 0.85, 0.42);   // Hue variation direction.
static const float3 MBOX_FLOW_DIR = float3(0.21, -0.48, 0.30); // Flow direction.
// Colors in sRGB, converted to linear RGB in the shader.
static const float3 MBOX_DEEP = float3(0.015, 0.035, 0.060);   // Near-black deep blue.
static const float3 MBOX_MID = float3(0.060, 0.170, 0.240);    // Deep teal.
static const float3 MBOX_ALT = float3(0.200, 0.360, 0.500);    // Steel blue; the other end of the hue blend.
static const float3 MBOX_LIGHT = float3(0.450, 0.680, 0.720);  // Pale cyan filaments.
static const float BG_TOLERANCE = 0.02;

// The original GLSL mat3 literal is column-major; transpose it for row-major representation.
static const float3x3 MBOX_M = float3x3(
     0.288,  0.069, -0.954,
     0.699,  0.665,  0.260,
     0.653, -0.743,  0.143);

// Field evaluation: mirrored box folding and iterative accumulation.
static float
magic_box(float3 p) {
    p = 1.0 - abs(1.0 - (p - 2.0 * floor(p * 0.5)));   // Floor-based GLSL mod(p, 2) semantics.
    float last = length(p);
    float tot = 0.0;
    for (int i = 0; i < MBOX_ITERS; i++) {
        p = abs(p) / max(last * last, 1e-9) - MBOX_MAGIC;
        float now_len = length(p);
        tot += abs(now_len - last);
        last = now_len;
    }
    return tot;
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 res = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));
    // Original fragCoord / iResolution.yy: y spans 0..1, x spans the aspect ratio, without centering.
    float2 uv = float2(t.pos.x * res.x / res.y, t.pos.y);
    float z = d.timestamp * MBOX_SPEED + 100.0;         // Original initial camera depth: 100.0.
    float3 world = MBOX_ZOOM * mul(MBOX_M, float3(uv, z));

    float r = magic_box(world) * MBOX_SCALE;

    // Base color: deep blue at low field values, with flow modulation for tonal variation.
    float flow = 1.0 - 0.5 * MBOX_FLOW
               + 0.5 * MBOX_FLOW * sin(dot(world, normalize(MBOX_FLOW_DIR)) * 0.06 + 1.7);
    float base = smoothstep(MBOX_BASE_LO, MBOX_BASE_HI, r) * flow;
    // Filaments: squared band-pass response for softer edges and thinner strands.
    float rim = smoothstep(MBOX_GATE, MBOX_RIM0, r) * (1.0 - smoothstep(MBOX_RIM0, MBOX_RIM1, r));
    rim *= rim;
    // Hue varies with position between steel blue and teal, and changes during drift.
    float hue = 0.5 + 0.5 * sin(dot(world, normalize(MBOX_HUE_DIR)) * MBOX_HUE_FREQ);

    float3 col = pow(MBOX_DEEP, 2.2) * base
               + pow(lerp(MBOX_MID, MBOX_ALT, hue), 2.2) * (0.5 * base * base)
               + pow(MBOX_LIGHT, 2.2) * (rim * (0.6 + 0.4 * hue));

    return float4(lerp(color.rgb, col * MBOX_STRENGTH, bg), color.a);
}
