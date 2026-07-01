import Foundation
import SwiftUI
import WInstallerCore

/// Coordinates the assistant flow: owns user intent, confirmation state, live
/// device data, and the running operation. Long work runs in cancellable tasks;
/// UI-facing state stays on the main actor.
@MainActor
final class AssistantModel: ObservableObject {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome = 1
        case chooseISO
        case verifyISO
        case insertUSB
        case analyzeUSB
        case confirmErase
        case createUSB
        case done
        case vmware

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .chooseISO: "Choose ISO"
            case .verifyISO: "Verify ISO"
            case .insertUSB: "Insert USB"
            case .analyzeUSB: "Analyze USB"
            case .confirmErase: "Confirm Erase"
            case .createUSB: "Create USB"
            case .done: "Done"
            case .vmware: "VMware Fusion"
            }
        }

        var symbol: String {
            switch self {
            case .welcome: "sparkles"
            case .chooseISO: "opticaldisc"
            case .verifyISO: "checkmark.seal"
            case .insertUSB: "cable.connector"
            case .analyzeUSB: "list.bullet.clipboard"
            case .confirmErase: "exclamationmark.triangle"
            case .createUSB: "gearshape.2"
            case .done: "checkmark.circle"
            case .vmware: "macwindow.on.rectangle"
            }
        }
    }

    // Flow state
    @Published var step: Step = .welcome
    @Published var iso: InstallerISO?
    @Published var selectedDrive: USBDrive?
    @Published var plan: OperationPlan?
    @Published var events: [EngineEvent] = []
    @Published var confirmationText = ""
    @Published var errorMessage: String?

    // UI state
    @Published var showingFileImporter = false
    @Published var showingTechnicalDetails = false
    @Published var isInspectingISO = false
    @Published var isRefreshingDrives = false
    @Published var isRunning = false
    @Published var simulateMode = false

    // Device data
    @Published var drives: [USBDrive] = []
    @Published var vmwareApps: [VirtualizationApp] = []
    @Published var commandLog = ""

    private let engine = BootableUSBEngine()
    private let liveRunner: CommandRunning = ProcessCommandRunner()
    private let logger = LocalLogger()
    private let detector = VirtualizationDetector()
    private var executionTask: Task<Void, Never>?

    var canContinue: Bool {
        switch step {
        case .welcome: true
        case .chooseISO: iso != nil && !isInspectingISO
        case .verifyISO: (iso?.confidence ?? .low) >= .medium
        case .insertUSB: selectedDrive != nil
        case .analyzeUSB: plan != nil
        case .confirmErase: confirmationText == selectedDrive?.displayName
        case .createUSB: !isRunning
        case .done, .vmware: true
        }
    }

    // MARK: - Navigation

    func continueFlow() {
        errorMessage = nil
        switch step {
        case .welcome:
            step = .chooseISO
        case .chooseISO:
            step = .verifyISO
        case .verifyISO:
            step = .insertUSB
            refreshDrives()
        case .insertUSB:
            createPlan()
            if plan != nil { step = .analyzeUSB }
        case .analyzeUSB:
            step = .confirmErase
        case .confirmErase:
            confirmAndCreate()
        case .createUSB:
            step = .done
        case .done:
            detectVMware()
            step = .vmware
        case .vmware:
            reset()
        }
    }

    func goBack() {
        guard step.rawValue > Step.welcome.rawValue, step.rawValue < Step.createUSB.rawValue else { return }
        step = Step(rawValue: step.rawValue - 1) ?? .welcome
    }

    // MARK: - ISO

    func importISO(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.pathExtension.lowercased() == "iso" else {
                errorMessage = "Choose a file with the .iso extension."
                return
            }
            inspectISO(url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func inspectISO(_ url: URL) {
        isInspectingISO = true
        errorMessage = nil
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let inspector = ISOInspector(runner: liveRunner, engine: engine)
            do {
                iso = try await inspector.inspect(url: url)
            } catch let error as ISOInspectionError {
                errorMessage = error.userMessage
            } catch let error as BootableUSBError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = error.localizedDescription
            }
            isInspectingISO = false
        }
    }

    // MARK: - USB

    func refreshDrives() {
        isRefreshingDrives = true
        Task {
            let enumerator = DiskEnumerator(runner: liveRunner)
            let found = (try? await enumerator.removableDrives()) ?? []
            drives = found
            if let selectedDrive, !found.contains(where: { $0.id == selectedDrive.id }) {
                self.selectedDrive = nil
            }
            isRefreshingDrives = false
        }
    }

    private func createPlan() {
        guard let iso, let selectedDrive else { return }
        do {
            let created = try engine.makePlan(iso: iso, drive: selectedDrive, tools: ToolAvailability(wimlibImageX: true))
            plan = created
            events = seedEvents(for: created)
        } catch let error as BootableUSBError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Execution

    private func confirmAndCreate() {
        guard let plan, let selectedDrive else { return }
        do {
            try engine.confirmErase(for: selectedDrive, typedName: confirmationText)
        } catch let error as BootableUSBError {
            errorMessage = error.userMessage
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        step = .createUSB
        isRunning = true
        errorMessage = nil
        events = seedEvents(for: plan)

        let executor = simulateMode
            ? Simulation.executor(for: plan, logger: logger)
            : OperationExecutor(runner: liveRunner, logger: logger)

        executionTask = Task {
            do {
                for try await event in executor.run(plan: plan) {
                    apply(event)
                }
                isRunning = false
                commandLog = await logger.exportText()
                step = .done
            } catch let error as ExecutionError {
                isRunning = false
                errorMessage = error.userMessage
                commandLog = await logger.exportText()
            } catch {
                isRunning = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        executionTask?.cancel()
        executionTask = nil
        isRunning = false
    }

    private func apply(_ event: EngineEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
    }

    private func seedEvents(for plan: OperationPlan) -> [EngineEvent] {
        var seeds: [(String, String)] = [
            ("mount-iso", "Mount ISO read-only"),
            ("verify-usb", "Re-check USB identity"),
            ("unmount", "Unmount USB drive"),
            ("erase-disk", "Erase and format USB drive"),
            ("copy-files", "Copy installer files")
        ]
        if plan.strategy.requiresWIMSplit {
            seeds.append(("split-wim", "Split oversized Windows image"))
        }
        seeds.append(contentsOf: [
            ("validate", "Validate boot files"),
            ("eject", "Eject USB safely")
        ])
        return seeds.map { EngineEvent(id: $0.0, state: .idle, title: $0.1, detail: "Waiting…", status: .waiting) }
    }

    // MARK: - VMware

    func detectVMware() {
        vmwareApps = detector.detectAll()
    }

    var vmwareFusion: VirtualizationApp? {
        vmwareApps.first { $0.id == VirtualizationTarget.vmwareFusion.bundleIdentifier }
    }

    func openVMware() {
        guard let app = vmwareFusion, app.isInstalled else { return }
        detector.open(app)
    }

    // MARK: - Reset

    private func reset() {
        cancel()
        engine.reset()
        step = .welcome
        iso = nil
        selectedDrive = nil
        plan = nil
        events = []
        confirmationText = ""
        errorMessage = nil
        commandLog = ""
    }

    #if DEBUG
    /// Loads a fabricated Windows ISO so the UI can be exercised without hardware.
    func loadSampleISO() {
        do {
            iso = try engine.analyzeISO(
                url: URL(filePath: "/Users/example/Downloads/Win11_English_x64.iso"),
                size: 6_500_000_000,
                volumeLabel: "CCCOMA_X64FRE",
                directoryEntries: ["setup.exe", "sources/boot.wim", "sources/install.wim", "efi/boot/bootx64.efi"],
                fileSizes: ["sources/install.wim": 5_100_000_000]
            )
        } catch let error as BootableUSBError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSampleDrives() {
        drives = [.sampleRemovable]
    }
    #endif
}
