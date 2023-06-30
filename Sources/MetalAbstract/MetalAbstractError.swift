//
//  MAError.swift
//  
//
//  Created by Noah Pikielny on 6/29/23.
//

import Foundation

struct MAError: LocalizedError {
    var errorDescription: String?
    init(_ description: String) {
        self.errorDescription = description
    }
}
