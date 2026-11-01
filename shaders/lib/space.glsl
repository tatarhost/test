/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/space.glsl

    Coordinate space conversions. All of them are derived from the matrices
    supplied by the shader loader, so they stay correct with any FOV, camera
    roll or shadow setup.

    Spaces:
      screen : uv in [0,1] + hardware depth in [0,1]
      view   : camera space, -Z forward, in blocks
      world  : Minecraft world space
      shadow : normalised [0,1]^3 light clip space of the shadow map
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_SPACE_GLSL
#define HYPERREAL_SPACE_GLSL

vec3 screenToView(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / view.w;
}

vec3 screenToWorld(vec2 uv, float depth) {
    return (gbufferModelViewInverse * vec4(screenToView(uv, depth), 1.0)).xyz + cameraPosition;
}

// Returns (uv.x, uv.y, depth) of a view space position.
vec3 viewToScreen(vec3 viewPos) {
    vec4 clip = gbufferProjection * vec4(viewPos, 1.0);
    vec3 ndc = clip.xyz / clip.w;
    return vec3(ndc.xy * 0.5 + 0.5, ndc.z * 0.5 + 0.5);
}

vec3 viewToWorldDir(vec3 viewDir) {
    return mat3(gbufferModelViewInverse) * viewDir;
}

vec3 worldToViewDir(vec3 worldDir) {
    return mat3(gbufferModelView) * worldDir;
}

vec3 viewToWorldPos(vec3 viewPos) {
    return (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
}

vec3 worldToViewPos(vec3 worldPos) {
    return (gbufferModelView * vec4(worldPos - cameraPosition, 1.0)).xyz;
}

// Normalised view space direction of the ray going through a screen pixel.
vec3 viewRayDir(vec2 uv) {
    vec3 nearPoint = screenToView(uv, 0.0);
    vec3 farPoint  = screenToView(uv, 1.0);
    return normalize(farPoint - nearPoint);
}

// World space direction of the ray going through a screen pixel.
vec3 worldRayDir(vec2 uv) {
    return normalize(viewToWorldDir(viewRayDir(uv)));
}

// Distance from the camera to the fragment at the given depth, in blocks.
float linearDepth(float depth) {
    return abs(viewZFromDepth(depth));
}

#endif // HYPERREAL_SPACE_GLSL
