//
//  RendererExtensions.swift
//  swiftui-test
//
//  Created by utku on 24/09/2022.
//

import Foundation

import Metal
import MetalKit
import AVKit


extension Renderer {
    
    func immediateSubmit(callee: (MTLCommandBuffer) -> Void){
        if let commandBuffer = immediateCommandQueue.makeCommandBuffer() {
            callee(commandBuffer)
            commandBuffer.commit()
        }
    }
    
    func mergeTextures(commandBuffer: MTLCommandBuffer,
                       t1: MTLTexture,
                       t2: MTLTexture? = nil,
                       t3: MTLTexture? = nil,
                       t4: MTLTexture? = nil,
                       output: MTLTexture,
                       options: TextureMergeChannels
    ){
        struct statics {
            static var pipelineState: MTLComputePipelineState? = nil
            static var descriptor = MTLComputePassDescriptor()
        }
        
        if statics.pipelineState == nil {
            let library = device.makeDefaultLibrary()
            do {
                statics.pipelineState = try device.makeComputePipelineState(
                    function: library!.makeFunction(name: "mergeTextures")!
                )
            } catch {
                print(error.localizedDescription)
            }
        }
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder(descriptor: statics.descriptor)
        computeEncoder?.setComputePipelineState(statics.pipelineState!)
        computeEncoder?.setTexture(t1, index: 0)
        computeEncoder?.setTexture(t2, index: 1)
        computeEncoder?.setTexture(t3, index: 2)
        computeEncoder?.setTexture(t4, index: 3)
        computeEncoder?.setTexture(output, index: 4)
        
        var cacheOptions = options
        computeEncoder?.setBytes(&cacheOptions, length: MemoryLayout.size(ofValue: cacheOptions), index: 0)

        let threadgroupSize = MTLSizeMake(32, 32, 1);
        var threadgroupCount = MTLSize()
        threadgroupCount.width  = (output.width  + threadgroupSize.width -  1) / threadgroupSize.width;
        threadgroupCount.height = (output.height + threadgroupSize.height - 1) / threadgroupSize.height;
        threadgroupCount.depth = 1;
        
        computeEncoder?.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        
        computeEncoder?.endEncoding()
        
        
    }
    
