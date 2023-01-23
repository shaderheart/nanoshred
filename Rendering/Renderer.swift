//
//  Renderer.swift
//  metal-modelio
//
//  Created by utku on 21/09/2022.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

import MetalPerformanceShaders

import GameController

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100


struct MeshNode {
    var transform = MDLTransform()
    var mesh: MTKMesh!
    
    var materials: [SwiftPBRMaterial] = []
    
    var children: [MeshNode] = []
}

struct LightNode {
    enum LightType {
        case point
        case spot
        case area
    }
    
    var transform = MDLTransform()
    var material = RenderLightMaterial()
    var type = LightType.point
}

class Renderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    public static var staticDevice: MTLDevice!
    let commandQueue: MTLCommandQueue
    let immediateCommandQueue: MTLCommandQueue
    
    var computeQueue: MTLCommandQueue!
    var immediateFence : MTLFence!
    var libraries: [String: MTLLibrary] = [:]
    
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    
    var uniformBuffer: FlyingGPUBuffer<Uniforms>!
    var genericVertexBuffer: FlyingGPUBuffer<GenericVertex>!
    var bonePropertiesBuffer: FlyingGPUBuffer<BoneProperties>!
    var genericBoneVertexBuffer: FlyingGPUBuffer<BoneVertex>!
    var genericIndexBuffer: FlyingGPUBuffer<UInt32>!
    var boneAnimationBuffer: FlyingGPUBuffer<simd_float4x4>!
    var genericCPUBuffer: FlyingGPUBuffer<FragmentCpuBuffer>!
    var fragmentCPUBufferData: UnsafeMutablePointer<FragmentCpuBuffer>
    
    var simpleParticleBuffer: FlyingGPUBuffer<SimpleParticle>!
    var simpleParticleVertexBuffer: FlyingGPUBuffer<SimpleParticleVertex>!
    var simpleParticleDeletionBuffer: FlyingGPUBuffer<uint>!
    
    
    //    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    
    var sceneMeshes: [MTKMesh] = []
    var sceneMeshNodes: [MeshNode] = []
    var camera = GameCamera()
    
    var renderPasses: [String : RenderPassObject] = [:]
    var pipelines: [String : PipelineObject] = [:]
    
    var renderTextureStore: [String : MTLTexture] = [:]
    var modelMatrixBuffer: FlyingGPUBuffer<simd_float4x4>
    
    var pointLightMesh: MTKMesh!
    var spotLightMesh: MTKMesh!
    var pointLights: [LightNode] = []
    var spotLights: [LightNode] = []
    
    var genericMeshes: [String: GenericMesh] = [:]
    var textures: [String: MTLTexture] = [:]
    var videoTextures: [String: VideoTexture] = [:]
    var environmentCubemap: MTLTexture!
    var environmentIBL: MTLTexture!
    var environmentRenderingEnabled = true
    
    static var mainWidth: Int = 0
    static var mainHeight: Int = 0
    
    var gltfRegistry: SHRegistry?
    
    public static var bufferSemaphore = DispatchSemaphore(value: 1)
    
    static var textureLoader: MTKTextureLoader!
    
    static var defaultVertexDescriptor = MTLVertexDescriptor()
    static var genericVertexDescriptor = MTLVertexDescriptor()
    static var lightVertexDescriptor = MTLVertexDescriptor()
    
    var mainMaterial = SwiftPBRMaterial()
    
    var shadowRenderPasses = [RenderPassObject]()
    var availableShadowRenderPasses = [RenderPassObject]()
    
    var tapRequested = false
    var tapCaptured = false
    var tapPosition = CGPoint()
    var tapPositionUV = CGPoint()
    var tappedEntity: SHEntity?
    private var tapDispatched = false
    private var tappableMap: [SHEntity: UInt32] = [:]
    private var inverseTappableMap: [UInt32: SHEntity] = [:]
    
    let ndc_shifter = simd_float4x4(columns: (simd_float4(0.5,  0, 0,   0),
                                              simd_float4(0,  0.5, 0,   0),
                                              simd_float4(0,  0, 1.0,   0),
                                              simd_float4(0.5,  0.5, 0.0,   1)))
    
    class RendererBindingManager {
        var vertexBufferBindings: [Int: [Int: UInt64]] = [:]
        var fragmentBufferBindings: [Int: [Int: UInt64]] = [:]
        var computeBufferBindings: [Int: [Int: UInt64]] = [:]
        
        var vertexTextureBindings: [Int: [Int: Int]] = [:]
        var fragmentTextureBindings: [Int: [Int: Int]] = [:]
        var computeTextureBindings: [Int: [Int: Int]] = [:]
        
        func reset() {
            vertexBufferBindings = [:]
            fragmentBufferBindings = [:]
            computeBufferBindings = [:]
            
            vertexTextureBindings = [:]
            fragmentTextureBindings = [:]
            computeTextureBindings = [:]
        }
        
        func bindVertexBuffer(cmd: MTLRenderCommandEncoder, slot: Int, buffer: MTLBuffer, offset: Int) {
            if vertexBufferBindings[cmd.hash] == nil {
                vertexBufferBindings[cmd.hash] = [:]
            }
            if (vertexBufferBindings[cmd.hash]![slot] ?? 0) != buffer.gpuAddress {
                vertexBufferBindings[cmd.hash]![slot] = buffer.gpuAddress
                cmd.setVertexBuffer(buffer, offset: offset, index: slot)
            }
        }
        
        func bindFragmentBuffer(cmd: MTLRenderCommandEncoder, slot: Int, buffer: MTLBuffer, offset: Int) {
            if fragmentBufferBindings[cmd.hash] == nil {
                fragmentBufferBindings[cmd.hash] = [:]
            }
            if (fragmentBufferBindings[cmd.hash]![slot] ?? 0) != buffer.gpuAddress {
                fragmentBufferBindings[cmd.hash]![slot] = buffer.gpuAddress
                cmd.setFragmentBuffer(buffer, offset: offset, index: slot)
            }
        }
        
        func bindComputeBuffer(cmd: MTLComputeCommandEncoder, slot: Int, buffer: MTLBuffer, offset: Int) {
            if computeBufferBindings[cmd.hash] == nil {
                computeBufferBindings[cmd.hash] = [:]
            }
            if (computeBufferBindings[cmd.hash]![slot] ?? 0) != buffer.gpuAddress {
                computeBufferBindings[cmd.hash]![slot] = buffer.gpuAddress
                cmd.setBuffer(buffer, offset: offset, index: slot)
            }
        }
        
        func bindVertexTexture(cmd: MTLRenderCommandEncoder, slot: Int, texture: MTLTexture?) {
            if vertexTextureBindings[cmd.hash] == nil {
                vertexTextureBindings[cmd.hash] = [:]
            }
            if (vertexTextureBindings[cmd.hash]![slot] ?? 0) != (texture?.hash ?? 0) {
                vertexTextureBindings[cmd.hash]![slot] = (texture?.hash ?? 0)
                cmd.setVertexTexture(texture, index: slot)
            }
        }
        
        func bindFragmentTexture(cmd: MTLRenderCommandEncoder, slot: Int, texture: MTLTexture?) {
            if fragmentTextureBindings[cmd.hash] == nil {
                fragmentTextureBindings[cmd.hash] = [:]
            }
            if (fragmentTextureBindings[cmd.hash]![slot] ?? 0) != (texture?.hash ?? 0) {
                fragmentTextureBindings[cmd.hash]![slot] = (texture?.hash ?? 0)
                cmd.setFragmentTexture(texture, index: slot)
            }
        }
        
        func bindComputeTexture(cmd: MTLComputeCommandEncoder, slot: Int, texture: MTLTexture?) {
            if computeTextureBindings[cmd.hash] == nil {
                computeTextureBindings[cmd.hash] = [:]
            }
            if (computeTextureBindings[cmd.hash]![slot] ?? 0) != (texture?.hash ?? 0) {
                computeTextureBindings[cmd.hash]![slot] = (texture?.hash ?? 0)
                cmd.setTexture(texture, index: slot)
            }
        }
    }
    
    static var bindingManager: RendererBindingManager = .init()
    
    init(metalKitView: MTKView) {
        self.device = metalKitView.device!
        
        /// create meshes used for lighting
        let allocator = MTKMeshBufferAllocator(device: device)
        let pLightMesh = MDLMesh.newIcosahedron(withRadius: 1.0, inwardNormals: true, allocator: allocator)
        let sLightMesh = MDLMesh.newEllipticalCone(withHeight: 1.0, radii: vector_float2(x: 2.0, y: 2.0),
                                                   radialSegments: 30, verticalSegments: 1,
                                                   geometryType: .triangles, inwardNormals: true, allocator: allocator)
        do {
            self.pointLightMesh = try MTKMesh(mesh: pLightMesh, device: device)
            self.spotLightMesh = try MTKMesh(mesh: sLightMesh, device: device)
            Renderer.lightVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(self.pointLightMesh.vertexDescriptor)!
        } catch {
            print("Loading light mesh failed: \(error)")
        }
        
        Renderer.staticDevice = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!
        self.commandQueue.label = "render queue"
        self.computeQueue = device.makeCommandQueue(maxCommandBufferCount: 2)
        self.computeQueue.label = "compute queue"
        self.immediateFence = device.makeFence()!
        self.immediateCommandQueue = self.device.makeCommandQueue()!
        self.immediateCommandQueue.label = "immediate queue"
        
        Renderer.textureLoader = .init(device: device)
        
        uniformBuffer = .init(device: device, elements: 2, flights: 3)
        genericVertexBuffer = .init(device: device, elements: 1000, flights: 1)
        genericBoneVertexBuffer = .init(device: device, elements: 1000, flights: 1)
        bonePropertiesBuffer = .init(device: device, elements: 1000, flights: 1)
        boneAnimationBuffer = .init(device: device, elements: 400, flights: 1)
        genericIndexBuffer = .init(device: device, elements: 1000, flights: 1)
        genericCPUBuffer = .init(device: device, elements: 2, cpuReadsAllowed: true)
        simpleParticleBuffer = .init(device: device, elements: SimpleParticleManager.maxParticles, flights: 1)
        simpleParticleVertexBuffer = .init(device: device, elements: SimpleParticleManager.maxParticles, flights: 1)
        simpleParticleDeletionBuffer = .init(device: device, elements: 1, flights: 1)
        SimpleParticleManager.currentMetalFlyingBuffer = simpleParticleBuffer
        SimpleParticleManager.currentMetalVertexBuffer = simpleParticleVertexBuffer
        SimpleParticleManager.currentParticleDeletionBuffer = simpleParticleDeletionBuffer
        
        fragmentCPUBufferData = genericCPUBuffer.bufferView
        
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1
        
        modelMatrixBuffer = FlyingGPUBuffer(device: device, elements: 100)
        
        super.init()
        
        var postProcessPassOptions = RenderPassOptions()
        postProcessPassOptions.createDepthTarget = false
        postProcessPassOptions.scaleFactor = 0.5
        postProcessPassOptions.targetFormats = [.rgba16Float]
        let postProcessPass = RenderPassObject(device: device, options: postProcessPassOptions,
                                               width: metalKitView.currentDrawable?.texture.width ?? 0,
                                               height: metalKitView.currentDrawable?.texture.height ?? 0)
        renderPasses["postprocessing"] = postProcessPass
        
        
        var hdriCubemapPassOptions = RenderPassOptions()
        hdriCubemapPassOptions.renderTargetCount = 1
        hdriCubemapPassOptions.createDepthTarget = false
        hdriCubemapPassOptions.resizeWithFramebuffer = false
        hdriCubemapPassOptions.isCubemap = true
        hdriCubemapPassOptions.hasMips = true
        hdriCubemapPassOptions.targetFormats = [.rgba16Float]
        let cubemapHeight = 1024
        let cubemapWidth = 1024
        let hdriCubemapProcessPass = RenderPassObject(device: device, options: hdriCubemapPassOptions,
                                                      width: cubemapHeight,
                                                      height: cubemapWidth)
        renderPasses["hdriCubemapPass"] = hdriCubemapProcessPass
        
        let hdriTexturePath = Bundle.main.url(forResource: "satara_night_4k", withExtension: ".hdr", subdirectory: "environments")!
        let hdriTexture = loadHDR(hdriTexturePath.relativePath)
        
        immediateCompute(kernelName: "hdriToCubemap") { computeEncoder in
            let outputTexture = self.renderPasses["hdriCubemapPass"]!.renderTargets[0].currentTarget!
            computeEncoder.setTexture(hdriTexture, index: 0)
            computeEncoder.setTexture(outputTexture, index: 1)
            
            let threadgroupSize = MTLSizeMake(32, 32, 1);
            var threadgroupCount = MTLSize()
            threadgroupCount.width  = (outputTexture.width  + threadgroupSize.width - 1) / threadgroupSize.width;
            threadgroupCount.height = (outputTexture.height + threadgroupSize.height - 1) / threadgroupSize.height;
            threadgroupCount.depth = 1;
            
            var outputSize = simd_float2(Float(cubemapWidth), Float(cubemapHeight))
            computeEncoder.setBytes(&outputSize, length: MemoryLayout.size(ofValue: outputSize), index: 0)
            
            for face in 0..<6 {
                var outputFace = UInt(face)
                computeEncoder.setBytes(&outputFace, length: MemoryLayout.size(ofValue: outputSize), index: 1)
                computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            }
        }
        
        environmentCubemap = self.renderPasses["hdriCubemapPass"]!.renderTargets[0].currentTarget
        immediateSubmit { cmd in
            let blitEncoder = cmd.makeBlitCommandEncoder()
            blitEncoder?.waitForFence(self.immediateFence)
            blitEncoder?.updateFence(self.immediateFence)
            blitEncoder?.generateMipmaps(for: self.environmentCubemap)
            blitEncoder?.endEncoding()
        }
        
        var iblConvolvePassOptions = RenderPassOptions()
        iblConvolvePassOptions.renderTargetCount = 1
        iblConvolvePassOptions.createDepthTarget = false
        iblConvolvePassOptions.resizeWithFramebuffer = false
        iblConvolvePassOptions.isCubemap = true
        iblConvolvePassOptions.hasMips = false
        iblConvolvePassOptions.targetFormats = [.rgba16Float]
        let iblConvolvePass = RenderPassObject(device: device, options: iblConvolvePassOptions,
                                               width: 32, height: 32)
        renderPasses["iblConvolve"] = iblConvolvePass
        environmentIBL = self.renderPasses["iblConvolve"]!.renderTargets[0].currentTarget
        
        var iblConvolveOptions = PipelineOptions(targetRenderPass: iblConvolvePass, vertexDescriptor: nil)
        iblConvolveOptions.vertexFunctionName = "cubemapVertexFunction"
        iblConvolveOptions.fragmentFunctionName = "cubemapConvolve"
        iblConvolveOptions.cullMode = .none
        iblConvolveOptions.label = "IBL convolver"
        let iblConvolvePipeline = PipelineObject(device: device, options: iblConvolveOptions)
        pipelines["iblConvolve"] = iblConvolvePipeline
        immediateSubmit { commandBuffer in
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPasses["iblConvolve"]!.currentPassDescriptor) {
                self.applyIBLCubemapConvolution(commandEncoder: renderEncoder)
                renderEncoder.endEncoding()
            }
        }
        
        var shadowPassOptions = RenderPassOptions()
        shadowPassOptions.renderTargetCount = 0
        shadowPassOptions.hasMips = false
        shadowPassOptions.resizeWithFramebuffer = false
        shadowPassOptions.createDepthTarget = true
        shadowPassOptions.stencilEnable = false
        let shadowPass = RenderPassObject(device: device, options: shadowPassOptions, width: 2048, height: 2048)
        
        shadowRenderPasses.append(shadowPass)
        
        for _ in 0..<4 {
            shadowRenderPasses.append(RenderPassObject(device: device, options: shadowPassOptions, width: 512, height: 512))
        }
        
        var spotlightShadowOptions = PipelineOptions(targetRenderPass: shadowPass, vertexDescriptor: nil)
        spotlightShadowOptions.cullMode = .back
        spotlightShadowOptions.depthWrite = true
        spotlightShadowOptions.stencilWrite = false
        spotlightShadowOptions.vertexFunctionName = "lightShadowVertex"
        let spotlightShadowPipeline = PipelineObject(device: device, options: spotlightShadowOptions)
        pipelines["spotlightShadow"] = spotlightShadowPipeline
        
        buildReloadablePipelines(width: Int(metalKitView.drawableSize.width), height: Int(metalKitView.drawableSize.height))
        
    }
    
