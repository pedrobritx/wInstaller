import Foundation
import Testing
@testable import WInstallerCore

// MARK: - Plist fixtures

private enum Fixture {
    static func data(_ xml: String) -> Data { Data(xml.utf8) }

    static let diskList = data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>AllDisksAndPartitions</key>
      <array>
        <dict>
          <key>DeviceIdentifier</key><string>disk4</string>
          <key>Content</key><string>GUID_partition_scheme</string>
          <key>Size</key><integer>64000000000</integer>
          <key>Partitions</key>
          <array>
            <dict>
              <key>DeviceIdentifier</key><string>disk4s1</string>
              <key>VolumeName</key><string>UNTITLED</string>
            </dict>
          </array>
        </dict>
      </array>
    </dict></plist>
    """)

    static func infoRemovable(size: Int64 = 64_000_000_000, identifier: String = "disk4", mediaName: String = "Kingston DataTraveler Media") -> Data {
        data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>DeviceIdentifier</key><string>\(identifier)</string>
          <key>MediaName</key><string>\(mediaName)</string>
          <key>Size</key><integer>\(size)</integer>
          <key>Internal</key><false/>
          <key>RemovableMedia</key><true/>
          <key>Ejectable</key><true/>
          <key>BusProtocol</key><string>USB</string>
          <key>Content</key><string>FDisk_partition_scheme</string>
          <key>FilesystemName</key><string>MS-DOS FAT32</string>
          <key>VolumeName</key><string>UNTITLED</string>
        </dict></plist>
        """)
    }

    static let infoInternal = data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>DeviceIdentifier</key><string>disk0</string>
      <key>MediaName</key><string>Apple SSD</string>
      <key>Size</key><integer>1000000000000</integer>
      <key>Internal</key><true/>
      <key>RemovableMedia</key><false/>
      <key>Ejectable</key><false/>
      <key>BusProtocol</key><string>PCI-Express</string>
      <key>Content</key><string>GUID_partition_scheme</string>
    </dict></plist>
    """)

    static let hdiutilAttach = data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>system-entities</key>
      <array>
        <dict><key>dev-entry</key><string>/dev/disk5</string></dict>
        <dict>
          <key>dev-entry</key><string>/dev/disk5s1</string>
          <key>mount-point</key><string>/Volumes/CCCOMA_X64FRE</string>
        </dict>
      </array>
    </dict></plist>
    """)
}

// MARK: - Disk enumeration parsing

@Suite("Disk enumeration")
struct DiskEnumeratorTests {
    @Test("parses whole disks and volume names from diskutil list")
    func parsesList() throws {
        let disks = try DiskEnumerator.parseDiskList(Fixture.diskList)
        #expect(disks == [DiskEnumerator.ParsedDisk(identifier: "disk4", volumes: ["UNTITLED"])])
    }

    @Test("maps a removable disk onto the domain model")
    func parsesRemovable() throws {
        let drive = try DiskEnumerator.parseDriveInfo(Fixture.infoRemovable(), volumes: ["UNTITLED"])
        #expect(drive.bsdIdentifier == "disk4")
        #expect(drive.isRemovable)
        #expect(!drive.isInternal)
        #expect(drive.partitionScheme == "MBR")
        #expect(drive.fileSystem == "MS-DOS FAT32")
        #expect(drive.connectionType == "USB")
        #expect(drive.size == 64_000_000_000)
    }

    @Test("marks internal disks as unsafe")
    func parsesInternal() throws {
        let drive = try DiskEnumerator.parseDriveInfo(Fixture.infoInternal, volumes: [])
        #expect(drive.isInternal)
        #expect(!drive.isRemovable)
    }

    @Test("enumeration filters out internal disks")
    func enumerationFiltersInternal() async throws {
        let runner = DryRunCommandRunner { command in
            guard command.arguments.first == "info" else {
                return .init(standardOutput: Fixture.diskList)
            }
            // list contains only disk4; return internal-looking info to force a filter.
            return .init(standardOutput: Fixture.infoInternal)
        }
        let drives = try await DiskEnumerator(runner: runner).removableDrives()
        #expect(drives.isEmpty)
    }

    @Test("enumeration returns removable drives")
    func enumerationReturnsRemovable() async throws {
        let runner = DryRunCommandRunner { command in
            command.arguments.first == "info"
                ? .init(standardOutput: Fixture.infoRemovable())
                : .init(standardOutput: Fixture.diskList)
        }
        let drives = try await DiskEnumerator(runner: runner).removableDrives()
        #expect(drives.map(\.bsdIdentifier) == ["disk4"])
    }
}

// MARK: - ISO mount parsing

@Suite("ISO inspection")
struct ISOInspectorTests {
    @Test("extracts mount point and device from hdiutil attach")
    func parsesAttach() throws {
        let attachment = try ISOInspector.parseAttach(Fixture.hdiutilAttach)
        #expect(attachment.mountPoint == "/Volumes/CCCOMA_X64FRE")
        #expect(attachment.devEntry == "/dev/disk5")
    }
}

// MARK: - Virtualization detection

private struct StubLocator: ApplicationLocating {
    var urls: [String: URL]
    var versions: [String: String]
    var existingPaths: Set<String>

    func url(forBundleIdentifier identifier: String) -> URL? { urls[identifier] }
    func fileExists(atPath path: String) -> Bool { existingPaths.contains(path) }
    func shortVersion(forBundleAt url: URL) -> String? { versions[url.path] }
}

