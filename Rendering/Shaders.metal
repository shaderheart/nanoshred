//
//  Shaders.metal
//  metal-modelio
//
//  Created by utku on 21/09/2022.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"
#import "ShaderHelpers.h"

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

