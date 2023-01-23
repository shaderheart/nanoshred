//
//  EngineComponents.swift
//  swiftui-test
//
//  Created by utku on 04/12/2022.
//

import Foundation

import GameController


struct EngineRestorableState: Codable {
   var lastScene: URL = URL(fileURLWithPath: "")
   var cameraPosition = simd_float3()
   var cameraRotation = simd_quatf()
}


class NodeTreeDetailModel: ObservableObject {
    weak var targetTransform: ETransformComponent?
    @Published var name = ""
    @Published var location = "0, 0, 0"
    @Published var rotation = "0, 0, 0"
    @Published var scale = "0, 0, 0"
    
    func update(){
        if let targetTransform = targetTransform {
            name = targetTransform.name
            location = String.init(format: "%.2f, %.2f, %.2f",
                                   targetTransform.local.translation.x,
                                   targetTransform.local.translation.y,
                                   targetTransform.local.translation.z)
            let angles = quatfToEuler(quatf: targetTransform.local.rotation)
            rotation = String.init(format: "%.2f, %.2f, %.2f",
                                   angles.x,
                                   angles.y,
                                   angles.z)
            scale = String.init(format: "%.2f, %.2f, %.2f",
                                   targetTransform.local.scale.x,
                                   targetTransform.local.scale.y,
                                   targetTransform.local.scale.z)
        }
    }
    
}

public class EngineGlobals: ObservableObject {
    @Published var isGameRunning = false
    @Published var menuActive = true
    @Published var nodeOutlinerActive = false
    @Published var nodeOutlinerTree = [NodeTree<String>]()
    @Published var nodeTreeDetailModel = NodeTreeDetailModel()
    
    static var restorableState = EngineRestorableState()
    
    public static var input = InputState()
    
    static var availableScenes: [String: URL] = [:]
    
    static var activeCamera: GameCamera!
        
#if os( iOS )
    static private var _virtualController: Any?
    @available(iOS 15.0, *)
    static public var virtualController: GCVirtualController? {
      get { return self._virtualController as? GCVirtualController }
      set { self._virtualController = newValue }
    }
#endif
}

public protocol InitComponent {
    static var typeID: UUID {get set}
    var entity: SHEntity? { get set }
    static var storage: SHSparseComponentSet<Self> {get}
    static func resetStorage()
    init()
}
extension InitComponent {
    public static func resetStorage(){
        Self.storage.reset()
    }
}

public protocol CodableComponent: InitComponent, Codable {
    var entity: SHEntity? { get set }
    init()
}

protocol ArgComponent: InitComponent {
    init(args: Any...)
}

extension simd_float4x4: Codable {
    enum CodingKeys: String, CodingKey {
        case columns0
        case columns1
        case columns2
        case columns3
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(columns.0, forKey: .columns0)
        try container.encode(columns.1, forKey: .columns1)
        try container.encode(columns.2, forKey: .columns2)
        try container.encode(columns.3, forKey: .columns3)
    }
    
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        columns.0 = try values.decode(simd_float4.self, forKey: .columns0)
        columns.1 = try values.decode(simd_float4.self, forKey: .columns1)
        columns.2 = try values.decode(simd_float4.self, forKey: .columns2)
        columns.3 = try values.decode(simd_float4.self, forKey: .columns3)
    }
}

extension simd_quatf: Codable {
    enum CodingKeys: String, CodingKey {
        case vector
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vector, forKey: .vector)
    }
    
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        vector = try values.decode(simd_float4.self, forKey: .vector)
    }
}

@objcMembers
class ETransform: NSObject, Codable {
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

public final class EDestructionRequest: InitComponent {
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    public static var storage = SHSparseComponentSet<EDestructionRequest>()
    required public init(){}
}

@objcMembers
public final class ETransformComponent: NSObject {
    var name = ""
    var local = ETransform()
    var global = ETransform()
    required public override init() {}
}

final class ETappableComponent: CodableComponent {
    var justTapped = false
    enum CodingKeys: CodingKey {}
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    public static var storage = SHSparseComponentSet<ETappableComponent>()
    required public init() {}
}

final class EMeshComponent: InitComponent, Codable {
    var meshName = ""
    var meshInstance: GenericMesh?
    
