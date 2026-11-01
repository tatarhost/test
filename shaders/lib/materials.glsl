/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/materials.glsl

    Surface / material description.

    Block ids come from block.properties (see ID_* below). When a resource pack
    ships labPBR style maps (suffix "_n" / "_s") they are used for normals,
    roughness, reflectance and emissive masks. Without such a pack the material
    is derived from the block id plus luminance heuristics, so the pack always
    looks correct with vanilla textures.

    The default normal map bound by Iris is a neutral (0.5, 0.5, 1.0) 1x1
    texture and the default specular map is fully black, which makes the
    detection below reliable.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_MATERIALS_GLSL
#define HYPERREAL_MATERIALS_GLSL

// --- block ids, mirrored from block.properties -------------------------------
const float ID_NONE       = 0.0;
const float ID_WATER      = 10000.0;
const float ID_LAVA       = 10001.0;
const float ID_PLANT      = 10010.0;
const float ID_LEAVES     = 10011.0;
const float ID_VINE       = 10012.0;
const float ID_WATERPLANT = 10013.0;
const float ID_LILY       = 10014.0;
const float ID_GLASS      = 10020.0;
const float ID_ICE        = 10021.0;
const float ID_METAL      = 10030.0;
const float ID_GEM        = 10031.0;
const float ID_SNOW       = 10040.0;
const float ID_EMISSIVE   = 10050.0;

bool idIs(float id, float target) { return abs(id - target) < 0.5; }

bool isWaterId(float id)      { return idIs(id, ID_WATER); }
bool isPlantId(float id)      { return idIs(id, ID_PLANT); }
bool isLeavesId(float id)     { return idIs(id, ID_LEAVES); }
bool isVineId(float id)       { return idIs(id, ID_VINE); }
bool isWaterPlantId(float id) { return idIs(id, ID_WATERPLANT); }
bool isGlassId(float id)      { return idIs(id, ID_GLASS); }
bool isIceId(float id)        { return idIs(id, ID_ICE); }
bool isMetalId(float id)      { return idIs(id, ID_METAL); }
bool isGemId(float id)        { return idIs(id, ID_GEM); }
bool isSnowId(float id)       { return idIs(id, ID_SNOW); }
bool isEmissiveId(float id)   { return idIs(id, ID_EMISSIVE) || idIs(id, ID_LAVA); }

//--- material struct ---------------------------------------------------------

struct Material {
    vec3  albedo;       // linear space
    float alpha;
    vec3  viewNormal;   // shaded normal, view space
    vec3  worldNormal;
    float roughness;    // 0 = mirror, 1 = fully diffuse
    float reflectance;  // F0 for dielectrics / albedo for metals
    float metallic;     // 0..1 blend for F0
    float emissive;     // 0..N
    float subsurface;   // 0..1 translucency (leaves, thin plants)
    float wetness;      // 0..1
    vec2  lmcoord;
    float blockId;
    bool  isFoliage;
};

// Geometric (macro) surface derived from the vertex attributes.
struct SurfaceGeom {
    vec3  normal;       // view space geometric normal
    vec3  tangent;      // view space tangent
    vec3  bitangent;    // view space bitangent
    vec2  texcoord;
    vec2  lmcoord;
    vec4  midBlock;
    float blockId;
    vec3  viewPos;
    bool  isHand;
};

//==============================================================================
// helpers
//==============================================================================

