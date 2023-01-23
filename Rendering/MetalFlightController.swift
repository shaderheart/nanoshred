//
//  MetalFlightControl.swift
//  swiftui-test
//
//  Created by utku on 22/09/2022.
//

import Foundation
import Metal

let maxBuffersInFlight = 3

protocol GPUFlightProtocol: AnyObject {
    var targetID: UUID { get set }
    var flightIndex: Int { get set }
    
    func moveNext()
    func reset(device: MTLDevice, keepingCapacity: Bool)
}

class WeakFlight {
  weak var value : GPUFlightProtocol?
  init (value: GPUFlightProtocol) {
    self.value = value
  }
}

var flightList: [UUID : WeakFlight] = [:]


class FlyingGPUBuffer<T>: GPUFlightProtocol {
    var targetID: UUID
    var flightIndex = 0
    var flightCount = maxBuffersInFlight
    
    var rawSizePerFlight = 0
    var bytesPerElement = 0
    var itemsPerFlight = 0
    var initItemCount = 0
    var flightStride = 0
    var backingBuffers: [MTLBuffer] = []
    var bufferView: UnsafeMutablePointer<T>
    var lastBufferView: UnsafeMutablePointer<T>
    
    private var bufferOptions: MTLResourceOptions = [.storageModeShared, .hazardTrackingModeUntracked]
    
    var count = 0
    
    init(device: MTLDevice, elements: Int, flights: Int = maxBuffersInFlight, cpuReadsAllowed: Bool = false) {
        if !cpuReadsAllowed {
            bufferOptions.insert(.cpuCacheModeWriteCombined)
        }
        initItemCount = elements
        flightCount = flights
        itemsPerFlight = elements
        bytesPerElement = MemoryLayout<T>.stride
        rawSizePerFlight = bytesPerElement * elements
        flightStride = ((rawSizePerFlight) + 0xFF) & -0x100
        for _ in 0..<flightCount {
            if let backingBuffer = device.makeBuffer(length: flightStride, options: bufferOptions) {
                backingBuffers.append(backingBuffer)
            }
        }
        bufferView = UnsafeMutableRawPointer(backingBuffers[0].contents()).bindMemory(to: T.self, capacity: itemsPerFlight)
        lastBufferView = bufferView
        targetID = UUID()
        flightList[targetID] = WeakFlight(value: self)
    }
    
    deinit {
        flightList.removeValue(forKey: targetID)
    }
    
    func reset(device: MTLDevice, keepingCapacity: Bool = false) {
        count = 0
        if !keepingCapacity {
            resize(device: device, elements: initItemCount, keepValues: false)
        }
    }
    
    func resize(device: MTLDevice, elements: Int, keepValues: Bool = true) {
        Renderer.bufferSemaphore.wait()
        
        rawSizePerFlight = bytesPerElement * elements
        flightStride = ((rawSizePerFlight) + 0xFF) & -0x100
        var newBuffers = [MTLBuffer]()
        for _ in 0..<flightCount {
            if let newBuffer = device.makeBuffer(length: flightStride,  options: bufferOptions) {
                newBuffers.append(newBuffer)
            }
        }

        if keepValues {
            let copySize = (elements > itemsPerFlight ? itemsPerFlight : elements) * MemoryLayout<T>.stride
            
            for fi in 0..<flightCount {
                newBuffers[fi].contents().copyMemory(from: backingBuffers[fi].contents(), byteCount: copySize)
            }
        }
        
        backingBuffers = newBuffers
        itemsPerFlight = elements
        bufferView = UnsafeMutableRawPointer(backingBuffers[flightIndex].contents()).bindMemory(to: T.self, capacity: itemsPerFlight)
        lastBufferView = bufferView
        
        Renderer.bufferSemaphore.signal()
    }
    
    func append(from: UnsafePointer<T>, count: Int = 1){
        while self.itemsPerFlight < (self.count + count) {
            resize(device: Renderer.staticDevice, elements: self.itemsPerFlight * 2)
        }
        backingBuffers[flightIndex].contents()
            .advanced(by: self.count * MemoryLayout<T>.stride)
            .copyMemory(from: from, byteCount: count * MemoryLayout<T>.stride)
        self.count += count
    }
    
    func appendAll(from: UnsafePointer<T>, count: Int = 1){
        while self.itemsPerFlight < (self.count + count) {
            resize(device: Renderer.staticDevice, elements: self.itemsPerFlight * 2)
        }
        for fi in 0..<flightCount {
            backingBuffers[fi].contents()
                .advanced(by: self.count * MemoryLayout<T>.stride)
                .copyMemory(from: from, byteCount: count * MemoryLayout<T>.stride)
        }
        self.count += count
    }
    
    func moveNext() {
        flightIndex = (flightIndex + 1) % flightCount
        lastBufferView = bufferView
        bufferView = UnsafeMutableRawPointer(backingBuffers[flightIndex].contents()).bindMemory(to: T.self, capacity: itemsPerFlight)
    }
    
