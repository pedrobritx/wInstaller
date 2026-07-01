import Foundation

public enum ISOInspectionError: Error, Equatable, Sendable {
    case mountFailed(String)
    case noMountPoint

    public var userMessage: String {
        switch self {
        case .mountFailed:
            "wInstaller could not mount this ISO. It may be damaged or unsupported."
        case .noMountPoint:
            "The ISO mounted but no readable volume was found."
        }
    }
}

/// Mounts an ISO read-only with `hdiutil`, walks its directory tree to gather the
/// entries and file sizes that `BootableUSBEngine.analyzeISO` needs, then detaches
/// the image. The image is never modified (`REQ-ISO-003`, `REQ-ISO-007`).
public struct ISOInspector: Sendable {
    public static let hdiutil = "/usr/bin/hdiutil"

    private let runner: CommandRunning
    private let engine: BootableUSBEngine

    public init(runner: CommandRunning = ProcessCommandRunner(), engine: BootableUSBEngine = BootableUSBEngine()) {
        self.runner = runner
        self.engine = engine
    }

    public func inspect(url: URL) async throws -> InstallerISO {
        let attachResult = try await runner.run(
            PlannedCommand(
                executable: Self.hdiutil,
                arguments: ["attach", "-readonly", "-nobrowse", "-plist", url.path],
                isDestructive: false
            ),
            timeout: .mount
        )
        guard attachResult.succeeded else {
            throw ISOInspectionError.mountFailed(attachResult.standardErrorString)
        }

        let attachment = try Self.parseAttach(attachResult.standardOutput)
        guard let mountPoint = attachment.mountPoint else {
            if let device = attachment.devEntry { await detach(device) }
            throw ISOInspectionError.noMountPoint
        }

        // Always detach, whether analysis succeeds or throws (e.g. unsupported ISO).
        do {
            let mountURL = URL(fileURLWithPath: mountPoint)
            let scan = Self.scan(mountPoint: mountURL)
            let size = fileSize(of: url)
            let iso = try engine.analyzeISO(
                url: url,
                size: size,
                volumeLabel: mountURL.lastPathComponent,
                directoryEntries: scan.entries,
                fileSizes: scan.fileSizes
            )
            if let device = attachment.devEntry { await detach(device) }
            return iso
        } catch {
            if let device = attachment.devEntry { await detach(device) }
            throw error
        }
    }

    private func detach(_ device: String) async {
        _ = try? await runner.run(
            PlannedCommand(executable: Self.hdiutil, arguments: ["detach", device], isDestructive: false),
            timeout: .mount
        )
    }

    private func fileSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        if let size = values?.fileSize { return Int64(size) }
        return 0
    }

    // MARK: - Pure parsing / scanning

    public struct Attachment: Equatable, Sendable {
        public var devEntry: String?
        public var mountPoint: String?
    }

    /// Extracts the mounted volume and its device entry from
    /// `hdiutil attach -plist` output.
    public static func parseAttach(_ data: Data) throws -> Attachment {
        let decoded = try PropertyListDecoder().decode(HDIUtilAttach.self, from: data)
        // The volume entity is the one that carries a mount point.
        let mounted = decoded.systemEntities.first { $0.mountPoint?.isEmpty == false }
        // The whole-disk entity (shortest dev-entry) is what we detach.
        let device = decoded.systemEntities
            .compactMap(\.devEntry)
            .min(by: { $0.count < $1.count })
        return Attachment(devEntry: device, mountPoint: mounted?.mountPoint)
    }

    struct ScanResult {
        var entries: [String]
        var fileSizes: [String: Int64]
    }

    /// Walks a mounted volume and returns relative paths plus file sizes. Sizes
    /// are recorded under both the natural-case and lowercased relative path so
    /// the engine's case-sensitive lookups resolve on any ISO layout.
    static func scan(mountPoint: URL) -> ScanResult {
        var entries: [String] = []
        var fileSizes: [String: Int64] = [:]

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        // Do not skip hidden files: Linux media is detected via `.disk/info`.
        guard let enumerator = FileManager.default.enumerator(
            at: mountPoint,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return ScanResult(entries: entries, fileSizes: fileSizes)
        }

        let base = mountPoint.standardizedFileURL.path
        for case let fileURL as URL in enumerator {
            let path = fileURL.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            var relative = String(path.dropFirst(base.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            if relative.isEmpty { continue }

            entries.append(relative)

            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { continue }
            if let size = values?.fileSize {
                fileSizes[relative] = Int64(size)
                fileSizes[relative.lowercased()] = Int64(size)
            }
        }

        return ScanResult(entries: entries, fileSizes: fileSizes)
    }
}

struct HDIUtilAttach: Decodable {
    var systemEntities: [Entity]

    enum CodingKeys: String, CodingKey {
        case systemEntities = "system-entities"
    }

    struct Entity: Decodable {
        var devEntry: String?
        var mountPoint: String?

        enum CodingKeys: String, CodingKey {
            case devEntry = "dev-entry"
            case mountPoint = "mount-point"
        }
    }
}
