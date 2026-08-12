import Foundation
import DiskArbitration
import Darwin

enum PhysicalDiskResolver {
    static func wholeDiskBSDName(forVolumeAt path: String) -> String? {
        let url = URL(fileURLWithPath: path)

        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            return nil
        }

        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else {
            return nil
        }

        guard let wholeDisk = DADiskCopyWholeDisk(disk) else {
            return nil
        }

        guard let description = DADiskCopyDescription(wholeDisk) as? [String: Any] else {
            return nil
        }

        return description[kDADiskDescriptionMediaBSDNameKey as String] as? String
    }
}
