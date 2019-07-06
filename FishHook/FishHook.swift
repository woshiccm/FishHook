//
//  FishHook.swift
//  FishHook
//
//  Created by roy.cao on 2019/7/5.
//  Copyright © 2019 roy. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation
import MachO

public struct Rebinding {
    let name: String
    let replacement: UnsafeMutableRawPointer
    var replaced: UnsafeMutableRawPointer?

    init(_ name: String, replacement: UnsafeMutableRawPointer, replaced: inout UnsafeMutableRawPointer?) {
        self.name = name
        self.replacement = replacement
        self.replaced = replaced
    }
}

private var currentRebinding: Rebinding? = nil

public func rebindSymbol(_ name: String, replacement: UnsafeMutableRawPointer, replaced: inout UnsafeMutableRawPointer?) {
    let rebinding = Rebinding(name, replacement: replacement, replaced: &replaced)
    _rebindSymbol(rebinding)
}

public func _rebindSymbol(_ rebinding: Rebinding) {
    if currentRebinding == nil {
        currentRebinding = rebinding
        _dyld_register_func_for_add_image(rebindSymbolForImage)
    } else {
        currentRebinding = rebinding
        for i in 0..<_dyld_image_count() {
            rebindSymbolForImage(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i))
        }
    }
}

func rebindSymbolForImage(_ mh: UnsafePointer<mach_header>?, _ slide:Int) {
    guard let mh = mh else { return }

    var curSegCmd: UnsafeMutablePointer<segment_command_64>!
    var linkeditSegment: UnsafeMutablePointer<segment_command_64>!
    var symtabCmd: UnsafeMutablePointer<symtab_command>!
    var dysymtabCmd: UnsafeMutablePointer<dysymtab_command>!

    var cur = UnsafeRawPointer(mh).advanced(by: MemoryLayout<mach_header_64>.stride)

    for _: UInt32 in 0 ..< mh.pointee.ncmds {
        curSegCmd = UnsafeMutableRawPointer(mutating: cur).assumingMemoryBound(to: segment_command_64.self)
        cur = UnsafeRawPointer(cur).advanced(by: Int(curSegCmd.pointee.cmdsize))

        if curSegCmd.pointee.cmd == LC_SEGMENT_64 {
            let segname = String(cString: &curSegCmd.pointee.segname, maxLength: 16)
            if segname == SEG_LINKEDIT {
                linkeditSegment = curSegCmd
            }
        } else if curSegCmd.pointee.cmd == LC_SYMTAB {
            symtabCmd = UnsafeMutableRawPointer(mutating: curSegCmd).assumingMemoryBound(to: symtab_command.self)
        } else if curSegCmd.pointee.cmd == LC_DYSYMTAB {
            dysymtabCmd = UnsafeMutableRawPointer(mutating: curSegCmd).assumingMemoryBound(to: dysymtab_command.self)
        }
    }

    guard linkeditSegment != nil, symtabCmd != nil, dysymtabCmd != nil else {
        return
    }

    let linkeditBase = slide + Int(linkeditSegment.pointee.vmaddr) - Int(linkeditSegment.pointee.fileoff)
    let symtab = UnsafeMutablePointer<nlist_64>(bitPattern: linkeditBase + Int(symtabCmd.pointee.symoff))
    let strtab = UnsafeMutablePointer<UInt8>(bitPattern: linkeditBase + Int(symtabCmd.pointee.stroff))
    let indirectSymtab = UnsafeMutablePointer<UInt32>(bitPattern: linkeditBase + Int(dysymtabCmd.pointee.indirectsymoff))

    guard let _symtab = symtab, let _strtab = strtab, let _indirectSymtab = indirectSymtab else {
        return
    }

    cur = UnsafeRawPointer(mh).advanced(by: MemoryLayout<mach_header_64>.stride)
    for _: UInt32 in 0 ..< mh.pointee.ncmds {
        curSegCmd = UnsafeMutableRawPointer(mutating: cur).assumingMemoryBound(to: segment_command_64.self)
        cur = UnsafeRawPointer(cur).advanced(by: Int(curSegCmd.pointee.cmdsize))

        if curSegCmd.pointee.cmd == LC_SEGMENT_64 {
            let segname = String(cString: &curSegCmd.pointee.segname, maxLength: 16)
            if segname == SEG_DATA {
                for j in 0..<curSegCmd.pointee.nsects {
                    let cur = UnsafeRawPointer(curSegCmd).advanced(by: MemoryLayout<segment_command_64>.size + MemoryLayout<section_64>.size*Int(j))
                    let section = UnsafeMutableRawPointer(mutating: cur).assumingMemoryBound(to: section_64.self)
                    if section.pointee.flags == S_LAZY_SYMBOL_POINTERS || section.pointee.flags == S_NON_LAZY_SYMBOL_POINTERS {
                        performRebindingWithSection(section, slide: slide, symtab: _symtab, strtab: _strtab, indirectSymtab: _indirectSymtab)
                    }
                }
            }
        }
    }
}

func performRebindingWithSection(_ section: UnsafeMutablePointer<section_64>,
                                 slide: Int,
                                 symtab: UnsafeMutablePointer<nlist_64>,
                                 strtab: UnsafeMutablePointer<UInt8>,
                                 indirectSymtab: UnsafeMutablePointer<UInt32>) {
    guard var rebinding = currentRebinding, let symbolBytes = rebinding.name.data(using: String.Encoding.utf8)?.map({ $0 }) else {
        return
    }

    let indirectSymbolIndices = indirectSymtab.advanced(by: Int(section.pointee.reserved1))
    let indirectSymbolBindings = UnsafeMutablePointer<UnsafeMutableRawPointer>(bitPattern: slide+Int(section.pointee.addr))

    guard let _indirectSymbolBindings = indirectSymbolBindings else {
        return
    }

    for i in 0..<Int(section.pointee.size)/MemoryLayout<UnsafeMutableRawPointer>.size {
        let symtabIndex = indirectSymbolIndices.advanced(by: i)
        if symtabIndex.pointee == INDIRECT_SYMBOL_ABS || symtabIndex.pointee == INDIRECT_SYMBOL_LOCAL {
            continue;
        }

        let strtabOffset = symtab.advanced(by: Int(symtabIndex.pointee)).pointee.n_un.n_strx
        let symbolName = strtab.advanced(by: Int(strtabOffset))

        var isEqual = true
        for i in 0..<symbolBytes.count {
            if symbolBytes[i] != symbolName.advanced(by: i+1).pointee {
                isEqual = false
            }
        }

        if isEqual {
            rebinding.replaced = _indirectSymbolBindings.advanced(by: i).pointee
            _indirectSymbolBindings.advanced(by: i).initialize(to: rebinding.replacement)
        }
    }
}

extension String {
    //Special initializer to get a string from a possibly not-null terminated but usually null-terminated UTF-8 encoded C String.
    init (cString: UnsafeRawPointer!, maxLength: Int) {
        var buffer = [UInt8](repeating: 0, count: maxLength + 1)
        memcpy(&buffer, cString, maxLength)
        self.init(cString: buffer)
    }
}
