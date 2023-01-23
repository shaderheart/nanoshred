//
//  InputSystem.swift
//  shred_ios
//
//  Created by utku on 22/01/2023.
//

import Foundation
import GameController

public class InputState {
    
    public class Mouse {
        var workingButtonState: [MouseButton : Bool] = [:]
        var buttonState: [MouseButton : Bool] = [:]
        var previousButtonState: [MouseButton : Bool] = [:]

        var workingAxisState: [MouseAxis : Float] = [:]
        var axisState: [MouseAxis : Float] = [:]
        var previousAxisState: [MouseAxis : Float] = [:]

        enum MouseAxis {
            case scrollX
            case scrollY
            case positionX
            case positionY
            case tumbleX
            case tumbleY
        }
        
        enum MouseButton {
            case left
            case right
            case middle
            case back
            case forward
            case X5
            case X6
            case X7
            case X8
            case X9
            case X10
        }
        
        func isDown(c: MouseButton) -> Bool{
            buttonState[c] ?? false
        }
        
        func isUp(c: MouseButton) -> Bool{
            buttonState[c] ?? true
        }
        
        func justPressed(c: MouseButton) -> Bool{
            (buttonState[c] ?? false) && (!(previousButtonState[c] ?? true))
        }
        
        func justReleased(c: MouseButton) -> Bool{
            (!(buttonState[c] ?? true)) && (previousButtonState[c] ?? false)
        }
        
        
    }
    
    public class Controller {
        var workingButtonState: [ControllerButton : Bool] = [:]
        var buttonState: [ControllerButton : Bool] = [:]
        var previousButtonState: [ControllerButton : Bool] = [:]

        var workingAxisState: [ControllerAxis : Float] = [:]
        var axisState: [ControllerAxis : Float] = [:]
        var previousAxisState: [ControllerAxis : Float] = [:]

        enum ControllerAxis {
            case leftThumbstickX
            case leftThumbstickY
            case rightThumbstickX
            case rightThumbstickY
            case leftTrigger
            case rightTrigger
        }
        
        enum ControllerButton {
            case a
            case b
            case x
            case y
            case up
            case down
            case left
            case right
            case start
            case menu
            case leftThumbstick
            case rightThumbstick
            case leftBumper
            case rightBumper
        }
        
        func isDown(c: ControllerButton) -> Bool{
            buttonState[c] ?? false
        }
        
        func isUp(c: ControllerButton) -> Bool{
            buttonState[c] ?? true
        }
        
        func justPressed(c: ControllerButton) -> Bool{
            (buttonState[c] ?? false) && (!(previousButtonState[c] ?? true))
        }
        
        func justReleased(c: ControllerButton) -> Bool{
            (!(buttonState[c] ?? true)) && (previousButtonState[c] ?? false)
        }
        
        func axisValue(c: ControllerAxis) -> Float {
            axisState[c] ?? 0.0
        }
        
        func axisDelta(c: ControllerAxis) -> Float {
            (previousAxisState[c] ?? 0.0) - (axisState[c] ?? 0.0)
        }
        
    }
    
    private let controller = Controller()
    private let mouse = Mouse()
    
    private var workingKeyState: [Character : Bool] = [:]
    private var keyState: [Character : Bool] = [:]
    private var previousKeyState: [Character : Bool] = [:]
    
    private var inputSemaphore: DispatchSemaphore = .init(value: 1)
    
    func consume(){
        inputSemaphore.wait()
        previousKeyState = keyState
        keyState = workingKeyState
        
        controller.previousAxisState = controller.axisState
        controller.axisState = controller.workingAxisState
        controller.previousButtonState = controller.buttonState
        controller.buttonState = controller.workingButtonState
        
        mouse.previousAxisState = mouse.axisState
        mouse.axisState = mouse.workingAxisState
        mouse.previousButtonState = mouse.buttonState
        mouse.buttonState = mouse.workingButtonState

        inputSemaphore.signal()
    }
    
    func isDown(c: Character) -> Bool{
        inputSemaphore.wait()
        let state =  keyState[c] ?? false
        inputSemaphore.signal()
        return state
    }
    
    func isUp(c: Character) -> Bool{
        inputSemaphore.wait()
        let state =  keyState[c] ?? false
        inputSemaphore.signal()
        return state
    }
    
    func justPressed(c: Character) -> Bool{
        inputSemaphore.wait()
        let state =  (keyState[c] ?? false) && (!(previousKeyState[c] ?? true))
        inputSemaphore.signal()
        return state
    }
    
    func justReleased(c: Character) -> Bool{
        inputSemaphore.wait()
        let state = (!(keyState[c] ?? true)) && (previousKeyState[c] ?? false)
        inputSemaphore.signal()
        return state
    }
    
    func justPressed(c: Controller.ControllerButton) -> Bool{
        inputSemaphore.wait()
        let state =  (controller.buttonState[c] ?? false) && (!(controller.previousButtonState[c] ?? true))
        inputSemaphore.signal()
        return state
    }
    
    func justPressed(m: Mouse.MouseButton) -> Bool{
        inputSemaphore.wait()
        let state =  (mouse.buttonState[m] ?? false) && (!(mouse.previousButtonState[m] ?? true))
        inputSemaphore.signal()
        return state
    }

    func axisValue(c: Controller.ControllerAxis) -> Float {
        inputSemaphore.wait()
        let state = controller.axisState[c] ?? 0.0
        inputSemaphore.signal()
        return state
    }
    
    func axisDelta(c: Controller.ControllerAxis) -> Float {
        inputSemaphore.wait()
        let state = (controller.previousAxisState[c] ?? 0.0) - (controller.axisState[c] ?? 0.0)
        inputSemaphore.signal()
        return state
    }
    
