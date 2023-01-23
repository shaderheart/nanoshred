//
//  shred_iosApp.swift
//  shred_ios
//
//  Created by utku on 23/09/2022.
//

import SwiftUI

@main
struct shred_iosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().onAppear {
                print("Main view appeared!")
            }
            .onDisappear {
                print("Main view disappeared!")
            }
        }
    }
    
    init() {
        PhysxBindings.initializePhysicsWorld()
        EngineGlobals.input.bind()
    }
    
}
