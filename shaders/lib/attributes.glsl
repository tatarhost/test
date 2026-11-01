/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/attributes.glsl

    Extra vertex attributes provided by Iris / OptiFine.
      mc_Entity     : x = block id (from block.properties), y = render type
      mc_midTexCoord: centre of the sprite the vertex belongs to
      at_tangent    : xyz = tangent, w = handedness
      at_midBlock   : offset of the vertex from the centre of its block
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_ATTRIBUTES_GLSL
#define HYPERREAL_ATTRIBUTES_GLSL

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
attribute vec4 at_tangent;
attribute vec4 at_midBlock;

#endif // HYPERREAL_ATTRIBUTES_GLSL
