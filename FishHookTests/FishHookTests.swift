//
//  FishHookTests.swift
//  FishHookTests
//
//  Created by roy.cao on 2019/7/6.
//  Copyright © 2019 roy. All rights reserved.
//

import XCTest
@testable import FishHook

typealias NewPrintf = @convention(thin) (String, Any...) -> Void

func newPrinf(str: String, arg: Any...) -> Void {
    string = "test success"
}

public func fishhookPrint(newMethod: UnsafeMutableRawPointer) {
    var oldMethod: UnsafeMutableRawPointer?
    rebindSymbol("printf", replacement: newMethod, replaced: &oldMethod)
}

var string = ""

class FishHookTests: XCTestCase {

    func testHook() {
        fishhookPrint(newMethod: unsafeBitCast(newPrinf as NewPrintf, to: UnsafeMutableRawPointer.self))

        Test.print(withStr: "Hello World")

        XCTAssertEqual(string, "test success")
    }
}
