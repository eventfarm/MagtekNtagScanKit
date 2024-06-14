//
//  NTag.swift
//  MagtekNtagScanKit
//
//  Created by Vladyslav Ternovskyi on 10.06.2024.
//

import Foundation

public class NTag {
    private let getVersion = "60"
    private let read = "30"
    private let fastRead = "3A"
    private let write = "A2"
    
    /// send a NFC command and get the response. NTag class need this to contruct.
    ///  @param command NTAG command to send
    ///  @param lastCommand Indicate it is a last command to send. Device will beep and close the communication to tag card once it is last command.
    ///  @returns NFC response
    private let sendNfc: ((_ command : String, _ lastCommand : Bool) async throws -> String)
    private var userSize: UInt8 = 0
    
    public init(sendNfc: @escaping (_: String, _: Bool) async throws -> String) {
        self.sendNfc = sendNfc
    }
    
    public func readNdef() async throws -> [NdefRecord] {
        let rawByteArray = try await readAll()
        
        let records = try NFCTagLenghValue.parse(rawByteArray)
            .compactMap {
                Ndef.makeNdefMessage(rawByteArray: $0.value)?.records
            }
            .flatMap { $0 }
        
        return records
    }
    
    public func getVersion() async throws -> Void {
        let _ = try await sendNfc(getVersion, false)
    }
    
    public func getMemorySize() async throws -> UInt {
        if userSize == 0 {
            let vhex = try await readOne(0)
            userSize = vhex.count > 15 ? vhex[14] : 0
        }
        
        return UInt(userSize) * 8
    }
    
    private func readAll() async throws -> [UInt8] {
        if userSize == 0 {
            let vhex = try await readOne(0)
            userSize = vhex.count > 15 ? vhex[14] : 0
        }
        
        //let readCount = 8
        let readCount = 255 - 4 // read all in one shot
        
        if userSize > 0 {
            var result: [UInt8] = []
            let lastBlock = userSize * 2 + 4 - 1
            for start in stride(from: 4, to: lastBlock, by: readCount) {
                let isLastRead = start + UInt8(readCount) > lastBlock
                let endBlock = isLastRead ? lastBlock : start + UInt8(readCount) - 1
                
                let value = try await fastRead(start, endBlock, lastCommand: isLastRead)
                result.append(contentsOf: value)
            }
            return result
        }
        return []
    }
    
    private func readOne(_ block: UInt8, lastCommand: Bool = false) async throws -> [UInt8] {
        let hexBlock = String(format:"%02X", block)
        let vhex = try await sendNfc(read + hexBlock, lastCommand)
        return vhex.byteArrayFromHexString
    }
    
    private func fastRead( _ startBlock: UInt8, _ endBlock: UInt8, lastCommand : Bool = false) async throws -> [UInt8] {
        let hexStartBlock = String(format:"%02X", startBlock)
        let hexEndBlock = String(format:"%02X", endBlock)
        let vhex = try await sendNfc(fastRead + hexStartBlock + hexEndBlock, lastCommand)
        return vhex.byteArrayFromHexString
    }
}
