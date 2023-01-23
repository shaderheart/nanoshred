// 
//  Shaders.metal 
//  metal-modelio 
// 
//  Created by utku on 21/09/2022. 
// 
// File for Metal kernel and shader functions 
#include <metal_stdlib> 
// Including header shared between this Metal shader code and Swift/C code executing Metal API commands 
//
//  ShaderTypes.h
//  metal-modelio
//
//  Created by utku on 21/09/2022.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#define MSL_ATTRIBUTE(x) [[attribute(x)]]
#else
#import <Foundation/Foundation.h>
#define MSL_ATTRIBUTE(x)
#endif

#include <simd/simd.h>

typedef NS_ENUM(NSInteger, BufferIndex)
{
    BufferIndexMeshPositions = 0,
    BufferIndexMeshGenerics  = 1,
    BufferIndexMeshBoneProps = 2,
    BufferIndexBoneLocations = 3,
    BufferIndexUniforms      = 5,
    BufferIndexMeshTransform = 10,
    BufferIndexVertexShaderOptions = 15,
    BufferIndexMaterials = 0
};

typedef NS_ENUM(NSInteger, VertexAttribute)
{
    VertexAttributePosition  = 0,
    VertexAttributeNormal  = 1,
    VertexAttributeTexcoord  = 2,
    VertexAttributeTangent  = 3,
};

typedef NS_ENUM(NSInteger, TextureIndex)
{
    TextureIndexColor    = 0,
    TextureIndexAlbedo = 0,
    TextureIndexNormal = 1,
    TextureIndexPBR = 2,
    TextureIndexEmission = 3,
    TextureIndexEnvironmentIBL = 4,
    TextureIndexAlphaMap = 5,
    TextureIndexEnvironmentReflection = 6,
    TextureIndexLightShadow = 7,
};


typedef struct{
    matrix_float4x4 baseTransform;
    matrix_float4x4 normalTransform;
} MeshTransform;


typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    simd_float3 viewPosition;
    simd_float3 viewDirection;
    simd_float3 tapPosition;
} Uniforms;

typedef struct {
    simd_float3 color;
    simd_float3 emissiveColor;
    float roughness;
    float metallic;
    float emissivePower;
    int albedoTexture;
    int normalTexture;
    int metallicTexture;
    int specularTexture;
    int roughnessTexture;
    int emissiveTexture;

    simd_float2 uvScale;
    
}RenderPBRMaterial;


typedef struct {
    simd_float3 color;
    simd_float3 emissiveColor;
    float roughness;
    float metallic;
    float emissivePower;
    float alphaClipValue;
    int albedoTexture;
    int normalTexture;
    int metallicTexture;
    int roughnessTexture;
    int emissiveTexture;

    simd_float2 uvScale;
    
}AlphaClipMaterial;

typedef struct {
    simd_float3 color;
    float roughness;
    float IOR;
    int albedoTexture;
    int normalTexture;
    int IORTexture;
    int roughnessTexture;
    simd_float2 uvScale;

} RenderGlassMaterial;

typedef struct {
    simd_float3 color;
    float power;
    
    float innerCutoff;
    float outerCutoff;
    
    simd_float4x4 lightViewMatrix;
    simd_float3 worldPosition;
    simd_float3 lightDirection;
    uint type;
} RenderLightMaterial;


typedef struct  {
    uint8_t textureCount;
    uint8_t t1Channel;
    uint8_t t2Channel;
    uint8_t t3Channel;
    uint8_t t4Channel;
}TextureMergeChannels;

typedef struct {
    uint selected_id;
    simd_float3 cursorWorldpos;
}FragmentCpuBuffer;


#pragma pack(push, 1)
typedef struct {
    simd_float3 position MSL_ATTRIBUTE(0);
    simd_float3 normal MSL_ATTRIBUTE(1);
    simd_float2 texcoord_0 MSL_ATTRIBUTE(2);
    simd_float2 texcoord_1 MSL_ATTRIBUTE(3);
    simd_float3 tangent MSL_ATTRIBUTE(4);
    uint8_t materialIndex MSL_ATTRIBUTE(5);
} GenericVertex;

typedef struct {
    simd_float3 position MSL_ATTRIBUTE(0);
    simd_float3 normal MSL_ATTRIBUTE(1);
    simd_float2 texcoord_0 MSL_ATTRIBUTE(2);
    simd_float2 texcoord_1 MSL_ATTRIBUTE(3);
    simd_float3 tangent MSL_ATTRIBUTE(4);
    simd_float4 boneWeights MSL_ATTRIBUTE(5);
    simd_uint4 boneIndices MSL_ATTRIBUTE(6);
    uint8_t materialIndex MSL_ATTRIBUTE(7);
} BoneVertex;

