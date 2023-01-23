//
//  BasicGLTF.swift
//  swiftui-test
//
//  Created by utku on 25/09/2022.
//

import Foundation
import simd


#if GLTFMetalBindings

import Metal
import MetalKit

#endif

enum VertexAttribute: String {
    case position = "POSITION"
    case normal = "NORMAL"
    case texcoord0 = "TEXCOORD_0"
    case texcoord1 = "TEXCOORD_1"
    case tangent = "TANGENT"
    case color = "COLOR_0"
    case color1 = "COLOR_1"
    case joints = "JOINTS_0"
    case joints1 = "JOINTS_1"
    case weights = "WEIGHTS_0"
    case weights1 = "WEIGHTS_1"
}

protocol JSONLoadable {
    /**
    Initializes the conforming type from JSON data.

    - Parameters:
    - jsonData: A dictionary of JSON data that represents an instance of the conforming type.
    */
    init(jsonData: [String: Any])
}

/**
 Loads a list of values from a JSON dictionary.
 
 - Parameters:
    - name: The name of the property to read from the JSON dictionary.
    - target: A reference to the list to store the values in.
    - data: The JSON dictionary to read the values from.
*/
func loadListFromJSON<T: JSONLoadable>(name: String, target: inout [T], data: [String: Any]){
    if let entries = data[name] as? [[String: Any]] {
        for entry in entries {
            let entry = T(jsonData: entry)
            target.append(entry)
        }
    }
}

/**
 Sets a property from a JSON dictionary, if the value is present.
 
 - Parameters:
    - name: The name of the property to set.
    - target: A reference to the property to set.
    - data: The JSON dictionary to read the value from.
*/
func setFromJSONOptional<T>(name: String, target: inout T, data: [String: Any]){
    if let variable = data[name] as? T {
        target = variable
    }
}

/**
 Calls a function with a value from a JSON dictionary, if the value is present.
 
 - Parameters:
    - name: The name of the property to read.
    - data: The JSON dictionary to read the value from.
    - function: The function to call with the value from the JSON dictionary.
*/
func setFromJSONOptional<T>(name: String, data: [String: Any], function: (T) -> ()){
    if let variable = data[name] as? T {
        function(variable)
    }
}

func forEachOptional<T, V>(collection: T?, process: ((V) -> ())){
    if let castCollection = collection as? [V] {
        for item in castCollection {
            process(item)
        }
    }
}

class GLTFFile {
    
    // MARK: Primitive, Mesh, Skin
    class GLTFPrimitive {
        /// An enumeration of the different drawing modes for the primitive.
        enum Mode: Int {
            case points = 0
            case lines = 1
            case lineLoop = 2
            case lineStrip = 3
            case triangles = 4
            case triangleStrip = 5
            case triangleFan = 6
        }
        
        /// A mapping of vertex attributes to their indices in the attribute array.
        static let attributeMapping: [VertexAttribute: Int] = [
            .position: 0, .normal: 1, .texcoord0: 2, .tangent: 3, .joints: 4, .weights: 5, .texcoord1: 6, .color: 7
        ]
        
        /// The attributes of the vertices in the primitive, mapped to their corresponding `GLTFAccessor` objects.
        var attributes: [VertexAttribute: GLTFAccessor] = [:]
        
        /// The accessor that contains the indices of the vertices in the primitive.
        var indexAccessor: GLTFAccessor?
        
        /// The material to use when rendering the primitive.
        var material: IndexedReference<GLTFMaterial>?
        
        /// The drawing mode for the primitive.
        var mode: Mode? = .triangles
        
        /// Number of vertices in the primitive
        var vertexCount = 0
        
        /// Number of indices in the primitive
        var indexCount = 0
    }
    
    class GLTFMesh {
        var name = ""
        var primitives: [GLTFPrimitive] = []
        
        func getVerticesAsFloats() -> [Float] {
            var positions = [Float]()
            for primitive in primitives {
                if primitive.indexCount > 0 {
                    var indices: [Int] = []
                    primitive.indexAccessor?.copyWithTypeCast(into: &indices)
                    primitive.attributes[VertexAttribute.position]?.withArray { (x: [Float]) in
                        for index in indices {
                            positions.append(x[index * 3])
                            positions.append(x[index * 3 + 1])
                            positions.append(x[index * 3 + 2])
                        }
                    }
                }else{
                    primitive.attributes[VertexAttribute.position]?.forEach { (x: Float) in
                        positions.append(x)
                    }
                }
            }
            return positions
        }
    }
    
    class GLTFSkin {
        var name = ""
        var inverseBindMatrices: GLTFAccessor?
        weak var skeleton: GLTFNode?
        var joints: [GLTFNode] = []
    }
    
    // MARK: Cameras
    class GLTFCameraOrtographic {
        var xmag: Float = 1.0
        var ymag: Float = 1.0
        var zfar: Float = 1.0
        var znear: Float = 0.01
    }
    
    class GLTFCameraPerspective {
        var aspectRatio: Float = 1.0
        var fov: Float = .pi / 2.0
        var zFar: Float = 1.0
        var zNear: Float = 0.01
    }
    
    class GLTFCamera {
        enum CameraType: String {
            case perspective = "perspective"
            case orthographic = "orthographic"
        }
        var orthographic: GLTFCameraOrtographic?
        var perspective: GLTFCameraPerspective?
        var type: CameraType = .orthographic
        
        
        init(input: [String: Any]) {
            
        }
    }

    // MARK: Transform, Reference and Node
    class GLTFTransform {
        /// A flag that indicates whether the `setGuard` function is currently blocking set calls.
        private var blockSetCalls = false
        
        /**
         A helper function that ensures that only one property is set at a time.
         
         - Parameters:
            - callee: The function to call to set a property.
        */
        private func setGuard(callee: () -> Void){
            if !blockSetCalls {
                blockSetCalls = true
                callee()
                blockSetCalls = false
            }
        }
        
