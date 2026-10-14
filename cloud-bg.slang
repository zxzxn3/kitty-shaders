#language slang 2026
// Slang port and Kitty adaptation by zxzx; cloud algorithm by nimitz (@stormoid).
// Source: Protean Clouds, https://www.shadertoy.com/view/3l23Rh (CC BY-NC-SA 3.0).
// This adaptation is also distributed under CC BY-NC-SA 3.0; see LICENSES/CC-BY-NC-SA-3.0.txt.
// Preserve the deformation, volume integration and color interpolation algorithms.
// Port GLSL matrices to row-major mul(); pass mutable globals as function parameters.
// Reduce marching steps 130 -> 48, deformation iterations 5 -> 4, light taps 2 -> 1.
// Compute every fourth row into texture a; cloud-bg-apply interpolates and masks the background.
// Expose timing, sampling and brightness controls through the Kitty pipeline.

import kitty_custom_shader_types;

// Performance controls, overridden by cloud-bg.pipeline.
static const int CLOUD_ROW_STRIDE = 4;   // Row sampling stride; 1 computes every row.
static const int CLOUD_LIGHT_TAPS = 1;   // Additional lighting samples; original value: 2.
static const int CLOUD_MAP_ITER = 4;     // Deformation iterations per step; original value: 5.
static const int CLOUD_STEPS = 48;       // Marching steps; original value: 130.

// Appearance controls.
static const float CLOUD_TIME_SCALE = 0.2;  // Original timeScaling; higher values increase drift speed.
static const bool CLOUD_MOUSE = false;      // Whether the mouse controls the view.

// Implementation details.
static const float3x3 M3 = float3x3(
     0.33338, -0.87887,  0.15162,
     0.56034,  0.32651,  0.69596,
    -0.71817, -0.15323,  0.61339) * 1.93;

static float2
rot_mul(float a, float2 v) {
    float c = cos(a), s = sin(a);
    return mul(float2x2(c, -s, s, c), v);
}

static float2
disp(float t) { return float2(sin(t * 0.22), cos(t * 0.175)) * 2.0; }

static float
mag2(float2 p) { return dot(p, p); }

static float
linstep(float mn, float mx, float x) { return clamp((x - mn) / (mx - mn), 0.0, 1.0); }

static float2
cloud_map(float3 p, float time, float prm1, float2 bsMo) {
    float3 p2 = p;
    p2.xy -= disp(p.z);
    p.xy = rot_mul(sin(p.z + time) * (0.1 + prm1 * 0.05) + time * 0.09, p.xy);
    float cl = mag2(p2.xy);
    float d = 0.0;
    p *= 0.61;
    float z = 1.0;
    float trk = 1.0;
    float dspAmp = 0.1 + prm1 * 0.2;
    for (int i = 0; i < CLOUD_MAP_ITER; i++) {
        p += sin(p.zxy * 0.75 * trk + time * trk * 0.8) * dspAmp;
        d -= abs(dot(cos(p), sin(p.yzx)) * z);
        z *= 0.57;
        trk *= 1.4;
        p = mul(M3, p);
    }
    d = abs(d + prm1 * 3.0) + prm1 * 0.3 - 2.5 + bsMo.y;
    return float2(d + cl * 0.2 + 0.25, cl);
}

