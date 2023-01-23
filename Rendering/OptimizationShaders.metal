//
//  OptimizationShaders.metal
//  swiftui-test
//
//  Created by utku on 24/09/2022.
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#include "ShaderTypes.h"

#define M_PI 3.14159265358979323846264338327950288
sampler s = sampler(mag_filter::linear,
                    min_filter::linear,
                    s_address::clamp_to_edge,
                    t_address::clamp_to_edge,
                    r_address::clamp_to_edge,
                    mip_filter::linear,
                    compare_func::greater_equal,
                    (max_anisotropy)16);

sampler sr = sampler(mag_filter::linear,
                    min_filter::linear,
                    s_address::repeat,
                    t_address::repeat,
                    r_address::repeat,
                    mip_filter::linear,
                    compare_func::greater_equal,
                     (max_anisotropy)16);


kernel void mergeTextures(
                          texture2d<float, access::read> t1 [[texture(0)]],
                          texture2d<float, access::read> t2 [[texture(1)]],
                          texture2d<float, access::read> t3 [[texture(2)]],
                          texture2d<float, access::read> t4 [[texture(3)]],
                          texture2d<float, access::write> target [[texture(4)]],
                          constant TextureMergeChannels& channels [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]
)
{
    float4 newColor = float4(0);
    
    // caution: case fallthrough allowed knowingly!
    switch (channels.textureCount) {
        case 4:
            newColor[0] = t4.read(gid)[channels.t4Channel];
        case 3:
            newColor[1] = t3.read(gid)[channels.t3Channel];
        case 2:
            newColor.g = t2.read(gid).g;
        case 1:
            newColor.r = t1.read(gid).g;
        default:
            break;
    }
    
    target.write(newColor, gid);
    
}


kernel void
minmaxKernel(texture2d<half, access::read_write> texture  [[texture(0)]],
                uint2                               gid      [[thread_position_in_grid]],
                const device float2& minmax [[buffer(0)]])
{
    // Return early if the pixel is out of bounds
    if((gid.x >= texture.get_width()) || (gid.y >= texture.get_height())){
        return;
    }
    
    half4 inColor  = texture.read(gid);
    inColor.rgb = min(half3(inColor.rgb), half3(minmax.y));
    half luminance = (0.299f * inColor.r + 0.587f * inColor.g + 0.114f * inColor.b) > minmax.x;
    inColor.rgb *= luminance;
//    inColor.r = inColor.r > minmax.x ? inColor.r : 0.0h;
//    inColor.g = inColor.g > minmax.x ? inColor.g : 0.0h;
//    inColor.b = inColor.b > minmax.x ? inColor.b : 0.0h;
    texture.write(half4(inColor.rgb, 1.0h), gid);
    
}

struct CubeMapVertexIn {
    float3 position;
};

struct CubeMapVertexOut {
    float4 position [[position]];
    float3 localPosition;
    uint   layer [[render_target_array_index]];
};


vertex CubeMapVertexOut cubemapVertexFunction(const device CubeMapVertexIn* inVertex [[buffer(0)]],
                                              uint vertexID [[ vertex_id  ]],
                                              constant float4x4 &view [[buffer(1)]],
                                              constant float4x4 &projection [[buffer(2)]],
                                              constant uint &layer [[buffer(3)]]
                                              )
{
    const float3 vertices[6] = {
        {-1, -1, -1},
        { 1, -1, -1},
        {-1,  1, -1},
        { 1,  1, -1},
        {-1,  1, -1},
        { 1, -1, -1}
    };
    
    CubeMapVertexOut output;
    output.localPosition = vertices[vertexID];

    float3x3 cutView = float3x3(view.columns[0].xyz,view.columns[1].xyz,view.columns[2].xyz);
    float4 clipPos = projection * float4(output.localPosition, 1.0f);

    output.position = clipPos.xyww;
    
    output.localPosition = cutView * vertices[vertexID];
    output.layer = layer;
    
    return output;
}