typedef struct {
    simd_float4 boneWeights MSL_ATTRIBUTE(5);
    simd_uint4 boneIndices MSL_ATTRIBUTE(6);
} BoneProperties;
#pragma pack(pop)


typedef struct {
    simd_float3 position;
    simd_float3 normal;
    simd_float2 texcoord_0;
    simd_float2 texcoord_1;
    simd_float3 tangent;
    simd_float3 color;
    simd_float4 boneWeights;
    simd_uint4 boneIndices;
    uint8_t materialIndex;
} UltimateVertexPrototype;



typedef struct {
        float lifetime;
        float currentTime;
        
        simd_float3 startColor;
        simd_float3 endColor;
        
        simd_float3 currentPosition;
        simd_float3 initialVelocity;
        simd_float3 finalVelocity;
        simd_float3 startScale;
        simd_float3 endScale;
    
} SimpleParticle;

typedef struct {
    float lifetime;
    float currentTime;
    uint textureIndex;
    
    simd_float3 colorBegin;
    simd_float3 colorEnd;
    
    simd_float3 currentPosition;
    simd_float3 currentAngles;
    simd_float3 velocityBegin;
    simd_float3 velocityEnd;
    simd_float3 rotationBegin;
    simd_float3 rotationEnd;
    simd_float3 scaleBegin;
    simd_float3 scaleEnd;
    
} TexturedParticle;

typedef struct {
    simd_float3 color;
    simd_float3 position;
    simd_float3 scale;
} SimpleParticleVertex;

typedef struct {
    simd_float3 color;
    simd_float3 position;
    simd_float3 scale;
    uint textureIndex;
    simd_float2 uv;
} TexturedParticleVertex;

typedef struct {
    float deltaTime;
    uint currentParticleCount;
    uint particlesPerThreadGroup;
} SimpleParticleManagerParameters;


typedef struct {
    bool isBoneAnimated;
    bool hasTangents;
    uint boneOffset;
}VertexShaderOptions;

#endif /* ShaderTypes_h */
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


half3 BRDFS( half3 V, half3 L, half3 N, half roughness, half3 f0, half3 diffuseColor)
{
    half3 Kd = diffuseColor;
    half3 Ks = f0;

    half3 H = normalize(L + V);
    half NdotL = clamp(dot(N, L), 0.0h, 1.0h);
    half NdotV = dot(N, V);
    half NdotH = dot(N, H);
    half LdotH = dot(L, H);

    half a_2 = roughness * roughness;
    half NdotL_2 = NdotL * NdotL;
    half NdotV_2 = NdotV * NdotV;
    half NdotH_2 = NdotH * NdotH;
    half OneMinusNdotL_2 = 1.0 - NdotL_2;
    half OneMinusNdotV_2 = 1.0 - NdotV_2;

    half3 Fd = 1.0 - Ks;

    half gamma = clamp(dot(V - N * NdotV, L - N * NdotL), 0.0h, 1.0h);
    half A = 1.0 - 0.5 * (a_2 / (a_2 + 0.33));
    half B = 0.45 * (a_2 / (a_2 + 0.09));
    half C = sqrt(OneMinusNdotL_2 * OneMinusNdotV_2) / max(NdotL, NdotV);

    half3 Rd = Kd * Fd * (A + B * gamma * C) * NdotL;

    half D = NdotH_2 * (a_2 - 1.0) + 1.0;

    half3 Fs = Ks + Fd * exp(-6 * LdotH);

    half G1_1 = 1.0 + sqrt(1.0 + a_2 * (OneMinusNdotL_2 / NdotL_2));
    half G1_2 = 1.0 + sqrt(1.0 + a_2 * (OneMinusNdotV_2 / NdotV_2));
    half G = G1_1 * G1_2;

    half3 Rs = (a_2 * Fs) / (D * D * G * NdotV);

    return Rd + Rs;
}


