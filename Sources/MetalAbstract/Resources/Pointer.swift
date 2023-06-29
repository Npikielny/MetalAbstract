//
//  Pointer.swift
//  
//
//  Created by Noah Pikielny on 6/26/23.
//

import Foundation

protocol Pointer {
    associatedtype Element
    
    subscript(_ index: Int) -> Element { get set }
    
    func `set`(_ index: Int, elt: Element)
}

public struct GKPointer<Element>: Pointer {
    let count: Int
    let pointer: UnsafeMutablePointer<Element>
    
    subscript(_ index: Int) -> Element {
        get { pointer[index] }
        set { pointer[index] = newValue }
    }
    
    func set(_ index: Int, elt: Element) {
        pointer[index] = elt
    }
}