        /// The 4x4 transformation matrix that encodes the translation, rotation, and scale of the object.
        var matrix = simd_float4x4() {
            didSet {
                setGuard { (translation, rotation, scale) = matrix_decomposeSimple(matrix: matrix)}
            }
        }
        
        /// The rotation matrix derived from the `rotation` property.
        var rotationMatrix: simd_float4x4 {
            get { simd_float4x4(rotation) }
        }
        
        /// The scale of the object.
        var scale = simd_float3(repeating: 1.0) {
            didSet {
                setGuard { matrix = matrix4x4_translation(translation.x, translation.y, translation.z) *
                    matrix_float4x4(rotation) *
                    matrix4x4_scale(scale.x, scale.y, scale.z)
                }
            }
        }
        
        /// The rotation of the object.
        var rotation = simd_quatf() {
            didSet {
                setGuard {matrix = matrix4x4_translation(translation.x, translation.y, translation.z) *
                                matrix_float4x4(rotation) *
                                matrix4x4_scale(scale.x, scale.y, scale.z)
                }
            }
        }
        
        /// The translation of the object.
        var translation = simd_float3(repeating: 0.0) {
            didSet {
                setGuard { matrix = matrix4x4_translation(translation.x, translation.y, translation.z) *
                                matrix_float4x4(rotation) *
                                matrix4x4_scale(scale.x, scale.y, scale.z)
                }
            }
        }
        
        /**
         Initializes the transform with a 4x4 matrix.
         
         - Parameters:
            - matrix: The 4x4 matrix to use for the transform.
        */
        init(matrix: simd_float4x4){
            self.matrix = matrix
            (self.translation, self.rotation, self.scale) = matrix_decomposeSimple(matrix: matrix)
        }
        
        /**
         Initializes the transform with translation, rotation, and scale values.
         
         - Parameters:
            - translation: The translation of the object. Defaults to `(0, 0, 0)`.
            - rotation: The rotation of the object. Defaults to the identity quaternion.
            - scale: The scale of the object. Defaults to `(1, 1, 1)`.
        */
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
    
    class IndexedReference<T> {
        var index: Int!
        var reference: T?
        
        init() {
            index = -1
        }
    }
    
    class GLTFNode: Hashable {
        // GLTF properties
        var name = ""
        var transform = GLTFTransform()

        weak var parent: GLTFNode?
        var children: [GLTFNode]?
        var childrenIndices: [Int]?

        var camera: GLTFCamera?
        var mesh: GLTFMesh?
        var skin: IndexedReference<GLTFSkin>?
        var weights: [Float]?
        var punctualLight: IndexedReference<PunctualLight>?
        
        var extras: [String: Any]?
        var shredProps: [String: Any]?
        var isPrototype = false
        
        // accessors and helpers
        var globalTransform: GLTFTransform?
        
        static func == (lhs: GLTFNode, rhs: GLTFNode) -> Bool {
            return lhs === rhs
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }
    
    // MARK: Texture, Materials and Lights
    class GLTFImage: JSONLoadable {
        var name: String?
        var uri: String?
        var mimeType: String?
        var bufferView: Int?
        
        var extensions: [String: Any]?
        var extras: [String: Any]?
        
        /**
         Initializes the `GLTFImage` from JSON data.
         
         - Parameters:
            - jsonData: A dictionary of JSON data that represents a GLTF image.
        */
        required init(jsonData: [String: Any]) {
            setFromJSONOptional(name: "name", target: &self.name, data: jsonData)
            setFromJSONOptional(name: "uri", target: &self.uri, data: jsonData)
            if self.uri != nil {
                if let uri = URL(string: self.uri!) {
                    self.uri = uri.relativePath
                }

            }
            setFromJSONOptional(name: "mimeType", target: &self.mimeType, data: jsonData)
            setFromJSONOptional(name: "bufferView", target: &self.bufferView, data: jsonData)
            setFromJSONOptional(name: "extensions", target: &self.extensions, data: jsonData)
            setFromJSONOptional(name: "extras", target: &self.extras, data: jsonData)
        }
    }
    
    class GLTFSampler: JSONLoadable {
        enum WrapMode: Int {
            case CLAMP_TO_EDGE = 33071
            case MIRRORED_REPEAT = 33648
            case REPEAT = 10497
        }
        enum FilterMode: Int {
            case NONE = 0
            case NEAREST = 9728
            case LINEAR = 9729
            case NEAREST_MIPMAP_NEAREST = 9984
            case LINEAR_MIPMAP_NEAREST = 9985
            case NEAREST_MIPMAP_LINEAR = 9986
            case LINEAR_MIPMAP_LINEAR = 9987
        }
        var name = ""
        var magFilter: FilterMode = .NONE
        var minFilter: FilterMode = .NONE
        var wrapS: WrapMode = .REPEAT
        var wrapT: WrapMode = .REPEAT
        
        var extensions: [String: Any]?
        var extras: [String: Any]?
        
        required init(jsonData: [String: Any]) {
            setFromJSONOptional(name: "name", target: &self.name, data: jsonData)
            setFromJSONOptional(name: "extensions", target: &self.extensions, data: jsonData)
            setFromJSONOptional(name: "extras", target: &self.extras, data: jsonData)
            
            magFilter = FilterMode.init(rawValue: jsonData["magFilter"] as? Int ?? 0)!
            minFilter = FilterMode.init(rawValue: jsonData["minFilter"] as? Int ?? 0)!
            wrapS = WrapMode.init(rawValue: jsonData["wrapS"] as? Int ?? 10497)!
            wrapT = WrapMode.init(rawValue: jsonData["wrapT"] as? Int ?? 10497)!
        }
    }
    
    class GLTFTexture: JSONLoadable {
        var name = ""
        var source: IndexedReference<GLTFImage> = .init()
        var sampler: IndexedReference<GLTFSampler> = .init()
        
