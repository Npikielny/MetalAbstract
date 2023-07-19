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
    public var completion: (GPU) async throws -> Void
    
    public init(pass: Pass, completion: @escaping (GPU) async throws -> Void) {
        self.pass = pass
        self.completion = completion
    }
    public init(@GPUPassBuilder pass: PassBuilder, completion: @escaping (GPU) async throws -> Void = { _ in }) rethrows {
        self.pass = try pass()
        self.completion = completion
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
