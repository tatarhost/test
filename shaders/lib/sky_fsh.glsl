/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/sky_fsh.glsl

    Fragment shader of the sky dome.

    The whole sky (atmosphere, sun, moon, stars, milky way, aurora) is
    evaluated procedurally from the view ray. Clouds are *not* drawn here: they
    are volumetric and occluded by terrain, so they are ray marched in the
    composite stage where the depth buffer is available.
    ---------------------------------------------------------------------------
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/sky.glsl"
#include "/lib/varyings.glsl"
#include "/lib/gbuffer_out.glsl"

void main() {
    vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec3 dirW = normalize(viewToWorldDir(viewRayDir(screenUV)));

    vec3 color = renderSky(dirW);

    // The sky is treated as a fully lit, fully sky-exposed surface so that the
    // composite stages (fog, bloom, exposure) can treat it consistently.
    vec3 upView = normalize(worldToViewDir(vec3(0.0, 1.0, 0.0)));
    writeGBuffer(1.0, color, upView, MAT_SKY, vec2(0.0, 1.0), 0.0, 0.0, 1.0, 0.0, 0.0, 0.0);
}
