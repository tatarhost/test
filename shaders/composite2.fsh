#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    composite2.fsh   (pass 3: volumetric clouds)

    Reads the shaded scene from colortex7 and composites the volumetric cloud
    deck over it, writing the result into colortex0.

    The ray is clipped against the scene depth (depthtex0, so water and glass
    also occlude the clouds) which keeps the clouds correctly hidden behind
    terrain, trees and buildings while still being seen above them.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/shadows.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/sky.glsl"
#include "/lib/clouds.glsl"
#include "/lib/composite_common.glsl"

uniform sampler2D colortex7;

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 outColor;

void main() {
    vec2 uv = screenUV();
    vec3 sceneColor = texture(colortex7, uv).rgb;

    vec3 color = sceneColor;

#ifndef CLOUD_DISABLED
    if (isEyeInWater != 1) {
        vec3 dirW = worldRayDir(uv);
        float depth = getDepth0(uv);
        float sceneDist = (depth < 1.0) ? linearDepth(depth) : 1e7;

        float transmittance = 1.0;
        vec3 cloud = raymarchClouds(cameraPosition, dirW, min(sceneDist, 3200.0), transmittance);
        color = sceneColor * transmittance + cloud;
    }
#endif

    outColor = vec4(max(color, vec3(0.0)), 1.0);
}
