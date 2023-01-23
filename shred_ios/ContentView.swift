//
//  ContentView.swift
//  swiftui-test
//
//  Created by utku on 21/09/2022.
//

import SwiftUI

import Metal
import MetalKit
import simd

import MusicKit
import MediaPlayer

import GameController

import UIKit.UIGestureRecognizerSubclass

class DebugViewModel: ObservableObject {
    @Published var currentAnimationFrame = "0"
    @Published var currentAnimationRotation = "0, 0, 0"
}

struct MetalView: View {
    @ObservedObject var dvm: DebugViewModel
    @ObservedObject var engineGlobals: EngineGlobals
    
    @State var metalView = MTKView()
    @State var fileContent = ""
    @State var showDocumentPicker = false
    static var renderer: Renderer?
    @State private var dropTargeted: Bool = false
    @State private var materialColor = CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
    @State static var rendererInitialized = false
    
    @State var isScenePickerVisible = false
        
    static var stateUpdateSemaphore = DispatchSemaphore(value: 1)
        
    static var gameStateDispatch: DispatchSourceTimer?
    
    func saveRestorableState(){
        if #available(macCatalyst 15, *) {
            let documentDir = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            var url = documentDir.appendingPathComponent("shaderheart.shred-ios")
            
            
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                
                url = url.appendingPathComponent("restorables")
                    .appendingPathExtension("json")
                
                print(url)
                
                EngineGlobals.restorableState.cameraRotation = MetalView.renderer!.camera.rotation
                EngineGlobals.restorableState.cameraPosition = MetalView.renderer!.camera.position
                
                let json = try JSONEncoder().encode(EngineGlobals.restorableState)
                try json.write(to: url)
            } catch {
                print(error)
            }
        }
    }
    
    func loadRestorableState(){
        if #available(macCatalyst 15, *) {
            let documentDir = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            var url = documentDir.appendingPathComponent("shaderheart.shred-ios")
            url = url.appendingPathComponent("restorables").appendingPathExtension("json")
            
            do {
                let raw = try Data(contentsOf: url)
                EngineGlobals.restorableState = try JSONDecoder().decode(EngineRestorableState.self, from: raw)
                
                let scenePath = EngineGlobals.restorableState.lastScene.relativePath
                print("Testing for file: \(scenePath)")
                
                if FileManager.default.isReadableFile(atPath: scenePath) {
                    print("Found resumable scene: \(EngineGlobals.restorableState.lastScene)")
                    GameStateManager.loadGLTF(url: EngineGlobals.restorableState.lastScene)
                }
                
                MetalView.renderer!.camera.rotation = EngineGlobals.restorableState.cameraRotation
                MetalView.renderer!.camera.position = EngineGlobals.restorableState.cameraPosition
                
                
            } catch {
                print(error)
            }
            
        }
    }
    
    @State var isGameRunning = false {
        didSet {
            engineGlobals.isGameRunning = isGameRunning
        }
    }
    
    struct gesturestatics {
        static var translation = CGSize()
        static var justStarted = true
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                BoopPreventer()
                
                MetalViewRepresentable(tappedCallback: {location in
                    // TODO: handle tapped callback!
                }, metalView: $metalView)
                .onAppear {
                    DispatchQueue.main.async {
                        // Select the device to render with.  We choose the default device
                        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
                            print("Metal is not supported on this device")
                            return
                        }
                        
                        metalView.device = defaultDevice
                        
                        let newRenderer = Renderer(metalKitView: metalView)
                        MetalView.renderer = newRenderer
                        MetalView.renderer!.mtkView(metalView, drawableSizeWillChange: metalView.drawableSize)
                        metalView.delegate = MetalView.renderer
                        MetalView.renderer?.camera.position = simd_float3(0, -1, -1)
                        
                        MetalView.rendererInitialized = true
                        
                        loadRestorableState()
                    }
                }
                .onDisappear {
                    saveRestorableState()
                }
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { item, location in
                    print(item)
                    item[0].loadItem(forTypeIdentifier: item[0].registeredTypeIdentifiers.first!, options: nil) {
                        (urlData, error) in
                        // ...?
                    }
                    return true
                }
            }
        }
    }
}

struct MetalViewRepresentable: UIViewRepresentable {
    var tappedCallback: ((CGPoint) -> Void)
    //let testPlayer = BackgroundMusicPlayer()

    
    class MetalGestureRecognizer: UIGestureRecognizer {
        var parent: MTKView? = nil
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            print("TOUCHES BEGAN!!")
            
