#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0

    Textured sky geometry. In the Overworld these are the vanilla sun and moon
    sprites, which the pack replaces with its own procedural celestial bodies
    (see lib/sky.glsl), so they are discarded. Dimensions without skylight (the
    End) keep their vanilla sky texture so the dimension still looks right.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/varyings.glsl"
#include "/lib/gbuffer_out.glsl"

void main() {
    if (eyeBrightnessSmooth.y > 4) discard;

    vec4 tex = texture(gtexture, vTexCoord);
    if (tex.a < 0.02) discard;

    vec3 color = srgbToLinear(tex.rgb);
    vec3 upView = normalize(worldToViewDir(vec3(0.0, 1.0, 0.0)));
    writeGBuffer(1.0, color, upView, MAT_SKY, vec2(0.0, 1.0), 0.0, 0.0, 1.0, 0.0, 0.0, 0.0);
}
