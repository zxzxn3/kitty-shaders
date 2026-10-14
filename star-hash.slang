#language slang 2026
// Author: zxzx. Two-layer parallax starfield with background-only masking.
// hash21 uses Dave Hoskins' Hash without Sine formula (MIT).
// Formula source: https://www.shadertoy.com/view/4djSRW

import kitty_custom_shader_types;

// Controls overridden by star-hash.pipeline.
static const float STAR_CELL = 26.0;      // Near-layer cell size in pixels; smaller values increase density.
static const float STAR_DENSITY = 0.35;   // Near-layer occupied-cell fraction.
static const float STAR_BRIGHT = 0.55;    // Maximum near-layer additive linear brightness.
static const float STAR_SPEED = 120.0;    // Near-layer drift speed in pixels per second; 0 disables drift.
static const float STAR_FAR_SCALE = 0.55; // Far-layer cell size, radius and brightness scale; smaller values make stars finer and dimmer.
static const float STAR_FAR_SPEED = 0.35; // Far-layer speed ratio controls parallax.

// Implementation details.
static const float STAR_RADIUS = 2.2;     // Near-layer base star radius in pixels.
static const float STAR_FAR_DENSITY = 0.30; // Far-layer occupied-cell fraction.
static const float STAR_BAND = 0.45;      // Large-scale density modulation.
static const float BG_TOLERANCE = 0.02;

static float
hash21(float2 p) {
    float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

static float3
star_tint(float t) {
    // 0 = warm white, 1 = cool white.
    return lerp(float3(1.0, 0.86, 0.70), float3(0.78, 0.88, 1.0), t);
}

// One star layer: divide sky space into cell_px cells and place stars.
static float3
star_layer(float2 sky, float cell_px, float density, float radius_px, float bright, float seed) {
    float2 cell = floor(sky / cell_px);
    float2 fx = sky - cell * cell_px;                 // Pixel position within its cell.
    float rmax = radius_px * 1.3;                     // Maximum star radius, matching the radius calculation below.
    // Precompute three gaps per axis and skip cells beyond the star radius.
    float3 gx = float3(fx.x, 0.0, cell_px - fx.x);
    float3 gy = float3(fx.y, 0.0, cell_px - fx.y);
    float rmax2 = rmax * rmax;
    float3 acc = float3(0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            if (gx[i + 1] * gx[i + 1] + gy[j + 1] * gy[j + 1] > rmax2) continue;
            float2 c = cell + float2(i, j) + seed;           // Seed offsets decorrelate the two layers.
            if (hash21(c) > density) continue;               // Most cells are empty.
            float2 jitter = float2(hash21(c + 11.7), hash21(c + 23.1));
            float2 delta = sky - ((cell + float2(i, j)) + jitter) * cell_px;
            float mag = hash21(c + 53.9);
            float radius = radius_px * (0.55 + 0.75 * mag);  // Brighter stars are slightly larger.
            float d2 = dot(delta, delta);
            if (d2 > radius * radius) continue;              // Skip pixels beyond the radius.
            // Cubic radial falloff: bright center and a smooth transition to zero.
            float profile = 1.0 - d2 / (radius * radius);
            acc += (profile * profile * profile) * (0.22 + 0.78 * mag * mag * mag)
                   * star_tint(hash21(c + 71.3)) * bright;
        }
    }
    return acc;
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 res = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));
    float2 base = t.pos * res;                              // Pixel-space coordinates keep the starfield isotropic.
    float2 drift = float2(-0.35, -0.94) * (d.timestamp * STAR_SPEED);

    float3 stars = star_layer(base + drift, STAR_CELL, STAR_DENSITY, STAR_RADIUS, 1.0, 0.0)
                 + star_layer(base + drift * STAR_FAR_SPEED,
                              STAR_CELL * STAR_FAR_SCALE, STAR_FAR_DENSITY,
                              STAR_RADIUS * STAR_FAR_SCALE, STAR_FAR_SCALE, 37.0);
    // Compute large-scale trigonometric modulation only for pixels containing stars.
    if (stars.r + stars.g + stars.b <= 0.0) return color;

    // Both layers share the same large-scale density field.
    float2 q = (base + drift * 0.5) / 700.0;
    float band = 1.0 + STAR_BAND * (sin(q.x * 2.1 + 1.7) * cos(q.y * 1.7 - 0.4)
                                    + 0.5 * sin((q.x + q.y) * 3.1));

    // Add stars over the background without lifting its base black level.
    return float4(lerp(color.rgb, color.rgb + stars * (STAR_BRIGHT * band), bg), color.a);
}
