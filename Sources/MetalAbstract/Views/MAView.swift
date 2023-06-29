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
    var view: DrawableView

    var timer: Publishers.Autoconnect<Timer.TimerPublisher>?
    
    var update: (MTLDrawable?, MTLRenderPassDescriptor?) async throws -> Void
    
    public init(gpu: GPU,
        frame: CGRect = CGRect(
            x: 0,
            y: 0,
            width: 512,
            height: 512
        ),
        format: MTLPixelFormat = .bgra8Unorm,
        updateProcedure: UpdateProcedure = .manual,
        draw: @escaping (MTLDrawable?, MTLRenderPassDescriptor?) async throws -> Void
    ) {
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
        draw: @escaping (MTLDrawable?, MTLRenderPassDescriptor?) async throws -> Void
    ) {
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
    
    func draw() {
        let drawable = view.currentDrawable
        let descriptor = view.currentRenderPassDescriptor
        Task {
            try await update(drawable, descriptor)
        }
    }
}
