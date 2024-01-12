//
//  ShaderResources.swift
//
//
//  Created by Noah Pikielny on 10/13/23.
//

import Foundation

public protocol ShaderResources {
    var allTextures: [[Texture]] { get }
    var allBuffers: [[any ErasedBuffer]] { get }
}

extension ComputeShader: ShaderResources {
    public var allTextures: [[Texture]] { [textures] }
    public var allBuffers: [[any ErasedBuffer]] { [buffers] }
}

extension RasterShader: ShaderResources {
    public var allTextures: [[Texture]] { [fragmentTextures, vertexTextures] }
    public var allBuffers: [[any ErasedBuffer]] { [fragmentBuffers, vertexBuffers] }
}
