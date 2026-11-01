/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/uniforms.glsl

    Game / engine state shared by all programs.
    Only samplers that OptiFine and Iris both provide for *world* programs are
    declared here. Screen space buffers live in lib/buffers.glsl, because
    colortex0-3 cannot be sampled inside gbuffer programs.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_UNIFORMS_GLSL
#define HYPERREAL_UNIFORMS_GLSL

// --- textures ---------------------------------------------------------------
// NOTE: "texture" is a reserved function name in GLSL 330, so only "gtexture"
// is declared. Iris/OptiFine bind both names to the same texture unit.
uniform sampler2D gtexture;     // block / entity texture
uniform sampler2D lightmap;     // vanilla lightmap atlas
uniform sampler2D noisetex;     // 256x256 blue-ish noise
uniform sampler2D normals;      // labPBR normal map (resource pack)
uniform sampler2D specular;     // labPBR specular map (resource pack)

uniform sampler2D shadowtex0;   // shadow depth, includes translucent geometry
uniform sampler2D shadowtex1;   // shadow depth, opaque geometry only
uniform sampler2D shadowcolor0; // shadow colour attachment (translucent tint)

// --- matrices ---------------------------------------------------------------
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

// --- celestial --------------------------------------------------------------
uniform vec3 sunPosition;           // view space, normalised * 100
uniform vec3 moonPosition;          // view space
uniform vec3 shadowLightPosition;   // view space, direction of the shadow caster
uniform vec3 upPosition;            // world up direction in view space
uniform float sunAngle;             // 0 = sunrise, 0.25 = noon, 0.5 = sunset
uniform float shadowAngle;
uniform int   moonPhase;            // 0 = full moon ... 7

// --- camera -----------------------------------------------------------------
uniform vec3  cameraPosition;       // world space camera position (block precision)
uniform vec3  previousCameraPosition;
uniform float far;
uniform float near;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform float eyeAltitude;

// --- world ------------------------------------------------------------------
uniform int   worldTime;            // 0..23999
uniform int   worldDay;
uniform float frameTimeCounter;     // seconds, wraps
uniform float frameTime;
uniform int   frameCounter;
uniform float rainStrength;         // 0..1
uniform float wetness;              // 0..1
uniform float thunderStrength;      // Iris: 0..1
uniform vec4  lightningBoltPosition;

// --- player -----------------------------------------------------------------
uniform int   isEyeInWater;         // 0 = air, 1 = water, 2 = lava, 3 = powder snow
uniform float blindness;
uniform float nightVision;
uniform float screenBrightness;
uniform float playerMood;
uniform int   heldBlockLightValue;
uniform int   heldBlockLightValue2;
uniform vec3  heldBlockLightColor;
uniform int   heldItemId;

// --- lightmap / environment -------------------------------------------------
uniform ivec2 eyeBrightness;       // x = block light, y = sky light (0..240)
uniform ivec2 eyeBrightnessSmooth;
uniform vec3  skyColor;            // vanilla sky colour (used as a fallback)
uniform vec3  fogColor;            // vanilla fog colour
uniform float fogDensity;
uniform int   fogMode;

// --- shadow program ---------------------------------------------------------
uniform float alphaTestRef;

#endif // HYPERREAL_UNIFORMS_GLSL
