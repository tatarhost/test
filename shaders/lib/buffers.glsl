/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/buffers.glsl

    Single source of truth for the render target layout of the pack.

    ---------------------------------------------------------------------------
    Buffer map

     id  format    written by                content
    ---------------------------------------------------------------------------
     0   RGBA16F   gbuffers_*                RGB = HDR scene colour, A = coverage
     1   RGBA16     gbuffers_*                RGB = view space normal (octahedral
                                            encoded), A = material class / 8
     2   RGBA16     gbuffers_*                R = sky light, G = block light,
                                            B = emissive / 4, A = wetness
     3   RGBA16     gbuffers_*                R = roughness, G = metalness,
                                            B = subsurface, A = hand flag
     4   RGBA16F    composite -> composite4   composite  : RGB = SSGI, A = SSAO
                                            composite4 : RGB = bloom bright pass
     5   RGBA16F    composite -> composite5   composite  : RGB = SSR, A = hit
                                            confidence
                                            composite5 : RGB = blurred bloom
     6   RGBA16F    gbuffers_water/glass      RGB = forward translucent colour,
                                            A = coverage
     7   RGBA16F    composite3                RGB = shaded scene after fog and
                                            volumetrics, A = brightness hint

    Why these formats
      * colortex0 and colortex7 carry HDR radiance (sun disc and emissive
        blocks are far above 1.0), 16 bit float keeps the highlights usable
        for the bloom bright pass.
      * colortex1..3 are 16 bit normalised: they store encoded normals, light
        levels in the 0..1 range and small material parameters. 8 bit would
        show banding in the smooth shading of large surfaces, 32 bit would
        waste bandwidth for every pixel of the scene.

    Buffer reuse
      colortex4 and colortex5 are handed to the bloom chain once composite1 has
      consumed the analysis data, so the pack needs only eight colour buffers.
      The chain is strictly forward:

          gbuffers -> composite -> composite1 -> composite2 -> composite3
                   -> composite4 -> composite5 -> final

      which means no program samples a buffer that it writes in the same draw
      call. Framebuffer feedback is what produces black screens on some
      drivers, so the layout is arranged to make it impossible rather than
      merely unlikely.

    Depth buffers (read only, provided by the driver)
      depthtex0  full depth, translucent geometry included
      depthtex1  opaque geometry only
      depthtex2  hand only (used to keep the hand out of the blur chain)
      shadowtex0 / shadowtex1  shadow map with / without translucents

    Clearing
      Every colour buffer keeps the default "clear once per frame" behaviour.
      Disabling clears leaves stale data in the sky, in the void, in the End and
      in areas no geometry covers, which is the usual cause of smeared frames
      after switching dimensions.
    ---------------------------------------------------------------------------

    The declarations below are the format directives read by Iris and OptiFine.
    Both loaders scan the expanded program source line by line for lines that
    start with "const", so the lines have to live in a comment (the GLSL
    compiler has no idea what RGBA16F means) while still being the first token
    on their line. Do not "tidy" this block into single line comments and do
    not indent the const keyword.
*/
/*
const int colortex0Format = RGBA16F; // HDR scene colour
const int colortex1Format = RGBA16;  // encoded normal + material class
const int colortex2Format = RGBA16;  // light levels, emissive, wetness
const int colortex3Format = RGBA16;  // roughness, metalness, subsurface, hand
const int colortex4Format = RGBA16F; // AO + GI, later the bloom bright pass
const int colortex5Format = RGBA16F; // SSR, later the blurred bloom
const int colortex6Format = RGBA16F; // forward translucent colour
const int colortex7Format = RGBA16F; // shaded scene handed to post processing
*/

#ifndef HYPERREAL_BUFFERS_GLSL
#define HYPERREAL_BUFFERS_GLSL

// Number of colour buffers the pack uses; handy for sanity checks and for the
// debug views in final.fsh.
const int HYPERREAL_COLOR_BUFFERS = 8;

#endif // HYPERREAL_BUFFERS_GLSL
