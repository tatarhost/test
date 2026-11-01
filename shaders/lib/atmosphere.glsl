/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/atmosphere.glsl

    Physically motivated single scattering atmosphere.

    The model is a standard Rayleigh + Mie + ozone atmosphere integrated along
    the view ray on a spherical planet (Nishita style). It is fully analytic
    (no lookup textures), which keeps the pack self contained and lets the
    sun / moon colours evolve continuously with the time of day.

    Because Minecraft's world is only a few hundred blocks tall, the *aerial
    perspective* of terrain is handled separately by lib/fog.glsl with an
    artistically tuned exponential height fog. The sky itself uses the real
    scattering model, which is what produces the deep blue zenith, the bright
    horizon band and the orange / magenta twilight.

    All directions passed to this file are world space and normalised.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_ATMOSPHERE_GLSL
#define HYPERREAL_ATMOSPHERE_GLSL

// --- physical constants (metres) --------------------------------------------
const float ATM_PLANET_R   = 6360e3;
const float ATM_ATMOS_R    = 6420e3;
const float ATM_H_RAYLEIGH = 8000.0;
const float ATM_H_MIE      = 1200.0;
const float ATM_H_OZONE    = 15000.0;
const float ATM_OZONE_C    = 25000.0;

const vec3  ATM_BETA_R = vec3(5.802e-6, 13.558e-6, 33.1e-6);
const float ATM_BETA_M = 21.0e-6;
const vec3  ATM_BETA_O = vec3(0.650e-6, 1.881e-6, 0.085e-6);

// Artist tuned scale so that the single scattering is visible in a world that
// is only a few hundred blocks deep instead of kilometres.
const float ATM_MIE_G       = 0.76;
const float ATM_SUN_ENERGY  = 22.0;
const float ATM_MIE_DENSITY = 1.35;

//==============================================================================
// geometry helpers
//==============================================================================

// Returns (near, far) intersection distances, or (-1,-1) on a miss.
vec2 raySphere(vec3 ro, vec3 rd, float radius) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - radius * radius;
    float d = b * b - c;
    if (d < 0.0) return vec2(-1.0, -1.0);
    d = sqrt(d);
    return vec2(-b - d, -b + d);
}

float densityRayleigh(float h) { return exp(-max(h, 0.0) / ATM_H_RAYLEIGH); }
float densityMie(float h)      { return exp(-max(h, 0.0) / ATM_H_MIE); }
float densityOzone(float h) {
    float d = (h - ATM_OZONE_C) / ATM_H_OZONE;
    return max(0.0, 1.0 - d * d);
}

// Rayleigh phase function
float phaseRayleigh(float cosTheta) {
    return 3.0 / (16.0 * PI) * (1.0 + cosTheta * cosTheta);
}

