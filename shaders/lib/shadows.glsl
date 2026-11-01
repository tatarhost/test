/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/shadows.glsl

    Shadow map sampling.

    The pack uses a single high resolution shadow map (a shader pack cannot
    allocate cascades) with a radial clip space distortion that spends more
    texels close to the camera, where shadow detail is actually visible.
    The distortion is a monotonic remap of the shadow clip space radius:

        g(r) = r * (1 + K * (1 - r))        g(0) = 0,  g(1) = 1

    The same function is applied in shadow.vsh, so the map is sampled
    consistently. K is driven by SHADOW_DISTORTION.

    Filtering:
      SHADOW_FILTER 0 : single tap (fastest)
      SHADOW_FILTER 1 : 4 tap rotated PCF
      SHADOW_FILTER 2 : 9 tap rotated PCF
      SHADOW_FILTER 3 : 17 tap disc PCF
    plus optional PCSS (percentage closer soft shadows) with a blocker search
    for contact hardened penumbrae, and slope scaled depth bias combined with a
    world space normal offset to avoid peter panning.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_SHADOWS_GLSL
#define HYPERREAL_SHADOWS_GLSL

const float SHADOW_DISTORT_K = 1.0;

float shadowDistortFactor(float radius) {
#ifdef SHADOW_DISTORTION
    return 1.0 + SHADOW_DISTORT_K * (1.0 - saturate(radius));
#else
    return 1.0;
#endif
}

// camera relative world position -> shadow clip space with distortion applied
vec4 shadowClip(vec3 viewPos) {
    vec3 relWorld = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec4 clip = shadowProjection * (shadowModelView * vec4(relWorld, 1.0));
    vec2 ndc = clip.xy / clip.w;
    ndc *= shadowDistortFactor(length(ndc));
    clip.xy = ndc * clip.w;
    return clip;
}

vec3 shadowClipPoint(vec3 viewPos) {
    vec4 clip = shadowClip(viewPos);
    return vec3(clip.xy / clip.w * 0.5 + 0.5, clip.z / clip.w * 0.5 + 0.5);
}

// Size of one shadow texel in shadow clip space.
const float SHADOW_TEXEL = 1.0 / float(shadowMapResolution);

// Rotation matrix from a per pixel dither angle
mat2 shadowRotate(vec2 fragCoord) {
    float a = ign(fragCoord + frameCounter * 5.588238) * TAU;
    float s = sin(a);
    float c = cos(a);
    return mat2(c, s, -s, c);
}

float shadowCompare(vec2 uv, float depth, float bias) {
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 1.0;
    return step(depth - bias, texture(shadowtex1, uv).r);
}

// Blocker depth search for PCSS. Returns the average blocker depth or -1.
float shadowBlockerDepth(vec3 clipPos, float searchRadius, float lightBleedingFix) {
    float sum = 0.0;
    float count = 0.0;
    mat2 rot = shadowRotate(gl_FragCoord.xy);
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        vec2 offset = vec2(cos(fi * TAU / 8.0 + 0.39), sin(fi * TAU / 8.0 + 0.39));
        offset = rot * offset * searchRadius;
        float d = texture(shadowtex1, clipPos.xy + offset).r;
        if (d < clipPos.z - lightBleedingFix) {
            sum += d;
            count += 1.0;
        }
    }
    if (count < 0.5) return -1.0;
    return sum / count;
}

float pcfShadow(vec3 clipPos, float bias, float radius) {
#if SHADOW_FILTER == 0
    return shadowCompare(clipPos.xy, clipPos.z, bias);
#else
    mat2 rot = shadowRotate(gl_FragCoord.xy);
    float sum = 0.0;
  #if SHADOW_FILTER == 1
    const int taps = 4;
  #elif SHADOW_FILTER == 2
    const int taps = 9;
  #else
    const int taps = 17;
  #endif
    for (int i = 0; i < 17; i++) {
        if (i >= taps) break;
        float fi = float(i);
        // spiral / disc distribution
        float r = sqrt((fi + 0.5) / float(taps));
        float a = fi * 2.39996;
        vec2 offset = vec2(cos(a), sin(a)) * r;
        offset = rot * offset * radius;
        sum += shadowCompare(clipPos.xy + offset, clipPos.z, bias);
    }
    return sum / float(taps);
#endif
}

/*
    Main shadow lookup.

    viewPos    : fragment position in view space
    viewNormal : geometric normal in view space
    NdotL      : dot(normal, light direction), used for normal offset + bias
    lightDirView : direction towards the light in view space
*/
float getShadowVisibility(vec3 viewPos, vec3 viewNormal, float NdotL, vec3 lightDirView) {
    if (shadowMapResolution <= 0) return 1.0;

    vec3 clipPos = shadowClipPoint(viewPos);

    // Distance fade: outside of the shadow map the geometry is lit normally.
    float dist = length(clipPos.xy * 2.0 - 1.0);
    float fade = 1.0 - smoothstep(0.86, 1.0, dist);
    if (fade <= 0.0) return 1.0;
    if (clipPos.z > 1.0) return 1.0;

    // World space normal offset to fight acne on grazing angles.
    vec3 offsetPos = viewPos;
#ifdef SHADOW_NORMAL_OFFSET
    float texelWorld = 2.0 * shadowDistance / float(shadowMapResolution);
    float offsetScale = texelWorld * (1.35 + 1.9 * (1.0 - NdotL));
    offsetPos += viewNormal * offsetScale;
    clipPos = shadowClipPoint(offsetPos);
#endif

    // Slope scaled depth bias
    float bias = 0.00012 + 0.00075 * (1.0 - NdotL);
    bias *= 1.0 + (dist * dist) * 1.5;

#ifdef SHADOW_PCSS
    float searchRadius = SHADOW_TEXEL * 22.0 * SHADOW_SOFTNESS;
    float blocker = shadowBlockerDepth(clipPos, searchRadius, 0.0004);
    if (blocker < 0.0) return 1.0;
    float penumbra = (clipPos.z - blocker) * 34.0 * SHADOW_SOFTNESS;
    float filterRadius = clamp(penumbra, SHADOW_TEXEL * 0.75, SHADOW_TEXEL * 26.0);
    float visible = pcfShadow(clipPos, bias, filterRadius);
#else
    float visible = pcfShadow(clipPos, bias, SHADOW_TEXEL * 2.6 * SHADOW_SOFTNESS);
#endif

    return mix(1.0, visible, fade);
}

// Cheap 4 tap shadow lookup used by volumetrics (no PCSS, no normal offset).
float getShadowVisibilityFast(vec3 viewPos) {
    vec4 clip = shadowClip(viewPos);
    vec3 clipPos = vec3(clip.xy / clip.w * 0.5 + 0.5, clip.z / clip.w * 0.5 + 0.5);
    if (clipPos.x < 0.0 || clipPos.y < 0.0 || clipPos.x > 1.0 || clipPos.y > 1.0) return 1.0;
    float bias = 0.0009;
    mat2 rot = shadowRotate(gl_FragCoord.xy);
    float sum = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        vec2 offset = rot * vec2(cos(fi * 1.5707 + 0.7), sin(fi * 1.5707 + 0.7)) * SHADOW_TEXEL * 2.2;
        sum += shadowCompare(clipPos.xy + offset, clipPos.z, bias);
    }
    return sum * 0.25;
}

#endif // HYPERREAL_SHADOWS_GLSL
