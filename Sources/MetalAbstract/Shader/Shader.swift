//
//  Shader.swift
//  
//
//  Created by Noah Pikielny on 6/29/23.
//

import Metal

public protocol Shader: AnyObject {
    func setDrawingContext(drawable: MTLDrawable, descriptor: MTLRenderPassDescriptor)
    func initialize(gpu: GPU)
    func encode(commandBuffer: MTLCommandBuffer)
}

extension Shader {
    func setDrawingContext(drawable: MTLDrawable, descriptor: MTLRenderPassDescriptor) {}
}