// Cornette-Shanks / Henyey-Greenstein hybrid (keeps the Mie glow forward)
float phaseMie(float cosTheta) {
    const float g = ATM_MIE_G;
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

//==============================================================================
// optical depth along a ray inside the atmosphere
//==============================================================================

// Accumulates optical depth of a ray starting at 'ro' (planet centred) that
// travels 'len' metres in direction 'rd'. Cheap fixed-step integration is fine
// for the light ray because the density falls off exponentially.
vec3 lightOpticalDepth(vec3 ro, vec3 rd, float len, int steps) {
    vec3 od = vec3(0.0);
    float ds = len / float(steps);
    for (int i = 0; i < 8; i++) {
        if (i >= steps) break;
        vec3 p = ro + rd * (ds * (float(i) + 0.5));
        float h = length(p) - ATM_PLANET_R;
        vec3 density = vec3(densityRayleigh(h)) * ATM_BETA_R
                     + vec3(ATM_BETA_M * ATM_MIE_DENSITY * densityMie(h))
                     + ATM_BETA_O * densityOzone(h);
        od += density * ds;
    }
    return od;
}

// Transmittance from a point in the atmosphere towards the sun.
vec3 sunTransmittance(vec3 worldPos, vec3 sunDir) {
    float height = max(worldPos.y + ATM_PLANET_R, ATM_PLANET_R + 1.0) - ATM_PLANET_R;
    vec3 ro = vec3(0.0, ATM_PLANET_R + height, 0.0);
    vec2 atm = raySphere(ro, sunDir, ATM_ATMOS_R);
    if (atm.y < 0.0) return vec3(0.0);
    vec3 od = lightOpticalDepth(ro, sunDir, atm.y, 6);
    return exp(-od);
}

//==============================================================================
// single scattering
//==============================================================================

// dirW    : normalised view direction in world space
// sunDirW : normalised direction towards the sun in world space
// steps   : view ray integration steps (8..16 is a good range)
// lightSteps : sun ray integration steps (2..4)
vec3 atmosphereScattering(vec3 dirW, vec3 sunDirW, int steps, int lightSteps) {
    float eyeH = max(eyeAltitude - 62.0, 0.0) + 2.0;
    vec3 ro = vec3(0.0, ATM_PLANET_R + eyeH, 0.0);
    vec3 rd = vec3(dirW.x, dirW.y, dirW.z);

    vec2 atm = raySphere(ro, rd, ATM_ATMOS_R);
    if (atm.y <= 0.0) return vec3(0.0);

    float tMax = atm.y;
    vec2 ground = raySphere(ro, rd, ATM_PLANET_R);
    if (ground.x > 0.0) tMax = min(tMax, ground.x);

    float cosTheta = dot(rd, sunDirW);
    float phaseR = phaseRayleigh(cosTheta);
    float phaseM = phaseMie(cosTheta);

    // Jitter the first sample to hide the banding of the fixed step march.
    float jitter = ign(gl_FragCoord.xy);

    vec3 sumR = vec3(0.0);
    vec3 sumM = vec3(0.0);
    vec3 odView = vec3(0.0);

    float prevT = 0.0;
    for (int i = 0; i < 16; i++) {
        if (i >= steps) break;
        float f0 = (float(i) + jitter) / float(steps);
        float f1 = (float(i) + 1.0) / float(steps);
        float t0 = f0 * tMax;
        float t1 = f1 * tMax;
        float ds = max(t1 - t0, 1e-3);
        vec3 p = ro + rd * ((t0 + t1) * 0.5);
        float h = max(length(p) - ATM_PLANET_R, 0.0);

        vec3 density = vec3(densityRayleigh(h)) * ATM_BETA_R
                     + vec3(ATM_BETA_M * ATM_MIE_DENSITY * densityMie(h))
                     + ATM_BETA_O * densityOzone(h);
        odView += density * ds;

        // Shadowing of this sample by the planet body.
        if (raySphere(p, sunDirW, ATM_PLANET_R).x > 0.0) continue;

        vec2 lAtm = raySphere(p, sunDirW, ATM_ATMOS_R);
        vec3 odLight = lightOpticalDepth(p, sunDirW, max(lAtm.y, 1.0), lightSteps);
        vec3 transmittance = exp(-(odView + odLight));

        float dR = densityRayleigh(h);
        float dM = densityMie(h) * ATM_MIE_DENSITY;
        sumR += transmittance * dR * ds;
        sumM += transmittance * dM * ds;
    }

    vec3 radiance = ATM_SUN_ENERGY * (sumR * ATM_BETA_R * phaseR + sumM * ATM_BETA_M * phaseM);
    return radiance;
}

// Cheap variant used for reflection fallbacks and fog. Intentional low sample
// count; the result is smooth because it is only used as a tint.
vec3 atmosphereScatteringCheap(vec3 dirW, vec3 sunDirW) {
    return atmosphereScattering(dirW, sunDirW, 4, 2);
}

// Sky radiance including the twilight boost of the horizon.
vec3 skyRadiance(vec3 dirW, vec3 sunDirW) {
#if ATMOSPHERE_QUALITY >= 2
    vec3 rad = atmosphereScattering(dirW, sunDirW, 12, 4);
#elif ATMOSPHERE_QUALITY == 1
    vec3 rad = atmosphereScattering(dirW, sunDirW, 8, 3);
#else
    vec3 rad = atmosphereScattering(dirW, sunDirW, 5, 2);
#endif
    return rad;
}

//==============================================================================
// sun, moon, stars
//==============================================================================

vec3 sunDisc(vec3 dirW, vec3 sunDirW) {
    float cosAngle = dot(dirW, sunDirW);
    // ~0.55 degree radius
    float radius = 0.0088;
    float d = acos(clamp(cosAngle, -1.0, 1.0));
    if (d > radius * 4.0) return vec3(0.0);

    float disc = 1.0 - smoothstep(radius * 0.88, radius * 1.12, d);
    // limb darkening
    float r = saturate(d / radius);
    float limb = 1.0 - 0.55 * (1.0 - sqrt(max(1.0 - r * r, 0.0)));
    vec3 tint = vec3(1.0, 0.94, 0.86);
    return tint * disc * limb * 26.0;
}

vec3 moonDisc(vec3 dirW, vec3 moonDirW, vec3 sunDirW) {
    float cosAngle = dot(dirW, moonDirW);
    float radius = 0.0135;
    float d = acos(clamp(cosAngle, -1.0, 1.0));
    if (d > radius * 1.6) return vec3(0.0);

    float disc = 1.0 - smoothstep(radius * 0.88, radius * 1.04, d);

    // Local disc coordinates: 'x' runs along the terminator axis.
    vec3 up = abs(moonDirW.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(up, moonDirW));
    // Orient the lit limb towards the sun so that phases look plausible.
    if (dot(right, sunDirW) < 0.0) right = -right;
    vec3 tangential = normalize(dirW - moonDirW * cosAngle + vec3(1e-6));
    float x = dot(tangential, right) / radius;

    // moonPhase 0 = full moon in Minecraft, 4 = new moon.
    float phaseNew = 0.5 - 0.5 * cos(float(moonPhase) / 8.0 * TAU);
    float k = phaseNew * 2.0 - 1.0;
    float lit = smoothstep(-0.10, 0.10, x - k);
    lit *= (1.0 - smoothstep(0.85, 1.05, abs(x)));

    // Crater / maria detail, stable in world space.
    float craters = 0.80 + 0.20 * fbm2D(tangential.xz * 80.0 + tangential.y * 60.0, 4);
    return vec3(1.0, 0.985, 0.95) * disc * lit * craters * 2.1;
}

vec3 starField(vec3 dirW, float visibility) {
    if (visibility <= 0.001) return vec3(0.0);
    // Project the sphere onto a grid; every cell may hold one star.
    vec3 p = dirW * 220.0;
    vec3 cell = floor(p);
    vec3 f = fract(p);
    vec3 rnd = hash33(cell);
    if (rnd.z < 0.90) return vec3(0.0);
    vec3 centre = 0.25 + 0.5 * hash33(cell + 7.3);
    float d = length(f - centre);
    float radius = 0.035 + 0.05 * rnd.x;
    float star = 1.0 - smoothstep(radius * 0.4, radius, d);
    // twinkle: slow, small amplitude, no temporal noise
    float tw = 0.75 + 0.25 * sin(frameTimeCounter * (1.1 + rnd.y * 2.3) + rnd.x * 30.0);
    float temp = mix(0.55, 1.0, rnd.y);
    vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.94, 0.83), temp);
    return tint * star * tw * 7.0 * visibility;
}

