//
//  EngineMenuView.swift
//  shred_ios
//
//  Created by utku on 25/12/2022.
//

import SwiftUI


struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .frame(width:30, height: 30)
            .foregroundColor(Color.white)
            .background(.regularMaterial)
            .cornerRadius(10.0)
            .padding(5)

    }
}

struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .frame(width:140)
            .foregroundColor(Color.white)
            .padding()
            .border(Color.orange, width: 3.0)
            .background(LinearGradient(gradient: Gradient(colors: [Color.pink, Color.purple, Color.cyan]), startPoint: .leading, endPoint: .trailing))
            .cornerRadius(5.0)
    }
}

struct EngineMenuView: View {
    @State var isVisible = true
    @State var isScenePickerVisible = false
    @ObservedObject var engineGlobals: EngineGlobals
    var body: some View {
        if isVisible {
            ZStack {
                Color.black.opacity(0.15).background(.thinMaterial)
                
                VStack{
                    Button(action: {
                        if !engineGlobals.isGameRunning {
                            GameStateManager.startGame()
                            engineGlobals.isGameRunning = true
                        }
                        GameStateManager.resumeGame()
                        ContentView.globals.menuActive = false

                    }, label: {
                        HStack{
                            if engineGlobals.isGameRunning {
                                Image(systemName: "play")
                                Text("Resume")
                            } else {
                                Image(systemName: "play")
                                Text("Start")
                            }
                        }
                        
                    })
                    .padding(.vertical, 20)
                    .buttonStyle(GradientButtonStyle())
                    
                    if engineGlobals.isGameRunning {
                        Button(action: {
                            GameStateManager.stopGame()
                            engineGlobals.isGameRunning = false
                            GameStateManager.isGamePaused = true
                        }, label: {
                            HStack{
                                Image(systemName: "arrow.counterclockwise")
                                Text("Restart")
                            }
                            
                        })
                        .padding(.vertical, 20)
                        .buttonStyle(GradientButtonStyle())
                    }
                    
                    #if targetEnvironment(macCatalyst)
                        
                        FilePicker(types: [.data], allowMultiple: false, onPicked: { urls in
                            print(urls)
                            print("selected \(urls.count) files")
                            
                            let url = urls[0]
                            guard url.startAccessingSecurityScopedResource() else {
                                return
                            }
                            
                            if url.pathExtension == "gltf" {
                                GameStateManager.loadGLTF(url: url)
                            }
                        }) {
                            HStack{
                                Image(systemName: "filemenu.and.cursorarrow")
                                Text("Open from Disk")
                            }
                        }
                        .padding(.vertical, 20)
                        .buttonStyle(GradientButtonStyle())
                        
                    #endif
                    
                    Button(action: {
                        isScenePickerVisible = true
                    }, label: {
                        HStack{
                            Image(systemName: "questionmark.folder.fill")
                            Text("Pick Scene")
                        }
                    })
                    .padding(.vertical, 30)
                    .buttonStyle(GradientButtonStyle())
                    
                    #if targetEnvironment(macCatalyst)
                    Button(action: {
                        MetalView.renderer?.buildReloadablePipelines(width: Renderer.mainWidth, height: Renderer.mainHeight)
                    }, label: {
                        HStack{
                            Image(systemName: "questionmark.folder.fill")
                            Text("Reload Shaders")
                        }
                    })
                    .padding(.vertical, 30)
                    .buttonStyle(GradientButtonStyle())
                    #endif
                    
                }
            }.overlay() {
                if isScenePickerVisible {
                    AvailableScenesView()
                        .onPick {
                            isScenePickerVisible = false
                        }.onAppear(){
                            print("Hello from scene picker!")
                        }
                }
            }
        }
    }
    
    func visible(_ state: Bool) -> some View {
        isVisible = state
        return self
    }
}

struct EngineMenuView_Previews: PreviewProvider {
    static var previews: some View {
//        EngineMenuView(, parentView: self).visible(true)
        Text("Hello!")
    }
}
