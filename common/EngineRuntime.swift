//
//  EngineRuntime.swift
//  shred_ios
//
//  Created by utku on 29/12/2022.
//

import Foundation


struct GameStateManager {
    static var isGameRunning = false
    static var isGamePaused = true
    static let gameplayQueue = DispatchQueue(label: "com.shaderheart.GameplayQueue")

    
    static func startGame(){
        MetalView.stateUpdateSemaphore.wait()

        if MetalView.renderer?.gltfRegistry  == nil {
            return
        }
        weak var registry = MetalView.renderer?.gltfRegistry
        
        PhysicsSystem.start(registry: registry!)
        
        registry!.forEach(types: [EMusicComponent.self]) { entity in
            let music: EMusicComponent = entity.component()!
            SoundSystem.startBackgroundMusic(song: music)
        }
        
        var lastTime = 0.0
        
        MetalView.gameStateDispatch = DispatchSource.makeTimerSource()
        MetalView.gameStateDispatch?.setEventHandler {
            if !isGamePaused {
                MetalView.stateUpdateSemaphore.wait()
                guard let registry = registry else {
                    MetalView.gameStateDispatch?.cancel()
                    MetalView.gameStateDispatch = nil
                    return
                }
                let currentTime = CFAbsoluteTimeGetCurrent()
                var timeDelta = Double(currentTime - lastTime)
                timeDelta = min(0.033, timeDelta)
                let skip = lastTime == 0.0
                lastTime = currentTime
                
                if !skip {
                    registry.forEach(types: [EScriptComponent.self]) { entity in
                        let script: EScriptComponent? = entity.component()
                        script?.scriptInstance?.tick(deltaTime: Double(timeDelta), registry: registry)
                    }
                    
                    SoundSystem.tick(deltaTime: timeDelta, registry: registry)
                    PhysicsSystem.tick(deltaTime: timeDelta, registry: registry)
                    EngineGlobals.input.consume()
                    
                    registry.forEach(types: [EDestructionRequest.self]) { entity in
                        registry.destroy(entity: entity)
                    }
                }
                MetalView.stateUpdateSemaphore.signal()
            }
        }
        
        MetalView.gameStateDispatch?.setCancelHandler {
            print("Main game timer got cancelled?!")
        }
        
        MetalView.gameStateDispatch?.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .microseconds(1))
        MetalView.gameStateDispatch?.activate()
        
        MetalView.stateUpdateSemaphore.signal()
    }

    static func stopGame() {
        MetalView.stateUpdateSemaphore.wait()
                
        guard let registry = MetalView.renderer?.gltfRegistry else {
            MetalView.stateUpdateSemaphore.signal()
            return
        }
        PhysicsSystem.end(registry: registry)
        
        SoundSystem.reset()
        registry.reset()
        SimpleParticleManager.reset()
        MetalView.renderer?.pauseAllVideoTextures()
        
    //                            loadRestorableState()
        
        MetalView.gameStateDispatch?.cancel()
        MetalView.gameStateDispatch = nil
    //                            isGameRunning = false
        
        MetalView.stateUpdateSemaphore.signal()
    }
    
    static func pauseGame(){
        isGamePaused = true
        SoundSystem.pauseMusic()
        MetalView.renderer?.pauseAllVideoTextures()
    }
    
    static func resumeGame(){
        isGamePaused = false
        SoundSystem.resumeMusic()
        MetalView.renderer?.resumeVideoTextures()
    }
    
    
    static private var fileObverser : DispatchSourceFileSystemObject?
    static private let fileMonitorQueue = DispatchQueue(label: "FileMonitorQueue", attributes: .concurrent)
    static private var monitoredFileHandle: CInt = -1
    static func loadGLTF(url: URL, saveAsState: Bool = false){

        // clear current engine state
        GameStateManager.stopGame()
        MetalView.renderer?.gltfRegistry?.clear()
        MetalView.renderer?.cleanupGLTFScene()
        MetalView.renderer?.reset()
        
        
        let gltf = GLTFFile(path: url)
        gltf!.parse()
        
        // (re)initialize the file observer used for automatic reloading of scenes when the gltf file changes.
        if let obverser = GameStateManager.fileObverser {
            obverser.cancel()
        }
        
        GameStateManager.monitoredFileHandle = open(url.path, O_EVTONLY)
        if #available(macCatalyst 15, *) {
            GameStateManager.fileObverser = DispatchSource.makeFileSystemObjectSource(fileDescriptor: GameStateManager.monitoredFileHandle,
                                                                               eventMask: .write,
                                                                               queue: fileMonitorQueue)
            GameStateManager.fileObverser?.setEventHandler {
                print("Imported file changed, will reload!")
                GameStateManager.loadGLTF(url: url)
            }
            
            GameStateManager.fileObverser?.resume()
        }
        
        
        DispatchQueue.main.async {
            ContentView.globals.isGameRunning = false
            ContentView.globals.menuActive = true
        }

        PhysicsSystem.invalidate()
        
        let meshes = gltf!.getMeshNodes()
        
        for mesh in meshes {
            let gMesh = GenericMesh(gltfMesh: mesh.mesh!)
            gMesh.baseDir = gltf?.fileDirectory?.relativePath ?? "./"
            MetalView.renderer?.importGLTFBasedMesh(mesh: gMesh)
        }
        
        
        let gltfRegistry = SHRegistry(fromGLTFScene: gltf!)
        
        MetalView.renderer?.gltfRegistry = gltfRegistry
        
        EngineGlobals.restorableState.lastScene = url
    }
    
}
