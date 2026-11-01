#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0

    Rain and snow. Lit by the lightmap so that rain in a cave stays dark, with
    a small amount of forward scattering when looking towards the sun.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/varyings.glsl"
#include "/lib/gbuffer_out.glsl"

void main() {
    vec4 tex = texture(gtexture, vTexCoord);
    if (tex.a < 0.02) discard;

    float skyL = lightCurve(skyLightLevel(vLmCoord));
    float blockL = lightCurve(blockLightLevel(vLmCoord));

    vec3 albedo = srgbToLinear(tex.rgb);
    vec3 light = vec3(0.62, 0.68, 0.78) * (0.18 + 0.9 * skyL)
               + vec3(1.0, 0.62, 0.30) * blockL * 0.35;

    vec3 color = albedo * light;
    writeGBuffer(tex.a, color, normalize(vNormal.xyz), MAT_EFFECT, vLmCoord,
                 0.0, 1.0, 0.35, 0.0, 0.0, vHand);
}