        var extensions: [String: Any]?
        var extras: [String: Any]?
        
        required init(jsonData: [String: Any]) {
            setFromJSONOptional(name: "name", target: &self.name, data: jsonData)
            setFromJSONOptional(name: "source", target: &self.source.index, data: jsonData)
            setFromJSONOptional(name: "sampler", target: &self.sampler.index, data: jsonData)
        }
        
    }
    
    class GLTFTextureInfo: JSONLoadable {
        var index = 0
        var texCoord: String?
        var normalScale: Float?
        var occlusionStrength: Float?
        var texture: GLTFTexture?
        
        required init(jsonData: [String: Any]){
            self.index = jsonData["index"] as? Int ?? 0
            if let texC = jsonData["texCoord"] as? Int {
                texCoord = "TEXCOORD_\(texC)"
            }
            self.normalScale = jsonData["scale"] as? Float
            self.occlusionStrength = jsonData["strength"] as? Float
        }
    }
    
    class GLTFMaterial: JSONLoadable {
        enum AlphaMode: String {
            case opaque = "OPAQUE"
            case mask = "MASK"
            case blend = "BLEND"
        }
        
        enum RenderMode {
            case pbr
            case specular
            case transmissive
            case glass
        }
        
        var name = ""
        
        var baseColor = simd_float4(repeating: 1.0)
        var baseColorTexture: GLTFTextureInfo?
        var alphaOnlyTexture: GLTFTextureInfo?
        var metallic: Float = 1.0
        var roughness: Float = 1.0
        var metallicRoughnessTexture: GLTFTextureInfo?
        
        var normalTexture: GLTFTextureInfo?
        var occlusionTexture: GLTFTextureInfo?
        var emissiveTexture: GLTFTextureInfo?
        var specularTexture: GLTFTextureInfo?
        
        var specularFactor = simd_float3(repeating: 1.0)
        var specularStrength = 1.0
        
        var emissiveFactor = simd_float3(repeating: 0.0)
        var emissiveStrength: Float?
        var doubleSided = false
        
        var alphaMode: AlphaMode = .opaque
        var alphaCutoff: Float = 0.5
        
        var renderMode: RenderMode = .pbr
        
        var extensions: [String: Any]?
        var extras: [String: Any]?
        
        init(){}
        
        required init(jsonData: [String: Any]){
            if let pbr = jsonData["pbrMetallicRoughness"] as? [String: Any] {
                // numerics
                if let baseColor = pbr["baseColorFactor"] as? [Double] {
                    self.baseColor = simd_float4(Float(baseColor[0]),
                                                 Float(baseColor[1]),
                                                 Float(baseColor[2]),
                                                 Float(baseColor[3]))
                }
                self.metallic = Float(pbr["metallicFactor"] as? Double ?? 1.0)
                self.roughness = Float(pbr["roughnessFactor"] as? Double ?? 1.0)
                
                // textures
                if let colorTexture = pbr["baseColorTexture"] as? [String: Any] {
                    self.baseColorTexture = GLTFTextureInfo(jsonData: colorTexture)
                }
                if let mrTexture = pbr["metallicRoughnessTexture"] as? [String: Any] {
                    self.metallicRoughnessTexture = GLTFTextureInfo(jsonData: mrTexture)
                }
            }
            
            if let emissive = jsonData["emissiveFactor"] as? [Double] {
                self.emissiveFactor = simd_float3(x: Float(emissive[0]), y: Float(emissive[1]), z: Float(emissive[1]))
            }
            if let emissiveTexture = jsonData["emissiveTexture"] as? [String: Any] {
                self.emissiveTexture = GLTFTextureInfo(jsonData: emissiveTexture)
            }
            if let normalTexture = jsonData["normalTexture"] as? [String: Any] {
                self.normalTexture = GLTFTextureInfo(jsonData: normalTexture)
            }
            if let occlusionTexture = jsonData["occlusionTexture"] as? [String: Any] {
                self.occlusionTexture = GLTFTextureInfo(jsonData: occlusionTexture)
            }
            self.doubleSided = jsonData["doubleSided"] as? Bool ?? false
            self.alphaCutoff = Float(jsonData["alphaCutoff"] as? Double ?? 0.5)
            if let alphaMode = jsonData["alphaMode"] as? String {
                self.alphaMode = AlphaMode.init(rawValue: alphaMode) ?? .opaque
            }
            
            // TODO: handle material extensions
            if let extensions = jsonData["extensions"] as? [String: Any] {
                self.extensions = extensions
                if let emissiveStrengthExtension = extensions["KHR_materials_emissive_strength"] as? [String: Double] {
                    self.emissiveStrength = Float(emissiveStrengthExtension["emissiveStrength"] ?? 0.0)
                }
                
                if let specularExtension = extensions["KHR_materials_specular"] as? [String: Any] {
                    renderMode = .specular
                    
                    if let specularColorFactor = specularExtension["specularColorFactor"] as? [Double] {
                        self.specularFactor = simd_float3(x: Float(specularColorFactor[0]),
                                                          y: Float(specularColorFactor[1]),
                                                          z: Float(specularColorFactor[1]))
                    }
                    
                    setFromJSONOptional(name: "specularFactor", target: &specularFactor, data: specularExtension)
                    
                    if let specularColorTexture = jsonData["specularColorTexture"] as? [String: Any] {
                        self.specularTexture = GLTFTextureInfo(jsonData: specularColorTexture)
                    }
                }
            }
            
            if let extras = jsonData["extras"] as? [String: Any] {
                self.extras = extras
            }
        }
    }
    
    class PunctualLight {
        enum LightType: String {
            case directional = "directional"
            case spot = "spot"
            case point = "point"
        }
        
        var color = simd_float3(repeating: 1.0)
        var intensity: Float = 1.0
        var range: Float = 100000.0
        var type: LightType = .point
        var castsShadows = true
        
