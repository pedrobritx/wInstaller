import AppKit
import SwiftUI
import WInstallerCore

@main
struct WInstallerApp: App {
    // When launched as a bare SwiftPM executable (no .app bundle), macOS starts the
    // process as a background agent. This adaptor promotes it to a regular foreground
    // app so the window appears and accepts focus.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("wInstaller") {
            AssistantRootView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
private final class AssistantModel: ObservableObject {
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
    }

    @Published var step: Step = .welcome
    @Published var iso: InstallerISO?
    @Published var selectedDrive: USBDrive?
    @Published var plan: OperationPlan?
    @Published var events: [EngineEvent] = []
    @Published var confirmationText = ""
    @Published var showingFileImporter = false
    @Published var showingTechnicalDetails = false
    @Published var errorMessage: String?

    let drives: [USBDrive] = [.sampleRemovable]
    private let engine = BootableUSBEngine()

    var canContinue: Bool {
        switch step {
        case .welcome:
            return true
        case .chooseISO:
            return iso != nil
        case .verifyISO:
            return iso?.confidence ?? .low >= .medium
        case .insertUSB:
            return selectedDrive != nil
        case .analyzeUSB:
            return plan != nil
        case .confirmErase:
            return confirmationText == selectedDrive?.displayName
        case .createUSB, .done, .vmware:
            return true
        }
    }

    func continueFlow() {
        errorMessage = nil
        switch step {
        case .welcome:
            step = .chooseISO
        case .chooseISO:
            if iso == nil { loadSampleISO() }
            step = .verifyISO
        case .verifyISO:
            step = .insertUSB
        case .insertUSB:
            if selectedDrive == nil { selectedDrive = drives.first }
            createPlan()
            step = .analyzeUSB
        case .analyzeUSB:
            step = .confirmErase
        case .confirmErase:
            confirmErase()
        case .createUSB:
            finishDryRun()
        case .done:
            step = .vmware
        case .vmware:
            reset()
        }
    }

    func goBack() {
        guard step.rawValue > Step.welcome.rawValue, step.rawValue < Step.createUSB.rawValue else { return }
        step = Step(rawValue: step.rawValue - 1) ?? .welcome
    }

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

    func importISO(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.pathExtension.lowercased() == "iso" else {
                errorMessage = "Choose a file with the .iso extension."
                return
            }
            loadSampleISO(named: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func loadSampleISO(named url: URL) {
        do {
            iso = try engine.analyzeISO(
                url: url,
                size: 6_500_000_000,
                volumeLabel: "Detected ISO",
                directoryEntries: ["setup.exe", "sources/boot.wim", "sources/install.wim", "efi/boot/bootx64.efi"],
                fileSizes: ["sources/install.wim": 3_600_000_000]
            )
        } catch let error as BootableUSBError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createPlan() {
        guard let iso, let selectedDrive else { return }
        do {
            plan = try engine.makePlan(iso: iso, drive: selectedDrive, tools: ToolAvailability(wimlibImageX: true))
            if let plan {
                events = engine.dryRunEvents(for: plan)
            }
        } catch let error as BootableUSBError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmErase() {
        guard let selectedDrive else { return }
        do {
            try engine.confirmErase(for: selectedDrive, typedName: confirmationText)
            step = .createUSB
            runDryRunProgress()
        } catch let error as BootableUSBError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runDryRunProgress() {
        events = events.map { event in
            var updated = event
            updated.status = updated.id == "iso" || updated.id == "usb" ? .complete : .running
            return updated
        }
    }

    private func finishDryRun() {
        events = events.map { event in
            var updated = event
            updated.status = .complete
            return updated
        }
        step = .done
    }

    private func reset() {
        engine.reset()
        step = .welcome
        iso = nil
        selectedDrive = nil
        plan = nil
        events = []
        confirmationText = ""
        errorMessage = nil
    }
}

private struct AssistantRootView: View {
    @StateObject private var model = AssistantModel()

    var body: some View {
        NavigationSplitView {
            StepSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 250, ideal: 280)
        } detail: {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(32)

                Divider()
                FooterBar(model: model)
            }
            .background(.background)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        model.showingTechnicalDetails.toggle()
                    } label: {
                        Label("Log", systemImage: "doc.text.magnifyingglass")
                    }
                    .help("Show technical details")

                    Button {} label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    .help("Open user guide")
                }
            }
        }
        .fileImporter(isPresented: $model.showingFileImporter, allowedContentTypes: [.diskImage], allowsMultipleSelection: false) { result in
            model.importISO(result: result.map { urls in urls.first ?? URL(filePath: "/") })
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome: WelcomeStep(model: model)
        case .chooseISO: ChooseISOStep(model: model)
        case .verifyISO: VerifyISOStep(model: model)
        case .insertUSB: InsertUSBStep(model: model)
        case .analyzeUSB: AnalyzeUSBStep(model: model)
        case .confirmErase: ConfirmEraseStep(model: model)
        case .createUSB: CreateUSBStep(model: model)
        case .done: DoneStep(model: model)
        case .vmware: VMwareStep(model: model)
        }
    }
}

