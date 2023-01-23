//
//  ShredRegistry.swift
//  swiftui-test
//
//  Created by utku on 12/12/2022.
//

import Foundation

func loadCodableFromDictionary<T: Decodable>(from: [String: Any]) -> T? {
    guard let jsonData = try? JSONSerialization.data(withJSONObject: from, options: []) else {
        return nil
    }
    let decoder = JSONDecoder()
    do {
        let value = try decoder.decode(T.self, from: jsonData)
        return value
    } catch {
        print(error)
    }
    return nil
}

public class SHEntity: Equatable, Hashable {
    public static func == (lhs: SHEntity, rhs: SHEntity) -> Bool {
        lhs.entityID == rhs.entityID
    }
    
    public var entityID: UInt
    var name: String = ""
    var transform: ETransformComponent = .init()
    var relationship: ERelationshipComponent = .init()
    weak public var containingRegistry: SHRegistry?
    
    
    init(registry: SHRegistry, entityID: UInt, name: String?) {
        containingRegistry = registry
        self.entityID = entityID
        self.name = name ?? ""
    }
    
    @inlinable func component<T: InitComponent>() -> T? {
        return containingRegistry?[self]
    }
    
    @inlinable func component<T: InitComponent>() -> UnsafeMutablePointer<T>? {
        return containingRegistry?[self]
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(entityID)
        hasher.combine(name)
    }

}

public protocol SHSparseComponentSetProtocol: Hashable, Equatable {
    associatedtype T: InitComponent
    func insert(entity: SHEntity) -> T?
    func insert(entity: SHEntity, component: T) -> T?
    func remove(entity: SHEntity)
    func has(entity: SHEntity) -> Bool
    subscript(entity: SHEntity) -> T? {get}
    subscript(denseID: UInt) -> T? {get}
    func iterate(_ with: ((T) -> ()))
    func ptr(entity: SHEntity) -> UnsafeMutablePointer<T>?
}

public class SHSparseComponentSet<T: InitComponent>: SHSparseComponentSetProtocol {
    public typealias T = T
    public var sparse: ContiguousArray<UInt> = []
    public var dense: ContiguousArray<T> = []
    public var denseCount = 0
    
    func sparseExpand(upTo: UInt) {
        if sparse.count < (upTo + 1) {
            sparse.reserveCapacity(Int(upTo + 1))
            sparse.append(contentsOf: [UInt](repeating: .max, count: Int(upTo + 1) - sparse.count))
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(T.typeID)
    }
    public static func == (lhs: SHSparseComponentSet<T>, rhs: SHSparseComponentSet<T>) -> Bool {
        true
    }
    
    public func reset() {
        sparse = []
        dense = []
        denseCount = 0
    }
    
    public func insert(entity: SHEntity) -> T? {
        sparseExpand(upTo: entity.entityID)
        sparse[Int(entity.entityID)] = UInt(dense.count)
        dense.append(T())
        denseCount += 1
        return dense.last
    }
    
    public func insert(entity: SHEntity, component: T = T()) -> T? {
        sparseExpand(upTo: entity.entityID)
        sparse[Int(entity.entityID)] = UInt(dense.count)
        dense.append(component)
        denseCount += 1
        return dense.last
    }
    
    public func remove(entity: SHEntity) {
        sparseExpand(upTo: entity.entityID)
        let moveIndex = sparse[Int(entity.entityID)]
        sparse[Int(entity.entityID)] = .max
        let moveID = dense[dense.count - 1].entity!.entityID
        let moveFromIndex = sparse[Int(moveID)]
        dense[Int(moveIndex)] = dense[Int(moveFromIndex)]
        denseCount -= 1
        sparse[Int(moveID)] = moveIndex
    }
    
    @inlinable public func has(entity: SHEntity) -> Bool {
        var has = false
        has = Int(entity.entityID) < sparse.count && sparse[Int(entity.entityID)] < denseCount
        return has
    }
    
    @inlinable public subscript(entity: SHEntity) -> T? {
        if sparse.count > entity.entityID && sparse[Int(entity.entityID)] < denseCount {
            return dense[Int(sparse[Int(entity.entityID)])]
        }
        return nil
    }
    
    @inlinable public func ptr(entity: SHEntity) -> UnsafeMutablePointer<T>? {
        if sparse.count > entity.entityID && sparse[Int(entity.entityID)] < denseCount {
            let pointer = dense.withContiguousMutableStorageIfAvailable { bufferPointer in
                // TODO: this is quite dangerous, it returns a pointer from a storage that could be reallocated.
                return bufferPointer.baseAddress?.advanced(by: Int(sparse[Int(entity.entityID)]))
            }
            return pointer ?? nil
        }
        return nil
    }
    
    @inlinable public subscript(denseID: UInt) -> T? {
        if sparse.count > denseID && sparse[Int(denseID)] < dense.count {
            return dense[Int(sparse[Int(denseID)])]
        }
        return nil
    }
    
    @inlinable public func iterate(_ with: ((T) -> ())) {
        for item in dense {
            with(item)
        }
    }
}


public protocol SHQueryProtocol {
    @inlinable func has(entity: SHEntity) -> Bool
    @inlinable func iterate(functor: (any InitComponent) -> Void)

}

public struct SHQuery<C: InitComponent>: SHQueryProtocol {
    @inlinable public func has(entity: SHEntity) -> Bool {
        C.storage.has(entity: entity)
    }
    
