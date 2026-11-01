#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    shadow.fsh

    Depth only pass. Alpha tested geometry (leaves, grass, fences, panes, ...)
    is masked out so foliage casts the correct dappled shadow pattern that the
    light shafts are then built from.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"

in vec2 vTexCoord;
in vec2 vLmCoord;
in float vBlockId;

void main() {
    vec4 albedo = texture(gtexture, vTexCoord);
    if (albedo.a < 0.1) discard;
}
