//
//  ParticleSystem.swift
//  swiftui-test
//
//  Created by utku on 19/12/2022.
//

import Foundation
import Metal


class SimpleParticleManager: EngineSystem {
    static var activeParticles = 0
    static var maxParticles = 1_000_000
    static var currentMetalBuffer: UnsafeMutablePointer<SimpleParticle>?
    static var currentMetalFlyingBuffer: FlyingGPUBuffer<SimpleParticle>?
    static var currentMetalVertexBuffer: FlyingGPUBuffer<SimpleParticleVertex>?
    static var currentParticleDeletionBuffer: FlyingGPUBuffer<uint>?
    static let particlesPerThreadGroup = 32

    static func reset(){
        guard let currentBuffer = currentMetalBuffer else {
            return
        }
        
        for i in 0..<activeParticles {
            currentBuffer[i] = SimpleParticle()
        }
        activeParticles = 0
    }
    
    static func dispatch(encoder: MTLComputeCommandEncoder, deltaTime: Double) {
        if let deletionBuffer = currentParticleDeletionBuffer?.bufferView {
            activeParticles -= Int(deletionBuffer[0])
            if activeParticles < 0 {
                activeParticles = 0
            }
            deletionBuffer[0] = 0
        }
        
        if activeParticles > 0 {
            currentMetalFlyingBuffer?.bindToComputeSlot(computeEncoder: encoder, manager: Renderer.bindingManager, slot: 0)
            currentMetalVertexBuffer?.bindToComputeSlot(computeEncoder: encoder, manager: Renderer.bindingManager, slot: 2)
            currentParticleDeletionBuffer?.bindToComputeSlot(computeEncoder: encoder, manager: Renderer.bindingManager, slot: 3)
            
            var params = SimpleParticleManagerParameters()
            params.deltaTime = Float(deltaTime)
            params.currentParticleCount = uint(activeParticles)
            
            let gridSize = MTLSize(width: activeParticles, height: 1, depth: 1)
            params.particlesPerThreadGroup = uint(particlesPerThreadGroup)
            
            encoder.setBytes(&params, length: MemoryLayout.stride(ofValue: params), index: 1)

            let threadgroupSize = MTLSize(width: activeParticles > 512 ? 512 : activeParticles, height: 1, depth: 1)
            
            
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        }
        
        
    }
    
    static func tick(deltaTime: Double, registry: SHRegistry) {
        currentMetalBuffer = currentMetalFlyingBuffer?.bufferView
        
        guard let currentBuffer = currentMetalBuffer else {
            return
        }
        
        var deletionIndices: [Int] = []
        
        for i in 0..<activeParticles {
            let current = currentBuffer[i]
            if current.currentTime >= current.lifetime {
                deletionIndices.append(i)
            }
        }

        for deletionIndex in deletionIndices {
            currentBuffer[deletionIndex] = currentBuffer[activeParticles - 1]
            activeParticles -= 1
        }

        registry.forEach(types: [SimpleParticleComponent.self]) { entity in
            let emitter: SimpleParticleComponent = entity.component()!
            if emitter.enabled {
                // TODO: this will not work properly for slow-emitters.
                let frameEmitCount = min(Int(Double(emitter.emitsPerSecond) * deltaTime), maxParticles - activeParticles)
                for _ in 0..<frameEmitCount {
                    currentBuffer[activeParticles] = emitter.modelParticle.convert(at: entity.transform.global.translation, parentTransform: entity.transform.global)
                    activeParticles += 1
                }
            }
        }
    }
    
    required init() {
        
    }
}
