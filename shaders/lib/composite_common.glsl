/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/composite_common.glsl

    Accessors for the G-buffer, shared by all full screen passes.
    colortex0 is deliberately not declared here because some passes read it
    while others write it.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_COMPOSITE_COMMON_GLSL
#define HYPERREAL_COMPOSITE_COMMON_GLSL

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;

vec3  getNormalView(vec2 uv)  { return decodeNormal(texture(colortex1, uv).rgb); }
float getMatClass(vec2 uv)    { return decodeMat(texture(colortex1, uv).a); }
vec3  getLightLevels(vec2 uv) { return texture(colortex2, uv).rgb; }   // sky, block, emissive
float getWetness(vec2 uv)     { return texture(colortex2, uv).a; }
vec3  getMaterial(vec2 uv)    { return texture(colortex3, uv).rgb; }   // roughness, metallic, subsurface
float getHandFlag(vec2 uv)    { return texture(colortex3, uv).a; }

float getDepth0(vec2 uv) { return texture(depthtex0, uv).r; }
float getDepth1(vec2 uv) { return texture(depthtex1, uv).r; }

float linearDepth0(vec2 uv) { return linearDepth(getDepth0(uv)); }
float linearDepth1(vec2 uv) { return linearDepth(getDepth1(uv)); }

vec3 getViewPos0(vec2 uv) { return screenToView(uv, getDepth0(uv)); }
vec3 getViewPos1(vec2 uv) { return screenToView(uv, getDepth1(uv)); }

bool isBackground(vec2 uv) { return getDepth1(uv) >= 1.0; }

vec2 screenUV() { return gl_FragCoord.xy / vec2(viewWidth, viewHeight); }
vec2 texelSize() { return 1.0 / vec2(viewWidth, viewHeight); }

#endif // HYPERREAL_COMPOSITE_COMMON_GLSL