    enum CodingKeys: CodingKey {
        case meshName
    }
    
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    public static var storage = SHSparseComponentSet<EMeshComponent>()
    required public init() {}
}

final class EBoneAnimationComponent: InitComponent {
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    public static var storage = SHSparseComponentSet<EBoneAnimationComponent>()
    required public init() {}
    enum CodingKeys: CodingKey {}
    var boneAnimation: BoneAnimation? = nil
}

final class EParentNodeMarkerComponent: InitComponent {
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    public static var storage = SHSparseComponentSet<EParentNodeMarkerComponent>()
    required public init(){}
}

final class EIgnoresParentTransformMarker: InitComponent {
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    public static var storage = SHSparseComponentSet<EIgnoresParentTransformMarker>()
    required public init(){}
}

final class EMusicComponent: CodableComponent {
    static var storage = SHSparseComponentSet<EMusicComponent>()
    
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    required public init() {}
    
    var file_name: String = ""
    var accompanyingMidi: String = ""
    var active: Bool = false
    var threeD: Bool = false
    var volume: Float = 1.0
    var outChannels: Int = 2
    var sourceChannel: Int = 0
    var multiMono: Bool = false
    
    enum CodingKeys: CodingKey {
        case file_name
        case accompanyingMidi
        case active
        case threeD
        case volume
        case outChannels
        case sourceChannel
        case multiMono
    }
    
    var isPlaying = false
    var currentTime = 0.0
    
}

struct NodeTree<Value: Hashable>: Hashable {
    let name: Value
    weak var transform: ETransformComponent?
    var children: [NodeTree]? = nil
}


final class ERelationshipComponent {
    weak var parent: SHEntity?
    var children: [SHEntity] = []

    static func detachEntityFromParent(entity: SHEntity) {
        if entity.relationship.parent != nil {
            entity.relationship.parent!.relationship.children.removeAll { iEntity in
                iEntity == entity
            }
            entity.relationship.parent = nil
        }
    }
    
    static func attachEntityToEntity(registry: SHRegistry, parent: SHEntity, child: SHEntity) {
        guard parent != child else {
            fatalError("Tried to parent an entity to itself!")
        }
        
        // if the child already has a parent, detach it first.
        detachEntityFromParent(entity: child)
        
        parent.relationship.children.append(child)
        child.relationship.parent = parent
        
        child.transform.global.matrix = parent.transform.global.matrix * child.transform.local.matrix
    }
    

    static func propagateTransforms(registry: SHRegistry){
        registry.iterate { entity in
            if entity.relationship.parent == nil {
                entity.transform.global = entity.transform.local
                entity.relationship.propagateTransform(parent: entity)
            }
        }
    }
    
    func propagateTransform(parent: SHEntity){
        for child in children {
            let ignoreParent: UnsafeMutablePointer<EIgnoresParentTransformMarker>? = child.component()
            // non-kinematic physics components don't inherit parent transforms during runtime, but everything else does.
            if ignoreParent == nil {
                if let physics: UnsafeMutablePointer<EPhysicsComponent> = child.component(), (physics.pointee.is_kinematic == 0) {
                    continue
                }
                child.transform.global.matrix = parent.transform.global.matrix * child.transform.local.matrix
            }
            child.relationship.propagateTransform(parent: child)
        }
    }
    
    func getSiblingWithTag(tag: String) -> SHEntity? {
        for child in parent?.relationship.children ?? [] {
            if child.name == tag {
                return child
            }
        }
        return nil
    }
    
    func getChildWithTag(tag: String) -> SHEntity? {
        guard !children.isEmpty else {
            return nil
        }
        
        for child in children {
            if child.name == tag {
                return child
            }
        }
        return nil
    }
    
    func buildNodeTree() -> [NodeTree<String>] {
        var tree = [NodeTree<String>]()
//        for child in children {
//            let childRelationship: ERelationshipComponent = child.component()!
//            let childTransform: ETransformComponent = child.component()!
//            tree.append(.init(name: child.name, transform: childTransform, children: childRelationship.buildNodeTree()))
//        }
        return tree
    }
    
}

final class EPunctualLight: GLTFFile.PunctualLight, InitComponent, ArgComponent, Codable {
    static var storage = SHSparseComponentSet<EPunctualLight>()
    
    var shadowTexture: MTLTexture?
    var shadowFrustum: CameraFrustum = .init()
    var shadowProjection: simd_float4x4 = .init()
    