    func importGLTFBasedMesh(mesh: GenericMesh){
        guard genericMeshes[mesh.name] == nil else {
            return
        }
        
        genericMeshes[mesh.name] = mesh
        for primitive in mesh.primitives {
            RendererCBindings.calculate(primitive)
            
            primitive.vertexBufferOffset = genericVertexBuffer.count
            for vertex in primitive.vertices {
                var vv: GenericVertex = vertex.convert()!
                genericVertexBuffer.append(from: &vv)
            }
            
            if primitive.isBoneAnimated {
                primitive.bonePropertyBufferOffset = bonePropertiesBuffer.count
                for vertex in primitive.vertices {
                    var bps: BoneProperties = vertex.getBoneProperties()
                    bonePropertiesBuffer.append(from: &bps)
                }
            }
            
            primitive.indexBufferOffset = genericIndexBuffer.count
            genericIndexBuffer.appendAll(from: primitive.indices, count: primitive.indices.count)
            
            tryToLoadTexture(textureInfo: primitive.protoMaterial.baseColorTexture, baseDir: mesh.baseDir, forceReload: true, linearColor: false)
            tryToLoadTexture(textureInfo: primitive.protoMaterial.normalTexture, baseDir: mesh.baseDir, forceReload: true, linearColor: true)
            tryToLoadTexture(textureInfo: primitive.protoMaterial.emissiveTexture, baseDir: mesh.baseDir, forceReload: true, linearColor: false)
            tryToLoadTexture(textureInfo: primitive.protoMaterial.metallicRoughnessTexture, baseDir: mesh.baseDir, forceReload: true, linearColor: true)
            
            primitive.material.pbrTexture = textures[primitive.protoMaterial.metallicRoughnessTexture?.texture?.source.reference?.uri ?? ""]
            primitive.material.albedoTexture = textures[primitive.protoMaterial.baseColorTexture?.texture?.source.reference?.uri ?? ""]
            primitive.material.normalTexture = textures[primitive.protoMaterial.normalTexture?.texture?.source.reference?.uri ?? ""]
            primitive.material.emissiveTexture = {
                [unowned self, unowned primitive] in
                self.textures[primitive.protoMaterial.emissiveTexture?.texture?.source.reference?.uri ?? ""]
            }
            
            if let shredderExtras = primitive.protoMaterial.extras?["shredder"] as? [String: Any] {
                if let _ = shredderExtras["model"] as? String {
                    primitive.material.shadingModel = .glass
                    mesh.containsGlassPrimitives = true
                }
                
                if primitive.protoMaterial.alphaMode == .mask {
                    mesh.containsAlphaClippedPrimitives = true
                    primitive.material.alphaCutoff = primitive.protoMaterial.alphaCutoff
                    primitive.material.shadingModel = .alphaClipped
                } else {
                    primitive.material.alphaCutoff = -1.0
                }
                
                if let emission = shredderExtras["Emission"] as? [String: Any],
                   let emissionVideo = emission["VideoTexture"] as? String {
                    tryToLoadVideoTexture(name: emissionVideo, forceReload: true)
                    primitive.material.emissiveTexture = {
                        [unowned self] in
                        self.videoTextures[emissionVideo]?.targetTexture
                    }
                }
            }
            
            primitive.material.color.x = primitive.protoMaterial.baseColor.x
            primitive.material.color.y = primitive.protoMaterial.baseColor.y
            primitive.material.color.z = primitive.protoMaterial.baseColor.z
            primitive.material.emissiveColor = primitive.protoMaterial.emissiveFactor * (primitive.protoMaterial.emissiveStrength ?? 1.0)
            primitive.material.metallic = primitive.protoMaterial.metallic
            primitive.material.roughness = primitive.protoMaterial.roughness
            
        }
        
        mesh.imported = true
    }
    
    
    func cleanupGLTFScene(){
        genericMeshes = [:]
        MetalView.renderer?.gltfRegistry = nil
    }
    
    
    static func loadSingularTexture(filename: String, srgbMode: Bool = false) -> MTLTexture? {
        do {
            let usage: MTLTextureUsage = [.shaderRead]
            let path =  URL(fileURLWithPath: filename + ".ktx")
            let out_tex = try textureLoader.newTexture(URL: path,
                                                       options: [.SRGB: srgbMode,
                                                                 .textureStorageMode: MTLStorageMode.private.rawValue,
                                                                 .textureUsage: usage.rawValue,
                                                                 ])
            return out_tex
        }catch {
            print("failed to load texture '\(filename)' with error: \(error.localizedDescription)")
        }
        return nil
    }
    
    
    /// from: https://github.com/Hi-Rez/Satin/blob/70f576550ecb7a8df8f3121a6a1a4c8939e9c4d8/Source/Utilities/Textures.swift#L114
    func loadHDR(_ url: String) -> MTLTexture? {
        
        guard let cfURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, url as CFString, CFURLPathStyle.cfurlposixPathStyle, false) else {
            fatalError("Failed to create CFURL from: \(url)")
        }
        guard let cgImageSource = CGImageSourceCreateWithURL(cfURL, nil) else {
            fatalError("Failed to create CGImageSource")
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) else {
            fatalError("Failed to create CGImage")
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGImageByteOrderInfo.order16Little.rawValue
        guard let bitmapContext = CGContext(data: nil,
                                            width: cgImage.width,
                                            height: cgImage.height,
                                            bitsPerComponent: cgImage.bitsPerComponent,
                                            bytesPerRow: cgImage.width * 2 * 4,
                                            space: colorSpace,
                                            bitmapInfo: bitmapInfo) else { return nil }
        
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = cgImage.width
        descriptor.height = cgImage.height
        descriptor.depth = 1
        descriptor.usage = .shaderRead
        descriptor.resourceOptions = .storageModeShared
        descriptor.sampleCount = 1
        descriptor.textureType = .type2D
        
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, cgImage.width, cgImage.height), mipmapLevel: 0, withBytes: bitmapContext.data!, bytesPerRow: cgImage.width * 2 * 4)
        
        return texture
    }
    
    
    func tryToLoadTexture(textureInfo: GLTFFile.GLTFTextureInfo?, baseDir: String, forceReload: Bool = false, linearColor: Bool = true){
        if let protoTexture = textureInfo?.texture {
            if let uri = protoTexture.source.reference?.uri, uri != "" {
                if textures[uri] == nil || forceReload {
                    textures[uri] = Renderer.loadSingularTexture(filename: baseDir + "/" + uri, srgbMode: !linearColor)
                }
            }
        }
    }
    
    func tryToLoadVideoTexture(name: String, forceReload: Bool = false){
        if videoTextures[name] == nil || forceReload {
            if let url = Bundle.main.url(forResource: name, withExtension: ".mp4", subdirectory: "videos") {
                Renderer.bufferSemaphore.wait()
                videoTextures[name] = VideoTexture(url: url, device: device)
                Renderer.bufferSemaphore.signal()
            } else {
                fatalError("Failed to find the video!")
            }
        }
    }
    
    func pauseAllVideoTextures() {
        for (_, videoTexture) in videoTextures {
            videoTexture.pause()
        }
    }
    
    func resumeVideoTextures() {
        for (_, videoTexture) in videoTextures {
            videoTexture.resume()
        }
    }
    
    func extractDescriptor(fromTexture: MTLTexture) -> MTLTextureDescriptor {
        let newDescriptor = MTLTextureDescriptor()
        
        newDescriptor.width = fromTexture.width
        newDescriptor.height = fromTexture.height
        newDescriptor.depth = fromTexture.depth
        newDescriptor.arrayLength = fromTexture.arrayLength
        newDescriptor.usage = fromTexture.usage
        newDescriptor.pixelFormat = fromTexture.pixelFormat
        newDescriptor.mipmapLevelCount = fromTexture.mipmapLevelCount
        newDescriptor.storageMode = fromTexture.storageMode
        
        return newDescriptor
    }
    
    static func loadTexture(device: MTLDevice,
                           textureName: String) throws -> MTLTexture {
        /// Load texture data with optimal parameters for sampling

        let textureLoader = MTKTextureLoader(device: device)

        let textureLoaderOptions = [
            MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue)
        ]

        return try textureLoader.newTexture(name: textureName,
                                            scaleFactor: 1.0,
                                            bundle: nil,
                                            options: textureLoaderOptions)

    }

    
    func immediateCompute(kernelName: String, varFunc: ((MTLComputeCommandEncoder) -> ())? = nil){
        struct statics {
            static var pipelineStates: [String : MTLComputePipelineState] = [:]
            static var descriptor = MTLComputePassDescriptor()
        }
        
        let commandBuffer = computeQueue.makeCommandBuffer()
        
        if statics.pipelineStates[kernelName] == nil {
            let library = device.makeDefaultLibrary()
            do {
                statics.pipelineStates[kernelName] = try device.makeComputePipelineState(
                    function: library!.makeFunction(name: kernelName)!
                )
            } catch {
                print(error.localizedDescription)
            }
        }
        
        if let computeEncoder = commandBuffer?.makeComputeCommandEncoder(descriptor: statics.descriptor) {
            if let pipeline = statics.pipelineStates[kernelName] {
                computeEncoder.setComputePipelineState(pipeline)
                computeEncoder.waitForFence(immediateFence)
                computeEncoder.updateFence(immediateFence)
                
                if let function = varFunc {
                    function(computeEncoder)
                }
            }
            computeEncoder.endEncoding()
        }
        
        commandBuffer?.commit()
    }
    
    func encodeCompute(kernelName: String, commandBuffer: MTLCommandBuffer, varFunc: ((MTLComputeCommandEncoder) -> ())? = nil){
        struct statics {
            static var pipelineStates: [String : MTLComputePipelineState] = [:]
            static var descriptor = MTLComputePassDescriptor()
        }
                
        if statics.pipelineStates[kernelName] == nil {
            let library = device.makeDefaultLibrary()
            do {
                statics.pipelineStates[kernelName] = try device.makeComputePipelineState(
                    function: library!.makeFunction(name: kernelName)!
                )
            } catch {
                print(error.localizedDescription)
            }
        }
        
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder(descriptor: statics.descriptor) {
            computeEncoder.setComputePipelineState(statics.pipelineStates[kernelName]!)
            
            if let function = varFunc {
                function(computeEncoder)
            }
        }
    }
    
    
    func applyIBLCubemapConvolution(commandEncoder: MTLRenderCommandEncoder){
        var iblVertices: [vector_float3] = [
            vector_float3(x: 1, y: 1, z: 1), // 0
            vector_float3(x: 1, y: -1, z: 1),
            vector_float3(x: -1, y: 1, z: 1), // 2
            vector_float3(x: -1, y: -1, z: 1),
            vector_float3(x: 1, y: 1, z: -1), // 4
            vector_float3(x: 1, y: -1, z: -1),
            vector_float3(x: -1, y: 1, z: -1), // 6
            vector_float3(x: -1, y: -1, z: -1),
        ]
        
        var captureViews : [matrix_float4x4] =
        [
            lookAt(position: simd_float3(0.0, 0.0, 0.0), target: simd_float3( 1.0,  0.0,  0.0), up_vec: simd_float3(0.0, -1.0,  0.0)),
            lookAt(position: simd_float3(0.0, 0.0, 0.0), target: simd_float3(-1.0,  0.0,  0.0), up_vec: simd_float3(0.0, -1.0,  0.0)),
            lookAt(position: simd_float3(0.0, 0.0, 0.0), target: simd_float3( 0.0,  1.0,  0.0), up_vec: simd_float3(0.0,  0.0,  1.0)),
            lookAt(position: simd_float3(0.0, 0.0, 0.0), target: simd_float3( 0.0, -1.0,  0.0), up_vec: simd_float3(0.0,  0.0, -1.0)),
            lookAt(position: simd_float3(0.0, 0.0, 0.0), target: simd_float3( 0.0,  0.0,  1.0), up_vec: simd_float3(0.0, -1.0,  0.0)),
            lookAt(position: simd_float3(0.0, 0.0, 0.0), target: simd_float3( 0.0,  0.0, -1.0), up_vec: simd_float3(0.0, -1.0,  0.0))
        ];
        
        pipelines["iblConvolve"]?.use(renderEncoder: commandEncoder)
        
        for i in 0..<6 {
            var layer = i
            var projection = matrix_perspective_right_hand(fovyRadians: .pi / 2.0, aspectRatio: 1.0, nearZ: 0.1, farZ: 10.0)
            commandEncoder.setVertexBytes(&iblVertices, length: MemoryLayout<simd_float3>.stride * 8, index: 0)
            commandEncoder.setVertexBytes(&captureViews[i], length: MemoryLayout<float4x4>.stride, index: 1)
            commandEncoder.setVertexBytes(&projection, length: MemoryLayout<float4x4>.stride, index: 2)
            commandEncoder.setVertexBytes(&layer, length: MemoryLayout<uint>.stride, index: 3)
            
            commandEncoder.setFragmentTexture(environmentCubemap, index: 0)
            
            commandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: Int(6), instanceCount: 1, baseInstance: 0)
        }
    }
    
    
}



