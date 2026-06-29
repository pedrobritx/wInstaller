import Foundation

public enum DetectedOperatingSystem: Equatable, Sendable {
    case windows(version: String?)
    case linux(distribution: String?)
    case unknown

    public var displayName: String {
        switch self {
        case .windows(let version):
            if let version, !version.isEmpty { return "Windows \(version)" }
            return "Windows installer"
        case .linux(let distribution):
            if let distribution, !distribution.isEmpty { return distribution }
            return "Linux installer"
        case .unknown:
            return "Unknown installer"
        }
    }
}

public enum DetectionConfidence: String, Comparable, Sendable {
    case low
    case medium
    case high

    public static func < (lhs: DetectionConfidence, rhs: DetectionConfidence) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ confidence: DetectionConfidence) -> Int {
        switch confidence {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }
}

public struct WindowsImageInfo: Equatable, Sendable {
    public static let fat32SingleFileLimit: Int64 = 4_294_967_295

    public var installWimSize: Int64?
    public var hasInstallESD: Bool

    public init(installWimSize: Int64?, hasInstallESD: Bool) {
        self.installWimSize = installWimSize
        self.hasInstallESD = hasInstallESD
    }

    public var requiresSplit: Bool {
        guard let installWimSize else { return false }
        return installWimSize > Self.fat32SingleFileLimit
    }
}

public struct InstallerISO: Equatable, Sendable {
    public var url: URL
    public var displayName: String
    public var size: Int64
    public var volumeLabel: String?
    public var detectedOS: DetectedOperatingSystem
    public var confidence: DetectionConfidence
    public var bootFiles: [String]
    public var windowsImageInfo: WindowsImageInfo?

    public init(url: URL, displayName: String, size: Int64, volumeLabel: String?, detectedOS: DetectedOperatingSystem, confidence: DetectionConfidence, bootFiles: [String], windowsImageInfo: WindowsImageInfo?) {
        self.url = url
        self.displayName = displayName
        self.size = size
        self.volumeLabel = volumeLabel
        self.detectedOS = detectedOS
        self.confidence = confidence
        self.bootFiles = bootFiles
        self.windowsImageInfo = windowsImageInfo
    }
}

public struct USBDrive: Identifiable, Equatable, Sendable {
    public var id: String { bsdIdentifier }
    public var bsdIdentifier: String
    public var displayName: String
    public var mediaName: String
    public var size: Int64
    public var isRemovable: Bool
    public var isInternal: Bool
    public var connectionType: String
    public var partitionScheme: String
    public var fileSystem: String
    public var volumes: [String]

    public init(bsdIdentifier: String, displayName: String, mediaName: String, size: Int64, isRemovable: Bool, isInternal: Bool, connectionType: String, partitionScheme: String, fileSystem: String, volumes: [String]) {
        self.bsdIdentifier = bsdIdentifier
        self.displayName = displayName
        self.mediaName = mediaName
        self.size = size
        self.isRemovable = isRemovable
        self.isInternal = isInternal
        self.connectionType = connectionType
        self.partitionScheme = partitionScheme
        self.fileSystem = fileSystem
        self.volumes = volumes
    }
}

public enum EngineState: String, Equatable, Sendable, CaseIterable {
    case idle
    case analyzingISO
    case waitingForUSB
    case analyzingUSB
    case planning
    case awaitingEraseConfirmation
    case preparingDrive
    case copyingFiles
    case splittingWIM
    case validating
    case ejecting
    case completed
    case failed
    case cancelled
}

public enum BootableUSBError: Error, Equatable, Sendable {
    case unsupportedISO
    case diskNotRemovable
    case diskIsInternal
    case insufficientCapacity(required: Int64, available: Int64)
    case missingTool(String)
    case confirmationMismatch
    case invalidState(current: EngineState)

    public var userMessage: String {
        switch self {
        case .unsupportedISO:
            return "wInstaller could not identify this ISO as supported installation media."
        case .diskNotRemovable:
            return "The selected drive is not marked as removable."
        case .diskIsInternal:
            return "wInstaller refuses to erase internal disks."
        case .insufficientCapacity:
            return "The selected USB drive does not have enough capacity."
        case .missingTool(let name):
            return "The required tool \(name) is not available."
        case .confirmationMismatch:
            return "The confirmation does not match the selected drive."
        case .invalidState:
            return "The operation cannot continue from the current state."
        }
    }
}