@Suite("Virtualization detection")
struct VirtualizationDetectorTests {
    @Test("detects VMware Fusion via bundle identifier and reads version")
    func detectsByBundleID() {
        let url = URL(fileURLWithPath: "/Applications/VMware Fusion.app")
        let locator = StubLocator(
            urls: ["com.vmware.fusion": url],
            versions: [url.path: "13.5.0"],
            existingPaths: []
        )
        let app = VirtualizationDetector(locator: locator).detectVMwareFusion()
        #expect(app.isInstalled)
        #expect(app.version == "13.5.0")
        #expect(app.url == url)
    }

    @Test("falls back to the known install path")
    func detectsByPath() {
        let locator = StubLocator(
            urls: [:],
            versions: [:],
            existingPaths: ["/Applications/VMware Fusion.app"]
        )
        let app = VirtualizationDetector(locator: locator).detectVMwareFusion()
        #expect(app.isInstalled)
    }

    @Test("reports absent apps")
    func detectsAbsent() {
        let locator = StubLocator(urls: [:], versions: [:], existingPaths: [])
        let app = VirtualizationDetector(locator: locator).detectVMwareFusion()
        #expect(!app.isInstalled)
        #expect(app.url == nil)
    }
}

// MARK: - Operation execution (dry-run runner)

@Suite("Operation executor")
struct OperationExecutorTests {
    private func windowsPlan(requiresSplit: Bool = false) throws -> OperationPlan {
        let engine = BootableUSBEngine()
        let iso = try engine.analyzeISO(
            url: URL(filePath: "/tmp/Win11.iso"),
            size: 6_500_000_000,
            volumeLabel: "Windows",
            directoryEntries: ["setup.exe", "sources/boot.wim", "sources/install.wim", "efi/boot/bootx64.efi"],
            fileSizes: ["sources/install.wim": requiresSplit ? 5_200_000_000 : 3_600_000_000]
        )
        return try engine.makePlan(iso: iso, drive: .sampleRemovable, tools: ToolAvailability(wimlibImageX: true))
    }

    private func runner(infoSize: Int64 = USBDrive.sampleRemovable.size, infoInternal: Bool = false) -> DryRunCommandRunner {
        DryRunCommandRunner { command in
            if command.executable == ISOInspector.hdiutil, command.arguments.first == "attach" {
                return .init(standardOutput: Fixture.hdiutilAttach)
            }
            if command.executable == DiskEnumerator.diskutil, command.arguments.first == "info" {
                let info = infoInternal
                    ? Fixture.infoInternal
                    : Fixture.infoRemovable(size: infoSize, identifier: USBDrive.sampleRemovable.bsdIdentifier, mediaName: USBDrive.sampleRemovable.mediaName)
                return .init(standardOutput: info)
            }
            return .init()
        }
    }

    private func collect(_ executor: OperationExecutor, plan: OperationPlan) async throws -> [EngineEvent] {
        var events: [EngineEvent] = []
        for try await event in executor.run(plan: plan) {
            events.append(event)
        }
        return events
    }

    @Test("runs the full sequence in order without a real disk")
    func runsInOrder() async throws {
        let plan = try windowsPlan()
        let cmd = runner()
        let executor = OperationExecutor(runner: cmd, validateExisting: { _ in [] })

        let events = try await collect(executor, plan: plan)
        let completedIDs = events.filter { $0.status == .complete }.map(\.id)
        #expect(completedIDs.contains("erase-disk"))
        #expect(events.last?.id == "completed")

        // The recorded invocations show erase happens only after unmount.
        let tools = cmd.invocations.map { ($0.executable as NSString).lastPathComponent + " " + ($0.arguments.first ?? "") }
        #expect(tools.contains("diskutil unmountDisk"))
        #expect(tools.contains("diskutil eraseDisk"))
        let unmountIndex = tools.firstIndex(of: "diskutil unmountDisk")
        let eraseIndex = tools.firstIndex(of: "diskutil eraseDisk")
        #expect(unmountIndex != nil && eraseIndex != nil && unmountIndex! < eraseIndex!)
    }

    @Test("aborts before erase when the disk identity changed")
    func abortsOnIdentityMismatch() async throws {
        let plan = try windowsPlan()
        let executor = OperationExecutor(runner: runner(infoSize: 999), validateExisting: { _ in [] })
        await #expect(throws: ExecutionError.self) {
            _ = try await collect(executor, plan: plan)
        }
    }

    @Test("refuses to erase if the target became internal")
    func refusesInternal() async throws {
        let plan = try windowsPlan()
        let cmd = runner(infoInternal: true)
        let executor = OperationExecutor(runner: cmd, validateExisting: { _ in [] })
        do {
            _ = try await collect(executor, plan: plan)
            Issue.record("expected an execution error")
        } catch let error as ExecutionError {
            #expect(error == .refusedInternalDisk)
        }
        // No destructive command was ever issued.
        #expect(!cmd.invocations.contains { $0.isDestructive })
    }

    @Test("fails when required boot files are missing")
    func failsValidation() async throws {
        let plan = try windowsPlan()
        let executor = OperationExecutor(runner: runner(), validateExisting: { _ in ["sources/boot.wim"] })
        do {
            _ = try await collect(executor, plan: plan)
            Issue.record("expected a validation failure")
        } catch let error as ExecutionError {
            #expect(error == .validationFailed(["sources/boot.wim"]))
        }
    }
}
