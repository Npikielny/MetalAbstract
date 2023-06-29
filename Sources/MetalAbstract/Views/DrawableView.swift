//
//  DrawableView.swift
//  
//
//  Created by Noah Pikielny on 6/27/23.
//

import MetalKit
import SwiftUI

#if os(macOS)
public struct DrawableView: NSViewRepresentable {
    public var view: MTKView
    
    public func makeNSView(context: Context) -> MTKView {
        view
    }
    
    public func updateNSView(_ nsView: MTKView, context: Context) {
    }
    
    public init(view: MTKView) {
        self.view = view
    }
}
#elseif os(iOS)
import UIKit

public struct DrawableView: UIViewRepresentable {
    public var view: MTKView
    
    public func makeUIView(context: Context) -> MTKView {
        view
    }
    
    public func updateUIView(_ nsView: MTKView, context: Context) {
    }
    
    public init(view: MTKView) {
        self.view = view
    }
}
#endif

extension DrawableView {
    var currentDrawable: MTLDrawable? { view.currentDrawable }
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { view.currentRenderPassDescriptor }
}
