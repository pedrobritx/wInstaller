import Foundation

/// Enumerates physical disks through `diskutil` structured (`-plist`) output and
/// maps them into the domain `USBDrive` model. Internal/system disks are marked
/// unsafe for erase and filtered out by default (`REQ-USB-002`, `REQ-USB-005`).
///
/// All parsing is exposed as pure static functions so it can be fixture-tested
/// without a real disk.
public struct DiskEnumerator: Sendable {
    public static let diskutil = "/usr/sbin/diskutil"

    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    /// Removable, external drives that are safe to consider as erase targets.
    public func removableDrives() async throws -> [USBDrive] {
        let listResult = try await runner.run(
            PlannedCommand(executable: Self.diskutil, arguments: ["list", "-plist"], isDestructive: false),
            timeout: .metadata
        )
        let disks = try Self.parseDiskList(listResult.standardOutput)

        var drives: [USBDrive] = []
        for disk in disks {
            let infoResult = try? await runner.run(
                PlannedCommand(executable: Self.diskutil, arguments: ["info", "-plist", disk.identifier], isDestructive: false),
                timeout: .metadata
            )
            guard let infoResult,
                  let drive = try? Self.parseDriveInfo(infoResult.standardOutput, volumes: disk.volumes)
            else { continue }

            // Safety: never surface internal or fixed disks as erase targets.
            guard drive.isRemovable, !drive.isInternal else { continue }
            drives.append(drive)
        }
        return drives
    }

    /// Re-reads a single disk's identity immediately before a destructive step.
    /// Used by `OperationExecutor` to abort if the device changed.
    public func info(for identifier: String) async throws -> USBDrive {
        let result = try await runner.run(
            PlannedCommand(executable: Self.diskutil, arguments: ["info", "-plist", identifier], isDestructive: false),
            timeout: .metadata
        )
        return try Self.parseDriveInfo(result.standardOutput, volumes: [])
    }

    // MARK: - Pure parsing

    public struct ParsedDisk: Equatable, Sendable {
        public var identifier: String
        public var volumes: [String]
    }

    /// Extracts whole-disk identifiers and their volume names from
    /// `diskutil list -plist` output.
    public static func parseDiskList(_ data: Data) throws -> [ParsedDisk] {
        let decoded = try PropertyListDecoder().decode(DiskUtilList.self, from: data)
        return decoded.allDisksAndPartitions.map { entry in
            let partitionVolumes = (entry.partitions ?? []).compactMap(\.volumeName)
            let apfsVolumes = (entry.apfsVolumes ?? []).compactMap(\.volumeName)
            return ParsedDisk(
                identifier: entry.deviceIdentifier,
                volumes: partitionVolumes + apfsVolumes
            )
        }
    }

    /// Maps `diskutil info -plist <id>` output onto the domain `USBDrive`.
    public static func parseDriveInfo(_ data: Data, volumes: [String]) throws -> USBDrive {
        let info = try PropertyListDecoder().decode(DiskUtilInfo.self, from: data)

        let removable = (info.removable ?? false)
            || (info.removableMedia ?? false)
            || (info.removableMediaOrExternalDevice ?? false)
            || (info.ejectable ?? false)

        let size = info.size ?? info.totalSize ?? 0
        let displayName = firstNonEmpty(info.mediaName, info.ioRegistryEntryName, info.volumeName)
            ?? info.deviceIdentifier
        let mediaName = firstNonEmpty(info.mediaName, info.ioRegistryEntryName) ?? displayName

        let resolvedVolumes = volumes.isEmpty
            ? [info.volumeName].compactMap { $0 }.filter { !$0.isEmpty }
            : volumes

        return USBDrive(
            bsdIdentifier: info.deviceIdentifier,
            displayName: displayName,
            mediaName: mediaName,
            size: size,
            isRemovable: removable,
            isInternal: info.isInternal ?? false,
            connectionType: info.busProtocol ?? "Unknown",
            partitionScheme: partitionScheme(from: info.content),
            fileSystem: firstNonEmpty(info.filesystemName, info.filesystemType) ?? "Unformatted",
            volumes: resolvedVolumes
        )
    }

    static func partitionScheme(from content: String?) -> String {
        switch content {
        case "GUID_partition_scheme": "GPT"
        case "FDisk_partition_scheme": "MBR"
        case "Apple_partition_scheme": "APM"
        case .some(let value) where !value.isEmpty: value
        default: "Unknown"
        }
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                return value
            }
        }
        return nil
    }
}

// MARK: - Decodable models for diskutil plist output

struct DiskUtilList: Decodable {
    var allDisksAndPartitions: [DiskListEntry]

    enum CodingKeys: String, CodingKey {
        case allDisksAndPartitions = "AllDisksAndPartitions"
    }
}

struct DiskListEntry: Decodable {
    var deviceIdentifier: String
    var size: Int64?
    var content: String?
    var partitions: [DiskListPartition]?
    var apfsVolumes: [DiskListPartition]?

    enum CodingKeys: String, CodingKey {
        case deviceIdentifier = "DeviceIdentifier"
        case size = "Size"
        case content = "Content"
        case partitions = "Partitions"
        case apfsVolumes = "APFSVolumes"
    }
}

struct DiskListPartition: Decodable {
    var deviceIdentifier: String?
    var volumeName: String?
    var mountPoint: String?

    enum CodingKeys: String, CodingKey {
        case deviceIdentifier = "DeviceIdentifier"
        case volumeName = "VolumeName"
        case mountPoint = "MountPoint"
    }
}

struct DiskUtilInfo: Decodable {
    var deviceIdentifier: String
    var mediaName: String?
    var ioRegistryEntryName: String?
    var size: Int64?
    var totalSize: Int64?
    var isInternal: Bool?
    var removable: Bool?
    var removableMedia: Bool?
    var removableMediaOrExternalDevice: Bool?
    var ejectable: Bool?
    var busProtocol: String?
    var content: String?
    var filesystemName: String?
    var filesystemType: String?
    var volumeName: String?

    enum CodingKeys: String, CodingKey {
        case deviceIdentifier = "DeviceIdentifier"
        case mediaName = "MediaName"
        case ioRegistryEntryName = "IORegistryEntryName"
        case size = "Size"
        case totalSize = "TotalSize"
        case isInternal = "Internal"
        case removable = "Removable"
        case removableMedia = "RemovableMedia"
        case removableMediaOrExternalDevice = "RemovableMediaOrExternalDevice"
        case ejectable = "Ejectable"
        case busProtocol = "BusProtocol"
        case content = "Content"
        case filesystemName = "FilesystemName"
        case filesystemType = "FilesystemType"
        case volumeName = "VolumeName"
    }
}
