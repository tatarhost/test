/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/varyings.glsl

    Shared vertex -> fragment interface. Include after defining VERTEX_STAGE
    in the vertex shader (the fragment shader must not define it).
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_VARYINGS_GLSL
#define HYPERREAL_VARYINGS_GLSL

#ifdef VERTEX_STAGE
    #define VARYING out
#else
    #define VARYING in
#endif

VARYING vec2 vTexCoord;    // block / entity texture coordinate
VARYING vec2 vLmCoord;     // lightmap coordinate
VARYING vec4 vNormal;      // xyz = view space normal, w = unused
VARYING vec4 vTangent;     // xyz = view space tangent, w = handedness
VARYING vec2 vMidUV;       // sprite centre
VARYING vec3 vMidBlock;    // offset from block centre
VARYING float vBlockId;    // block id from block.properties
VARYING float vHand;       // 1.0 for first person geometry

#endif // HYPERREAL_VARYINGS_GLSL
