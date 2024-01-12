//
//  Shader.swift
//  
//
//  Created by Noah Pikielny on 6/29/23.
//

import Metal

public protocol Shader: AnyObject {
    func setDrawingContext(drawable: MTLDrawable, descriptor: MTLRenderPassDescriptor)
    func initialize(gpu: GPU, library: MTLLibrary) async throws
    func encode(gpu: GPU, commandBuffer: MTLCommandBuffer) async throws
}

extension Shader {
    public func setDrawingContext(drawable: MTLDrawable, descriptor: MTLRenderPassDescriptor) {}
}

enum PipelineRepresentation<T: Pipeline> {
    case constructor(T.Constructor)
    case pipeline(T.Pipeline)
}

protocol Pipeline: AnyObject {
    associatedtype Pipeline
    associatedtype Constructor
    
    var wrapped: PipelineRepresentation<Self> { get set }
    
    static func construct(gpu: GPU, library: MTLLibrary, constructor: Constructor) async throws -> Pipeline

}

extension Pipeline {
    func compile(gpu: GPU, library: MTLLibrary) async throws -> Self.Pipeline {
        switch wrapped {
            case let .constructor(constructor):
                let pipeline = try await Self.construct(gpu: gpu, library: library, constructor: constructor)
                self.wrapped = .pipeline(pipeline)
                return pipeline
            case let .pipeline(pipeline):
                return pipeline
        }
    }
}

protocol CompiledShader: Shader {
    associatedtype Function: Pipeline
    associatedtype Encoder: CommandEncoder where Encoder.Pipeline == Function.Pipeline
    
    var function: Function { get set }
    
    var buffers: [any ErasedBuffer] { get }
    var textures: [Texture] { get }
    
    func makeEncoder(gpu: GPU, commandBuffer: MTLCommandBuffer) async throws -> Encoder?
    
    func setBuffers(_ encoder: Encoder) throws
    func setTextures(_ encoder: Encoder) throws
    func dispatch(_ encoder: Encoder)
}

extension CompiledShader {
    public func initialize(gpu: GPU, library: MTLLibrary) async throws {
        for buffer in buffers {
            try await buffer.manager.initialize(gpu: gpu)
        }
        
        for texture in textures {
            let _ = try await texture.encode(gpu)
        }
        let _ = try await function.compile(gpu: gpu, library: library)
    }
    
    public func encode(gpu: GPU, commandBuffer: MTLCommandBuffer) async throws {
        guard case let .pipeline(pipeline) = function.wrapped else {
            throw MAError("Unable to compile functions")
        }
        guard let encoder = try await makeEncoder(gpu: gpu, commandBuffer: commandBuffer) else {
            throw MAError("Unable to make command encoder")
        }
        
        do {
            try setBuffers(encoder)
            try setTextures(encoder)
        } catch {
            print(error.localizedDescription)
            throw error
        }
        
        encoder.setPipelineState(pipeline)
        dispatch(encoder)
        
        encoder.encoder.endEncoding()
    }
}

protocol CommandEncoder {
    var encoder: Encoder { get }
    func setBuffer(_ buffer: MTLBuffer, offset: Int, index: Int)
    func setBytes(_ bytes: some BytesArray, index: Int)
    func setPipelineState(_ pipeline: Pipeline)

    associatedtype Pipeline
    associatedtype Encoder: MTLCommandEncoder
}
