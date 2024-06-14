//
//  HexUtil.swift
//  MagtekNtagScanKit
//
//  Created by Vladyslav Ternovskyi on 10.06.2024.
//

import Foundation

extension String {
   
    public var byteArrayFromHexString:[UInt8] {
        return HexUtil.getByteArrayFromHexString(self)
    }
    
    public func parseTLVDataWithNoLength() -> [AnyHashable : Any]? {
        if let hexData = HexUtil.getBytesFromHexString(self) {
            return hexData.parseTLVDataWithNoLength()
        }
        return nil    }
}


extension Data {
    
    func toArray<T>(type: T.Type) -> [T] {
        withUnsafeBytes {
            [T](UnsafeBufferPointer(start: $0, count: self.count/MemoryLayout<T>.stride))
        }
    }
    
    /// Return hexadecimal string representation of NSData bytes
    
    public var hexadecimalString: String {
        return self.reduce("") { $0 + String(format: "%02x", $1) }
    }
    
    func parseTLVData() -> [AnyHashable : Any]? {
        return NSData(data: self).parseTLVData()
    }
    
    func parseTLVDataWithNoLength() -> [AnyHashable : Any]? {
        return NSData(data: self).parseTLVDataWithNoLength()
    }
}

extension NSData {
    
    func parseTLVData() -> [AnyHashable : Any]? {
        var parsedTLVList: [AnyHashable : Any] = [:]
        
        let dataLen = Int(self.count)
        
        if dataLen >= 2 {
            // NSData* tlvData = [self subdataWithRange:NSMakeRange(2, self.length - 2)];
            //subdata(in: 2 ..< dataLen-2)
            let tlvData =  self.subdata(with: NSRange(location: 2, length: self.length - 2))
            //let tlvData = subdata(in: 2 ..< dataLen-2)
            
            var iTLV: Int
            var iTag: Int
            var iLen: Int
            var bTag: Bool
            var bMoreTagBytes: Bool
            var bConstructedTag: Bool
            var ByteValue: UInt8
            var lengthValue: Int
            
            var tagBytes: Data? = nil
            
            let MoreTagBytesFlag1 : UInt8 = 0x1f
            let MoreTagBytesFlag2 : UInt8 = 0x80
            let ConstructedFlag : UInt8 = 0x20
            let MoreLengthFlag : UInt8 = 0x80
            let OneByteLengthMask : UInt8 = 0x7f
            // var TagBuffer = [UInt8](repeating: nil, count: 50)
            var TagBuffer = [UInt8] (repeating: 0, count: 50)
            //var TagBuffer : [UInt8][50] = []
            
            bTag = true
            iTLV = 0
            
            while iTLV < tlvData.count {
                let bytePtr = [UInt8](tlvData) //UInt8(tlvData.bytes)
                ByteValue = bytePtr[iTLV]
                
                if bTag {
                    // Get Tag
                    iTag = 0
                    bMoreTagBytes = true
                    
                    while bMoreTagBytes && (iTLV < tlvData.count) {
                        let bytePtr = [UInt8](tlvData) //UInt8(tlvData.bytes)
                        ByteValue = bytePtr[iTLV]
                        iTLV += 1
                        
                        TagBuffer[iTag] = ByteValue
                        
                        if iTag == 0 {
                            bMoreTagBytes = (ByteValue & MoreTagBytesFlag1) == MoreTagBytesFlag1
                        } else {
                            bMoreTagBytes = (ByteValue & MoreTagBytesFlag2) == MoreTagBytesFlag2
                        }
                        
                        iTag += 1
                    }
                    
                    tagBytes = Data()
                    tagBytes?.append(&TagBuffer, count: iTag)
                    // tagBytes.append(&TagBuffer, length: iTag)
                    bTag = false
                } else {
                    lengthValue = 0
                    
                    if (ByteValue & MoreLengthFlag) == MoreLengthFlag {
                        let nLengthBytes = Int(ByteValue & OneByteLengthMask)
                        
                        iTLV += 1
                        iLen = 0
                        
                        while (iLen < nLengthBytes) && (iTLV < tlvData.count) {
                            let bytePtr = [UInt8](tlvData) //UInt8(tlvData.bytes)
                            ByteValue = bytePtr[iTLV]
                            iTLV += 1
                            lengthValue = Int((lengthValue & 0x000000ff) << 8) + Int(ByteValue & 0x000000ff)
                            iLen += 1
                        }
                    } else {
                        lengthValue = Int(ByteValue & OneByteLengthMask)
                        iTLV += 1
                    }
                    
                    if tagBytes != nil && (memcmp((tagBytes! as NSData).bytes, "00", tagBytes!.count) != 0) {
                        let bytePtr = [UInt8](tagBytes!) //UInt8(tagBytes!.bytes())
                        let tagByte = Int(bytePtr[0])
                        
                        bConstructedTag = (tagByte & Int(ConstructedFlag)) == Int(ConstructedFlag)
                        //bConstructedTag = true
                        if bConstructedTag {
                            let map = MTTLV()
                            map.tag = HexUtil.toHex(tagBytes!)!
                            map.length = lengthValue
                            map.value = "[Container]"
                            // [parsedTLVList addObject:map];
                            parsedTLVList[map.tag.uppercased()] = map
                            //parsedTLVList.setObject(map, forKeyedSubscript: map?.tag)
                        } else {
                            // Primitive
                            var endIndex = iTLV + lengthValue
                            
                            if endIndex > tlvData.count {
                                endIndex = Int(tlvData.count)
                            }
                            
                            var valueBytes: Data? = nil
                            let len = endIndex - iTLV
                            if len > 0 {
                                valueBytes = Data()
                                
                                
                                let range =  NSRange(location: iTLV, length: len)
                                let subData = tlvData.subdata(in: Range<Data.Index>(range)!)
                                
                                valueBytes = subData
                            }
                            
                            let tlvMap = MTTLV()
                            tlvMap.tag = HexUtil.toHex(tagBytes!)!
                            tlvMap.length = lengthValue
                            
                            
                            if valueBytes != nil {
                                tlvMap.value = HexUtil.toHex(valueBytes!)!
                            } else {
                                tlvMap.value = ""
                            }
                            parsedTLVList[tlvMap.tag.uppercased()] = tlvMap
                            iTLV += lengthValue
                        }
                    }
                    
                    bTag = true
                }
            }
        }
        return parsedTLVList
    }
    