    private func copyFromLight(_ light: GLTFFile.PunctualLight) {
        color = light.color
        intensity = light.intensity
        range = light.range
        type = light.type
        innerConeAngle = light.innerConeAngle
        outerConeAngle = light.outerConeAngle
    }
    
    required init(args: Any...) {
        super.init()
        for arg in args {
            if let light = arg as? GLTFFile.PunctualLight {
                copyFromLight(light)
            }
        }
    }
    
    enum CodingKeys: CodingKey {}
    
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    required public override init() {super.init()}

    convenience init(_ light: GLTFFile.PunctualLight) {
        self.init()
        copyFromLight(light)
    }
}

final class EScriptComponent: InitComponent, Codable {
    static var storage = SHSparseComponentSet<EScriptComponent>()

    var scriptName = ""
    var scriptInstance: (ShredScript)?
    
    enum CodingKeys: CodingKey {
        case scriptName
    }
    
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    required public init() {}
}

final class ESceneParentComponent: InitComponent {
    static var storage = SHSparseComponentSet<ESceneParentComponent>()
    var sceneName = ""
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    required public init() {}
}

final class EMainPlayerMarker: InitComponent {
    static var storage = SHSparseComponentSet<EMainPlayerMarker>()
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    required public init() {}
}

class CodableCamera: Codable {
    var zFar: Float = 0.1
    var zNear: Float = 1000.01
    var FOV: Float = 90.0001
    var active: Int! = 0 {
        didSet {
            bActive = active == 1
        }
    }
    
    enum CodingKeys: CodingKey {
        case zFar
        case zNear
        case FOV
        case bActive
    }
    
    var bActive: Bool! = false
}

final class ECameraComponent: CodableCamera, CodableComponent {
    static var storage = SHSparseComponentSet<ECameraComponent>()
    var transform = ETransform()
    
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    required public override init() {super.init()}
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        bActive = active == 1
    }
}

@objcMembers
public class CodablePhysics: NSObject, Codable {
    @objc enum PhysicsShape: Int, Codable {
        case BOX = 0
        case SPHERE = 1
        case CAPSULE = 2
        case MESH = 3
        case HEIGHTMAP = 4
        case COMPOUND = 5
        case CONVEX = 6
    }
    
    var shape: PhysicsShape = .BOX
    var friction: Float = 1.0
    var contactThreshold: Float? = 0.0001
    var mass: Float = 1.0
    var bounce: Float = 1.0
    
    var linear_damping: Float = 1.0
    var angular_damping: Float = 1.0
    
    var scale = simd_float3(repeating: 1.0)
    var radius: Float = 1.0
    var height: Float = 1.0
    var box_extents = simd_float3(repeating: 1.0)
    
    var is_kinematic = 0
    var is_static = 0
    var is_trigger = 0
    
    var belongs: UInt32 = 0x1FFFFFFF
    var responds: UInt32 = 0x1FFFFFFF
  
}

@objcMembers
final public class EPhysicsComponent: CodablePhysics, InitComponent {
    var vertexFloats: [Float]?
    var cookedData: Data?
    var physicsMeshName: String?
    
    var prepared = false
    var inWorld = false
    var physicsTransform = ETransform()
    
    var impulse = simd_float3(repeating: 0.0)
    
    var hitCallback: ((EPhysicsComponent) -> (Void))?
    var overlapBeginCallback: ((EPhysicsComponent) -> (Void))?
    var overlapEndCallback: ((EPhysicsComponent) -> (Void))?
    
    weak var parentEntity: SHEntity?

    weak public var entity: SHEntity?
    public static var typeID = UUID()
    public static var storage = SHSparseComponentSet<EPhysicsComponent>()
    required public override init() {
        super.init()
        physicsTransform = ETransform()
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}

final class MidiProviderComponent: InitComponent, Codable {
    var filename = ""
    
    enum CodingKeys: CodingKey {
        case filename
    }
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    public static var storage = SHSparseComponentSet<MidiProviderComponent>()
    required public init (){}
}

final class AnimationControllerComponent: InitComponent, Codable {
    var targetAnimations: [NodeAnimation] = []
    
