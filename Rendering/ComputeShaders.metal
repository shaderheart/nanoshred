//
//  ComputeShaders.metal
//  shred_ios
//
//  Created by utku on 29/12/2022.
//

#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

kernel void processSimpleParticles(device SimpleParticle* particles [[buffer(0)]],
                                   constant SimpleParticleManagerParameters& parameters [[buffer(1)]],
                                   device SimpleParticleVertex* particleVertices [[buffer(2)]],
                                   device atomic_uint& deletedParticleCount [[buffer(3)]],
                                   uint particleIndex [[ thread_position_in_grid ]])
{
    auto current = particles[particleIndex];
    current.currentTime += parameters.deltaTime;
    if (current.currentTime > current.lifetime){
//        uint previousCount = atomic_fetch_add_explicit(&deletedParticleCount, 1, memory_order_relaxed);
//        particles[particleIndex] = particles[(parameters.currentParticleCount - previousCount - 1)];
//        return;
    }
    auto timeRatio = (current.currentTime) / (current.lifetime);
    auto currentVelocity = ((current.initialVelocity * (1.0 - timeRatio)) + (current.finalVelocity * (timeRatio)));

    current.currentPosition += currentVelocity * parameters.deltaTime;
    
    particles[particleIndex] = current;
    
    SimpleParticleVertex out;
    out.position = particles[particleIndex].currentPosition;
    out.scale = (current.startScale * (1.0f - timeRatio)) + (current.endScale * timeRatio);
    out.color = (timeRatio) * (current.endColor) + (1.0f - timeRatio) * (current.startColor);
    
    particleVertices[particleIndex] = out;
}