    func bindToVertexSlot(renderEncoder: MTLRenderCommandEncoder, manager: Renderer.RendererBindingManager, slot: Int, offset: Int = 0){
        manager.bindVertexBuffer(cmd: renderEncoder, slot: slot, buffer: backingBuffers[flightIndex], offset: offset * bytesPerElement)
    }
    
    func bindToVertexSlot(renderEncoder: MTLRenderCommandEncoder, slot: Int, offset: Int = 0){
        renderEncoder.setVertexBuffer(backingBuffers[flightIndex], offset: offset * bytesPerElement, index: slot)
    }
    
    func bindToFragmentSlot(renderEncoder: MTLRenderCommandEncoder, manager: Renderer.RendererBindingManager, slot: Int, offset: Int = 0){
        manager.bindFragmentBuffer(cmd: renderEncoder, slot: slot, buffer: backingBuffers[flightIndex], offset: offset * bytesPerElement)
    }
    
    func bindToComputeSlot(computeEncoder: MTLComputeCommandEncoder, manager: Renderer.RendererBindingManager, slot: Int, offset: Int = 0){
        manager.bindComputeBuffer(cmd: computeEncoder, slot: slot, buffer: backingBuffers[flightIndex], offset: offset * bytesPerElement)
    }
    
}

class FlyingRenderTarget: GPUFlightProtocol {
    var targetID: UUID
    var flightIndex = 0
    var flightCount: Int

    var targets: [MTLTexture] = []
    var currentTarget: MTLTexture!
    var previousTarget: MTLTexture!
    
    let descriptor: MTLTextureDescriptor
    
    func reset(device: MTLDevice, keepingCapacity: Bool = false) {
        
    }
    
    init(device: MTLDevice, descriptor: MTLTextureDescriptor, flights: Int = maxBuffersInFlight) {
        flightCount = flights
        self.descriptor = descriptor
        if descriptor.width != 0 && descriptor.height != 0 {
            for _ in 0 ..< flightCount {
                targets.append(device.makeTexture(descriptor: descriptor)!)
            }
            currentTarget = targets[0]
            previousTarget = targets[flightCount - 1]
        }
        
        targetID = UUID()
        flightList[targetID] =  WeakFlight(value: self)
    }
    
    deinit {
        flightList.removeValue(forKey: targetID)
    }
    
    func moveNext() {
        flightIndex = (flightIndex + 1) % flightCount
        previousTarget = currentTarget
        currentTarget = targets[flightIndex]
    }
}

struct TexConvenience {
    static let defaultRenderTargetFormat = MTLPixelFormat.bgra8Unorm_srgb
    static let defaultDepthStencilTargetFormat = MTLPixelFormat.depth32Float_stencil8
    static let defaultDepthTargetFormat = MTLPixelFormat.depth16Unorm

    private static func generateTargetDescriptor(width: Int, height: Int, depth: Int = 1,
                                                 arrayLength: Int = 1, memoryless: Bool = false,
                                                 isCube: Bool = false, hasMips: Bool = false) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = isCube ? .typeCube : .type2D
        descriptor.width = width
        descriptor.height = height
        descriptor.allowGPUOptimizedContents = true
        descriptor.storageMode = memoryless ? .memoryless : .private
        descriptor.depth = depth
        descriptor.arrayLength = arrayLength
        descriptor.mipmapLevelCount = hasMips ? 8 : 1
        descriptor.usage = memoryless ? [.renderTarget] : [.renderTarget, .shaderRead, .shaderWrite]
        return descriptor
    }
    
    static func createDefaultRenderTargetDescriptor(width: Int, height: Int,
                                                    formatOverride: MTLPixelFormat = defaultRenderTargetFormat,
                                                    memoryless: Bool = false) -> MTLTextureDescriptor {
        let descriptor = generateTargetDescriptor(width: width, height: height, memoryless: memoryless)
        descriptor.pixelFormat = formatOverride
        return descriptor
    }
    
    static func createCubemapResourceDescriptor(width: Int, height: Int,
                                      formatOverride: MTLPixelFormat = defaultRenderTargetFormat,
                                                memoryless: Bool = false, hasMips: Bool = true) -> MTLTextureDescriptor {
        let descriptor = generateTargetDescriptor(width: width, height: height, memoryless: memoryless, isCube: true, hasMips: hasMips)
        descriptor.pixelFormat = formatOverride
        return descriptor
    }
    
    static func createDefaultDepthTargetDescriptor(width: Int, height: Int, enableStencil: Bool = true) -> MTLTextureDescriptor {
        let descriptor = generateTargetDescriptor(width: width, height: height)
        descriptor.pixelFormat = enableStencil ? defaultDepthStencilTargetFormat : defaultDepthTargetFormat
        return descriptor
    }
}


struct RenderPassOptions {
    var createRenderTargets = true
    var renderTargetCount = 1
    
