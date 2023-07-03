//
//  File.swift
//  
//
//  Created by Noah Pikielny on 6/26/23.
//

import MetalKit

public protocol ErasedBuffer: AnyObject {
    associatedtype Element
    
    func initialize(gpu: GPU) async throws
    
    var manager: BufferManager { get }
}

public class Buffer<T: Bytes>: ErasedBuffer {
    var name: String?
    public typealias Element = T.GPUElement
    var wrapped: Representation
    public let count: Int
    
    public let manager = BufferManager()
    private let usage: Usage

    convenience init(name: String? = nil, _ wrapped: T..., usage: Usage) {
        self.init(name: name, wrapped as [T], usage: usage)
    }
    
    enum Representation {
        case allocation(_ count: Int)
        case wrapped(any BytesArray)
        case freed
    }
    
    public init(name: String? = nil, _ wrapped: [T], usage: Usage) {
        self.name = name
        switch usage {
            case .sparse:
                self.wrapped = .wrapped(BytesWrapper(array: wrapped))
                self.manager.cache(.bytes(BytesWrapper(array: wrapped)))
            case .shared:
                self.wrapped = .wrapped(BytesWrapper(array: wrapped))
            #if os(macOS)
            case .managed:
                self.wrapped = .wrapped(BytesWrapper(array: wrapped))
            #endif
            case .gpu:
                fatalError("Unable to create GPU-only buffer with initial values, try other initializer")
        }
        self.usage = usage
        count = wrapped.count
    }
    
    public init(count: Int, type: T.Type) {
        usage = .gpu
        wrapped = .allocation(count)
        self.count = count
    }
    
    public func initialize(gpu: GPU) async throws {
        if let _ = manager.wrapped { return }
        switch usage {
            case .sparse:
                return
            case .gpu:
                guard case let .allocation(count) = wrapped else {
                    throw MAError("Trying to make private buffer with data or no allocation size")
                }
                guard let buffer = gpu.device.makeBuffer(length: MemoryLayout<T>.stride * count, options: .storageModePrivate) else {
                    throw MAError("Unable to make buffer")
                }
                self.manager.cache(.buffer(buffer, offset: 0, usage: .gpu))
            case .shared:
                guard case let .wrapped(wrapped) = wrapped else {
                    throw MAError("Unable to make shared buffer from private allocation")
                }
                guard let buffer = gpu.device.makeBuffer(
                    bytes: wrapped.getPointer(),
                    length: MemoryLayout<T>.stride * count,
                    options: .storageModeShared
                ) else {
                    throw MAError("Unable to make buffer")
                }
                self.manager.cache(.buffer(buffer, offset: 0, usage: .shared))
            #if os(macOS)
            case .managed:
                guard case let .wrapped(wrapped) = wrapped else {
                    throw MAError("Unable to make shared buffer from private allocation")
                }
                guard let manager = gpu.device.makeBuffer(
                    bytes: wrapped.getPointer(),
                    length: MemoryLayout<T>.stride * count,
                    options: .storageModeManaged
                ) else {
                    throw MAError("Unable to make buffer")
                }
                self.manager.cache(.buffer(manager, offset: 0, usage: .managed))
            #endif
        }
        self.wrapped = .freed
    }
    
    public subscript(_ index: Int) -> T? {
        get {
            if usage == .sparse {
                switch wrapped {
                    case let .wrapped(wrapped):
                        return T.decode(wrapped[index] as! T.GPUElement)
                    default:
                        print("Unable to find bytes")
                        return nil
                }
            } else {
                return manager[index, T.self, count]
            }
        }
        set {
            guard let newValue else { fatalError("Cannot have null value in buffer") }
            switch wrapped {
                case let .wrapped(wrapped):
                    wrapped.attemptSet(index, elt: newValue.encode())
                case .freed, .allocation(_):
                    fatalError("Attempting to edit GPU buffer")
                    
            }
            manager[index, T.self, count] = newValue
        }
    }
}

public enum Usage {
    /// GPU-use only
    case gpu
    /// Both CPU and GPU share this data
    case shared
    #if os(macOS)
    /// GPU data that the CPU can modify
    case managed
    #endif
    /// Small pieces of data that are stored on and can only be changed by the CPU
    case sparse
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
