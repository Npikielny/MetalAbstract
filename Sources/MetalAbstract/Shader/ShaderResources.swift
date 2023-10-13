//
//  ShaderResources.swift
//
//
//  Created by Noah Pikielny on 10/13/23.
//

import Foundation

public protocol ShaderResources {
    var allTextures: [[Texture]] { get }
    var allBuffers: [[BufferManager]] { get }
}

extension ComputeShader: ShaderResources {
    public var allTextures: [[Texture]] { [textures] }
    public var allBuffers: [[BufferManager]] { [bufferManagers] }
}

extension RasterShader: ShaderResources {
    public var allTextures: [[Texture]] { [fragmentTextures, vertexTextures] }
    public var allBuffers: [[BufferManager]] { [fragmentBuffers, vertexBuffers] }
}
