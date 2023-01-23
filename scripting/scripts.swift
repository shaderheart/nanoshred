//
//  shred_scripts.swift
//  shred_scripts
//
//  Created by utku on 08/12/2022.
//

import Foundation

@objc
public class AllScripts: NSObject {
    public static let allScripts: [String: any ShredScript] = {
        let scripts: [any ShredScript] = [
            TestScript(),
            PulsingMaterialScript(),
            BinBallBall(),
            BallFollowingCamera(),
            GestureResponderScript(),
            MovingBulletScript(),
            BulletSpawnerScript(),
            TapPuzzleHolderScript(),
            TapPuzzleTappableScript(),
            GreenLevelLoader(),
            BulletDestroyer(),
            BeatBasedParticleController(),
            PlayerShipMover(),
            CameraHolderRotator(),
            GolfBallController(),
            CameraDistanceController(),
            EditorModeCamera(),
            TestingScript(),
        ]
        
        var scriptMap: [String: any ShredScript] = [:]
        
        for script in scripts {
            scriptMap[String(describing: type(of: script))] = script
        }
        return scriptMap
    }()
}

final class TestingScript: ShredScript {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {
        case index
    }
    
    var index = 0
    
}

final class TestScript: ShredScript {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
}

final class BinBallBall: ShredScript, PhysicsEvents {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    func onHit(other: EPhysicsComponent) {
        print("GOT HIT?!")
    }
    
    func onOverlapBegin(other: EPhysicsComponent) {
        print("A trigger is currently triggering me!")
        if let transform = attachedEntity?.transform {
            print("I was at \(transform.global.translation) when it happened!")
        }
    }

    func tick(deltaTime: Double, registry: SHRegistry) {
        typealias Controller = InputState.Controller
        if let entity = attachedEntity, let physics: EPhysicsComponent = entity.component() {
            if EngineGlobals.input.isDown(c: "w") {
                physics.impulse.z -= 0.3
            }
            if EngineGlobals.input.isDown(c: "s") {
                physics.impulse.z += 0.3
            }
            if EngineGlobals.input.isDown(c: "a") {
                physics.impulse.x -= 0.3
            }
            if EngineGlobals.input.isDown(c: "d") {
                physics.impulse.x += 0.3
            }
            
            
            physics.impulse.z -= 0.3 * EngineGlobals.input.axisValue(c: .leftThumbstickY)
            physics.impulse.x += 0.3 * EngineGlobals.input.axisValue(c: .leftThumbstickX)
            
        }
        
        if EngineGlobals.input.justPressed(c: "b") {
            if let transform = attachedEntity?.transform,
               let bullet = registry.loadPrototype(named: "playerBullet", overrideTransform: transform.global)
            {
                bullet.transform.global.matrix = transform.global.matrix
                bullet.transform.local.matrix = bullet.transform.global.matrix
            }
        }
        
    }
}


final class EditorModeCamera: ShredScript {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    
    func tick(deltaTime: Double, registry: SHRegistry) {
        if let transform = attachedEntity?.transform {
            var dx = EngineGlobals.input.axisDelta(c: .scrollX)
            var dy = EngineGlobals.input.axisDelta(c: .scrollY)
            if dx == 0 {
                dx = -EngineGlobals.input.axisValue(c: .rightThumbstickX)
            }
            if dy == 0 {
                dy = -EngineGlobals.input.axisValue(c: .rightThumbstickY)
            }
            let rotX = simd_quatf(angle: Float(dx * 0.01), axis: SIMD3<Float>(0, 1, 0))
            let rotY = simd_quatf(angle: Float(dy * 0.01), axis: SIMD3<Float>(-1, 0, 0))
            transform.local.rotation = rotX * transform.local.rotation * rotY
            
            do { // manage keyboard input
                var positionDeltaRequest = simd_float3(repeating: 0)
                let moveSpeed =  deltaTime * 10
                if EngineGlobals.input.isDown(c: "w") {
                    positionDeltaRequest.z += 1.0
                }
                if EngineGlobals.input.isDown(c: "s") {
                    positionDeltaRequest.z -= 1.0
                }
                if EngineGlobals.input.isDown(c: "a") {
                    positionDeltaRequest.x += 1.0
                }
                if EngineGlobals.input.isDown(c: "d") {
                    positionDeltaRequest.x -= 1.0
                }
                if EngineGlobals.input.isDown(c: "q") {
                    positionDeltaRequest.y += 1.0
                }
                if EngineGlobals.input.isDown(c: "e") {
                    positionDeltaRequest.y -= 1.0
                }
                
                if positionDeltaRequest.z == 0.0 {
                    positionDeltaRequest.z = -EngineGlobals.input.axisValue(c: .leftThumbstickY)
                }
                
                if positionDeltaRequest.x == 0.0 {
                    positionDeltaRequest.x = -EngineGlobals.input.axisValue(c: .leftThumbstickX)
                }
                
                if simd_length(positionDeltaRequest) > 0 {
                    positionDeltaRequest = -simd_float3x3(transform.local.rotation) * simd_normalize(positionDeltaRequest) * Float(moveSpeed)
                    transform.local.translation += positionDeltaRequest
                }
            }
            
        }
    }
    
}

