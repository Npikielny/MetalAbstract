//
//  MTLLibrary.swift
//  
//
//  Created by Noah Pikielny on 6/30/23.
//

import Metal

extension MTLLibrary {
    func compile(name: String, constants: MTLFunctionConstantValues?) throws -> MTLFunction {
        let function: MTLFunction? = try {
            if let constants {
                return try makeFunction(name: name, constantValues: constants)
            }
            return makeFunction(name: name)
        }()
        guard let function else {
            throw MAError("Unable to make function \(name) on library \(functionNames)")
        }
        return function
    }
}