// A stable tangent frame from just a normal, used when at_tangent is absent
// (entities, particles, hand).
void buildFrame(vec3 n, out vec3 t, out vec3 b) {
    vec3 up = abs(n.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    t = normalize(cross(up, n));
    b = normalize(cross(n, t));
}

vec3 perturbNormal(SurfaceGeom geom, float strength, out float normalMapStrength) {
    vec3 n = normalize(geom.normal);
    vec3 t = geom.tangent;
    vec3 b = geom.bitangent;
    if (dot(t, t) < 0.01 || dot(b, b) < 0.01) buildFrame(n, t, b);
    vec3 texNormal = texture(normals, geom.texcoord).rgb * 2.0 - 1.0;
    normalMapStrength = length(texNormal.xy);
    texNormal.xy *= strength;
    texNormal.z = sqrt(max(1.0 - dot(texNormal.xy, texNormal.xy), 0.0));
    return normalize(mat3(t, b, n) * normalize(texNormal));
}

//==============================================================================
// material construction
//==============================================================================

// Roughness / reflectance heuristics for vanilla textures.
void heuristicMaterial(float blockId, vec3 albedo, vec2 lmcoord, out float roughness, out float metallic, out float emissive, out float subsurface) {
    float lum = luma(albedo);

    // sensible defaults per surface type
    roughness = 0.78;
    metallic  = 0.0;
    emissive  = 0.0;
    subsurface = 0.0;

    if (isMetalId(blockId)) {
        roughness = 0.28;
        metallic  = 1.0;
    } else if (isGemId(blockId)) {
        roughness = 0.16;
        metallic  = 0.35;
    } else if (isGlassId(blockId)) {
        roughness = 0.06;
        metallic  = 0.0;
    } else if (isIceId(blockId)) {
        roughness = 0.12;
        metallic  = 0.0;
    } else if (isSnowId(blockId)) {
        roughness = 0.55;
        subsurface = 0.35;
    } else if (isPlantId(blockId) || isLeavesId(blockId) || isVineId(blockId) || isWaterPlantId(blockId)) {
        roughness = 0.62;
        subsurface = 1.0;
        metallic  = 0.0;
    } else if (isEmissiveId(blockId)) {
        roughness = 0.55;
        emissive  = 2.2;
    } else {
        // Texture driven fallback: bright smooth blocks (quartz, polished
        // stone, planks) get a lower roughness than dirt / gravel / cobble.
        float textureDetail = abs(albedo.r - albedo.g) + abs(albedo.g - albedo.b);
        roughness = clamp(0.92 - lum * 0.35 - textureDetail * 0.6, 0.35, 0.95);
    }

    // Snow and ice get a subtle sheen.
    if (isIceId(blockId) || isSnowId(blockId)) metallic = 0.05;
}

Material buildMaterial(SurfaceGeom geom, vec4 albedoSrgb, out float normalStrengthOut) {
    Material m;
    m.albedo = srgbToLinear(albedoSrgb.rgb);
    m.alpha  = albedoSrgb.a;
    m.lmcoord = geom.lmcoord;
    m.blockId = geom.blockId;
    m.isFoliage = isPlantId(geom.blockId) || isLeavesId(geom.blockId) ||
                  isVineId(geom.blockId) || isWaterPlantId(geom.blockId);

#ifdef PBR_RESOURCEPACK
    vec4 specSample = texture(specular, geom.texcoord);
    float pbrEvidence = specSample.r + specSample.g + specSample.b + specSample.a;
    bool hasPBR = pbrEvidence > 0.004;

    m.viewNormal = perturbNormal(geom, NORMAL_MAP_STRENGTH, normalStrengthOut);
    if (!hasPBR) normalStrengthOut = 0.0;

    if (hasPBR) {
        m.roughness = clamp(1.0 - specSample.r, 0.015, 1.0) / max(MATERIAL_SMOOTHNESS, 0.01);
        m.metallic  = smoothstep(0.12, 0.75, specSample.g);
        m.emissive  = specSample.a > 0.004 ? specSample.a * 3.0 : 0.0;
        m.subsurface = specSample.b > 0.5 ? (specSample.b - 0.5) * 2.0 : 0.0;
        if (isEmissiveId(geom.blockId)) m.emissive = max(m.emissive, 2.2);
    } else {
        heuristicMaterial(geom.blockId, m.albedo, geom.lmcoord, m.roughness, m.metallic, m.emissive, m.subsurface);
    }
#else
    m.viewNormal = normalize(geom.normal);
    normalStrengthOut = 0.0;
    heuristicMaterial(geom.blockId, m.albedo, geom.lmcoord, m.roughness, m.metallic, m.emissive, m.subsurface);
#endif

    // Glass / ice / water-like dielectrics always keep a tight highlight.
    if (isGlassId(geom.blockId)) { m.roughness = min(m.roughness, 0.08); m.metallic = 0.0; }
    if (isIceId(geom.blockId))   { m.roughness = min(m.roughness, 0.18); }

    // Rock solid default so untextured geometry never turns into a mirror.
    m.roughness = clamp(m.roughness, 0.015, 1.0);
    m.reflectance = 0.04;
    m.wetness = 0.0;
    m.worldNormal = normalize(viewToWorldDir(m.viewNormal));

    return m;
}

// Apply rain wetness: darken, lower roughness and boost the reflectance.
// Only surfaces that are actually exposed to the sky get wet.
void applyWetness(inout Material m, float rainAmount) {
#ifdef WET_RAIN_SURFACES
    float exposure = saturate(m.lmcoord.y * 1.15);
    float wet = saturate(rainAmount) * exposure;
    // porous / vegetation surfaces soak up water instead of becoming glossy
    if (m.isFoliage) wet *= 0.45;
    m.wetness = wet;
    m.albedo *= mix(1.0, 0.62, wet);
    m.roughness = mix(m.roughness, 0.14, wet * 0.85);
    m.reflectance = mix(m.reflectance, 0.055, wet);
#else
    m.wetness = 0.0;
#endif
}

#endif // HYPERREAL_MATERIALS_GLSL
