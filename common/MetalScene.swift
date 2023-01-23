//
//  MetalScene.swift
//  swiftui-test
//
//  Created by utku on 29/09/2022.
//

import Foundation
import simd
import Metal
import MetalKit

class MetalTransform {
    private var blockSetCalls = false
    private func setGuard(callee: () -> Void){
        if !blockSetCalls {
            blockSetCalls = true
            callee()
            blockSetCalls = false
        }
    }
    var matrix = simd_float4x4() {
        didSet {
            setGuard { (translation, rotation, scale) = matrix_decomposeSimple(matrix: matrix)}
        }
    }
    var rotationMatrix: simd_float4x4 {
        get { simd_float4x4(rotation) }
    }
    var scale = simd_float3(repeating: 1.0) {
        didSet {
            setGuard { matrix = matrix4x4_translation(translation.x, translation.y, translation.z) *
                matrix_float4x4(rotation) *
                matrix4x4_scale(scale.x, scale.y, scale.z)
            }
        }
    }
    var rotation = simd_quatf() {
        didSet {
            setGuard {matrix = matrix4x4_translation(translation.x, translation.y, translation.z) *
                            matrix_float4x4(rotation) *
                            matrix4x4_scale(scale.x, scale.y, scale.z)
            }
        }
    }
    var translation = simd_float3(repeating: 0.0) {
        didSet {
            setGuard { matrix = matrix4x4_translation(translation.x, translation.y, translation.z) *
                            matrix_float4x4(rotation) *
                            matrix4x4_scale(scale.x, scale.y, scale.z)
            }
        }
    }
    
    init(matrix: simd_float4x4){
        self.matrix = matrix
        (self.translation, self.rotation, self.scale) = matrix_decomposeSimple(matrix: matrix)
    }
    
    init(translation: simd_float3 = simd_float3(repeating: 0.0),
         rotation: simd_quatf = simd_quatf(),
         scale: simd_float3 = simd_float3(repeating: 1.0)
    ){
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
        self.matrix = matrix4x4_translation(translation.x, translation.y, translation.z) *
                        matrix_float4x4(rotation) *
                        matrix4x4_scale(scale.x, scale.y, scale.z)
    }
}

class MetalSceneNode {
    var globalTransform: MetalTransform!
    var mesh: MetalMesh!
}

class MetalTexture {
    
}

class MetalMaterial {
    enum AlphaMode: String {
        case opaque = "OPAQUE"
        case mask = "MASK"
        case blend = "BLEND"
    }
    var name = ""
    
    var baseColor = simd_float4(repeating: 1.0)
    var baseColorTexture: MetalTexture?
    var metallic: Float = 1.0
    var roughness: Float = 1.0
    var metallicRoughnessTexture: MetalTexture?

    var normalTexture: MetalTexture?
    var occlusionTexture: MetalTexture?
    var emissiveTexture: MetalTexture?
    
    var emissiveFactor = simd_float3(repeating: 0.0)
    var doubleSided = false
    var alphaMode: AlphaMode = .opaque
    var alphaCutoff: Float = 0.5
}


class MetalBuffer<T> {
    var buffer: MTLBuffer!
    var capacity = 0
    var count = 0
    
    func resize(device: MTLDevice, newSize: Int) {
        let newBuffer = device.makeBuffer(bytes: buffer.contents(), length: newSize)
        buffer = newBuffer
        capacity = newSize
    }
    
    func withMutableBytes(callee: (UnsafeMutablePointer<T>) -> Void) {
        let ptr = buffer.contents().bindMemory(to: T.self, capacity: capacity)
        callee(ptr)
    }
    
    func append(from: UnsafePointer<T>, count: Int = 1){
        buffer.contents().advanced(by: self.count * MemoryLayout<T>.stride).copyMemory(from: from, byteCount: count * MemoryLayout<T>.stride)
        self.count += count
    }
}

class MetalPrimitive {
    var indexCount = 0
    var indexBufferOffset = 0
    var indexType: MTLIndexType = .uint32
    var primitiveType: MTLPrimitiveType = .triangle
    var materialIndex = 0
    
}

class MetalMesh {
    var positionBufferOffset = 0
    var primitives: [MetalPrimitive] = []
}

