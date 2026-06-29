import Foundation
import Testing
@testable import WInstallerCore

@Suite("Bootable USB engine")
struct BootableUSBEngineTests {
    @Test("detects Windows ISO markers with high confidence")
    func detectsWindowsISO() throws {
        let engine = BootableUSBEngine()
        let iso = try engine.analyzeISO(
            url: URL(filePath: "/tmp/Win11.iso"),
            size: 6_500_000_000,
            volumeLabel: "CCCOMA_X64FRE",
            directoryEntries: [
                "setup.exe",
                "sources/boot.wim",
                "sources/install.wim",
                "efi/boot/bootx64.efi"
            ],
            fileSizes: ["sources/install.wim": 5_100_000_000]
        )

        #expect(iso.detectedOS == .windows(version: nil))
        #expect(iso.confidence == .high)
        #expect(iso.windowsImageInfo?.requiresSplit == true)
        #expect(engine.state == .waitingForUSB)
    }

    @Test("rejects unrecognized ISO layouts")
    func rejectsUnknownISO() throws {
        let engine = BootableUSBEngine()

        #expect(throws: BootableUSBError.unsupportedISO) {
            try engine.analyzeISO(
                url: URL(filePath: "/tmp/archive.iso"),
                size: 120_000_000,
                volumeLabel: nil,
                directoryEntries: ["README.txt"],
                fileSizes: [:]
            )
        }
        #expect(engine.state == .failed)
    }

    @Test("refuses internal disks during planning")
    func refusesInternalDisk() throws {
        let engine = BootableUSBEngine()
        let iso = try windowsISO(requiresSplit: false)

        #expect(throws: BootableUSBError.diskNotRemovable) {
            try engine.makePlan(iso: iso, drive: .sampleInternal)
        }
    }

    @Test("requires wimlib when Windows image must be split")
    func requiresWimlibForLargeWIM() throws {
        let engine = BootableUSBEngine()
        let iso = try windowsISO(requiresSplit: true)

        #expect(throws: BootableUSBError.missingTool("wimlib-imagex")) {
            try engine.makePlan(iso: iso, drive: .sampleRemovable, tools: ToolAvailability(wimlibImageX: false))
        }
    }

    @Test("creates deterministic dry-run plan")
    func createsDeterministicPlan() throws {
        let engine = BootableUSBEngine()
        let iso = try windowsISO(requiresSplit: true)
        let plan = try engine.makePlan(iso: iso, drive: .sampleRemovable, tools: ToolAvailability(wimlibImageX: true))

        #expect(plan.strategy.targetPartitionScheme == "GPT")
        #expect(plan.strategy.targetFileSystem == "FAT32")
        #expect(plan.strategy.requiresWIMSplit)
        #expect(plan.destructiveSteps.map(\.id) == ["erase-disk"])
        #expect(plan.steps.map(\.id) == ["mount-iso", "verify-usb", "erase-disk", "copy-files", "split-wim", "validate", "eject"])
        #expect(engine.state == .awaitingEraseConfirmation)
    }

    @Test("confirmation must match selected drive name")
    func confirmationMatchesDriveName() throws {
        let engine = BootableUSBEngine()
        let iso = try windowsISO(requiresSplit: false)
        _ = try engine.makePlan(iso: iso, drive: .sampleRemovable)

        #expect(throws: BootableUSBError.confirmationMismatch) {
            try engine.confirmErase(for: .sampleRemovable, typedName: "Wrong Drive")
        }

        try engine.confirmErase(for: .sampleRemovable, typedName: USBDrive.sampleRemovable.displayName)
        #expect(engine.state == .preparingDrive)
    }

    private func windowsISO(requiresSplit: Bool) throws -> InstallerISO {
        let engine = BootableUSBEngine()
        let installWimSize: Int64 = requiresSplit ? 5_200_000_000 : 3_600_000_000
        return try engine.analyzeISO(
            url: URL(filePath: "/tmp/Win11.iso"),
            size: 6_500_000_000,
            volumeLabel: "Windows",
            directoryEntries: [
                "setup.exe",
                "sources/boot.wim",
                "sources/install.wim",
                "efi/boot/bootx64.efi"
            ],
            fileSizes: ["sources/install.wim": installWimSize]
        )
    }
}