#if targetEnvironment(macCatalyst)
    func rebuildShaderLibrary(metalFile: URL, directory: URL, name: String){
        
        print("RENDERER: Loading shaders from \(metalFile)")
        let compileOptions = MTLCompileOptions()
        compileOptions.fastMathEnabled = true
        compileOptions.languageVersion = .version2_4
        compileOptions.libraryType = .executable
        
        if let shaderSource = try? String.init(contentsOf: metalFile) {
            var sourceCopy = ""
            for line in shaderSource.split(separator: "\n"){
                if line.starts(with: "#import") {
                    if let match = line.firstMatch(of: /(?:#import.?[<,\"])(.*)([>,\"])/)?.output.1 {
                        let fileInDirectoryUrl = directory.appendingPathComponent(String(match))
                        if let headerSource = try? String.init(contentsOf: fileInDirectoryUrl) {
                            sourceCopy.append(headerSource)
                        }
                    }
                }else {
                    sourceCopy.append("\(line) \n")
                }
            }
            do {
                try sourceCopy.write(toFile: directory.appendingPathComponent("\(name)combined.metal").relativePath, atomically: true, encoding: .utf8)
                
                libraries[name] = try self.device.makeLibrary(source: sourceCopy, options: compileOptions)
            } catch {
                print(error.localizedDescription)
            }
        }
    }
#endif
    
    func buildReloadablePipelines(width: Int, height: Int) {
        
#if targetEnvironment(macCatalyst)
        // load shaders as libraries from the source directory
        let filePath = #file
        let fileUrl = URL(fileURLWithPath: filePath)
        let fileDirectoryUrl = fileUrl.deletingLastPathComponent()
        var fileInDirectoryUrl = fileDirectoryUrl.appendingPathComponent("Shaders.metal")
        rebuildShaderLibrary(metalFile: fileInDirectoryUrl, directory: fileDirectoryUrl, name: "Shaders")
        fileInDirectoryUrl = fileDirectoryUrl.appendingPathComponent("Shadows.metal")
        //        rebuildShaderLibrary(metalFile: fileInDirectoryUrl, directory: fileDirectoryUrl, name: "Shadows")
#endif
        
        camera.aspectRatio = Float(width) / Float(height)
        
        var testPassOptions = RenderPassOptions()
        testPassOptions.renderTargetCount = 4
        testPassOptions.targetFormats = [.rgba16Float, .rgba8Unorm, .rgba16Float, .rgba16Float]
        testPassOptions.targetMemoryless = [false, true, true, true]
        testPassOptions.scaleFactor = 1.0
        let testPass = RenderPassObject(device: device, options: testPassOptions, width: width, height: height)
        renderPasses["testPass"] = testPass
        
        var testPipelineOptions = PipelineOptions(targetRenderPass: testPass,
                                                  vertexDescriptor: Renderer.defaultVertexDescriptor)
        testPipelineOptions.fragmentFunctionName = "gBufferFragment"
        testPipelineOptions.label = "test pipeline"
        testPipelineOptions.stencilWrite = true
        testPipelineOptions.stencilReference = 0x4
        testPipelineOptions.stencilOperationFront.stencilFail = .replace
        testPipelineOptions.stencilOperationFront.stencilPass = .replace
        testPipelineOptions.stencilOperationFront.depthFail = .replace
        
        testPipelineOptions.vertexFunctionName = "genericGBufferVertex"
        testPipelineOptions.label = "generic pipeline"
        testPipelineOptions.vertexDescriptor = nil
        let genericPipeline = PipelineObject(device: device, options: testPipelineOptions, externalLibrary: libraries["Shaders"])
        pipelines["genericPipeline"] = genericPipeline
        
        testPipelineOptions.fragmentFunctionName = "gBufferAlphaClippedFragment"
        testPipelineOptions.cullMode = .none
        let alphaClipPipeline = PipelineObject(device: device, options: testPipelineOptions, externalLibrary: libraries["Shaders"])
        pipelines["alphaClipPipeline"] = alphaClipPipeline
        
        testPipelineOptions.fragmentFunctionName = "gBufferGlassFragment"
        testPipelineOptions.cullMode = .back
        testPipelineOptions.stencilReference = 0x4
        testPipelineOptions.blendMode = .alpha
        let glassPipeline = PipelineObject(device: device, options: testPipelineOptions, externalLibrary: libraries["Shaders"])
        pipelines["glassPipeline"] = glassPipeline
        
        
        let emptyVertexDescriptor = MTLVertexDescriptor()
        let mainRenderPassOptions = RenderPassOptions()
        let mainRenderPass = RenderPassObject(device: device, options: mainRenderPassOptions,
                                              width: width,
                                              height: height)
        var mainPipelineOptions = PipelineOptions(targetRenderPass: mainRenderPass,
                                                  vertexDescriptor: emptyVertexDescriptor)
        mainPipelineOptions.vertexFunctionName = "copy_vertex_function"
        mainPipelineOptions.fragmentFunctionName = "blitFragment"
        mainPipelineOptions.label = "main pipeline"
        let mainPipeline = PipelineObject(device: device, options: mainPipelineOptions, externalLibrary: libraries["Shaders"])
        pipelines["main"] = mainPipeline
        
        
        /// create lighting pipeline
        var lightPipelineOptions = PipelineOptions(targetRenderPass: testPass,
                                                   vertexDescriptor: Renderer.lightVertexDescriptor)
        lightPipelineOptions.vertexFunctionName = "lightVertexFunction"
        lightPipelineOptions.fragmentFunctionName = "pointLightingSinglePass"
        lightPipelineOptions.label = "lighting pipeline"
        lightPipelineOptions.cullMode = .front
        lightPipelineOptions.depthCompareFunction = .always
        lightPipelineOptions.depthWrite = false
        lightPipelineOptions.stencilWrite = false
        lightPipelineOptions.blendMode = .additive
        lightPipelineOptions.stencilReference = 0x4
        
        lightPipelineOptions.stencilOperationBack.compareFunction = .equal
        lightPipelineOptions.stencilOperationFront.compareFunction = .equal
        
        let lightingPipeline = PipelineObject(device: device, options: lightPipelineOptions, externalLibrary: libraries["Shaders"])
        pipelines["lighting"] = lightingPipeline
        
        lightPipelineOptions.vertexFunctionName = "copy_vertex_function"
        lightPipelineOptions.fragmentFunctionName = "directionalLightingSinglePass"
        lightPipelineOptions.cullMode = .none
        let directionalLightingPipeline = PipelineObject(device: device, options: lightPipelineOptions, externalLibrary: libraries["Shaders"])
        pipelines["directionalLighting"] = directionalLightingPipeline
        
        var simpleParticlePipelineOptions = lightPipelineOptions
        simpleParticlePipelineOptions.vertexDescriptor = nil
        simpleParticlePipelineOptions.vertexFunctionName = "particleVertexFunction"
        simpleParticlePipelineOptions.fragmentFunctionName = "particleFragmentFunction"
        simpleParticlePipelineOptions.label = "particle pipeline"
        simpleParticlePipelineOptions.bothStencilOperations.compareFunction = .always
        simpleParticlePipelineOptions.cullMode = .none
        simpleParticlePipelineOptions.depthCompareFunction = .lessEqual
        
        let simpleParticlePipeline = PipelineObject(device: device, options: simpleParticlePipelineOptions, externalLibrary: libraries["Shaders"])
        pipelines["simpleParticle"] = simpleParticlePipeline
    }
    
    func reset() {
        for bird in flightList.values {
            bird.value?.reset(device: device, keepingCapacity: false)
        }
    }
    
    
    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering
        for bird in flightList.values {
            bird.value?.moveNext()
        }
    }
    
    static var lastTime = CFAbsoluteTimeGetCurrent()
    static var deltaTime = 0.0
    
    private func updateGameState() {
        /// Update any game state before rendering
        EngineGlobals.activeCamera = camera
        
        modelMatrixBuffer.bufferView[0] = simd_float4x4(1.0)
        
        let uniforms = uniformBuffer.bufferView
        uniforms[0].projectionMatrix = camera.projection
        uniforms[0].viewMatrix = camera.matrix
        uniforms[0].viewPosition = -camera.position
        uniforms[0].viewDirection = -camera.direction
        uniforms[0].tapPosition = simd_float3(Float(tapPosition.x), Float(tapPosition.y), 0.0)
        
    }
    
    // MARK: Draw functions
    func drawDirectionalLight(renderEncoder: MTLRenderCommandEncoder, light: EPunctualLight, transform: ETransformComponent) {
        var lightMaterial = RenderLightMaterial()
        lightMaterial.color = light.color
        lightMaterial.power = light.intensity
        lightMaterial.lightDirection = simd_make_float3(transform.global.rotationMatrix * simd_float4(0, 0, 1, 0))
        renderEncoder.setFragmentBytes(&lightMaterial,
                                       length: MemoryLayout.stride(ofValue: lightMaterial),
                                       index: BufferIndex.materials.rawValue)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        
    }
    
    func drawPunctualLight(renderEncoder: MTLRenderCommandEncoder, light: EPunctualLight, transform: ETransformComponent) {
        var meshTransform = MeshTransform()
        transform.global.scale = simd_float3(repeating: light.intensity * 0.75)

        var lightMaterial = RenderLightMaterial()
        lightMaterial.type = 0
        var lightMesh = pointLightMesh
        
        let tempTransform: ETransform = .init(matrix: transform.global.matrix)

        if light.type == .spot {
            let angleScale = light.outerConeAngle / (.pi / 4.0)
            tempTransform.scale *= simd_float3(x: angleScale, y: 1.0, z: angleScale)
            tempTransform.rotation = tempTransform.rotation * simd_quatf(angle: .pi / 2.0, axis: simd_float3(x: 1, y: 0, z: 0))
            tempTransform.matrix = tempTransform.matrix * matrix4x4_translation(0, -0.5, 0)
            lightMesh = spotLightMesh
            lightMaterial.type = 1
        }
        
        meshTransform.baseTransform = tempTransform.matrix
        meshTransform.normalTransform = transform.global.rotationMatrix.inverse
        renderEncoder.setVertexBytes(&meshTransform,
                                     length: MemoryLayout.stride(ofValue: meshTransform),
                                     index: BufferIndex.meshTransform.rawValue)
        
        
        for (index, element) in lightMesh!.vertexDescriptor.layouts.enumerated() {
            guard let layout = element as? MDLVertexBufferLayout else {
                return
            }
            if layout.stride != 0 {
                let buffer = lightMesh!.vertexBuffers[index]
                renderEncoder.setVertexBuffer(buffer.buffer, offset:buffer.offset, index: index)
            }
        }
        
        if let shadowTexture = light.shadowTexture {
            renderEncoder.setFragmentTexture(shadowTexture, index: TextureIndex.lightShadow.rawValue)
        }
        
        lightMaterial.color = light.color
        lightMaterial.power = light.intensity
        lightMaterial.innerCutoff = cos(light.innerConeAngle)
        lightMaterial.outerCutoff = cos(light.outerConeAngle)
        lightMaterial.worldPosition = transform.global.translation
        lightMaterial.lightDirection = simd_make_float3(transform.global.rotationMatrix * simd_float4(0, 0, 1, 0))
        
        let lightModel = transform.global.matrix
        var mconv3 = convertMatrix(input: lightModel)
        mconv3 = simd_transpose(extractRotation(input: mconv3))
        
        // setup light's view and projection matrices, and send them to the GPU
        var camera = simd_float4x4(1.0)
        camera = convertMatrix(input: mconv3) * camera
        camera.columns.3 += (camera.columns.0 * (-lightModel.columns.3.x))
        camera.columns.3 += (camera.columns.1 * (-lightModel.columns.3.y))
        camera.columns.3 += (camera.columns.2 * (-lightModel.columns.3.z))
        
        lightMaterial.lightViewMatrix = ndc_shifter * light.shadowProjection * camera
        
        renderEncoder.setFragmentBytes(&lightMaterial,
                                       length: MemoryLayout.stride(ofValue: lightMaterial),
                                       index: BufferIndex.materials.rawValue)
        
        for (_, submesh) in lightMesh!.submeshes.enumerated() {
            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer.buffer,
                                                indexBufferOffset: submesh.indexBuffer.offset)
        }
    }
    
    enum MeshRenderMode {
        case opaque
        case alphaClipped
        case alphaBlended
        case glass
    }
    
    func drawGenericMesh(renderEncoder: MTLRenderCommandEncoder, mesh: GenericMesh, entity: SHEntity, renderMode: MeshRenderMode, boneAnimation: BoneAnimation? = nil){
        guard mesh.imported else {
            return
        }
        
        
        
        var meshTransform = MeshTransform()
        meshTransform.baseTransform = entity.transform.global.matrix
        meshTransform.normalTransform = entity.transform.global.rotationMatrix
        
        renderEncoder.setVertexBytes(&meshTransform,
                                     length: MemoryLayout.stride(ofValue: meshTransform),
                                     index: BufferIndex.meshTransform.rawValue)
        
        genericVertexBuffer.bindToVertexSlot(renderEncoder: renderEncoder,
                                             slot: BufferIndex.meshPositions.rawValue,
                                             offset: 0)
        bonePropertiesBuffer.bindToVertexSlot(renderEncoder: renderEncoder,
                                              slot: BufferIndex.meshBoneProps.rawValue, offset: 0)
        boneAnimationBuffer.bindToVertexSlot(renderEncoder: renderEncoder,
                                             slot: BufferIndex.boneLocations.rawValue, offset: 0)
        genericCPUBuffer.bindToFragmentSlot(renderEncoder: renderEncoder, manager: Renderer.bindingManager,
                                            slot: 8)
        
        var vertexShaderOptions = VertexShaderOptions()
        if let boneAnimation = boneAnimation {
            vertexShaderOptions.isBoneAnimated = true
            vertexShaderOptions.boneOffset = uint(boneAnimation.rendererMatrixIndex)
        }
        
        renderEncoder.setVertexBytes(&vertexShaderOptions,
                                     length: MemoryLayout<VertexShaderOptions>.stride,
                                     index: BufferIndex.vertexShaderOptions.rawValue)
        
        
        var tapRequestedInt: UInt32 = 0
        var entityID = UInt32.max
        let tappable: UnsafeMutablePointer<ETappableComponent>? = entity.component()
        if tapRequested && tappable != nil {
            entityID = tappableMap[entity]!
            tapRequestedInt = 1
        }
        
        for (_, primitive) in mesh.primitives.enumerated() {
            switch renderMode {
            case .opaque:
                if primitive.material.shadingModel != .opaque {continue}
                
                var renderMaterial = primitive.material.getRenderMaterial()
                renderEncoder.setFragmentBytes(&renderMaterial,
                                               length: MemoryLayout.stride(ofValue: renderMaterial),
                                               index: BufferIndex.materials.rawValue)
            case .alphaClipped:
                if primitive.material.shadingModel != .alphaClipped {continue}
                
                var renderMaterial = primitive.material.getAlphaClippedMaterial()
                renderEncoder.setFragmentBytes(&renderMaterial,
                                               length: MemoryLayout.stride(ofValue: renderMaterial),
                                               index: BufferIndex.materials.rawValue)
            case .alphaBlended:
                if primitive.material.shadingModel != .alphaBlended {continue}
                
                break
            case .glass:
                if primitive.material.shadingModel != .glass {continue}
                
                var renderMaterial = primitive.material.getGlassMaterial()
                renderEncoder.setFragmentBytes(&renderMaterial,
                                               length: MemoryLayout.stride(ofValue: renderMaterial),
                                               index: BufferIndex.materials.rawValue)
            }
            
            renderEncoder.setVertexBufferOffset(primitive.vertexBufferOffset * genericVertexBuffer.bytesPerElement,
                                                index: BufferIndex.meshPositions.rawValue)
            renderEncoder.setVertexBufferOffset(primitive.bonePropertyBufferOffset * bonePropertiesBuffer.bytesPerElement,
                                                index: BufferIndex.meshBoneProps.rawValue)
            renderEncoder.setFragmentBytes(&tapRequestedInt, length: MemoryLayout<UInt32>.stride, index: 15)
            renderEncoder.setFragmentBytes(&entityID, length: MemoryLayout<UInt32>.stride, index: 16)
            
            Renderer.bindingManager.bindFragmentTexture(cmd: renderEncoder,
                                                        slot: TextureIndex.color.rawValue,
                                                        texture: primitive.material.albedoTexture)
            Renderer.bindingManager.bindFragmentTexture(cmd: renderEncoder,
                                                        slot: TextureIndex.normal.rawValue,
                                                        texture: primitive.material.normalTexture)
            Renderer.bindingManager.bindFragmentTexture(cmd: renderEncoder,
                                                        slot: TextureIndex.PBR.rawValue,
                                                        texture: primitive.material.pbrTexture)
            let emission = primitive.material.emissiveTexture()
            Renderer.bindingManager.bindFragmentTexture(cmd: renderEncoder,
                                                        slot: TextureIndex.emission.rawValue,
                                                        texture: emission)
            Renderer.bindingManager.bindFragmentTexture(cmd: renderEncoder,
                                                        slot: TextureIndex.environmentIBL.rawValue,
                                                        texture: environmentIBL)
            Renderer.bindingManager.bindFragmentTexture(cmd: renderEncoder,
                                                        slot: TextureIndex.environmentReflection.rawValue,
                                                        texture: environmentCubemap)
            
            renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                indexCount: primitive.indices.count,
                                                indexType: .uint32,
                                                indexBuffer: genericIndexBuffer.backingBuffers[0],
                                                indexBufferOffset: 4 * primitive.indexBufferOffset,
                                                instanceCount: 1,
                                                baseVertex: 0,
                                                baseInstance: 0)
            
        }
    }
    
    
    func applyTwoWayClamping(commandBuffer: MTLCommandBuffer, texture: MTLTexture, mini: Float, maxi: Float) {
        struct statics {
            static var pipelineState: MTLComputePipelineState? = nil
            static var descriptor = MTLComputePassDescriptor()
        }
        
        if statics.pipelineState == nil {
            let library = device.makeDefaultLibrary()
            do {
                statics.pipelineState = try device.makeComputePipelineState(
                    function: library!.makeFunction(name: "minmaxKernel")!
                )
            } catch {
                print(error.localizedDescription)
            }
        }
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder(descriptor: statics.descriptor)
        computeEncoder?.setComputePipelineState(statics.pipelineState!)
        computeEncoder?.setTexture(texture, index: 0)
        
        var minmax = simd_float2(x: mini, y: maxi)
        computeEncoder?.setBytes(&minmax, length: 8, index: 0)
        
        let threadgroupSize = MTLSizeMake(32, 32, 1);
        
        var threadgroupCount = MTLSize()
        threadgroupCount.width  = (texture.width  + threadgroupSize.width -  1) / threadgroupSize.width;
        threadgroupCount.height = (texture.height + threadgroupSize.height - 1) / threadgroupSize.height;
        threadgroupCount.depth = 1;
        
        computeEncoder?.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        
        computeEncoder?.endEncoding()
    }
    
    func renderLightShadow(commandEncoder: MTLRenderCommandEncoder,
                           lightEntity: SHEntity, renderables: [SHEntity] )
    {
        let light: EPunctualLight = lightEntity.component()!.pointee
        let lightModel = lightEntity.transform.global.matrix
        var mconv3 = convertMatrix(input: lightModel)
        mconv3 = simd_transpose(extractRotation(input: mconv3))
        
        // setup light's view and projection matrices, and send them to the GPU
        var camera = simd_float4x4(1.0)
        camera = convertMatrix(input: mconv3) * camera
        camera.columns.3 += (camera.columns.0 * (-lightModel.columns.3.x))
        camera.columns.3 += (camera.columns.1 * (-lightModel.columns.3.y))
        camera.columns.3 += (camera.columns.2 * (-lightModel.columns.3.z))
        
        light.shadowProjection = matrix_perspective_right_hand(fovyRadians: light.outerConeAngle * 2, aspectRatio: 1.0, nearZ: 0.1, farZ: 50.0)
        var vpMatrix = light.shadowProjection * camera
        commandEncoder.setVertexBytes(&vpMatrix, length: MemoryLayout.size(ofValue: vpMatrix), index: 9)
        
        genericVertexBuffer.bindToVertexSlot(renderEncoder: commandEncoder,
                                             slot: BufferIndex.meshPositions.rawValue,
                                             offset: 0)
        bonePropertiesBuffer.bindToVertexSlot(renderEncoder: commandEncoder, manager: Renderer.bindingManager,
                                              slot: BufferIndex.meshBoneProps.rawValue, offset: 0)
        boneAnimationBuffer.bindToVertexSlot(renderEncoder: commandEncoder, manager: Renderer.bindingManager,
                                             slot: BufferIndex.boneLocations.rawValue, offset: 0)
        
        for renderable in renderables {
            let meshComponent: UnsafeMutablePointer<EMeshComponent>? = gltfRegistry?[renderable]
            if let meshComponent = meshComponent, let mesh = genericMeshes[meshComponent.pointee.meshName] {
                let boneAnimation: UnsafeMutablePointer<EBoneAnimationComponent>? = renderable.component()
                
                var vertexShaderOptions = VertexShaderOptions()
                if let boneAnimation = boneAnimation?.pointee.boneAnimation {
                    vertexShaderOptions.isBoneAnimated = true
                    vertexShaderOptions.boneOffset = uint(boneAnimation.rendererMatrixIndex)
                }
                
                var meshTransform = MeshTransform()
                meshTransform.baseTransform = renderable.transform.global.matrix
                meshTransform.normalTransform = renderable.transform.global.rotationMatrix
                
                commandEncoder.setVertexBytes(&meshTransform,
                                              length: MemoryLayout.stride(ofValue: meshTransform),
                                              index: BufferIndex.meshTransform.rawValue)
                
                
                commandEncoder.setVertexBytes(&vertexShaderOptions,
                                              length: MemoryLayout<VertexShaderOptions>.stride,
                                              index: BufferIndex.vertexShaderOptions.rawValue)
                
                for (_, primitive) in mesh.primitives.enumerated() {
                    if primitive.material.shadingModel == .opaque {
                        commandEncoder.setVertexBufferOffset(primitive.vertexBufferOffset * genericVertexBuffer.bytesPerElement,
                                                             index: BufferIndex.meshPositions.rawValue)
                        commandEncoder.setVertexBufferOffset(primitive.bonePropertyBufferOffset * bonePropertiesBuffer.bytesPerElement,
                                                             index: BufferIndex.meshBoneProps.rawValue)
                        
                        commandEncoder.drawIndexedPrimitives(type: .triangle,
                                                             indexCount: primitive.indices.count,
                                                             indexType: .uint32,
                                                             indexBuffer: genericIndexBuffer.backingBuffers[0],
                                                             indexBufferOffset: 4 * primitive.indexBufferOffset,
                                                             instanceCount: 1,
                                                             baseVertex: 0,
                                                             baseInstance: 0)
                    }
                    
                }
            }
        }
    }
    
    let drawDispatchQueue: DispatchQueue = .init(label: "com.shaderheart.RendererDraw")
    
    func draw(in view: MTKView) {
        /// Per frame updates hare
        let currentTime = CFAbsoluteTimeGetCurrent()
        Renderer.deltaTime = Double(currentTime - Renderer.lastTime)
        Renderer.lastTime = currentTime
        
        // TODO: This does not belong here!
        ContentView.nodeDetailModel.update()
        
        if !GameStateManager.isGamePaused {
            if let registry = gltfRegistry {
                RenderingSystem.tick(deltaTime: Renderer.deltaTime, registry: registry)
                
                registry.advanceAnimations(deltaTime: Renderer.deltaTime)
                ERelationshipComponent.propagateTransforms(registry: registry)
            }
            
            // advance bone animations
            boneAnimationBuffer.reset(device: device, keepingCapacity: true)
            for (_, boneAnimation) in gltfRegistry?.boneAnimations ?? [:] {
                boneAnimation.updateBuffer(buffer: boneAnimationBuffer)
            }
        }
        
        Renderer.bufferSemaphore.wait()
        MetalView.stateUpdateSemaphore.wait()
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            self.updateDynamicBufferState()
            Renderer.bindingManager.reset()
            availableShadowRenderPasses = shadowRenderPasses
            
            // advance videotextures
            for (_, videoTexture) in videoTextures {
                if videoTexture.enabled {
                    videoTexture.render(cmd: commandBuffer)
                }
            }
            
            if tapDispatched {
                let tappedId = genericCPUBuffer.lastBufferView[0].selected_id
                if tappedId != 0 {
                    genericCPUBuffer.lastBufferView[0].selected_id = 0
                    tappedEntity = inverseTappableMap[tappedId]
                    
                    let tappable: ETappableComponent? = tappedEntity?.component()
                    tappable?.justTapped = true
                    
                    tapCaptured = true
                    tapDispatched = false
                    print("tapped id: \(tappedId), entity: \(String(describing: tappedEntity))")
                }
            }
            
            self.updateGameState()
            
            camera.frustum.viewMatrix = camera.matrix
            camera.frustum.setFromMV(camera.projection)
            
            if !GameStateManager.isGamePaused {
                encodeCompute(kernelName: "processSimpleParticles", commandBuffer: commandBuffer) { encoder in
                    SimpleParticleManager.dispatch(encoder: encoder, deltaTime: Renderer.deltaTime)
                    encoder.endEncoding()
                }
            }
            let renderables = gltfRegistry?.view(types: [EMeshComponent.self])
            
            // Render shadows
            if let renderables = renderables {
                gltfRegistry?.forEach(types: [EPunctualLight.self]) { entity in
                    guard availableShadowRenderPasses.count > 0 else {
                        return
                    }
                    
                    if let light: EPunctualLight = entity.component(), light.type == .spot, light.castsShadows {
                        let targetPass = availableShadowRenderPasses.popLast()!
                        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: targetPass.currentPassDescriptor) {
                            light.shadowTexture = targetPass.depthTarget?.currentTarget
                            pipelines["spotlightShadow"]?.use(renderEncoder: renderEncoder)
                            renderLightShadow(commandEncoder: renderEncoder, lightEntity: entity, renderables: renderables)
                            renderEncoder.endEncoding()
                        }
                    }
                }
            }
            
            
            /// Render to an offscreen buffer
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPasses["testPass"]!.currentPassDescriptor) {
                renderEncoder.label = "Offscreen Render Encoder"
                uniformBuffer.bindToVertexSlot(renderEncoder: renderEncoder, manager: Renderer.bindingManager,
                                               slot: BufferIndex.uniforms.rawValue, offset: 0)
                uniformBuffer.bindToFragmentSlot(renderEncoder: renderEncoder, manager: Renderer.bindingManager,
                                                 slot: BufferIndex.uniforms.rawValue, offset: 0)
                
                renderEncoder.pushDebugGroup("Generic Pipeline")
                pipelines["genericPipeline"]?.use(renderEncoder: renderEncoder)
                
                if let registry = gltfRegistry {
                    if tapRequested {
                        tapPositionUV.x = tapPosition.x / CGFloat(renderPasses["testPass"]!.renderTargets[0].currentTarget.width)
                        tapPositionUV.y = tapPosition.y / CGFloat(renderPasses["testPass"]!.renderTargets[0].currentTarget.height)
                        print("Will capture a tap at \(tapPositionUV)")
                        tappableMap.removeAll()
                        inverseTappableMap.removeAll()
                        registry.forEach(types: [EMeshComponent.self]) { entity in
                            tappableMap[entity] = UInt32(tappableMap.count)
                            inverseTappableMap[tappableMap[entity]!] = entity
                        }
                        tapDispatched = true
                    }
                    
                    if let renderables = renderables {
                        for entity in renderables {
                            let meshComponent: UnsafeMutablePointer<EMeshComponent>? = gltfRegistry?[entity]
                            if let meshComponent = meshComponent, let mesh = genericMeshes[meshComponent.pointee.meshName] {
                                let transformComponent = entity.transform
                                let boneAnimationComponent: UnsafeMutablePointer<EBoneAnimationComponent>? = entity.component()
                                if camera.frustum.check(mesh: mesh, transform: transformComponent.global) {
                                    drawGenericMesh(renderEncoder: renderEncoder, mesh: mesh, entity: entity, renderMode: .opaque,
                                                    boneAnimation: boneAnimationComponent?.pointee.boneAnimation)
                                }
                            }
                        }
                    }
                    tapRequested = false
                }
                
                renderEncoder.popDebugGroup()
                
                /// Render alpha-clipped primitives
                pipelines["alphaClipPipeline"]?.use(renderEncoder: renderEncoder)
                
                if let renderables = renderables {
                    for entity in renderables {
                        let meshComponent: UnsafeMutablePointer<EMeshComponent>? = gltfRegistry?[entity]
                        if let meshComponent = meshComponent, let mesh = genericMeshes[meshComponent.pointee.meshName] {
                            let transformComponent = entity.transform
                            if mesh.containsAlphaClippedPrimitives, camera.frustum.check(mesh: mesh, transform: transformComponent.global) {
                                let boneAnimationComponent: UnsafeMutablePointer<EBoneAnimationComponent>? = entity.component()
                                drawGenericMesh(renderEncoder: renderEncoder, mesh: mesh, entity: entity, renderMode: .alphaClipped,
                                                boneAnimation: boneAnimationComponent?.pointee.boneAnimation)
                            }
                        }
                        
                    }
                }
                
                /// Render lights
                pipelines["lighting"]!.use(renderEncoder: renderEncoder)
                
                uniformBuffer.bindToVertexSlot(renderEncoder: renderEncoder, manager: Renderer.bindingManager,
                                               slot: BufferIndex.uniforms.rawValue, offset: 0)
                uniformBuffer.bindToFragmentSlot(renderEncoder: renderEncoder, manager: Renderer.bindingManager,
                                                 slot: BufferIndex.uniforms.rawValue, offset: 0)
                
                gltfRegistry?.forEach(types: [EPunctualLight.self]) { entity in
                    let tform = entity.transform
                    if let light: EPunctualLight = entity.component(), light.type != .directional {
                        drawPunctualLight(renderEncoder: renderEncoder, light: light, transform: tform)
                    }
                }
                
                
                pipelines["directionalLighting"]!.use(renderEncoder: renderEncoder)
                gltfRegistry?.forEach(types: [EPunctualLight.self]) { entity in
                    let tform = entity.transform
                    if let light: EPunctualLight = entity.component(), light.type == .directional {
                        drawDirectionalLight(renderEncoder: renderEncoder, light: light, transform: tform)
                    }
                }
                
                /// Render glass  primitives
                pipelines["glassPipeline"]?.use(renderEncoder: renderEncoder)
                
                if let renderables = renderables {
                    for entity in renderables {
                        let meshComponent: UnsafeMutablePointer<EMeshComponent>? = gltfRegistry?[entity]
                        if let meshComponent = meshComponent, let mesh = genericMeshes[meshComponent.pointee.meshName] {
                            let transformComponent = entity.transform
                            if mesh.containsGlassPrimitives, camera.frustum.check(mesh: mesh, transform: transformComponent.global) {
                                let boneAnimationComponent: UnsafeMutablePointer<EBoneAnimationComponent>? = entity.component()
                                drawGenericMesh(renderEncoder: renderEncoder, mesh: mesh, entity: entity, renderMode: .glass,
                                                boneAnimation: boneAnimationComponent?.pointee.boneAnimation)
                            }
                        }
                    }
                }
                
                
                /// Render particles
                renderEncoder.pushDebugGroup("Particle Pipeline")
                
                pipelines["simpleParticle"]!.use(renderEncoder: renderEncoder)
                let triangleCount = SimpleParticleManager.activeParticles
                if triangleCount > 0 {
                    simpleParticleVertexBuffer.bindToVertexSlot(renderEncoder: renderEncoder, manager: Renderer.bindingManager, slot: 0)
                    
                    var invRotation = simd_matrix4x4(camera.rotation.inverse)
                    renderEncoder.setVertexBytes(&invRotation, length: MemoryLayout.size(ofValue: invRotation), index: 10)
                    
                    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: triangleCount * 3, instanceCount: 1, baseInstance: 0)
                }
                renderEncoder.popDebugGroup()
                
                
                renderEncoder.endEncoding()
            }
            
            if !GameStateManager.isGamePaused, let registry = gltfRegistry {
                SimpleParticleManager.tick(deltaTime: Renderer.deltaTime, registry: registry)
            }
            
            if environmentRenderingEnabled {
                encodeCompute(kernelName: "drawEnvironmentCubemap", commandBuffer: commandBuffer) { computeEncoder in
                    let outputTexture = self.renderPasses["testPass"]!.renderTargets[0].currentTarget!
                    computeEncoder.setTexture(self.environmentCubemap, index: 0)
                    computeEncoder.setTexture(outputTexture, index: 1)
                    
                    let threadgroupSize = MTLSizeMake(32, 32, 1);
                    var threadgroupCount = MTLSize()
                    threadgroupCount.width  = (outputTexture.width  + threadgroupSize.width - 1) / threadgroupSize.width;
                    threadgroupCount.height = (outputTexture.height + threadgroupSize.height - 1) / threadgroupSize.height;
                    threadgroupCount.depth = 1;
                    
                    var outputSize = simd_float2(Float(outputTexture.width), Float(outputTexture.height))
                    computeEncoder.setBytes(&outputSize, length: MemoryLayout.size(ofValue: outputSize), index: 0)
                    
                    let inverseViewProjection = simd_inverse(self.camera.projection * self.camera.matrix)
                    let ulDirection = inverseViewProjection * simd_float4(-1, 1, 1, 1);
                    let urDirection = inverseViewProjection * simd_float4(1, 1, 1, 1);
                    let llDirection = inverseViewProjection * simd_float4(-1, -1, 1, 1);
                    let lrDirection = inverseViewProjection * simd_float4(1, -1, 1, 1);
                    
                    var directions = simd_float4x4(ulDirection, urDirection, llDirection, lrDirection);
                    computeEncoder.setBytes(&directions, length: MemoryLayout.size(ofValue: directions), index: 1)
                    
                    computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
                    
                    computeEncoder.endEncoding()
                }
            }
            
            
            let scaleFactor = renderPasses["postprocessing"]?.options.scaleFactor ?? 0.25
            var scale = MPSScaleTransform(scaleX: scaleFactor, scaleY: scaleFactor, translateX: 0, translateY: 0)
            let scaler = MPSImageBilinearScale(device: device)
            
            withUnsafePointer(to: &scale) { (transformPtr: UnsafePointer<MPSScaleTransform>) -> () in
                scaler.scaleTransform = transformPtr
                scaler.encode(commandBuffer: commandBuffer,
                              sourceTexture: renderPasses["testPass"]!.renderTargets[0].currentTarget,
                              destinationTexture: renderPasses["postprocessing"]!.renderTargets[0].currentTarget
                )
            }
            
            applyTwoWayClamping(commandBuffer: commandBuffer,
                                texture: renderPasses["postprocessing"]!.renderTargets[0].currentTarget,
                                mini: 2.0, maxi: 50.0)
            
            
            let kernel = MPSImageGaussianBlur(device: device, sigma: 13.0)
            kernel.options = [.allowReducedPrecision]
            kernel.encode(commandBuffer: commandBuffer, inPlaceTexture: &renderPasses["postprocessing"]!.renderTargets[0].currentTarget)
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            
            if let renderPassDescriptor = renderPassDescriptor {
                
                /// Final pass rendering code here
                if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                    renderEncoder.label = "Primary Render Encoder"
                    
                    self.pipelines["main"]!.use(renderEncoder: renderEncoder)
                    
                    renderEncoder.setFragmentTexture(renderPasses["testPass"]!.renderTargets[0].currentTarget, index: 0)
                    renderEncoder.setFragmentTexture(renderPasses["postprocessing"]!.renderTargets[0].currentTarget, index: 1)
                    renderEncoder.setCullMode(.none)
                    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                    
                    renderEncoder.endEncoding()
                    
                    if let drawable = view.currentDrawable {
                        commandBuffer.present(drawable)
                    }
                }
            }
            
            commandBuffer.commit()
        }
        MetalView.stateUpdateSemaphore.signal()
        Renderer.bufferSemaphore.signal()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
        
        if size.width != 0 && size.height != 0 {
            let aspect = Float(size.width) / Float(size.height)
            Renderer.mainWidth = Int(size.width)
            Renderer.mainHeight = Int(size.height)
            camera.aspectRatio = aspect
            for rp in renderPasses.values {
                if rp.options.resizeWithFramebuffer {
                    rp.initializePassWithSize(device: device, width: Int(size.width), height: Int(size.height))
                }
            }
        }
    }
}
