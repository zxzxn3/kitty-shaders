#language slang 2026
// cloud-bg —— 体积云背景。移植自 nimitz 的 "Protean clouds"
//   https://www.shadertoy.com/view/3l23Rh
//   作者 nimitz（twitter: @stormoid）；Onan 加过 timeScaling
//   许可 CC BY-NC-SA 3.0：署名、非商业、相同方式共享
//
// 全程序化单趟 raymarcher：每次 map() 里有 5 轮三角函数形变，整屏最多 130 次步进，
// 命中时还要为光照再加两次 map()。所以它比 bg-drift 重两三个数量级。
//
// 和 bg-drift 一样只画背景像素（跟 d.background 比颜色），字浮在云上。
// ⚠ bg-drift 和 cloud-bg 只能开一个：两者都靠「和背景色比较」来认背景，
//   先跑的那个会把背景染色，后跑的那个就认不出了。
//
// 顺序：必须在 ink-stroke 之后（否则墨痕认不出背景）、在两个 fade 之前
// （否则失焦窗口的云不会被去饱和）。
//
// 移植时三个容易出错的地方（都按原版语义处理了）：
//   1. GLSL 矩阵是列主序，Slang 是行主序 —— rot 和 M3 都显式转成了行主序写法
//   2. GLSL 的 p*m3 与 p.xy*=rot(a) 都是「矩阵左乘向量」，Slang 里必须显式 mul(M,v)
//   3. 原版用可变的全局变量 prm1 / bsMo 在 mainImage 里算、在 map() 里读，
//      这里改成参数传入，避免依赖全局可变状态

import kitty_custom_shader_types;

// ── 实现细节（一般不用动）──
static const float BG_TOLERANCE = 0.02;
// 原版的形变迭代次数。改了就换了另一张云，不建议动。
static const int MAP_ITER = 5;

// ── 可调参数（会被 cloud-bg.pipeline 里的 var 覆盖）──
static const int CLOUD_STEPS = 48;          // 步进数：48 省电档，原版 130 最饱满
static const float CLOUD_TIME_SCALE = 0.2;  // 原版的 timeScaling，越大云漂得越快
// 云的整体亮度乘数。实测（CPU 复算，320x180，四个时刻）：
//   1.00 → 平均亮度 0.45、峰值 0.96，白字基本没法读
//   0.12 → 平均 0.045、峰值 0.11，是很淡的一层，白字仍然清晰
static const float CLOUD_STRENGTH = 0.12;
static const float CLOUD_MIX = 1.0;         // 背景像素被云替换的程度
static const bool CLOUD_MOUSE = false;      // 鼠标是否控制视角

// 原版：const mat3 m3 = mat3(0.33338, 0.56034, -0.71817, -0.87887, 0.32651,
//                            -0.15323, 0.15162, 0.69596, 0.61339) * 1.93
// GLSL 按列填充，这里按行写出等价的数学矩阵。
static const float3x3 M3 = float3x3(
     0.33338, -0.87887,  0.15162,
     0.56034,  0.32651,  0.69596,
    -0.71817, -0.15323,  0.61339) * 1.93;

// 原版：mat2 rot(float a){ return mat2(c, s, -s, c); } —— 列主序，等价于
// [[c, -s], [s, c]]。Slang 按行填充，所以写 (c, -s, s, c)，并用 mul 左乘。
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

// 原版 map()。time 参数就是原版的 iTime*timeScaling（调用方已经乘好）。
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
    for (int i = 0; i < MAP_ITER; i++) {
        p += sin(p.zxy * 0.75 * trk + time * trk * 0.8) * dspAmp;
        d -= abs(dot(cos(p), sin(p.yzx)) * z);
        z *= 0.57;
        trk *= 1.4;
        p = mul(M3, p);
    }
    d = abs(d + prm1 * 3.0) + prm1 * 0.3 - 2.5 + bsMo.y;
    return float2(d + cl * 0.2 + 0.25, cl);
}

// 原版 render()。原版里那个 lpos 变量没被用到，略去了。
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
            dif += clamp((den - cloud_map(pos + 0.35, time, prm1, bsMo).x) / 2.5, 0.001, 1.0);
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

// 原版作者自己另一个 shader 里的插值，用来让颜色过渡不经过灰色。
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
    // 只画背景像素，字不碰。
    float3 diff = abs(color.rgb - d.background.rgb);
    float bg = 1.0 - smoothstep(0.0, BG_TOLERANCE, max(max(diff.r, diff.g), diff.b));
    if (bg <= 0.0) return color;

    float2 res = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));
    float2 fragCoord = t.pos * res;
    float2 q = fragCoord / res;
    float2 p = (fragCoord - 0.5 * res) / res.y;

    // 原版的 iMouse.xy 是像素坐标。默认不用鼠标（背景跟着鼠标晃太活跃）。
    float2 bsMo = CLOUD_MOUSE ? (d.mouse_pos.xy * res - 0.5 * res) / res.y : float2(0.0);

    float time = d.timestamp * CLOUD_TIME_SCALE * 3.0;
    float3 ro = float3(0.0, 0.0, time);
    // 原版这里还有一项 sin(iTime*timeScaling*1.)*0. —— 乘 0，等于没有，略去。
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
    col *= pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.12) * 0.7 + 0.3;  // 暗角

    // 把云铺到背景上。CLOUD_STRENGTH 压亮度是为了保住文字对比度；
    // 想更接近 Shadertoy 原图就调到 1.0，但白字会不好读。
    return float4(lerp(color.rgb, col * CLOUD_STRENGTH, bg * CLOUD_MIX), color.a);
}
