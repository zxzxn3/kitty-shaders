#language slang 2026
// Author: zxzx.
// Focus-triggered edge pulse; the first frame after reload also triggers it. See the pipeline for parameters.

import kitty_custom_shader_types;

// The following three defaults are overridden by group variables in focus-pulse.pipeline.
static const float PULSE_PEAK = 0.05;      // Peak additive linear brightness.
static const float PULSE_BAND_PX = 48.0;   // Inward falloff distance in pixels.
static const float PULSE_ATTACK = 0.12;    // Attack fraction of the animation duration.

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 area = d.central_area;
    if (area.z <= 0.0 || area.w <= 0.0) return color;

    // Distances to the four content edges; convert each axis to pixels to preserve band width.
    float2 dd = min(t.pos - area.xy, area.xy + area.zw - t.pos) * float2(d.viewport_size_pixels);
    float dmin = min(dd.x, dd.y);
    if (dmin <= 0.0) return color;   // Do not affect pixels outside the content area, including the tab bar.

    float band = 1.0 - smoothstep(0.0, PULSE_BAND_PX, dmin);
    if (band <= 0.0) return color;

    // Apply an attack/release envelope to the pipeline's linear progress.
    float p = clamp(t.animation_progress, 0.0, 1.0);
    float env = (1.0 - p) * smoothstep(0.0, PULSE_ATTACK, p);
    if (env <= 0.0) return color;

    return float4(color.rgb + float3(band * env * PULSE_PEAK), color.a);
}
