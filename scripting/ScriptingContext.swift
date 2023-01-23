//
//  ScriptingContext.swift
//  swiftui-test
//
//  Created by utku on 16/12/2022.
//

import Foundation

@objc
public class ScriptContext: NSObject {
    
    @objc
    public func getScriptsAsStrings() -> NSDictionary {
        let strMap: [String: String] = [:]
        return strMap as NSDictionary
    }
    
    @objc
    public func getNameOfScript(index: Int) -> String {
        if index < AllScripts.allScripts.count {
            var iterator = AllScripts.allScripts.makeIterator()
            for _ in 0..<index {
                let _ = iterator.next()
            }
            let name = iterator.next()?.key ?? ""
            return name
        }
        
        return ""
    }
    
    @objc
    public func getVariablesOfScript(index: Int) -> String {
        if index < AllScripts.allScripts.count {
            var iterator = AllScripts.allScripts.makeIterator()
            for _ in 0..<index {
                let _ = iterator.next()
            }
            let variables = ""
            return variables
        }
        
        return ""
    }
}



public protocol MusicEvents {
    var targetMidiFile: String {get set}
    var targetTrack: String {get set}
    var getFromAllChannels: Bool {get set}
    var attached: Bool {get set}
    func onBeat(beatIndex: Int, time: Double)
    func onNoteOn(noteNumber: Int, time: Double)
    func onNoteOff(noteNumber: Int, time: Double)
    func onCC(ccIndex: Int, ccValue: Float)
    func onPitchWheel(value: Float)
    func gotAttached()
}
extension MusicEvents {
    func onBeat(beatIndex: Int, time: Double) {}
    func onNoteOn(noteNumber: Int, time: Double) {}
    func onNoteOff(noteNumber: Int, time: Double) {}
    func onCC(ccIndex: Int, ccValue: Float) {}
    func onPitchWheel(value: Float) {}
    mutating func gotAttached() {
        attached = true
    }
}

public protocol PhysicsEvents {
    func onHit(other: EPhysicsComponent)
    func onOverlapBegin(other: EPhysicsComponent)
    func onOverlapEnd(other: EPhysicsComponent)
}
extension PhysicsEvents {
    func onHit(other: EPhysicsComponent){}
    func onOverlapBegin(other: EPhysicsComponent){}
    func onOverlapEnd(other: EPhysicsComponent){}
}

public protocol InputEvents {
    func onKeyDown()
    func onKeyUp()
    
    func onAxis()
    func onTap()
    func onDrag()
}

extension InputEvents {
    func onKeyDown() {}
    func onKeyUp() {}
    func onAxis() {}
    func onTap() {}
    func onDrag() {}
}

public protocol ShredScript: Codable {
    var attachedEntity: SHEntity? {get set}
    
    init()
    init(jsonData: [String: Any])
    
    func tick(deltaTime: Double, registry: SHRegistry)
    func clone() -> Self
}

/// default implementations for ShredScript.
extension ShredScript {
    public init() {self.init()}
    public init(jsonData: [String : Any]) {self.init()}
    
    public func clone() -> Self {
        return Self()
    }
    
    public func tick(deltaTime: Double, registry: SHRegistry){
        
    }
}