private struct StepSidebar: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        List(AssistantModel.Step.allCases) { step in
            HStack(spacing: 10) {
                Image(systemName: symbol(for: step))
                    .symbolVariant(step.rawValue < model.step.rawValue ? .fill : .none)
                    .foregroundStyle(color(for: step))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Step \(step.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(step.title)
                        .font(.headline)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(step.rawValue), \(step.title)")
        }
        .navigationTitle("wInstaller")
    }

    private func symbol(for step: AssistantModel.Step) -> String {
        if step.rawValue < model.step.rawValue { return "checkmark.circle" }
        if step == model.step { return "circle.inset.filled" }
        return "circle"
    }

    private func color(for step: AssistantModel.Step) -> Color {
        if step.rawValue < model.step.rawValue { return .green }
        if step == model.step { return .accentColor }
        return .secondary
    }
}

private struct FooterBar: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        HStack {
            Label("Local only. No telemetry. No disk changes until confirmation.", systemImage: "lock.shield")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Back") { model.goBack() }
                .disabled(model.step == .welcome || model.step.rawValue >= AssistantModel.Step.createUSB.rawValue)
            Button(primaryTitle) { model.continueFlow() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canContinue)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var primaryTitle: String {
        switch model.step {
        case .confirmErase: "Erase and Create Bootable USB"
        case .createUSB: "Complete Dry Run"
        case .done: "Open VMware Instructions"
        case .vmware: "Create Another USB"
        default: "Continue"
        }
    }
}

private struct StepHeader: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WelcomeStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            StepHeader(icon: "externaldrive.connected.to.line.below", title: "Create a bootable installer USB", subtitle: "wInstaller guides ISO selection, USB verification, erase confirmation, copy planning, validation, and VMware handoff.")
            InfoGrid(items: [
                ("ISO file", "Choose Windows or Linux installation media."),
                ("USB drive", "Use removable media with enough capacity."),
                ("Confirmation", "Erase is blocked until the drive name is typed."),
                ("Dry-run core", "This build plans operations without touching disks.")
            ])
            ErrorBanner(message: model.errorMessage)
        }
    }
}

private struct ChooseISOStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(icon: "opticaldiscdrive", title: "Choose an ISO file", subtitle: "Select installation media. The importer rejects non-ISO files before analysis.")
            HStack(spacing: 12) {
                Button {
                    model.showingFileImporter = true
                } label: {
                    Label("Choose ISO", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.loadSampleISO()
                } label: {
                    Label("Use Sample", systemImage: "play.circle")
                }
            }
            if let iso = model.iso {
                ISOCard(iso: iso)
            }
            ErrorBanner(message: model.errorMessage)
        }
    }
}

private struct VerifyISOStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(icon: "checkmark.seal", title: "Verify the installer", subtitle: "The app explains what it detected before a USB drive is selected.")
            if let iso = model.iso {
                ISOCard(iso: iso)
                Checklist(rows: [
                    ("Operating system", iso.detectedOS.displayName, .complete),
                    ("Confidence", iso.confidence.rawValue.capitalized, iso.confidence == .high ? .complete : .warning),
                    ("Boot files", "\(iso.bootFiles.count) marker files found", .complete),
                    ("WIM status", iso.windowsImageInfo?.requiresSplit == true ? "Split required" : "No split required", iso.windowsImageInfo?.requiresSplit == true ? .warning : .complete)
                ])
            }
            ErrorBanner(message: model.errorMessage)
        }
    }
}

private struct InsertUSBStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(icon: "externaldrive", title: "Select a removable USB drive", subtitle: "Internal disks are hidden and refused by the planning engine.")
            VStack(spacing: 10) {
                ForEach(model.drives) { drive in
                    Button {
                        model.selectedDrive = drive
                    } label: {
                        DriveRow(drive: drive, isSelected: model.selectedDrive == drive)
                    }
                    .buttonStyle(.plain)
                }
            }
            ErrorBanner(message: model.errorMessage)
        }
    }
}

private struct AnalyzeUSBStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(icon: "list.bullet.clipboard", title: "Review the operation plan", subtitle: "wInstaller plans every command as arguments and marks destructive steps explicitly.")
            if let plan = model.plan {
                PlanSummary(plan: plan)
            }
            ErrorBanner(message: model.errorMessage)
        }
    }
}

