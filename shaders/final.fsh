#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    final.fsh

    The cinematic finish:

      chromatic aberration -> depth of field -> motion blur -> bloom ->
      auto / manual exposure -> tone mapping -> lens flare -> colour grade ->
      vignette -> sharpening -> film grain -> dithering -> sRGB encode

    Everything can be toggled from the shader options; with all of them off
    the pass is a plain filmic tone map with a correct sRGB encode.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/shadows.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/sky.glsl"
#include "/lib/post.glsl"
#include "/lib/composite_common.glsl"

uniform sampler2D colortex7;   // final scene
uniform sampler2D colortex5;   // bloom
uniform sampler2D colortex4;   // bloom bright pass (debug views)

layout(location = 0) out vec4 fragColor;

//==============================================================================
// exposure
//==============================================================================

// Mean luminance of the current frame, sampled on a sparse grid. A spatial
// estimate is used on purpose: it cannot "pump" across frames the way a
// temporal accumulator with a history buffer would, and the sample grid is
// large enough for the value to change smoothly while moving.
float sceneLuminance(vec2 uv) {
    float sum = 0.0;
    float weight = 0.0;
    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            vec2 offset = vec2(float(x), float(y)) * 0.19;
            vec2 suv = clamp(uv + offset, vec2(0.0), vec2(1.0));
            float l = luma(max(texture(colortex7, suv).rgb, vec3(0.0)));
            // centre weighted, log compressed so highlights do not dominate
            float w = exp(-float(x * x + y * y) * 0.10);
            sum += log(1.0 + l * 4.0) * w;
            weight += w;
        }
    }
    return sum / max(weight, 1e-4);
}

float autoExposure(vec2 uv) {
#ifdef AUTO_EXPOSURE
    float avg = sceneLuminance(uv);
    // Aim for a well exposed mid grey (~0.16 linear after tone mapping).
    float target = log(1.0 + 0.55 * 4.0);
    float factor = target / max(avg, 1e-4);
    return clamp(factor, 0.35, 3.2);
#else
    return 1.0;
#endif
}

//==============================================================================
// depth of field
//==============================================================================

vec3 depthOfField(vec2 uv, vec3 color) {
#ifdef DEPTH_OF_FIELD
    float centerDepth = linearDepth(0.5 * (getDepth0(vec2(0.5, 0.5)) + getDepth0(uv)));
    if (centerDepth <= 0.0 || centerDepth > 250.0) centerDepth = 24.0;
    float focusDistance = clamp(centerDepth * (0.35 + DOF_FOCUS * 1.3), 0.6, 200.0);

    float depth = linearDepth(getDepth0(uv));
    if (depth >= 1000.0) return color;

    // Circle of confusion in screen space.
    float coc = abs(depth - focusDistance) / max(focusDistance, 0.5);
    coc = saturate(coc * 0.35 * DOF_STRENGTH);
    if (coc < 0.002) return color;

    float radius = coc * 14.0;
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);

    vec3 sum = color;
    float wsum = 1.0;
    for (int i = 0; i < 12; i++) {
        float fi = float(i);
        float ang = fi * 2.39996;
        float r = sqrt((fi + 0.5) / 12.0) * radius;
        vec2 offset = vec2(cos(ang), sin(ang)) * r * texel;
        vec2 suv = clamp(uv + offset, vec2(0.0), vec2(1.0));
        float sampleDepth = linearDepth(getDepth0(suv));
        // Do not bleed sharp foreground into the background and vice versa.
        float accept = step(depth - 1.0, sampleDepth);
        vec3 sampleColor = texture(colortex7, suv).rgb;
        float w = accept * (1.0 - r / max(radius, 1e-3));
        sum += sampleColor * w;
        wsum += w;
    }
    return sum / max(wsum, 1e-3);
#else
    return color;
#endif
}

//==============================================================================
// motion blur (camera reprojection)
//==============================================================================

vec2 reprojectionVelocity(vec2 uv) {
    float depth = getDepth0(uv);
    if (depth >= 1.0) return vec2(0.0);

    vec3 viewPos = screenToView(uv, depth);
    vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;   // camera relative
    vec4 prevView = gbufferPreviousModelView * vec4(worldPos, 1.0);
    vec4 prevClip = gbufferPreviousProjection * prevView;
    if (abs(prevClip.w) < 1e-5) return vec2(0.0);
    vec2 prevUV = prevClip.xy / prevClip.w * 0.5 + 0.5;
    vec2 velocity = uv - prevUV;
    if (any(isnan(velocity)) || any(isinf(velocity))) return vec2(0.0);
    // Clamp so a camera cut cannot smear the whole screen.
    float len = length(velocity);
    if (len > 0.05) velocity *= 0.05 / len;
    return velocity;
}

vec3 motionBlur(vec2 uv, vec3 color) {
#ifdef MOTION_BLUR
    vec2 velocity = reprojectionVelocity(uv) * MOTION_BLUR_STRENGTH;
    float amount = length(velocity) * 22.0;
    if (amount < 0.15) return color;

    const int TAPS = 8;
    vec3 sum = color;
    float wsum = 1.0;
    for (int i = 1; i < TAPS; i++) {
        float t = float(i) / float(TAPS);
        vec2 suv = clamp(uv - velocity * t, vec2(0.0), vec2(1.0));
        float w = 1.0 - t;
        sum += texture(colortex7, suv).rgb * w;
        wsum += w;
    }
    return sum / wsum;
#else
    return color;
#endif
}