#endif /* ShaderHelpers_h */
using namespace metal; 
constant bool uvs_defined [[function_constant(1)]]; 
typedef struct 
{ 
    float3 position [[attribute(VertexAttributePosition)]]; 
    float3 normal [[attribute(VertexAttributeNormal)]]; 
//    float2 texCoord [[attribute(VertexAttributeTexcoord), function_constant(uvs_defined)]]; 
    float2 texCoord [[attribute(VertexAttributeTexcoord)]]; 
    float3 tangent [[attribute(VertexAttributeTangent)]]; 
} Vertex; 
typedef struct 
{ 
    float4 position [[position]]; 
    half3 normal; 
    float2 texCoord; 
} ColorInOut; 
// MARK: gBuffer! 
typedef struct { 
    half4 lighting [[color(0), raster_order_group(0)]]; 
    half4 albedoColor [[color(1), raster_order_group(1)]]; 
    half4 normalValue [[color(2), raster_order_group(1)]]; 
    float4 positionValue [[color(3), raster_order_group(1)]]; 
}gBufferOutput; 
struct AccumLightBuffer{ 
    half4 lighting [[color(0), raster_order_group(0)]]; 
}; 
typedef struct 
{ 
    float4 position [[position]]; 
    half3 normal; 
    float3 worldPosition; 
    float2 texCoord; 
    half3 tangent; 
    half3 bitangent; 
} gBufferVertexData; 
inline RenderPBRMaterial alphaClipToPBR(AlphaClipMaterial in){ 
    RenderPBRMaterial out; 
    out.color = in.color; 
    out.emissiveColor = in.emissiveColor; 
    out.roughness = in.roughness; 
    out.metallic = in.metallic; 
    out.emissivePower = in.emissivePower; 
    out.albedoTexture = in.albedoTexture; 
    out.normalTexture = in.normalTexture; 
    out.metallicTexture = in.metallicTexture; 
    out.roughnessTexture = in.roughnessTexture; 
    out.emissiveTexture = in.emissiveTexture; 
    out.uvScale = in.uvScale; 
    return out; 
} 
vertex gBufferVertexData 
genericGBufferVertex( 
                     constant GenericVertex* vertices [[buffer(0)]], 
                     constant BoneProperties* boneProps [[buffer(BufferIndexMeshBoneProps)]], 
                     constant simd_float4x4* boneMatrices [[buffer(BufferIndexBoneLocations)]], 
                     constant MeshTransform & meshTransform [[ buffer(BufferIndexMeshTransform) ]], 
                     constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]], 
                     constant VertexShaderOptions & options [[ buffer(BufferIndexVertexShaderOptions) ]], 
                     uint vertexIndex [[vertex_id]]) 
{ 
    gBufferVertexData out; 
    GenericVertex in = vertices[vertexIndex]; 
    float4 position = meshTransform.baseTransform * float4(in.position, 1.0); 
    half3x3 normalMatrix = half3x3(half3(meshTransform.normalTransform.columns[0].xyz), 
                             half3(meshTransform.normalTransform.columns[1].xyz), 
                             half3(meshTransform.normalTransform.columns[2].xyz) 
                             ); 
    if (options.isBoneAnimated){ 
        BoneProperties props = boneProps[vertexIndex]; 
        uint32_t boneStart = options.boneOffset; 
        float4x4 boneTotal = boneMatrices[boneStart + props.boneIndices.x] * float(props.boneWeights.x) + 
        boneMatrices[boneStart + props.boneIndices.y] * float(props.boneWeights.y) + 
        boneMatrices[boneStart + props.boneIndices.z] * float(props.boneWeights.z) + 
        boneMatrices[boneStart + props.boneIndices.w] * float(props.boneWeights.w); 
        position = boneTotal * float4(in.position, 1.0); 
        normalMatrix = half3x3(half3(boneTotal.columns[0].xyz), 
                               half3(boneTotal.columns[1].xyz), 
                               half3(boneTotal.columns[2].xyz) 
                               ); 
    } 
    out.worldPosition = position.xyz - uniforms.viewPosition; 
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * position; 
    out.texCoord = in.texcoord_0; 
    half tangentLengthSq = dot(in.tangent, in.tangent); 
    out.tangent = normalize(half3((normalMatrix * (half3(in.tangent))).xyz)); 
    out.normal = half3((normalMatrix * (half3(in.normal))).xyz); 
     
    out.bitangent = (half3) (normalMatrix * (half3((tangentLengthSq < 2 ? -1 : 1) * cross(in.normal, in.tangent)))).xyz; 
    return out; 
} 
gBufferOutput pbrCalculator(gBufferVertexData in, 
                            constant Uniforms & uniforms, 
                            RenderPBRMaterial material, 
                            half4 colorSample, 
                            texture2d<half> normalMap, 
                            texture2d<half> pbrMap, 
                            texture2d<half> emissiveMap, 
                            texturecube<half> environmentIBL, 
                            texturecube<half> environmentReflect, 
                            device FragmentCpuBuffer *frag_cpu, 
                            constant uint32_t &hoverUpdateRequested, 
                            constant uint32_t &entityID, 
                            uint primitive_id 
                            ){ 
    gBufferOutput out; 
     
    constexpr sampler colorSampler(mip_filter::linear, 
                                   mag_filter::linear, 
                                   s_address::repeat, 
                                   t_address::repeat, 
                                   r_address::repeat, 
                                   min_filter::linear, 
                                    
                                   (max_anisotropy)16); 
    const half M_RPI_H = 1.0h / M_PI_H; 
     
    half3 emissionSample = half3(material.emissiveColor); 
    half4 normalSample = half4(0, 0, 1, 0); 
    half metalSample = material.metallic; 
    half roughSample = material.roughness; 
    float2 uv = in.texCoord * material.uvScale; 
    if (material.normalTexture >= 0){ 
        normalSample = normalMap.sample(colorSampler, uv.xy) * 2.0f - 1.0f; 
    } 
     
    if (material.metallicTexture >= 0){ 
        metalSample = pbrMap.sample(colorSampler, uv.xy).b; 
    } 
     
    if (material.roughnessTexture >= 0){ 
        roughSample = pbrMap.sample(colorSampler, uv.xy).g; 
    } 
     
    if (material.emissiveTexture >= 0){ 
        emissionSample *= emissiveMap.sample(colorSampler, uv.xy).rgb; 
    } 
    half3x3 tbn = {in.tangent, -in.bitangent, in.normal}; 
    normalSample.xyz = normalize(tbn * normalSample.xyz); 
    half3 viewdir = half3(normalize(in.worldPosition.xyz)); 
     
    half roughSquare = roughSample * roughSample; 
    half3 reflectDirection = -reflect(-viewdir, normalSample.xyz); 
//    half3 vNout = normalize( normalSample.x * in.tangent + normalSample.y * in.bitangent + normalSample.z * in.normal ); 
//    normalSample.xyz = vNout; 
    out.lighting = half4(emissionSample, 1.0h); 
    out.albedoColor = colorSample; 
    out.normalValue = half4(normalSample.xyz, metalSample); 
    out.positionValue = float4(in.worldPosition.xyz, float(roughSample)); 
     
    half3 ibl = environmentIBL.sample(colorSampler, float3(normalSample.xyz)).rgb; 
//    ibl = 0.0; 
    float iblReflectLod = roughSample * 16; 
    float iblReflectPower = 1.0f - (roughSquare); 
    half3 iblReflect = environmentReflect.sample(colorSampler, float3(reflectDirection.xyz), min_lod_clamp(iblReflectLod)).rgb; 
    half3 F0 = half3(0.04); 
    F0 = mix(F0, colorSample.rgb, 1.0h - metalSample); 
    ibl = ibl * F0; 
    half3 h = normalize(viewdir - normalSample.xyz); 
     
    half3 metalColorFactor = mix(half3(1.0), colorSample.rgb, metalSample) * iblReflectPower; 
     
    half dotNV = saturate(dot(normalSample.xyz, viewdir)); 
    half dotLH = saturate(dot(-normalSample.xyz, h)); 
    half3 F = F_Schlick(dotLH, F0); 
    half diffusePower = DisneyDiffuse(dotNV, 1.0, dotLH, roughSquare); 
    half3 denomy = 4.0h * dotNV; 
//    out.lighting.rgb += (diffusePower * colorSample.rgb) * ibl * 0.1h; 
//    out.lighting.rgb += (colorSample.rgb) * 1.0h; 
    out.lighting.rgb += mix(iblReflect * metalColorFactor, ibl, roughSample); 
     
    if (hoverUpdateRequested){ 
        bool cpuBufferIndex = (length_squared(in.position.xy - uniforms.tapPosition.xy) > 1.05); 
        if (!cpuBufferIndex){ 
            FragmentCpuBuffer cpuOut; 
            cpuOut.selected_id = entityID; 
    //        cpuOut.cursorWorldpos = in.wposition.xyz; 
            frag_cpu[0] = cpuOut; 
            out.lighting.rgb += half3(0.5); 
        } 
    } 
    return out; 
} 
[[early_fragment_tests]] 
fragment gBufferOutput gBufferFragment(gBufferVertexData in [[stage_in]], 
                                       constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]], 
                                       constant RenderPBRMaterial & material [[ buffer(BufferIndexMaterials) ]], 
                                       texture2d<half> colorMap     [[ texture(TextureIndexColor) ]], 
                                       texture2d<half> normalMap     [[ texture(TextureIndexNormal) ]], 
                                       texture2d<half> pbrMap     [[ texture(TextureIndexPBR) ]], 
                                       texture2d<half> emissiveMap     [[ texture(TextureIndexEmission) ]], 
                                       texturecube<half> environmentIBL     [[ texture(TextureIndexEnvironmentIBL) ]], 
                                       texturecube<half> environmentReflect     [[ texture(TextureIndexEnvironmentReflection) ]], 
                                       device FragmentCpuBuffer *frag_cpu [[buffer(8)]], 
                                       constant uint32_t &hoverUpdateRequested [[buffer(15)]], 
                                       constant uint32_t &entityID [[buffer(16)]], 
                                       uint primitive_id [[primitive_id]] 
                                       ) 
{ 
    constexpr sampler colorSampler(mip_filter::linear, 
                                   mag_filter::linear, 
                                   s_address::repeat, 
                                   t_address::repeat, 
                                   r_address::repeat, 
                                   min_filter::linear, 
                                   (max_anisotropy)16); 
     
    gBufferOutput out; 
    half4 colorSample; 
    colorSample.a = 1.0f; 
    colorSample.rgb = half3(material.color); 
    float2 uv = in.texCoord * material.uvScale; 
     
    if (material.albedoTexture >= 0){ 
        colorSample = colorMap.sample(colorSampler, uv.xy); 
    } 
         
    out = pbrCalculator(in, uniforms, material, colorSample, normalMap, pbrMap, emissiveMap, environmentIBL, environmentReflect, frag_cpu, hoverUpdateRequested, entityID, primitive_id); 
    return out; 
} 
fragment gBufferOutput gBufferAlphaClippedFragment( 
                                                   gBufferVertexData in [[stage_in]], 
                                       constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]], 
                                       constant AlphaClipMaterial & material [[ buffer(BufferIndexMaterials) ]], 
                                       texture2d<half> colorMap     [[ texture(TextureIndexColor) ]], 
                                       texture2d<half> normalMap     [[ texture(TextureIndexNormal) ]], 
                                       texture2d<half> pbrMap     [[ texture(TextureIndexPBR) ]], 
                                       texture2d<half> emissiveMap     [[ texture(TextureIndexEmission) ]], 
                                       texturecube<half> environmentIBL     [[ texture(TextureIndexEnvironmentIBL) ]], 
                                       texturecube<half> environmentReflect     [[ texture(TextureIndexEnvironmentReflection) ]], 
                                       device FragmentCpuBuffer *frag_cpu [[buffer(8)]], 
                                       constant uint32_t &hoverUpdateRequested [[buffer(15)]], 
                                       constant uint32_t &entityID [[buffer(16)]], 
                                       uint primitive_id [[primitive_id]] 
                                       ) 
{ 
    constexpr sampler colorSampler(mip_filter::linear, 
                                   mag_filter::linear, 
                                   s_address::repeat, 
                                   t_address::repeat, 
                                   r_address::repeat, 
                                   min_filter::linear, 
                                   (max_anisotropy)16); 
     
    gBufferOutput out; 
    RenderPBRMaterial pbrMaterial = alphaClipToPBR(material); 
     
    half4 colorSample; 
    colorSample.a = 1.0f; 
    colorSample.rgb = half3(material.color); 
    float2 uv = in.texCoord * material.uvScale; 
     
    if (material.albedoTexture >= 0){ 
        colorSample = colorMap.sample(colorSampler, uv.xy); 
    } 
     
    if (colorSample.a < material.alphaClipValue){ 
        discard_fragment(); 
    } 
     
    out = pbrCalculator(in, uniforms, pbrMaterial, 
                        colorSample, normalMap, pbrMap, emissiveMap, environmentIBL, environmentReflect, 
                        frag_cpu, hoverUpdateRequested, entityID, primitive_id); 
    return out; 
} 
fragment gBufferOutput gBufferGlassFragment( 
                                            gBufferVertexData in [[stage_in]], 
                                           constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]], 
                                           constant RenderGlassMaterial & material [[ buffer(BufferIndexMaterials) ]], 
                                           texture2d<half> colorMap     [[ texture(TextureIndexColor) ]], 
                                           texture2d<half> normalMap     [[ texture(TextureIndexNormal) ]], 
                                           texture2d<half> pbrMap     [[ texture(TextureIndexPBR) ]], 
                                           texturecube<half> environmentIBL     [[ texture(TextureIndexEnvironmentIBL) ]], 
                                           texturecube<half> environmentReflect     [[ texture(TextureIndexEnvironmentReflection) ]], 
                                           device FragmentCpuBuffer *frag_cpu [[buffer(8)]], 
                                           constant uint32_t &hoverUpdateRequested [[buffer(15)]], 
                                           constant uint32_t &entityID [[buffer(16)]], 
                                           uint primitive_id [[primitive_id]] 
                                       ) 
{ 
    constexpr sampler colorSampler(mip_filter::linear, 
                                   mag_filter::linear, 
                                   s_address::repeat, 
                                   t_address::repeat, 
                                   r_address::repeat, 
                                   min_filter::linear, 
                                   (max_anisotropy)16); 
     
    gBufferOutput out = {0}; 
    float2 uv = in.texCoord * material.uvScale; 
     
    half roughSample = 0.5h; 
    if (material.roughnessTexture >= 0){ 
        roughSample = pbrMap.sample(colorSampler, uv.xy).r; 
    } 
    half perceivedRoughness = roughSample * roughSample; 
     
    half4 colorSample; 
    colorSample.a = 1.0f; 
    colorSample.rgb = half3(material.color); 
     
    half4 normalSample = half4(0, 0, 1, 0); 
    if (material.normalTexture >= 0){ 
        normalSample = normalMap.sample(colorSampler, uv.xy) * 2.0f - 1.0f; 
    } 
     
    if (material.albedoTexture >= 0){ 
        colorSample = colorMap.sample(colorSampler, uv.xy); 
    } 
     
    half3x3 tbn = {in.tangent, in.bitangent, in.normal}; 
    normalSample.xyz = normalize(tbn * normalSample.xyz); 
    half3 viewdir = half3(normalize(in.worldPosition.xyz)); 
    half3 reflectDirection = -reflect(-viewdir, normalSample.xyz); 
    float iblReflectLod = roughSample * 4; 
    float iblReflectPower = 1.0f - (perceivedRoughness * perceivedRoughness); 
    half3 iblReflect = environmentReflect.sample(colorSampler, float3(reflectDirection.xyz), min_lod_clamp(iblReflectLod)).rgb; 
    half3 F0 = half3(0.04); 
    half3 h = normalize(viewdir - normalSample.xyz); 
     
    half3 metalColorFactor = half3(1.0); 
     
    half dotNV = saturate(dot(normalSample.xyz, viewdir)); 
    half dotLH = saturate(dot(-normalSample.xyz, h)); 
    half3 F = F_Schlick(dotLH, F0); 
    out.lighting.rgb = iblReflect * metalColorFactor * 1.0; 
    out.lighting.a = 0.5; 
     
    return out; 
} 
struct VertexOut { 
    float4 position [[ position ]]; 
    float2 uv; 
}; 
vertex VertexOut copy_vertex_function(uint vertexID [[ vertex_id  ]]) { 
    const float3 vertices[6] = { 
        {-1, -1, 0.5}, 
        { 1, -1, 0.5}, 
        {-1,  1, 0.5}, 
        { 1,  1, 0.5}, 
        {-1,  1, 0.5}, 
        { 1, -1, 0.5} 
    }; 
     
    const float2 uvs[6] = { 
        {0, 1}, 
        {1, 1}, 
        {0, 0}, 
        {1, 0}, 
        {0, 0}, 
        {1, 1} 
    }; 
     
    float3 v_pos = vertices[vertexID]; 
    VertexOut vOut; 
    vOut.position = float4(v_pos,1); 
    vOut.uv = uvs[vertexID]; 
    return vOut; 
}; 
float3 whitePreservingLumaBasedReinhardToneMapping(float3 color) 
{ 
    float gamma = 1.6f; 
    float white = 1.; 
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722)); 
    float toneMappedLuma = luma * (1. + luma / (white*white)) / (1. + luma); 
    color *= toneMappedLuma / luma; 
    color = pow(color, float3(1. / gamma)); 
    return color; 
} 
fragment float4 blitFragment(VertexOut vIn [[ stage_in ]], 
                             texture2d<float> inputTexture [[texture(0)]], 
                             texture2d<float> bloomTexture [[texture(1)]] 
                             ) 
{ 
    constexpr sampler s = sampler(mag_filter::linear, 
                                 min_filter::linear, 
                                 s_address::clamp_to_edge, 
                                 t_address::clamp_to_edge, 
                                 r_address::clamp_to_edge, 
                                 mip_filter::linear, 
                                 compare_func::greater_equal); 
    const float gamma = 1.8f; 
    float4 color = float4(inputTexture.sample(s, float2(vIn.uv))); 
    float4 bloom = float4(bloomTexture.sample(s, float2(vIn.uv))); 
     
    color.rgb += bloom.rgb; 
    color.rgb = whitePreservingLumaBasedReinhardToneMapping(pow(color.rgb, gamma)); 
//    color.rgb = cutscene.rgb; 
    return color; 
} 
struct LightVertexOut { 
    float4 position [[ position ]]; 
    float4 wiposition; 
    float2 uv; 
}; 
vertex LightVertexOut lightVertexFunction(Vertex in [[stage_in]], 
                                          constant MeshTransform & meshTransform [[ buffer(BufferIndexMeshTransform) ]], 
                                          constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]] 
                                          ) 
{ 
    float4 position = meshTransform.baseTransform * float4(in.position, 1.0); 
    LightVertexOut vOut; 
    vOut.wiposition = meshTransform.baseTransform * float4(0, 0, 0, 1.0); 
    vOut.position = uniforms.projectionMatrix * uniforms.viewMatrix * position; 
    vOut.uv = in.texCoord; 
     
    return vOut; 
} 
[[early_fragment_tests]] fragment AccumLightBuffer 
pointLightingSinglePass (LightVertexOut vIn [[ stage_in ]], 
                         gBufferOutput gBufferIn, 
                         constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]], 
                         constant RenderLightMaterial &material [[ buffer(BufferIndexMaterials) ]], 
                         depth2d<float, access::sample> shadowMap     [[ texture(TextureIndexLightShadow) ]] 
