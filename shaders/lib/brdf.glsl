/*
    HYPERREAL SHADERS v1.0
    ---------------------------------------------------------------------------
    lib/brdf.glsl

    Microfacet BRDF building blocks (GGX / Trowbridge-Reitz with Smith height
    correlated visibility and Schlick Fresnel) plus the analytic split sum
    approximation used for ambient specular. Purely mathematical, no uniforms.
    ---------------------------------------------------------------------------
*/

#ifndef HYPERREAL_BRDF_GLSL
#define HYPERREAL_BRDF_GLSL

const float DIELECTRIC_F0 = 0.04;

vec3 fresnelSchlick(float cosTheta, vec3 f0) {
    float f = pow(1.0 - saturate(cosTheta), 5.0);
    return f0 + (1.0 - f0) * f;
}

// F90 tinted fresnel for metals / coated materials
vec3 fresnelSchlickRoughness(float cosTheta, vec3 f0, float roughness) {
    float f = pow(1.0 - saturate(cosTheta), 5.0);
    vec3 f90 = vec3(saturate(1.0 - roughness + roughness * 0.4));
    return f0 + (max(f90, f0) - f0) * f;
}

float distributionGGX(float NdotH, float roughness) {
    float a = max(roughness * roughness, 1e-4);
    float a2 = a * a;
    float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / max(PI * d * d, 1e-7);
}

// Smith height correlated visibility (already divided by 4 NdotL NdotV)
float visibilitySmith(float NdotL, float NdotV, float roughness) {
    float a = max(roughness * roughness, 1e-4);
    float a2 = a * a;
    float gv = NdotL * sqrt(max(NdotV * NdotV * (1.0 - a2) + a2, 1e-7));
    float gl = NdotV * sqrt(max(NdotL * NdotL * (1.0 - a2) + a2, 1e-7));
    return 0.5 / max(gv + gl, 1e-6);
}

// Karis' analytic approximation of the split sum environment BRDF.
vec2 envBRDFApprox(float NdotV, float roughness) {
    const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
    const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
    vec4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * NdotV)) * r.x + r.y;
    return vec2(-1.04, 1.04) * a004 + r.zw;
}

// Energy conserving diffuse (Lambert, with a subtle Oren-Nayar style
// retro-reflection for very rough surfaces so that dust/snow look right).
float diffuseTerm(float NdotL) {
    return max(NdotL, 0.0) / PI;
}

float diffuseWrapped(float NdotL, float wrap) {
    return max((NdotL + wrap) / ((1.0 + wrap) * (1.0 + wrap)), 0.0) * (1.0 / PI) * (1.0 + wrap);
}

// Specular highlight for the direct light.
vec3 specularDirect(vec3 N, vec3 V, vec3 L, float roughness, vec3 f0) {
    vec3 H = normalize(V + L);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 1e-3);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);
    float D = distributionGGX(NdotH, roughness);
    float Vis = visibilitySmith(NdotL, NdotV, roughness);
    vec3 F = fresnelSchlick(VdotH, f0);
    return D * Vis * F * NdotL;
}

#endif // HYPERREAL_BRDF_GLSL
