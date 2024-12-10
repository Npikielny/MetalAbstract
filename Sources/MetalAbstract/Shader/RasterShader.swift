//
//  RasterShader.swift
//  
//
//  Created by Noah Pikielny on 6/29/23.
//

import MetalKit

open class RasterShader: CompiledShader {
    var function: Function
    
    public var vertexTextures: [Texture]
    public var vertexBuffers: [any ErasedBuffer]
    
    public var fragmentTextures:[Texture]
    public var fragmentBuffers: [any ErasedBuffer]
    
    var buffers: [any ErasedBuffer] { vertexBuffers + fragmentBuffers }
    var textures: [Texture] { vertexTextures + fragmentTextures }
    
    public var startingVertex: Int
    public var vertexCount: Int
    
    public let primitive: MTLPrimitiveType
    
    var descriptor: RenderPassDescriptor
    var defaultDescriptor: MTLRenderPassDescriptor?
    var drawable: MTLDrawable? = nil
    
    public convenience init(
        vertexShader: String,
        vertexConstants: MTLFunctionConstantValues? = nil,
        fragmentShader: String,
        fragmentConstants: MTLFunctionConstantValues? = nil,
        vertexTextures: [Texture] = [],
        vertexBuffers: [any ErasedBuffer] = [],
        fragmentTextures: [Texture] = [],
        fragmentBuffers: [any ErasedBuffer] = [],
        startingVertex: Int = 0,
        vertexCount: Int = 6,
        primitive: MTLPrimitiveType = .triangle,
        passDescriptor: RenderPassDescriptor,
        texture: Texture
    ) {
        self.init(
            vertexShader: vertexShader,
            vertexConstants: vertexConstants,
            fragmentShader: fragmentShader,
            fragmentConstants: fragmentConstants,
            vertexTextures: vertexTextures,
            vertexBuffers: vertexBuffers,
            fragmentTextures: fragmentTextures,
            fragmentBuffers: fragmentBuffers,
            startingVertex: startingVertex,
            vertexCount: vertexCount,
            primitive: primitive,
            passDescriptor: passDescriptor,
            targetFormat: texture
        )
    }
    
    public convenience init(
        vertexShader: String,
        vertexConstants: MTLFunctionConstantValues? = nil,
        fragmentShader: String,
        fragmentConstants: MTLFunctionConstantValues? = nil,
        vertexTextures: [Texture] = [],
        vertexBuffers: [any ErasedBuffer] = [],
        fragmentTextures: [Texture] = [],
        fragmentBuffers: [any ErasedBuffer] = [],
        startingVertex: Int = 0,
        vertexCount: Int = 6,
        primitive: MTLPrimitiveType = .triangle,
        passDescriptor: RenderPassDescriptor,
        format: MTLPixelFormat
    ) {
        self.init(
            vertexShader: vertexShader,
            vertexConstants: vertexConstants,
            fragmentShader: fragmentShader,
            fragmentConstants: fragmentConstants,
            vertexTextures: vertexTextures,
            vertexBuffers: vertexBuffers,
            fragmentTextures: fragmentTextures,
            fragmentBuffers: fragmentBuffers,
            startingVertex: startingVertex,
            vertexCount: vertexCount,
            primitive: primitive,
            passDescriptor: passDescriptor,
            targetFormat: format
        )
    }
    
    public init(
        function: Function,
        vertexTextures: [Texture] = [],
        vertexBuffers: [any ErasedBuffer] = [],
        fragmentTextures: [Texture] = [],
        fragmentBuffers: [any ErasedBuffer] = [],
        startingVertex: Int = 0,
        vertexCount: Int = 6,
        primitive: MTLPrimitiveType = .triangle,
        passDescriptor: RenderPassDescriptor
    ) {
        self.function = function
        self.vertexTextures = vertexTextures
        self.vertexBuffers = vertexBuffers
        self.fragmentTextures = fragmentTextures
        self.fragmentBuffers = fragmentBuffers
        self.startingVertex = startingVertex
        self.vertexCount = vertexCount
        self.descriptor = passDescriptor
        self.primitive = primitive
    }
    
    init(
        vertexShader: String,
        vertexConstants: MTLFunctionConstantValues? = nil,
        fragmentShader: String,
        fragmentConstants: MTLFunctionConstantValues? = nil,
        vertexTextures: [Texture] = [],
        vertexBuffers: [any ErasedBuffer] = [],
        fragmentTextures: [Texture] = [],
        fragmentBuffers: [any ErasedBuffer] = [],
        startingVertex: Int = 0,
        vertexCount: Int = 6,
        primitive: MTLPrimitiveType = .triangle,
        passDescriptor: RenderPassDescriptor,
        targetFormat: RenderTargetFormat
    ) {
        self.function = Function(
            vertexShader: vertexShader,
            vertexConstants: vertexConstants,
            fragmentShader: fragmentShader,
            fragmentConstants: fragmentConstants,
            format: targetFormat
        )
        self.vertexTextures = vertexTextures
        self.vertexBuffers = vertexBuffers
        self.fragmentTextures = fragmentTextures
        self.fragmentBuffers = fragmentBuffers
        self.startingVertex = startingVertex
        self.vertexCount = vertexCount
        self.descriptor = passDescriptor
        self.primitive = primitive
    }
    
