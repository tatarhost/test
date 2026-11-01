#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0

    Un-textured geometry: block selection outlines, hitboxes, debug lines and
    similar overlays. These have no lightmap and no texture, only a vertex
    colour, so they are passed through almost untouched while still respecting
    the time of day.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/varyings.glsl"
#include "/lib/gbuffer_out.glsl"

void main() {
    vec3 color = srgbToLinear(gl_Color.rgb);
    writeGBuffer(gl_Color.a, color, normalize(vNormal.xyz), MAT_EFFECT, vec2(0.0, 1.0),
                 0.0, 0.0, 0.6, 0.0, 0.0, vHand);
}
