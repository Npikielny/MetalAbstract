//
//  File.swift
//  
//
//  Created by Noah Pikielny on 6/30/23.
//

import Metal

open class BufferManager {
    weak var parent: (any ErasedBuffer)? = nil
    var wrapped: Representation? = nil
    var usage: Usage? = nil
    
    var transformations = [(BufferManager) -> Void]()
    
    init() {}
    
    var count: Int? { parent?.unsafeCount }
    
    func initialize(gpu: GPU) async throws {
        guard let parent else {
            throw MAError("Buffer without manager")
        }
        try await parent.initialize(gpu: gpu)
    }
    
    enum Representation {
        case bytes(any BytesArray)
        case buffer(MTLBuffer, offset: Int, usage: Usage)
        case pointer(any Pointer)
    }
    
    func cache(_ wrapped: Representation?) {
        self.wrapped = wrapped
        if let _ = wrapped {
            for transformation in transformations {
                transformation(self)
            }
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
                case let .buffer(buffer, offset, usage):
                    switch usage {
                        case .gpu: return nil
                        case .shared:
                            let bound = buffer.contents().bindMemory(to: T.GPUElement.self, capacity: count)
                            return T.decode(bound[index + offset])
                        #if os(macOS)
                        case .managed:
                            let bound = buffer.contents().bindMemory(to: T.GPUElement.self, capacity: count)
                            return T.decode(bound[index + offset])
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
                    (bytes as! BytesWrapper<T>).set(index, elt: newValue.encode())
                case let .pointer(pointer):
                    setPointer(index: index, value: newValue.encode(), pointer: pointer)
                case let .buffer(buffer, offset, usage):
                    switch usage {
                        case .gpu: fatalError("CPU attempting access to GPU-only buffer")
                        case .sparse: fatalError("Buffer encoded as MTLBuffer instead of bytes")
                        case .shared:
                            let stride = MemoryLayout<T.GPUElement>.stride
                            let start = stride * index
                            memcpy(buffer.contents() + start + offset, [newValue.encode()], stride)
                        #if os(macOS)
                        case .managed:
                            let stride = MemoryLayout<T.GPUElement>.stride
                            let start = stride * index
                            memcpy(buffer.contents() + start + offset, [newValue.encode()], stride)
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
    
    func encode(_ encoder: any CommandEncoder, index: Int) throws {
        guard let wrapped else {
            throw MAError("No buffer to encode")
        }
        
        switch wrapped {
            case let .buffer(buffer, offset, usage: _):
                encoder.setBuffer(buffer, offset: offset, index: index)
            case let .bytes(bytes):
                encoder.setBytes(bytes, index: index)
            case let .pointer(pointer):
                encoder.setBytes(pointer, index: index)
        }
    }
}

