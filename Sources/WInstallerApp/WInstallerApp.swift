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
                .frame(minWidth: 1000, minHeight: 700)
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

struct AssistantRootView: View {
    @StateObject private var model = AssistantModel()

    var body: some View {
        NavigationSplitView {
            StepSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(Space.xxl)
                }
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

                    if let helpURL = URL(string: "https://developer.apple.com/design/human-interface-guidelines") {
                        Link(destination: helpURL) {
                            Label("Help", systemImage: "questionmark.circle")
                        }
                        .help("Open the design and usage guidelines")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $model.showingFileImporter,
            allowedContentTypes: [.diskImage],
            allowsMultipleSelection: false
        ) { result in
            model.importISO(result: result.map { $0 })
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
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
        .transition(.opacity)
        .animation(.smooth(duration: 0.25), value: model.step)
    }
}

struct FooterBar: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        HStack(spacing: Space.md) {
            Label("Local only. No telemetry. No disk changes until confirmation.", systemImage: "lock.shield")
                .foregroundStyle(.secondary)
                .font(.callout)
            Spacer()
            Button("Back") { model.goBack() }
                .disabled(model.step == .welcome || model.step.rawValue >= AssistantModel.Step.createUSB.rawValue)
            Button(primaryTitle) { model.continueFlow() }
                .primaryGlassButton()
                .disabled(!model.canContinue)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.md)
    }

    private var primaryTitle: String {
        switch model.step {
        case .confirmErase: model.simulateMode ? "Simulate Bootable USB" : "Erase and Create Bootable USB"
        case .createUSB: model.isRunning ? "Working…" : "Continue"
        case .done: "Open VMware Instructions"
        case .vmware: "Create Another USB"
        default: "Continue"
        }
    }
}

#if DEBUG
#Preview("Welcome") {
    AssistantRootView()
        .frame(width: 1000, height: 700)
}
#endif