//                         texture2d<float, access::sample> shadowMap     [[ texture(TextureIndexLightShadow) ]] 
                         ) 
{ 
    constexpr sampler shadowSampler(mip_filter::linear, 
                                   mag_filter::linear, 
                                   s_address::repeat, 
                                   t_address::repeat, 
                                   r_address::repeat, 
                                   min_filter::linear, 
                                    compare_func::greater, 
                                   (max_anisotropy)16); 
     
    AccumLightBuffer output; 
     
    half4 alby = gBufferIn.albedoColor; 
    float4 position = gBufferIn.positionValue; 
     
    half4 normal = gBufferIn.normalValue; 
    half4 pbr = half4(position.w, normal.w, 0.0h, 1.0h); 
    half roughness = pbr.r; 
    half metallic = pbr.g; 
    half3 F0 = half3(0.04); 
    F0 = mix(F0, alby.rgb, metallic); 
     
    half3 lightpos = half3(material.worldPosition - uniforms.viewPosition); 
    half3 lightedPosition = lightpos - half3(position.xyz); 
    half3 lightdir = half3(normalize(lightedPosition)); 
    half3 viewdir = half3(normalize(-position.xyz)); 
    half3 difference = half3(lightedPosition); 
    half dist2 = dot(difference, difference); 
    half dist = sqrt(dist2); 
    half attn = 1.0h / (1.0h + 0.35h * dist + 0.84h * dist2); 
     
    if (material.type == 1) { 
        float4x4 rotation = float4x4(material.lightViewMatrix); 
        float4 shadowPosition = rotation * float4(float3(position.xyz + uniforms.viewPosition), 1.0h); 
        shadowPosition.xyz /= shadowPosition.w; 
        shadowPosition.y = 1.0 - shadowPosition.y; 
        float3 sp_ndc = float3(shadowPosition.xyz); 
        half4 resultg = half4(shadowMap.gather_compare(shadowSampler, sp_ndc.xy, (sp_ndc.z - 0.0009))); 
        half in_shadow = 1.0h - (resultg.x + resultg.y + resultg.z + resultg.w) * 0.25h; 
         
        half theta = dot(lightdir, normalize(half3(material.lightDirection))); 
        if (theta > material.outerCutoff){ 
             
            half divid = 1.0f / max(0.001f, material.innerCutoff - material.outerCutoff); 
            float lightAngleOffset = -material.outerCutoff * divid; 
            float angularAttenuation = saturate(theta * divid + lightAngleOffset); 
            angularAttenuation *= angularAttenuation; 
             
//            half epsilon   = material.outerCutoff - material.innerCutoff; 
//            half intensity = clamp((theta - material.outerCutoff) / epsilon, 0.0, 1.0); 
            attn *= angularAttenuation * in_shadow; 
        } else { 
            attn = 0.0; 
        } 
    } 
     
    half4 outColor = {0}; 
     
    half3 diffuseColor = (1.0 - metallic) * alby.rgb; 
    outColor.rgb = BRDF(viewdir, lightdir, normal.xyz, roughness, F0, diffuseColor.rgb) * attn * material.power * 1.5 * half3(material.color); 
    outColor.rgb = saturate(outColor.rgb); 
    outColor.a = 0.998; 
     
//    if (material.type == 1) { 
//        outColor.rgb = half3(1.0); 
//    } 
     
    output.lighting = outColor; 
    return output; 
} 
[[early_fragment_tests]] fragment AccumLightBuffer 
directionalLightingSinglePass (VertexOut vIn [[ stage_in ]], 
                         gBufferOutput gBufferIn, 
                         constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]], 
                         constant RenderLightMaterial &material [[ buffer(BufferIndexMaterials) ]] 
                         ) 
{ 
     
    AccumLightBuffer output; 
     
    half4 alby = gBufferIn.albedoColor; 
    float4 position = gBufferIn.positionValue; 
    half4 normal = gBufferIn.normalValue; 
    half roughness = position.w; 
    half metallic = normal.w; 
     
    half3 F0 = half3(0.04); 
    F0 = mix(F0, alby.rgb, metallic); 
     
    half3 lightdir = half3(normalize(material.lightDirection)); 
    half3 viewdir = half3(normalize(-position.xyz)); 
    half attn = 1.0h; 
     
    half4 outColor = {0}; 
     
    half3 diffuseColor = (1.0 - metallic) * alby.rgb; 
    outColor.rgb = BRDF(viewdir, lightdir, normal.xyz, roughness, F0, diffuseColor.rgb) * attn * material.power * 1.0 * half3(material.color); 
    outColor.rgb = saturate(outColor.rgb); 
    outColor.a = 0.998; 
     
    output.lighting = outColor; 
    return output; 
} 
struct ParticleVertexOut { 
    float4 position [[ position ]]; 
    float2 uv; 
    half3 color; 
}; 
vertex ParticleVertexOut particleVertexFunction(uint vertexID [[ vertex_id  ]], 
                                                uint instanceID [[ instance_id ]], 
                                                const device SimpleParticleVertex *vertices [[ buffer(0) ]], 
                                                constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]], 
                                                constant float4x4 &invCameraRotation [[buffer(10)]] 
                                                ) 
{ 
    ParticleVertexOut out; 
    auto current = vertices[vertexID / 3]; 
    const float3 triangleExpanders[3] = { 
        float3(0.0f, 0.57735026918666666666666666666666f, 0.0f) * current.scale, 
        float3(-0.5f, -0.28867513459333333333333333333333f, 0.0f) * current.scale, 
        float3(0.5f, -0.28867513459333333333333333333333f, 0.0f) * current.scale, 
    }; 
     
    const float2 triangleUVs[3] = { 
        float2(0.0f, 0.0f), 
        float2(0.0f, 1.0f), 
        float2(1.0f, 0.0f) 
    }; 
     
    float3 basePosition = current.position; 
    uint whichVertex = vertexID % 3; 
    float3 trianglePosition = triangleExpanders[whichVertex]; 
    out.uv = triangleUVs[whichVertex]; 
    out.color = half3(current.color); 
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * ((invCameraRotation * float4(trianglePosition, 1.0)) + float4(basePosition, 0.0f)); 
     
    return out; 
} 
fragment AccumLightBuffer particleFragmentFunction(ParticleVertexOut in [[ stage_in ]], 
                                        texture2d<float> depthTexture [[texture(0)]], 
                                        constant float2& textureSize [[buffer(0)]] 
                                                   ){ 
     
    AccumLightBuffer output; 
    float factor = 0; 
    float3 uvw = float3(in.uv, 1.0f - in.uv.x - in.uv.y); 
    factor = clamp(0.4f - length(uvw - float3(0.333, 0.333, 0.333)), 0.0f, 1.0f); 
    factor *= 4; 
    output.lighting = half4(in.color.r * factor, in.color.g * factor, in.color.b * factor, factor); 
    return output; 
} 