final class BallFollowingCamera: ShredScript {
    weak var attachedEntity: SHEntity?
    weak var parent: SHEntity?
    enum CodingKeys: CodingKey {}
    func tick(deltaTime: Double, registry: SHRegistry) {
        
    }
}



final class GolfBallController: ShredScript {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    
    var direction: simd_float3 = .init(x: 0, y: 0, z: -1)
    
    func tick(deltaTime: Double, registry: SHRegistry) {
        if let entity = attachedEntity,
           let ballChild = entity.relationship.getChildWithTag(tag: "ball"),
           let ballPhysics: EPhysicsComponent = ballChild.component(){
            entity.transform.global.translation = ballChild.transform.global.translation
            if EngineGlobals.input.justPressed(c: " ") ||
                EngineGlobals.input.justPressed(c: .left) ||
                EngineGlobals.input.justPressed(c: .a)
            {
                direction = EngineGlobals.activeCamera.direction
                direction.y = 0
                direction = simd_normalize(direction)
                ballPhysics.impulse = direction * 10.0
            }
        }
    }
}

final class CameraHolderRotator: ShredScript {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    
    func tick(deltaTime: Double, registry: SHRegistry) {
        if let transform = attachedEntity?.transform {
            var dx = EngineGlobals.input.axisDelta(c: .scrollX)
            if dx == 0 {
                dx = EngineGlobals.input.axisValue(c: .leftThumbstickX)
            }
            let rotX = simd_quatf(angle: Float(dx * 0.01), axis: SIMD3<Float>(0, 1, 0))
            transform.local.rotation = transform.local.rotation * rotX
        }
    }
}


final class CameraDistanceController: ShredScript {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    
    func tick(deltaTime: Double, registry: SHRegistry) {
        if let entity = attachedEntity,
           let animations: AnimationControllerComponent = entity.component()
        {
            let dy = EngineGlobals.input.axisDelta(c: .scrollY)
            for animation in animations.targetAnimations {
                animation.playbackSpeed = 0.0
                animation.currentTime += dy * 0.01
                animation.currentTime = max(0.001, min(animation.length, animation.currentTime))
            }
        }
    }
}


final class CameraAnimationController: ShredScript {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    
    func tick(deltaTime: Double, registry: SHRegistry) {
        if let entity = attachedEntity, let animationController: AnimationControllerComponent = entity.component() {
            animationController.targetAnimations[0].playbackSpeed = 0.0
            animationController.targetAnimations[0].enabled = true
        }
    }
    
}


final class PlayerShipMover: ShredScript {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    
    enum position: String {
        case left = "Left"
        case center = "Center"
        case right = "Right"
    }
    
    var currentPosition: position = .center
    
