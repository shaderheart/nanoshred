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
