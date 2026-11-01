#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    composite.fsh   (pass 1 of the pipeline: screen space analysis)

    This pass never writes the scene colour. It reads it (for the screen space
    algorithms that gather light) and stores the results in helper buffers:

      colortex4 : RGB = screen space global illumination, A = ambient occlusion
      colortex5 : RGB = screen space reflection (raw), A = hit confidence

    Because read and write targets are disjoint there is no framebuffer
    feedback anywhere in the pipeline.

    Algorithms
      SSAO : hemisphere sampling in view space with a rotated spiral, range
             limited so that far geometry does not create halos.
      SSGI : short cosine weighted screen space rays that gather scene colour,
             giving a cheap approximation of one bounce of indirect light.
      SSR  : view space ray march against the opaque depth buffer with binary
             refinement. Only evaluated on reflective surfaces.
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
#include "/lib/buffers.glsl"


uniform sampler2D colortex0;

/* DRAWBUFFERS:45 */
layout(location = 0) out vec4 outAO;   // -> colortex4
layout(location = 1) out vec4 outSSR;  // -> colortex5

//==============================================================================
// ambient occlusion
//==============================================================================

float computeAO(vec3 viewPos, vec3 normal, float dither) {
#ifdef SSAO
    const int SAMPLES = 10;
    float radius = 1.25 * SSAO_RADIUS;
    float occlusion = 0.0;
    float valid = 0.0;

    vec3 up = abs(normal.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal));
    vec3 bitangent = cross(normal, tangent);

    float rot = dither * TAU;
    mat2 rotM = mat2(cos(rot), -sin(rot), sin(rot), cos(rot));

    for (int i = 0; i < SAMPLES; i++) {
        float fi = float(i);
        float r = sqrt((fi + 0.5) / float(SAMPLES));
        float a = fi * 2.39996;
        vec2 disc = rotM * (vec2(cos(a), sin(a)) * r);
        float h = sqrt(max(1.0 - dot(disc, disc), 0.0));
        vec3 dir = normalize(tangent * disc.x + bitangent * disc.y + normal * h);

        vec3 samplePos = viewPos + dir * radius * (0.3 + 0.7 * r);
        vec3 scr = viewToScreen(samplePos);
        if (scr.x < 0.0 || scr.x > 1.0 || scr.y < 0.0 || scr.y > 1.0 || scr.z > 1.0) {
            valid += 1.0;
            continue;
        }

        float sceneZ = viewZFromDepth(texture(depthtex1, scr.xy).r);
        float delta = sceneZ - samplePos.z;   // > 0 : geometry in front of the sample
        float occl = smoothstep(0.035, radius * 0.85, delta) *
                     (1.0 - smoothstep(radius * 2.2, radius * 6.0, delta));
        occlusion += occl;
        valid += 1.0;
    }

    float ao = 1.0 - occlusion / max(valid, 1.0);
    return saturate(pow(ao, 1.4) * SSAO_STRENGTH);
#else
    return 1.0;
#endif
}

//==============================================================================
// screen space global illumination
//==============================================================================

vec3 computeGI(vec3 viewPos, vec3 normal, float dither) {
#ifdef SSGI
    const int RAYS = 4;
    const int STEPS = 3;

    vec3 up = abs(normal.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal));
    vec3 bitangent = cross(normal, tangent);

    vec3 sum = vec3(0.0);
    float weight = 0.0;

    for (int r = 0; r < RAYS; r++) {
        float fr = float(r);
        float ang = (fr / float(RAYS)) * TAU + dither * 2.4;
        vec2 disc = vec2(cos(ang), sin(ang)) * sqrt((fr + 0.55) / float(RAYS));
        float h = sqrt(max(1.0 - dot(disc, disc), 0.0));
        vec3 dir = normalize(tangent * disc.x + bitangent * disc.y + normal * h);

        for (int s = 1; s <= STEPS; s++) {
            float t = 2.4 * (float(s) / float(STEPS)) * (0.65 + 0.35 * fract(dither * 7.0 + fr * 0.37));
            vec3 p = viewPos + dir * t;
            vec3 scr = viewToScreen(p);
            if (scr.x < 0.0 || scr.x > 1.0 || scr.y < 0.0 || scr.y > 1.0 || scr.z > 1.0) break;

            float sceneZ = viewZFromDepth(texture(depthtex1, scr.xy).r);
            float delta = sceneZ - p.z;
            if (delta > 0.02 && delta < 1.4) {
                vec3 c = min(max(texture(colortex0, scr.xy).rgb, vec3(0.0)), vec3(6.0));
                float w = 1.0 / (1.0 + t * t) * (1.0 - float(s) / float(STEPS + 1));
                sum += c * w;
                weight += w;
                break;
            }
            if (delta < -0.6) break;
        }
    }

    if (weight <= 0.0) return vec3(0.0);
    return sum / weight * SSGI_STRENGTH * 0.55;
