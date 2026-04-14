#include <CoreImage/CoreImage.h>
using namespace coreimage;
typedef coreimage::sampler ci_sampler;

#define PI 3.1415926535897932384626433832795
#define TAU 6.28318530717958647692

// --- Helpers ---

float glsl_mod(float x, float y) { return x - y * floor(x / y); }
float2 glsl_mod(float2 x, float y) { return x - y * floor(x / y); }

float2 rotate2d(float2 v, float rad) {
    float s = sin(rad), c = cos(rad);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float hash(float2 uv) {
    return fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453123);
}

float white_noise_f(float x) { return fract(sin(x * 12.9898) * 43758.5453); }
float3 white_noise_v3(float3 x) { return fract(sin(x * float3(12.9898, 78.233, 45.164)) * 43758.5453); }

float voronoi_noise(float2 uv) {
    float2 idx = floor(uv);
    float2 fra = fract(uv);
    float md = 1.0;
    for (int y = -1; y <= 1; y++)
        for (int x = -1; x <= 1; x++) {
            float2 nb = float2(float(x), float(y));
            float r = hash(idx + nb);
            float2 diff = nb + float2(r, r) - fra;
            md = min(md, length(diff));
        }
    return md;
}

float3 palette(float3 a, float3 b, float3 c, float3 d, float t) {
    return a + b * cos(TAU * (c * t + d));
}

float map_range(float v, float min1, float max1, float min2, float max2) {
    return min2 + (v - min1) * (max2 - min2) / (max1 - min1);
}

float stay01(float t, float period, float offset, float power) {
    if (period <= 0.0) return 0.0;
    float wave = sin((t + offset) / period * TAU);
    float s = sign(wave);
    return map_range(s - s * pow(1.0 - abs(wave), power), -1.0, 1.0, 0.0, 1.0);
}