        // spot properties
        var innerConeAngle: Float = 0
        var outerConeAngle: Float = .pi / 4.0
        
        var extensions: [String: Any]?
        var extras: [String: Any]?
        
        // generators
        static func loadFromJSON(jsonData: [String: Any]) -> PunctualLight {
            let light = PunctualLight()
            light.type = LightType.init(rawValue: jsonData["type"] as! String)!
            if let colorList = jsonData["color"] as? [Double] {
                light.color = simd_float3(x: Float(colorList[0]),
                                          y: Float(colorList[1]),
                                          z: Float(colorList[1]))
            }
            light.intensity = Float((jsonData["intensity"] as? Double) ?? 1.0)
            if let spotData = jsonData["spot"] as? [String: Any] {
                light.outerConeAngle = Float((spotData["outerConeAngle"] as? Double) ?? .pi / 2.0)
                light.innerConeAngle = Float((spotData["innerConeAngle"] as? Double) ?? 0.0)
            }
            
            if let extras = jsonData["extras"] as? [String: Any] {
                light.extras = extras
            }

            return light
        }
        
        static func loadExtension(input: [String: Any]) -> [PunctualLight] {
            var punctualLights: [PunctualLight] = []
            for light in (input["lights"]! as! [[String: Any]])  {
                let newLight = PunctualLight.loadFromJSON(jsonData: light)
                punctualLights.append(newLight)
            }
            return punctualLights
        }
    }
    
    // MARK: Animations
    class GLTFAnimationSampler {
        enum Interpolation: String {
            case linear = "LINEAR"
            case step = "STEP"
            case cubic = "CUBICSPLINE"
        }
        
        var timestamps: GLTFAccessor!
        var keyframes: GLTFAccessor!
        var interpolation: Interpolation = .linear
    }
    
    class GLTFAnimationChannel {
        enum TargetType: String {
            case translation = "translation"
            case rotation = "rotation"
            case scale = "scale"
            case weights = "weights"
        }
        
        var sampler = GLTFAnimationSampler()
        var targetNode: GLTFNode?
        var targetType: TargetType = .translation
    }
    
    class GLTFAnimation {
        var name = ""
        var channels: [GLTFAnimationChannel] = []
        var samplers: [GLTFAnimationSampler] = []
    }
    
    // MARK: Buffer, BufferView and Accessors
    class GLTFBuffer {
        var name = ""
        var uri: String
        var byteLength: Int
        var data: Data!
        
        var bufferIndex = 0
        
        init(size: Int, uri: String = "") {
            self.uri = uri
            byteLength = size
            data = Data(count: size)
        }
        
        func putBytes(input: Data) {
            data.replaceSubrange(0..<byteLength, with: input)
        }
    }
    
    class GLTFBufferView {
        enum BufferTarget: Int {
            case arrayBuffer = 34962
            case elementBuffer = 34963
        }
        
        var name = ""
        var buffer: GLTFBuffer!
        var byteLength: Int!
        var byteOffset: Int = 0
        var byteStride: Int?
        var bufferTarget: BufferTarget?
    }
    
    class GLTFAccessor {
        enum ComponentType: Int {
            case byte = 5120
            case ubyte = 5121
            case short = 5122
            case ushort = 5123
            case uint = 5125
            case float = 5126
        }
        
        static let componentSwiftTypes: [ComponentType: Any.Type] = [
            .byte: Int8.self, .ubyte: UInt8.self, .short: Int16.self, .ushort: UInt16.self, .uint: UInt32.self, .float: Float.self
        ]

        enum AccessorType: String {
            case scalar = "SCALAR"
            case vec2 = "VEC2"
            case vec3 = "VEC3"
            case vec4 = "VEC4"
            case mat2 = "MAT2"
            case mat3 = "MAT3"
            case mat4 = "MAT4"
        }
        
        struct AccessorElementDescriptor {
            static let componentSizes: [ComponentType : Int] = [
                .byte: 1, .ubyte: 1, .short: 2, .ushort: 2, .uint: 4, .float: 4
            ]
            
            static let componentCounts: [AccessorType: Int] = [
                .scalar: 1, .vec2: 2, .vec3: 3, .vec4: 4,
                .mat2: 4, .mat3: 9, .mat4: 16
            ]

            var componentSize = 1
            var componentCount = 1
            var elementStride = 1
            
            init(componentType: ComponentType, accessorType: AccessorType) {
                componentSize = AccessorElementDescriptor.componentSizes[componentType]!
                componentCount = AccessorElementDescriptor.componentCounts[accessorType]!
                elementStride = componentCount * componentSize
            }
        }

        var name = ""
        var count: Int = 1
        var componentType: ComponentType = .byte
        var accessorType: AccessorType = .scalar
        var normalized = false
        
        var byteOffset = 0
        var bufferView: GLTFBufferView?
        var byteCount = 1
        var baseCount = 1
        var elementDescriptor: AccessorElementDescriptor!

        
        init(componentType: ComponentType, accessorType: AccessorType, count: Int) {
            self.componentType = componentType
            self.accessorType = accessorType
            self.elementDescriptor = AccessorElementDescriptor(componentType: componentType, accessorType: accessorType)
            self.count = count
            self.byteCount = self.elementDescriptor.elementStride * count
            self.baseCount = self.elementDescriptor.componentCount * count

        }

        func access<T>(callee: (UnsafePointer<T>) -> Void) {
            fatalError("You can't call this yet, sorry...")
        }
        
        func withArray<T>(callee: ([T]) -> Void) {
            if GLTFAccessor.componentSwiftTypes[componentType] != T.self {
                fatalError("Tried to access accessor of type \(componentType) with type \(T.self).")
            }
            
            bufferView?.buffer.data.withUnsafeBytes {
                bufferBytes in
                let bufferPointer = bufferBytes.baseAddress!.advanced(by: bufferView!.byteOffset + byteOffset)
                let typedPointer = bufferPointer.bindMemory(to: T.self, capacity: baseCount)
                let arrayBuffer = UnsafeBufferPointer(start: typedPointer, count: baseCount)
                let array = Array(arrayBuffer)
                callee(array)
            }
        }
        
