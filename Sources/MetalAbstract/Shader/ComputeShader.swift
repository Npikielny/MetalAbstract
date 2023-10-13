//
//  ComputeShader.swift
//  
//
//  Created by Noah Pikielny on 6/29/23.
//

import Metal

public class ComputeShader {
    var function: Function
    public var bufferManagers: [BufferManager]
    public var textures: [Texture]
    var threadGroupSize: MTLSize
    var dispatchSize: ThreadGroupDispatch
    
    public convenience init(
        name: String,
        constants: MTLFunctionConstantValues? = nil,
        buffers: [any ErasedBuffer] = [],
        textures: [Texture] = [],
        threadGroupSize: MTLSize,
        dispatchSize: @escaping (MTLSize, ShaderResources) -> MTLSize
    ) {
        self.init(
            name: name,
            constants: constants,
            buffers: buffers,
            textures: textures,
            threadGroupSize: threadGroupSize,
            dispatchSize: ThreadGroupDispatchWrapper(wrapped: dispatchSize)
        )
    }
    
    public init(
        name: String,
        constants: MTLFunctionConstantValues? = nil,
        buffers: [any ErasedBuffer] = [],
        textures: [Texture] = [],
        threadGroupSize: MTLSize,
        dispatchSize: ThreadGroupDispatch
    ) {
        function = Function(name: name, constants: constants)
        bufferManagers = buffers.map(\.manager)
        self.textures = textures
        self.threadGroupSize = threadGroupSize
        self.dispatchSize = dispatchSize
    }
    private init(function: Function, bufferManagers: [BufferManager], textures: [Texture], threadGroupSize: MTLSize, dispatchSize: ThreadGroupDispatch) {
        self.function = function
        self.bufferManagers = bufferManagers
        self.textures = textures
        self.threadGroupSize = threadGroupSize
        self.dispatchSize = dispatchSize
    }
    
    public func initialize(gpu: GPU) async throws {
        for texture in textures {
            let _ = try await texture.encode(gpu)
        }
        
        for manager in bufferManagers {
            try await manager.initialize(gpu: gpu)
        }
    }
    
    public func copy() -> ComputeShader {
        ComputeShader(function: function, bufferManagers: bufferManagers, textures: textures, threadGroupSize: threadGroupSize, dispatchSize: dispatchSize)
    }
}

public protocol ThreadGroupDispatch {
    func groupsForSize(size: MTLSize, resources: ShaderResources) -> MTLSize
}

extension MTLSize: ThreadGroupDispatch {
    public func groupsForSize(size: MTLSize, resources: ShaderResources) -> MTLSize { self }
}

public struct ThreadGroupDispatchWrapper: ThreadGroupDispatch {
    public static func groupsForSize(size: MTLSize, dispatch: MTLSize) -> MTLSize {
        MTLSize(
            width: (dispatch.width + size.width - 1) / size.width,
            height: (dispatch.height + size.height - 1) / size.height,
            depth: (dispatch.depth + size.depth - 1) / size.depth
        )
    }
    
    public var wrapped: (MTLSize, ShaderResources) -> MTLSize
    
    init(wrapped: @escaping (MTLSize, ShaderResources) -> MTLSize) {
        self.wrapped = wrapped
    }
    
    init() {
        self.wrapped = { size, resources in
            let texture = try! resources.allTextures.first!.first!.forceUnwrap()
            return Self.groupsForSize(
                size: size,
                dispatch: MTLSize(width: texture.width, height: texture.height, depth: texture.depth)
            )
        }
    }
    
    public func groupsForSize(size: MTLSize, resources: ShaderResources) -> MTLSize {
        wrapped(size, resources)
    }
}

extension ComputeShader: CompiledShader {
    typealias Encoder = ComputeEncoder
    
    func makeEncoder(gpu: GPU, commandBuffer: MTLCommandBuffer) -> ComputeEncoder? {
        ComputeEncoder(commandBuffer: commandBuffer)
    }
    
    func setBuffers(_ encoder: ComputeEncoder) throws {
        for (index, buffer) in bufferManagers.enumerated() {
            try buffer.encode(encoder, index: index)
        }
    }
    
    func setTextures(_ encoder: ComputeEncoder) throws {
        encoder.setTextures(try textures.map { try $0.forceUnwrap() })
    }
    
    func dispatch(_ encoder: ComputeEncoder) {
        encoder.encoder.dispatchThreadgroups(
            dispatchSize.groupsForSize(size: threadGroupSize, resources: self),
            threadsPerThreadgroup: threadGroupSize
        )
    }
}

extension ComputeShader {
    final class Function: Pipeline {
        typealias Constructor = (String, MTLFunctionConstantValues?)
        typealias Pipeline = MTLComputePipelineState
        
        var wrapped: PipelineRepresentation<ComputeShader.Function>
        
        init(name: String, constants: MTLFunctionConstantValues? = nil) {
            wrapped = .constructor((name, constants))
        }
        
        static func construct(
            gpu: GPU,
            library: MTLLibrary,
            constructor: (String, MTLFunctionConstantValues?)
        ) throws -> Pipeline {
            let function = try library.compile(name: constructor.0, constants: constructor.1)
            return try gpu.device.makeComputePipelineState(function: function)
        }
    }
    
    class ComputeEncoder: CommandEncoder {
        typealias Pipeline = MTLComputePipelineState
        
        var encoder: MTLComputeCommandEncoder
        init?(commandBuffer: MTLCommandBuffer) {
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
            self.encoder = encoder
        }
        
        func setBuffer(_ buffer: MTLBuffer, offset: Int, index: Int) {
            encoder.setBuffer(buffer, offset: offset, index: index)
        }
        
        func setBytes<T: BytesArray>(_ bytes: T, index: Int) {
            encoder.setBytes(bytes.getPointer(), length: MemoryLayout<T.Element.GPUElement>.stride * bytes.count, index: index)
        }
        
        func setTextures(_ textures: [MTLTexture]) {
            encoder.setTextures(textures, range: 0..<textures.count)
        }
        
        func setPipelineState(_ pipeline: Pipeline) {
            encoder.setComputePipelineState(pipeline)
        }
    }
}

