//
//  NFCReader.swift
//  MagtekNtagScanKit
//
//  Created by Vladyslav Ternovskyi on 10.06.2024.
//

import Foundation
import ExternalAccessory
import MTSCRA

public enum ReaderDevice: String {
    case iDynamo6
}

public enum NFCReaderError: Error {
    case noContent
    case unknown
    case invalidResponse
    case statusCode(String)
}

public struct NFCReaderSettings {
    let debugEnabled: Bool
    
    public init(debugEnabled: Bool) {
        self.debugEnabled = debugEnabled
    }
}

public protocol NFCReader {
    var isDeviceConnected: Bool { get }
    var debugMessageCallback: ((String) -> Void)? { get set }
    
    func begin(completion: @escaping (Result<String, Error>) -> Void)
    func cancel()
}

public class DefaultNFCReader: NSObject, NFCReader {
    
    public var isDeviceConnected: Bool {
        getConnectedDevice() != nil
    }
    
    private let transactionDelay = 0.4
    
    private var lib = MTSCRA()
    private var selectedDevice = ReaderDevice.iDynamo6.rawValue
    private var detector = EADetector()
    private let deviceCfg = [
        ReaderDevice.iDynamo6.rawValue : [
            "Connection": Lightning,
            "Type": MAGTEKKDYNAMO,
            "Protocol": "com.magtek.idynamo",
            "Initial": ["Turning On MSR": "580101"]
        ]
    ]
    private let settings: NFCReaderSettings
    private var completion: ((Result<String, Error>) -> Void)?
    
    public var debugMessageCallback: ((String) -> Void)?
    
    public override init() {
        self.settings = .init(debugEnabled: true)
        super.init()
        
        lib.delegate = self
        MTSCRA.enableDebugPrint(settings.debugEnabled)

        detector.delegate = self

        lib.debugInfoCallback = { info in
            print("time - " + Date.now.description)
            print("debug.name  - " + (info?.name ?? ""))
            print("debug.value - " + (info?.value ?? ""))
        }
        
        let sdkversion: String = lib.getSDKVersion()
        log("SDK version - \(sdkversion)")
        deviceConnected()
    }
    
    public func begin(completion: @escaping (Result<String, Error>) -> Void) {
        deviceConnected()
        self.completion = completion
        
        let success = lib.openDeviceSync()
        guard success else {
            completion(.failure(NFCReaderError.unknown))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + transactionDelay) { [self] in
            startTransaction()
        }
    }
    
    public func cancel() {
        lib.cancelTransaction()
    }
    
    private func startTransaction() {
        let amount = stringToN12(value: "1.0")
        let cashback = stringToN12(value: "0")
        let currencyCode = HexUtil.getBytesFromHexString("0840")
        
        var bAmount: [UInt8] = [0, 0, 0, 0, 0, 0]
        var bCashback: [UInt8] = [0, 0, 0, 0, 0, 0]
        var bCurrencyCode: [UInt8] = [0, 0]
        
        memcpy(&bAmount, amount.bytes, 6)
        memcpy(&bCashback, cashback.bytes, 6)
        memcpy(&bCurrencyCode, currencyCode?.bytes, 2)
        
        lib.startTransaction(0, // 1-255 seconds, 0 for infinite
                             cardType: 4, // Contactless (4)
                             option: 0x20, // NFC enabled (0x20)
                             amount: &bAmount,
                             transactionType: 0,
                             cashBack: &bCashback,
                             currencyCode: &bCurrencyCode,
                             reportingOption: 2) // report all state changed
    }
    
    private func readNtag() {
        
        lib.setTimeout(20000) // 20 seconds
        
        log("Read NTAG card")
        let card = NTag(sendNfc: sendNFCSync)
        Task {
            do {
                try await card.getVersion()
                let size = try await card.getMemorySize()
                log("card size : \(size)" )
                
                let ndefs = try await card.readNdef()
                for ndef in ndefs {
                    if let textRecord = ndef as? TextRecord {
                        completion?(.success(textRecord.text))
                        log("TEXT RECORD: \(textRecord.text)")
                        
                    } else {
                        completion?(.failure(NFCReaderError.invalidResponse))
                        log("RECORD BYTES : \(ndef.payload)")
                    }
                }
            }
            catch {
                completion?(.failure(error))
                log(error.localizedDescription)
            }
        }
    }
    
    private func getConnectedDevice() -> EAAccessory? {
        let device = detector.accessories.first { accessory in
            guard let name = detector.getDeviceTypeString(accessory) else {
                return false
            }
            return name == ReaderDevice.iDynamo6.rawValue
        }
        return device
    }
    
    private func log(_ message: String) {
        guard settings.debugEnabled else {
            return
        }
        debugMessageCallback?(message)
    }
    