struct PipelineOptions {
    enum BlendMode {
        case replace
        case additive
        case alpha
    }
    
    struct stencilOptions {
        var stencilPass = MTLStencilOperation.keep
        var stencilFail = MTLStencilOperation.keep
        var depthFail = MTLStencilOperation.keep
        var compareFunction = MTLCompareFunction.always
        var writeMask: UInt32 = 0xFF
        var readMask: UInt32 = 0xFF

        func setOperations(at: MTLStencilDescriptor) {
            at.stencilCompareFunction = compareFunction
            at.depthStencilPassOperation = stencilPass
            at.stencilFailureOperation = stencilFail
            at.depthFailureOperation = depthFail
            at.writeMask = writeMask
            at.readMask = readMask
        }
    }
    var targetRenderPass: RenderPassObject
    var vertexDescriptor: MTLVertexDescriptor?
    
    var colorWrite = true
    var depthWrite = true
    var depthCompareFunction = MTLCompareFunction.lessEqual
    var stencilCompareFunction = MTLCompareFunction.always
    var stencilWrite = true
    var stencilReference: UInt32 = 0x0
    var stencilOperationBack = stencilOptions()
    var stencilOperationFront = stencilOptions()
    var bothStencilOperations = stencilOptions() {
        didSet {
            stencilOperationBack = bothStencilOperations
            stencilOperationFront = bothStencilOperations
        }
    }

