/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/fog.glsl

    Atmospheric fog and volumetric light shafts.

    * Aerial perspective : exponential height fog integrated along the view
      ray, tinted with the sky colour in the view direction so that distant
      terrain melts into the horizon instead of a flat grey wall.
    * Volumetric light  : single scattering march along the view ray that
      samples the shadow map per step (god rays, crepuscular rays through
      windows and foliage) modulated by the Henyey-Greenstein phase function.
    * Underwater        : the same march with a much denser, absorbing medium
      plus caustic light on the surfaces.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_FOG_GLSL
#define HYPERREAL_FOG_GLSL

// Height fog parameters (blocks).
const float FOG_HEIGHT_BASE = 58.0;
const float FOG_HEIGHT_SCALE = 26.0;

float fogDensityAt(vec3 worldPos) {
    float height = worldPos.y - FOG_HEIGHT_BASE;
    float density = exp(-height / FOG_HEIGHT_SCALE);
    // Morning mist thickens near the ground just after sunrise.
#ifdef MORNING_FOG
    float morning = 1.0 - smoothstep(0.0, 0.35, abs(fract(worldTime / 24000.0) - 0.02) * 8.0);
    density *= mix(1.0, 1.9, morning * 0.5);
#endif
    density *= 0.0075 * FOG_DENSITY;
    density *= 1.0 + rainStrength * 1.6 + thunderStrength * 1.1;
    return density;
}

// Henyey-Greenstein phase function (forward scattering of sunlight).
float fogPhase(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

struct FogResult {
    vec3 color;
    float transmittance;
};

/*
    Sky coloured fog / haze tint for a given view direction.
*/
vec3 fogTint(vec3 dirW, vec3 sunDirW) {
    vec3 zenith;
    vec3 horizon;
    skyGradientColors(sunDirW, zenith, horizon);
    float up = saturate(dirW.y * 1.4 + 0.15);
    vec3 col = mix(horizon, zenith, up);
    // Sun glow: the haze brightens strongly towards the sun.
    float sunAmount = saturate(dot(dirW, sunDirW));
    col += sunDirectColor(sunDirW) * pow(sunAmount, 8.0) * 0.12;
    return col;
}

/*
    Marches the fog and the volumetric light shafts.

    viewPos     : view space position of the fragment (end of the ray)
    uv          : screen uv (for dithering)
    Returns the in-scattered colour and the transmittance.
*/
FogResult marchFog(vec3 viewPos, vec2 uv, vec3 dirW) {
    FogResult result;
    result.color = vec3(0.0);
    result.transmittance = 1.0;

    float rayLength = length(viewPos);

#ifdef WATER_FOG
    // Underwater medium: dense, strongly absorbing, no shadow map detail.
    if (isEyeInWater == 1) {
        vec3 absorb = exp(-vec3(0.34, 0.115, 0.075) * rayLength * WATER_FOG_DENSITY);
        float trans = saturate(luma(absorb));
        vec3 waterTint = vec3(0.03, 0.13, 0.19) * (0.35 + 0.65 * skyLightLevel(vec2(0.0, 1.0)));
        waterTint *= shadowLightColor() * 0.25 + vec3(0.05, 0.16, 0.22);
        result.color = waterTint * (1.0 - trans) * 1.4;
        result.transmittance = trans;
        return result;
    }
#endif

    float maxDist = min(rayLength, 512.0);
    if (maxDist <= 0.05) return result;

    vec3 sunDirW = getSunDirWorld();
    vec3 sunColor = shadowLightColor();
    vec3 tint = fogTint(dirW, sunDirW);
    float cosTheta = dot(dirW, sunDirW);
    float phase = fogPhase(cosTheta, 0.72) * 2.2 + 0.06;

    // --- analytic aerial perspective (always on) ----------------------------
    vec3 cameraWorld = cameraPosition;
    vec3 endWorld = cameraWorld + dirW * maxDist;
    // Approximate the height fog integral with the average of both ends.
    float avgDensity = (fogDensityAt(cameraWorld) + fogDensityAt(endWorld)) * 0.5;
    float fogAmount = 1.0 - exp(-avgDensity * maxDist);
    vec3 color = tint * fogAmount;
    float transmittance = 1.0 - fogAmount;

    // --- volumetric light shafts -------------------------------------------
#ifdef VOLUMETRIC_LIGHT
#if VOLUMETRIC_QUALITY == 0
    const int STEPS = 0;
#elif VOLUMETRIC_QUALITY == 1
    const int STEPS = 8;
#elif VOLUMETRIC_QUALITY == 2
    const int STEPS = 14;
#else
    const int STEPS = 22;
#endif
    if (STEPS > 0) {
        float jitter = ign(gl_FragCoord.xy + frameCounter * 0.618);
        float volDist = min(maxDist, 180.0);
        float stepLen = volDist / float(STEPS);
        float od = 0.0;
        vec3 scatter = vec3(0.0);

        for (int i = 0; i < 22; i++) {
            if (i >= STEPS) break;
            float t = (float(i) + jitter) * stepLen;
            vec3 pWorld = cameraWorld + dirW * t;
            float density = fogDensityAt(pWorld);
            if (density <= 1e-6) continue;

            vec3 pView = worldToViewPos(pWorld);
            float visibility = getShadowVisibilityFast(pView);
            // Fade the shadow lookup near the shadow map border.
            float edgeFade = 1.0 - smoothstep(0.75, 1.0, length(pView) / max(shadowDistance, 1.0));

            vec3 stepLight = sunColor * visibility * mix(1.0, edgeFade, 0.5) * phase;
            scatter += stepLight * density * stepLen * exp(-od);
            od += density * stepLen;
        }

        color += scatter * 1.35;
        transmittance *= exp(-od);
    }
#endif

    result.color = color;
    result.transmittance = transmittance;
    return result;
}

#endif // HYPERREAL_FOG_GLSL
