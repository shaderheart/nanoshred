//
//  EngineSystems.swift
//  swiftui-test
//
//  Created by utku on 09/12/2022.
//

import Foundation

protocol EngineSystem {
    static func tick(deltaTime: Double, registry: SHRegistry)
    init()
}

#if !SCRIPT_CONTEXT
public class RenderingSystem: EngineSystem {
    static func tick(deltaTime: Double, registry: SHRegistry) {
        registry.forEach(types: [ECameraComponent.self]) { entity in
            let transform = entity.transform
            let camera: ECameraComponent = entity.component()!
            
            camera.transform.rotation = transform.global.rotation
            camera.transform.translation = transform.global.translation

            if MetalView.renderer != nil {
                MetalView.renderer!.camera.position = (-camera.transform.translation) * 0.1 + (MetalView.renderer!.camera.position * 0.9)
                MetalView.renderer!.camera.rotation = simd_slerp(MetalView.renderer!.camera.rotation, camera.transform.rotation.inverse, 0.1)
                if MetalView.renderer!.camera.fov != camera.FOV ||
                    MetalView.renderer!.camera.nearZ != camera.zNear ||
                    MetalView.renderer!.camera.farZ != camera.zFar
                {
                    MetalView.renderer!.camera.fov = camera.FOV
                    MetalView.renderer!.camera.nearZ = camera.zNear
                    MetalView.renderer!.camera.farZ = camera.zFar
                    MetalView.renderer!.camera.projection = matrix_perspective_right_hand(
                        fovyRadians: radians_from_degrees(camera.FOV),
                        aspectRatio: MetalView.renderer!.camera.aspectRatio,
                        nearZ: MetalView.renderer!.camera.nearZ, farZ: MetalView.renderer!.camera.farZ)
                }
            }
        }
    }
    
    required init(){}
}
#endif

public class PhysicsSystem: EngineSystem {
    static func tick(deltaTime: Double, registry: SHRegistry) {
#if !SCRIPT_CONTEXT
        prepareEntities(registry: registry)
        addEntitiesToWorld(registry: registry)
        
        registry.forEach(types: [EPhysicsComponent.self]) { (x: SHEntity) in
            let transform = x.transform
            if let physics: UnsafeMutablePointer<EPhysicsComponent> = x.component() {
                if physics.pointee.is_kinematic != 0 {
                    physics.pointee.physicsTransform.matrix = transform.global.matrix
                }
            }
        }
        
        var dT = deltaTime
        if deltaTime > 0.1 {dT = 0.1}
        PhysxBindings.advance(dT)
        
        registry.forEach(types: [EPhysicsComponent.self]) { (x: SHEntity) in
            let transform = x.transform
            if let physics: UnsafeMutablePointer<EPhysicsComponent> = x.component() {
                transform.global.matrix = physics.pointee.physicsTransform.matrix
            }
        }
#endif
    }
    
    required init() {
#if !SCRIPT_CONTEXT
        PhysxBindings.initializePhysicsWorld()
#endif
    }
    
#if !SCRIPT_CONTEXT
    static func invalidate(){
        PhysxBindings.invalidateCaches()
    }
    
    static func prepareEntities(registry: SHRegistry) {
        registry.forEach(types: [EPhysicsComponent.self]) { entity in
            
            if let physics: EPhysicsComponent = entity.component(), !(physics.prepared) {
                if let scriptComponent: EScriptComponent = entity.component() {
                    if let script = scriptComponent.scriptInstance as? PhysicsEvents {
                        physics.hitCallback = script.onHit
                        physics.overlapBeginCallback = script.onOverlapBegin
                        physics.overlapEndCallback = script.onOverlapEnd
                    }
                }
                if physics.shape == .CONVEX {
                    PhysxBindings.cookPhysxConvexHull(physics)
                    PhysxBindings.buildPhysxConvexHull(physics)
                }else if physics.shape == .MESH {
                    PhysxBindings.cookPhysxMesh(physics)
                    PhysxBindings.buildPhysxMesh(physics)
                }
                
                physics.prepared = true
                physics.parentEntity = entity
            }
        }
    }
    
    static func start(registry: SHRegistry) {

    }
    
