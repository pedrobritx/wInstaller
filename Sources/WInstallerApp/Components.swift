import SwiftUI
import WInstallerCore

// MARK: - Step sidebar

struct StepSidebar: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(AssistantModel.Step.allCases) { step in
                    StepSidebarRow(
                        step: step,
                        state: state(for: step),
                        isLast: step == AssistantModel.Step.allCases.last
                    )
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.lg)
        }
        .navigationTitle("wInstaller")
    }

    private func state(for step: AssistantModel.Step) -> StepSidebarRow.State {
        if step.rawValue < model.step.rawValue { return .complete }
        if step == model.step { return .current }
        return .pending
    }
}

private struct StepSidebarRow: View {
    enum State { case pending, current, complete }

    let step: AssistantModel.Step
    let state: State
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            VStack(spacing: 0) {
                marker
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(step.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(state == .pending ? .secondary : .primary)
            }
            .padding(.bottom, Space.md)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.sm)
        .background {
            if state == .current {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(step.rawValue), \(step.title)")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var marker: some View {
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: 28, height: 28)
            switch state {
            case .complete:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            case .current:
                Text("\(step.rawValue)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            case .pending:
                Text("\(step.rawValue)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fill: Color {
        switch state {
        case .complete: .green
        case .current: .accentColor
        case .pending: Color.secondary.opacity(0.15)
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .complete: "completed"
        case .current: "current step"
        case .pending: "not started"
        }
    }
}

// MARK: - Step header

struct StepHeader: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .glassChip()
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - ISO card

struct ISOCard: View {
    var iso: InstallerISO

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label(iso.displayName, systemImage: "opticaldisc")
                .font(.headline)
            LabeledContent("Detected OS", value: iso.detectedOS.displayName)
            LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: iso.size, countStyle: .file))
            LabeledContent("Volume", value: iso.volumeLabel ?? "Unknown")
            LabeledContent("Confidence", value: iso.confidence.rawValue.capitalized)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .glassCard()
    }
}

// MARK: - Drive row

struct DriveRow: View {
    var drive: USBDrive
    var isSelected: Bool

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            Image(systemName: "externaldrive")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(drive.displayName).font(.headline)
                Text("\(drive.bsdIdentifier) · \(ByteCountFormatter.string(fromByteCount: drive.size, countStyle: .file)) · \(drive.connectionType) · \(drive.fileSystem)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: isSelected ? Color.accentColor : nil)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(drive.displayName), \(ByteCountFormatter.string(fromByteCount: drive.size, countStyle: .file))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Checklist

struct Checklist: View {
    var rows: [(String, String, ChecklistStatus)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: Space.md) {
                    StatusIcon(status: rows[index].2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rows[index].0).font(.headline)
                        Text(rows[index].1).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(rows[index].0), \(rows[index].2.accessibilityText): \(rows[index].1)")
            }
        }
    }
}

struct StatusIcon: View {
    var status: ChecklistStatus

    var body: some View {
        Group {
            if status == .running {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(color)
            }
        }
        .frame(width: 22, height: 22)
    }

    private var symbol: String {
        switch status {
        case .waiting: "circle"
        case .running: "circle"
        case .complete: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch status {
        case .waiting: .secondary
        case .running: .accentColor
        case .complete: .green
        case .warning: .yellow
        case .failed: .red
        }
    }
}

extension ChecklistStatus {
    var accessibilityText: String {
        switch self {
        case .waiting: "waiting"
        case .running: "in progress"
        case .complete: "complete"
        case .warning: "warning"
        case .failed: "failed"
        }
    }
}

struct EventList: View {
    var events: [EngineEvent]

    var body: some View {
        Checklist(rows: events.map { ($0.title, $0.detail, $0.status) })
    }
}

// MARK: - Plan summary

struct PlanSummary: View {
    var plan: OperationPlan

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            InfoGrid(items: [
                ("Target format", "\(plan.strategy.targetPartitionScheme) / \(plan.strategy.targetFileSystem)"),
                ("Authorization", plan.requiresAuthorization ? "Required" : "Not required"),
                ("Estimated copy", ByteCountFormatter.string(fromByteCount: plan.estimatedBytesToCopy, countStyle: .file)),
                ("WIM split", plan.strategy.requiresWIMSplit ? "Required" : "Not required")
            ])

            if !plan.strategy.warnings.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(plan.strategy.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(plan.steps) { step in
                    HStack(alignment: .top, spacing: Space.md) {
                        Image(systemName: step.command?.isDestructive == true ? "exclamationmark.triangle.fill" : "terminal")
                            .foregroundStyle(step.command?.isDestructive == true ? .red : .secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title).font(.headline)
                            Text(step.detail).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

// MARK: - Info grid

struct InfoGrid: View {
    var items: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.xl, verticalSpacing: Space.md) {
            ForEach(items.indices, id: \.self) { index in
                GridRow {
                    Text(items[index].0)
                        .font(.headline)
                    Text(items[index].1)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassCard()
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    var message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(tint: .red)
                .accessibilityLabel("Error: \(message)")
        }
    }
}

// MARK: - Technical details

struct TechnicalDetails: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        DisclosureGroup(isExpanded: $model.showingTechnicalDetails) {
            VStack(alignment: .leading, spacing: Space.md) {
                if !model.commandLog.isEmpty {
                    logText(model.commandLog)
                } else if let plan = model.plan {
                    logText(plannedText(plan))
                }
                HStack(spacing: Space.md) {
                    Button {
                        copyToPasteboard(currentText)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button {
                        exportLog(currentText)
                    } label: {
                        Label("Export Log", systemImage: "square.and.arrow.up")
                    }
                }
                .font(.callout)
            }
            .padding(.top, Space.sm)
        } label: {
            Label("Technical details", systemImage: "chevron.left.forwardslash.chevron.right")
        }
    }

    private var currentText: String {
        if !model.commandLog.isEmpty { return model.commandLog }
        if let plan = model.plan { return plannedText(plan) }
        return ""
    }

    private func logText(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.md)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func plannedText(_ plan: OperationPlan) -> String {
        plan.steps.compactMap { step in
            guard let command = step.command else { return nil }
            return ([command.executable] + command.arguments).joined(separator: " ")
        }.joined(separator: "\n")
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func exportLog(_ text: String) {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "winstaller-log.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? text.data(using: .utf8)?.write(to: url)
        }
        #endif
    }
}