    @inlinable public func iterate(functor: (any InitComponent) -> Void) {
        C.storage.dense.withContiguousStorageIfAvailable { buffer in
            for component in buffer {
                functor(component)
            }
        }
    }
}

public class SHRegistry {
    private var entityCounter: UInt = 0
    public var entities: [SHEntity?] = []
    var entityHoles: [UInt] = []
    
    var encounteredComponents: [UUID: any InitComponent.Type] = [:]
    
    var nodeEntityMap: [GLTFFile.GLTFNode: SHEntity] = [:]
    
    var animations: [NodeAnimation] = []
    var boneAnimations: [String: BoneAnimation] = [:]
    
    static var scriptContext: ScriptContext = .init()
    
    var prototypes: [String: GLTFFile.GLTFNode] = [:]
    var sourceFile: GLTFFile?
    
    func createEntity(name: String? = nil) -> SHEntity {
        let targetIndex = entityHoles.popLast()
        let newEntity = SHEntity(registry: self, entityID: targetIndex ?? entityCounter, name: name)
        if targetIndex == nil {
            entityCounter += 1
            entities.append(newEntity)
        } else {
            entities[Int(targetIndex!)] = newEntity
        }
        return newEntity
    }
    
    func destroy(entity: SHEntity) {
        entityHoles.append(entity.entityID)
        entities[Int(entity.entityID)] = nil
        
        // handle components that deal with special systems
        if let physics: EPhysicsComponent = entity.component() {
            PhysicsSystem.removeFromWorld(physics: physics)
        }
    }
    
    func addComponentToEntity<T: InitComponent>(_ entity: SHEntity, component: T = T()) -> T? {
        encounteredComponents[T.typeID] = T.self
        var component = T.storage.insert(entity:entity, component: component)
        component?.entity = entity
        return component
    }
    
    func addComponentToEntity<T: ArgComponent>(_ entity: SHEntity, args: Any...) -> T? {
        var component: T? = T.storage.insert(entity:entity, component: T(args: args))
        component?.entity = entity
        return component
    }

    @inlinable func getComponentOfEntity<T: InitComponent>(_ entity: SHEntity) -> T? {
        T.storage[entity]
    }
    
    func getOrCreateComponent<T: InitComponent>(_ entity: SHEntity) -> T? {
        if let component: T = entity.component() {
            return component
        }else{
            return addComponentToEntity(entity)
        }
    }

    @inlinable func forEach(types: [any InitComponent.Type], exclude: [any InitComponent.Type] = [], functor: ((SHEntity) -> Void)) {
        let entities = view(types: types, exclude: exclude)
        for entity in entities {
            functor(entity)
        }
    }
    
    @inlinable func iterate(functor: (SHEntity) -> Void) {
        for entity in entities {
            if let entity = entity {
                functor(entity)
            }
        }
    }
    
    public struct QuerySet {
        public var contains: [SHQueryProtocol] = []
        public var excludes: [SHQueryProtocol] = []
        
        init(contains: [SHQueryProtocol], exclude: [SHQueryProtocol] = []) {
            self.contains.append(contentsOf: contains)
            self.excludes.append(contentsOf: exclude)
        }
        mutating func has<T: InitComponent>(_ componentType: T.Type){
            contains.append(SHQuery<T>() as SHQueryProtocol)
        }
        
        mutating func exclude<T: InitComponent>(_ componentType: T.Type){
            excludes.append(SHQuery<T>() as SHQueryProtocol)
        }
        
        public init(contains: [any InitComponent.Type], excludes: [any InitComponent.Type] = []) {
            for contain in contains {
                has(contain)
            }
            for exclude in excludes {
                self.exclude(exclude)
            }
        }
        