    func makeEncoder(gpu: GPU, commandBuffer: MTLCommandBuffer) async throws -> Encoder? {
        switch descriptor {
            case let .drawable(loadAction):
                let descriptor = defaultDescriptor!
                if let loadAction {
                    descriptor.colorAttachments[0].loadAction = loadAction
                }
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return nil }
                return Encoder(encoder: encoder)
            case let .custom(descriptor):
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return nil }
                return Encoder(encoder: encoder)
            case let .future(future):
                let descriptor = try await future(gpu)
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return nil }
                return Encoder(encoder: encoder)
                
        }
    }
    
    public func setDrawingContext(drawable: MTLDrawable, descriptor: MTLRenderPassDescriptor) {
        defaultDescriptor = descriptor
        self.drawable = drawable
    }
    
    func setBuffers(_ encoder: Encoder) throws {
        encoder.encoding = .vertex
        for (index, buffer) in vertexBuffers.map(\.manager).enumerated() {
            try buffer.encode(encoder, index: index)
        }
        
        encoder.encoding = .fragment
        for (index, buffer) in fragmentBuffers.map(\.manager).enumerated() {
            try buffer.encode(encoder, index: index)
        }
    }
    
    func setTextures(_ encoder: Encoder) throws {
        if !vertexTextures.isEmpty {
            encoder.encoder.setVertexTextures(try vertexTextures.map { try $0.forceUnwrap() }, range: 0..<vertexTextures.count)
        }
        if !fragmentTextures.isEmpty {
            encoder.encoder.setFragmentTextures(try fragmentTextures.map { try $0.forceUnwrap() }, range: 0..<fragmentTextures.count)
        }
    }
    
    func dispatch(_ encoder: Encoder) {
        encoder.encoder.drawPrimitives(type: primitive, vertexStart: startingVertex, vertexCount: vertexCount)
        // FIXME: Presenting
    }
}

// MARK: Render Pass Descriptor
public enum RenderPassDescriptor {
    case drawable(_ loadAction: MTLLoadAction? = nil)
    case custom(MTLRenderPassDescriptor)
    case future((GPU) async throws -> MTLRenderPassDescriptor)
    
    public static func future(texture: Texture, loadAction: MTLLoadAction = .dontCare, storeAction: MTLStoreAction = .store) -> Self {
        .future { gpu in
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = try await texture.encode(gpu)
            descriptor.colorAttachments[0].loadAction = loadAction
            descriptor.colorAttachments[0].storeAction = storeAction
            return descriptor
        }
    }
}

public protocol RenderTargetFormat {
    func format(gpu: GPU) async throws -> MTLPixelFormat
}

extension MTLPixelFormat: RenderTargetFormat {
    public func format(gpu: GPU) async throws -> MTLPixelFormat { self }
}

extension Texture: RenderTargetFormat {
    public func format(gpu: GPU) async throws -> MTLPixelFormat {
        let unwrapped = try await encode(gpu)
        return unwrapped.pixelFormat
    }
}

extension RasterShader {
    public final class Function: Pipeline {
        var name: String
        
        typealias Constructor = (
            vertName: String,
            vertConstants: MTLFunctionConstantValues?,
            fragName: String,
            fragConstants: MTLFunctionConstantValues?,
            format: RenderTargetFormat
        )
        typealias Pipeline = MTLRenderPipelineState
        
        var wrapped: PipelineRepresentation<RasterShader.Function>
        
        public init(
            vertexShader: String,
            vertexConstants: MTLFunctionConstantValues? = nil,
            fragmentShader: String,
            fragmentConstants: MTLFunctionConstantValues? = nil,
            format: RenderTargetFormat
        ) {
            self.name = "\(vertexShader), \(fragmentShader)"
            self.wrapped = .constructor((vertexShader, vertexConstants, fragmentShader, fragmentConstants, format))
        }
        
        static func construct(
            gpu: GPU,
            library: MTLLibrary,
            constructor: Constructor
        ) async throws -> Pipeline {
            let vert = try library.compile(name: constructor.vertName, constants: constructor.vertConstants)
            let frag = try library.compile(name: constructor.fragName, constants: constructor.fragConstants)
            
            let descriptor = MTLRenderPipelineDescriptor()
            
            descriptor.vertexFunction = vert
            descriptor.fragmentFunction = frag
            
            descriptor.colorAttachments[0].pixelFormat = try await constructor.format.format(gpu: gpu)
            descriptor.label = "\(constructor.vertName) \(constructor.fragName)"
            
            return try await gpu.device.makeRenderPipelineState(descriptor: descriptor)
        }
        
        public func compile(gpu: GPU, library: MTLLibrary) async throws {
            switch wrapped {
                case .constructor(let constructor):
                    wrapped = try await .pipeline(Self.construct(gpu: gpu, library: library, constructor: constructor))
                case .pipeline(_):
                    return
            }
        }
    }
    
    class Encoder: CommandEncoder {
        typealias Pipeline = MTLRenderPipelineState
        
        var encoder: MTLRenderCommandEncoder
        var encoding: EncodingFunction
        
        enum EncodingFunction {
            case vertex
            case fragment
        }
        
        init?(encoder: MTLRenderCommandEncoder) {
            self.encoder = encoder
            self.encoding = .vertex
        }
        
        func setBuffer(_ buffer: MTLBuffer, offset: Int, index: Int) {
            switch encoding {
                case .fragment: encoder.setFragmentBuffer(buffer, offset: offset, index: index)
                case .vertex: encoder.setVertexBuffer(buffer, offset: offset, index: index)
            }
        }
        
        func setBytes<T: BytesArray>(_ bytes: T, index: Int) {
            switch encoding {
                case .fragment:
                    encoder.setFragmentBytes(bytes.getPointer(), length: MemoryLayout<T.Element.GPUElement>.stride * bytes.count, index: index)
                case .vertex:
                    encoder.setVertexBytes(bytes.getPointer(), length: MemoryLayout<T.Element.GPUElement>.stride * bytes.count, index: index)
            }
        }
        
        func setPipelineState(_ pipeline: Pipeline) {
            encoder.setRenderPipelineState(pipeline)
        }
    }
}
