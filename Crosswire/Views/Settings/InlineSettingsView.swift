//
//  InlineSettingsView.swift
//  Crosswire
//
//  This file is part of Crosswire.
//
//  Crosswire is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Crosswire is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Crosswire.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import Sparkle
import CrosswireKit
import AppKit

/// Full-bleed inline settings view shown when `AppRoute == .settings`. Slides
/// in over the library and exits via the shared "‹ Library" back bar — the
/// same navigation affordance as the per-app detail view (these are inline
/// destinations, not modal dialogs). Left sidebar with section nav + version
/// chip; right content pane where every section flows into one shared layout.
struct InlineSettingsView: View {
    let updater: SPUUpdater?
    var onDone: () -> Void

    // Optional to satisfy `List(selection:)` single-selection binding. nil is
    // treated as `.general` when resolving content.
    @State private var selectedSection: SettingsSection? = .general

    /// One layout frame shared by every pane so switching sections never makes
    /// the title or content jump (identical insets + rhythm).
    private enum PaneLayout {
        static let leftInset: CGFloat = 28
        static let topInset: CGFloat = 24
        static let rhythm: CGFloat = 16
        static let maxWidth: CGFloat = 480
    }

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case updates = "Updates"
        case privacy = "Privacy"
        case advanced = "Advanced"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .updates: return "arrow.triangle.2.circlepath"
            case .privacy: return "lock.shield"
            case .advanced: return "wrench.adjustable"
            case .about: return "info.circle"
            }
        }
    }

    init(updater: SPUUpdater? = nil, onDone: @escaping () -> Void) {
        self.updater = updater
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            InlinePanelBackBar(action: onDone)
            Divider().opacity(0.3)
            HStack(spacing: 0) {
                sidebar
                Divider().opacity(0.3)
                content
            }
        }
        // Transient overlay → material blur over the library shell, per the
        // materials-vs-branded-hex rule.
        .background(.regularMaterial)
    }

    // MARK: - Sidebar

    /// "SETTINGS" label, native section List, and the version chip pinned
    /// bottom-left. Native `.sidebar` selection renders the on-brand blue pill.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .cwSectionHeader()
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)
            List(selection: $selectedSection) {
                // `id: \.self` so each row's selection identity is the
                // `SettingsSection` value itself, matching the binding.
                ForEach(SettingsSection.allCases, id: \.self) { section in
                    Label {
                        Text(section.rawValue)
                            .font(CrosswireTheme.Typography.body)
                    } icon: {
                        Image(systemName: section.icon)
                            .font(.system(size: 13, weight: .regular))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Text(versionString)
                .font(CrosswireTheme.Typography.entryMeta)
                .foregroundStyle(CrosswireTheme.textTertiary)
                .textSelection(.enabled)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .frame(width: 200)
    }

    // MARK: - Content pane

    @ViewBuilder
    private var content: some View {
        ScrollView {
            switch selectedSection ?? .general {
            case .general:  settingsPane("General") { SettingsGeneralGroup() }
            case .updates:  settingsPane("Updates") { SettingsUpdatesGroup(updater: updater) }
            case .privacy:  settingsPane("Privacy") { SettingsPrivacyGroup() }
            case .advanced: settingsPane("Advanced") { SettingsAdvancedGroup() }
            case .about:    settingsPane("About") { SettingsAboutGroup() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The one content-layout container every pane flows into.
    @ViewBuilder
    private func settingsPane(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: PaneLayout.rhythm) {
            Text(title)
                .font(CrosswireTheme.Typography.title)
                .foregroundStyle(CrosswireTheme.textPrimary)
            content()
        }
        .frame(maxWidth: PaneLayout.maxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, PaneLayout.leftInset)
        .padding(.trailing, 24)
        .padding(.top, PaneLayout.topInset)
        .padding(.bottom, 24)
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "v\(short)" : "v\(short) (\(build))"
    }
}

// MARK: - Group views

/// General settings: quit-on-terminate behavior and the app-data location
/// (a labeled section — no sub-card; "Show in Finder" reveals the path).
struct SettingsGeneralGroup: View {
    @AppStorage("killOnTerminate") var killOnTerminate = true
    @AppStorage("defaultBottleLocation") var defaultBottleLocation = BottleData.defaultBottleDir

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Quit running apps when Crosswire quits", isOn: $killOnTerminate)
                .tint(CrosswireTheme.accent)
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            VStack(alignment: .leading, spacing: 8) {
                Text("App Data Location")
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Text("Where your installed apps and their files are kept.")
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                HStack(spacing: 8) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([defaultBottleLocation])
                    }
                    .buttonStyle(CrosswireButtonStyle(kind: .secondary))
                    Button("Change…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = true
                        panel.directoryURL = BottleData.containerDir
                        panel.begin { result in
                            if result == .OK, let url = panel.urls.first {
                                defaultBottleLocation = url
                            }
                        }
                    }
                    .buttonStyle(CrosswireButtonStyle(kind: .secondary))
                }
                .padding(.top, 2)
            }
        }
    }
}

