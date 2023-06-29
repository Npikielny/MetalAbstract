//
//  File.swift
//  
//
//  Created by Noah Pikielny on 6/26/23.
//

import MetalKit

func >>= <A, B>(lhs: A?, rhs: (A) -> B) -> B? {
    if let lhs { return rhs(lhs) }
    return nil
}

class BufferManager {
    var wrapped: Representation? = nil
    var usage: Usage? = nil
    
    var transformations = [(BufferManager) -> Void]()
    
    init() {}
    
    enum Representation {
        case bytes([any Bytes])
        case buffer(MTLBuffer, usage: Usage)
        case pointer(any Pointer)
    }
    
    func cache(_ wrapped: Representation) {
        self.wrapped = wrapped
        for transformation in transformations {
            transformation(self)
        }
    }
    
    subscript<T: Bytes>(_ index: Int, type: T.Type, count: Int) -> T? {
        get {
            guard let rep = wrapped else { return nil }
            switch rep {
                case let .bytes(bytes):
                    return T.decode(bytes[index] as! T.GPUElement)
                case let .pointer(pointer):
                    return T.decode(pointer[index] as! T.GPUElement)
                case let .buffer(buffer, usage):
                    switch usage {
                        case .gpu: return nil
                        case .shared:
                            let bound = buffer.contents().bindMemory(to: T.GPUElement.self, capacity: count)
                            return T.decode(bound[index])
                        #if os(macOS)
                        case .managed:
                            let bound = buffer.contents().bindMemory(to: T.GPUElement.self, capacity: count)
                            return T.decode(bound[index])
                        #endif
                        case .sparse: fatalError("Erroneously passed to buffer manager")
                    }
            }
        }
        set {
            guard let newValue = newValue else { fatalError("Cannot have null values in buffer") }
            guard let rep = wrapped else {
                transformations.append { $0[index, T.self, count] = newValue }
                return
            }
            switch rep {
                case let .bytes(bytes):
                    self.wrapped = .bytes((bytes[..<index] as! ArraySlice<T.GPUElement>) + [newValue.encode()] + (bytes[(index + 1)...] as! ArraySlice<T.GPUElement>))
                case let .pointer(pointer):
                    setPointer(index: index, value: newValue.encode(), pointer: pointer)
                case let .buffer(buffer, usage):
                    switch usage {
                        case .gpu: fatalError("CPU attempting access to GPU-only buffer")
                        case .sparse: fatalError("Buffer encoded as MTLBuffer instead of bytes")
                        case .shared:
                            let stride = MemoryLayout<T.GPUElement>.stride
                            let start = stride * index
                            memcpy(buffer.contents() + start, [newValue.encode()], stride)
                        #if os(macOS)
                        case .managed:
                            let stride = MemoryLayout<T.GPUElement>.stride
                            let start = stride * index
                            memcpy(buffer.contents() + start, [newValue.encode()], stride)
                            if usage == .managed {
                                buffer.didModifyRange(start..<(start + stride))
                            }
                        #endif
                    }
            }
        }
    }
    
    func setPointer<P: Pointer>(index: Int, value: Any, pointer: P) {
        pointer.set(index, elt: value as! P.Element)
    }
}

protocol BufferEncoder: AnyObject {
    associatedtype Element
}

public class Buffer<T: Bytes> {
    typealias Element = T.GPUElement
    var wrapped: [T]?
    let count: Int
    
    private let buffer: BufferManager
    private let usage: Usage
    
//    subscript(_ index: Int) {
//
//    }
//
    convenience init(_ wrapped: T..., usage: Usage) {
        self.init(wrapped as [T], usage: usage)
    }
    
    init(_ wrapped: [T], usage: Usage) {
        buffer = BufferManager()
        switch usage {
            case .sparse:
                self.wrapped = wrapped
                self.buffer.cache(.bytes(wrapped))
            case .shared:
                self.wrapped = wrapped
            #if os(macOS)
            case .managed:
                self.wrapped = wrapped
            #endif
            case .gpu:
                fatalError("Unable to create GPU-only buffer with initial values, try other initializer")
        }
        self.usage = usage
        self.wrapped = wrapped
        count = wrapped.count
    }
    
    subscript(_ index: Int) -> T? {
        get {
            if usage == .sparse, let wrapped {
                return wrapped[index]
            } else {
                return buffer[index, T.self, count]
            }
        }
        set {
            guard let newValue else { fatalError("Cannot have null value in buffer") }
            if let wrapped {
                self.wrapped = wrapped[..<index] + [newValue] + wrapped[(index + 1)...]
            }
            buffer[index, T.self, count] = newValue
        }
    }
    
    public enum MemoryUsage {
        case optimized
    }
}

public enum Usage {
    /// For GPU editing only
    case gpu
    /// Both CPU and GPU can edit this data
    case shared
    #if os(macOS)
    /// Both CPU and GPU can edit this data, but the GPU must be notified of data changes
    case managed
    #endif
    /// Small pieces of data that cannot be changed by the GPU, but can be altered by the CPU
    case sparse
}

extension Buffer: BufferEncoder {
    
}
//protocol BufferEncoder {
//    /// Element that will be encoded into a GPU buffer
//    associatedtype Element
//}

public protocol Bytes {
    associatedtype GPUElement: GPUEncodable
    func encode() -> GPUElement
    static func decode(_ elt: GPUElement) -> Self
}

extension Bytes {
    public static func decode(_ elt: GPUElement) -> Self where GPUElement == Self { elt }
}

public protocol GPUEncodable: Bytes where GPUElement == Self {}
extension GPUEncodable {
    public func encode() -> GPUElement { self }
}

extension Int: Bytes {
    public func encode() -> Int32 { Int32(self) }
    public static func decode(_ elt: Int32) -> Int { Int(elt) }
}
extension Int32: GPUEncodable {}
extension UInt32: GPUEncodable {}
extension Int8: GPUEncodable {}
extension UInt8: GPUEncodable {}
extension Float: GPUEncodable {}

extension SIMD2: Bytes where Scalar: GPUEncodable {}
extension SIMD2: GPUEncodable where Scalar: GPUEncodable {}

extension SIMD3: Bytes where Scalar: GPUEncodable {}
extension SIMD3: GPUEncodable where Scalar: GPUEncodable {}

extension SIMD4: Bytes where Scalar: GPUEncodable {}
extension SIMD4: GPUEncodable where Scalar: GPUEncodable {}

public typealias Vec2<T: SIMDScalar> = SIMD2<T>
public typealias Vec3<T: SIMDScalar> = SIMD3<T>
public typealias Vec4<T: SIMDScalar> = SIMD4<T>
