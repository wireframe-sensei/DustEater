import Foundation
import IOKit
import IOKit.storage
import Darwin

enum IORegistryDiskReader {
    struct DeviceCharacteristics: Sendable {
        let productName: String?
        let mediumType: MediumType
        let interconnect: Interconnect
        let interconnectProtocol: String?
        let smartStatus: SMARTStatus
    }

    static func deviceCharacteristics(forBSDName bsdName: String) -> DeviceCharacteristics? {
        guard let matchingDict = IOBSDNameMatching(kIOMasterPortDefault, 0, bsdName) else {
            return nil
        }

        var iterator: io_iterator_t = 0
        defer { IOObjectRelease(iterator) }

        guard IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            return nil
        }

        var service = IOIteratorNext(iterator)
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }

        var productName: String?
        var mediumType: MediumType = .unknown
        var interconnect: Interconnect = .unknown
        var interconnectProtocol: String?
        var smartStatus: SMARTStatus = .notReported

        let searchOptions: IOOptionBits = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)

        if let properties = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            kIOPropertyDeviceCharacteristicsKey as CFString,
            kCFAllocatorDefault,
            searchOptions
        ) as? [String: Any] {
            if let name = properties[kIOPropertyProductNameKey as String] as? String {
                productName = name
            }

            if let mediumTypeKey = properties[kIOPropertyMediumTypeKey as String] as? String {
                if mediumTypeKey == kIOPropertyMediumTypeSolidStateKey as String {
                    mediumType = .solidState
                } else if mediumTypeKey == kIOPropertyMediumTypeRotationalKey as String {
                    mediumType = .rotational
                }
            }

        }

        if let protocolDict = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            kIOPropertyProtocolCharacteristicsKey as CFString,
            kCFAllocatorDefault,
            searchOptions
        ) as? [String: Any] {
            if let interconnectType = protocolDict[kIOPropertyPhysicalInterconnectTypeKey as String] as? String {
                switch interconnectType {
                case "PCI-Express":
                    interconnect = .internal
                    interconnectProtocol = "PCI-Express"
                case "SATA":
                    interconnect = .internal
                    interconnectProtocol = "SATA"
                case "USB":
                    interconnect = .external
                    interconnectProtocol = "USB"
                case "Thunderbolt":
                    interconnect = .external
                    interconnectProtocol = "Thunderbolt"
                default:
                    interconnectProtocol = interconnectType
                }
            }

            if let locationKey = protocolDict[kIOPropertyPhysicalInterconnectLocationKey as String] as? String {
                if locationKey == "External" {
                    interconnect = .external
                } else if locationKey == "Internal" {
                    interconnect = .internal
                }
            }
        }

        if let smartStatusValue = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            "SMART Status" as CFString,
            kCFAllocatorDefault,
            searchOptions
        ) as? String {
            if smartStatusValue == "Verified" {
                smartStatus = .verified
            } else if smartStatusValue == "Failing" {
                smartStatus = .failing
            }
        }

        return DeviceCharacteristics(
            productName: productName,
            mediumType: mediumType,
            interconnect: interconnect,
            interconnectProtocol: interconnectProtocol,
            smartStatus: smartStatus
        )
    }

    static func isSystemDisk(bsdName: String, forPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.isVolumeKey]),
           let isVolume = values.isVolume, isVolume {
            let path = (path as NSString).deletingLastPathComponent
            return path == "/" || path.isEmpty
        }
        return false
    }
}
