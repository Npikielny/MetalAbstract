import XCTest
@testable import MetalAbstract
#if os(macOS)
import Cocoa
import SwiftUI
#endif

final class GraphicsKitTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
//        XCTAssertEqual(GraphicsKit().text, "Hello, World!")
    }
    
    func testBuffer() throws {
        let ints = (0...10).map { _ in Int32.random(in: Int32.min...Int32.max) }
        let buffer = Buffer(0, 1, 2, 3, usage: .sparse)
        XCTAssertEqual(buffer[3], 3)
        XCTAssertEqual(Buffer(0, 1, 2, 3, usage: .shared)[3], 3)
    }
}