    var cullMode: MTLCullMode = .back
    
    var blendMode: BlendMode = .replace

    var label = "???"
    var vertexFunctionName = ""
    var fragmentFunctionName = ""
    
    init(targetRenderPass: RenderPassObject, vertexDescriptor: MTLVertexDescriptor?) {
        self.targetRenderPass = targetRenderPass
        self.vertexDescriptor = vertexDescriptor
    }
}

struct PipelineObject {
    var options: PipelineOptions
    var pipelineState: MTLRenderPipelineState!
    var depthState: MTLDepthStencilState

    init(device: MTLDevice, options: PipelineOptions, externalLibrary: MTLLibrary? = nil) {
        self.options = options
        
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        if options.targetRenderPass.options.createDepthTarget {
            depthStateDescriptor.depthCompareFunction = options.depthCompareFunction
            depthStateDescriptor.isDepthWriteEnabled = options.depthWrite
            if options.targetRenderPass.options.stencilEnable {
                options.stencilOperationFront.setOperations(at: depthStateDescriptor.frontFaceStencil)
                options.stencilOperationBack.setOperations(at: depthStateDescriptor.backFaceStencil)
            }
        }
        self.depthState = device.makeDepthStencilState(descriptor:depthStateDescriptor)!

        var library: MTLLibrary!
        if externalLibrary == nil {
            library = device.makeDefaultLibrary()
        } else {
            library = externalLibrary
        }
        
        let functionConstants = MTLFunctionConstantValues()
        if var hasUVs = options.vertexDescriptor?.layouts[2].stride, hasUVs != 0 {
            functionConstants.setConstantValue(&hasUVs, type: .bool, index: 1)
        }

        var vertexFunction: MTLFunction!
        do {
            vertexFunction = try library?.makeFunction(name: options.vertexFunctionName, constantValues: functionConstants)
        } catch {
            fatalError("\(error)")
        }
        let fragmentFunction = library?.makeFunction(name: options.fragmentFunctionName)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = options.label
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = options.vertexDescriptor
        pipelineDescriptor.inputPrimitiveTopology = .triangle
        pipelineDescriptor.vertexBuffers[0].mutability = .immutable

        for (idx, target) in options.targetRenderPass.renderTargets.enumerated() {
            pipelineDescriptor.colorAttachments[idx].pixelFormat = target.descriptor.pixelFormat
        }
        if (options.targetRenderPass.options.createDepthTarget){
            pipelineDescriptor.depthAttachmentPixelFormat = options.targetRenderPass.depthTarget!.descriptor.pixelFormat
            if options.targetRenderPass.options.stencilEnable {
                pipelineDescriptor.stencilAttachmentPixelFormat = options.targetRenderPass.depthTarget!.descriptor.pixelFormat
            }
        }
        
        switch options.blendMode {
        case .replace:
            break
        
        case .additive:
            for targetIdx in 0..<options.targetRenderPass.renderTargets.count {
                pipelineDescriptor.colorAttachments[targetIdx].rgbBlendOperation = .add
                pipelineDescriptor.colorAttachments[targetIdx].isBlendingEnabled = true
                pipelineDescriptor.colorAttachments[targetIdx].sourceRGBBlendFactor = .one
                pipelineDescriptor.colorAttachments[targetIdx].destinationRGBBlendFactor = .one
                pipelineDescriptor.colorAttachments[targetIdx].alphaBlendOperation = .max
            }
            break
        case .alpha:
            for targetIdx in 0..<options.targetRenderPass.renderTargets.count {
                pipelineDescriptor.colorAttachments[targetIdx].rgbBlendOperation = .add
                pipelineDescriptor.colorAttachments[targetIdx].isBlendingEnabled = true
                pipelineDescriptor.colorAttachments[targetIdx].sourceRGBBlendFactor = .sourceAlpha
                pipelineDescriptor.colorAttachments[targetIdx].destinationRGBBlendFactor = .oneMinusSourceAlpha
                pipelineDescriptor.colorAttachments[targetIdx].alphaBlendOperation = .max
            }
            break
            
        }

        do{
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Error info: \(error)")
            fatalError("Failed to create the requested pipeline state.")
        }
    }
    