            if let parent = parent,
               let location = touches.first?.location(in: parent) {
                
                MetalView.renderer!.tapPosition.x = location.x * UIScreen.main.nativeScale
                MetalView.renderer!.tapPosition.y = location.y * UIScreen.main.nativeScale
                MetalView.renderer!.tapRequested = true
            }
        }
        
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            print("TOUCHES MOVED!!")
        }
    }
    
    class Coordinator: NSObject {
            var tappedCallback: ((CGPoint) -> Void)
            init(tappedCallback: @escaping ((CGPoint) -> Void)) {
                self.tappedCallback = tappedCallback
            }
            @objc func tapped(gesture:UITapGestureRecognizer) {
                let point = gesture.location(in: gesture.view)
                self.tappedCallback(point)
            }
        }

        func makeCoordinator() -> MetalViewRepresentable.Coordinator {
            return Coordinator(tappedCallback:self.tappedCallback)
        }
        
    func makeUIView(context: Context) -> MTKView {
        // trigger local network access prompt
        let _ = ProcessInfo.processInfo.hostName
        
        do {
            if let urlForScenes = Bundle.main.resourceURL?.appendingPathComponent("scenes") {
                let items = try FileManager.default.contentsOfDirectory(at: urlForScenes, includingPropertiesForKeys: [URLResourceKey.isDirectoryKey])
                
                for scene in items {
                    if scene.hasDirectoryPath {
                        var canLoadScene = false
                        var sceneGLTFURL: URL?
                        var sceneName = ""
                        let sceneContents = try FileManager.default.contentsOfDirectory(at: scene, includingPropertiesForKeys: nil)
                        
                        for sceneFile in sceneContents {
                            if sceneFile.pathExtension == "gltf" {
                                canLoadScene = true
                                sceneGLTFURL = sceneFile
                                sceneName = sceneFile.lastPathComponent
                                break
                            }
                        }
                        
                        if canLoadScene {
                            EngineGlobals.availableScenes[sceneName] = sceneGLTFURL
                        }
                    }
                }
            }
        } catch {
            print(error)
        }
        

        // initialize 

        let gesturem = MetalGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        gesturem.parent = metalView
        metalView.addGestureRecognizer(gesturem)
    
        return metalView
        
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        
    }
    
    typealias UIViewType = MTKView
    @Binding var metalView: MTKView
}

struct HealthView: View {
    @State var healthValue = 100
    
    func set(newHealth: Int){
        healthValue = newHealth
        $healthValue.wrappedValue = healthValue
    }
    var body: some View {
        Text("Health: \(healthValue)")
    }
}

struct NodeTreeDetailView: View {
    @ObservedObject var model: NodeTreeDetailModel
    var body: some View {
        VStack {
            Text("name: " + model.name).lineLimit(1)
            Text("location: " + model.location).lineLimit(1)
            Text("rotation: " + model.rotation).lineLimit(1)
            Text("scale: " + model.scale).lineLimit(1)
        }
    }
}

struct ContentView: View {
    static let sdvm = DebugViewModel()
    static var globals = EngineGlobals()
    @ObservedObject var oglobals = globals
    
    static var nodeDetailModel = NodeTreeDetailModel()
    @ObservedObject var onodeDetailModel = nodeDetailModel
    
    static var healthView = HealthView()
        
    var body: some View {
        HStack {
            
            if oglobals.nodeOutlinerActive {
                ZStack {
                    Color.black
                    
                    VStack {
                        Button("done") {
                            ContentView.globals.nodeOutlinerActive = false
                        }
                        List(oglobals.nodeOutlinerTree, id: \.name, children: \.children) { node in
                            HStack {
                                Text((node.children?.isEmpty ?? true) ? node.name : "* " + node.name).lineLimit(0...1)
                                Button("v") {
                                    print("\(node.name)")
                                    ContentView.nodeDetailModel.targetTransform = node.transform
                                }.frame(alignment: .trailing)
                            }
                        }
                        NodeTreeDetailView(model: onodeDetailModel)
                    }
                }.frame(width: 200)
            }
            
            ZStack(alignment: .top){
                
                MetalView(dvm: ContentView.sdvm, engineGlobals: ContentView.globals)
                
                if oglobals.menuActive {
                    EngineMenuView(engineGlobals: ContentView.globals)
                    
                }
                
                if !oglobals.menuActive {
                    Button(action: {
                        ContentView.globals.menuActive = true
                        GameStateManager.pauseGame()
                    }, label: {
                        Image(systemName: "gear.circle")
                            .imageScale(.large)
                    })
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .buttonStyle(SettingsButtonStyle())
                }
                
                ContentView.healthView
                
            }
            //.padding()
            .frame(minWidth: 400, minHeight: 300)
#if !targetEnvironment(macCatalyst)
            .ignoresSafeArea()
#endif
        }
        
    }
}

struct AvailableScenesView: View {
    var onPick: (() -> ())?
    var body: some View {
        
        List {
            ForEach(Array(EngineGlobals.availableScenes), id: \.key) { key, value in
                Button(key) {
                    print("Will load a scene from: \(value)")
                    GameStateManager.loadGLTF(url: value)
                    onPick?()
                }
            }
        }
    }
    
    func onPick(fun: @escaping () -> ()) -> some View {
        var newView = self
        newView.onPick = fun
        return newView
    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


class BoopPreventerController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            let chars = press.key?.charactersIgnoringModifiers ?? ""
            if chars.count == 1 {
                EngineGlobals.input.setState(c: chars.first!, s: true)
            }
        }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            let chars = press.key?.charactersIgnoringModifiers ?? ""
            if chars.count == 1 {
                EngineGlobals.input.setState(c: chars.first!, s: false)
            }
        }
    }
}


/// this is placed within the body in a way that it's invisible, and it does not contain anything.
///  it's just used for preventing the OS from booping on keyboard key presses, as there's nothing else that captures them
struct BoopPreventer: UIViewControllerRepresentable {
    typealias UIViewControllerType = BoopPreventerController
    func makeUIViewController(context: Context) -> BoopPreventerController {
        let vc = BoopPreventerController()
        return vc
    }
    func updateUIViewController(_ uiViewController: BoopPreventerController, context: Context) {}
}