    func tick(deltaTime: Double, registry: SHRegistry) {
        var playerEntity: SHEntity?
        guard let entity = attachedEntity else{
            return
        }
        
        for child in entity.relationship.children {
            if child.name.contains(currentPosition.rawValue) {
                // check if the targeted position has the player
                if !child.relationship.children.isEmpty {
                    playerEntity = child.relationship.children[0]
                }
                break
            }
        }
        
        if playerEntity != nil {
            var target = currentPosition
            if EngineGlobals.input.justPressed(c: "a") {
                switch currentPosition {
                case .center:
                    target = .left
                case .right:
                    target = .center
                case .left:
                    break
                }
            }
            
            if EngineGlobals.input.justPressed(c: "d") {
                switch currentPosition {
                case .center:
                    target = .right
                case .left:
                    target = .center
                case .right:
                    break
                }
            }
            
            if target != currentPosition {
                currentPosition = target
                for child in entity.relationship.children {
                    if child.name.contains(currentPosition.rawValue) {
//                        ERelationshipComponent.attachEntityToEntity(registry: registry, parent: child, child: playerEntity!)
                        break
                    }
                }
            }
        }
    }
    
}

final class PulsingMaterialScript: ShredScript {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    func tick(deltaTime: Double, registry: SHRegistry) {
        guard let entity = attachedEntity else {
            return
        }
        let meshComponent: EMeshComponent? = entity.component()
        if let mesh = meshComponent, let meshInstance = mesh.meshInstance {
            meshInstance.primitives[0].material.color = .init(repeating: 0.75)
        }
        
    }
}


final class GestureResponderScript: ShredScript {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    func tick(deltaTime: Double, registry: SHRegistry) {
        if let tappable: ETappableComponent = attachedEntity?.component() {
            if tappable.justTapped {
                print("I GOT TAPPED!")
                tappable.justTapped = false
            }
        }
    }
}


final class MovingBulletScript: ShredScript, PhysicsEvents, InputEvents {
    weak var attachedEntity: SHEntity?
    var velocity: simd_float3? = .init(x: 0, y: 0, z: 10)
    enum CodingKeys: CodingKey {case velocity}
    
    func tick(deltaTime: Double, registry: SHRegistry) {
        if let transform = attachedEntity?.transform {
            if velocity != nil {
                transform.global.translation += velocity! * Float(deltaTime)
            }else {
                transform.global.translation.z += Float(10 * deltaTime)
            }
        }
        if let tappable: ETappableComponent = attachedEntity?.component() {
            if tappable.justTapped {
                print("I GOT TAPPED!")
                onTap()
                tappable.justTapped = false
            }
        }
    }

    func onOverlapBegin(other: EPhysicsComponent) {
        if let entity = attachedEntity {
            print("Goodbye gruel world.")
//            entity.components[EDestructionRequest.self]  = EDestructionRequest()
        }
    }

    func onTap() {
        if let entity = attachedEntity {
            print("Goodbye gruel world.")
//            entity.components[EDestructionRequest.self]  = EDestructionRequest()
        }
    }
    
}

final class BulletDestroyer: ShredScript, PhysicsEvents {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    func onOverlapBegin(other: EPhysicsComponent) {
        if let otherEntity = other.parentEntity {
            if otherEntity.transform.name.contains("bullet") {
//                otherEntity.components[EDestructionRequest.self]  = EDestructionRequest()
            }
        }
    }
}


final class BeatBasedParticleController: ShredScript, MusicEvents {
    func gotAttached() {
        attached = true
    }
    
    var targetMidiFile: String = ""
    var targetTrack: String = "bass"
    var getFromAllChannels: Bool = false
    var attached: Bool = false
    
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    
    weak var emitterComponent: SimpleParticleComponent? = nil
    var emitFor = 0.1
    var emitCounter = 0.0
    
    func tick(deltaTime: Double, registry: SHRegistry) {
        if emitterComponent == nil, let entity = attachedEntity {
            emitterComponent = entity.component()
        }
        
        if emitCounter < 0.0 {
            emitCounter = 0.0
            emitterComponent?.enabled = false
        } else if emitCounter > 0.0 {
            emitCounter -= deltaTime
        }
    }
    