        func forEach<T: sSIMD>(callee: (T) -> Void) {
            var simdAccess = false
            var simdCount = 1
            if let simdT = T() as? (any SIMD) {
                simdCount = simdT.scalarCount
                simdAccess = true
            } else if T.self == simd_float4x4.self {
                simdAccess = true
                simdCount = 16
            } else if  T.self == simd_float3x3.self {
                simdAccess = true
                simdCount = 9
            }
            
            if !(simdAccess && (simdCount == AccessorElementDescriptor.componentCounts[accessorType]))
                && GLTFAccessor.componentSwiftTypes[componentType] != T.self {
                fatalError("Tried to access accessor of type \(componentType) with type \(T.self).")
            }
            
            bufferView?.buffer.data.withUnsafeBytes {
                bufferBytes in
                let bufferPointer = bufferBytes.baseAddress!.advanced(by: bufferView!.byteOffset + byteOffset)
                let bindCount = simdAccess ? (baseCount / simdCount) : baseCount
                let typedPointer = bufferPointer.bindMemory(to: T.self, capacity: bindCount)
                let arrayBuffer = UnsafeBufferPointer(start: typedPointer, count: bindCount)
                let array = Array(arrayBuffer)
                for element in array {
                    callee(element)
                }
            }
            
        }
        
        func withRawPointer(callee: (UnsafeRawPointer) -> Void) {
            bufferView?.buffer.data.withUnsafeBytes {
                bufferBytes in
                let bufferPointer = bufferBytes.baseAddress!.advanced(by: bufferView!.byteOffset + byteOffset)
                callee(bufferPointer)
            }
        }
        
        func withTypedPointer<T>(callee: (UnsafePointer<T>, Int) -> Void) {
            if GLTFAccessor.componentSwiftTypes[componentType] != T.self {
                fatalError("Tried to access accessor of type \(componentType) with type \(T.self).")
            }
            
            bufferView?.buffer.data.withUnsafeBytes {
                bufferBytes in
                let bufferPointer = bufferBytes.baseAddress!.advanced(by: bufferView!.byteOffset + byteOffset)
                let typedPointer = bufferPointer.bindMemory(to: T.self, capacity: baseCount)
                callee(typedPointer, baseCount)
            }
        }
        
        func copyWithTypeCast<T: FixedWidthInteger>(into: inout [T]){
            switch componentType {
                case .byte:
                    withTypedPointer { (x: UnsafePointer<Int8>, count) in
                        for i in 0..<count {
                            into.append(T(x[i]))
                        }
                    }
                case .ubyte:
                    withTypedPointer { (x: UnsafePointer<UInt8>, count) in
                        for i in 0..<count {
                            into.append(T(x[i]))
                        }
                    }
                case .short:
                    withTypedPointer { (x: UnsafePointer<Int16>, count) in
                        for i in 0..<count {
                            into.append(T(x[i]))
                        }
                    }
                case .ushort:
                    withTypedPointer { (x: UnsafePointer<UInt16>, count) in
                        for i in 0..<count {
                            into.append(T(x[i]))
                        }
                    }
                case .uint:
                    withTypedPointer { (x: UnsafePointer<UInt32>, count) in
                        for i in 0..<count {
                            into.append(T(x[i]))
                        }
                    }
                case .float:
                    withTypedPointer { (x: UnsafePointer<Float>, count) in
                        for i in 0..<count {
                            into.append(T(x[i]))
                        }
                    }
            }
        }
        
        func copyContents(into: UnsafeMutablePointer<UInt8>) {
            bufferView?.buffer.data.copyBytes(to: into,
                                              from: (bufferView!.byteOffset + byteOffset)..<(bufferView!.byteOffset + byteOffset + byteCount))
        }
        
        func copyAsCollection<T: Numeric>() -> [T] {
            if GLTFAccessor.componentSwiftTypes[componentType] != T.self {
                fatalError("Tried to access accessor of type \(componentType) with type \(T.self).")
            }
            
            var newCollection = [T](repeating: 0, count: count * elementDescriptor.componentCount)
            newCollection.withUnsafeMutableBytes {
                bytes in
                let bytePointer = bytes.baseAddress!.bindMemory(to: UInt8.self, capacity: byteCount)
                copyContents(into: bytePointer)
            }
            return newCollection
        }

        
        
        
    }
    
    // MARK: Storage
    var fileNodes: [GLTFNode] = []
    var buffers: [GLTFBuffer] = []
    var bufferViews: [GLTFBufferView] = []
    var accessors: [GLTFAccessor] = []
    
    var meshes: [GLTFMesh] = []
    var materials: [GLTFMaterial] = []
    var animations: [GLTFAnimation] = []
    var skins: [GLTFSkin] = []
    
    var images: [GLTFImage] = []
    var textures: [GLTFTexture] = []
    var samplers: [GLTFSampler] = []

    
    var extensionTargetMap: [String: [Any]]!
    
    var extensionLoaderMap: [String: ([String: Any]) -> [Any]] = [
        "KHR_lights_punctual" : PunctualLight.loadExtension
    ]
    
    var fileStream: InputStream!
    var gf: [String: Any] = [:]
    var bData: Data? = nil
    
    var filePath: URL?
    var fileDirectory: URL?
    