    func use(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(options.cullMode)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        if options.targetRenderPass.options.stencilEnable {
            renderEncoder.setStencilReferenceValue(options.stencilReference)
        }
    }
    
}


class VideoTexture {
    var enabled = true
    var loops = true
    var currentTime = 0.0
    var videoLength = 1.0
    var textureWidth = 1
    var textureHeight = 1
    
    var player: AVPlayer?
    var targetTexture: MTLTexture!
    var videoTransform: CGAffineTransform?
    var unfilteredImage: CIImage?
    let ciContext: CIContext!
    
    let textureCache: CVMetalTextureCache?
    
    private var observer: NSKeyValueObservation?
    
    static let pixelBufferAttributes: [String:AnyObject] = [
        String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_32BGRA)]
      
    var videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: VideoTexture.pixelBufferAttributes)
    
    func pause() {
        player?.pause()
    }
    
    func resume() {
        if enabled {
            player?.play()
        }
    }
    
    init(url: URL, device: MTLDevice) {
        ciContext = CIContext(mtlDevice: device)
        player = AVPlayer(url: url)
        let currentItem = player?.currentItem
        currentItem?.add(videoOutput)
        var metalTextureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &metalTextureCache)
        textureCache = metalTextureCache
        
        guard let player = player else {
            fatalError("** unable to initialize player **")
        }
        
        observer = player.observe(\.status, changeHandler: { [self] player, status in
            if player.status == .readyToPlay {
                if let currentItem = player.currentItem {
                    self.videoLength = currentItem.duration.seconds
                }
            }
        })
        
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.play()
        
    }
    
    func renderMetalTexture(cmd: MTLCommandBuffer) {
        guard let img = unfilteredImage,
              let tex = targetTexture else {
            return
        }
        let rect = CGRect(x: 0, y: 0, width: textureWidth, height: textureHeight)
        let colorSpace = img.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        ciContext.render(img, to: tex, commandBuffer: cmd, bounds: rect, colorSpace: colorSpace)
    }
    
    func render(cmd: MTLCommandBuffer){
        guard let player = player,
              let currentItem = player.currentItem,
              player.status == .readyToPlay && currentItem.status == .readyToPlay else {
            return
        }
        let time = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        if videoOutput.hasNewPixelBuffer(forItemTime: time) {
            var presentationItemTime = CMTime.zero
            
            guard let pixelBuffer = videoOutput.copyPixelBuffer(
                forItemTime: time,
                itemTimeForDisplay: &presentationItemTime) else {
                return
            }

            textureWidth = CVPixelBufferGetWidth(pixelBuffer)
            textureHeight = CVPixelBufferGetHeight(pixelBuffer)
            let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
            CVMetalTextureCacheFlush(textureCache!, CVOptionFlags())
            var cvTexture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, pixelBuffer, nil, .rgba8Unorm, textureWidth, textureHeight, planeCount, &cvTexture)
            if let cvTexture = cvTexture {
                targetTexture = CVMetalTextureGetTexture(cvTexture)
            }
        }
        
    }
}

extension BoneAnimation {
    func updateBuffer(buffer: FlyingGPUBuffer<simd_float4x4>){
        rendererMatrixIndex = buffer.count
        var transforms = [simd_float4x4]()
        
        for (index, jointNode) in jointNodes.enumerated() {
            let current = jointNode.transform.global.matrix * inverseBindMatrices[index]
            transforms.append(current)
        }
        
        buffer.append(from: transforms, count: transforms.count)
    }
}