//==============================================================================
// lens flare
//==============================================================================

vec3 lensFlare(vec2 uv, float sceneDepth) {
#ifdef LENS_FLARE
    vec3 sunDirView = getSunDirView();
    vec3 sunWorld = getSunDirWorld();
    if (sunWorld.y < 0.0) return vec3(0.0);

    // Screen position of the sun (infinite distance).
    vec3 sunScreen = viewToScreen(normalize(sunDirView) * 10000.0);
    if (sunScreen.z > 1.0) return vec3(0.0);
    vec2 sunUV = sunScreen.xy;
    if (sunUV.x < -0.2 || sunUV.x > 1.2 || sunUV.y < -0.2 || sunUV.y > 1.2) return vec3(0.0);

    // Occluded by terrain? Then the flare fades out.
    float vis = 1.0;
    if (sunUV.x > 0.0 && sunUV.x < 1.0 && sunUV.y > 0.0 && sunUV.y < 1.0) {
        float d = getDepth0(sunUV);
        vis = step(0.99999, d);
    }
    vis *= celestialVisibility() * smoothstep(0.0, 0.12, sunWorld.y);

    vec2 axis = vec2(0.5) - sunUV;
    vec3 flare = vec3(0.0);

    // Ghosts mirrored through the screen centre.
    for (int i = 1; i <= 4; i++) {
        float fi = float(i);
        vec2 ghostUV = sunUV + axis * fi * 0.62;
        float d = length((uv - ghostUV) * vec2(aspectRatio, 1.0));
        float size = 0.035 + fi * 0.028;
        float ghost = smoothstep(size, size * 0.25, d);
        vec3 tint = mix(vec3(0.25, 0.55, 1.0), vec3(1.0, 0.45, 0.25), fract(fi * 0.37));
        flare += tint * ghost * 0.055;
    }

    // Halo around the sun itself.
    float sunDistance = length((uv - sunUV) * vec2(aspectRatio, 1.0));
    flare += vec3(1.0, 0.85, 0.65) * smoothstep(0.55, 0.0, sunDistance) * 0.10;

    return flare * vis;
#else
    return vec3(0.0);
#endif
}

//==============================================================================

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);

    // ---------------------------------------------------- chromatic aberration
    vec3 color;
#ifdef CHROMATIC_ABERRATION
    color = chromaticAberration(colortex7, uv, 1.0);
#else
    color = texture(colortex7, uv).rgb;
#endif

    // --------------------------------------------------------------- post FX
    color = depthOfField(uv, color);
    color = motionBlur(uv, color);

#ifdef BLOOM
    vec3 bloom = max(texture(colortex5, uv).rgb, vec3(0.0));
    color += bloom * BLOOM_STRENGTH * 0.85;
#endif

    // --------------------------------------------------------------- exposure
    float exposure = EXPOSURE * autoExposure(uv);
    color *= exposure;

    color = applyTonemap(color);

    // ------------------------------------------------------------- lens flare
    color += lensFlare(uv, getDepth0(uv));

    // ------------------------------------------------------------- grading
    color = applyColorGrade(color, SATURATION, CONTRAST);

#ifdef VIGNETTE
    color *= vignette(uv, VIGNETTE_STRENGTH);
#endif

    // ------------------------------------------------------------- sharpening
#ifdef SHARPEN
    // Sharpening is applied on the tone mapped image; the neighbours are
    // reconstructed the same way to stay consistent.
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
    vec3 north = applyTonemap(texture(colortex7, uv + vec2(0.0, texel.y)).rgb * exposure);
    vec3 south = applyTonemap(texture(colortex7, uv - vec2(0.0, texel.y)).rgb * exposure);
    vec3 east  = applyTonemap(texture(colortex7, uv + vec2(texel.x, 0.0)).rgb * exposure);
    vec3 west  = applyTonemap(texture(colortex7, uv - vec2(texel.x, 0.0)).rgb * exposure);
    vec3 blur = (north + south + east + west) * 0.25;
    color = clamp(color + (color - blur) * 0.42, 0.0, 1.0);
#endif

    // ------------------------------------------------------------- film grain
#ifdef FILM_GRAIN
    float grain = filmGrain(uv, frameTimeCounter) * 0.016 * GRAIN_STRENGTH;
    color += grain * (1.0 - luma(color) * 0.65);
#endif

    // ---------------------------------------------- dithering and sRGB encode
    color = linearToSrgb(saturate(color));
    color += ditherNoise(gl_FragCoord.xy);

    // ------------------------------------------------------------ debug views
#if DEBUG_VIEW > 0
    if (DEBUG_VIEW == 1) {
        float d = linearDepth(getDepth0(uv));
        color = vec3(fract(d / 32.0), fract(d / 8.0), fract(d / 2.0));
    } else if (DEBUG_VIEW == 2) {
        color = getNormalView(uv) * 0.5 + 0.5;
    } else if (DEBUG_VIEW == 3) {
        color = linearToSrgb(saturate(texture(colortex5, uv).rgb));
    } else if (DEBUG_VIEW == 4) {
        color = getMaterial(uv);
    } else if (DEBUG_VIEW == 5) {
        color = getLightLevels(uv);
    } else if (DEBUG_VIEW == 6) {
        color = vec3(getWetness(uv), getMatClass(uv) / 4.0, getHandFlag(uv));
    }
#endif

    fragColor = vec4(color, 1.0);
}