        public func perform(entity: SHEntity) -> Bool {
            var result = true
            for contain in contains {
                result = result && contain.has(entity: entity)
            }
            for exclude in excludes {
                result = result && !exclude.has(entity: entity)
            }
            return result
        }
    }
    
    @inlinable func view(types: [any InitComponent.Type], exclude: [any InitComponent.Type] = []) -> [SHEntity] {
        var matches: [SHEntity] = []
        let q = QuerySet(contains: types, excludes: exclude)
        
        if !q.contains.isEmpty {
            // pick the first requested type, and walk other sets using that
            if q.contains.count > 1 || q.excludes.count > 0 {
                q.contains[0].iterate { component in
                    guard let entity = component.entity else {return}
                    if q.perform(entity: entity) {
                        matches.append(entity)
                    }
                }
            } else {
                q.contains[0].iterate { component in
                    guard let entity = component.entity else {return}
                    matches.append(entity)
                }
            }
        } else if !q.excludes.isEmpty {
            
        }
        
        return matches
    }
    
    @inlinable subscript<T: InitComponent>(entity: SHEntity) -> T? {
        T.storage[entity]
    }
    
    @inlinable subscript<T: InitComponent>(entity: SHEntity) -> UnsafeMutablePointer<T>? {
        T.storage.ptr(entity: entity)
    }
    
    func recursiveConstruct(node: GLTFFile.GLTFNode, overrideTransform: ETransform? = nil) -> SHEntity {
        let parent = construct(node: node, overrideTransform: overrideTransform)
        for childNode in node.children ?? [] {
            let child = recursiveConstruct(node: childNode)
            ERelationshipComponent.attachEntityToEntity(registry: self, parent: parent, child: child)
        }
        return parent
    }
    
    func construct(node: GLTFFile.GLTFNode, overrideTransform: ETransform? = nil) -> SHEntity {
        let nodeEntity = createEntity(name: node.name)
        
        nodeEntityMap[node] = nodeEntity
        
        if overrideTransform == nil {
            nodeEntity.transform.local.matrix = node.transform.matrix
            nodeEntity.transform.global.matrix = node.transform.matrix
        } else {
            nodeEntity.transform.local.matrix = overrideTransform!.matrix
            nodeEntity.transform.global.matrix = overrideTransform!.matrix
        }
        
        var shredExtras = node.extras?["shred"] as? [String: Any]
        
        if shredExtras == nil, let shredString = node.extras?["shred"] as? String {
            if let data = shredString.data(using: .utf8) {
                shredExtras = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
        }
        
        // add mesh
        if let mesh = node.mesh, shredExtras != nil, shredExtras!["dont_render"] == nil {
            let meshComponent: EMeshComponent = addComponentToEntity(nodeEntity)!
            meshComponent.meshName = mesh.name
        }
        
        // add light
        if let light = node.punctualLight?.reference {
            let lightComponent: EPunctualLight = addComponentToEntity(nodeEntity, args: light)!
            
            if let lightProps = shredExtras?["light"] as? [String: Any] {
                lightComponent.castsShadows = lightProps["castShadows"] as? Bool ?? false
            }
            
        }
        
        // scripts
        if let script = shredExtras?["script"] as? [String: Any],
           let scriptInstance = AllScripts.allScripts[script["name"] as? String ?? ""] {
            let scriptComponent: EScriptComponent = addComponentToEntity(nodeEntity)!
            scriptComponent.scriptName = script["name"] as? String ?? ""
            scriptComponent.scriptInstance = scriptInstance.clone()
            scriptComponent.scriptInstance?.attachedEntity = nodeEntity
        }
        
        // camera
        if let camera = shredExtras?["camera"] as? [String: Any],
           let cameraComponent: ECameraComponent = loadCodableFromDictionary(from: camera)
        {
            let _ = addComponentToEntity(nodeEntity, component: cameraComponent)
        }
        
        // others
        if let simpleEmitter = shredExtras?["SimpleParticleComponent"] as? [String: Any] {
            if let simpleEmitterComponent: SimpleParticleComponent = loadCodableFromDictionary(from: simpleEmitter) {
                let _ = addComponentToEntity(nodeEntity, component: simpleEmitterComponent)
            }
        }
        
        // physics
    physicsLoading:
        if let physics = shredExtras?["physics"] as? [String: Any] {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: physics, options: []) else {
                break physicsLoading
            }
            let decoder = JSONDecoder()
            do {
                let physicsComponent = try decoder.decode(EPhysicsComponent.self, from: jsonData)
                let scaleUpAxis = physicsComponent.scale.z
                physicsComponent.scale.z = physicsComponent.scale.y
                physicsComponent.scale.y = scaleUpAxis
                physicsComponent.physicsTransform.matrix = nodeEntity.transform.global.matrix
                
                if (physicsComponent.shape == .MESH || physicsComponent.shape == .CONVEX) && node.mesh != nil {
                    physicsComponent.physicsMeshName = node.mesh!.name
                    physicsComponent.vertexFloats = node.mesh?.getVerticesAsFloats()
                }
                let _ = addComponentToEntity(nodeEntity, component: physicsComponent)
            } catch {
                print(error)
            }
        }

        // tappable
        if let _ = shredExtras?["tappable"] as? [String: Any] {
            let _ = addComponentToEntity(nodeEntity, component: ETappableComponent())
        }
        
        // mainplayer
        if let _ = shredExtras?["mainplayer"] {
            let _ = addComponentToEntity(nodeEntity, component: EMainPlayerMarker())
        }
        
        // music
    musicLoading:
        if let music = shredExtras?["music"] as? [String: Any] {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: music, options: []) else {
                break musicLoading
            }
            let decoder = JSONDecoder()
            do {
                let musicComponent = try decoder.decode(EMusicComponent.self, from: jsonData)
                let _ = addComponentToEntity(nodeEntity, component: musicComponent)
            } catch {
                print(error)
            }
        }
        
