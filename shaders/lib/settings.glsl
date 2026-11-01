/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/settings.glsl

    Central configuration file.

    Every option below is picked up by the Iris / OptiFine shader option parser:
      * "#define NAME"                      -> boolean toggle
      * "#define NAME value // [a b c]"     -> enumerable / slider option
      * "const <type> name = value; // [..]"-> engine level option (buffer-agnostic)

    Options are grouped into screens inside shaders.properties. The presets
    (LOW / MEDIUM / HIGH / ULTRA / EXTREME / CINEMATIC) only override the
    values that matter for performance, so user edits survive a preset switch
    for everything that the preset does not touch.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_SETTINGS_GLSL
#define HYPERREAL_SETTINGS_GLSL

//==============================================================================
// Engine level constants (handled by the shader loader, not by GLSL logic)
//==============================================================================

const int   shadowMapResolution   = 2048;   // [1024 1536 2048 3072 4096]
const float shadowDistance        = 160.0;  // [96.0 128.0 160.0 192.0 256.0 320.0]
const float sunPathRotation       = -32.0;  // [-60.0 -45.0 -35.0 -32.0 -20.0 0.0 20.0 35.0 45.0 60.0]
const float shadowIntervalSize    = 2.0;    // [1.0 2.0 3.0 4.0]
const bool  shadowHardwareFiltering = false;
const bool  shadowtex1Nearest     = true;

// Vanilla ambient occlusion is replaced by our own screen space solution.
const float ambientOcclusionLevel = 0.0;
const int   noiseTextureResolution = 256;

//==============================================================================
// SHADOWS
//==============================================================================

#define SHADOW_FILTER 2             // [0 1 2 3] 0=1tap 1=4tap 2=9tap rotated 3=17tap disc
#define SHADOW_PCSS
#define SHADOW_SOFTNESS 1.0         // [0.5 0.75 1.0 1.5 2.0 3.0]
#define SHADOW_NORMAL_OFFSET
#define SHADOW_DISTORTION
#define CONTACT_SHADOWS
#define COLORED_SHADOWS             // fake coloured light bleed from stained glass

//==============================================================================
// AMBIENT OCCLUSION / GLOBAL ILLUMINATION
//==============================================================================

#define SSAO
#define SSAO_STRENGTH 1.0           // [0.0 0.5 1.0 1.5 2.0 2.5]
#define SSAO_RADIUS 1.0             // [0.75 1.0 1.5 2.0]
#define SSGI
#define SSGI_STRENGTH 0.9           // [0.0 0.5 0.9 1.5 2.0]

//==============================================================================
// SCREEN SPACE REFLECTIONS
//==============================================================================

#define REFLECTIONS
#define REFLECTION_QUALITY 32       // [16 24 32 48 64] raymarch steps
#define REFLECTION_ROUGH            // jittered rays -> rough reflections

//==============================================================================
// WATER
//==============================================================================

#define WATER_WAVES
#define WATER_WAVE_HEIGHT 1.0       // [0.0 0.25 0.5 1.0 1.5 2.0]
#define WATER_WAVE_SPEED 1.0        // [0.5 0.75 1.0 1.25 1.5]
#define WATER_REFLECTIONS
#define WATER_REFRACTION
#define WATER_CAUSTICS
#define WATER_FOG
#define WATER_FOG_DENSITY 1.0       // [0.5 0.75 1.0 1.5 2.0 3.0]

//==============================================================================
// SKY / ATMOSPHERE / CLOUDS
//==============================================================================

#define ATMOSPHERE_QUALITY 2        // [0 1 2] single scattering integration steps
#define NIGHT_SKY
#define STARS
#define AURORA
#define CLOUDS_VOLUMETRIC
#define CLOUD_QUALITY 2             // [0 1 2 3] raymarch step budget
#define CLOUD_COVERAGE 1.0          // [0.5 0.75 1.0 1.25 1.5]
#define CLOUD_HEIGHT 1.0            // [0.5 0.75 1.0 1.5 2.0]
#define CLOUD_SHADOWS
#define CLOUD_FOG                   // clouds fade into the horizon haze

//==============================================================================
// VOLUMETRIC LIGHT / FOG
//==============================================================================

#define VOLUMETRIC_LIGHT
#define VOLUMETRIC_QUALITY 2        // [0 1 2 3]
#define VOLUMETRIC_FOG
#define FOG_DENSITY 1.0             // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define MORNING_FOG
#define UNDERWATER_GODRAYS

//==============================================================================
// MATERIALS
//==============================================================================

#define PBR_RESOURCEPACK            // labPBR style normal/specular maps
#define NORMAL_MAP_STRENGTH 1.0     // [0.0 0.5 1.0 1.5 2.0]
#define SUBSURFACE_SCATTERING
#define EMISSIVE_BLOCKS
#define WET_SURFACES
#define MATERIAL_SMOOTHNESS 1.0     // [0.5 0.75 1.0 1.25 1.5]

//==============================================================================
// VEGETATION ANIMATION
//==============================================================================

#define WAVING_PLANTS
#define WAVING_LEAVES
#define WAVING_WATER_PLANTS
#define WIND_STRENGTH 1.0           // [0.0 0.5 1.0 1.5 2.0 3.0]
#define WIND_GUSTS

//==============================================================================
// WEATHER
//==============================================================================

#define WET_RAIN_SURFACES
#define LIGHTNING_FLASH

//==============================================================================
// POST PROCESSING
//==============================================================================

#define BLOOM
#define BLOOM_STRENGTH 1.0          // [0.0 0.5 1.0 1.5 2.0 3.0]
#define EXPOSURE 1.0                // [0.4 0.6 0.8 1.0 1.25 1.5 2.0]
#define AUTO_EXPOSURE
#define TONEMAP_MODE 1              // [0 1 2] 0=Reinhard 1=ACES fitted 2=Uchimura
#define COLOR_GRADE 1               // [0 1 2 3] 0=neutral 1=cinematic 2=warm 3=cool
#define SATURATION 1.0              // [0.6 0.8 0.9 1.0 1.1 1.2 1.4]
#define CONTRAST 1.0                // [0.8 0.9 1.0 1.1 1.2]
#define VIGNETTE
#define VIGNETTE_STRENGTH 1.0       // [0.5 0.75 1.0 1.5 2.0]
#define CHROMATIC_ABERRATION
#define LENS_FLARE
#define SHARPEN
#define FILM_GRAIN
#define GRAIN_STRENGTH 1.0          // [0.5 0.75 1.0 1.5 2.0]
#define DEPTH_OF_FIELD
#define DOF_STRENGTH 1.0            // [0.5 0.75 1.0 1.5 2.0]
#define DOF_FOCUS 0.5               // [0.1 0.25 0.5 0.75 1.0]
#define MOTION_BLUR
#define MOTION_BLUR_STRENGTH 1.0    // [0.25 0.5 0.75 1.0 1.5 2.0]

//==============================================================================
// MISC / DEBUG
//==============================================================================

#define HAND_LIGHT                  // dynamic light from the held item
#define DEBUG_VIEW 0                // [0 1 2 3 4 5 6] 0=off

#endif // HYPERREAL_SETTINGS_GLSL