public enum OperationKind: String, Equatable, Sendable {
    case analyzeISO
    case verifyUSB
    case eraseDisk
    case copyFiles
    case splitWIM
    case validateBootFiles
    case ejectDisk
}

public struct PlannedCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var isDestructive: Bool

    public init(executable: String, arguments: [String], isDestructive: Bool) {
        self.executable = executable
        self.arguments = arguments
        self.isDestructive = isDestructive
    }
}

public struct OperationStep: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var kind: OperationKind
    public var command: PlannedCommand?

    public init(id: String, title: String, detail: String, kind: OperationKind, command: PlannedCommand?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.command = command
    }
}

public struct BootStrategy: Equatable, Sendable {
    public var targetPartitionScheme: String
    public var targetFileSystem: String
    public var requiresErase: Bool
    public var requiresWIMSplit: Bool
    public var warnings: [String]

    public init(targetPartitionScheme: String, targetFileSystem: String, requiresErase: Bool, requiresWIMSplit: Bool, warnings: [String]) {
        self.targetPartitionScheme = targetPartitionScheme
        self.targetFileSystem = targetFileSystem
        self.requiresErase = requiresErase
        self.requiresWIMSplit = requiresWIMSplit
        self.warnings = warnings
    }
}

public struct OperationPlan: Equatable, Sendable {
    public var iso: InstallerISO
    public var drive: USBDrive
    public var strategy: BootStrategy
    public var steps: [OperationStep]
    public var requiresAuthorization: Bool
    public var estimatedBytesToCopy: Int64
    public var validationChecks: [String]

    public init(iso: InstallerISO, drive: USBDrive, strategy: BootStrategy, steps: [OperationStep], requiresAuthorization: Bool, estimatedBytesToCopy: Int64, validationChecks: [String]) {
        self.iso = iso
        self.drive = drive
        self.strategy = strategy
        self.steps = steps
        self.requiresAuthorization = requiresAuthorization
        self.estimatedBytesToCopy = estimatedBytesToCopy
        self.validationChecks = validationChecks
    }

    public var destructiveSteps: [OperationStep] {
        steps.filter { $0.command?.isDestructive == true }
    }
}

public enum ChecklistStatus: String, Equatable, Sendable {
    case waiting
    case running
    case complete
    case warning
    case failed
}

public struct EngineEvent: Identifiable, Equatable, Sendable {
    public var id: String
    public var state: EngineState
    public var title: String
    public var detail: String
    public var status: ChecklistStatus

    public init(id: String, state: EngineState, title: String, detail: String, status: ChecklistStatus) {
        self.id = id
        self.state = state
        self.title = title
        self.detail = detail
        self.status = status
    }
}

public struct ToolAvailability: Equatable, Sendable {
    public var diskutil: Bool
    public var hdiutil: Bool
    public var rsync: Bool
    public var wimlibImageX: Bool

    public init(diskutil: Bool = true, hdiutil: Bool = true, rsync: Bool = true, wimlibImageX: Bool = false) {
        self.diskutil = diskutil
        self.hdiutil = hdiutil
        self.rsync = rsync
        self.wimlibImageX = wimlibImageX
    }
}

public final class BootableUSBEngine: @unchecked Sendable {
    public private(set) var state: EngineState = .idle

    public init() {}

    public func reset() {
        state = .idle
    }

    public func analyzeISO(url: URL, size: Int64, volumeLabel: String?, directoryEntries: [String], fileSizes: [String: Int64]) throws -> InstallerISO {
        state = .analyzingISO

        let normalized = Set(directoryEntries.map { Self.normalize($0) })
        let bootFiles = normalized.filter { path in
            path.contains("boot") || path.contains("efi") || path.contains("isolinux") || path.contains("syslinux")
        }.sorted()

        let windowsMarkers: Set<String> = [
            "setup.exe",
            "sources/boot.wim",
            "sources/install.wim",
            "sources/install.esd",
            "efi/boot/bootx64.efi"
        ]
        let windowsMatches = windowsMarkers.intersection(normalized)

        let linuxMarkers: Set<String> = ["efi", "isolinux", "syslinux", "casper", ".disk/info"]
        let hasLinuxMarkers = linuxMarkers.contains { marker in
            normalized.contains(marker) || normalized.contains { $0.hasPrefix(marker + "/") }
        }

        let detectedOS: DetectedOperatingSystem
        let confidence: DetectionConfidence
        let windowsImageInfo: WindowsImageInfo?

        if windowsMatches.count >= 3 {
            detectedOS = .windows(version: nil)
            confidence = windowsMatches.count >= 4 ? .high : .medium
            windowsImageInfo = WindowsImageInfo(
                installWimSize: fileSizes["sources/install.wim"] ?? fileSizes["SOURCES/INSTALL.WIM"],
                hasInstallESD: normalized.contains("sources/install.esd")
            )
        } else if hasLinuxMarkers {
            detectedOS = .linux(distribution: volumeLabel)
            confidence = .medium
            windowsImageInfo = nil
        } else {
            detectedOS = .unknown
            confidence = .low
            windowsImageInfo = nil
        }

        let iso = InstallerISO(url: url, displayName: url.lastPathComponent, size: size, volumeLabel: volumeLabel, detectedOS: detectedOS, confidence: confidence, bootFiles: bootFiles, windowsImageInfo: windowsImageInfo)

        state = confidence == .low ? .failed : .waitingForUSB
        if confidence == .low {
            throw BootableUSBError.unsupportedISO
        }

        return iso
    }

