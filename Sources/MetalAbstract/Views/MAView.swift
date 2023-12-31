//
//  MAView.swift
//  
//
//  Created by Noah Pikielny on 6/27/23.
//

import SwiftUI
import MetalKit
import Combine

public struct MAView: View {
    let view: DrawableView
    let timer: Publishers.Autoconnect<Timer.TimerPublisher>?
    let update: (GPU, MTLDrawable?, MTLRenderPassDescriptor?) async throws -> Void
    let gpu: GPU
    
    @State var drawing = false
    
    public init(
        gpu: GPU,
        frame: CGRect = CGRect(
            x: 0,
            y: 0,
            width: 512,
            height: 512
        ),
        format: MTLPixelFormat = .bgra8Unorm,
        updateProcedure: UpdateProcedure = .manual,
        draw: @escaping (_ gpu: GPU, _ drawable: MTLDrawable?, _ descriptor: MTLRenderPassDescriptor?) async throws -> Void
    ) {
        self.gpu = gpu
        view = DrawableView(view: MTKView(frame: frame, device: gpu.device))
        view.view.colorPixelFormat = format
        switch updateProcedure {
            case .manual:
                timer = nil
            case let .rate(interval):
                timer = Timer.publish(every: interval, on: .main, in: .default).autoconnect()
        }
        update = draw
    }
    
    public init(
        gpu: GPU,
        view: MTKView,
        updateProcedure: UpdateProcedure = .manual,
        draw: @escaping (_ gpu: GPU, _ drawable: MTLDrawable?, _ descriptor: MTLRenderPassDescriptor?) async throws -> Void
    ) {
        self.gpu = gpu
        self.view = DrawableView(view: view)
        self.view.view.device = gpu.device
        switch updateProcedure {
            case .manual:
                timer = nil
            case let .rate(interval):
                timer = Timer.publish(every: interval, on: .main, in: .default).autoconnect()
        }
        update = draw
    }
    
    public enum UpdateProcedure {
        case rate(_ interval: Double)
        case manual
    }
    
    public var body: some View {
        if let timer {
            view
                .onReceive(timer) { _ in
                    draw()
                }
        } else {
            view
        }
    }
    
    public func draw() {
        if drawing { return }
        let drawable = view.currentDrawable
        let descriptor = view.currentRenderPassDescriptor
        drawing = true
        Task {
            try await update(gpu, drawable, descriptor)
            self.drawing = false
        }
    }
}