float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = mix(float4(c.b, c.g, K.w, K.z), float4(c.g, c.b, K.x, K.y), step(c.b, c.g));
    float4 q = mix(float4(p.x, p.y, p.w, c.r), float4(c.r, p.y, p.z, p.x), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float circle_sdf(float2 uv, float2 center, float size) {
    return length(uv - center) - size;
}

float rect_sdf(float2 uv, float2 center, float2 size) {
    float2 d = abs(uv - center) - size;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float3 vid(ci_sampler src, float2 uv, float w, float h) {
    uv = fract(uv);
    return src.sample(src.transform(uv * float2(w, h))).rgb;
}

// --- Combo kernels ---

// 1. The Bit: bulge(strength=0.76,radius=0.78) → random_bands(bands=4,offset=5.49)
extern "C" float4 combo_the_bit(ci_sampler src, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    float2 center = float2(0.5, 0.5);
    float2 delta = uv - center;
    float dist = length(delta);
    float edge_dist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float edge_factor = smoothstep(0.0, 0.3, edge_dist);
    uv = center + delta * (1.0 - 0.76 * edge_factor * smoothstep(0.78, 0.0, dist));

    float3 color = vid(src, uv, w, h);

    float luma = dot(color, float3(0.299, 0.587, 0.114));
    float band = floor(luma * 4.0) / 4.0;
    float3 bc = palette(
        white_noise_v3(float3(5.49)),
        white_noise_v3(float3(5.49, -4.49, -4.49)),
        white_noise_v3(float3(-4.49, -4.49, 5.49)),
        white_noise_v3(float3(-4.49, -4.49, -4.49)),
        band);
    color = bc;

    return float4(color, 1.0);
}

// 2. It Can Feel That Way: silhouette(thresh=0.5,bw=0) → outline(thresh=0.1,size=0.02) → hsv(hue=0.2)
extern "C" float4 combo_it_can_feel_that_way(ci_sampler src, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);
    float3 color = vid(src, uv, w, h);

    color = float3(float(color.r < 0.5), float(color.g < 0.5), float(color.b < 0.5));

    float d = 0.002;
    float3 c1 = vid(src, uv + float2(d, 0), w, h);
    float3 c2 = vid(src, uv - float2(d, 0), w, h);
    float3 c3 = vid(src, uv + float2(0, d), w, h);
    float3 c4 = vid(src, uv - float2(0, d), w, h);
    float edge = length(c1 - c2) + length(c3 - c4);
    color = (edge > 0.1 ? 0.0 : 1.0) * color;

    float3 hsv = rgb2hsv(color);
    hsv.x = clamp(hsv.x + 0.2, 0.0, 1.0);
    color = hsv2rgb(hsv);

    return float4(color, 1.0);
}

// 3. Puppet Show: kaleidoscope(3) → chromatic_aberration(0.02,speed=0.01) → silhouette(0.5,bw=1)
extern "C" float4 combo_puppet_show(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    float2 centered = uv - 0.5;
    float angle = atan2(centered.y, centered.x);
    float radius = length(centered);
    angle = glsl_mod(angle, TAU / 3.0);
    angle = abs(angle - PI / 3.0);
    uv = float2(cos(angle), sin(angle)) * radius + 0.5;

    float2 up = float2(0.0, -0.02);
    float3 color = float3(
        vid(src, uv + rotate2d(up, TAU * (time * 0.01 + 0.0/3.0)), w, h).r,
        vid(src, uv + rotate2d(up, TAU * (time * 0.01 + 1.0/3.0)), w, h).g,
        vid(src, uv + rotate2d(up, TAU * (time * 0.01 + 2.0/3.0)), w, h).b);

    float val = (color.r + color.g + color.b) / 3.0;
    color = float3(float(val < 0.5));

    return float4(color, 1.0);
}

// 4. Color Wheel: chromatic_aberration(0.02,speed=0.3) → hsv(hue=-0.35,sat=1.0,val=0.7) → color_cycle(speed=0.1,mix=0.7)
extern "C" float4 combo_color_wheel(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    float2 up = float2(0.0, -0.02);
    float3 color = float3(
        vid(src, uv + rotate2d(up, TAU * (time * 0.3 + 0.0/3.0)), w, h).r,
        vid(src, uv + rotate2d(up, TAU * (time * 0.3 + 1.0/3.0)), w, h).g,
        vid(src, uv + rotate2d(up, TAU * (time * 0.3 + 2.0/3.0)), w, h).b);

    float3 hsv = rgb2hsv(color);
    hsv.x = clamp(hsv.x + -0.35, 0.0, 1.0);
    hsv.y = clamp(hsv.y + 1.0, 0.0, 1.0);
    hsv.z = clamp(hsv.z + 0.7, 0.0, 1.0);
    color = hsv2rgb(hsv);

    float luma = dot(color, float3(0.299, 0.587, 0.114));
    float3 cycled = palette(float3(0.5), float3(0.5), float3(1.0),
        float3(0.0, 0.33, 0.67), luma + time * 0.1);
    color = mix(color, cycled, 0.7);

    return float4(color, 1.0);
}

// 5. Gnome: zoom(h=5.21,v=2.81,period=0) → sharpen(strength=1.4,radius=0.25) → color_cycle(speed=0.2,mix=0.29)
extern "C" float4 combo_gnome(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    float mult = stay01(time, 0.0, 0.0, 6.0);
    uv -= 0.5;
    uv /= mix(float2(5.21, 2.81), float2(1.0), mult);
    uv += 0.5;

    float3 color = vid(src, uv, w, h);

    float delta = pow(0.25, 3.0);
    float3 blur = (
        vid(src, uv + float2(-delta, 0), w, h) +
        vid(src, uv + float2(delta, 0), w, h) +
        vid(src, uv + float2(0, -delta), w, h) +
        vid(src, uv + float2(0, delta), w, h)) / 4.0;
    color = color + (color - blur) * pow(1.4, 5.0);

    float luma = dot(color, float3(0.299, 0.587, 0.114));
    float3 cycled = palette(float3(0.5), float3(0.5), float3(1.0),
        float3(0.0, 0.33, 0.67), luma + time * 0.2);
    color = mix(color, cycled, 0.29);

    return float4(color, 1.0);
}

// 6. Us: bulge(x=0.5,y=0.5,strength=-0.97,radius=0.91) → slide(h=0.2,v=0) → boxes(5,5)
extern "C" float4 combo_us(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    float2 center = float2(0.5, 0.5);
    float2 delta = uv - center;
    float dist = length(delta);
    float edge_dist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float edge_factor = smoothstep(0.0, 0.3, edge_dist);
    uv = center + delta * (1.0 - (-0.97) * edge_factor * smoothstep(0.91, 0.0, dist));

    uv += float2(0.2, 0.0) * time;

    uv *= float2(5.0, 5.0);

    float3 color = vid(src, uv, w, h);
    return float4(color, 1.0);
}

// 7. The Matrix: fake_blur(amount=0.7,samples=7) → metal(speed=0.08,amount=1.0) → tint(r=0,g=1,b=0)
extern "C" float4 combo_the_matrix(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    float2 up = float2(0.0, 0.7 / 50.0);
    float3 sum = vid(src, uv, w, h);
    for (float s = 0.0; s < 6.0; s += 1.0)
        sum += vid(src, uv - rotate2d(up, s / 7.0 * TAU), w, h);
    float3 color = sum / 7.0;

    float dt = time * 0.08;
    float3 p1 = vid(src, float2(color.x, color.y) + dt, w, h);
    float3 p2 = vid(src, float2(color.y, color.z) + dt, w, h);
    float3 p3 = vid(src, float2(color.x, color.z) + dt, w, h);
    color = min(p3, min(p1, p2));

    float luma = dot(color, float3(0.299, 0.587, 0.114));
    float3 sepia = float3(luma) * float3(0.0, 1.0, 0.0) * 2.0;
    color = sepia;

    return float4(color, 1.0);
}

// 8. Water Color: noise_voronoi(sx=5.67,sy=5.63,amt=0.01) → noise_white(amt=0.01) → chromatic(0.02,speed=0.1) → hsv(sat=-0.2,val=0.8)
extern "C" float4 combo_water_color(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    uv += voronoi_noise((uv - 0.5) * pow(float2(2.0), float2(5.67, 5.63))) * 0.01;

    float2 wn_scaled = (uv - 0.5) * pow(float2(2.0), float2(5.0, 5.0));
    float2 wn = fract(sin(wn_scaled * float2(12.9898, 78.233)) * 43758.5453);
    uv += float2(wn.x, wn.y) * 0.01;

    float2 up = float2(0.0, -0.02);
    float3 color = float3(
        vid(src, uv + rotate2d(up, TAU * (time * 0.1 + 0.0/3.0)), w, h).r,
        vid(src, uv + rotate2d(up, TAU * (time * 0.1 + 1.0/3.0)), w, h).g,
        vid(src, uv + rotate2d(up, TAU * (time * 0.1 + 2.0/3.0)), w, h).b);

    float3 hsv = rgb2hsv(color);
    hsv.y = clamp(hsv.y + -0.2, 0.0, 1.0);
    hsv.z = clamp(hsv.z + 0.8, 0.0, 1.0);
    color = hsv2rgb(hsv);

    return float4(color, 1.0);
}

// 9. Who Is That?: random_bands(bands=6,offset=3.56) → circle(thickness=0.15,speed=0.05,shape=1) → rotate(degrees=1,moving=1)
extern "C" float4 combo_who_is_that(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    float dist = circle_sdf(uv, float2(0.5), 0.15);
    float radius = glsl_mod(time * 0.05 + dist, 0.15 * 2.0);
    uv = radius < 0.15 ? float2(uv.x, 1.0 - uv.y) : uv;

    float theta = 1.0 * PI / 180.0;
    uv = rotate2d(uv - 0.5, theta * time * TAU) + 0.5;

    float3 color = vid(src, uv, w, h);

    float luma = dot(color, float3(0.299, 0.587, 0.114));
    float band = floor(luma * 6.0) / 6.0;
    float3 bc = palette(
        white_noise_v3(float3(3.56)),
        white_noise_v3(float3(3.56, 1.0 - 3.56, 1.0 - 3.56)),
        white_noise_v3(float3(1.0 - 3.56, 1.0 - 3.56, 3.56)),
        white_noise_v3(float3(1.0 - 3.56, 1.0 - 3.56, 1.0 - 3.56)),
        band);
    color = bc;

    return float4(color, 1.0);
}

// 10. Dizzy: camera_shake(amount=0.02,speed=1) → zoom(h=1.01,v=1.0,period=0.4) → fake_blur(amount=0.4,samples=7)
extern "C" float4 combo_dizzy(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    float2 noise = float2(sin(time * 3.283), cos(time * 2.320)) * 0.02;
    uv *= (1.0 - 0.02);
    uv += noise;

    float mult = stay01(time, 0.4, 0.0, 6.0);
    uv -= 0.5;
    uv /= mix(float2(1.01, 1.0), float2(1.0), mult);
    uv += 0.5;

    float2 up = float2(0.0, 0.4 / 50.0);
    float3 sum = vid(src, uv, w, h);
    for (float s = 0.0; s < 6.0; s += 1.0)
        sum += vid(src, uv - rotate2d(up, s / 7.0 * TAU), w, h);
    float3 color = sum / 7.0;

    return float4(color, 1.0);
}

// 11. Potion Seller: bulge(radius=0.82,y=0.7,x=0.66) → bulge(strength=-1,radius=0.54,y=0.28)
extern "C" float4 combo_potion_seller(ci_sampler src, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    // Bulge 1: x=0.66,y=0.7,strength=0.5(default),radius=0.82
    {
        float2 center = float2(1.0 - 0.66, 0.7);
        float2 delta = uv - center;
        float dist = length(delta);
        float ed = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
        float ef = smoothstep(0.0, 0.3, ed);
        uv = center + delta * (1.0 - 0.5 * ef * smoothstep(0.82, 0.0, dist));
    }
    // Bulge 2: x=0.5(default),y=0.28,strength=-1,radius=0.54
    {
        float2 center = float2(0.5, 0.28);
        float2 delta = uv - center;
        float dist = length(delta);
        float ed = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
        float ef = smoothstep(0.0, 0.3, ed);
        uv = center + delta * (1.0 - (-1.0) * ef * smoothstep(0.54, 0.0, dist));
    }

    float3 color = vid(src, uv, w, h);
    return float4(color, 1.0);
}

// 12. Another World: pixelize(h=0.13,v=0.13) → [chromatic_aberration default] → silhouette(0.5,bw=0) → color_cycle(speed=0.08,mix=0.5)
extern "C" float4 combo_another_world(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    uv = floor(uv / float2(0.013, 0.013)) * float2(0.013, 0.013);

    float2 up = float2(0.0, -0.02);
    float3 color = float3(
        vid(src, uv + rotate2d(up, TAU * (time * 0.01 + 0.0/3.0)), w, h).r,
        vid(src, uv + rotate2d(up, TAU * (time * 0.01 + 1.0/3.0)), w, h).g,
        vid(src, uv + rotate2d(up, TAU * (time * 0.01 + 2.0/3.0)), w, h).b);

    color = float3(float(color.r < 0.5), float(color.g < 0.5), float(color.b < 0.5));

    float luma = dot(color, float3(0.299, 0.587, 0.114));
    float3 cycled = palette(float3(0.5), float3(0.5), float3(1.0),
        float3(0.0, 0.33, 0.67), luma + time * 0.08);
    color = mix(color, cycled, 0.5);

    return float4(color, 1.0);
}

// 13. Compression: mirage(period=0.11,size=0.13) → posturize(bands=6.2) → sharpen(strength=1.9,radius=0.23)
extern "C" float4 combo_compression(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    float qt = floor(time / 0.11) * 0.11;
    float sz = pow(2.0, -1.0 / 0.13);
    float2 rounded = floor(uv / sz) * sz;
    uv = uv + hash(rounded + qt) * 0.02;

    float3 color = vid(src, uv, w, h);

    color = floor(color * 6.2) / (6.2 - 1.0);

    float delta = pow(0.23, 3.0);
    float3 blur = (
        vid(src, uv + float2(-delta, 0), w, h) +
        vid(src, uv + float2(delta, 0), w, h) +
        vid(src, uv + float2(0, -delta), w, h) +
        vid(src, uv + float2(0, delta), w, h)) / 4.0;
    color = color + (color - blur) * pow(1.9, 5.0);

    return float4(color, 1.0);
}

// 14. Mandala: color_cycle(speed=0.08) → random_bands(bands=9,offset=3.79) → kaleidoscope(6)
extern "C" float4 combo_mandala(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    float2 centered = uv - 0.5;
    float angle = atan2(centered.y, centered.x);
    float radius = length(centered);
    angle = glsl_mod(angle, TAU / 6.0);
    angle = abs(angle - PI / 6.0);
    uv = float2(cos(angle), sin(angle)) * radius + 0.5;

    float3 color = vid(src, uv, w, h);

    float luma = dot(color, float3(0.299, 0.587, 0.114));
    float3 cycled = palette(float3(0.5), float3(0.5), float3(1.0),
        float3(0.0, 0.33, 0.67), luma + time * 0.08);
    color = mix(color, cycled, 0.7);

    luma = dot(color, float3(0.299, 0.587, 0.114));
    float band = floor(luma * 9.0) / 9.0;
    float3 bc = palette(
        white_noise_v3(float3(3.79)),
        white_noise_v3(float3(3.79, 1.0 - 3.79, 1.0 - 3.79)),
        white_noise_v3(float3(1.0 - 3.79, 1.0 - 3.79, 3.79)),
        white_noise_v3(float3(1.0 - 3.79, 1.0 - 3.79, 1.0 - 3.79)),
        band);
    color = bc;

    return float4(color, 1.0);
}

// 15. Mirror World: pixelize(h=0.02,v=0.27) → kaleidoscope(1) → sharpen(strength=-1.8,radius=0.14)
extern "C" float4 combo_mirror_world(ci_sampler src, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    uv = floor(uv / float2(0.002, 0.027)) * float2(0.002, 0.027);

    float2 centered = uv - 0.5;
    float angle = atan2(centered.y, centered.x);
    float radius = length(centered);
    angle = glsl_mod(angle, TAU / 1.0);
    angle = abs(angle - PI / 1.0);
    uv = float2(cos(angle), sin(angle)) * radius + 0.5;

    float3 color = vid(src, uv, w, h);

    float delta = pow(0.14, 3.0);
    float3 blur = (
        vid(src, uv + float2(-delta, 0), w, h) +
        vid(src, uv + float2(delta, 0), w, h) +
        vid(src, uv + float2(0, -delta), w, h) +
        vid(src, uv + float2(0, delta), w, h)) / 4.0;
    color = color + (color - blur) * pow(-1.8, 5.0);

    return float4(color, 1.0);
}

// 16. Knights: kaleidoscope(8) → slide(v=0.3,h=0)
extern "C" float4 combo_knights(ci_sampler src, float time, float w, float h, destination dest) {
    float2 uv = dest.coord() / float2(w, h);

    float2 centered = uv - 0.5;
    float angle = atan2(centered.y, centered.x);
    float radius = length(centered);
    angle = glsl_mod(angle, TAU / 8.0);
    angle = abs(angle - PI / 8.0);
    uv = float2(cos(angle), sin(angle)) * radius + 0.5;

    uv += float2(0.0, 0.3) * time;

    float3 color = vid(src, uv, w, h);
    return float4(color, 1.0);
}

// 17. Dither: cycles through 7 patterns (750ms each). "On" pixels keep source color.

constant float dither_bayer2[4] = { 0, 2, 3, 1 };

constant float dither_bayer4[16] = {
     0,  8,  2, 10,
    12,  4, 14,  6,
     3, 11,  1,  9,
    15,  7, 13,  5
};

constant float dither_bayer8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
};

