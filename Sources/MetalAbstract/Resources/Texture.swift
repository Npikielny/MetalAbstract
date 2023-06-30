//
//  Texture.swift
//  
//
//  Created by Noah Pikielny on 6/29/23.
//

import MetalKit

class Texture {
    var name: String?
    var wrapped: Representation
    
    public init(name: String? = nil, texture: MTLTexture) {
        self.name = name
        self.wrapped = .raw(texture)
    }
    
    public init(name: String? = nil, path: String, options: TextureLoaderOptions? = nil) {
        self.name = name
        self.wrapped = .path(path, options: options)
    }
    
    public init(name: String? = nil, future: @escaping (GPU) async throws -> MTLTexture) {
        self.name = name
        self.wrapped = .future(future)
    }
    
    static func createMTLTexture(
        name: String?,
        gpu: MTLDevice,
        format: MTLPixelFormat,
        width: Int,
        height: Int,
        depth: Int = 1,
        storageMode: MTLStorageMode,
        usage: MTLTextureUsage
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        
        descriptor.textureType = depth > 1 ? .type3D : .type2D
        
        descriptor.depth = depth
        descriptor.width = width
        descriptor.height = height
        descriptor.storageMode = storageMode
        descriptor.usage = usage
        guard let texture = gpu.makeTexture(descriptor: descriptor) else {
            throw MetalAbstractError("Unabled to create texture \(name ?? "")")
        }
        return texture
    }
    
    public init(
        name: String? = nil,
        format: MTLPixelFormat,
        width: Int,
        height: Int,
        depth: Int = 1,
        storageMode: MTLStorageMode,
        usage: MTLTextureUsage
    ) {
        self.name = name
        self.wrapped = .future { gpu in
            try Self.createMTLTexture(
                name: name,
                gpu: gpu.device,
                format: format,
                width: width,
                height: height,
                storageMode: storageMode,
                usage: usage
            )
        }
    }
    
    public func emptyCopy(
        name: String? = nil,
        format: MTLPixelFormat? = nil,
        width: Int? = nil,
        height: Int? = nil,
        depth: Int? = nil,
        storageMode: MTLStorageMode? = nil,
        usage: MTLTextureUsage? = nil
    ) -> Texture {
        let texName = name ?? "Copy of \(self.name ?? "unnamed texture")"
        return Texture(name: texName) { gpu in
            let raw = try await self.encode(gpu)
            return try Self.createMTLTexture(
                name: texName,
                gpu: gpu.device,
                format: format ?? raw.pixelFormat,
                width: width ?? raw.width,
                height: height ?? raw.height,
                depth: depth ?? raw.depth,
                storageMode: storageMode ?? raw.storageMode,
                usage: usage ?? raw.usage
            )
        }
    }
    
    public func encode(_ gpu: GPU) async throws -> MTLTexture {
        switch wrapped {
            case let .raw(texture): return texture
            case let .path(path, options: options):
                let url: URL = {
                    if #available(iOS 16, macOS 13, *) {
                        return URL(filePath: path)
                    } else {
                        return URL(fileURLWithPath: path)
                    }
                }()
                
                let texture = try await gpu.loader.newTexture(
                    URL: url,
                    options: options
                )
                wrapped = .raw(texture)
                return texture
                
            case let .future(future):
                let texture = try await future(gpu)
                wrapped = .raw(texture)
                return texture
        }
    }
}

extension Texture {
    public typealias TextureLoaderOptions = [MTKTextureLoader.Option: Any]
    
    enum Representation {
        case raw(MTLTexture)
        case path(String, options: TextureLoaderOptions?)
        case future((GPU) async throws -> MTLTexture)
    }
}
