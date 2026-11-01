/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/sky.glsl

    Composes the visible sky: atmospheric scattering, sun disc, moon with real
    phases, stars, the milky way and an optional aurora. Also provides the
    direction helpers that the rest of the pack uses for lighting.

    Dimension handling: the Nether and the End have no skylight. In that case
    the sky is replaced by a soft gradient built from the vanilla fog colour so
    that fog, sky and lighting stay consistent.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_SKY_GLSL
#define HYPERREAL_SKY_GLSL

// --- directions -------------------------------------------------------------
vec3 getSunDirView()   { return normalize(sunPosition); }
vec3 getMoonDirView()  { return normalize(moonPosition); }
vec3 getLightDirView() { return normalize(shadowLightPosition); }

vec3 getSunDirWorld()   { return normalize(viewToWorldDir(getSunDirView())); }
vec3 getMoonDirWorld()  { return normalize(viewToWorldDir(getMoonDirView())); }
vec3 getLightDirWorld() { return normalize(viewToWorldDir(getLightDirView())); }

bool hasSkyLight() { return eyeBrightnessSmooth.y > 4; }

// 1 = full day, 0 = full night. Based on the real sun elevation.
float dayFactor() {
    return smoothstep(-0.10, 0.12, getSunDirWorld().y);
}

// How visible the celestial objects are (clouds and rain hide them).
float celestialVisibility() {
    float weather = 1.0 - rainStrength * 0.92;
    return saturate(weather);
}

//==============================================================================
// dimension aware base sky
//==============================================================================

vec3 netherSky(vec3 dirW) {
    // Vanilla's fog colour drives the tone, a vertical gradient adds depth.
    vec3 base = srgbToLinear(fogColor) * 0.75;
    float up = saturate(dirW.y * 0.5 + 0.5);
    vec3 col = base * mix(0.55, 1.15, up);
    // Static, very subtle ash haze so the sky is not a flat gradient.
    float haze = fbm2D(dirW.xz / max(abs(dirW.y) + 0.25, 0.15) * 1.7 + 3.0, 4);
    col *= 0.9 + 0.2 * haze;
    return col;
}

//==============================================================================
// full sky
//==============================================================================

vec3 renderSky(vec3 dirW) {
    if (!hasSkyLight()) return netherSky(dirW);

    vec3 sunDir = getSunDirWorld();
    vec3 moonDir = getMoonDirWorld();

    // Ground hemisphere tint: the atmosphere model only integrates the upper
    // part, so fade the deep negative elevations into the horizon colour.
    vec3 dir = normalize(vec3(dirW.x, max(dirW.y, -0.02), dirW.z));

    vec3 col = skyRadiance(dir, sunDir);

    float vis = celestialVisibility();
    float day = dayFactor();

    // --- sun -----------------------------------------------------------------
    col += sunDisc(dirW, sunDir) * vis * smoothstep(-0.03, 0.02, sunDir.y);

    // --- moon ----------------------------------------------------------------
#ifdef NIGHT_SKY
    col += moonDisc(dirW, moonDir, sunDir) * vis * smoothstep(-0.02, 0.04, moonDir.y)
         * mix(1.0, 0.25, day);
#endif

    // --- stars / milky way / aurora ------------------------------------------
#ifdef STARS
    float starVis = saturate(1.0 - day * 1.35) * vis;
    col += starField(dirW, starVis);
    col += milkyWay(dirW, starVis * 0.85);
#endif

#ifdef AURORA
    float auroraVis = saturate(1.0 - day * 2.2) * vis * (1.0 - rainStrength);
    col += aurora(dirW, auroraVis * 0.55);
#endif

    // --- horizon haze --------------------------------------------------------
    // A soft brightening right at the horizon keeps the far terrain readable
    // and adds the "hazy horizon line" described in the feature list.
    float horizon = exp(-abs(dirW.y) * 26.0);
    vec3 hazeCol = skyRadiance(normalize(vec3(dirW.x, 0.02, dirW.z)), sunDir);
    col = mix(col, hazeCol * 1.05 + vec3(0.02), horizon * 0.35);

    return col;
}

// Sky colour used for reflection fallbacks. Cheap, no celestial bodies.
vec3 renderSkyCheap(vec3 dirW) {
    if (!hasSkyLight()) return netherSky(dirW) * 0.6;
    vec3 sunDir = getSunDirWorld();
    vec3 dir = normalize(vec3(dirW.x, max(dirW.y, -0.015), dirW.z));
    return atmosphereScatteringCheap(dir, sunDir);
}


//==============================================================================
// light source colours
//==============================================================================

// Analytic sun colour: Rayleigh / Mie style extinction as a function of the
// sun elevation. Cheap enough to evaluate per pixel and a close match for the
// raymarched atmosphere used by the visible sky.
vec3 sunDirectColor(vec3 sunDirW) {
    float e = sunDirW.y;
    float airMass = 1.0 / max(e + 0.12, 0.045);
    vec3 tau = vec3(0.30, 0.55, 1.25) * airMass * 0.15;
    vec3 col = exp(-tau) * 11.0;
    return col * smoothstep(-0.14, 0.02, e);
}

vec3 moonDirectColor(vec3 moonDirW) {
    float phase = 0.5 - 0.5 * cos(float(moonPhase) / 8.0 * TAU);
    float brightness = mix(1.0, 0.16, phase);
    return vec3(0.34, 0.44, 0.72) * 1.05 * brightness * smoothstep(-0.10, 0.06, moonDirW.y);
}

// Colour of the light that casts shadows (sun by day, moon by night).
vec3 shadowLightColor() {
    vec3 sunDirW = getSunDirWorld();
    vec3 moonDirW = getMoonDirWorld();
    float day = smoothstep(-0.045, 0.035, sunDirW.y);
    vec3 col = mix(moonDirectColor(moonDirW), sunDirectColor(sunDirW), day);
    // Thunder storms kill most of the direct light.
    col *= 1.0 - 0.72 * rainStrength - 0.22 * thunderStrength;
#ifdef LIGHTNING_FLASH
    col *= 1.0 + thunderStrength * 0.6;
#endif
    return col;
}

#endif // HYPERREAL_SKY_GLSL