static float4
cloud_render(float3 ro, float3 rd, float time, float prm1, float2 bsMo) {
    float4 rez = float4(0.0);
    float t = 1.5;
    float fogT = 0.0;
    for (int i = 0; i < CLOUD_STEPS; i++) {
        if (rez.a > 0.99) break;

        float3 pos = ro + t * rd;
        float2 mpv = cloud_map(pos, time, prm1, bsMo);
        float den = clamp(mpv.x - 0.3, 0.0, 1.0) * 1.12;
        float dn = clamp(mpv.x + 2.0, 0.0, 3.0);

        float4 col = float4(0.0);
        if (mpv.x > 0.6) {
            col = float4(sin(float3(5.0, 0.4, 0.2) + mpv.y * 0.1 + sin(pos.z * 0.4) * 0.5 + 1.8) * 0.5 + 0.5, 0.08);
            col *= den * den * den;
            col.rgb *= linstep(4.0, -2.5, mpv.x) * 2.3;
            float dif = clamp((den - cloud_map(pos + 0.8, time, prm1, bsMo).x) / 9.0, 0.001, 1.0);
            if (CLOUD_LIGHT_TAPS > 1) {   // The original also samples pos + 0.35.
                dif += clamp((den - cloud_map(pos + 0.35, time, prm1, bsMo).x) / 2.5, 0.001, 1.0);
            }
            col.xyz *= den * (float3(0.005, 0.045, 0.075) + 1.5 * float3(0.033, 0.07, 0.03) * dif);
        }

        float fogC = exp(t * 0.2 - 2.2);
        col += float4(0.06, 0.11, 0.11, 0.1) * clamp(fogC - fogT, 0.0, 1.0);
        fogT = fogC;
        rez = rez + col * (1.0 - rez.a);
        t += clamp(0.5 - dn * dn * 0.05, 0.09, 0.3);
    }
    return clamp(rez, 0.0, 1.0);
}

static float
getsat(float3 c) {
    float mi = min(min(c.x, c.y), c.z);
    float ma = max(max(c.x, c.y), c.z);
    return (ma - mi) / (ma + 1e-7);
}

static float3
iLerp(float3 a, float3 b, float x) {
    float3 ic = lerp(a, b, x) + float3(1e-6, 0.0, 0.0);
    float sd = abs(getsat(ic) - lerp(getsat(a), getsat(b), x));
    float3 dir = normalize(float3(2.0 * ic.x - ic.y - ic.z,
                                  2.0 * ic.y - ic.x - ic.z,
                                  2.0 * ic.z - ic.y - ic.x));
    float lgt = dot(float3(1.0), ic);
    float ff = dot(dir, normalize(ic));
    ic += 1.5 * dir * sd * ff * lgt;
    return clamp(ic, 0.0, 1.0);
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float2 res = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));

    // Skip unsampled rows; the apply pass interpolates only between computed rows.
    float yrow = floor(t.pos.y * res.y);
    // Slang fmod uses truncation; nonnegative row indices also match GLSL modulo.
    if (CLOUD_ROW_STRIDE > 1 && fmod(yrow, float(CLOUD_ROW_STRIDE)) > 0.5) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 fragCoord = t.pos * res;
    float2 q = fragCoord / res;
    float2 p = (fragCoord - 0.5 * res) / res.y;

    float2 bsMo = CLOUD_MOUSE ? (d.mouse_pos.xy * res - 0.5 * res) / res.y : float2(0.0);

    float time = d.timestamp * CLOUD_TIME_SCALE * 3.0;
    float3 ro = float3(0.0, 0.0, time);
    ro += float3(sin(d.timestamp * CLOUD_TIME_SCALE) * 0.5, 0.0, 0.0);

    float dspAmp = 0.85;
    ro.xy += disp(ro.z) * dspAmp;

    float tgtDst = 3.5;
    float3 target = normalize(ro - float3(disp(time + tgtDst) * dspAmp, time + tgtDst));
    ro.x -= bsMo.x * 2.0;
    float3 rightdir = normalize(cross(target, float3(0.0, 1.0, 0.0)));
    float3 updir = normalize(cross(rightdir, target));
    rightdir = normalize(cross(updir, target));
    float3 rd = normalize(p.x * rightdir + p.y * updir - target);
    rd.xy = rot_mul(-disp(time + 3.5).x * 0.2 + bsMo.x, rd.xy);

    float prm1 = smoothstep(-0.4, 0.4, sin(d.timestamp * CLOUD_TIME_SCALE * 0.3));
    float4 scn = cloud_render(ro, rd, time, prm1, bsMo);

    float3 col = scn.rgb;
    col = iLerp(col.bgr, col.rgb, clamp(1.0 - prm1, 0.05, 1.0));
    col = pow(col, float3(0.55, 0.65, 0.6)) * float3(1.0, 0.97, 0.9);
    col *= pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.12) * 0.7 + 0.3;  // Vignette.

    // Compute only; brightness and blending are applied in cloud-bg-apply.
    return float4(col, 1.0);
}
