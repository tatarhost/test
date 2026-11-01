/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/gbuffer_out.glsl

    Definition of the pack's G-buffer layout and the single function that
    writes it.

      colortex0 : RGB = HDR colour (already lit), A = coverage / blend alpha
      colortex1 : RGB = view space normal (encoded), A = material class / 8
      colortex2 : R = sky light level, G = block light level,
                  B = emissive strength / 4, A = surface wetness
      colortex3 : R = roughness, G = metallic, B = subsurface, A = hand flag

    Material classes (see util.glsl):
      0 = sky / background, 1 = opaque, 2 = water, 3 = translucent (glass, ice),
      4 = effect (weather, particles) - excluded from screen space effects.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_GBUFFER_OUT_GLSL
#define HYPERREAL_GBUFFER_OUT_GLSL

/* DRAWBUFFERS:0123 */
layout(location = 0) out vec4 fragColor0;
layout(location = 1) out vec4 fragColor1;
layout(location = 2) out vec4 fragColor2;
layout(location = 3) out vec4 fragColor3;

void writeGBuffer(
    float alpha,
    vec3 color,
    vec3 viewNormal,
    float matClass,
    vec2 lmcoord,
    float emissive,
    float wetness,
    float roughness,
    float metallic,
    float subsurface,
    float handFlag
) {
    fragColor0 = vec4(color, alpha);
    fragColor1 = vec4(encodeNormal(viewNormal), encodeMat(matClass));
    fragColor2 = vec4(skyLightLevel(lmcoord), blockLightLevel(lmcoord),
                      saturate(emissive * 0.25), saturate(wetness));
    fragColor3 = vec4(saturate(roughness), saturate(metallic), saturate(subsurface), handFlag);
}

#endif // HYPERREAL_GBUFFER_OUT_GLSL