        return nodeEntity
    }
    
    func advanceAnimations(deltaTime: Double) {
        for animation in animations {
            if animation.enabled {
                animation.advance(deltaTime: deltaTime)
            }
        }
    }
    
    func reset(){
        clear()
        restart()
    }
    
    convenience init(fromGLTFScene: GLTFFile) {
        self.init()
        sourceFile = fromGLTFScene
        
        nodeEntityMap = [:]
        animations = []
        boneAnimations = [:]
        
        loadFromScene(gltfScene: fromGLTFScene)
    }
    
    func clear(){
        nodeEntityMap = [:]
        animations = []
        boneAnimations = [:]
        entities = []
        entityCounter = 0
        entityHoles = []
        for (_, encounteredComponent) in encounteredComponents {
            encounteredComponent.resetStorage()
        }
    }
    
    func restart() {
        clear()
        if let source = sourceFile {
            loadFromScene(gltfScene: source)
        } else {
            print("Cannot reset, the source GLTFFile has been deallocated.")
        }
    }
    
    func loadFromScene(gltfScene: GLTFFile) {
        var entityList = [SHEntity]()
        // build individual entities from nodes
        for node in gltfScene .fileNodes {
            if !node.isPrototype {
                let nodeEntity = construct(node: node)
                entityList.append(nodeEntity)
            } else {
                prototypes[node.name] = node
            }
        }
        
        // build relationships
        var nodeIndex = 0
        for node in gltfScene.fileNodes {
            if !node.isPrototype {
                let currentEntity = entityList[nodeIndex]
                for child in node.childrenIndices ?? [] {
                    let childEntity = entityList[child]
                    ERelationshipComponent.attachEntityToEntity(registry: self, parent: currentEntity, child: childEntity)
                }
                nodeIndex += 1
            }
        }
        
        for animation in gltfScene.animations {
            let nodeAnimation = NodeAnimation(fromGltfAnimation: animation)
            for channel in nodeAnimation.channels {
                if channel.targetNode != nil, let animationEntity = nodeEntityMap[channel.targetNode!] {
                    channel.setTarget(target: animationEntity)
                    if let animationController: AnimationControllerComponent = addComponentToEntity(animationEntity) {
                        animationController.targetAnimations.append(nodeAnimation)
                    }
                }
            }
            animations.append(nodeAnimation)
        }
        
        for skin in gltfScene.skins {
            let boneAnimation = BoneAnimation(skin: skin, nodeEntityMap: nodeEntityMap)
            boneAnimations[skin.name] = boneAnimation
        }
        
        for node in gltfScene.fileNodes {
            if node.skin != nil {
                let entity = nodeEntityMap[node]!
                let boneAnimationComponent: EBoneAnimationComponent = addComponentToEntity(entity)!
                boneAnimationComponent.boneAnimation = boneAnimations[node.skin!.reference!.name]
            }
        }
        #if !SCRIPT_CONTEXT
//        ContentView.globals.nodeOutlinerTree = sceneParentRelationship.buildNodeTree()
        #endif
    }
    
    func loadPrototype(named: String, overrideTransform: ETransform? = nil) -> SHEntity? {
        if let targetNode = prototypes[named] {
            let prototype = recursiveConstruct(node: targetNode, overrideTransform: overrideTransform)
            return prototype
        }
        return nil
    }

}