vec3 milkyWay(vec3 dirW, float visibility) {
    if (visibility <= 0.001) return vec3(0.0);
    // A tilted band across the sky, modulated with fbm for the dust lanes.
    vec3 axis = normalize(vec3(0.32, 0.82, -0.47));
    float band = 1.0 - smoothstep(0.0, 0.28, abs(dot(dirW, axis)));
    if (band <= 0.001) return vec3(0.0);
    vec2 uv = vec2(atan(dirW.z, dirW.x) * 1.6, dirW.y * 4.0);
    float dust = fbm2D(uv * 3.0 + 5.0, 5);
    float brightness = band * band * smoothstep(0.35, 0.85, dust);
    return mix(vec3(0.20, 0.24, 0.38), vec3(0.55, 0.55, 0.68), dust) * brightness * visibility * 0.35;
}

vec3 aurora(vec3 dirW, float visibility) {
    if (visibility <= 0.001 || dirW.y < 0.02) return vec3(0.0);
    float t = frameTimeCounter * 0.03;
    vec3 col = vec3(0.0);
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        vec2 uv = dirW.xz / max(dirW.y, 0.06) * (0.35 + fi * 0.22);
        float ribbon = fbm2D(uv * 1.4 + vec2(t * (0.6 + fi * 0.3), fi * 4.7), 4);
        ribbon = smoothstep(0.55, 0.95, ribbon);
        float curtain = smoothstep(0.15, 0.85, dirW.y) * (1.0 - smoothstep(0.55, 1.0, dirW.y));
        vec3 tint = mix(vec3(0.10, 0.95, 0.55), vec3(0.35, 0.35, 1.0), fi / 2.0);
        col += tint * ribbon * curtain * 0.35;
    }
    return col * visibility;
}

