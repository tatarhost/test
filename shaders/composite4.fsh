#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    composite4.fsh   (pass 5: bloom, bright pass + downsample)

    Extracts the part of the image above the bloom threshold and softens it with
    a 4x4 box downsample. The wide gaussian in composite5 turns it into the
    final bloom pyramid. colortex4 is reused here: the analysis buffers have
    already been consumed at this point.
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/composite_common.glsl"

uniform sampler2D colortex7;

/* DRAWBUFFERS:4 */
layout(location = 0) out vec4 outColor;

void main() {
    vec2 uv = screenUV();
    vec2 texel = texelSize();

#ifdef BLOOM
    // 4x4 downsample around the pixel centre, weighted with a small tent.
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    for (int y = -1; y <= 2; y++) {
        for (int x = -1; x <= 2; x++) {
            vec2 offset = (vec2(float(x), float(y)) + 0.5) * 4.0 * texel;
            float w = 1.0 - 0.12 * (abs(float(x) + 0.5) + abs(float(y) + 0.5));
            sum += max(texture(colortex7, uv + offset).rgb, vec3(0.0)) * w;
            wsum += w;
        }
    }
    vec3 c = sum / max(wsum, 1e-3);

    float brightness = luma(c);
    // Soft knee threshold, tuned for the linear HDR range of the pack.
    float knee = 0.6;
    float threshold = 1.05;
    float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-4);
    float contribution = max(soft, brightness - threshold) / max(brightness, 1e-3);

    outColor = vec4(c * contribution, 1.0);
#else
    outColor = vec4(0.0, 0.0, 0.0, 1.0);
#endif
}
