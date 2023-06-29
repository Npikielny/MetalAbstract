//
//  GPUPass.swift
//  
//
//  Created by Noah Pikielny on 6/27/23.
//

import MetalKit

public class GPUPass {
    public typealias Pass = [MAShader]
    public typealias PassBuilder = () throws -> Pass
    var pass: Pass
    
    init(pass: Pass) { self.pass = pass }
    init(@GPUPassBuilder pass: PassBuilder) rethrows {
        self.pass = try pass()
    }
}

extension GPUPass {
    @resultBuilder
    public struct GPUPassBuilder {
        public static func buildBlock(_ components: MAShader...) -> [MAShader] {
            components
        }
    }
}

public protocol MAShader {
    func setDrawingContext(drawable: MTLDrawable, descriptor: MTLRenderPassDescriptor)
    func initialize(gpu: GPU)
    func encode(commandBuffer: MTLCommandBuffer)
}

extension MAShader {
    func setDrawingContext(drawable: MTLDrawable, descriptor: MTLRenderPassDescriptor) {}
}
