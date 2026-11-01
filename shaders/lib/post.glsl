/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/post.glsl

    Tone mapping, exposure, colour grading and the small screen space lens
    effects used by the final pass.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_POST_GLSL
#define HYPERREAL_POST_GLSL

//==============================================================================
// tone mapping
//==============================================================================

// ACES fitted (Stephen Hill's RRT + ODT fit), the pack default.
const mat3 ACES_INPUT = mat3(
    0.59719, 0.07600, 0.02840,
    0.35458, 0.90834, 0.13383,
    0.04823, 0.01566, 0.83777
);
const mat3 ACES_OUTPUT = mat3(
     1.60475, -0.10208, -0.00327,
    -0.53108,  1.10813, -0.07276,
    -0.07367, -0.00605,  1.07602
);

vec3 rrtOdtFit(vec3 v) {
    vec3 a = v * (v + 0.0245786) - 0.000090537;
    vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return a / b;
}

vec3 tonemapACES(vec3 color) {
    color = ACES_INPUT * color;
    color = rrtOdtFit(color);
    color = ACES_OUTPUT * color;
    return saturate(color);
}

vec3 tonemapReinhard(vec3 color) {
    const float whitepoint = 4.0;
    vec3 numerator = color * (1.0 + color / (whitepoint * whitepoint));
    return saturate(numerator / (1.0 + color));
}

// Uchimura / Gran Turismo style curve.
vec3 tonemapUchimura(vec3 color) {
    const float P = 1.0;
    const float a = 1.0;
    const float m = 0.22;
    const float l = 0.4;
    const float c = 1.33;
    const float b = 0.0;

    vec3 result;
    for (int i = 0; i < 3; i++) {
        float x = max(color[i], 0.0);
        float l0 = ((P - m) * l) / a;
        float S0 = m + l0;
        float S1 = m + a * l0;
        float C2 = (a * P) / (P - S1);
        float CP = -C2 / P;

        float w0 = 1.0 - smoothstep(0.0, m, x);
        float w2 = step(m + l0, x);
        float w1 = 1.0 - w0 - w2;

        float T = m * pow(x / m, c) + b;
        float L = m + a * (x - m);
        float S = P - (P - S1) * exp(CP * (x - S0));

        result[i] = T * w0 + L * w1 + S * w2;
    }
    return saturate(result);
}

vec3 applyTonemap(vec3 color) {
#if TONEMAP_MODE == 0
    return tonemapReinhard(color);
#elif TONEMAP_MODE == 2
    return tonemapUchimura(color);
#else
    return tonemapACES(color);
#endif
}

//==============================================================================
// colour grading
//==============================================================================

vec3 saturateColor(vec3 color, float amount) {
    float l = luma(color);
    return mix(vec3(l), color, amount);
}

// Lift / gamma / gain style contrast around a pivot.
vec3 contrastAround(vec3 color, float amount, float pivot) {
    return (color - pivot) * amount + pivot;
}

vec3 applyColorGrade(vec3 color, float saturation, float contrast) {
    // Split toning: cool the shadows, warm the highlights (cinematic look).
#if COLOR_GRADE == 1
    float l = luma(color);
    vec3 shadowsTint = vec3(0.94, 1.00, 1.10);
    vec3 highlightsTint = vec3(1.06, 1.01, 0.94);
    color *= mix(shadowsTint, highlightsTint, smoothstep(0.08, 0.75, l));
    color = contrastAround(color, contrast, 0.45);
    color = saturateColor(color, saturation);
    // Slight filmic S-curve.
    color = mix(color, color * color * (3.0 - 2.0 * color), 0.18);
#elif COLOR_GRADE == 2
    color *= vec3(1.06, 1.005, 0.94);
    color = contrastAround(color, contrast, 0.45);
    color = saturateColor(color, saturation);
#elif COLOR_GRADE == 3
    color *= vec3(0.96, 1.0, 1.08);
    color = contrastAround(color, contrast, 0.45);
    color = saturateColor(color, saturation);
#else
    color = contrastAround(color, contrast, 0.45);
    color = saturateColor(color, saturation);
#endif
    return saturate(color);
}

//==============================================================================
// lens effects
//==============================================================================

float vignette(vec2 uv, float strength) {
    vec2 centered = uv - 0.5;
    float r2 = dot(centered, centered);
    return smoothstep(0.95, 0.18, r2 * (0.85 + strength * 0.85));
}

vec3 chromaticAberration(sampler2D tex, vec2 uv, float amount) {
    vec2 centered = uv - 0.5;
    vec2 offset = centered * amount * 0.0035;
    vec3 color;
    color.r = texture(tex, clamp(uv + offset, vec2(0.0), vec2(1.0))).r;
    color.g = texture(tex, uv).g;
    color.b = texture(tex, clamp(uv - offset, vec2(0.0), vec2(1.0))).b;
    return color;
}

// Unsharp mask / contrast adaptive sharpening hybrid.
vec3 sharpen(sampler2D tex, vec2 uv, vec3 center, float amount) {
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
    vec3 north = texture(tex, uv + vec2(0.0, texel.y)).rgb;
    vec3 south = texture(tex, uv - vec2(0.0, texel.y)).rgb;
    vec3 east  = texture(tex, uv + vec2(texel.x, 0.0)).rgb;
    vec3 west  = texture(tex, uv - vec2(texel.x, 0.0)).rgb;
    vec3 blur = (north + south + east + west) * 0.25;
    vec3 detail = center - blur;
    // Limit the amount of sharpening in very bright areas to avoid halos.
    float limit = 1.0 / (1.0 + luma(center) * 0.35);
    return max(center + detail * amount * limit, vec3(0.0));
}

//==============================================================================
// film grain and dither
//==============================================================================

float filmGrain(vec2 uv, float time) {
    float n = hash12(uv * vec2(viewWidth, viewHeight) + frameCounter * 37.0);
    return n - 0.5;
}

float ditherNoise(vec2 pixel) {
    // 2x2 ordered dither, enough to remove banding in the dark gradient.
    float d = bayer4(pixel);
    return (d - 0.5) / 255.0;
}

#endif // HYPERREAL_POST_GLSL