//==============================================================================
// lighting helpers derived from the sky model
//==============================================================================

// Colour of the direct sunlight after travelling through the atmosphere.
vec3 sunlightColor(vec3 sunDirW, vec3 worldPos) {
    vec3 transmittance = sunTransmittance(worldPos, sunDirW);
    vec3 base = vec3(1.0, 0.985, 0.96) * 12.0;
    return base * transmittance;
}

// Analytic fit of the sky's zenith / horizon colours. Running the full
// raymarch for every lit pixel would be wasteful, so the *ambient* term uses
// this fit which tracks the raymarched sky closely for the two dominant
// colours (zenith and horizon).
void skyGradientColors(vec3 sunDirW, out vec3 zenith, out vec3 horizon) {
    float e = sunDirW.y;
    float day = smoothstep(-0.14, 0.10, e);
    float airMass = 1.0 / max(e + 0.12, 0.045);
    vec3 extinction = exp(-vec3(0.30, 0.55, 1.25) * airMass * 0.15);

    // Night: deep blue with a hint of moonlight.
    vec3 zenithNight = vec3(0.008, 0.013, 0.030);
    vec3 horizonNight = vec3(0.016, 0.022, 0.038);

    vec3 zenithDay = vec3(0.10, 0.26, 0.66) * mix(vec3(1.0), extinction, 0.45);
    vec3 horizonDay = vec3(0.52, 0.58, 0.66) * extinction;

    zenith = mix(zenithNight, zenithDay, day);
    horizon = mix(horizonNight, horizonDay, day);

    // Twilight warm band right above the horizon.
    float twilight = exp(-abs(e) * 9.0) * (1.0 - smoothstep(0.05, 0.35, e));
    horizon += vec3(0.55, 0.22, 0.06) * twilight * 0.85;
    zenith += vec3(0.10, 0.05, 0.10) * twilight * 0.35;
}

// Approximate hemispherical sky irradiance around a world space normal.
// Cheap (a handful of exps) and stable, which matters because it is evaluated
// for every lit fragment in the world.
vec3 skyAmbient(vec3 normalW, vec3 sunDirW) {
    vec3 zenith;
    vec3 horizon;
    skyGradientColors(sunDirW, zenith, horizon);

    float up = saturate(normalW.y * 0.5 + 0.5);
    vec3 sky = mix(horizon * 0.72, zenith, up);

    // Moon and stars contribute a small amount of ambient at night.
    float night = 1.0 - smoothstep(-0.12, 0.08, sunDirW.y);
    sky += vec3(0.020, 0.026, 0.040) * night;

    // Ground bounce (multiple scattering approximation).
    vec3 bounce = vec3(0.030, 0.026, 0.020) * (0.4 + 0.6 * smoothstep(-0.1, 0.3, sunDirW.y));
    sky += bounce * saturate(-normalW.y * 0.5 + 0.5);

    return sky * (1.0 - rainStrength * 0.35);
}

#endif // HYPERREAL_ATMOSPHERE_GLSL
