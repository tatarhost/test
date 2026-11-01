/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/water_fsh.glsl

    Fragment shader of the translucent pass.

    Water surface
      * analytic wave normal + capillary ripples
      * Schlick fresnel with F0 = 0.02
      * procedural sky reflection (the screen space reflection is traced later,
        in composite1, where the opaque scene colour is available)
      * sun / moon glints through the shadow map
      * body scattering colour, which composite1 combines with the real water
        column depth stored in the depth buffer

    Glass, ice and other translucent blocks
      * thin dielectric: fresnel weighted reflection + tinted transmission
      * the final composite happens in composite1 as well

    The scene colour (colortex0) is intentionally left untouched here, see
    lib/trans_out.glsl for the reasoning.
    ---------------------------------------------------------------------------
*/

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/space.glsl"
#include "/lib/shadows.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/sky.glsl"
#include "/lib/clouds.glsl"
#include "/lib/brdf.glsl"
#include "/lib/materials.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/varyings.glsl"
#include "/lib/trans_out.glsl"

void main() {
    vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec3 viewPos = screenToView(screenUV, gl_FragCoord.z);
    vec3 worldPos = viewToWorldPos(viewPos);
    vec3 Vw = normalize(-viewToWorldDir(viewPos));
    vec3 Vv = normalize(-viewPos);

    vec3 sunDirW = getSunDirWorld();
    vec3 lightColor = shadowLightColor();

    vec3 nV = normalize(vNormal.xyz);
    float matClass = MAT_GLASS;
    float roughness = 0.05;
    float alpha = 1.0;
    vec3 color = vec3(0.0);
    float scatterOut = 0.0;

    if (isWaterId(vBlockId)) {
        // --------------------------------------------------------- water
        vec3 nW = waterWaveNormal(worldPos);
        vec3 ripple = waterRippleNormal(worldPos, vTexCoord);
        nW = normalize(vec3(nW.x + ripple.x * 0.45, 1.0, nW.z + ripple.z * 0.45));
        nV = normalize(worldToViewDir(nW));

        float NdotV = saturate(dot(nW, Vw));
        float fresnel = 0.02 + 0.98 * pow(1.0 - NdotV, 5.0);

        // Sky reflection. composite1 replaces it with the real screen space
        // reflection wherever a ray hit is available.
        vec3 R = reflect(-Vw, nW);
        R.y = abs(R.y);
        vec3 skyRefl = renderSkyCheap(R) + cloudLayerReflection(R, sunDirW);

        float shadow = getShadowVisibility(viewPos, nV, dot(nV, getLightDirView()), getLightDirView());
        vec3 glint = specularDirect(nV, Vv, getLightDirView(), 0.045, vec3(0.02)) * lightColor * shadow;

        vec3 scatter = waterBodyColor(4.5, lightColor) *
                       (0.55 + 0.45 * lightCurve(skyLightLevel(vLmCoord)));

        // The translucent buffer stores "scatter + sky reflection", composite1
        // adds the screen space reflection and the refracted background using
        // the same fresnel weights (encoded in alpha).
        color = scatter + glint;
        alpha = saturate(0.55 + 0.42 * fresnel);
        matClass = MAT_WATER;
        roughness = 0.04;
    } else {
        // ------------------------------------------------- glass / ice
        Material m = buildMaterial(
            SurfaceGeom(normalize(vNormal.xyz), vTangent.xyz,
                        cross(normalize(vNormal.xyz), vTangent.xyz) * (vTangent.w < 0.0 ? -1.0 : 1.0),
                        vTexCoord, vLmCoord, vec4(vMidBlock, 0.0), vBlockId, viewPos, vHand > 0.5),
            texture(gtexture, vTexCoord), scatterOut);

        vec3 nWorld = m.worldNormal;
        nV = m.viewNormal;
        float NdotV = saturate(dot(nWorld, Vw));
        float fresnel = 0.04 + 0.96 * pow(1.0 - NdotV, 5.0);

        vec3 R = reflect(-Vw, nWorld);
        R.y = abs(R.y);
        vec3 skyRefl = renderSkyCheap(R) + cloudLayerReflection(R, sunDirW);

        float shadow = getShadowVisibility(viewPos, nV, dot(nV, getLightDirView()), getLightDirView());
        vec3 spec = specularDirect(nV, Vv, getLightDirView(), min(m.roughness, 0.12), vec3(0.05))
                  * lightColor * shadow;

        vec3 tint = m.albedo * (0.35 + 0.65 * lightCurve(skyLightLevel(vLmCoord)));
        color = skyRefl * fresnel + tint * 0.85 + spec;
        color *= 0.35 + 0.65 * texture(gtexture, vTexCoord).a;
        alpha = saturate(0.34 + 0.60 * fresnel);
        roughness = min(m.roughness, 0.12);
    }

    writeTranslucent(alpha, color, nV, matClass, vLmCoord, 0.0, 1.0,
                     roughness, 0.0, 0.0, vHand);
}
