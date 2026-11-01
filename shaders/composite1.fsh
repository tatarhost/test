#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    composite1.fsh   (pass 2: shading composite)

    Reads the opaque scene colour, the analysis buffers and the translucent
    surface data, and produces the final lit scene into colortex7.

    Order of operations per pixel
      1. opaque: bifiltered AO, indirect light, contact shadows and screen
         space reflections on wet / polished surfaces
      2. water: refraction of the opaque background, Beer-Lambert absorption
         based on the real water column depth, animated caustics, fresnel
         weighted reflection (screen space, falling back to the sky)
      3. glass: tinted transmission plus fresnel reflection
      4. sky: passed through untouched (the atmosphere is already correct)
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/shadows.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/sky.glsl"
#include "/lib/clouds.glsl"
#include "/lib/composite_common.glsl"
#include "/lib/water.glsl"

uniform sampler2D colortex0;   // opaque scene
uniform sampler2D colortex4;   // AO (a) + GI (rgb)
uniform sampler2D colortex5;   // SSR (rgb) + confidence (a)
uniform sampler2D colortex6;   // translucent forward colour (rgb) + coverage (a)

/* DRAWBUFFERS:7 */
layout(location = 0) out vec4 outColor;

//==============================================================================
// helpers
//==============================================================================

float bilateralWeight(float centerDepth, float sampleDepth) {
    return exp(-abs(centerDepth - sampleDepth) * 22.0);
}

// Small edge aware blur of the AO buffer, done on sampling so that the
// analysis pass does not need an extra target.
float sampleAOSmooth(vec2 uv, float centerViewZ) {
    vec2 texel = texelSize();
    float sum = 0.0;
    float wsum = 0.0;
    const vec2 offsets[5] = vec2[5](
        vec2( 0.0,  0.0),
        vec2( 1.6,  0.0),
        vec2(-1.6,  0.0),
        vec2( 0.0,  1.6),
        vec2( 0.0, -1.6)
    );
    for (int i = 0; i < 5; i++) {
        vec2 suv = uv + offsets[i] * texel;
        float sd = viewZFromDepth(texture(depthtex1, suv).r);
        float w = bilateralWeight(centerViewZ, sd);
        sum += texture(colortex4, suv).a * w;
        wsum += w;
    }
    return wsum > 0.0 ? sum / wsum : texture(colortex4, uv).a;
}

vec3 sampleGISmooth(vec2 uv, float centerViewZ) {
    vec2 texel = texelSize();
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    const vec2 offsets[5] = vec2[5](
        vec2( 0.0,  0.0),
        vec2( 2.2,  0.0),
        vec2(-2.2,  0.0),
        vec2( 0.0,  2.2),
        vec2( 0.0, -2.2)
    );
    for (int i = 0; i < 5; i++) {
        vec2 suv = uv + offsets[i] * texel;
        float sd = viewZFromDepth(texture(depthtex1, suv).r);
        float w = bilateralWeight(centerViewZ, sd);
        sum += texture(colortex4, suv).rgb * w;
        wsum += w;
    }
    return wsum > 0.0 ? sum / wsum : texture(colortex4, uv).rgb;
}

float computeContactShadow(vec3 viewPos, vec3 normal, float NdotL, float dither) {
#ifdef CONTACT_SHADOWS
    if (NdotL <= 0.02) return 0.0;
    vec3 lightDir = getLightDirView();
    float maxDistance = 1.5;
    const int STEPS = 8;
    float start = 0.04 * (0.5 + dither);
    for (int i = 0; i < STEPS; i++) {
        float t = start + (float(i) / float(STEPS)) * maxDistance;
        vec3 p = viewPos + lightDir * t + normal * 0.02;
        vec3 scr = viewToScreen(p);
        if (scr.x < 0.0 || scr.x > 1.0 || scr.y < 0.0 || scr.y > 1.0 || scr.z > 1.0) break;
        float sceneZ = viewZFromDepth(texture(depthtex1, scr.xy).r);
        if (sceneZ > p.z + 0.02) return 0.0;
    }
    return 1.0;
#else
    return 1.0;
#endif
}

//==============================================================================
// water
//==============================================================================