    static func end(registry: SHRegistry) {
        registry.forEach(types: [EPhysicsComponent.self]) { (x: SHEntity) in
            let physics: EPhysicsComponent? = x.component()
            PhysxBindings.removeEntity(withPhysics: physics)
            physics?.inWorld = false
        }
    }
    
    static func addEntitiesToWorld(registry: SHRegistry) {
        registry.forEach(types: [EPhysicsComponent.self]) { entity in
            guard let physics: EPhysicsComponent = entity.component() else {return}
            if !physics.inWorld {
                let transform = entity.transform
                PhysxBindings.addEntityToWorld(withTransform: transform, physics: physics)
                physics.inWorld = true
                physics.parentEntity = entity
            }
        }
    }
#endif
    
    static func removeFromWorld(physics: EPhysicsComponent) {
#if !SCRIPT_CONTEXT
        PhysxBindings.removeEntity(withPhysics: physics)
#endif
    }
    
}

public class SoundSystem: EngineSystem {
    static var providers: [String: MidiEventProvider] = [:]
    static var backgroundMusic: BackgroundMusicPlayer?
    static var backgroundProvider: MidiEventProvider?
    static var backgroundComponent: EMusicComponent?
    
    static private var currentTime = 0.0
    static private var musicCurrentTime = 0.0
    static private var beatTime = 0.0
    static private var beatIndex = 0
    
    static func tick(deltaTime: Double, registry: SHRegistry) {
        guard let midiProvider = backgroundProvider,
              let music = backgroundMusic,
              music.readyToPlay
        else {
            return
        }
        
        registry.forEach(types: [EScriptComponent.self]) { entity in
            if let script: EScriptComponent = entity.component(),
               let musicHandler = script.scriptInstance as? MusicEvents {
                if !musicHandler.attached {
                    midiProvider.attachHandler(handler: musicHandler)
                    
                    musicHandler.gotAttached()
                }
            }
        }

        let musicDeltaTime = music.currentTime - musicCurrentTime
        musicCurrentTime = music.currentTime
        
        if abs(musicDeltaTime - deltaTime) > 0.003 {
            // print("Music-engine delta time discrepancy: \(musicDeltaTime), \(deltaTime)")
        }

        midiProvider.cumulativeTick(absoluteTime: musicCurrentTime)
        beatTime += deltaTime
        
        let secondsPerBeat = 1.0 / (Double(midiProvider.bpm) / 60.0)
        while beatTime > (secondsPerBeat) {
            beatTime -= secondsPerBeat
            beatIndex += 1
            
            registry.forEach(types: [EScriptComponent.self]) { entity in
                if let script: EScriptComponent = entity.component(),
                   let musicHandler = script.scriptInstance as? MusicEvents {
                    musicHandler.onBeat(beatIndex: beatIndex, time: currentTime)
                }
            }
            
        }
        currentTime = music.currentTime
        
    }
    
    static func startBackgroundMusic(song: EMusicComponent) {
        if backgroundComponent != nil {
            backgroundComponent?.isPlaying = false
        }
        backgroundMusic = .init(songName: song.file_name)
        
        if let midiPath = Bundle.main.url(forResource: song.accompanyingMidi, withExtension: ".mid", subdirectory: "midis") {
            backgroundProvider = .init(url: midiPath)
        }
        backgroundComponent = song
        
        currentTime = 0.0
        musicCurrentTime = 0.0
        beatTime = 0.0
        beatIndex = 0
        backgroundMusic?.startBlocking()
    }
    
    static func pauseMusic() {
        if let background = backgroundMusic {
            background.pause()
        }
    }
    
    static func resumeMusic() {
        if let background = backgroundMusic {
            background.resume()
        }
    }
    
    static func reset() {
        backgroundMusic?.reset()
        backgroundComponent = nil
        backgroundProvider = nil
        backgroundMusic = nil
        providers.removeAll()
        currentTime = 0.0
        musicCurrentTime = 0.0
        beatTime = 0.0
        beatIndex = 0
    }
    
    static func peekForward(track: String, startTime: Double = 0.0, endTime: Double = 999999999.0) -> [MIDIEvent] {
        if let provider = backgroundProvider {
            return provider.peekForward(track: track, startTime: startTime, endTime: endTime)
        } else {
            return []
        }
    }
    
    required init() {}
}