// Hilbert curve index for a 16x16 tile — GPU stand-in for Riemersma ordering.
int hilbert_d_16(int2 p) {
    int x = p.x, y = p.y, d = 0;
    for (int s = 8; s > 0; s /= 2) {
        int rx = (x / s) & 1;
        int ry = (y / s) & 1;
        d += s * s * ((3 * rx) ^ ry);
        if (ry == 0) {
            if (rx == 1) { x = 15 - x; y = 15 - y; }
            int t = x; x = y; y = t;
        }
    }
    return d;
}

extern "C" float4 combo_dither(ci_sampler src, float time, float w, float h, destination dest) {
    float2 coord = dest.coord();
    float2 uv = coord / float2(w, h);

    float3 color = vid(src, uv, w, h);
    float luma = dot(color, float3(0.299, 0.587, 0.114));
    luma = pow(luma, 1.0 / 1.8);

    int pattern = int(floor(time)) % 7;
    if (pattern < 0) pattern += 7;
    // Scale each dither cell up by 4x so the pattern survives print resampling.
    int2 pos = int2(floor(coord / 4.0));

    float threshold = 0.5;
    if (pattern == 0) {
        threshold = (dither_bayer2[(pos.y % 2) * 2 + (pos.x % 2)] + 0.5) / 4.0;
    } else if (pattern == 1) {
        threshold = (dither_bayer4[(pos.y % 4) * 4 + (pos.x % 4)] + 0.5) / 16.0;
    } else if (pattern == 2) {
        threshold = (dither_bayer8[(pos.y % 8) * 8 + (pos.x % 8)] + 0.5) / 64.0;
    } else if (pattern == 3) {
        threshold = hash(float2(pos));
    } else if (pattern == 4) {
        float2 cell = fract(float2(pos) / 6.0) - 0.5;
        threshold = clamp(1.0 - length(cell) * 2.0, 0.0, 1.0);
    } else if (pattern == 5) {
        threshold = (float(pos.y % 4) + 0.5) / 4.0;
    } else {
        int2 tile = int2(pos.x % 16, pos.y % 16);
        threshold = (float(hilbert_d_16(tile)) + 0.5) / 256.0;
    }

    float v = luma > threshold ? 1.0 : 0.0;
    return float4(v, v, v, 1.0);
}

// --- Print preview: grayscale → gamma → Bayer ordered dither ---

constant float bayer8x8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
};

extern "C" float4 print_preview(sample_t s, destination dest) {
    float luma = dot(s.rgb, float3(0.299, 0.587, 0.114));
    luma = pow(luma, 1.0 / 1.8);
    int2 pos = int2(dest.coord());
    float threshold = (bayer8x8[(pos.y % 8) * 8 + (pos.x % 8)] + 0.5) / 64.0;
    float v = luma > threshold ? 1.0 : 0.0;
    return float4(v, v, v, 1.0);
}