    func parseTLVDataWithNoLength() -> [AnyHashable: Any]? {
        var lengthByte = [UInt16] (repeating: 0, count: 2)
        lengthByte[1] = UInt16(length)
        lengthByte[0] = UInt16(length >> 8)
        let tempData = NSMutableData()
        tempData.append(&lengthByte[0], length: 1)
        tempData.append(&lengthByte[1], length: 1)
        tempData.append(self as Data)
        return tempData.parseTLVData()
    }
    
}

public enum HexUtil {
    
    public static func toHex(_ byteArray : [UInt8]) -> String {
        return byteArray.reduce("") { $0 + String(format: "%02x", $1) }
    }
    
    public static func toHex(_ aData: Data) -> String? {
        return aData.hexadecimalString
        //return HexUtil.toHex(aData, offset: 0, len: UInt(aData?.count ?? 0))
    }

    public static func getBytesFromHexString(_ string: String) -> NSData? {
        guard let chars = string.cString(using: .utf8) else {
            return nil
        }
        var index = 0
        let length = string.count
        
        let data = NSMutableData(capacity: length / 2)
        var byteChars: [CChar] = [0, 0, 0]
        
        var wholeByte: CUnsignedLong = 0
        
        while index < length {
            byteChars[0] = chars[index]
            index += 1
            byteChars[1] = chars[index]
            index += 1
            wholeByte = strtoul(byteChars, nil, 16)
            data?.append(&wholeByte, length: 1)
        }
        
        return data
    }
    
    public static func getByteArrayFromHexString(_ strIn: String) -> [UInt8] {
        
        return Data(getBytesFromHexString(strIn)!).toArray(type: UInt8.self)
    }

    public static func toHex(_ aData: Data, offset aOffset: UInt, len aLen: Int) -> String? {
        var sb = String(repeating: "\0", count: (aData.count) * 2)
        let bytes = [UInt8](aData)

        let max = Int(aOffset) + aLen
        for i in Int(aOffset)..<max {
            let b = bytes[i]
            sb += String(format: "%02X", b)
        }
        return sb
    }
}

public class MTTLV: NSObject {
    public var tag = ""
    public var length = 0
    public var value = ""
}

public extension Dictionary {
    
    func getTLV(_ key: String) -> MTTLV? {
        if let dictionaryRef = self as? [String: AnyObject] {
            return dictionaryRef[key] as? MTTLV
        }
        return MTTLV()
    }
}