private struct ConfirmEraseStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(icon: "exclamationmark.triangle", title: "Confirm erase", subtitle: "Type the exact USB drive name to unlock the destructive operation.")
            if let drive = model.selectedDrive {
                VStack(alignment: .leading, spacing: 12) {
                    Label("All data on \(drive.displayName) will be erased.", systemImage: "exclamationmark.octagon.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.red)
                    Text("Identifier: \(drive.bsdIdentifier). Capacity: \(ByteCountFormatter.string(fromByteCount: drive.size, countStyle: .file)). Volumes: \(drive.volumes.joined(separator: ", ")).")
                    TextField("Type \(drive.displayName)", text: $model.confirmationText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 420)
                        .accessibilityLabel("Drive name confirmation")
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            ErrorBanner(message: model.errorMessage)
        }
    }
}

private struct CreateUSBStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(icon: "progress.indicator", title: "Create bootable USB", subtitle: "This build runs the checklist in dry-run mode. No destructive command is executed.")
            EventList(events: model.events)
            TechnicalDetails(model: model)
            ErrorBanner(message: model.errorMessage)
        }
    }
}

private struct DoneStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(icon: "checkmark.circle", title: "USB creation plan completed", subtitle: "The dry-run checklist completed and validation requirements are visible for the hardware integration pass.")
            EventList(events: model.events)
        }
    }
}

private struct VMwareStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(icon: "macwindow.on.rectangle", title: "Use with VMware Fusion", subtitle: "wInstaller does not create or start virtual machines without explicit user intent.")
            Checklist(rows: [
                ("Create a new VM", "Choose install from disc or image.", .waiting),
                ("Attach media", "Use the prepared USB or the selected ISO.", .waiting),
                ("Review settings", "Allocate memory, storage, and firmware mode.", .waiting),
                ("License reminder", "Windows may require a valid license.", .warning)
            ])
        }
    }
}

private struct ISOCard: View {
    var iso: InstallerISO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(iso.displayName, systemImage: "doc.circle")
                .font(.headline)
            LabeledContent("Detected OS", value: iso.detectedOS.displayName)
            LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: iso.size, countStyle: .file))
            LabeledContent("Volume", value: iso.volumeLabel ?? "Unknown")
            LabeledContent("Confidence", value: iso.confidence.rawValue.capitalized)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 520, alignment: .leading)
    }
}

private struct DriveRow: View {
    var drive: USBDrive
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(drive.displayName).font(.headline)
                Text("\(drive.bsdIdentifier) · \(ByteCountFormatter.string(fromByteCount: drive.size, countStyle: .file)) · \(drive.connectionType) · \(drive.fileSystem)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : Color.clear))
    }
}

private struct PlanSummary: View {
    var plan: OperationPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoGrid(items: [
                ("Target format", "\(plan.strategy.targetPartitionScheme) / \(plan.strategy.targetFileSystem)"),
                ("Authorization", plan.requiresAuthorization ? "Required" : "Not required"),
                ("Estimated copy", ByteCountFormatter.string(fromByteCount: plan.estimatedBytesToCopy, countStyle: .file)),
                ("WIM split", plan.strategy.requiresWIMSplit ? "Required" : "Not required")
            ])
            ForEach(plan.steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: step.command?.isDestructive == true ? "exclamationmark.triangle" : "terminal")
                        .foregroundStyle(step.command?.isDestructive == true ? .red : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title).font(.headline)
                        Text(step.detail).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
}

private struct InfoGrid: View {
    var items: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
            ForEach(items.indices, id: \.self) { index in
                GridRow {
                    Text(items[index].0)
                        .font(.headline)
                    Text(items[index].1)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct Checklist: View {
    var rows: [(String, String, ChecklistStatus)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    Image(systemName: symbol(for: rows[index].2))
                        .foregroundStyle(color(for: rows[index].2))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rows[index].0).font(.headline)
                        Text(rows[index].1).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func symbol(for status: ChecklistStatus) -> String {
        switch status {
        case .waiting: "circle"
        case .running: "progress.indicator"
        case .complete: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func color(for status: ChecklistStatus) -> Color {
        switch status {
        case .waiting: .secondary
        case .running: .accentColor
        case .complete: .green
        case .warning: .yellow
        case .failed: .red
        }
    }
}

private struct EventList: View {
    var events: [EngineEvent]

    var body: some View {
        Checklist(rows: events.map { ($0.title, $0.detail, $0.status) })
    }
}

private struct TechnicalDetails: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        DisclosureGroup(isExpanded: $model.showingTechnicalDetails) {
            if let plan = model.plan {
                Text(plan.steps.compactMap { step in
                    guard let command = step.command else { return nil }
                    return ([command.executable] + command.arguments).joined(separator: " ")
                }.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        } label: {
            Label("Technical details", systemImage: "chevron.left.forwardslash.chevron.right")
        }
    }
}

private struct ErrorBanner: View {
    var message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
