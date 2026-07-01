import Foundation
import WInstallerCore

/// Builds a `DryRunCommandRunner` that returns just enough structured output for
/// the real `OperationExecutor` to run end-to-end without touching a disk. This
/// powers the "Simulate (dry-run)" toggle and exercises the exact production code
/// path — no destructive command is ever executed.
enum Simulation {
    static func executor(for plan: OperationPlan, logger: LocalLogger) -> OperationExecutor {
        OperationExecutor(
            runner: runner(for: plan),
            logger: logger,
            validateExisting: { _ in [] } // pretend every required file is present
        )
    }

    static func runner(for plan: OperationPlan) -> DryRunCommandRunner {
        let attach = attachPlist()
        let info = infoPlist(for: plan.drive)
        return DryRunCommandRunner { command in
            if command.executable == ISOInspector.hdiutil, command.arguments.first == "attach" {
                return .init(standardOutput: attach)
            }
            if command.executable == DiskEnumerator.diskutil, command.arguments.first == "info" {
                return .init(standardOutput: info)
            }
            return .init()
        }
    }

    private static func attachPlist() -> Data {
        let entity: [String: Any] = [
            "dev-entry": "/dev/disk99",
            "mount-point": "/Volumes/SIMULATED_INSTALLER"
        ]
        let root: [String: Any] = ["system-entities": [entity]]
        return plist(root)
    }

    private static func infoPlist(for drive: USBDrive) -> Data {
        let root: [String: Any] = [
            "DeviceIdentifier": drive.bsdIdentifier,
            "MediaName": drive.mediaName,
            "Size": Int(drive.size),
            "Internal": false,
            "RemovableMedia": true,
            "Ejectable": true,
            "BusProtocol": drive.connectionType,
            "Content": "GUID_partition_scheme"
        ]
        return plist(root)
    }

    private static func plist(_ object: [String: Any]) -> Data {
        (try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)) ?? Data()
    }
}