    // MARK: Main Parser
    func parse(){
        // reset state
        fileNodes = []
        buffers = []
        bufferViews = []
        accessors = []
        meshes = []
        materials = []
        animations = []
        skins = []
        samplers = []
        images = []
        textures = []
        
        // parse file
        do {
            // load extensions
            if let extensions = gf["extensions"] as? [String : Any] {
                for (k, v) in extensions {
                    if let extLoader = extensionLoaderMap[k] {
                        extensionTargetMap[k]!.append(contentsOf: (extLoader(v as! [String: Any])))
                    }
                }
            }
            
            // load buffers
            if let buffers = gf["buffers"] as? [[String: Any]] {
                for (index, buffer) in buffers.enumerated() {
                    let size = buffer["byteLength"] as! Int
                    let newBuffer = GLTFBuffer(size: size)
                    newBuffer.bufferIndex = index

                    if let uri = buffer["uri"] as? String, !uri.isEmpty {
                        if uri.hasPrefix("data:") {
                            // raw data here, decode and pass it directly to the buffer.
                            let uriIndex = uri.index(after: uri.firstIndex(of: ",")!)
                            let uriData = String(uri[uriIndex..<uri.endIndex])
                            // TODO: add handling of different data encodings here.
                            let rawData = Data(base64Encoded: uriData)
                            newBuffer.putBytes(input: rawData!)
                        } else {
                            // uri points to a path, put the path into the buffer uri parameter
                            newBuffer.uri = uri
                            let fullPath = fileDirectory!.relativePath + "/" + uri
                            let rawData = try! Data(contentsOf: URL(fileURLWithPath: fullPath))
                            newBuffer.putBytes(input: rawData)
                        }
                    } else {
                        // empty URI means load from BIN chunk
                        if let bData = bData {
                            newBuffer.putBytes(input: bData)
                        }
                    }
                    
                    self.buffers.append(newBuffer)
                }
            }
            
            // load bufferviews
            if let bufferViews = gf["bufferViews"] as? [[String: Any]] {
                for bufferView in bufferViews {
                    let newBufferView = GLTFBufferView()
                    let bufferIndex = bufferView["buffer"] as! Int
                    newBufferView.buffer = buffers[bufferIndex]
                    newBufferView.byteLength = bufferView["byteLength"] as? Int
                    
                    if let byteOffset = bufferView["byteOffset"] as? Int {
                        newBufferView.byteOffset = byteOffset
                    }
                    
                    if let byteStride = bufferView["byteStride"] as? Int {
                        newBufferView.byteStride = byteStride
                    }
                    
                    if let bufferTarget = bufferView["bufferTarget"] as? Int {
                        newBufferView.bufferTarget = GLTFBufferView.BufferTarget.init(rawValue: bufferTarget)
                    }
                    
                    if let name = bufferView["name"] as? String {
                        newBufferView.name = name
                    }
                    self.bufferViews.append(newBufferView)
                }
            }
            
            // load accessors
            if let accessors = gf["accessors"] as? [[String: Any]] {
                for accessor in accessors {
                    let accessorType = GLTFAccessor.AccessorType.init(rawValue: accessor["type"] as! String)!
                    let componentType = GLTFAccessor.ComponentType.init(rawValue: accessor["componentType"] as! Int)!
                    let count = accessor["count"] as! Int
                    
                    let newAccessor = GLTFAccessor(componentType: componentType, accessorType: accessorType, count: count)
                    newAccessor.count = count
                    
                    if let bufferView = accessor["bufferView"] as? Int {
                        newAccessor.bufferView = bufferViews[bufferView]
                    }
                    setFromJSONOptional(name: "byteOffset", target: &newAccessor.byteOffset, data: accessor)
                    setFromJSONOptional(name: "normalized", target: &newAccessor.normalized, data: accessor)
                    
                    self.accessors.append(newAccessor)
                }
            }
            
            loadListFromJSON(name: "images", target: &self.images, data: gf)
            
            loadListFromJSON(name: "samplers", target: &self.samplers, data: gf)

            loadListFromJSON(name: "textures", target: &self.textures, data: gf)
            
            // place references into textures
            for texture in textures {
                if texture.source.index != -1 {
                    texture.source.reference = images[texture.source.index]
                }
                
                if texture.sampler.index != -1 {
                    texture.sampler.reference = samplers[texture.sampler.index]
                }
            }

            loadListFromJSON(name: "materials", target: &self.materials, data: gf)
            
            // place material textures into materials
            for material in materials {
                if material.baseColorTexture != nil {
                    material.baseColorTexture!.texture = textures[material.baseColorTexture!.index]
                }
                if material.normalTexture != nil {
                    material.normalTexture!.texture = textures[material.normalTexture!.index]
                }
                if material.emissiveTexture != nil {
                    material.emissiveTexture!.texture = textures[material.emissiveTexture!.index]
                }
                if material.occlusionTexture != nil {
                    material.occlusionTexture!.texture = textures[material.occlusionTexture!.index]
                }
                if material.metallicRoughnessTexture != nil {
                    material.metallicRoughnessTexture!.texture = textures[material.metallicRoughnessTexture!.index]
                }
            }

            
            // load meshes
            forEachOptional(collection: gf["meshes"]) { (mesh: [String: Any]) in
                self.meshes.append(loadMesh(input: mesh))
            }
            
            // load nodes
            forEachOptional(collection: gf["nodes"]) { (node: [String: Any]) in
                fileNodes.append(loadNode(input: node))
            }

            // load skins
            forEachOptional(collection: gf["skins"]) { (skin: [String: Any]) in
                self.skins.append(loadSkin(input: skin))
            }

            // skins reference nodes, but nodes reference skins! so walk through nodes and resolve skin references.
            for node in fileNodes {
                if node.skin != nil {
                    node.skin!.reference = skins[node.skin!.index]
                }
            }
            
            // place child node references to parents
            for node in fileNodes {
                if let childrenIndices = node.childrenIndices {
                    node.children = []
                    for child in childrenIndices {
                        let childNode = fileNodes[child]
                        childNode.parent = node
                        node.children!.append(childNode)
                    }
                }
            }
            
            // calculate global positions of all nodes
            func recursiveTransform(node: GLTFNode, parentTransform: GLTFTransform? = nil){
                node.globalTransform = GLTFTransform(matrix: node.transform.matrix)
                if parentTransform != nil {
                    node.globalTransform!.matrix = parentTransform!.matrix * node.transform.matrix
                }
                
                if let children = node.children {
                    for child in children {
                        recursiveTransform(node: child, parentTransform: node.globalTransform)
                    }
                }
            }
            
            for node in fileNodes {
                // skip child nodes, walk into the hierarchy roots
                if node.parent == nil {
                    recursiveTransform(node: node)
                }
            }
            
            // load animations
            forEachOptional(collection: gf["animations"]) { (animation: [String: Any]) in
                self.animations.append(loadAnimation(input: animation))
            }
            
        }
    }
    
