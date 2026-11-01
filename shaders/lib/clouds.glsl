/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/clouds.glsl

    Volumetric cloud system.

    Two conceptually separate pieces:

    1. A *cumulus* deck built from a coverage map (2D fbm, animated) that
       drives a 3D density field (a second fbm shaped by a vertical profile).
       The deck is ray marched with a slab intersection, front to back
       compositing and per sample lighting that approximates multiple
       scattering (Beer's law + "powder" term + ambient sky fill).

    2. A cheap "cloud layer" used for water / glass reflections and cloud
       shadows, which only samples the coverage map on the cloud plane.

    Vanilla clouds are disabled through "clouds=off" in shaders.properties, so
    these are the only clouds in the scene.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_CLOUDS_GLSL
#define HYPERREAL_CLOUDS_GLSL

const float CLOUD_BASE = 180.0;
const float CLOUD_TOP  = 262.0;
const float CLOUD_EXTINCTION = 0.055;

// Wind offset, in cloud texture space.
vec2 cloudWind() {
    float t = frameTimeCounter;
    return vec2(t * 2.1, t * 0.85);
}

// Coverage in [0,1] at a world XZ position. Shared by the volumetric deck,
// the reflections and the cloud shadows so they always agree.
float cloudCoverage(vec2 worldXZ) {
    vec2 p = (worldXZ + cloudWind()) * 0.0013;
    float weather = fbm2D(p, 4);
    // Large weather systems modulate the local coverage.
    float macro = valueNoise2D(p * 0.23 + 7.3);
    float cov = saturate((weather - 0.44) * 2.35 * CLOUD_COVERAGE * mix(0.75, 1.25, macro));
    // Storms increase coverage.
    cov = saturate(cov + rainStrength * 0.45);
    return cov;
}

// 3D density of the cumulus deck. World space position.
float cloudDensity(vec3 p) {
    if (p.y < CLOUD_BASE || p.y > CLOUD_TOP) return 0.0;

    float hf = (p.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE);
    float profile = smoothstep(0.0, 0.22, hf) * (1.0 - smoothstep(0.55, 1.0, hf));
    if (profile <= 0.0) return 0.0;

    float cov = cloudCoverage(p.xz);
    if (cov <= 0.001) return 0.0;

    // Base shape: a slowly evolving fbm field, eroded near the top of the deck
    // so the clouds get the billowy "cauliflower" silhouette.
    vec2 wind = cloudWind();
    vec3 q = vec3((p.xz + wind) * 0.0075, p.y * 0.021 - frameTimeCounter * 0.004);
#if CLOUD_QUALITY >= 2
    float base = fbm3D(q, 4);
#else
    float base = fbm3D(q, 3);
#endif
    float d = saturate((base - (1.0 - cov) * 0.92) * 2.6);

    // Erode with a second, higher frequency field.
    if (d > 0.02) {
        float detail = valueNoise3D(q * 4.7 + 5.1);
        d = saturate(d - (1.0 - detail) * 0.28 * (1.0 - hf));
    }

    return d * profile * 2.4;
}

// Lighting for one cloud sample.
//   sunDir, sunColor : direct light
//   ambientColor     : sky / multiple scattering fill
//   density          : local density (for the powder term)
vec3 cloudSampleLight(vec3 p, vec3 sunDir, vec3 sunColor, vec3 ambientColor, float density, float cosTheta) {
#if CLOUD_QUALITY >= 2
    const int lightSteps = 4;
#else
    const int lightSteps = 2;
#endif
    float lightDensity = 0.0;
    for (int i = 0; i < 4; i++) {
        if (i >= lightSteps) break;
        float t = (float(i) + 0.5) * (CLOUD_TOP - CLOUD_BASE) * 0.22;
        lightDensity += cloudDensity(p + sunDir * t);
    }
    lightDensity /= float(lightSteps);

    float beer = exp(-lightDensity * 2.4);
    float powder = 1.0 - exp(-density * 5.0);
    float forward = 0.35 + 0.65 * pow(saturate(cosTheta), 6.0);   // silver lining

    // Hemisphere ambient: brighter towards the top of the deck.
    float topness = saturate((p.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE));
    vec3 ambient = ambientColor * mix(0.55, 1.15, topness);

    // Multiple scattering approximation (two extra cheaper octaves of
    // transmittance), which fills in the dark side of the clouds.
    float scatter = beer * 0.65 + exp(-lightDensity * 0.7) * 0.35;
    return sunColor * scatter * powder * forward * 0.85 + ambient;
}

// Ray / cloud slab intersection. Returns (near, far) or (-1,-1).
vec2 cloudSlab(vec3 ro, vec3 rd) {
    if (abs(rd.y) < 1e-4) {
        if (ro.y < CLOUD_BASE || ro.y > CLOUD_TOP) return vec2(-1.0);
        return vec2(0.0, 1e6);
    }
    float t0 = (CLOUD_BASE - ro.y) / rd.y;
    float t1 = (CLOUD_TOP - ro.y) / rd.y;
    if (t0 > t1) { float tmp = t0; t0 = t1; t1 = tmp; }
    return vec2(max(t0, 0.0), t1);
}

/*
    Ray marches the cloud deck.

    roWorld  : ray origin in world space (camera)
    rdWorld  : normalised ray direction
    maxDist  : distance to the scene geometry, clouds beyond it are hidden
    outTrans : remaining transmittance (1 = no cloud)
    returns  : in-scattered cloud radiance (not premultiplied)
*/
vec3 raymarchClouds(vec3 roWorld, vec3 rdWorld, float maxDist, out float outTrans) {
    outTrans = 1.0;
    vec3 result = vec3(0.0);
#if CLOUD_QUALITY == 0
    return result;
#else
    vec2 slab = cloudSlab(roWorld, rdWorld);
    if (slab.x < 0.0 || slab.x > maxDist) return result;
    float tNear = slab.x;
    float tFar = min(slab.y, maxDist);
    if (tFar <= tNear) return result;

    vec3 sunDir = getSunDirWorld();
    vec3 sunColor = sunDirectColor(sunDir) * 0.65 + vec3(0.02);
    vec3 ambTop;
    vec3 ambHorizon;
    skyGradientColors(sunDir, ambTop, ambHorizon);
    vec3 ambientColor = (ambTop * 0.75 + ambHorizon * 0.25) * 1.35 + vec3(0.01, 0.012, 0.02);

    float cosTheta = dot(rdWorld, sunDir);
    vec3 sunView = getLightDirView();
    vec3 rdView = worldToViewDir(rdWorld);

#if CLOUD_QUALITY >= 3
    const int steps = 40;
#elif CLOUD_QUALITY == 2
    const int steps = 24;
#else
    const int steps = 14;
#endif

    float jitter = ign(gl_FragCoord.xy + frameCounter * 0.618);
    float prevT = tNear;
    float transmittance = 1.0;

    for (int i = 0; i < 40; i++) {
        if (i >= steps) break;
        // Non linear step distribution: fine near the camera, coarse far away.
        float f = (float(i) + jitter) / float(steps);
        float t = mix(tNear, tFar, f * f);
        float stepLen = max(t - prevT, 0.05);
        prevT = t;

        vec3 p = roWorld + rdWorld * t;
        float density = cloudDensity(p);
        if (density <= 0.001) continue;

        float extinction = density * CLOUD_EXTINCTION * stepLen;
        vec3 sampleCol = cloudSampleLight(p, sunDir, sunColor, ambientColor, density, cosTheta);

        // Shadowing by the shadow map keeps clouds behind mountains dark.
        vec3 pView = worldToViewPos(p);
        sampleCol *= getShadowVisibilityFast(pView);

        result += transmittance * sampleCol * (1.0 - exp(-extinction));
        transmittance *= exp(-extinction);
        if (transmittance < 0.015) break;
    }

    // Aerial perspective on the cloud itself, so distant decks melt into haze.
    float hazeAmount = 1.0 - exp(-maxDist * 0.00035);
    vec3 hazeColor = atmosphereScatteringCheap(normalize(vec3(rdWorld.x, max(rdWorld.y, 0.0) * 0.3 + 0.02, rdWorld.z)), sunDir);
    result = mix(result, hazeColor, hazeAmount * 0.55);

    outTrans = transmittance;
    return result;
#endif
}

//==============================================================================
// cheap helpers
//==============================================================================

// Projected cloud layer used by reflections (water, glass, wet surfaces).
vec3 cloudLayerReflection(vec3 dirW, vec3 sunDirW) {
#if CLOUD_QUALITY == 0
    return vec3(0.0);
#else
    if (dirW.y <= 0.01) return vec3(0.0);
    float t = (CLOUD_BASE - eyeAltitude) / dirW.y;
    if (t <= 0.0 || t > 24000.0) return vec3(0.0);
    vec3 hit = cameraPosition + dirW * t;
    float cov = cloudCoverage(hit.xz);
    if (cov <= 0.01) return vec3(0.0);

    vec3 zenith;
    vec3 horizon;
    skyGradientColors(sunDirW, zenith, horizon);
    vec3 sunColor = sunDirectColor(sunDirW);
    float lit = saturate(dot(dirW, sunDirW) * 0.5 + 0.5);
    vec3 cloudCol = sunColor * (0.16 + 0.5 * lit) + (zenith * 0.6 + horizon * 0.4) * 0.9;
    // Fade towards the horizon so the layer does not form a hard band.
    float fade = smoothstep(0.0, 0.16, dirW.y);
    return cloudCol * cov * fade * 0.85;
#endif
}

// Shadow cast by the cloud deck onto the terrain.
float cloudShadowFactor(vec3 worldPos, vec3 sunDirW) {
#if defined(CLOUD_SHADOWS) && CLOUD_QUALITY > 0
    if (sunDirW.y < 0.03) return 1.0;
    float t = (CLOUD_BASE - worldPos.y) / sunDirW.y;
    if (t <= 0.0 || t > 20000.0) return 1.0;
    vec3 hit = worldPos + sunDirW * t;
    float cov = cloudCoverage(hit.xz);
    return mix(1.0, 0.25, saturate(cov * 1.35));
#else
    return 1.0;
#endif
}

#endif // HYPERREAL_CLOUDS_GLSL