    public func makePlan(iso: InstallerISO, drive: USBDrive, tools: ToolAvailability = ToolAvailability()) throws -> OperationPlan {
        state = .planning

        guard drive.isRemovable else {
            state = .failed
            throw BootableUSBError.diskNotRemovable
        }
        guard !drive.isInternal else {
            state = .failed
            throw BootableUSBError.diskIsInternal
        }
        guard drive.size >= iso.size else {
            state = .failed
            throw BootableUSBError.insufficientCapacity(required: iso.size, available: drive.size)
        }
        guard tools.diskutil else {
            state = .failed
            throw BootableUSBError.missingTool("diskutil")
        }
        guard tools.hdiutil else {
            state = .failed
            throw BootableUSBError.missingTool("hdiutil")
        }
        guard tools.rsync else {
            state = .failed
            throw BootableUSBError.missingTool("rsync")
        }

        let requiresWIMSplit = iso.windowsImageInfo?.requiresSplit == true
        if requiresWIMSplit && !tools.wimlibImageX {
            state = .failed
            throw BootableUSBError.missingTool("wimlib-imagex")
        }

        let strategy = BootStrategy(
            targetPartitionScheme: "GPT",
            targetFileSystem: "FAT32",
            requiresErase: true,
            requiresWIMSplit: requiresWIMSplit,
            warnings: strategyWarnings(for: iso, drive: drive, requiresWIMSplit: requiresWIMSplit)
        )

        var steps: [OperationStep] = [
            OperationStep(id: "mount-iso", title: "Mount ISO read-only", detail: "Inspect the installer without modifying it.", kind: .analyzeISO, command: PlannedCommand(executable: "/usr/bin/hdiutil", arguments: ["attach", "-readonly", iso.url.path], isDestructive: false)),
            OperationStep(id: "verify-usb", title: "Re-check USB identity", detail: "Confirm \(drive.displayName) is still \(drive.bsdIdentifier).", kind: .verifyUSB, command: PlannedCommand(executable: "/usr/sbin/diskutil", arguments: ["info", "-plist", drive.bsdIdentifier], isDestructive: false)),
            OperationStep(id: "erase-disk", title: "Erase and format USB drive", detail: "Create a GPT/FAT32 installer volume.", kind: .eraseDisk, command: PlannedCommand(executable: "/usr/sbin/diskutil", arguments: ["eraseDisk", "MS-DOS", "WINSTALLER", "GPT", drive.bsdIdentifier], isDestructive: true)),
            OperationStep(id: "copy-files", title: "Copy installer files", detail: "Preserve the ISO directory structure on the target volume.", kind: .copyFiles, command: PlannedCommand(executable: "/usr/bin/rsync", arguments: ["-aE", "--progress", "<mounted-iso>/", "/Volumes/WINSTALLER/"], isDestructive: false))
        ]

        if requiresWIMSplit {
            steps.append(OperationStep(id: "split-wim", title: "Split oversized Windows image", detail: "Create setup-compatible SWM parts below the FAT32 file limit.", kind: .splitWIM, command: PlannedCommand(executable: "/opt/homebrew/bin/wimlib-imagex", arguments: ["split", "<mounted-iso>/sources/install.wim", "/Volumes/WINSTALLER/sources/install.swm", "3800"], isDestructive: false)))
        }

        steps.append(contentsOf: [
            OperationStep(id: "validate", title: "Validate boot files", detail: "Check required boot folders and Windows source files.", kind: .validateBootFiles, command: nil),
            OperationStep(id: "eject", title: "Eject USB safely", detail: "Finish only after macOS releases the drive.", kind: .ejectDisk, command: PlannedCommand(executable: "/usr/sbin/diskutil", arguments: ["eject", drive.bsdIdentifier], isDestructive: false))
        ])

        state = .awaitingEraseConfirmation

        return OperationPlan(iso: iso, drive: drive, strategy: strategy, steps: steps, requiresAuthorization: true, estimatedBytesToCopy: iso.size, validationChecks: validationChecks(for: iso))
    }

