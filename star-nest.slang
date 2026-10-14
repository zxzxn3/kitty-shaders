#language slang 2026
// Slang port and Kitty adaptation by zxzx; original Star Nest by Pablo Roman Andrioli.
// Source: https://www.shadertoy.com/view/XlfGRj; retain the original source attribution.
// Preserve the tiled fractal recurrence and distance-based color accumulation.
// Reduce volume steps 20 -> 16 and fractal iterations 17 -> 14; normalize iteration strength.
// Add background-only masking, black level, reduced haze, exponential brightness cap and NaN guards.
// Preserve alpha; use floor-based GLSL modulo and expose slow camera drift through the pipeline.

import kitty_custom_shader_types;

// Controls overridden by star-nest.pipeline.
static const float NEB_BLACK = 18.0;     // Black level: values below the threshold become black; higher values darken the image.
static const float NEB_BRIGHT = 0.0004;  // Nebula and star brightness.
static const float NEB_SPEED = 0.0025;   // Drift speed; 0 disables drift.

// Implementation details.
static const int NEB_STEPS = 16;
static const int NEB_ITER = 14;
// Normalize to the original 17-iteration scale to preserve the meaning of the black level.
static const float NEB_ANORM = 17.0 / 14.0;
static const float NEB_HAZE = 0.02;    // Original haze term, reduced from 1.0 to avoid a gray background.
static const float NEB_SAT = 0.85;     // Original saturation parameter.
static const float NEB_ZOOM = 0.8;     // Original field-of-view parameter.
static const float NEB_PEAK = 0.35;    // Brightness limit with exponential compression.
static const float NEB_SCALE = 0.01;   // Original final v * 0.01 scale.
static const float NEB_TILE = 0.850;
static const float NEB_FORMU = 0.53;
static const float NEB_DARKMAT = 0.300;
static const float NEB_DISTFADE = 0.730;
static const float NEB_STEP0 = 0.1;
static const float NEB_A_MAX = 1.0e5;  // Clamp extreme field values to avoid infinity.
static const float BG_TOLERANCE = 0.02;

// GLSL mod uses floor semantics, unlike Slang fmod; implement it explicitly.
static float3
glsl_mod(float3 x, float3 y) { return x - y * floor(x / y); }

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // Reject text pixels before running the expensive fractal calculations.
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 res = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));
    float2 uv = t.pos - 0.5;
    uv.y *= res.y / res.x;               // Aspect-ratio correction keeps stars isotropic.
    float3 dir = float3(uv * NEB_ZOOM, 1.0);

    // Drift the camera in a fixed direction.
    float time = d.timestamp * NEB_SPEED + 0.25;
    float3 frm = float3(1.0 + 2.0 * time, 0.5 + time, 0.5 - 2.0 * time);

    float s = NEB_STEP0, fade = 1.0;
    float3 v = float3(0.0);
    float blk3 = NEB_BLACK * NEB_BLACK * NEB_BLACK;
    for (int r = 0; r < NEB_STEPS; r++) {
        float3 p = abs(NEB_TILE - glsl_mod(frm + (s * 0.5) * dir, 2.0 * NEB_TILE));
        float pa = 0.0, a = 0.0;
        for (int i = 0; i < NEB_ITER; i++) {
            p = abs(p) / dot(p, p) - NEB_FORMU;
            float l = length(p);         // The original computes the same length twice for a and pa.
            a += abs(l - pa);
            pa = l;
        }
        a *= NEB_ANORM;
        if (!(a > 0.0)) a = 0.0;         // Guard against NaN and negative values; NaN comparisons are false.
        a = min(a, NEB_A_MAX);

        float dm = max(0.0, NEB_DARKMAT - a * a * 0.001);   // Original dark-matter term.
        // Black level: subtract a constant from a cubed and clamp low values to zero.
        float e = max(a * a * a - blk3, 0.0);
        if (r > 6) fade *= 1.0 - dm;
        // Distance-based color: nearby red and distant blue, using the original (s, s squared, s to the fourth) curve.
        v += float3(fade * NEB_HAZE) + float3(s, s * s, s * s * s * s) * (e * NEB_BRIGHT * fade);
        fade *= NEB_DISTFADE;
        s += NEB_STEP0;
    }

    v = lerp(float3(length(v)), v, NEB_SAT);
    // Exponential compression prevents solid white highlights.
    float3 col = NEB_PEAK * (1.0 - exp(-v * NEB_SCALE / NEB_PEAK));
    return float4(lerp(color.rgb, col, bg), color.a);
}