    private func sendNFCSync(_ command : String, _ lastCommand : Bool = false) async throws -> String {
        let result =  try await withCheckedThrowingContinuation {
            continuation  in
            let response = self.lib.sendNFCCommandSync(command, lastCommand: lastCommand, encrypt: false)
            
            if let resp = response {
                if resp.count > 8 {
                    let tlvString = String(resp.suffix(resp.count - 8))
                    let tlvs = tlvString.parseTLVDataWithNoLength()
                    if let df7a = tlvs?.getTLV("DF7A") {
                        continuation.resume(returning: df7a.value)
                    } else {
                        continuation.resume(throwing: NFCReaderError.noContent)
                    }
                } else if resp.count == 8 {
                    if resp.starts(with: "0000") {
                        continuation.resume(returning: "")
                    } else {
                        continuation.resume(
                            throwing: NFCReaderError.statusCode(String(resp.prefix(4)))
                        )
                    }
                } else {
                    continuation.resume(throwing: NFCReaderError.invalidResponse)
                }
            } else {
                continuation.resume(throwing: NFCReaderError.unknown )
            }
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        return result
    }
    
    private func selectDevice(_ device : String) {
        log("Select - " + device)
        
        if !deviceCfg.keys.contains(device) {
            log("invalid device - " + device)
            return
        }
        
        selectedDevice = device
        
        lib.setConnectionType(UInt(deviceCfg[device]?["Connection"] as! Int))
        lib.setDeviceType(UInt32(deviceCfg[device]?["Type"] as! Int))
    }
    
    private func initialDevice(_ device : String) {
        if lib.isDeviceEMV() {
            setDateTime()
        }
        
        if let initial = deviceCfg[device]?["Initial"] {
            for (name, command) in (initial as! Dictionary<String, String>) {
                log(name)
                sendCommand(command)
            }
        }
    }
    
    private func sendCommand(_ command: String) {
        if command.isEmpty {
            return
        }
        let resp = lib.sendCommandSync(command)
        log("Send Command (\(command)) - \(resp ?? "")")
    }
    
    private func setDateTime() {
        log("setDateTime")
        let commandToSend = buildSetDateTimeCommand()
        let resp = lib.sendExtendedCommandSync(commandToSend)
        log("sendExtendedCommandSync(\(commandToSend) -> \(resp ?? "")")
    }
}

// MARK: - EADetectorDelegate
extension DefaultNFCReader: EADetectorDelegate {
    
    public func deviceConnected() {
        guard let device = getConnectedDevice(),
              let name = detector.getDeviceTypeString(device) else {
            return
        }
        selectDevice(name)
    }
    
    public func deviceDisconnected() {
        cancel()
    }
}

extension DefaultNFCReader: MTSCRAEventDelegate {
    
    public func onDeviceError(_ error: Error!) {
        log(error.debugDescription)
    }
    
    public func onDeviceConnectionDidChange(_ deviceType: UInt, connected: Bool, instance: Any!) {
        log(connected ? "[Connected]" : "[Disconnected]")
        
        if connected {
            DispatchQueue.main.async {
                self.initialDevice(self.selectedDevice)
            }
        }
    }
    
    public func onDeviceResponse(_ data: Data!) {
        log("[Device Response]\n\(data.hexadecimalString)")
    }
    
    public func onDeviceExtendedResponse(_ data: String!) {
        log("[Device Extended Response]\n\(data!)" )
    }
    
    public func onTransactionStatus(_ data: Data!) {
        let hex = data.hexadecimalString
        log("[Transaction Status]\n\(hex)")
        
        if hex == "1100000000" {
            DispatchQueue.main.asyncAfter(deadline: .now() + transactionDelay) {
                self.readNtag()
            }
        }
    }
}

// MARK: - Helper Methods
public extension NFCReader {
    
    func stringToN12(value: String) -> NSData {
        let amount = Double(value)
        let strAmount = String(format: "%12.0f", (amount ?? 0) * 100)
        let dataAmount = HexUtil.getBytesFromHexString(strAmount)
        return dataAmount ?? NSData()
    }
    
    func buildSetDateTimeCommand() -> String {
        let date = Date()
        
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date) - 2008
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        
        let cmd = "030C"
        let size = "0018"
        let deviceSn = "00000000000000000000000000000000"
        let strMonth = String(format: "%02lX", month)
        let strDay = String(format: "%02lX", day)
        let strHour = String(format: "%02lX", hour)
        let strMinute = String(format: "%02lX", minute)
        let strSecond = String(format: "%02lX", second)
        let strYear = String(format: "%02lX", year)
        let commandToSend = "\(cmd)\(size)00\(deviceSn)\(strMonth)\(strDay)\(strHour)\(strMinute)\(strSecond)00\(strYear)"
        
        return commandToSend
    }
}
