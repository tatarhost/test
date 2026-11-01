#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    composite3.fsh   (pass 4: atmosphere, fog, volumetric light)

    Reads the scene with clouds (colortex0), applies the aerial perspective,
    the volumetric light shafts and the underwater medium, and stores the
    result in colortex7.

    Sky pixels are left untouched: the sky shader already contains the full
    atmospheric scattering and adding fog on top would double it.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/shadows.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/sky.glsl"
#include "/lib/clouds.glsl"
#include "/lib/water.glsl"
#include "/lib/fog.glsl"
#include "/lib/composite_common.glsl"

uniform sampler2D colortex0;

/* DRAWBUFFERS:7 */
layout(location = 0) out vec4 outColor;

void main() {
    vec2 uv = screenUV();
    vec3 scene = texture(colortex0, uv).rgb;
    float depth = getDepth0(uv);

    vec3 color = scene;

    if (depth < 1.0) {
        vec3 viewPos = screenToView(uv, depth);
        vec3 dirW = normalize(viewToWorldDir(viewPos));

        FogResult fog = marchFog(viewPos, uv, dirW);
        color = scene * fog.transmittance + fog.color;

        // Underwater caustics projected onto the visible surfaces.
        if (isEyeInWater == 1) {
            vec3 worldPos = viewToWorldPos(viewPos);
            vec3 nW = normalize(viewToWorldDir(getNormalView(uv)));
            float facing = saturate(nW.y);
            float causticAmount = caustics(worldPos) * facing;
            color += causticAmount * shadowLightColor() * 0.09 * waterAbsorption(linearDepth(depth) * 0.35);
        }
    }

    outColor = vec4(max(color, vec3(0.0)), 1.0);
}