fragment float4 cubemapConvolve(CubeMapVertexOut vIn [[ stage_in ]],
                                texturecube<float> inputTexture [[texture(0)]])
{
    float3 normal = normalize(vIn.localPosition);
    normal.y *= -1;

//    return float4(inputTexture.sample(s, normal));

    // the sample direction equals the hemisphere's orientation
  
    float3 irradiance = float3(0.0);
  
    float3 up    = float3(0.0, 1.0, 0.0);
    float3 right = normalize(cross(up, normal));
    up         = normalize(cross(normal, right));

    float sampleDelta = 0.05;
    float nrSamples = 0.0;
    for(float phi = 0.0; phi < 2.0 * M_PI; phi += sampleDelta){
        for(float theta = 0.0; theta < 0.5 * M_PI; theta += sampleDelta){
            // spherical to cartesian (in tangent space)
            float3 tangentSample = float3(sin(theta) * cos(phi),  sin(theta) * sin(phi), cos(theta));
            // tangent space to world
            float3 sampleVec = tangentSample.x * right + tangentSample.y * up + tangentSample.z * normal;

            irradiance += inputTexture.sample(s, sampleVec).rgb * cos(theta) * sin(theta);
            nrSamples++;
        }
    }
    irradiance = M_PI * irradiance * (1.0 / float(nrSamples));
  
    return float4(irradiance, 1.0);
}



float3 uvToXYZ(uint face, float2 uv)
{
    if(face == 0)
        return float3(     1.f,   uv.y,    -uv.x);
    else if(face == 1)
        return float3(    -1.f,   uv.y,     uv.x);
    else if(face == 2)
        return float3(   +uv.x,   -1.f,    +uv.y);
    else if(face == 3)
        return float3(   +uv.x,    1.f,    -uv.y);
    else if(face == 4)
        return float3(   +uv.x,   uv.y,      1.f);
    else {
        return float3(    -uv.x,  +uv.y,     -1.f);
    }
}

float2 dirToUV(float3 dir){
    return float2( 0.5f + 0.5f * atan2(dir.z, dir.x) / M_PI_F, 1.f - acos(dir.y) / M_PI_F );
}

float2 panoramaToCubeMapUV(uint face, float2 texCoord){
    float2 texCoordNew = texCoord*2.0-1.0;
    float3 scan = uvToXYZ(face, texCoordNew);
    float3 direction = normalize(scan);
    float2 src = dirToUV(direction);
    return src;
}

kernel void hdriToCubemap(texture2d<float, access::sample> inputTexture [[texture(0)]],
                          texturecube<float, access::write> outputTexture [[texture(1)]],
                          const device float2& outputSize [[buffer(0)]],
                          const device uint& face [[buffer(1)]],
                          uint2 gid [[thread_position_in_grid]]
                          )
{
    float2 texCoord = (float2(gid)) / outputSize;
    float4 fragmentColor = float4(0.0, 0.0, 0.0, 1.0);
    fragmentColor.rgb = pow(inputTexture.sample(s, panoramaToCubeMapUV(face, texCoord)).rgb, 2.2);
    outputTexture.write(fragmentColor, gid, face);
}

kernel void drawEnvironmentCubemap(texturecube<float, access::sample> inputTexture [[texture(0)]],
                                   texture2d<float, access::read_write> outputTexture [[texture(1)]],
                                   const device float2& outputSize [[buffer(0)]],
                                   const device float4x4& frustumDirections [[buffer(1)]],
                                   uint2 gid [[thread_position_in_grid]]
                          )
{
    float4 sample = outputTexture.read(gid);
    if (sample.a < 1.0f){
        float2 texCoord = (float2(gid)) / outputSize;
        float4 fragmentColor = float4(1.0f);
        
        float3 frustumULD = frustumDirections.columns[0].xyz;
        float3 frustumURD = frustumDirections.columns[1].xyz;
        float3 frustumLLD = frustumDirections.columns[2].xyz;
        float3 frustumLRD = frustumDirections.columns[3].xyz;
        
        float3 directionU = mix(frustumULD, frustumURD, texCoord.x);
        float3 directionL = mix(frustumLLD, frustumLRD, texCoord.x);
        float3 direction = normalize(mix(directionU, directionL, texCoord.y));
        
        fragmentColor.rgb = inputTexture.sample(s, direction).rgb;
        if (any(isnan(sample.rgb))){
            sample.rgb = {0};
        }
        
        outputTexture.write(float4((sample.rgb * sample.a) + (fragmentColor.rgb * (1.0f - sample.a)), 1.0f), gid);
    }
}
