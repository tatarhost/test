/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/trans_out.glsl

    Outputs of the translucent pass (gbuffers_water).

    Water and glass are NOT blended into the scene colour while the geometry is
    drawn. Writing the G-buffer and the colour with the same blend factor would
    corrupt the normals (OpenGL blends every attachment of the framebuffer), so
    the translucent pass only fills in surface data and the actual compositing
    happens in composite1, where the full depth information is available.

      colortex1 : normal + material class
      colortex2 : light levels / emissive / wetness
      colortex3 : roughness / metallic / subsurface / hand
      colortex6 : RGB = forward shaded translucent colour,
                  A = coverage (water uses a fully deferred path)
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_TRANS_OUT_GLSL
#define HYPERREAL_TRANS_OUT_GLSL

/* DRAWBUFFERS:1236 */
layout(location = 0) out vec4 transNormal;
layout(location = 1) out vec4 transLight;
layout(location = 2) out vec4 transMaterial;
layout(location = 3) out vec4 transColor;

void writeTranslucent(
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
    transNormal   = vec4(encodeNormal(viewNormal), encodeMat(matClass));
    transLight    = vec4(skyLightLevel(lmcoord), blockLightLevel(lmcoord),
                         saturate(emissive * 0.25), saturate(wetness));
    transMaterial = vec4(saturate(roughness), saturate(metallic), saturate(subsurface), handFlag);
    transColor    = vec4(color, alpha);
}

#endif // HYPERREAL_TRANS_OUT_GLSL