@objcMembers
class UltimateVertex: NSObject {
    var position: simd_float3 = .init(repeating: 0)
    var normal: simd_float3 = .init(repeating: 0)
    var texcoord_0: simd_float2 = .init(repeating: 0)
    var texcoord_1: simd_float2 = .init(repeating: 0)
    var tangent: simd_float3 = .init(repeating: 0)
    var color: simd_float3 = .init(repeating: 0)
    var boneWeights: simd_float4 = .init(repeating: 0)
    var boneIndices: simd_uint4 = .init(repeating: 0)
    var materialIndex: UInt8 = 0
    
    func convert<T>() -> T? {
        if T.self == GenericVertex.self {
            var v = GenericVertex()
            v.position = position
            v.normal = normal
            v.texcoord_0 = texcoord_0
            v.texcoord_1 = texcoord_1
            v.tangent = tangent
            v.materialIndex = materialIndex
            return v as? T
        } else if T.self == BoneVertex.self {
            var v = BoneVertex()
            v.position = position
            v.normal = normal
            v.texcoord_0 = texcoord_0
            v.texcoord_1 = texcoord_1
            v.tangent = tangent
            v.boneWeights = boneWeights
            v.boneIndices = boneIndices
            v.materialIndex = materialIndex
            return v as? T
        }
        
        return nil
    }
    
    func getBoneProperties() -> BoneProperties {
        var props = BoneProperties()
        props.boneIndices = boneIndices
        props.boneWeights = boneWeights
        return props
    }
    
    func toPrototype() -> UltimateVertexPrototype {
        var prototype = UltimateVertexPrototype()
        prototype.position = position
        prototype.normal = normal
        prototype.texcoord_0 = texcoord_0
        prototype.texcoord_1 = texcoord_1
        prototype.tangent = tangent
        prototype.color = color
        prototype.boneWeights = boneWeights
        prototype.boneIndices = boneIndices
        prototype.materialIndex = materialIndex
        return prototype
    }
    
    func fromPrototype(prototype: UltimateVertexPrototype) {
        position = prototype.position
        normal = prototype.normal
        texcoord_0 = prototype.texcoord_0
        texcoord_1 = prototype.texcoord_1
        tangent = prototype.tangent
        color = prototype.color
        boneWeights = prototype.boneWeights
        boneIndices = prototype.boneIndices
        materialIndex = prototype.materialIndex
    }
    
}

@objcMembers
class GenericPrimitive: NSObject {
    enum VertexType {
        case Generic
        case Bone
    }
    var vertices: [UltimateVertex] = []
    var vertexBufferOffset = 0
    var bonePropertyBufferOffset = 0
    var indices: [UInt32] = []
    var indexBufferOffset = 0
    var protoMaterial = GLTFFile.GLTFMaterial()
    var material = SwiftPBRMaterial()
    var isBoneAnimated = false

    
    init(primitive: GLTFFile.GLTFPrimitive) {
        var positionFloats: [Float]?
        var normalFloats: [Float]?
        var texcoord0Floats: [Float]?
        var texcoord1Floats: [Float]?
        var tangentFloats: [Float]?
        var weightFloats: [Float]?
        var jointUInts: [UInt32]?
        var vertexIndices: [UInt32] = []
        
        if let gltfMaterial = primitive.material?.reference {
            protoMaterial = gltfMaterial
        }
        
        if let position = primitive.attributes[.position] {
            positionFloats = position.copyAsCollection()
        }
        
        if let normal = primitive.attributes[.normal] {
            normalFloats = normal.copyAsCollection()
        }
        
        if let texcoord0 = primitive.attributes[.texcoord0] {
            texcoord0Floats = texcoord0.copyAsCollection()
        }
        
        if let texcoord1 = primitive.attributes[.texcoord1] {
            texcoord1Floats = texcoord1.copyAsCollection()
        }
        
        if let tangent = primitive.attributes[.tangent] {
            tangentFloats = tangent.copyAsCollection()
        }
        
        if let indices = primitive.indexAccessor {
            indices.copyWithTypeCast(into: &vertexIndices)
        }
        
        if let weights = primitive.attributes[.weights] {
            isBoneAnimated = true
            weightFloats = weights.copyAsCollection()
        }
        
        if let joints = primitive.attributes[.joints]{
            jointUInts = []
            joints.copyWithTypeCast(into: &jointUInts!)
        }
        
        let currentVertexCount = UInt32(vertices.count)
        
        for vertexIndex in 0..<primitive.vertexCount {
            var vertex = UltimateVertex()
            vertex.materialIndex = 0
            
            if let positions = positionFloats {
                let positionIndex = vertexIndex * 3
                vertex.position = simd_float3(positions[positionIndex...(positionIndex+2)])
            }
            
            if let normals = normalFloats {
                let normalIndex = vertexIndex * 3
                vertex.normal = simd_float3(normals[normalIndex...(normalIndex+2)])
            }
            
            if let tangents = tangentFloats {
                let tangentIndex = vertexIndex * 3
                vertex.tangent = simd_float3(tangents[tangentIndex...(tangentIndex+2)])
            }
            
            if let texcoords = texcoord0Floats {
                let texcoordIndex = vertexIndex * 2
                vertex.texcoord_0 = simd_float2(texcoords[texcoordIndex...(texcoordIndex+1)])
            }
            
            if let texcoords = texcoord1Floats {
                let texcoordIndex = vertexIndex * 2
                vertex.texcoord_1 = simd_float2(texcoords[texcoordIndex...(texcoordIndex+1)])
            }
            
            if let weights = weightFloats {
                let weightIndex = vertexIndex * 4
                vertex.boneWeights = simd_float4(weights[weightIndex...(weightIndex+3)])
            }
            
            if let joints = jointUInts {
                let jointIndex = vertexIndex * 4
                vertex.boneIndices = simd_uint4(joints[jointIndex...(jointIndex+3)])
            }
            
            vertices.append(vertex)
        }
        
        for index in vertexIndices {
            indices.append(currentVertexCount + index)
        }
    }
    
}

