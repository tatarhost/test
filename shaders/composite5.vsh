#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0 - full screen pass vertex shader.
    The loader provides a screen covering quad; we only need the texture
    coordinate and pass the position straight through.
*/
out vec2 vUv;
void main() {
    gl_Position = ftransform();
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