    func onBeat(beatIndex: Int, time: Double) {
        emitterComponent?.enabled = true
        emitCounter = emitFor
    }
}


final class BulletSpawnerScript: ShredScript, MusicEvents {
    weak var attachedEntity: SHEntity?
    
    var targetMidiFile: String = ""
    var targetTrack: String = "drums"
    var getFromAllChannels: Bool = false
    var attached = false

    var spawnLocationCache: [ETransform] = []
    var randomGenerator = SystemRandomNumberGenerator()

    let tickRate = 2.5
    var currentTime = 0.0
    
    var createBulletNow = false
    
    var spawnTarget: ETransform?
    
    enum CodingKeys: CodingKey {
        case targetTrack
        case tickRate
    }
    
    func tick(deltaTime: Double, registry: SHRegistry) {
        // fill the cache if it's empty
        if spawnLocationCache.isEmpty {
            if let relationship = attachedEntity?.relationship {
                for child in relationship.children {
                    spawnLocationCache.append(child.transform.global)
                }
            }
        }
        
        if createBulletNow {
            if let bullet = registry.loadPrototype(named: "bullet", overrideTransform: spawnTarget),
               spawnTarget != nil
            {
                bullet.transform.global.matrix = spawnTarget!.matrix
                bullet.transform.local.matrix = bullet.transform.global.matrix
            }
            currentTime = 0.0
            createBulletNow = false
        }
        
        currentTime += deltaTime
    }
  
    func onNoteOn(noteNumber: Int, time: Double) {
        guard !spawnLocationCache.isEmpty else { return }
        spawnTarget = spawnLocationCache[0]
        if noteNumber == 48 {
            spawnTarget = spawnLocationCache[0]
        } else if noteNumber == 50 {
            spawnTarget = spawnLocationCache[1]
        } else if noteNumber == 56 {
            spawnTarget = spawnLocationCache[2]
        }
        createBulletNow = true
    }
    
    func gotAttached() {
        attached = true
    }
    
}

final class TapPuzzleHolderScript: ShredScript {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    enum ThingsMyChildCanTellMe {
        case iveBeenTapped
        case iveBeenHit
    }
    
    func iHaveSomethingVeryImportantToTellYou(theThingIs: ThingsMyChildCanTellMe){
        
    }
}


final class TapPuzzleTappableScript: ShredScript, InputEvents {
    weak var attachedEntity: SHEntity?
    enum CodingKeys: CodingKey {}
    
    var mother: TapPuzzleHolderScript!
    
    func onTap() {
        if mother == nil {
            // find the mother
            let relationships = attachedEntity?.relationship
            let motherEntity = relationships?.parent
            if let motherScript: EScriptComponent = motherEntity?.component(){
                mother = motherScript.scriptInstance as? TapPuzzleHolderScript
            }
        }
        mother.iHaveSomethingVeryImportantToTellYou(theThingIs: .iveBeenTapped)
    }
}

final class GreenLevelLoader: ShredScript, PhysicsEvents {
    weak var attachedEntity: SHEntity?
    
    var playerIsCurrentlyInBox = false
    
    var loadAfterTime = 5.0
    var currentTime = 0.0
    
    enum CodingKeys: CodingKey {
        case loadAfterTime
    }
    
    func tick(deltaTime: Double, registry: SHRegistry) {
        if playerIsCurrentlyInBox {
            currentTime += deltaTime
            
            if currentTime > loadAfterTime {
                print("Would've loaded the green level so hard right now...")
            }
            
        }
    }
    
    func onHit(other: EPhysicsComponent) {
        
    }
    
    func onOverlapBegin(other: EPhysicsComponent) {
        if let otherEntity = other.parentEntity,
           let _: EMainPlayerMarker = otherEntity.component() {
            playerIsCurrentlyInBox = true
        }
    }
    
    func onOverlapEnd(other: EPhysicsComponent) {
        print("The player left me...")
        if let otherEntity = other.parentEntity,
           let _: EMainPlayerMarker = otherEntity.component() {
            playerIsCurrentlyInBox = false
            currentTime = 0.0
        }
    }
}
