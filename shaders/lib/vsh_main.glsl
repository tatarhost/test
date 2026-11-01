/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/vsh_main.glsl

    Shared vertex shader for every world program.

    Required defines (set in the program file before including world_vsh.glsl):
      VERTEX_WAVE        apply vegetation wind animation (terrain programs)
      VERTEX_WATER_WAVE  apply water surface displacement (water program)
      VERTEX_HAND        mark the geometry as first person
    ---------------------------------------------------------------------------
*/

void main() {
    vec4 vpos = gl_Vertex;

    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLmCoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vMidUV    = mc_midTexCoord.xy;
    vMidBlock = at_midBlock.xyz;
    vBlockId  = mc_Entity.x;

    vec3 nrm = normalize(gl_NormalMatrix * gl_Normal);
    vec3 tan = mat3(gl_NormalMatrix) * at_tangent.xyz;
    vNormal  = vec4(nrm, 0.0);
    vTangent = vec4(tan, at_tangent.w != 0.0 ? at_tangent.w : 1.0);

    vHand = 0.0;
#ifdef VERTEX_HAND
    vHand = 1.0;
#endif

#if defined(VERTEX_WAVE) || defined(VERTEX_WATER_WAVE)
    // gl_Vertex of world geometry is expressed in world axes, relative to the
    // camera, so both the wave phase and the displacement can be evaluated
    // directly in world space.
    vec3 relWorld = (gbufferModelViewInverse * (gl_ModelViewMatrix * vpos)).xyz;
    vec3 worldPos = relWorld + cameraPosition;
#endif

#ifdef VERTEX_WAVE
    float vegStrength;
    float vegFlutter;
    bool vegRigid;
    vegetationParams(vBlockId, vegStrength, vegFlutter, vegRigid);
    if (vegStrength > 0.0) {
        // Leaves must move as a rigid block, otherwise neighbouring blocks
        // tear apart. Plants use the per-vertex height for the bend.
        vec3 phasePos = vegRigid ? (floor(worldPos) + 0.5) : worldPos;
        float heightFactor = vegRigid ? 1.0 :
            saturate((mc_midTexCoord.y - vTexCoord.y) / max(mc_midTexCoord.y, 0.001));
        vec2 offset = windOffset(phasePos, heightFactor, vegStrength, vegFlutter);
        vpos.x += offset.x;
        vpos.z += offset.y;
    }
#endif

#ifdef VERTEX_WATER_WAVE
    if (isWaterId(vBlockId)) {
        // Depends only on the world XZ position, therefore every vertex of a
        // water column moves identically and the mesh stays watertight.
        vpos.y += waterWaveHeight(worldPos);
    }
#endif

    // Vanilla alpha test hint / lighting are not needed, the fragment stage
    // recomputes everything from the gbuffer.
    gl_Position = ftransform();
}
