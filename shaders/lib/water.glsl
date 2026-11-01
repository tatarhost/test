/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/water.glsl

    Ocean / river / lake surface model.

      * wave height      : 5 directional sine waves (a compact Gerstner sum)
      * wave normal      : analytic derivatives of the same sum, so the shaded
                           normal always matches the displaced geometry
      * ripple detail    : two scrolling noise samples for capillary waves
      * absorption       : Beer-Lambert tint based on the water column
      * caustics         : animated cellular pattern projected on the bottom

    The waves only displace vertices vertically and depend solely on the
    world XZ position, which keeps the water mesh watertight: every vertex of a
    water column moves by exactly the same amount.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_WATER_GLSL
#define HYPERREAL_WATER_GLSL

const vec3 WATER_ABSORPTION = vec3(0.55, 0.13, 0.075);   // per block
const vec3 WATER_SCATTER    = vec3(0.012, 0.075, 0.105);

// Wave definition: direction (xz), frequency, amplitude, speed, phase
const vec2 W0 = vec2( 1.00,  0.18);
const vec2 W1 = vec2( 0.62, -0.78);
const vec2 W2 = vec2(-0.35,  0.94);
const vec2 W3 = vec2( 0.91,  0.41);
const vec2 W4 = vec2(-0.77, -0.63);

float waterTime() { return frameTimeCounter * WATER_WAVE_SPEED; }

// Wave height in blocks (world space).
float waterWaveHeight(vec3 worldPos) {
#ifdef WATER_WAVES
    float t = waterTime();
    vec2 p = worldPos.xz;
    float h = 0.0;
    h += sin(dot(p, W0) * 0.62 + t * 1.05) * 0.052;
    h += sin(dot(p, W1) * 1.13 + t * 1.47) * 0.031;
    h += sin(dot(p, W2) * 1.91 + t * 1.92) * 0.017;
    h += sin(dot(p, W3) * 2.87 + t * 2.35) * 0.009;
    h += sin(dot(p, W4) * 4.31 + t * 2.81) * 0.0045;
    // slow swell so the surface never looks perfectly periodic
    h *= 0.75 + 0.25 * valueNoise2D(p * 0.09 + t * 0.08);
    return h * WATER_WAVE_HEIGHT;
#else
    return 0.0;
#endif
}

// World space normal of the wave surface.
vec3 waterWaveNormal(vec3 worldPos) {
    vec3 n = vec3(0.0, 1.0, 0.0);
#ifdef WATER_WAVES
    float t = waterTime();
    vec2 p = worldPos.xz;
    float dhdx = 0.0;
    float dhdz = 0.0;

    dhdx += cos(dot(p, W0) * 0.62 + t * 1.05) * 0.052 * 0.62 * W0.x;
    dhdz += cos(dot(p, W0) * 0.62 + t * 1.05) * 0.052 * 0.62 * W0.y;
    dhdx += cos(dot(p, W1) * 1.13 + t * 1.47) * 0.031 * 1.13 * W1.x;
    dhdz += cos(dot(p, W1) * 1.13 + t * 1.47) * 0.031 * 1.13 * W1.y;
    dhdx += cos(dot(p, W2) * 1.91 + t * 1.92) * 0.017 * 1.91 * W2.x;
    dhdz += cos(dot(p, W2) * 1.91 + t * 1.92) * 0.017 * 1.91 * W2.y;
    dhdx += cos(dot(p, W3) * 2.87 + t * 2.35) * 0.009 * 2.87 * W3.x;
    dhdz += cos(dot(p, W3) * 2.87 + t * 2.35) * 0.009 * 2.87 * W3.y;
    dhdx += cos(dot(p, W4) * 4.31 + t * 2.81) * 0.0045 * 4.31 * W4.x;
    dhdz += cos(dot(p, W4) * 4.31 + t * 2.81) * 0.0045 * 4.31 * W4.y;

    float scale = WATER_WAVE_HEIGHT * 10.0;
    n = normalize(vec3(-dhdx * scale, 1.0, -dhdz * scale));
#endif
    return n;
}

// Small scale capillary ripples, added on top of the analytic waves in the
// fragment stage. Returns a world space normal perturbation.
vec3 waterRippleNormal(vec3 worldPos, vec2 uv) {
#ifdef WATER_WAVES
    float t = frameTimeCounter * WATER_WAVE_SPEED;
    vec2 u1 = worldPos.xz * 0.055 + vec2(t * 0.021, t * 0.012);
    vec2 u2 = worldPos.xz * 0.11 + vec2(-t * 0.017, t * 0.026);
    float e = 1.0 / 256.0;
    float n1 = texture(noisetex, u1).r;
    float n1x = texture(noisetex, u1 + vec2(e, 0.0)).r - n1;
    float n1z = texture(noisetex, u1 + vec2(0.0, e)).r - n1;
    float n2 = texture(noisetex, u2).b;
    float n2x = texture(noisetex, u2 + vec2(e, 0.0)).b - n2;
    float n2z = texture(noisetex, u2 + vec2(0.0, e)).b - n2;
    vec3 perturb = vec3(-(n1x + n2x * 1.4), 0.0, -(n1z + n2z * 1.4));
    return normalize(vec3(0.0, 1.0, 0.0) + perturb * 26.0 * WATER_WAVE_HEIGHT);
#else
    return vec3(0.0, 1.0, 0.0);
#endif
}

// Beer-Lambert absorption of the water column above a surface, in blocks.
vec3 waterAbsorption(float thickness) {
    return exp(-WATER_ABSORPTION * max(thickness, 0.0));
}

// Colour of the water body itself (scattering + absorption), as seen from
// above with 'thickness' blocks of water below the surface.
vec3 waterBodyColor(float thickness, vec3 lightColor) {
    vec3 scatter = WATER_SCATTER * (lightColor * 0.35 + vec3(0.02, 0.05, 0.08));
    vec3 absorbed = scatter * (1.0 - waterAbsorption(thickness));
    return absorbed * mix(0.35, 1.0, saturate(thickness / 6.0));
}

//==============================================================================
// caustics
//==============================================================================

// Animated cellular caustics for the sea / river floor.
float caustics(vec3 worldPos) {
#ifdef WATER_CAUSTICS
    float t = frameTimeCounter * 0.55;
    vec2 p = worldPos.xz * 1.35;

    // Two warped cellular layers, the second one slower and larger.
    vec2 warp1 = vec2(sin(t * 0.7 + p.y * 0.35), cos(t * 0.6 + p.x * 0.31)) * 0.55;
    vec2 warp2 = vec2(cos(t * 0.4 + p.y * 0.22), sin(t * 0.5 + p.x * 0.27)) * 0.85;

    vec2 c1 = worley2D(p * 1.0 + warp1);
    vec2 c2 = worley2D(p * 0.63 + warp2 + 17.0);

    // Caustic filaments live where two cells nearly touch.
    float f1 = 1.0 - smoothstep(0.0, 0.32, c1.y - c1.x);
    float f2 = 1.0 - smoothstep(0.0, 0.42, c2.y - c2.x);

    float caustic = pow(f1 * 0.65 + f2 * 0.5, 2.2);
    caustic += pow(max(f1, f2), 6.0) * 0.6;
    return saturate(caustic * 1.6);
#else
    return 0.0;
#endif
}

// Fade caustics out with depth: they are only visible on shallow bottoms.
float causticVisibility(float thickness) {
    return saturate(1.0 - thickness / 14.0) * smoothstep(0.15, 1.2, thickness);
}

#endif // HYPERREAL_WATER_GLSL
