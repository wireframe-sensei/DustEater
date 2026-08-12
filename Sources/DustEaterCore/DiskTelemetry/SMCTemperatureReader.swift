import Foundation
import IOKit
import Darwin

enum SMCTemperatureReader {
    private struct SMCKeyData {
        var key: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
        var padToSize: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
        var dataSize: UInt32 = 0
        var dataType: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
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

        let sensorKeys = ["TSSD", "TS0S", "TS1S", "TS2S"]

        for keyStr in sensorKeys {
            if let temp = readSMCTemperature(connection: connection, key: keyStr) {
                return temp
            }
        }

        return nil
    }

    private static func readSMCTemperature(connection: io_connect_t, key: String) -> Double? {
        var inputData = SMCKeyData()
        var outputData = SMCKeyData()

        let keyBytes = Array(key.utf8)
        inputData.key.0 = keyBytes.count > 0 ? keyBytes[0] : 0
        inputData.key.1 = keyBytes.count > 1 ? keyBytes[1] : 0
        inputData.key.2 = keyBytes.count > 2 ? keyBytes[2] : 0
        inputData.key.3 = keyBytes.count > 3 ? keyBytes[3] : 0

        var inputSize = MemoryLayout<SMCKeyData>.size
        var outputSize = MemoryLayout<SMCKeyData>.size

        let result = withUnsafeBytes(of: inputData) { inputPtr in
            withUnsafeMutableBytes(of: &outputData) { outputPtr in
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

        guard result == KERN_SUCCESS else {
            return nil
        }

        let bytes = outputData.bytes
        let byteArray: [UInt8] = [
            bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15,
            bytes.16, bytes.17, bytes.18, bytes.19, bytes.20, bytes.21, bytes.22, bytes.23,
            bytes.24, bytes.25, bytes.26, bytes.27, bytes.28, bytes.29, bytes.30, bytes.31
        ]

        if outputData.dataSize == 2 {
            let value = UInt16(byteArray[0]) << 8 | UInt16(byteArray[1])
            let celsius = Double(value >> 8) + (Double(value & 0xFF) / 256.0)
            return celsius > 0 && celsius < 150 ? celsius : nil
        }

        return nil
    }
}
