#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    composite5.fsh   (pass 6: bloom blur)

    Separable gaussian on the downsampled bright pass. The 13 tap kernel is
    spread over several texels, which combined with the 4x4 downsample of the
    previous pass gives a wide, smooth, cheap bloom.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/composite_common.glsl"

uniform sampler2D colortex4;

/* DRAWBUFFERS:5 */
layout(location = 0) out vec4 outColor;

const float BLOOM_SPREAD = 9.0;

void main() {
    vec2 uv = screenUV();
    vec2 texel = texelSize() * 4.0 * BLOOM_SPREAD;

    vec3 sum = vec3(0.0);
    float wsum = 0.0;

    // 13 tap gaussian, horizontal + vertical in one pass to keep the cost low.
    for (int i = -6; i <= 6; i++) {
        float fi = float(i);
        float w = exp(-fi * fi / 18.0);
        sum += max(texture(colortex4, uv + vec2(fi * texel.x, 0.0)).rgb, vec3(0.0)) * w;
        wsum += w;
    }
    for (int i = -6; i <= 6; i++) {
        float fi = float(i);
        if (i == 0) continue;
        float w = exp(-fi * fi / 18.0);
        sum += max(texture(colortex4, uv + vec2(0.0, fi * texel.y)).rgb, vec3(0.0)) * w;
        wsum += w;
    }

    outColor = vec4(sum / max(wsum, 1e-3), 1.0);
}