struct BoundingBox {
    
    
    init(fromMesh: GenericMesh) {
        var vertexMax = simd_float3(repeating: 9999999999.9)
        var vertexMin = simd_float3(repeating: -9999999999.9)
        
        for primitive in fromMesh.primitives {
            for vertex in primitive.vertices {
                vertexMax.x = (vertexMax.x < vertex.position[0]) ? vertex.position[0] : vertexMax.x;
                vertexMin.x = (vertexMin.x > vertex.position[0]) ? vertex.position[0] : vertexMin.x;
                vertexMax.y = (vertexMax.y < vertex.position[1]) ? vertex.position[1] : vertexMax.y;
                vertexMin.y = (vertexMin.y > vertex.position[1]) ? vertex.position[1] : vertexMin.y;
                vertexMax.z = (vertexMax.z < vertex.position[2]) ? vertex.position[2] : vertexMax.z;
                vertexMin.z = (vertexMin.z > vertex.position[2]) ? vertex.position[2] : vertexMin.z;
            }
        }
    }
}

struct CullingSphere {
    var radius: Float = 0.0
    var origin = simd_float4(0, 0, 0, 1)
    
    init() {}
    
    init(fromMesh: GenericMesh) {
        var vertexMax = simd_float3(repeating: 9999999999.9)
        var vertexMin = simd_float3(repeating: -9999999999.9)
        
        for primitive in fromMesh.primitives {
            for vertex in primitive.vertices {
                vertexMax.x = (vertexMax.x < vertex.position[0]) ? vertex.position[0] : vertexMax.x;
                vertexMin.x = (vertexMin.x > vertex.position[0]) ? vertex.position[0] : vertexMin.x;
                vertexMax.y = (vertexMax.y < vertex.position[1]) ? vertex.position[1] : vertexMax.y;
                vertexMin.y = (vertexMin.y > vertex.position[1]) ? vertex.position[1] : vertexMin.y;
                vertexMax.z = (vertexMax.z < vertex.position[2]) ? vertex.position[2] : vertexMax.z;
                vertexMin.z = (vertexMin.z > vertex.position[2]) ? vertex.position[2] : vertexMin.z;
            }
        }
        origin = simd_float4((vertexMax + vertexMin) * 0.5, 1.0)
        
        let origin3 = simd_float3(x: origin.x, y: origin.y, z: origin.z)
        
        var maxVertexLength: Float = -1.0
        for primitive in fromMesh.primitives {
            for vertex in primitive.vertices {
                let newLength = simd_length(vertex.position - origin3);
                if newLength > maxVertexLength {
                    maxVertexLength = newLength;
                }
            }
        }
        radius = maxVertexLength
    }
    
}

class GenericMesh {
    var name = ""
    var baseDir = ""
    var imported = false
    var primitives: [GenericPrimitive] = []
    var cullingSphere = CullingSphere()
    var containsAlphaClippedPrimitives = false
    var containsGlassPrimitives = false
    
