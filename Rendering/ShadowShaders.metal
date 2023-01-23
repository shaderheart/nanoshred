//
//  ShadowShaders.metal
//  shred_ios
//
//  Created by utku on 18/01/2023.
//

#include <metal_stdlib>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

struct ShadowVertexOut {
    float4 position [[ position ]];
    uint   layer [[render_target_array_index]];
};

struct DPSMVertexOut {
    float4 position [[ position ]];
    uint   layer [[render_target_array_index]];
};
 

vertex DPSMVertexOut dpsmShadowVertex(constant GenericVertex* vertices [[buffer(0)]],
                                      constant BoneProperties* boneProps [[buffer(BufferIndexMeshBoneProps)]],
                                      constant simd_float4x4* boneMatrices [[buffer(BufferIndexBoneLocations)]],
                                      constant MeshTransform & meshTransform [[ buffer(BufferIndexMeshTransform) ]],
                                      constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
									  constant VertexShaderOptions & options [[ buffer(BufferIndexVertexShaderOptions) ]],
                                      constant int &lightID [[buffer(12)]],
                                      uint vertexIndex [[vertex_id]]
                                      )
{
    GenericVertex in = vertices[vertexIndex];
    const float zNear = 0.1f, zFar = 300.0f;
    DPSMVertexOut vOut;

    float4 position = meshTransform.baseTransform * float4(in.position.xyz, 1.0);
    position /= position.w;

    float vertexLength = length(position.xyz);
    position /= vertexLength;
	position.w = 1.0f - float(position.z <= 0) * 2.0f;
    position.xy = (position.xy / (position.z + 1));
    position.z = position.w * (vertexLength - zNear) / (zFar - zNear);

    vOut.position = position;
	vOut.layer = lightID;
    return vOut;
}

vertex ShadowVertexOut lightShadowVertex(
                                         constant GenericVertex* vertices [[buffer(0)]],
                                         constant BoneProperties* boneProps [[buffer(BufferIndexMeshBoneProps)]],
                                         constant simd_float4x4* boneMatrices [[buffer(BufferIndexBoneLocations)]],
                                         constant MeshTransform & meshTransform [[ buffer(BufferIndexMeshTransform) ]],
                                         constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                                         constant VertexShaderOptions & options [[ buffer(BufferIndexVertexShaderOptions) ]],
                                         constant float4x4 &viewProjection [[buffer(9)]],
                                         constant int &lightID [[buffer(12)]],
                                         uint vertexIndex [[vertex_id]]
                                         )
{
    GenericVertex in = vertices[vertexIndex];

    ShadowVertexOut vOut;
    float4 position = meshTransform.baseTransform * float4(in.position, 1.0);
	if (options.isBoneAnimated){
        BoneProperties props = boneProps[vertexIndex];
        uint32_t boneStart = options.boneOffset;
        float4x4 boneTotal = meshTransform.baseTransform * (	
			boneMatrices[boneStart + props.boneIndices.x] * float(props.boneWeights.x) +
			boneMatrices[boneStart + props.boneIndices.y] * float(props.boneWeights.y) +
			boneMatrices[boneStart + props.boneIndices.z] * float(props.boneWeights.z) +
			boneMatrices[boneStart + props.boneIndices.w] * float(props.boneWeights.w)
		);
        position = boneTotal * float4(in.position, 1.0);
    }
    vOut.position = viewProjection * position;
    vOut.layer = lightID;
    return vOut;
}
