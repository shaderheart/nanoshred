//
//  GLBFile.swift
//  swiftui-test
//
//  Created by utku on 17/11/2022.
//

import Foundation

enum GLBChunkType: UInt32 {
    case JSON = 0x4E4F534A
    case BIN = 0x004E4942
    case GARBAGE = 0
}

struct GLBChunk {
    var chunkLength: UInt32 = 0
    var chunkType: GLBChunkType = .JSON
    var chunkData: UnsafeMutableRawPointer? = nil
}

struct GLBFile {
    var chunks: [GLBChunk] = []
    
    var jsonData: Data? = nil
    var binaryData: Data? = nil
    
    static func load(_ file: URL) -> GLBFile? {
        var newFile = GLBFile()
        guard let stream = InputStream(url: file) else {
            return nil
        }
        stream.open()
        
        var headerStore: [UInt8] = .init(repeating: 0, count: 12)
        stream.read(&headerStore, maxLength: 12)
        
        var fileSize: UInt32 = 0
        var filePtr: UInt32 = 0
        headerStore.withUnsafeMutableBytes {
            bytes in
            fileSize = (bytes.bindMemory(to: UInt32.self))[2]
        }
        filePtr += 12
        
        while filePtr < fileSize {
            var chunkHeaderStore: [UInt8] = .init(repeating: 0, count: 8)
            stream.read(&chunkHeaderStore, maxLength: 8)
            var newChunk = GLBChunk()
            chunkHeaderStore.withUnsafeMutableBytes {
                bytes in
                newChunk.chunkLength = (bytes.bindMemory(to: UInt32.self))[0]
                newChunk.chunkType = GLBChunkType.init(rawValue: (bytes.bindMemory(to: UInt32.self))[1]) ?? .GARBAGE
                newChunk.chunkData = malloc(Int(newChunk.chunkLength))
                stream.read(newChunk.chunkData!, maxLength: Int(newChunk.chunkLength))
                filePtr += 8 + newChunk.chunkLength
            }
            newFile.chunks.append(newChunk)
        }
        
        stream.close()
        
        if newFile.chunks.count > 0 && newFile.chunks[0].chunkType == .JSON {
            newFile.jsonData = Data.init(bytesNoCopy: newFile.chunks[0].chunkData!,
                                  count: Int(newFile.chunks[0].chunkLength),
                                  deallocator: Data.Deallocator.free)
        }
        if newFile.chunks.count > 1 && newFile.chunks[1].chunkType == .BIN {
            newFile.binaryData = Data.init(bytesNoCopy: newFile.chunks[1].chunkData!,
                                  count: Int(newFile.chunks[1].chunkLength),
                                  deallocator: Data.Deallocator.free)
        }
        
        return newFile
    }
    
}