    public func confirmErase(for drive: USBDrive, typedName: String) throws {
        guard state == .awaitingEraseConfirmation else {
            throw BootableUSBError.invalidState(current: state)
        }
        guard typedName == drive.displayName else {
            throw BootableUSBError.confirmationMismatch
        }
        state = .preparingDrive
    }

    public func dryRunEvents(for plan: OperationPlan) -> [EngineEvent] {
        var events = [
            EngineEvent(id: "iso", state: .analyzingISO, title: "ISO verified", detail: plan.iso.detectedOS.displayName, status: .complete),
            EngineEvent(id: "usb", state: .analyzingUSB, title: "USB selected", detail: "\(plan.drive.displayName) (\(plan.drive.bsdIdentifier))", status: .complete),
            EngineEvent(id: "erase", state: .preparingDrive, title: "USB erase planned", detail: "Requires explicit confirmation before execution.", status: .waiting),
            EngineEvent(id: "copy", state: .copyingFiles, title: "Files ready to copy", detail: ByteCountFormatter.string(fromByteCount: plan.estimatedBytesToCopy, countStyle: .file), status: .waiting)
        ]

        if plan.strategy.requiresWIMSplit {
            events.append(EngineEvent(id: "wim", state: .splittingWIM, title: "WIM split required", detail: "wimlib-imagex will create SWM parts.", status: .waiting))
        }

        events.append(contentsOf: [
            EngineEvent(id: "validate", state: .validating, title: "Boot validation planned", detail: plan.validationChecks.joined(separator: ", "), status: .waiting),
            EngineEvent(id: "eject", state: .ejecting, title: "Safe eject planned", detail: plan.drive.bsdIdentifier, status: .waiting)
        ])

        return events
    }

    private func strategyWarnings(for iso: InstallerISO, drive: USBDrive, requiresWIMSplit: Bool) -> [String] {
        var warnings: [String] = []
        if drive.fileSystem != "FAT32" {
            warnings.append("The USB drive will be reformatted as FAT32 for UEFI boot compatibility.")
        }
        if requiresWIMSplit {
            warnings.append("The Windows image is larger than FAT32 allows and must be split.")
        }
        if iso.confidence == .medium {
            warnings.append("ISO detection confidence is medium; validation must pass before success.")
        }
        return warnings
    }

    private func validationChecks(for iso: InstallerISO) -> [String] {
        switch iso.detectedOS {
        case .windows:
            if iso.windowsImageInfo?.requiresSplit == true {
                return ["boot directory", "efi directory", "sources/boot.wim", "sources/install.swm"]
            }
            return ["boot directory", "efi directory", "sources/boot.wim", "sources/install.wim or install.esd"]
        case .linux:
            return ["EFI or boot directory", "copy completed", "safe eject"]
        case .unknown:
            return ["copy completed", "safe eject"]
        }
    }

    private static func normalize(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
}

public extension USBDrive {
    static let sampleRemovable = USBDrive(
        bsdIdentifier: "disk4",
        displayName: "Kingston DataTraveler",
        mediaName: "Kingston DataTraveler Media",
        size: 64_000_000_000,
        isRemovable: true,
        isInternal: false,
        connectionType: "USB",
        partitionScheme: "MBR",
        fileSystem: "ExFAT",
        volumes: ["UNTITLED"]
    )

    static let sampleInternal = USBDrive(
        bsdIdentifier: "disk0",
        displayName: "APPLE SSD",
        mediaName: "Apple Internal SSD",
        size: 1_000_000_000_000,
        isRemovable: false,
        isInternal: true,
        connectionType: "PCI-Express",
        partitionScheme: "GPT",
        fileSystem: "APFS",
        volumes: ["Macintosh HD"]
    )
}
