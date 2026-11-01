/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/util.glsl

    Small, branch free helpers: colour space, hashing, procedural noise,
    depth reconstruction and dithering. Everything here is dependency free
    apart from lib/uniforms.glsl.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_UTIL_GLSL
#define HYPERREAL_UTIL_GLSL

#define PI  3.14159265359
#define TAU 6.28318530718

//==============================================================================
// scalar helpers
//==============================================================================

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2  saturate(vec2 x)  { return clamp(x, vec2(0.0), vec2(1.0)); }
vec3  saturate(vec3 x)  { return clamp(x, vec3(0.0), vec3(1.0)); }
vec4  saturate(vec4 x)  { return clamp(x, vec4(0.0), vec4(1.0)); }

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

float remap(float x, float a, float b, float c, float d) {
    return c + (x - a) * (d - c) / max(b - a, 1e-6);
}

// smooth min / max, handy for soft unions of density fields
float smin(float a, float b, float k) {
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 0.0 -> 1.0 ease
float easeInOut(float x) {
    x = saturate(x);
    return x * x * (3.0 - 2.0 * x);
}

// sRGB <-> linear. Textures are treated as sRGB, all math is linear.
vec3 srgbToLinear(vec3 c) {
    return pow(max(c, vec3(1e-5)), vec3(2.2));
}
vec3 linearToSrgb(vec3 c) {
    return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

//==============================================================================
// hashing / dithering
//==============================================================================

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
    p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// interleaved gradient noise - cheap, temporally stable per pixel
float ign(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

// Blue-noise lookup, tiled over the screen with a golden-ratio offset per
// frame so that dithering never forms a static pattern.
float blueNoise(vec2 uv) {
    vec2 coord = uv * vec2(viewWidth, viewHeight) / float(noiseTextureResolution);
    return texture(noisetex, coord).b;
}

float bayer4(vec2 pixel) {
    const mat4 m = mat4(0.0, 8.0, 2.0, 10.0,
                        12.0, 4.0, 14.0, 6.0,
                        3.0, 11.0, 1.0, 9.0,
                        15.0, 7.0, 13.0, 5.0);
    int x = int(mod(pixel.x, 4.0));
    int y = int(mod(pixel.y, 4.0));
    // GLSL 330 requires constant indices, so unroll the lookup
    float v = 0.0;
    for (int i = 0; i < 16; i++) {
        if (i / 4 == y && i % 4 == x) v = float(i);
    }
    return (v + 0.5) / 16.0;
}

//==============================================================================
// procedural noise
//==============================================================================

float valueNoise2D(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float valueNoise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash13(i);
    float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
    return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
               mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// gradient noise, 2D
float gradNoise2D(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = dot(hash33(vec3(i, 0.0)).xy * 2.0 - 1.0, f);
    float b = dot(hash33(vec3(i + vec2(1.0, 0.0), 0.0)).xy * 2.0 - 1.0, f - vec2(1.0, 0.0));
    float c = dot(hash33(vec3(i + vec2(0.0, 1.0), 0.0)).xy * 2.0 - 1.0, f - vec2(0.0, 1.0));
    float d = dot(hash33(vec3(i + vec2(1.0, 1.0), 0.0)).xy * 2.0 - 1.0, f - vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2D(vec2 p, int octaves) {
    float sum = 0.0;
    float amp = 0.5;
    float norm = 0.0;
    mat2 rot = mat2(0.80, 0.60, -0.60, 0.80);
    for (int i = 0; i < 8; i++) {
        if (i >= octaves) break;
        sum += amp * gradNoise2D(p);
        norm += amp;
        p = rot * p * 2.02 + 13.7;
        amp *= 0.5;
    }
    return sum / max(norm, 1e-5) * 0.5 + 0.5;
}

float fbm3D(vec3 p, int octaves) {
    float sum = 0.0;
    float amp = 0.5;
    float norm = 0.0;
    for (int i = 0; i < 6; i++) {
        if (i >= octaves) break;
        sum += amp * valueNoise3D(p);
        norm += amp;
        p = p * 2.02 + vec3(11.3, 7.1, 3.7);
        amp *= 0.5;
    }
    return sum / max(norm, 1e-5);
}

// cheap 2D worley (cellular) noise, returns F1 and F2
vec2 worley2D(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float f1 = 8.0;
    float f2 = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 g = vec2(float(x), float(y));
            vec2 o = hash33(vec3(i + g, 0.0)).xy;
            float d = length(g + o - f);
            if (d < f1) {
                f2 = f1;
                f1 = d;
            } else if (d < f2) {
                f2 = d;
            }
        }
    }
    return vec2(f1, f2);
}

//==============================================================================
// depth
//==============================================================================

// Minecraft's depth buffer is the standard perspective depth in [0,1].
float linearizeDepth(float depth, float nearPlane, float farPlane) {
    return (nearPlane * farPlane) / (farPlane - depth * (farPlane - nearPlane));
}

float viewZFromDepth(float depth) {
    // Negative view-space Z (OpenGL convention) in blocks.
    vec4 clip = vec4(0.0, 0.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.z / view.w;
}

//==============================================================================
// normals / material encoding helpers
//==============================================================================

vec3 encodeNormal(vec3 n) {
    return normalize(n) * 0.5 + 0.5;
}

vec3 decodeNormal(vec3 n) {
    return normalize(n * 2.0 - 1.0);
}

// material class stored in the alpha channel of colortex1
const float MAT_SKY    = 0.0;
const float MAT_OPAQUE = 1.0;
const float MAT_WATER  = 2.0;
const float MAT_GLASS  = 3.0;
const float MAT_EFFECT = 4.0;   // weather / particles: excluded from screen space effects

float encodeMat(float m) { return m * 0.125; }
float decodeMat(float a) { return floor(a * 8.0 + 0.5); }

// Minecraft lightmap coordinates are (u,v) in [0,1] over a 16x16 atlas with a
// half texel offset. Convert to a 0..1 light level.
float lmLevel(float coord) {
    return saturate((coord * 16.0 - 0.5) / 15.0);
}

float skyLightLevel(vec2 lm) { return lmLevel(lm.y); }
float blockLightLevel(vec2 lm) { return lmLevel(lm.x); }

// Vanilla-like falloff, a little softer in the low end.
float lightCurve(float level) {
    return level * level * (3.0 - 2.0 * level) * 0.96 + 0.04 * level;
}

#endif // HYPERREAL_UTIL_GLSL
