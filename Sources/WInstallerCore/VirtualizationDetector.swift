import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// A virtualization application wInstaller can hand off to.
public struct VirtualizationTarget: Equatable, Sendable {
    public var name: String
    public var bundleIdentifier: String
    public var knownPath: String

    public init(name: String, bundleIdentifier: String, knownPath: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.knownPath = knownPath
    }

    public static let vmwareFusion = VirtualizationTarget(
        name: "VMware Fusion",
        bundleIdentifier: "com.vmware.fusion",
        knownPath: "/Applications/VMware Fusion.app"
    )
    public static let utm = VirtualizationTarget(
        name: "UTM",
        bundleIdentifier: "com.utmapp.UTM",
        knownPath: "/Applications/UTM.app"
    )
    public static let parallels = VirtualizationTarget(
        name: "Parallels Desktop",
        bundleIdentifier: "com.parallels.desktop.console",
        knownPath: "/Applications/Parallels Desktop.app"
    )
    public static let virtualBuddy = VirtualizationTarget(
        name: "VirtualBuddy",
        bundleIdentifier: "codes.rambo.VirtualBuddy",
        knownPath: "/Applications/VirtualBuddy.app"
    )

    public static let all: [VirtualizationTarget] = [vmwareFusion, utm, parallels, virtualBuddy]
}

/// The detected state of a virtualization app (`REQ-VM-001..004`).
public struct VirtualizationApp: Identifiable, Equatable, Sendable {
    public var target: VirtualizationTarget
    public var isInstalled: Bool
    public var url: URL?
    public var version: String?

    public var id: String { target.bundleIdentifier }
    public var name: String { target.name }

    public init(target: VirtualizationTarget, isInstalled: Bool, url: URL?, version: String?) {
        self.target = target
        self.isInstalled = isInstalled
        self.url = url
        self.version = version
    }
}

/// Locates applications and reads their versions. Injectable so detection logic
/// can be tested without a real LaunchServices database.
public protocol ApplicationLocating: Sendable {
    func url(forBundleIdentifier identifier: String) -> URL?
    func fileExists(atPath path: String) -> Bool
    func shortVersion(forBundleAt url: URL) -> String?
}

/// Detects virtualization apps via bundle identifier lookup, falling back to the
/// documented install path. Detection is tolerant: an app may live outside
/// `/Applications`, and bundle identifiers are verified at runtime.
public struct VirtualizationDetector: Sendable {
    private let locator: ApplicationLocating

    public init(locator: ApplicationLocating = SystemApplicationLocator()) {
        self.locator = locator
    }

    public func detect(_ target: VirtualizationTarget) -> VirtualizationApp {
        let resolved = locator.url(forBundleIdentifier: target.bundleIdentifier)
            ?? (locator.fileExists(atPath: target.knownPath) ? URL(fileURLWithPath: target.knownPath) : nil)

        guard let resolved else {
            return VirtualizationApp(target: target, isInstalled: false, url: nil, version: nil)
        }
        return VirtualizationApp(
            target: target,
            isInstalled: true,
            url: resolved,
            version: locator.shortVersion(forBundleAt: resolved)
        )
    }

    public func detectAll() -> [VirtualizationApp] {
        VirtualizationTarget.all.map(detect)
    }

    /// Convenience for the primary handoff target.
    public func detectVMwareFusion() -> VirtualizationApp {
        detect(.vmwareFusion)
    }

    #if canImport(AppKit)
    /// Opens the app. Never starts or configures a VM (`REQ-VM-004`).
    @MainActor
    public func open(_ app: VirtualizationApp) {
        guard let url = app.url else { return }
        NSWorkspace.shared.open(url)
    }
    #endif
}

/// Real locator backed by `NSWorkspace` + `Bundle`.
public struct SystemApplicationLocator: ApplicationLocating {
    public init() {}

    public func url(forBundleIdentifier identifier: String) -> URL? {
        #if canImport(AppKit)
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        #else
        return nil
        #endif
    }

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func shortVersion(forBundleAt url: URL) -> String? {
        Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
