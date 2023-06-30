//
//  GPUPass.swift
//  
//
//  Created by Noah Pikielny on 6/27/23.
//

import MetalKit

public class GPUPass {
    public typealias Pass = [Shader]
    public typealias PassBuilder = () throws -> Pass
    var pass: Pass
    
    public init(pass: Pass) { self.pass = pass }
    public init(@GPUPassBuilder pass: PassBuilder) rethrows {
        self.pass = try pass()
    }
}

extension GPUPass {
    @resultBuilder
    public struct GPUPassBuilder {
        public static func buildBlock(_ components: Shader...) -> [Shader] {
            components
        }
    }
}
