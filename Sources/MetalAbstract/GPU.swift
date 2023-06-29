//
//  GPU.swift
//  
//
//  Created by Noah Pikielny on 6/27/23.
//

import MetalKit

public actor GPU {
    static var debug = false
    public var name: String { device.name }
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    public var library: MTLLibrary?
    
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
    ) async {
        pass.pass.forEach { shader in
            shader.initialize(gpu: self)
            if let drawable, let descriptor {
                shader.setDrawingContext(drawable: drawable, descriptor: descriptor)
            }
        }
#if DEBUG
        if (drawable == nil || descriptor == nil) {
            
        }
#endif
        let commandBuffer = queue.makeCommandBuffer()!
        pass.pass.forEach { $0.encode(commandBuffer: commandBuffer) }
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
    
    static var `default`: GPU {
        GPU(device: MTLCreateSystemDefaultDevice()!)!
    }
}
