//
//  MathFunctions.swift
//  swiftui-test
//
//  Created by utku on 22/09/2022.
//

import Foundation
import simd



// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix4x4_scale(_ scaleUniform: Float) -> matrix_float4x4 {
    return matrix4x4_scale(scaleUniform, scaleUniform, scaleUniform)
}

func matrix4x4_scale(_ scaleX: Float, _ scaleY: Float, _ scaleZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(scaleX, 0, 0, 0),
                                         vector_float4(0, scaleY, 0, 0),
                                         vector_float4(0, 0, scaleZ, 0),
                                         vector_float4(0, 0, 0, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}

func matrix_decomposeSimple(matrix: simd_float4x4) -> (simd_float3, simd_quatf, simd_float3){
    // decompose matrix into individual elements
    var matrixCopy = matrix
    let m4 = matrixCopy.columns.3
    let translation = simd_float3(m4.x, m4.y, m4.z)
    let scale = simd_float3(x: simd_length(matrixCopy.columns.0),
                             y: simd_length(matrixCopy.columns.1),
                             z: simd_length(matrixCopy.columns.2))
    
    matrixCopy = simd_float4x4(matrixCopy.columns.0 / scale.x,
                               matrixCopy.columns.1 / scale.y,
                               matrixCopy.columns.2 / scale.z,
                               simd_float4(x: 0, y: 0, z: 0, w: 1))
    let rotation = simd_quatf(matrixCopy)
    return (translation, rotation, scale)
}

protocol sSIMD { init() }
extension SIMD4: sSIMD {}
extension SIMD3: sSIMD {}
extension SIMD2: sSIMD {}
extension simd_float4x4: sSIMD {}
extension simd_float3x3: sSIMD {}
extension Float: sSIMD {}
extension Int: sSIMD {}
extension UInt: sSIMD {}
extension Int32: sSIMD {}
extension UInt32: sSIMD {}


extension simd_quatf: SIMD {
    public typealias MaskStorage = SIMD4<Scalar.SIMDMaskScalar>
    
    public subscript(index: Int) -> Float {
        get {
            vector[index]
        }
        set(newValue) {
            vector[index] = newValue
        }
    }
        
    public var scalarCount: Int {
        4
    }
        
    public typealias ArrayLiteralElement = Float
    public typealias Scalar = Float
}

extension Float: SIMD {
    public typealias MaskStorage = SIMD2<Scalar.SIMDMaskScalar>
    
    public subscript(index: Int) -> Float {
        get {
            self
        }
        set(newValue) {
            self = newValue
        }
    }
        
    public var scalarCount: Int {
        1
    }
        
    public typealias ArrayLiteralElement = Float
    public typealias Scalar = Float
}


func lookAt(position: simd_float3, target: simd_float3, up_vec: simd_float3) -> matrix_float4x4{
    let dir_vec = simd_fast_normalize(position - target)
    
    let c_x = simd_fast_normalize(simd_cross(up_vec, dir_vec))
    let c_y = simd_fast_normalize(simd_cross(dir_vec, c_x))
    
    
    
    return matrix_float4x4.init(columns:(vector_float4(c_x, simd_dot(-c_x, position)),
                                         vector_float4(c_y, simd_dot(-c_y, position)),
                                         vector_float4(dir_vec, simd_dot(-dir_vec, position)),
                                         vector_float4(0,0,0,1)
                                        )).transpose
}


func quatfToEuler (quatf: simd_quatf) -> simd_float3 {
    let quat = quatf.vector
    let x = atan2(2 * (quat.w * quat.x + quat.y * quat.z), 1 - 2 * (quat.x * quat.x + quat.y * quat.y))
    let y = asin(2 * (quat.w * quat.y - quat.z * quat.x))
    let z = atan2(2 * (quat.w * quat.z + quat.x * quat.y), 1 - 2 * (quat.y * quat.y + quat.z * quat.z))
    return simd_float3(x, y, z)
}


func convertMatrix(input: matrix_float4x4) -> matrix_float3x3 {
    let output = matrix_float3x3(simd_float3(input.columns.0.x, input.columns.0.y, input.columns.0.z),
                                 simd_float3(input.columns.1.x, input.columns.1.y, input.columns.1.z),
                                 simd_float3(input.columns.2.x, input.columns.2.y, input.columns.2.z))
    return output
}

func convertMatrix(input: simd_float3x3) -> simd_float4x4 {
    let output = simd_float4x4(simd_float4(input.columns.0.x, input.columns.0.y, input.columns.0.z, 0.0),
                                 simd_float4(input.columns.1.x, input.columns.1.y, input.columns.1.z, 0.0),
                                 simd_float4(input.columns.2.x, input.columns.2.y, input.columns.2.z, 0.0),
                                 simd_float4(0.0, 0.0, 0.0, 1.0))
    return output
}
 
func extractRotation(input: simd_float3x3) -> simd_float3x3 {
    var output: simd_float3x3 = (input)
    
    let lX = simd_length(output.columns.0)
    let lY = simd_length(output.columns.1)
    let lZ = simd_length(output.columns.2)
    
    output.columns.0 /= lX
    output.columns.1 /= lY
    output.columns.2 /= lZ

    return output
    
}
