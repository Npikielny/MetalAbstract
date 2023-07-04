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

public class VoidBuffer: ErasedBuffer {
    public typealias Transform = (UnsafeMutableRawPointer) -> (start: Int, end: Int)
    public let manager = BufferManager()
    
    public typealias Element = Void
    
    let name: String?
    var wrapped: Representation
    
    let usage: Usage
    
    var transforms = [Transform]()
    
    public init(name: String? = nil, future: @escaping (GPU) -> (MTLBuffer, _: Int)?, usage: Usage) {
        assert(usage != .gpu && usage != .sparse)
        self.name = name
        wrapped = .future(future)
        self.usage = usage
        manager.parent = self
    }
    
    public func initialize(gpu: GPU) async throws {
        switch wrapped {
            case .buffer(_, _): return
            case let .future(future):
                guard let (buffer, count) = try await future(gpu) else {
                    throw MAError("Unabled to create buffer \(name ?? "")")
                }
                let ptr = buffer.contents()
                let bounds = transforms.map { $0(ptr) }
                #if os(macOS)
                if usage == .managed, let min = bounds.map(\.start).min(), let max = bounds.map(\.end).max() {
                    buffer.didModifyRange(min..<max)
                }
                #endif
                wrapped = .buffer(buffer, count)
                manager.cache(.buffer(buffer, offset: 0, usage: usage))
        }
    }
    
    var buffer: MTLBuffer? {
        guard case let .some(.buffer(buffer, _, _)) = manager.wrapped else { return nil }
        return buffer
    }
    
    public var pointer: UnsafeMutableRawPointer? {
        guard case let .some(.buffer(buffer, _, _)) = manager.wrapped else { return nil }
        return buffer.contents()
    }
    
    public func edit(_ transform: @escaping Transform) {
        if let buffer {
            let (start, end) = transform(buffer.contents())
            #if os(macOS)
            if usage == .managed {
                buffer.didModifyRange(start..<end)
            }
            #endif
        } else {
            transforms.append(transform)
        }
    }
    
    enum Representation {
        case future((GPU) async throws -> (MTLBuffer, Int)?)
        case buffer(MTLBuffer, _ count: Int)
    }
}

public class Buffer<T: Bytes>: ErasedBuffer {
    var name: String?
    public typealias Element = T.GPUElement
    var wrapped: Representation
    public var count: Int
    
    public let manager = BufferManager()
    private let usage: Usage

    convenience init(name: String? = nil, _ wrapped: T..., usage: Usage) {
        self.init(name: name, wrapped as [T], usage: usage)
    }
    
    enum Representation {
        case allocation(_ count: Int)
        case future((GPU) async throws -> (MTLBuffer, count: Int))
        case wrapped(any BytesArray)
        case freed
    }
    
    public init(name: String? = nil, _ wrapped: [T], usage: Usage) {
        manager.parent = self
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
        manager.parent = self
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
                case .freed, .allocation(_), .future(_):
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
