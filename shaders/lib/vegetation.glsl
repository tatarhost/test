/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/vegetation.glsl

    Procedural wind animation for plants, leaves and water plants.

    The wind field is a smooth function of the world position, so neighbouring
    vertices move coherently and the geometry never tears. It is built from:
      * a slow travelling gust field (large scale fbm),
      * two sine waves at different frequencies and directions,
      * a tiny high frequency flutter for leaves,
    all driven by frameTimeCounter so the motion is frame rate independent.

    Animation is applied in the vertex shader before the transform.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_VEGETATION_GLSL
#define HYPERREAL_VEGETATION_GLSL

// wind direction (world space, normalised)
const vec2 WIND_DIR = vec2(0.82, 0.57);
const vec2 WIND_DIR2 = vec2(-0.42, 0.91);

// Large scale gust multiplier in [0.35 .. 1.35]
float windGust(vec3 worldPos, float t) {
#ifdef WIND_GUSTS
    float g = fbm2D(worldPos.xz * 0.013 + vec2(t * 0.05, -t * 0.031), 3);
    return mix(0.35, 1.35, g);
#else
    return 1.0;
#endif
}

/*
    Returns a world space horizontal offset (xz) for a vegetation vertex.

    worldPos     : world position used as the phase source
    heightFactor : 0 at the base of the plant, 1 at its tip
    strength     : per block kind amplitude scale
    flutter      : extra high frequency detail (leaves)
*/
vec2 windOffset(vec3 worldPos, float heightFactor, float strength, float flutter) {
#ifdef WAVING_PLANTS
    float t = frameTimeCounter * 1.35;
    float gust = windGust(worldPos, t);

    float phase = dot(worldPos.xz, WIND_DIR) * 0.85 + t * 1.25;
    float phase2 = dot(worldPos.xz, WIND_DIR2) * 1.7 + t * 2.15;

    float sway = sin(phase) * 0.65 + sin(phase2 + 1.7) * 0.35;
    vec2 dir = WIND_DIR * 0.75 + WIND_DIR2 * 0.25;

    vec2 offset = dir * sway * gust;

    // high frequency flutter, mostly visible on leaf blocks
    if (flutter > 0.001) {
        float f = sin(t * 5.5 + worldPos.x * 1.7 + worldPos.z * 2.3) *
                  sin(t * 3.1 + worldPos.y * 2.9);
        offset += dir * f * flutter * gust;
    }

    return offset * heightFactor * strength * WIND_STRENGTH;
#else
    return vec2(0.0);
#endif
}

// Per vegetation kind tuning. Returns (strength, flutter, useBlockCentre).
void vegetationParams(float blockId, out float strength, out float flutter, out bool rigid) {
    strength = 0.0;
    flutter = 0.0;
    rigid = false;

    if (isPlantId(blockId)) {
        strength = 0.115;
        flutter = 0.006;
    } else if (isVineId(blockId)) {
        strength = 0.085;
        flutter = 0.004;
    } else if (isWaterPlantId(blockId)) {
#ifdef WAVING_WATER_PLANTS
        strength = 0.16;
        flutter = 0.01;
#endif
    } else if (isLeavesId(blockId)) {
#ifdef WAVING_LEAVES
        strength = 0.052;
        flutter = 0.022;
        rigid = true;
#endif
    }
}

#endif // HYPERREAL_VEGETATION_GLSL
