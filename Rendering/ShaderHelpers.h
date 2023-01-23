//
//  ShaderHelpers.h
//  swiftui-test
//
//  Created by utku on 24/09/2022.
//

#ifndef ShaderHelpers_h
#define ShaderHelpers_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

using namespace metal;

struct PBR_uniform_f {
    float3 lightpos;
    float3 viewpos;
    float3 light_color;
    float light_power;
    float3 ambientColor;
};


inline half DistributionGGX(half3 N, half3 H, half roughness){
    half a2     = pow(roughness, 4.0h);
    half NdotH  = saturate(dot(N, H));
    half NdotH2 = NdotH*NdotH;
    
    half denom = (NdotH2 * (a2 - 1.0h) + 1.0h);
    return a2 / (M_PI_H * denom * denom);
}

inline half GeometrySmith(half NdotV, half NdotL, half roughness){
    half r = (roughness + 1.0h);
    half k = (r*r) / 8.0h;
    half num = NdotV * NdotL;
    half denom = (NdotV * (1.0h - k) + k) * (NdotL * (1.0h - k) + k);
    return num / denom;
}

inline half V_SmithGGXCorrelatedFast(half NoV, half NoL, half roughness) {
    half a = roughness;
    half GGXV = NoL * (NoV * (1.0h - a) + a);
    half GGXL = NoV * (NoL * (1.0h - a) + a);
    return 0.5h / (GGXV + GGXL);
}

inline half3 fresnelSchlick(half cosTheta, half3 F0){
    return F0 + (1.0h - F0) * pow(1.0h - cosTheta, 5.0h);
}

inline half fresnelSchlickDisney(half cosTheta){
    return pow(1.0h - cosTheta, 5.0h);
}

half DisneyDiffuse(half NdotV, half NdotL, half LdotH, half roughness){
    half eBias = mix(0.0h, 0.5h, roughness);
    half eFactor = mix(1.0h, 1.0h / 1.51h, roughness);
    half fd90 = eBias + 2.0h * LdotH * LdotH * roughness;
    half FL = fresnelSchlickDisney(NdotL);
    half FV = fresnelSchlickDisney(NdotV);
    return mix(1.0h, fd90, FL) * mix(1.0h, fd90, FV) * eFactor;
}

half F_Schlick(half u, half f0, half f90) {
    return f0 + (f90 - f0) * pow(1.0 - u, 5.0);
}

half Fd_Burley(half NoV, half NoL, half LoH, half roughness) {
    half f90 = 0.5 + 2.0 * roughness * LoH * LoH;
    half lightScatter = F_Schlick(NoL, 1.0, f90);
    half viewScatter = F_Schlick(NoV, 1.0, f90);
    return lightScatter * viewScatter * (1.0 / M_PI_H);
}


inline half4 pbr_function(half3 color,
                           float3 position,
                           half3 normal,
                           half shadow,
                           half4 pbr,
                           PBR_uniform_f uni,
                           bool attenuate = false) {
    half3 alby = color;
    half3 alpha = 1.0h;
    float3 wpos = position;
    
    const half M_RPI_H = 1.0h / M_PI_H;
    
    float3 viewpos = uni.viewpos;

    half roughness = pbr.r;
    half metallic = pbr.g;
    half ao = pbr.a;
    half3 F0 = half3(0.04h);
    F0 = mix(F0, alby, metallic);

    half3 norm_dir = (normal);
    shadow = 1.0h - shadow;
    
    half3 viewdir = half3(normalize(viewpos - wpos.xyz));
    half3 lightdir = half3(normalize(uni.lightpos - wpos.xyz));
    half3 half_vec = half3(normalize(viewdir + lightdir));
    
    half dist2 = length_squared(uni.lightpos - wpos.xyz);
    half dist = sqrt(dist2);
    half attn = 1.0h / (1.0h + 0.35h * dist + 0.84h * dist2);
    half attenuation = attenuate ? attn : 1.0h;

    half dotNL = saturate(dot(norm_dir, lightdir));
    half dotNV = saturate(dot(norm_dir, viewdir));
    half dotLH = saturate(dot(lightdir, half_vec));

    half ggx_dist = DistributionGGX(norm_dir, half_vec, roughness);
    half g_smith  = V_SmithGGXCorrelatedFast(dotNV, dotNL, roughness);
    half3 fresh = fresnelSchlick(saturate(dot(half_vec, viewdir)), F0);

//    half3 diffusePower = alby * M_RPI_H;
    half3 diffusePower = alby * Fd_Burley(dotNV, dotNL, dotLH, roughness);

    half3 num = ggx_dist * g_smith * fresh;
    half3 denomy = 4.0h * dotNV * dotNL;
    half3 specular_color = num / max(denomy, 0.001h); ;
    specular_color = saturate(specular_color);

    half3 radiance = half3(uni.light_color) * attenuation * uni.light_power;
    half3 light_out = ((diffusePower) + specular_color) * radiance;
    half3 amb = half3(uni.ambientColor) * alby * ao;

    return max(half4(( (light_out * shadow) + amb) * alpha, 1.0h), 0.0h);
}


// google filament functions
half D_GGX(half NdotH, half roughness, const half3 n, const half3 h){
    half3 NxH = cross(n, h);
    half a = NdotH * roughness;
    half k = roughness / (dot(NxH, NxH) + a * a);
    half d = k * k * (1.0 / M_PI_H);
    return max(0.0h, d);
}

half3 F_Schlick(half u, half3 f0){
    return f0 + (half3(1.0f) - f0) * pow(1.0f - u, 5.0f);
}

half V_SmithGGXCorrelated(half NdotV, half NdotL, half a){
    half a2 = a * a;
    half GGXL = NdotV * sqrt((-NdotL * a2 * NdotL) * NdotL + a2);
    half GGXV = NdotL * sqrt((-NdotV * a2 * NdotV) * NdotV + a2);
    return 0.5f / (GGXV + GGXL);
}

half Fd_Lambert(){
    return 1.0h / M_PI_H;
}

inline half3 SimpleLambertian(half3 l, half3 n, half3 f0, half3 diffuseColor){
    half LdotN = max(dot(l, n), 0.0h);
    return LdotN * diffuseColor;

}

half3 BRDF(half3 v, half3 l, half3 n, half roughness, half3 f0, half3 diffuseColor) {
    half3 h = normalize(v + l);

    half NdotV = abs(dot(n, v)) + 1e-5h;
    half NdotL = clamp(dot(n, l), 0.0h, 1.0h);
    half NdotH = clamp(dot(n, h), 0.0h, 1.0h);
    half LdotH = clamp(dot(l, h), 0.0h, 1.0h);

    half a = roughness * roughness;

    half D = D_GGX(NdotH, a, n, h);
    half3 F = F_Schlick(LdotH, f0);
    half V = V_SmithGGXCorrelatedFast(NdotV, NdotL, roughness);

    half3 Fr = (D * V) * F;
//    half3 Fd = diffuseColor * Fd_Lambert();
    half3 Fd = diffuseColor * Fd_Burley(NdotV, NdotL, LdotH, roughness);

    half3 light_out = (Fd + Fr) * NdotL;
    return light_out;
}


#endif /* ShaderHelpers_h */