    enum CodingKeys: CodingKey {}
    
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    public static var storage = SHSparseComponentSet<AnimationControllerComponent>()
    required public init() {}
}


class SwiftSimpleParticle: Codable {
    var fLifetime: Float = 1.000001;
    
    var fColorBegin: simd_float3 = .init(repeating: 0.00000001)
    var fColorEnd: simd_float3 = .init(repeating: 0.00000001)

    var startPosition: simd_float3 = .init(repeating: 0.00000001)
    var startOrientation: simd_float3 = .init(repeating: 0.00000001)
    var fVelocityBegin: simd_float3 = .init(repeating: 0.00000001)
    var fVelocityEnd: simd_float3 = .init(repeating: 0.00000001)
    var fScaleBegin: simd_float3 = .init(repeating: 1.00001)
    var fScaleEnd: simd_float3 = .init(repeating: 1.00001)
    
    var fLifetimeSpreadFactor: Float? = 0.00001
    var fPositionSpreadFactor: simd_float3? = .init(repeating: 0.00001)
    var fVelocitySpreadFactor: simd_float3? = .init(repeating: 0.00001)
    var bTransformIsLocal: Bool? = true
    
    enum CodingKeys: CodingKey {
        case fLifetime
        case fColorBegin
        case fColorEnd
        case fVelocityBegin
        case fVelocityEnd
        case fScaleBegin
        case fScaleEnd
        case fLifetimeSpreadFactor
        case fPositionSpreadFactor
        case fVelocitySpreadFactor
        case bTransformIsLocal
    }
    
    func convert(at: simd_float3, parentTransform: ETransform? = nil) -> SimpleParticle {
        var part = SimpleParticle()
        part.currentTime = 0.0
        
        part.currentPosition = at
        if let randomPosition = fPositionSpreadFactor {
            if !(bTransformIsLocal ?? true) {
                part.currentPosition += simd_float3.random(in: -1.0...1.0) * randomPosition
            } else if parentTransform != nil {
                let random4 = parentTransform!.matrix * simd_float4(randomPosition, 0.0)
                part.currentPosition += simd_float3.random(in: -1.0...1.0) * simd_make_float3(random4)
            }
        }
        
        part.lifetime = fLifetime
        if let randomLifetime = fLifetimeSpreadFactor {
            part.lifetime += Float(Double.random(in: -1.0..<1.0)) * randomLifetime
        }
        
        part.startColor = fColorBegin
        part.endColor = fColorEnd
        
        part.initialVelocity = fVelocityBegin
        part.finalVelocity = fVelocityEnd
        if let randomSpeed = fVelocitySpreadFactor {
            let rand = simd_float3.random(in: -1.0...1.0) * randomSpeed
            part.initialVelocity += rand
            part.finalVelocity += rand
        }
        if (bTransformIsLocal ?? false) && parentTransform != nil {
            let random4 = parentTransform!.rotationMatrix * simd_float4(part.initialVelocity, 0.0)
            part.initialVelocity = simd_make_float3(random4)
            let frandom4 = parentTransform!.rotationMatrix * simd_float4(part.finalVelocity, 0.0)
            part.finalVelocity = simd_make_float3(frandom4)
        }
        part.startScale = fScaleBegin
        part.endScale = fScaleEnd
        
        return part
    }
}

final class SimpleParticleComponent: CodableComponent {
    var modelParticle = SwiftSimpleParticle()
    
    var emitsPerSecond = 100
    var enabled = true
    
    enum CodingKeys: CodingKey {
        case modelParticle
        case emitsPerSecond
    }
    
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    public static var storage = SHSparseComponentSet<SimpleParticleComponent>()
    required public init (){}
}


final class TexturedParticleComponent: InitComponent {
    var modelParticle = SwiftSimpleParticle()
    var sParticleTexture = ""
    
    var uEmitsPerSecond = 100
    var bEnabled = true
    
    enum CodingKeys: CodingKey {
        case modelParticle
        case uEmitsPerSecond
        case sParticleTexture
        case bEnabled
    }
    
    weak public var entity: SHEntity?
    public static var typeID = UUID()
    public static var storage = SHSparseComponentSet<TexturedParticleComponent>()
    required public init (){}
}


class FrustumPlane {
    var normal = simd_float3()
    var distance: Float = 0.0
    
    func halfSpace(_ v: simd_float3) -> Float {
        simd_dot(simd_float4(normal, distance), simd_float4(v, 1.0))
    }
    