    init?(path: URL) {
        extensionTargetMap = [
            "KHR_lights_punctual" : []
        ]
        
        filePath = path
        fileDirectory = path.deletingLastPathComponent()
        
        
        guard let stream = InputStream(url: path) else {
            return nil
        }
        fileStream = stream
        fileStream.open()
        
        do {
            gf = try JSONSerialization.jsonObject(with: fileStream) as! [String: Any]
        } catch {
            print("JSON Serialization failed: \(error)")
        }
    }
    
    
    init?(jsonData: Data, binaryData: Data? = nil) {
        extensionTargetMap = [
            "KHR_lights_punctual" : []
        ]
        if binaryData != nil {
            bData = binaryData
        }
        do {
            gf = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        } catch {
            print("JSON Serialization failed: \(error)")
        }
    }
    
    
}

// MARK: Parser functions
extension GLTFFile {
    func loadNode(input: [String: Any]) -> GLTFNode {
        let node = GLTFNode()
        // properties
        if let name = input["name"] as? String {
            node.name = name
        }
        
        // transform
        if let tmatrix = input["matrix"] as? [Float] {
            node.transform = GLTFTransform(matrix: simd_float4x4(columns: (simd_float4(tmatrix[0..<4]),
                                                       simd_float4(tmatrix[4..<8]),
                                                       simd_float4(tmatrix[8..<12]),
                                                       simd_float4(tmatrix[12..<16])))
            )
        }

        if let scale = input["scale"] as? [Double] {
            node.transform.scale = simd_float3(x: Float(scale[0]), y: Float(scale[1]), z: Float(scale[2]))
        }
        if let rotation = input["rotation"] as? [Double] {
            node.transform.rotation = simd_quatf(ix: Float(rotation[0]),
                                                 iy: Float(rotation[1]),
                                                 iz: Float(rotation[2]),
                                                  r: Float(rotation[3]))
        }
        if let translation = input["translation"] as? [Double] {
            node.transform.translation = simd_float3(x: Float(translation[0]), y: Float(translation[1]), z: Float(translation[2]))
        }
        if let children = input["children"] as? [Int] {
            node.childrenIndices = []
            node.childrenIndices!.append(contentsOf: children)
        }
        if let mesh = input["mesh"] as? Int {
            node.mesh = meshes[mesh]
        }
        if let skin = input["skin"] as? Int {
            node.skin = IndexedReference()
            node.skin?.index = skin
        }

        // extensions
        if let extensions = input["extensions"] as? [String: Any] {
            for (ek, ev) in extensions {
                if ek == "KHR_lights_punctual" {
                    node.punctualLight = IndexedReference()
                    node.punctualLight!.index = (ev as! [String: Int])["light"]
                    node.punctualLight!.reference = extensionTargetMap[ek]![node.punctualLight!.index] as? PunctualLight
                }
            }
        }
        
        // extras
        if let extras = input["extras"] as? [String: Any] {
            node.extras = extras
            for (ek, ev) in extras {
                if ek == "shred" {
                    node.shredProps = try? JSONSerialization.jsonObject(with: (ev as? String ?? "").data(using: .utf8)!) as? [String: Any] ?? [:]
                    if let _ = node.shredProps?["prototype"] {
                        node.isPrototype = true
                    }
                }
            }
        }
        
        return node
    }
    
    func loadMesh(input: [String: Any]) -> GLTFMesh {
        let mesh = GLTFMesh()
        // properties
        mesh.name = input["name"] as? String ?? ""

        // primitives
        if let primitives = input["primitives"] as? [[String: Any]] {
            for primitive in primitives {
                let newPrimitive = loadPrimitive(input: primitive)
                mesh.primitives.append(newPrimitive)
            }
        }
        
        return mesh
    }
    
    func loadSkin(input: [String: Any]) -> GLTFSkin {
        let skin = GLTFSkin()
        
        if let joints = input["joints"] as? [Int] {
            for joint in joints {
                skin.joints.append(fileNodes[joint])
            }
        }
        if let skeleton = input["skeleton"] as? Int {
            skin.skeleton = fileNodes[skeleton]
        }
        if let inverseBindMatrices = input["inverseBindMatrices"] as? Int {
            skin.inverseBindMatrices = accessors[inverseBindMatrices]
        }
        
        skin.name = input["name"] as? String ?? ""
        
        return skin
    }
    
    func loadPrimitive(input: [String: Any]) -> GLTFPrimitive {
        let primitive = GLTFPrimitive()
        if let indices = input["indices"] as? Int {
            let accessor = accessors[indices]
            primitive.indexAccessor = accessor
            primitive.indexCount = primitive.indexAccessor!.count
        }
        
        if let attributes = input["attributes"] as? [String: Int] {
            for (k, v) in attributes {
                let accessor = accessors[v]
                if let attr = VertexAttribute.init(rawValue: k) {
                    primitive.attributes[attr] = accessor
                }
            }
            primitive.vertexCount = primitive.attributes[.position]!.count
        }
        
        if let material = input["material"] as? Int {
            primitive.material = IndexedReference()
            primitive.material!.index = material
            primitive.material!.reference = materials[material]
        }
        
        
        if let mode = input["mode"] as? Int {
            primitive.mode = GLTFPrimitive.Mode.init(rawValue: mode)
        }

        return primitive
    }
    