    var createDepthTarget = true
    var stencilEnable = true
    var resizeWithFramebuffer = true
    var scaleFactor = 1.0
    var isCubemap = false
    var hasMips = false
    
    var targetFormats: [MTLPixelFormat] = []
    var targetMemoryless: [Bool] = []
    
    
}

class RenderPassObject: GPUFlightProtocol {
    
    var targetID: UUID
    var flightIndex: Int = 0
    
    var options: RenderPassOptions
    
    var renderTargets: [FlyingRenderTarget] = []
    var depthTarget: FlyingRenderTarget?
    
    var passDescriptors: [MTLRenderPassDescriptor] = []
    var currentPassDescriptor: MTLRenderPassDescriptor!
    
    func reset(device: MTLDevice, keepingCapacity: Bool = false) {
        
    }
    
    init(device: MTLDevice, options: RenderPassOptions, width: Int, height: Int) {
        if (!options.createRenderTargets && !options.createDepthTarget) {
            fatalError("You can't create an empty renderpass!")
        }
        
        let passWidth = width == 0 ? 1 : width
        let passHeight = height == 0 ? 1 : height

        self.options = options
        targetID = UUID()
        flightList[targetID] = WeakFlight(value: self)
        
        initializePassWithSize(device: device, width: passWidth, height: passHeight)
    }
    
    func initializePassWithSize(device: MTLDevice, width: Int, height: Int) {
        let passDescriptor = MTLRenderPassDescriptor()

        let passWidth = width == 0 ? 1 : Int(Double(width) * options.scaleFactor)
        let passHeight = height == 0 ? 1 : Int(Double(height) * options.scaleFactor)
        
        /// clear state
        renderTargets.removeAll()
        depthTarget = nil
        passDescriptors.removeAll()
        
        /// create targets
        if options.createRenderTargets {
            for rti in 0 ..< options.renderTargetCount {
                let pixelFormat = (options.targetFormats.count <= rti) ? TexConvenience.defaultRenderTargetFormat : options.targetFormats[rti]
                let memoryless = (options.targetMemoryless.count <= rti) ? false : options.targetMemoryless[rti]
                var descriptor: MTLTextureDescriptor!
                if options.isCubemap {
                    descriptor = TexConvenience.createCubemapResourceDescriptor(width: passWidth, height: passHeight,
                                                                                formatOverride: pixelFormat,
                                                                                memoryless: memoryless, hasMips: options.hasMips)
                } else {
                    descriptor = TexConvenience.createDefaultRenderTargetDescriptor(width: passWidth, height: passHeight,
                                                                                        formatOverride: pixelFormat,
                                                                                        memoryless: memoryless)
                }
                
                let target = FlyingRenderTarget(device: device, descriptor: descriptor)
                renderTargets.append(target)
                
                passDescriptor.colorAttachments[rti].clearColor = .init(red: 0, green: 0, blue: 0, alpha: 0.0)
                passDescriptor.colorAttachments[rti].loadAction = memoryless ? .dontCare : .clear
                passDescriptor.colorAttachments[rti].storeAction = memoryless ? .dontCare : .store
            }
        }
        
        if options.createDepthTarget {
            let descriptor = TexConvenience.createDefaultDepthTargetDescriptor(width: passWidth, height: passHeight, enableStencil: options.stencilEnable)
            depthTarget = FlyingRenderTarget(device: device, descriptor: descriptor)
            
            passDescriptor.depthAttachment.clearDepth = 1.0
            passDescriptor.depthAttachment.loadAction = .clear
            passDescriptor.depthAttachment.storeAction = .store
            if options.stencilEnable {
                passDescriptor.stencilAttachment.clearStencil = 0
                passDescriptor.stencilAttachment.loadAction = .clear
                passDescriptor.stencilAttachment.storeAction = .store
            }
        }
        
        /// update descriptor
        for rpi in 0..<maxBuffersInFlight {
            let flyingDescriptor = passDescriptor.copy() as! MTLRenderPassDescriptor
            
            if options.createRenderTargets {
                for (rti, rt) in renderTargets.enumerated() {
                    flyingDescriptor.colorAttachments[rti].texture = rt.targets[rpi]
                    flyingDescriptor.renderTargetArrayLength = options.isCubemap ? 6 : 0
                }
            }

            if options.createDepthTarget {
                flyingDescriptor.depthAttachment.texture = depthTarget!.targets[rpi]
                if options.stencilEnable {
                    flyingDescriptor.stencilAttachment.texture = depthTarget!.targets[rpi]
                }
            }
            
            passDescriptors.append(flyingDescriptor)
        }
        
        currentPassDescriptor = passDescriptors[0]
        
    }
    
    deinit {
        flightList.removeValue(forKey: targetID)
    }
    
    func moveNext() {
        flightIndex = (flightIndex + 1) % maxBuffersInFlight
        currentPassDescriptor = passDescriptors[flightIndex]
    }
    
}
