//
//  GPU.swift
//  
//
//  Created by Noah Pikielny on 6/27/23.
//

import MetalKit

public class GPU {
    static var debug = false
    public var name: String { device.name }
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    public var library: MTLLibrary?
    
    public lazy var loader = MTKTextureLoader(device: device)
    
    public init?(device: MTLDevice, library: MTLLibrary? = nil) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        self.library = library ?? device.makeDefaultLibrary()
    }
    
    public func execute(
        library: MTLLibrary? = nil,
        drawable: MTLDrawable? = nil,
        descriptor: MTLRenderPassDescriptor? = nil,
        pass: GPUPass
    ) async throws {
        for shader in pass.pass { 
            try await shader.initialize(gpu: self, library: library ?? self.library ?? device.makeDefaultLibrary()!)
            if let drawable, let descriptor {
                shader.setDrawingContext(drawable: drawable, descriptor: descriptor)
            }
        }
#if DEBUG
        if (drawable == nil || descriptor == nil) {
            
        }
#endif
        let commandBuffer = queue.makeCommandBuffer()!
        for shader in pass.pass {
            try await shader.encode(gpu: self, commandBuffer: commandBuffer)
        }
        if let drawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    public func execute(
        library: MTLLibrary? = nil,
        drawable: MTLDrawable? = nil,
        descriptor: MTLRenderPassDescriptor? = nil,
        @GPUPass.GPUPassBuilder pass: GPUPass.PassBuilder
    ) async rethrows {
        try await execute(library: library, drawable: drawable, descriptor: descriptor, pass: pass)
    }
    
    public static var `default`: GPU {
        GPU(device: MTLCreateSystemDefaultDevice()!)!
    }
}