    func normalize() {
        let length = simd_length(normal)
        normal /= length
        distance /= length
    }
    
    init(_ normal_d: simd_float4) {
        setFrom(normal_d)
    }
    
    func setFrom(_ normal_d: simd_float4){
        normal.x = normal_d.x
        normal.y = normal_d.y
        normal.z = normal_d.z
        distance = normal_d.w
    }
    
    init() {}
}


class CameraFrustum {
    private let planes = [
        FrustumPlane(), FrustumPlane(), FrustumPlane(),
        FrustumPlane(), FrustumPlane(), FrustumPlane()
    ]
    var viewMatrix = simd_float4x4()
    
    func setFromMV(_ projection: simd_float4x4) {
        let viewProjectionRowMajor = (projection).transpose
        planes[0].setFrom(simd_normalize(viewProjectionRowMajor[3] + viewProjectionRowMajor[2]))
        planes[1].setFrom(simd_normalize(viewProjectionRowMajor[3] - viewProjectionRowMajor[2]))
        planes[2].setFrom(simd_normalize(viewProjectionRowMajor[3] + viewProjectionRowMajor[0]))
        planes[3].setFrom(simd_normalize(viewProjectionRowMajor[3] - viewProjectionRowMajor[0]))
        planes[4].setFrom(simd_normalize(viewProjectionRowMajor[3] - viewProjectionRowMajor[1]))
        planes[5].setFrom(simd_normalize(viewProjectionRowMajor[3] + viewProjectionRowMajor[1]))
        
        for plane in planes {
            plane.normalize()
        }
    }
    
    func checkPoint(_ point: simd_float3) -> Bool {
        return check(point: point, radius: 0)
    }
    
    func check(point: simd_float3, radius: Float) -> Bool {
        for plane in planes {
            if (plane.halfSpace(point) < -radius){
                return false
            }
        }
        return true
    }
    
    func check(mesh: GenericMesh, transform: ETransform) -> Bool {
        let rSO = viewMatrix * transform.matrix * mesh.cullingSphere.origin
        let r = simd_length(transform.matrix * simd_float4(x: 0, y: 0, z: mesh.cullingSphere.radius, w: 0))
        return check(point: simd_make_float3(rSO), radius: r)
    }
    
}


public class GameCamera {
    var position = simd_float3()
    var rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var fov: Float = 75.0 {
        didSet {
            projection = matrix_perspective_right_hand(
                fovyRadians: radians_from_degrees(fov),
                aspectRatio: aspectRatio,
                nearZ: nearZ, farZ: farZ)
        }
    }
    var aspectRatio: Float = 1.0 {
        didSet {
            projection = matrix_perspective_right_hand(
                fovyRadians: radians_from_degrees(fov),
                aspectRatio: aspectRatio,
                nearZ: nearZ, farZ: farZ)
        }
    }
    var nearZ: Float = 0.1 {
        didSet {
            projection = matrix_perspective_right_hand(
                fovyRadians: radians_from_degrees(fov),
                aspectRatio: aspectRatio,
                nearZ: nearZ, farZ: farZ)
        }
    }
    var farZ: Float = 100 {
        didSet {
            projection = matrix_perspective_right_hand(
                fovyRadians: radians_from_degrees(fov),
                aspectRatio: aspectRatio,
                nearZ: nearZ, farZ: farZ)
        }
    }
    
    var projection = simd_float4x4()
    var frustum = CameraFrustum()

    var matrix: simd_float4x4 {
        return simd_float4x4(rotation) * matrix4x4_translation(position.x, position.y, position.z)
    }
    
    var cmatrix: simd_float4x4 {
        return matrix4x4_translation(-position.x, -position.y, -position.z) * simd_float4x4(-rotation)
    }
    
    var direction: simd_float3 {
        return simd_make_float3(simd_float4x4(rotation.inverse) * simd_float4(0, 0, -1, 0))
    }
}


var registerableComponents: [any CodableComponent] = [
    ETappableComponent(),
    ECameraComponent(),
    SimpleParticleComponent(),
    EMusicComponent(),
]

var registerables: [any InitComponent] = [
    ETappableComponent(),
    ECameraComponent(),
    SimpleParticleComponent(),
    EMusicComponent(),
]