#else
    return vec3(0.0);
#endif
}

//==============================================================================
// screen space reflections
//==============================================================================

vec3 traceReflection(vec3 viewPos, vec3 normal, float roughness, float dither, out float confidence) {
    confidence = 0.0;
#ifdef REFLECTIONS
    vec3 rayDir = reflect(normalize(viewPos), normal);

#ifdef REFLECTION_ROUGH
    vec3 jitter = vec3(dither, fract(dither * 7.31), fract(dither * 3.77)) * 2.0 - 1.0;
    rayDir = normalize(rayDir + jitter * (0.015 + roughness * 0.4));
#endif
    if (rayDir.z > 0.0) return vec3(0.0);

    float t = 0.4;
    float stepScale = 0.3;

    for (int i = 0; i < REFLECTION_QUALITY; i++) {
        vec3 p = viewPos + rayDir * t;
        vec3 scr = viewToScreen(p);
        if (scr.z > 1.0 || scr.x < 0.0 || scr.x > 1.0 || scr.y < 0.0 || scr.y > 1.0) break;

        float sceneZ = viewZFromDepth(texture(depthtex1, scr.xy).r);
        float delta = sceneZ - p.z;
        float thickness = max(0.4, t * 0.075);

        if (delta > 0.0 && delta < thickness) {
            vec3 lo = viewPos + rayDir * max(t - stepScale, 0.0);
            vec3 hi = p;
            for (int j = 0; j < 5; j++) {
                vec3 mid = (lo + hi) * 0.5;
                vec3 midScr = viewToScreen(mid);
                float midZ = viewZFromDepth(texture(depthtex1, midScr.xy).r);
                if (midZ > mid.z) hi = mid; else lo = mid;
            }
            vec3 hitScr = viewToScreen(hi);
            float edge = smoothstep(0.0, 0.06, hitScr.x) * smoothstep(1.0, 0.94, hitScr.x) *
                         smoothstep(0.0, 0.06, hitScr.y) * smoothstep(1.0, 0.94, hitScr.y);
            float distFade = 1.0 - saturate(t / 110.0);
            confidence = edge * distFade;
            return max(texture(colortex0, hitScr.xy).rgb, vec3(0.0)) * confidence;
        }
        if (delta < -2.0 && sceneZ < p.z - 2.0) break;

        stepScale = 0.22 + t * 0.075;
        t += stepScale;
        if (t > 140.0) break;
    }
#endif
    return vec3(0.0);
}

//==============================================================================

void main() {
    vec2 uv = screenUV();
    float dither = blueNoise(uv);

    float matClass = getMatClass(uv);
    vec3 normal = getNormalView(uv);
    float depth = getDepth0(uv);

    float ao = 1.0;
    vec3 gi = vec3(0.0);
    vec3 ssr = vec3(0.0);
    float ssrConf = 0.0;

    if (depth < 1.0 && matClass >= 1.0 && matClass <= 3.0) {
        float d1 = getDepth1(uv);
        bool hasOpaque = d1 < 1.0;
        vec3 surfacePos = hasOpaque ? screenToView(uv, d1) : screenToView(uv, depth);

        ao = computeAO(surfacePos, normal, dither);
        gi = computeGI(surfacePos, normal, dither);

#ifdef REFLECTIONS
        if (hasOpaque) {
            vec3 mat = getMaterial(uv);
            float roughness = mat.x;
            float wetness = getWetness(uv);
            bool reflective = (matClass == MAT_WATER) || (matClass == MAT_GLASS) ||
                              (wetness > 0.05) || (roughness < 0.2);
            if (reflective) {
                vec3 tracePos = screenToView(uv, depth);
                float roughUsed = (matClass == MAT_WATER) ? 0.05 : roughness;
                ssr = traceReflection(tracePos, normal, roughUsed, dither, ssrConf);
            }
        }
#endif
    }

    outAO = vec4(gi, ao);
    outSSR = vec4(ssr, ssrConf);
}
