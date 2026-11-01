/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/lighting.glsl

    Forward lighting model.

    Direct light   : sun or moon, filtered through the shadow map (PCSS),
                     GGX specular + Lambert diffuse + wrapped diffuse for
                     foliage (cheap translucency).
    Ambient        : hemispherical sky irradiance from the atmosphere model,
                     weighted by the Minecraft sky light level and by the
                     screen space AO computed in the composite stage.
    Block light    : warm point-ish light driven by the block light level.
    Hand light     : dynamic light from the item held in the player's hand.
    Emissive       : emissive blocks and emissive labPBR masks.

    Requires (in this order): uniforms, util, space, atmosphere, shadows, brdf,
    materials, sky.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_LIGHTING_GLSL
#define HYPERREAL_LIGHTING_GLSL

//==============================================================================
// light source colours
//==============================================================================

//==============================================================================
// lightmap handling
//==============================================================================

vec3 blockLightColor() {
    // Torches / glowstone / lanterns: warm, slightly orange light.
    return vec3(1.0, 0.58, 0.26) * 1.55;
}

//==============================================================================
// direct light
//==============================================================================

vec3 directLighting(Material m, vec3 viewPos, vec3 lightDirView, vec3 lightColor, float shadow) {
    vec3 N = normalize(m.viewNormal);
    vec3 V = normalize(-viewPos);
    float NdotL = dot(N, lightDirView);

    if (NdotL <= 0.0 && m.subsurface <= 0.0) return vec3(0.0);

    vec3 f0 = mix(vec3(m.reflectance), m.albedo, m.metallic);
    vec3 spec = specularDirect(N, V, lightDirView, m.roughness, f0);

    float diffuse = diffuseTerm(NdotL);
    vec3 color = m.albedo * diffuse;

    // Foliage translucency: wrapped diffuse plus a forward scattering lobe
    // that lights up leaves when looking towards the sun (a very cheap but
    // convincing approximation of subsurface scattering).
    if (m.subsurface > 0.0) {
        float wrap = 0.62;
        float wrapped = diffuseWrapped(NdotL, wrap);
        float forward = pow(saturate(dot(V, -lightDirView)), 3.0) * 0.55;
        vec3 sssColor = m.albedo * mix(vec3(1.0), vec3(1.25, 1.05, 0.62), 0.35);
        color += sssColor * (wrapped * 0.45 + wrapped * forward) * m.subsurface;
    }

    color += spec * (1.0 - m.subsurface * 0.4);
    return color * lightColor * shadow;
}

//==============================================================================
// ambient light
//==============================================================================

vec3 ambientLighting(Material m, vec3 viewPos, vec3 skyIrradiance, float ao) {
    vec3 N = normalize(m.viewNormal);
    vec3 V = normalize(-viewPos);
    float NdotV = max(dot(N, V), 1e-3);

    vec3 f0 = mix(vec3(m.reflectance), m.albedo, m.metallic);
    vec2 ab = envBRDFApprox(NdotV, m.roughness);
    vec3 envSpec = skyIrradiance * (f0 * ab.x + ab.y);

    float skyLevel = lightCurve(skyLightLevel(m.lmcoord));
    float blockLevel = lightCurve(blockLightLevel(m.lmcoord));

    vec3 diffuseAmbient = m.albedo * skyIrradiance * skyLevel;
    // Ambient specular is occluded much less than diffuse.
    vec3 specAmbient = envSpec * skyLevel * mix(0.45, 1.0, ao);

    vec3 blockAmbient = m.albedo * blockLightColor() * blockLevel * (1.0 - m.metallic * 0.6);
    // A small specular response to nearby torches, direction approximated by
    // the view vector so that it always reads as a soft sheen.
    blockAmbient += envSpec * blockLightColor() * blockLevel * 0.12;

    // Night vision and blindness
    float nv = saturate(nightVision);
    diffuseAmbient *= mix(1.0, 3.2, nv);
    blockAmbient *= mix(1.0, 1.6, nv);

    return (diffuseAmbient * ao + specAmbient * ao + blockAmbient) * (1.0 - blindness * 0.85);
}

//==============================================================================
// dynamic hand light
//==============================================================================

vec3 handLight(Material m, vec3 viewPos) {
#ifdef HAND_LIGHT
    int level = max(heldBlockLightValue, heldBlockLightValue2);
    if (level <= 0) return vec3(0.0);
    vec3 toCam = normalize(-viewPos);
    float dist = max(length(viewPos), 0.001);
    float radius = 4.0 + float(level) * 0.7;
    float atten = 1.0 / (1.0 + dist * dist * 0.35);
    atten *= 1.0 - smoothstep(radius * 0.4, radius, dist);
    if (atten <= 0.001) return vec3(0.0);
    vec3 col = heldBlockLightColor;
    if (dot(col, col) < 0.01) col = vec3(1.0, 0.62, 0.32);
    float NdotL = max(dot(normalize(m.viewNormal), toCam), 0.0);
    return m.albedo * col * atten * NdotL * (float(level) / 15.0) * 2.4;
#else
    return vec3(0.0);
#endif
}

//==============================================================================
// full shading entry point
//==============================================================================

/*
    shadeSurface - the single place where a world fragment is lit.

    m          : material (already wetness adjusted)
    viewPos    : fragment position in view space
    sunIrradiance : ambient sky irradiance around the surface normal
    shadow     : sun/moon visibility from the shadow map (0..1)
*/
vec3 shadeSurface(Material m, vec3 viewPos, vec3 sunIrradiance, float shadow) {
    vec3 N = normalize(m.viewNormal);
    vec3 lightDir = getLightDirView();
    vec3 lightColor = shadowLightColor();

    // Surfaces that are strongly shadowed by the lightmap (deep caves,
    // sealed rooms) must not receive direct sunlight outside of the shadow
    // map range either. This is a compromise between correctness (the shadow
    // map has a limited range) and a readable result.
    float skyExposure = smoothstep(0.02, 0.55, skyLightLevel(m.lmcoord));
    float directVisibility = mix(0.15, 1.0, skyExposure);

    vec3 color = directLighting(m, viewPos, lightDir, lightColor, shadow * directVisibility);
    color += ambientLighting(m, viewPos, sunIrradiance, 1.0);
    color += handLight(m, viewPos);
    color += m.albedo * m.emissive;

    return color;
}

// Simplified lighting for full bright / unlit programs (items in hand, lines).
vec3 shadeUnlit(vec3 albedo, vec2 lmcoord, float emissive) {
    float skyLevel = lightCurve(skyLightLevel(lmcoord));
    float blockLevel = lightCurve(blockLightLevel(lmcoord));
    vec3 ambient = vec3(0.055, 0.065, 0.085);
    vec3 sunAmb = vec3(0.9, 0.85, 0.78) * 0.35 * skyLevel;
    vec3 blockAmb = blockLightColor() * blockLevel * 0.35;
    return albedo * (ambient + sunAmb + blockAmb + emissive);
}

#endif // HYPERREAL_LIGHTING_GLSL
