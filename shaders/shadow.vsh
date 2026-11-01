#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    shadow.vsh

    Shadow map vertex stage. The same radial clip space distortion that
    lib/shadows.glsl applies when sampling is applied here, so the shadow map
    spends more texels close to the camera.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/attributes.glsl"

out vec2 vTexCoord;
out vec2 vLmCoord;
out float vBlockId;

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLmCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vBlockId = mc_Entity.x;

    gl_Position = ftransform();

#ifdef SHADOW_DISTORTION
    // g(r) = r * (1 + K * (1 - r)); identical to shadowDistortFactor()
    vec2 ndc = gl_Position.xy / gl_Position.w;
    float r = min(length(ndc), 1.0);
    float factor = 1.0 + 1.0 * (1.0 - r);
    gl_Position.xy *= factor;
#endif
}
