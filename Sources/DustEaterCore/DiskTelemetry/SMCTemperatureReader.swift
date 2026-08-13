import Foundation
import IOKit
import Darwin

enum SMCTemperatureReader {
    private struct SMCKeyData {
        var key: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
        var vers: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
        var pLimitData: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                         UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var keyInfo: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var dataSize: UInt8 = 0
        var dataType: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum SMCCommand: UInt8 {
        case getKeyInfo = 9
        case readKey = 5
        case getKeyFromIndex = 12
    }

    static func ssdTemperatureCelsius() -> Double? {
        let matchingDict = IOServiceMatching("AppleSMC")
        var iterator: io_iterator_t = 0
        defer { IOObjectRelease(iterator) }

        guard IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            return nil
        }

        var device = IOIteratorNext(iterator)
        guard device != 0 else {
            return nil
        }
        defer { IOObjectRelease(device) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(device, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            return nil
        }
        defer { IOServiceClose(connection) }

        let hardcodedKeys = ["TSSD", "TS0S", "TS1S", "TS2S"]

        for keyStr in hardcodedKeys {
            if let temp = readSMCTemperature(connection: connection, key: keyStr) {
                return temp
            }
        }

        return enumerateTemperatureSensors(connection: connection)
    }

    private static func readSMCTemperature(connection: io_connect_t, key: String) -> Double? {
        guard key.utf8.count == 4 else { return nil }

        guard let keyInfo = getKeyInfo(connection: connection, key: key) else {
            return nil
        }

        let dataSize = Int(keyInfo.dataSize)
        let dataType = dataTypeString(keyInfo.dataType)

        var data = SMCKeyData()
        data.data8 = SMCCommand.readKey.rawValue
        let keyBytes = Array(key.utf8)
        data.key.0 = keyBytes[0]
        data.key.1 = keyBytes[1]
        data.key.2 = keyBytes[2]
        data.key.3 = keyBytes[3]

        var inputSize = MemoryLayout<SMCKeyData>.size
        var outputSize = MemoryLayout<SMCKeyData>.size

        let result = withUnsafeBytes(of: data) { inputPtr in
            withUnsafeMutableBytes(of: &data) { outputPtr in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    inputSize,
                    outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    &outputSize
                )
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        return decodeTemperature(from: data, dataSize: dataSize, dataType: dataType)
    }

    private static func getKeyInfo(connection: io_connect_t, key: String) -> SMCKeyData? {
        guard key.utf8.count == 4 else { return nil }

        var data = SMCKeyData()
        data.data8 = SMCCommand.getKeyInfo.rawValue
        let keyBytes = Array(key.utf8)
        data.key.0 = keyBytes[0]
        data.key.1 = keyBytes[1]
        data.key.2 = keyBytes[2]
        data.key.3 = keyBytes[3]

        var inputSize = MemoryLayout<SMCKeyData>.size
        var outputSize = MemoryLayout<SMCKeyData>.size

        let result = withUnsafeBytes(of: data) { inputPtr in
            withUnsafeMutableBytes(of: &data) { outputPtr in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    inputSize,
                    outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    &outputSize
                )
            }
        }

        return result == KERN_SUCCESS ? data : nil
    }

    private static func enumerateTemperatureSensors(connection: io_connect_t) -> Double? {
        guard let keyCount = getKeyCount(connection: connection) else {
            return nil
        }

        for i in 0..<keyCount {
            if let keyName = getKeyFromIndex(connection: connection, index: UInt32(i)) {
                if keyName.count == 4 && keyName.first == "T" {
                    if let temp = readSMCTemperature(connection: connection, key: keyName) {
                        return temp
                    }
                }
            }
        }

        return nil
    }

    private static func getKeyCount(connection: io_connect_t) -> Int? {
        let keyStr = "#KEY"
        guard let keyInfo = getKeyInfo(connection: connection, key: keyStr) else { return nil }

        var data = SMCKeyData()
        data.data8 = SMCCommand.readKey.rawValue
        let keyBytes = Array(keyStr.utf8)
        data.key.0 = keyBytes[0]
        data.key.1 = keyBytes[1]
        data.key.2 = keyBytes[2]
        data.key.3 = keyBytes[3]

        var inputSize = MemoryLayout<SMCKeyData>.size
        var outputSize = MemoryLayout<SMCKeyData>.size

        let result = withUnsafeBytes(of: data) { inputPtr in
            withUnsafeMutableBytes(of: &data) { outputPtr in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    inputSize,
                    outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    &outputSize
                )
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let bytes = [
            data.bytes.0, data.bytes.1, data.bytes.2, data.bytes.3
        ]
        let count = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        return Int(count)
    }

    private static func getKeyFromIndex(connection: io_connect_t, index: UInt32) -> String? {
        var data = SMCKeyData()
        data.data8 = SMCCommand.getKeyFromIndex.rawValue
        data.bytes.0 = UInt8((index >> 24) & 0xFF)
        data.bytes.1 = UInt8((index >> 16) & 0xFF)
        data.bytes.2 = UInt8((index >> 8) & 0xFF)
        data.bytes.3 = UInt8(index & 0xFF)

        var inputSize = MemoryLayout<SMCKeyData>.size
        var outputSize = MemoryLayout<SMCKeyData>.size

        let result = withUnsafeBytes(of: data) { inputPtr in
            withUnsafeMutableBytes(of: &data) { outputPtr in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    inputSize,
                    outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    &outputSize
                )
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let keyBytes = [data.key.0, data.key.1, data.key.2, data.key.3]
        guard let keyString = String(bytes: keyBytes, encoding: .ascii) else { return nil }

        return keyString.trimmingCharacters(in: .controlCharacters)
    }

    private static func decodeTemperature(from data: SMCKeyData, dataSize: Int, dataType: String) -> Double? {
        let byteArray: [UInt8] = [
            data.bytes.0, data.bytes.1, data.bytes.2, data.bytes.3,
            data.bytes.4, data.bytes.5, data.bytes.6, data.bytes.7,
            data.bytes.8, data.bytes.9, data.bytes.10, data.bytes.11,
            data.bytes.12, data.bytes.13, data.bytes.14, data.bytes.15,
            data.bytes.16, data.bytes.17, data.bytes.18, data.bytes.19,
            data.bytes.20, data.bytes.21, data.bytes.22, data.bytes.23,
            data.bytes.24, data.bytes.25, data.bytes.26, data.bytes.27,
            data.bytes.28, data.bytes.29, data.bytes.30, data.bytes.31
        ]

        if dataType.hasPrefix("flt ") && dataSize >= 4 {
            let bits = UInt32(byteArray[0]) << 24 | UInt32(byteArray[1]) << 16 | UInt32(byteArray[2]) << 8 | UInt32(byteArray[3])
            let celsius = Float(bitPattern: bits)
            let value = Double(celsius)
            return value > 0 && value < 150 ? value : nil
        }

        if dataType.hasPrefix("sp78") && dataSize >= 2 {
            let intPart = Int8(bitPattern: byteArray[0])
            let fracPart = byteArray[1]
            let celsius = Double(intPart) + Double(fracPart) / 256.0
            return celsius > 0 && celsius < 150 ? celsius : nil
        }

        return nil
    }

    private static func dataTypeString(_ typeBytes: (UInt8, UInt8, UInt8, UInt8)) -> String {
        let bytes = [typeBytes.0, typeBytes.1, typeBytes.2, typeBytes.3]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}
