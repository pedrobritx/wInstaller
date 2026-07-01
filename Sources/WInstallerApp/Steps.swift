import SwiftUI
import WInstallerCore

struct WelcomeStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            StepHeader(
                icon: "externaldrive.connected.to.line.below",
                title: "Create a bootable installer USB",
                subtitle: "wInstaller guides ISO selection, USB verification, erase confirmation, copy planning, validation, and VMware handoff."
            )
            InfoGrid(items: [
                ("ISO file", "Choose Windows or Linux installation media."),
                ("USB drive", "Use removable media with enough capacity."),
                ("Confirmation", "Erase is blocked until the drive name is typed."),
                ("Local only", "Every operation runs on this Mac. No uploads.")
            ])
            ErrorBanner(message: model.errorMessage)
        }
    }
}

struct ChooseISOStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            StepHeader(
                icon: "opticaldisc",
                title: "Choose an ISO file",
                subtitle: "Select installation media. The importer rejects non-ISO files, then wInstaller mounts it read-only to analyze."
            )
            HStack(spacing: Space.md) {
                Button {
                    model.showingFileImporter = true
                } label: {
                    Label("Choose ISO", systemImage: "folder")
                }
                .primaryGlassButton()
                .disabled(model.isInspectingISO)

                #if DEBUG
                Button {
                    model.loadSampleISO()
                } label: {
                    Label("Use Sample", systemImage: "play.circle")
                }
                .secondaryGlassButton()
                #endif

                if model.isInspectingISO {
                    ProgressView().controlSize(.small)
                    Text("Mounting and analyzing…").foregroundStyle(.secondary)
                }
            }
            if let iso = model.iso {
                ISOCard(iso: iso)
            }
            ErrorBanner(message: model.errorMessage)
        }
    }
}

struct VerifyISOStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            StepHeader(
                icon: "checkmark.seal",
                title: "Verify the installer",
                subtitle: "wInstaller explains what it detected before a USB drive is selected."
            )
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

struct InsertUSBStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack(alignment: .top) {
                StepHeader(
                    icon: "cable.connector",
                    title: "Select a removable USB drive",
                    subtitle: "Internal disks are hidden and refused by the planning engine."
                )
                Spacer()
                Button {
                    model.refreshDrives()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .secondaryGlassButton()
                .disabled(model.isRefreshingDrives)
            }

            if model.isRefreshingDrives && model.drives.isEmpty {
                HStack(spacing: Space.md) {
                    ProgressView().controlSize(.small)
                    Text("Looking for removable drives…").foregroundStyle(.secondary)
                }
            } else if model.drives.isEmpty {
                EmptyStateCard(
                    icon: "externaldrive.badge.questionmark",
                    title: "Connect a removable USB drive",
                    message: "Plug in a USB drive, then choose Refresh. Internal disks are never shown."
                )
            } else {
                VStack(spacing: Space.md) {
                    ForEach(model.drives) { drive in
                        Button {
                            model.selectedDrive = drive
                        } label: {
                            DriveRow(drive: drive, isSelected: model.selectedDrive == drive)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            ErrorBanner(message: model.errorMessage)
        }
    }
}

struct AnalyzeUSBStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            StepHeader(
                icon: "list.bullet.clipboard",
                title: "Review the operation plan",
                subtitle: "wInstaller plans every command as arguments and marks destructive steps explicitly."
            )
            if let plan = model.plan {
                PlanSummary(plan: plan)
            }
            ErrorBanner(message: model.errorMessage)
        }
    }
}

struct ConfirmEraseStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            StepHeader(
                icon: "exclamationmark.triangle",
                title: "Confirm erase",
                subtitle: "Type the exact USB drive name to unlock the destructive operation."
            )
            if let drive = model.selectedDrive {
                VStack(alignment: .leading, spacing: Space.md) {
                    Label("All data on \(drive.displayName) will be erased.", systemImage: "exclamationmark.octagon.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Identifier: \(drive.bsdIdentifier) · Capacity: \(ByteCountFormatter.string(fromByteCount: drive.size, countStyle: .file)) · Volumes: \(drive.volumes.isEmpty ? "none" : drive.volumes.joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("Type \(drive.displayName)", text: $model.confirmationText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 420)
                        .accessibilityLabel("Drive name confirmation")
                    Toggle(isOn: $model.simulateMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simulate (dry-run)").font(.callout.weight(.medium))
                            Text("Run the full sequence without erasing anything.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(tint: .red)
            }
            ErrorBanner(message: model.errorMessage)
        }
    }
}

struct CreateUSBStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            StepHeader(
                icon: "gearshape.2",
                title: model.simulateMode ? "Simulating USB creation" : "Creating bootable USB",
                subtitle: model.simulateMode
                    ? "Dry-run mode: wInstaller runs the full checklist without executing any destructive command."
                    : "wInstaller is preparing the drive, copying files, and validating boot media."
            )
            EventList(events: model.events)
            if model.isRunning {
                Button(role: .cancel) {
                    model.cancel()
                } label: {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .secondaryGlassButton()
            }
            TechnicalDetails(model: model)
            ErrorBanner(message: model.errorMessage)
        }
    }
}

struct DoneStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            StepHeader(
                icon: "checkmark.circle",
                title: model.simulateMode ? "Dry run completed" : "Bootable USB is ready",
                subtitle: model.simulateMode
                    ? "The simulated checklist completed. Turn off Simulate to create real media."
                    : "The installer USB was created, validated, and safely ejected."
            )
            EventList(events: model.events)
            TechnicalDetails(model: model)
        }
    }
}

struct VMwareStep: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            StepHeader(
                icon: "macwindow.on.rectangle",
                title: "Use with VMware Fusion",
                subtitle: "wInstaller does not create or start virtual machines without explicit user intent."
            )

            if let fusion = model.vmwareFusion, fusion.isInstalled {
                VStack(alignment: .leading, spacing: Space.md) {
                    Label("VMware Fusion detected", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    if let version = fusion.version {
                        Text("Version \(version)").foregroundStyle(.secondary)
                    }
                    Button {
                        model.openVMware()
                    } label: {
                        Label("Open VMware Fusion", systemImage: "arrow.up.forward.app")
                    }
                    .primaryGlassButton()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            } else {
                EmptyStateCard(
                    icon: "macwindow",
                    title: "VMware Fusion is not installed on this Mac",
                    message: "You can still use the USB you created. Install VMware Fusion or another virtualization app to continue in a VM."
                )
            }

            Checklist(rows: [
                ("Create a new VM", "Choose install from disc or image.", .waiting),
                ("Attach media", "Use the prepared USB or the selected ISO.", .waiting),
                ("Review settings", "Allocate memory, storage, and firmware mode.", .waiting),
                ("License reminder", "Windows may require a valid license.", .warning)
            ])

            if otherApps.isEmpty == false {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Also detected").font(.headline)
                    ForEach(otherApps) { app in
                        Label(app.name, systemImage: "app.badge.checkmark")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var otherApps: [VirtualizationApp] {
        model.vmwareApps.filter { $0.isInstalled && $0.id != VirtualizationTarget.vmwareFusion.bundleIdentifier }
    }
}

// MARK: - Shared empty state

struct EmptyStateCard: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
