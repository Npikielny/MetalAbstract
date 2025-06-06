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
    var unsafeCount: Int? { get }
}

open class Buffer<T: Bytes>: ErasedBuffer {
    var name: String?
    public typealias Element = T.GPUElement
    var wrapped: Representation
    public var count: Int
    public var unsafeCount: Int? { count }
    
    public let manager: BufferManager
    private var usage: Usage

    enum Representation {
        case allocation(_ count: Int)
        case future((GPU) async throws -> (MTLBuffer, count: Int))
        case delegated
    }
    
    convenience init(name: String? = nil, _ wrapped: T..., usage: Usage) {
        self.init(name: name, wrapped as [T], usage: usage)
    }
    
    /// Used a placeholder for future assignment – pair with `reset`
    public init(name: String? = nil) {
        self.name = name
        self.usage = .sparse
        self.count = 0
        wrapped = .delegated
        manager = BufferManager(name: name, usage: usage)
        manager.parent = self
    }
    
    public init(name: String? = nil, _ wrapped: [T], usage: Usage) {
        self.name = name
        self.usage = usage
        count = wrapped.count
        manager = BufferManager(name: name, usage: usage)
        switch usage {
        case .sparse:
            self.wrapped = .delegated
            self.manager.cache(.bytes(BytesWrapper(array: wrapped)))
        case .shared:
            self.wrapped = .delegated
            self.manager.cache(.bytes(BytesWrapper(array: wrapped)))
#if os(macOS)
        case .managed:
            self.wrapped = .delegated
            self.manager.cache(.bytes(BytesWrapper(array: wrapped)))
#endif
        case .gpu:
            fatalError("Unable to create GPU-only buffer with initial values, try other initializer")
        }
        manager.parent = self
    }
    
    public init(name: String? = nil, count: Int, type: T.Type, usage: Usage = .gpu) {
        assert(usage != .sparse)
        self.name = name
        self.usage = usage
        wrapped = .allocation(count)
        self.count = count
        manager = BufferManager(name: name, usage: usage)
        manager.parent = self
    }
    
    public func initialize(gpu: GPU) async throws {
        switch usage {
        case .sparse: return
        case .gpu:
            if let _ = manager.wrapped { return }
            guard case let .allocation(count) = wrapped else {
                throw MAError("Trying to make private buffer with data or no allocation size")
            }
            guard let buffer = gpu.device.makeBuffer(length: MemoryLayout<T>.stride * count, options: .storageModePrivate) else {
                throw MAError("Unable to make buffer")
            }
            manager.cache(.buffer(buffer, offset: 0, usage: .gpu))
        case .shared:
            switch wrapped {
            case .delegated:
                if case .buffer(_, offset: _, usage: _) = manager.wrapped { return }
                guard let wrapped = manager.wrapped else {
                    throw MAError("Delegated shared buffer, but unable to find \(name ?? "unnamed buffer")")
                }
                guard case let .bytes(wrapped) = wrapped else {
                    throw MAError("Unable to make shared buffer from private allocation: \(name ?? "unnamed buffer")")
                }
                guard let buffer = gpu.device.makeBuffer(
                    bytes: wrapped.getPointer(),
                    length: MemoryLayout<T>.stride * count,
                    options: .storageModeShared
                ) else {
                    throw MAError("Unable to make buffer: \(name ?? "unnamed buffer")")
                }
                manager.cache(.buffer(buffer, offset: 0, usage: .shared))
            case let .allocation(allocation):
                count = allocation
                guard let buffer = gpu.device.makeBuffer(
                    length: MemoryLayout<T>.stride * count,
                    options: .storageModeShared
                ) else {
                    throw MAError("Unable to make buffer")
                }
                manager.cache(.buffer(buffer, offset: 0, usage: .shared))
                wrapped = .delegated
            case let .future(future):
                let (buffer, count) = try await future(gpu)
                self.count = count
                manager.cache(.buffer(buffer, offset: 0, usage: .shared))
                wrapped = .delegated
            }
#if os(macOS)
        case .managed:
            switch wrapped {
            case .delegated:
                if case .buffer(_, offset: _, usage: _) = manager.wrapped { return }
                guard let wrapped = manager.wrapped else {
                    throw MAError("Delegated managed buffer, but unable to find \(name ?? "unnamed buffer")")
                }
                guard case let .bytes(wrapped) = wrapped else {
                    throw MAError("Unable to make shared buffer from private allocation: \(name ?? "unnamed buffer")")
                }
                guard let buffer = gpu.device.makeBuffer(
                    bytes: wrapped.getPointer(),
                    length: MemoryLayout<T>.stride * count,
                    options: .storageModeManaged
                ) else {
                    throw MAError("Unable to make buffer: \(name ?? "unnamed buffer")")
                }
                manager.cache(.buffer(buffer, offset: 0, usage: .managed))
            case let .allocation(allocation):
                count = allocation
                guard let buffer = gpu.device.makeBuffer(
                    length: MemoryLayout<T>.stride * count,
                    options: .storageModeManaged
                ) else {
                    throw MAError("Unable to make buffer")
                }
                manager.cache(.buffer(buffer, offset: 0, usage: .managed))
                wrapped = .delegated
            case let .future(future):
                let (buffer, count) = try await future(gpu)
                self.count = count
                manager.cache(.buffer(buffer, offset: 0, usage: .managed))
                wrapped = .delegated
            }
#endif
        }
        self.wrapped = .delegated
    }
    
