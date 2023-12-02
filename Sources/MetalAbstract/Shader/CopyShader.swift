//
//  CopyShader.swift
//  
//
//  Created by Noah Pikielny on 6/29/23.
//

import MetalKit

open class CopyShader: Shader {
    var operation: Representation
    enum Representation {
        case textures(
            source: Texture,
            sourceOrigin: MTLOrigin,
            sink: Texture,
            sinkOrigin: MTLOrigin,
            size: MTLSize
        )
        case directTextures(from: Texture, to: Texture)
        case synchronize(Texture)
    }
    
    public init(source: Texture, sourceOrigin: MTLOrigin, sink: Texture, sinkOrigin: MTLOrigin, size: MTLSize) {
        operation = .textures(source: source, sourceOrigin: sourceOrigin, sink: sink, sinkOrigin: sinkOrigin, size: size)
    }
    
    public init(from: Texture, to: Texture) {
        operation = .directTextures(from: from, to: to)
    }
    
    public init(synchronizing: Texture) {
        operation = .synchronize(synchronizing)
    }
    
    public func initialize(gpu: GPU, library: MTLLibrary) async throws {
        switch operation {
            case let .textures(source, _, sink, _, _),
                let .directTextures(from: source, to: sink):
                let _ = try await source.encode(gpu)
                let _ = try await sink.encode(gpu)
            case .synchronize(let tex):
                let _ = try await tex.encode(gpu)
        }
    }
    
    public func encode(gpu: GPU, commandBuffer: MTLCommandBuffer) async throws {
        let encoder = commandBuffer.makeBlitCommandEncoder()
        switch operation {
            case let .textures(source, sourceOrigin, sink, sinkOrigin, size):
                try await encoder?.copy(
                    from: source.encode(gpu),
                    sourceSlice: 0,
                    sourceLevel: 0,
                    sourceOrigin: sourceOrigin,
                    sourceSize: size,
                    to: sink.encode(gpu),
                    destinationSlice: 0,
                    destinationLevel: 0,
                    destinationOrigin: sinkOrigin
                )
            case let .directTextures(from, to):
                try await encoder?.copy(from: from.encode(gpu), to: to.encode(gpu))
            case let .synchronize(tex):
                let unwrapped = try await tex.encode(gpu)
                encoder?.synchronize(resource: unwrapped)
        }
        encoder?.endEncoding()
    }
}
