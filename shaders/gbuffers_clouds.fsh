#version 330 compatibility
/*
    HYPERREAL SHADERS v1.0

    Vanilla clouds are disabled (clouds=off in shaders.properties) because the
    pack renders a volumetric cloud deck in the composite stage instead. If a
    user forces vanilla clouds back on through the video settings, this program
    discards them so the two systems never double up.
*/
void main() {
    discard;
}
