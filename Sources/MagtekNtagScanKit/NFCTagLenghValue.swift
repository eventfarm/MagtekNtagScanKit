//
//  NFCTagLenghValue.swift
//  MagtekNtagScanKit
//
//  Created by Vladyslav Ternovskyi on 12.06.2024.
//

import Foundation

public class NFCTagLenghValue {
    public let tag: UInt8
    public let value: [UInt8]
    
    init(tag: UInt8, value: [UInt8]) {
        self.tag = tag
        self.value = value
    }
    
    public static func parse(_ data: [UInt8]) throws -> [NFCTagLenghValue] {
        var index = 0
        var result: [NFCTagLenghValue] = []
        
        while (index < data.count) {
            let tag = data[index]
            index = index + 1
            
            if tag == 0xFE { // terminator
                break
            }
            
            let taglength = data[index]
            index = index + 1
            
            var length = Int(taglength)
            if (taglength == 0xFF) {
                length = Int(data[index]) * 256 + Int(data[index + 1])
                index = index + 2
            }
            let valueEndIndex = index + length
            
            let value = [UInt8](data[index ..< valueEndIndex])
            index = valueEndIndex
            result.append(.init(tag: tag, value: value))
        }
        
        return result
    }
}