vec3 shadeWater(vec2 uv, vec3 viewPos, vec3 nV) {
    vec3 worldPos = viewToWorldPos(viewPos);
    vec3 Vw = normalize(-viewToWorldDir(viewPos));
    vec3 nW = normalize(viewToWorldDir(nV));

    float NdotV = saturate(dot(nW, Vw));
    float fresnel = 0.02 + 0.98 * pow(1.0 - NdotV, 5.0);

    float d0 = getDepth0(uv);
    float d1 = getDepth1(uv);
    float thickness = max(linearDepth(d1) - linearDepth(d0), 0.0);
    if (d1 >= 1.0) thickness = 12.0;   // water against the sky

    // --- refraction of the opaque background --------------------------------
#ifdef WATER_REFRACTION
    vec2 refr = nV.xy * 0.075 * saturate(thickness * 0.7);
    refr.x *= viewHeight / max(viewWidth, 1.0);
#else
    vec2 refr = vec2(0.0);
#endif
    vec3 background = texture(colortex0, clamp(uv + refr, vec2(0.0005), vec2(0.9995))).rgb;

    // --- absorption + caustics ---------------------------------------------
    vec3 absorption = waterAbsorption(thickness * WATER_FOG_DENSITY);
#ifdef WATER_CAUSTICS
    vec3 bottomWorld = viewToWorldPos(screenToView(uv, d1 < 1.0 ? d1 : d0));
    float causticAmount = caustics(bottomWorld) * causticVisibility(thickness);
    vec3 causticLight = shadowLightColor() * 0.32 + vec3(0.02, 0.05, 0.06);
    background += causticAmount * causticLight * absorption;
#endif
    vec3 bottom = background * absorption;

    // --- reflection ---------------------------------------------------------
    vec3 R = reflect(-Vw, nW);
    R.y = abs(R.y);
    vec3 skyRefl = renderSkyCheap(R) + cloudLayerReflection(R, getSunDirWorld());

    vec4 ssrSample = texture(colortex5, uv);
    vec3 ssr = ssrSample.a > 0.001 ? ssrSample.rgb / max(ssrSample.a, 1e-3) : skyRefl;
    vec3 reflection = mix(skyRefl, ssr, saturate(ssrSample.a));

    // --- body scattering (pre-integrated in gbuffers_water) -----------------
    vec3 scatter = texture(colortex6, uv).rgb;

    return mix(bottom + scatter, reflection, fresnel);
}

//==============================================================================
// glass
//==============================================================================

vec3 shadeGlass(vec2 uv, vec3 nV) {
    vec4 trans = texture(colortex6, uv);
#ifdef WATER_REFRACTION
    vec2 offset = nV.xy * 0.028;
    offset.x *= viewHeight / max(viewWidth, 1.0);
#else
    vec2 offset = vec2(0.0);
#endif
    vec3 background = texture(colortex0, clamp(uv + offset, vec2(0.0005), vec2(0.9995))).rgb;
    vec3 color = mix(background, trans.rgb, saturate(trans.a));

    vec4 ssrSample = texture(colortex5, uv);
    if (ssrSample.a > 0.001) {
        vec3 ssr = ssrSample.rgb / max(ssrSample.a, 1e-3);
        color = mix(color, ssr, saturate(ssrSample.a) * 0.35);
    }
    return color;
}

//==============================================================================

void main() {
    vec2 uv = screenUV();
    float dither = blueNoise(uv);

    float d0 = getDepth0(uv);
    float d1 = getDepth1(uv);
    float matClass = getMatClass(uv);

    vec3 color;

    if (d0 >= 1.0 && d1 >= 1.0) {
        // ------------------------------------------------------------- sky
        color = texture(colortex0, uv).rgb;
    } else if (matClass == MAT_WATER) {
        color = shadeWater(uv, getViewPos0(uv), getNormalView(uv));
    } else if (matClass == MAT_GLASS) {
        color = shadeGlass(uv, getNormalView(uv));
    } else if (matClass == MAT_EFFECT) {
        // weather / particles: already final, just add indirect light
        color = texture(colortex0, uv).rgb;
    } else {
        // ----------------------------------------------------------- opaque
        vec3 normal = getNormalView(uv);
        vec3 viewPos = getViewPos1(uv);
        float viewZ = viewPos.z;

        color = texture(colortex0, uv).rgb;

        float ao = sampleAOSmooth(uv, viewZ);
        vec3 gi = sampleGISmooth(uv, viewZ);

        // Ambient occlusion attenuates the ambient part of the lighting. The
        // forward pass is a single colour buffer, so the split is approximated
        // with a mild global multiplication plus the indirect term below.
        color *= mix(1.0, ao, 0.72);
        color += gi * mix(0.35, 1.0, ao);

        float NdotL = dot(normal, getLightDirView());
        float cs = computeContactShadow(viewPos, normal, NdotL, dither);
        color *= mix(1.0, cs, 0.55 * saturate(NdotL));

        // Wet / polished surfaces get screen space reflections on top of the
        // forward reflection term.
#ifdef REFLECTIONS
        float wetness = getWetness(uv);
        vec3 mat = getMaterial(uv);
        float roughness = mat.x;
        vec4 ssrSample = texture(colortex5, uv);
        if (ssrSample.a > 0.001) {
            vec3 Vv = normalize(-viewPos);
            float NdotV = saturate(dot(normal, Vv));
            float F = 0.04 + 0.96 * pow(1.0 - NdotV, 5.0);
            float strength = F * saturate(ssrSample.a) * mix(0.35, 1.0, saturate(wetness * 2.0));
            if (roughness < 0.2) strength = max(strength, F * saturate(ssrSample.a) * 0.5);
            vec3 ssr = ssrSample.rgb / max(ssrSample.a, 1e-3);
            color = mix(color, ssr, saturate(strength * 0.75));
        }
#endif
    }

    outColor = vec4(max(color, vec3(0.0)), 1.0);
}
