//
//  Pointer.swift
//  
//
//  Created by Noah Pikielny on 6/26/23.
//

import Foundation

protocol Pointer: BytesArray {
    subscript(_ index: Int) -> Element { get set }
    
    func set(_ index: Int, elt: Element)
}

public struct MAPointer<Element: GPUEncodable>: Pointer {
    let count: Int
    let pointer: UnsafeMutablePointer<Element>
    
    subscript(_ index: Int) -> Element {
        get { pointer[index] }
        set { pointer[index] = newValue }
    }
    
    func set(_ index: Int, elt: Element) {
        pointer[index] = elt
    }
    
    func getPointer() -> UnsafeRawPointer {
        UnsafeRawPointer(pointer)
    }
}

protocol ErasedBytesArray {
    func attemptSet(_ index: Int, elt: Any)
}

protocol BytesArray: ErasedBytesArray {
    associatedtype Element: Bytes
    
    var count: Int { get }
    
    subscript(_ index: Int) -> Element.GPUElement { get set }
    func set(_ index: Int, elt: Element.GPUElement)
    
    func getPointer() -> UnsafeRawPointer
}

extension BytesArray {
    func attemptSet(_ index: Int, elt: Any) {
        self.set(index, elt: elt as! Element.GPUElement)
    }
}

class BytesWrapper<Element: Bytes>: BytesArray {
    var array: [Element]
    
    var count: Int { array.count }
    
    init(array: [Element]) {
        self.array = array
    }
    
    subscript(index: Int) -> Element.GPUElement {
        get { array[index].encode() }
        set { array[index] = Element.decode(newValue) }
    }
    
    func set(_ index: Int, elt: Element.GPUElement) {
        self[index] = elt
    }
    
    func convert(_ ptr: UnsafeRawPointer) -> UnsafeRawPointer {
        ptr
    }
    
    func getPointer() -> UnsafeRawPointer {
        convert(array)
    }
}