    func axisValue(c: Mouse.MouseAxis) -> Float {
        inputSemaphore.wait()
        let state = mouse.axisState[c] ?? 0.0
        inputSemaphore.signal()
        return state
    }
    
    func axisDelta(c: Mouse.MouseAxis) -> Float {
        inputSemaphore.wait()
        let state = (mouse.previousAxisState[c] ?? 0.0) - (mouse.axisState[c] ?? 0.0)
        inputSemaphore.signal()
        return state
    }
    
    func setState(c: Character, s: Bool) {
        inputSemaphore.wait()
        if workingKeyState[c] != nil {
            workingKeyState[c]! = s
        } else {
            workingKeyState[c] = s
        }
        inputSemaphore.signal()
    }
    
    func setThroughDelta(c: Mouse.MouseAxis, delta: Float) {
        inputSemaphore.wait()
        if mouse.workingAxisState[c] != nil {
            mouse.workingAxisState[c]! += delta
        } else {
            mouse.workingAxisState[c] = delta
        }
        inputSemaphore.signal()
    }
    
    func setThroughDelta(c: Controller.ControllerAxis, delta: Float) {
        inputSemaphore.wait()
        if controller.workingAxisState[c] != nil {
            controller.workingAxisState[c]! += delta
        } else {
            controller.workingAxisState[c] = delta
        }
        inputSemaphore.signal()
    }
    
    func setButton(c: Mouse.MouseButton, value: Bool) {
        inputSemaphore.wait()
        if mouse.workingButtonState[c] != nil {
            mouse.workingButtonState[c]! = value
        } else {
            mouse.workingButtonState[c] = value
        }
        inputSemaphore.signal()
    }

    
    
    var keyboardRef: GCKeyboard?
    var mouseRef: GCMouse?
    var controllerRef: GCController?
    
    var captureInputs = true
    
    var inputQueue: DispatchQueue = .init(label: "com.shaderheart.nanoshred.Input", attributes: .concurrent)
//    var inputQueue: DispatchQueue = .main
    
    func bind() {
        NotificationCenter.default.addObserver(forName: .init("NSWindowDidBecomeMainNotification"), object: nil, queue: nil) { notification in
            print("This window became focused: \(notification.object)")
            self.captureInputs = true
        }
        
        NotificationCenter.default.addObserver(forName: .init("NSWindowDidResignMainNotification"), object: nil, queue: nil) { notification in
            print("This window lost focus: \(notification.object)")
            self.captureInputs = false
        }
        
        weak var weakInput = self

        NotificationCenter.default.addObserver(forName: .GCMouseDidBecomeCurrent, object: nil, queue: nil) { notification in
            self.mouseRef = notification.object as? GCMouse
            self.mouseRef?.handlerQueue = self.inputQueue
            self.mouseRef?.mouseInput?.mouseMovedHandler = { (mouse, dx, dy) in
                // TODO: mouse move events
            }
            
            self.mouseRef?.mouseInput?.leftButton.pressedChangedHandler = { (button, pressure, pressed) in
                guard let input = weakInput else { return }
                input.setButton(c: .left, value: pressed)
            }
            
            self.mouseRef?.mouseInput?.rightButton?.pressedChangedHandler = { (button, pressure, pressed) in
                guard let input = weakInput else { return }
                input.setButton(c: .right, value: pressed)
            }
            
            self.mouseRef?.mouseInput?.scroll.valueChangedHandler = { (controller, dx, dy) in
                guard let input = weakInput, self.captureInputs else { return }
                input.setThroughDelta(c: .scrollX, delta: dx)
                input.setThroughDelta(c: .scrollY, delta: dy)
            }
            
        }
        
#if !targetEnvironment(macCatalyst) && os(iOS)
        let vcConfig = GCVirtualController.Configuration.init()
        vcConfig.elements = [GCInputLeftThumbstick,
                             GCInputRightThumbstick,
                             GCInputButtonA,
                             GCInputButtonB]
        
        EngineGlobals.virtualController = GameController.GCVirtualController(configuration: vcConfig)
        
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: nil) { notification in
            
            //            EngineGlobals.virtualController!.controller?.handlerQueue = self.controllerQueue
            
            let extended = EngineGlobals.virtualController!.controller?.extendedGamepad
            extended?.buttonA.preferredSystemGestureState = .alwaysReceive
            extended?.buttonA.valueChangedHandler = { (button, pressure, pressed) in
                EngineGlobals.input.controller.workingButtonState[.a] = pressed
            }
            
            extended?.buttonB.preferredSystemGestureState = .alwaysReceive
            extended?.buttonB.valueChangedHandler = { (button, pressure, pressed) in
                EngineGlobals.input.controller.workingButtonState[.b] = pressed
            }
            
            extended?.leftThumbstick.preferredSystemGestureState = .alwaysReceive
            extended?.leftThumbstick.valueChangedHandler = { (button, xAxis, yAxis) in
                EngineGlobals.input.controller.workingAxisState[.leftThumbstickX] = xAxis
                EngineGlobals.input.controller.workingAxisState[.leftThumbstickY] = yAxis
            }
            
            extended?.rightThumbstick.preferredSystemGestureState = .alwaysReceive
            extended?.rightThumbstick.valueChangedHandler = { (button, xAxis, yAxis) in
                EngineGlobals.input.controller.workingAxisState[.rightThumbstickX] = xAxis
                EngineGlobals.input.controller.workingAxisState[.rightThumbstickY] = yAxis
            }
        }
        EngineGlobals.virtualController!.connect()
#endif
        
    }
    
}

