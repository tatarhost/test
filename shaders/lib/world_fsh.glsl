/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/world_fsh.glsl

    Fragment shader for every world program (terrain, entities, hand, ...).

    Variants (defined by the program file):
      WORLD_ALPHA_TEST  cutout geometry needs an alpha test
      WORLD_WATER       translucent pass: water surface + glass / ice
      WORLD_UNLIT       geometry without lighting information
    ---------------------------------------------------------------------------
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/shadows.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/sky.glsl"
#include "/lib/clouds.glsl"
#include "/lib/brdf.glsl"
#include "/lib/materials.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/varyings.glsl"
#include "/lib/gbuffer_out.glsl"

void main() {
    vec4 albedoRaw = texture(gtexture, vTexCoord);

#ifdef WORLD_ALPHA_TEST
    if (albedoRaw.a < 0.1) discard;
#endif

    vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec3 viewPos = screenToView(screenUV, gl_FragCoord.z);
    vec3 worldPos = viewToWorldPos(viewPos);
    vec3 worldViewDir = normalize(viewToWorldDir(viewPos));   // camera -> fragment
    vec3 Vw = -worldViewDir;                                  // fragment -> camera
    vec3 Vv = normalize(-viewPos);                            // same, in view space

    vec3 sunDirW = getSunDirWorld();
    vec3 lightColor = shadowLightColor();

    //------------------------------------------------------------------ geometry
    SurfaceGeom geom;
    geom.normal = normalize(vNormal.xyz);
    geom.tangent = vTangent.xyz;
    vec3 bitan = cross(geom.normal, geom.tangent) * (vTangent.w < 0.0 ? -1.0 : 1.0);
    geom.bitangent = (dot(geom.tangent, geom.tangent) > 0.001) ? bitan : vec3(0.0);
    geom.texcoord = vTexCoord;
    geom.lmcoord = vLmCoord;
    geom.midBlock = vec4(vMidBlock, 0.0);
    geom.blockId = vBlockId;
    geom.viewPos = viewPos;
    geom.isHand = vHand > 0.5;

    float normalStrengthOut = 0.0;
    Material m = buildMaterial(geom, albedoRaw, normalStrengthOut);
    applyWetness(m, wetness);

    //===================================================================== opaque
#ifdef WORLD_UNLIT
    // Geometry without a lightmap (items, lines, glint): keep it readable but
    // still influenced by the time of day.
    vec3 unlit = shadeUnlit(m.albedo, vLmCoord, m.emissive);
    writeGBuffer(albedoRaw.a, unlit, m.viewNormal, MAT_EFFECT, vLmCoord, m.emissive,
                 m.wetness, m.roughness, m.metallic, m.subsurface, vHand);
    return;
#else
    float NdotL = dot(m.viewNormal, getLightDirView());
    float shadow = getShadowVisibility(viewPos, m.viewNormal, NdotL, getLightDirView());
    shadow *= cloudShadowFactor(worldPos, sunDirW);

    vec3 sunIrr = skyAmbient(m.worldNormal, sunDirW);
    vec3 color = shadeSurface(m, viewPos, sunIrr, shadow);

#ifdef WORLD_EFFECT
    // Particles and other transient geometry: lit, but excluded from the
    // screen space effects that would look wrong on them.
    writeGBuffer(albedoRaw.a, color, m.viewNormal, MAT_EFFECT, vLmCoord, m.emissive,
                 0.0, m.roughness, m.metallic, m.subsurface, vHand);
#else
    writeGBuffer(1.0, color, m.viewNormal, MAT_OPAQUE, vLmCoord, m.emissive,
                 m.wetness, m.roughness, m.metallic, m.subsurface, vHand);
#endif
#endif
}
