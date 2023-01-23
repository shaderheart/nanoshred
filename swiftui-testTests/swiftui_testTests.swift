//
//  swiftui_testTests.swift
//  swiftui-testTests
//
//  Created by utku on 25/09/2022.
//

import XCTest

import simd


final class swiftui_testTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
        
    }
    
    func testGLBLoader() throws {
        let url = URL(fileURLWithPath: "/Users/utku/Documents/workspace/gamespace/shred3-vulkan/shred.3/resources/package/blender/scenes/exports/shredder_test_2.glb")
        var glbFileO = GLBFile.load(url)
        
        guard let glbFile = glbFileO else {throw POSIXError(.ECONNRESET)}
        
        var binaryData: Data? = nil
        
        if glbFile.chunks.count > 1 && glbFile.chunks[1].chunkType == .BIN {
            binaryData = Data.init(bytesNoCopy: glbFile.chunks[1].chunkData!,
                                  count: Int(glbFile.chunks[1].chunkLength),
                                  deallocator: Data.Deallocator.free)
        }
        
        var gltf: GLTFFile? = GLTFFile(jsonData: Data.init(bytesNoCopy: glbFile.chunks[0].chunkData!,
                                                           count: Int(glbFile.chunks[0].chunkLength),
                                                           deallocator: Data.Deallocator.none), binaryData: binaryData)
        gltf?.parse()

        print("Loading complete.")
    }
     
    func testGLTFLoader() throws {
//        var gltf = GLTFFile(path: URL(fileURLWithPath: "/Users/utku/Documents/blender/yuiwithlights.gltf"))!
        let url = URL(fileURLWithPath: "/Users/utku/Documents/workspace/gamespace/shred3-vulkan/shred.3/resources/package/blender/scenes/exports/binball.gltf")
        var gltf = GLTFFile(path: url)!
        gltf.parse()
        
        
        let lights = gltf.getLightNodes()
        let meshes = gltf.getMeshNodes()
        var metalMeshes: [GenericMesh] = []

        for mesh in meshes {
            print("Processing \(mesh.mesh!.name)")
            
            let gMesh = GenericMesh(gltfMesh: mesh.mesh!)
            metalMeshes.append(gMesh)
        }
        
        for node in gltf.fileNodes {
            if let shred = node.shredProps {
                print("Found a shred! \(shred)")
            }
        }
        
        
        print("Loading complete.")
    }
    
    func testMidiFile() throws {
        let midi = MIDIFile(path: "/Users/utku/Documents/game_projects/musicball/midis/DancingQueen.mid")
        let midi2 = MIDIFile(path: "/Users/utku/Documents/workspace/test/swiftui-test/assets/midis/ctyokine - butterfly.mid")
        
        print(midi.tracks.count)
        print(midi2.tracks.count)
        
    }
    
    func testRegistryBasic() throws {
        let registry = SHRegistry()
        for _ in 0..<50000 {
            let entity = registry.createEntity()
            let mesh: EMeshComponent? = registry.addComponentToEntity(entity)
            let transform: ETransformComponent? = registry.addComponentToEntity(entity)
            let music: EMusicComponent? = registry.addComponentToEntity(entity)
        }
        measure {
            let view = registry.view(types: [EMeshComponent.self])
            for entity in view {
                let mesh: EMeshComponent? = registry[entity]
                mesh?.meshName = ""
            }
        }
        
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