    func loadAnimation(input: [String: Any]) -> GLTFAnimation {
        let newAnimation = GLTFAnimation()
        
        if let samplers = input["samplers"] as? [[String: Any]] {
            for sampler in samplers {
                let newSampler = GLTFAnimationSampler()
                let inputAccessorIndex = sampler["input"] as! Int
                newSampler.timestamps = accessors[inputAccessorIndex]
                
                let outputAccessorIndex = sampler["output"] as! Int
                newSampler.keyframes = accessors[outputAccessorIndex]
                
                if let interpolation = sampler["interpolation"] as? String {
                    newSampler.interpolation = .init(rawValue: interpolation)!
                }
                newAnimation.samplers.append(newSampler)
            }
        }
        
        if let channels = input["channels"] as? [[String: Any]] {
            for channel in channels {
                let newChannel = GLTFAnimationChannel()
                if let target = channel["target"] as? [String: Any] {
                    if let node = target["node"] as? Int {
                        newChannel.targetNode = fileNodes[node]
                    }
                    newChannel.targetType = .init(rawValue: target["path"] as! String)!
                }
            
                if let sampler = channel["sampler"] as? Int {
                    newChannel.sampler = newAnimation.samplers[sampler]
                }
                newAnimation.channels.append(newChannel)
            }
        }
        
        newAnimation.name = input["name"] as? String ?? ""
        
        return newAnimation
    }

}

// MARK: Access functions
extension GLTFFile {
    func getLightNodes() -> [GLTFNode] {
        var lightNodes: [GLTFNode] = []
        for node in fileNodes {
            if node.punctualLight != nil {
                lightNodes.append(node)
            }
        }
        return lightNodes
    }
    
    func getMeshNodes() -> [GLTFNode] {
        var meshNodes: [GLTFNode] = []
        for node in fileNodes {
            if node.mesh != nil {
                meshNodes.append(node)
            }
        }
        return meshNodes
    }
    
    
}


#if GLTFMetalBindings

extension GLTFFile.GLTFAccessor {
    func getAsVertexFormat() -> MTLVertexFormat {
        switch accessorType{
            case .scalar:
                switch componentType {
                    case .byte: return MTLVertexFormat.char
                    case .ubyte: return MTLVertexFormat.uchar
                    case .short: return MTLVertexFormat.short
                    case .ushort: return MTLVertexFormat.ushort
                    case .uint: return MTLVertexFormat.uint
                    case .float: return MTLVertexFormat.float
                }
            case .vec2:
                switch componentType {
                    case .byte: return MTLVertexFormat.char2
                    case .ubyte: return MTLVertexFormat.uchar2
                    case .short: return MTLVertexFormat.short2
                    case .ushort: return MTLVertexFormat.ushort2
                    case .uint: return MTLVertexFormat.uint2
                    case .float: return MTLVertexFormat.float2
                }
            case .vec3:
                switch componentType {
                    case .byte: return MTLVertexFormat.char3
                    case .ubyte: return MTLVertexFormat.uchar3
                    case .short: return MTLVertexFormat.short3
                    case .ushort: return MTLVertexFormat.ushort3
                    case .uint: return MTLVertexFormat.uint3
                    case .float: return MTLVertexFormat.float3
                }
            case .vec4:
                switch componentType {
                    case .byte: return MTLVertexFormat.char4
                    case .ubyte: return MTLVertexFormat.uchar4
                    case .short: return MTLVertexFormat.short4
                    case .ushort: return MTLVertexFormat.ushort4
                    case .uint: return MTLVertexFormat.uint4
                    case .float: return MTLVertexFormat.float4
                }
            default:
                fatalError("Current accessor type \(componentType) is not available as a Vertex Attribute.")
        }
    }
}

extension GLTFFile.GLTFMesh {
    func getMetalVertexDescriptor() -> MTLVertexDescriptor {
        var primitiveDescriptors: [MTLVertexDescriptor] = []
        for primitive in primitives {
            let descriptor = MTLVertexDescriptor()
            
            for (attribute, accessor) in primitive.attributes {
                let index = GLTFFile.GLTFPrimitive.attributeMapping[attribute]!
                let currentDescriptor = descriptor.attributes[index]
                
                currentDescriptor?.bufferIndex = accessor.bufferView!.buffer.bufferIndex
                currentDescriptor?.format = accessor.getAsVertexFormat()
                currentDescriptor?.offset = accessor.byteOffset
                
                let currentLayout = descriptor.layouts[index]!
                currentLayout.stride = accessor.elementDescriptor.elementStride
                currentLayout.stepRate = 1
                currentLayout.stepFunction = .perVertex
                
            }
            primitiveDescriptors.append(descriptor)
        }
        
        return primitiveDescriptors[0]
    }
}


extension GLTFFile.GLTFPrimitive {
    func getMetalVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        
        for (attribute, accessor) in attributes {
            let index = GLTFFile.GLTFPrimitive.attributeMapping[attribute]!
            let currentDescriptor = descriptor.attributes[index]

            currentDescriptor?.bufferIndex = accessor.bufferView!.buffer.bufferIndex
            currentDescriptor?.format = accessor.getAsVertexFormat()
            currentDescriptor?.offset = accessor.byteOffset + accessor.bufferView!.byteOffset
            
            let currentLayout = descriptor.layouts[index]!
            currentLayout.stride = accessor.bufferView?.byteStride ?? accessor.elementDescriptor.elementStride
            currentLayout.stepRate = 1
            currentLayout.stepFunction = .perVertex

        }
        return descriptor
    }
}

extension GLTFFile.GLTFBuffer {
    func copyAsMetalBuffer(device: MTLDevice) -> MTLBuffer {
        data.withUnsafeBytes {
            bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: byteLength)!
        }
    }
}


#endif