    init(gltfMesh: GLTFFile.GLTFMesh) {
        name = gltfMesh.name
        for primitive in gltfMesh.primitives {
            primitives.append(GenericPrimitive(primitive: primitive))
        }
        cullingSphere = .init(fromMesh: self)
    }
}

class SwiftPBRMaterial {
    enum ShadingModel {
        case opaque
        case diffuseOnly
        case glass
        case transmissive
        case alphaClipped
        case alphaBlended
        case specular
    }
    var color = simd_float3(repeating: 1.0)
    var emissiveColor = simd_float3(repeating: 1.0)
    var roughness: Float = 0.5
    var metallic: Float = 0.0
    var emissivePower: Float = 0.0
    var alphaCutoff: Float = 1.0
    var glassIOR: Float = 1.5
    var albedoTexture: MTLTexture?
    var emissiveTexture: () -> MTLTexture? = {nil}
    var normalTexture: MTLTexture?
    var metallicTexture: MTLTexture?
    var roughnessTexture: MTLTexture?
    var pbrTexture: MTLTexture?
    
    var specularFactor = simd_float4(repeating: 1.0)
    var specularTexture: MTLTexture?
    
    var shadingModel: ShadingModel = .opaque

    var uvScale = simd_float2(repeating: 1.0)
    
    func getRenderMaterial() -> RenderPBRMaterial {
        var material = RenderPBRMaterial()
        material.color = color
        material.emissiveColor = emissiveColor
        material.roughness = roughness
        material.metallic = metallic
        material.emissivePower = emissivePower
        material.uvScale = uvScale

        material.albedoTexture = albedoTexture == nil ? -1 : 0
        material.normalTexture = normalTexture == nil ? -1 : 0
        material.metallicTexture = pbrTexture == nil ? -1 : 0
        material.roughnessTexture = pbrTexture == nil ? -1 : 0
        material.emissiveTexture = emissiveTexture() == nil ? -1 : 0
        return material
    }
    
    func getAlphaClippedMaterial() -> AlphaClipMaterial {
        var material = AlphaClipMaterial()
        material.color = color
        material.emissiveColor = emissiveColor
        material.roughness = roughness
        material.metallic = metallic
        material.emissivePower = emissivePower
        material.uvScale = uvScale
        material.alphaClipValue = alphaCutoff

        material.albedoTexture = albedoTexture == nil ? -1 : 0
        material.normalTexture = normalTexture == nil ? -1 : 0
        material.metallicTexture = pbrTexture == nil ? -1 : 0
        material.roughnessTexture = pbrTexture == nil ? -1 : 0
        material.emissiveTexture = emissiveTexture() == nil ? -1 : 0
        return material
    }
    
    func getGlassMaterial() -> RenderGlassMaterial {
        var material = RenderGlassMaterial()
        material.color = color
        material.albedoTexture = albedoTexture == nil ? -1 : 0
        material.roughness = roughness
        material.roughnessTexture = roughnessTexture == nil ? -1 : 0
        material.IOR = metallic
        material.IORTexture = metallicTexture == nil ? -1 : 0
        material.normalTexture = normalTexture == nil ? -1 : 0
        return material
    }
}

enum ChannelTargetType: String {
    case translation = "translation"
    case rotation = "rotation"
    case scale = "scale"
    case weights = "weights"
}

protocol AnimationChannelProtocol {
    var targetType: ChannelTargetType {get set}
    
    associatedtype T: SIMD<Float>
    func getValue(timestamp: Float) -> T
    
    var targetNode: GLTFFile.GLTFNode? {get set}
    var target: SHEntity! {get set}
    var length: Float {get set}
    func setTarget(target: SHEntity)
}

class AnimationChannel<T: SIMD<Float>>: AnimationChannelProtocol {
    
    enum Interpolation: String {
        case linear = "LINEAR"
        case step = "STEP"
        case cubic = "CUBICSPLINE"
    }
    
    var targetNode: GLTFFile.GLTFNode?
    weak var target: SHEntity!
    var targetType: ChannelTargetType = .translation
    var interpolation: Interpolation = .linear
    
    var timestamps: [Float] = []
    var keyframes: [T] = []
    var length: Float = 1.0
    