    public subscript(_ index: Int) -> T? {
        get {
            switch wrapped {
            case .allocation(_), .future(_):
                fatalError("GPU Resources are inaccessible to the CPU")
            case .delegated:
                switch usage {
                case .gpu:
                    fatalError("GPU Resources are inaccessible to the CPU")
                case .shared, .sparse:
                    return manager[index, T.self, count]
#if os(macOS)
                case .managed:
                    return manager[index, T.self, count]
#endif
                }
            }
        }
        set {
            guard let newValue else { fatalError("Cannot have null value in buffer") }
            switch wrapped {
            case .allocation(_), .future(_):
                fatalError("GPU Resources are inaccessible to the CPU")
            case .delegated:
                switch usage {
                case .gpu:
                    fatalError("GPU Resources are inaccessible to the CPU")
                case .shared, .sparse:
                    manager[index, T.self, count] = newValue
#if os(macOS)
                case .managed:
                    manager[index, T.self, count] = newValue
#endif
                }
            }
        }
    }
    
    /// Replaces original buffer with a new buffer encoding `wrapped`
    public func reset(_ wrapped: [T], usage: Usage) {
        switch usage {
        case .sparse, .shared:
            self.wrapped = .delegated
            self.manager.cache(.bytes(BytesWrapper(array: wrapped)))
#if os(macOS)
        case .managed:
            self.wrapped = .delegated
            self.manager.cache(.bytes(BytesWrapper(array: wrapped)))
#endif
        case .gpu:
            fatalError("Unable to create GPU-only buffer with initial values, try other initializer")
        }
        self.usage = usage
        count = wrapped.count
        manager.parent = self
    }
    
    /// Replaces original buffer with an empty buffer
    public func reset(count: Int, usage: Usage = .gpu) {
        assert(usage != .sparse)
        self.usage = usage
        wrapped = .allocation(count)
        self.count = count
        manager.parent = self
        self.manager.cache(nil)
    }
    
    public func forceUnwrap() throws -> MTLBuffer {
        guard case let .buffer(buffer, _, _) = manager.wrapped! else {
            throw MAError("Force unwrapped buffer that did not exist :(")
        }
        return buffer
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

open class VoidBuffer: ErasedBuffer {
    public typealias Transform = (UnsafeMutableRawPointer) -> (start: Int, end: Int)
    public let manager: BufferManager
    
    public typealias Element = Void
    
    let name: String?
    var wrapped: Representation
    
    let usage: Usage
    
    var transforms = [Transform]()
    public var unsafeCount: Int? { nil }
    
    public init(name: String? = nil, future: @escaping (_ gpu: GPU) -> (MTLBuffer, _: Int)?, usage: Usage) {
        assert(usage != .gpu && usage != .sparse)
        self.name = name
        wrapped = .future(future)
        self.usage = usage
        manager = BufferManager(name: name, usage: usage)
        manager.parent = self
    }
    
    public init(name: String? = nil, buffer: MTLBuffer, count: Int, usage: Usage) {
        // TODO: in theory GPU would work here...
        assert(usage != .gpu && usage != .sparse)
        self.name = name
        wrapped = .buffer(buffer, count)
        self.usage = usage
        manager = BufferManager(name: name, usage: usage)
        manager.parent = self
    }
    
    public init(name: String? = nil, usage: Usage) {
        assert(usage != .gpu && usage != .sparse)
        self.name = name
        wrapped = .unassigned
        self.usage = usage
        manager = BufferManager(name: name, usage: usage)
        manager.parent = self
    }
    
    public func initialize(gpu: GPU) async throws {
        switch wrapped {
        case .unassigned:
            throw MAError("Cannot initialize unnassigned buffer")
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
    
    public func reset(buffer: MTLBuffer, count: Int) {
        wrapped = .buffer(buffer, count)
    }
    
    public func reset(future: @escaping (_ gpu: GPU) -> (MTLBuffer, Int)?) {
        wrapped = .future(future)
    }
    
    public var buffer: MTLBuffer? {
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
        /// Requires manual reset before usage – essentially implicit unwrap
        case unassigned
    }
}

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

//extension SIMD2: Bytes where Scalar: GPUEncodable {
//    typealias GPUElement = self
//}
extension SIMD2: Bytes where Scalar: GPUEncodable {
    public typealias GPUElement = Self
}

extension SIMD2: GPUEncodable where Scalar: GPUEncodable {}

extension SIMD3: Bytes where Scalar: GPUEncodable {
    public typealias GPUElement = Self
}
extension SIMD3: GPUEncodable where Scalar: GPUEncodable {}

extension SIMD4: Bytes where Scalar: GPUEncodable {
    public typealias GPUElement = Self
}
extension SIMD4: GPUEncodable where Scalar: GPUEncodable {}

public typealias Vec2<T: SIMDScalar> = SIMD2<T>
public typealias Vec3<T: SIMDScalar> = SIMD3<T>
public typealias Vec4<T: SIMDScalar> = SIMD4<T>
