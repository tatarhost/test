/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/world_vsh.glsl

    Common preamble for all world vertex shaders. The program file only has to
    define the variant (VERTEX_WAVE / VERTEX_WATER_WAVE / VERTEX_HAND).
    ---------------------------------------------------------------------------
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/attributes.glsl"
#include "/lib/materials.glsl"
#include "/lib/vegetation.glsl"
#include "/lib/water.glsl"

#define VERTEX_STAGE
#include "/lib/varyings.glsl"

#include "/lib/vsh_main.glsl"