    init(fromGltfAnimationChannel: GLTFFile.GLTFAnimationChannel) {
        targetNode = fromGltfAnimationChannel.targetNode
        targetType = ChannelTargetType(rawValue: fromGltfAnimationChannel.targetType.rawValue)!
        interpolation = Interpolation(rawValue: fromGltfAnimationChannel.sampler.interpolation.rawValue)!
        timestamps = fromGltfAnimationChannel.sampler.timestamps.copyAsCollection()
        length = timestamps.last!
        
        let keyframeFloats: [Float] = fromGltfAnimationChannel.sampler.keyframes.copyAsCollection()
        
        if T.self == Float.self {
            keyframes = keyframeFloats as! [T]
        } else {
            var index = 0
            let maxIndex = keyframeFloats.count
            while index < maxIndex {
                if T.self == simd_float3.self {
                    keyframes.append(simd_float3(keyframeFloats[(index)...(index+2)]) as! T)
                    index += 3
                } else if T.self == simd_quatf.self {
                    keyframes.append(simd_quatf(keyframeFloats[(index)...(index+3)]) as! T)
                    index += 4
                }
            }
        }
    }
    
    func setTarget(target: SHEntity){
        self.target = target
    }
    
    func getValue(timestamp: Float) -> T {
        var currentIndex = 1
        
        var lastTimestamp = timestamps[0]
        var weight: Float = 1.0
        
        if lastTimestamp > timestamp {
            return keyframes[0]
        }
        
        while currentIndex < (timestamps.count - 1){
            if timestamp > lastTimestamp && timestamp <= timestamps[currentIndex] {
                weight = (timestamp - lastTimestamp) / (timestamps[currentIndex] - lastTimestamp)
                break
            }
            lastTimestamp = timestamps[currentIndex]
            currentIndex += 1
        }
        if T.self == simd_quatf.self {
            return simd_slerp(keyframes[currentIndex - 1] as! simd_quatf, keyframes[currentIndex]  as! simd_quatf, weight) as! T
        } else {
            return keyframes[currentIndex - 1] * (1.0 - weight) + keyframes[currentIndex] * weight
        }
    }
}

class NodeAnimation {
    var channels: [any AnimationChannelProtocol] = []
    var currentTime: Float = 0.0
    var length: Float = 0.0
    var enabled = true
    var playbackSpeed = 1.0
    
    init(fromGltfAnimation: GLTFFile.GLTFAnimation) {
        for channel in fromGltfAnimation.channels {
            print(channel)
            switch channel.targetType {
                
            case .translation:
                let newChannel = AnimationChannel<simd_float3>(fromGltfAnimationChannel: channel)
                channels.append(newChannel)
            case .rotation:
                let newChannel = AnimationChannel<simd_quatf>(fromGltfAnimationChannel: channel)
                channels.append(newChannel)

            case .scale:
                let newChannel = AnimationChannel<simd_float3>(fromGltfAnimationChannel: channel)
                channels.append(newChannel)

            case .weights:
                let newChannel = AnimationChannel<Float>(fromGltfAnimationChannel: channel)
                channels.append(newChannel)

            }
        }
        
        for channel in channels {
            if channel.length > length {
                length = channel.length
            }
        }
        
        print(fromGltfAnimation.name)
    }
    
    func advance(deltaTime: Double) {
        if playbackSpeed != 0.0 {
            currentTime += Float(deltaTime * playbackSpeed)
            currentTime = currentTime.truncatingRemainder(dividingBy: length)
        }
        
        for channel in channels {
            if let target = channel.target{
                switch channel.targetType {
                case .translation:
                    target.transform.local.translation = channel.getValue(timestamp: Float(currentTime)) as! simd_float3
                case .rotation:
                    target.transform.local.rotation = channel.getValue(timestamp: Float(currentTime)) as! simd_quatf
                case .scale:
                    target.transform.local.scale = channel.getValue(timestamp: Float(currentTime)) as! simd_float3
                default:
                    break
                }
            }
        }
    }
}

class BoneAnimation {
    var inverseBindMatrices = [simd_float4x4]()
    var jointNodes = [SHEntity]()
    var rendererMatrixIndex = 0
    var connectedAnimation: NodeAnimation?
    
    init(skin: GLTFFile.GLTFSkin, nodeEntityMap: [GLTFFile.GLTFNode: SHEntity]) {
        skin.inverseBindMatrices?.forEach { (ibm: simd_float4x4) in
            inverseBindMatrices.append(ibm)
        }
        
        for node in skin.joints {
            let entity = nodeEntityMap[node]!
            jointNodes.append(entity)
        }
    }
}