/// About panel: app icon, name, version, and external links. The engine
/// version is intentionally NOT shown — the app surfaces no user-facing
/// engine/version strings (project naming rule).
struct SettingsAboutGroup: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Crosswire")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CrosswireTheme.textPrimary)
                    Text(appVersionString)
                        .font(CrosswireTheme.Typography.body)
                        .foregroundStyle(CrosswireTheme.textSecondary)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                aboutLink("Source Code", "https://github.com/Grubwire/crosswire-source")
                aboutLink("Crosswire Website", "https://grubwire.io")
                aboutLink("Report an Issue", "https://github.com/Grubwire/crosswire-source/issues")
            }
        }
    }

    @ViewBuilder
    private func aboutLink(_ title: String, _ urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) { openURL(url) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                Text(title)
            }
        }
        .buttonStyle(CrosswireButtonStyle(kind: .plain, tint: CrosswireTheme.accent))
        .accessibilityLabel(title)
    }

    private var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(short)" : "Version \(short) (\(build))"
    }
}

/// Privacy: the crash-reporting opt-in. Off by default; drives whether Sentry
/// initializes (along with a configured DSN — see `CrosswireTelemetry`). Honest
/// copy about what is and isn't collected.
struct SettingsPrivacyGroup: View {
    @AppStorage(CrosswireTelemetry.enabledDefaultsKey) private var crashReporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Send anonymous crash reports", isOn: $crashReporting)
                .tint(CrosswireTheme.accent)
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
                .disabled(!CrosswireTelemetry.isConfigured)
            Text(bodyText)
                .font(CrosswireTheme.Typography.entryMeta)
                .foregroundStyle(CrosswireTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bodyText: String {
        let base = "Off by default. When on, Crosswire sends anonymized reports about "
            + "crashes and errors in the app itself — never your installed apps, your "
            + "files, or your account details."
        return CrosswireTelemetry.isConfigured
            ? base
            : base + "\n\nCrash reporting isn’t configured in this build."
    }
}

/// Advanced: power-user maintenance actions (the same ones the menu bar exposes,
/// surfaced here for discoverability).
struct SettingsAdvancedGroup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionRow("Open Diagnostics", "stethoscope") { CrosswireApp.openDiagnosticsWindow() }
            actionRow("Reveal Logs in Finder", "doc.text.magnifyingglass") { CrosswireApp.openLogsFolder() }
            actionRow("Quit All Running Apps", "stop.circle") { CrosswireApp.killBottles() }
            actionRow("Clear Shader Caches", "trash") {
                CrosswireApp.killBottles()
                CrosswireApp.wipeShaderCaches()
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 16)
                Text(title)
                Spacer()
            }
        }
        .buttonStyle(CrosswireButtonStyle(kind: .secondary, fillWidth: true))
        .accessibilityLabel(title)
    }
}
