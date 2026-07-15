//
//  EntryDetailView.swift
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
import AppKit
import UniformTypeIdentifiers
import CrosswireKit

// swiftlint:disable type_body_length
/// Full-bleed inline per-entry detail shown when `AppRoute == .entryDetail`.
/// Slides in over the library (same pattern as inline Settings); the back
/// chevron returns. Replaces the old detached per-app settings sheet.
///
/// This is a transient overlay, so it sits on a `.regularMaterial` blur over
/// the library shell (materials-vs-hex rule). Launch + run-specific routes go
/// back out through ContentView's run helpers so single-instance handling
/// (Commit 6) applies uniformly.
struct EntryDetailView: View {
    @ObservedObject var bottle: Bottle
    var onBack: () -> Void
    var onRun: () -> Void
    var onRunProgram: (Program) -> Void
    var onUninstall: () -> Void
    /// Launch with full-lifetime diagnostics capture (Advanced › Maintenance).
    var onLaunchDiagnostics: () -> Void

    @State private var showRuntimesSheet: Bool = false
    @State private var isRenaming: Bool = false
    @State private var nameDraft: String = ""
    @State private var showAdvanced: Bool = false
    @State private var primarySelection: URL?
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            InlinePanelBackBar(action: onBack)
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    launchButton
                    secondaryActions
                    advancedDisclosure
                }
                .padding(28)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(.regularMaterial)
        .sheet(isPresented: $showRuntimesSheet) {
            CommonRuntimesView(bottle: bottle)
        }
        .onAppear {
            primarySelection = bottle.settings.primaryProgramURL
            if bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(spacing: 18) {
            AppIcon(bottle: bottle, side: 84)
            VStack(alignment: .leading, spacing: 5) {
                nameField
                Text(categoryLine)
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                Text(lastPlayedLine)
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textTertiary)
            }
            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CrosswireTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CrosswireTheme.surfaceStroke, lineWidth: 1)
        )
    }

    /// "Last played 2 hours ago" / "Never launched", for the hero subtitle.
    private var lastPlayedLine: String {
        guard let last = bottle.settings.lastLaunched else { return "Never launched" }
        return "Last played \(Self.relativeFormatter.localizedString(for: last, relativeTo: Date()))"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    @ViewBuilder
    private var nameField: some View {
        if isRenaming {
            TextField("App name", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CrosswireTheme.textPrimary)
                .focused($nameFieldFocused)
                .onSubmit { commitRename() }
                .onExitCommand { isRenaming = false }
                .frame(maxWidth: 360)
        } else {
            HStack(spacing: 8) {
                Text(bottle.displayName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CrosswireTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button(action: beginRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(CrosswireButtonStyle(kind: .plain, tint: CrosswireTheme.textSecondary))
                .help("Rename")
                .accessibilityLabel("Rename")
            }
        }
    }

    private var categoryLine: String {
        let count = bottle.userVisiblePrograms.count
        if count > 1 { return "Windows app · \(count) launchers" }
        return "Windows app"
    }

    // MARK: - Launch

    private var canLaunch: Bool {
        !bottle.programs.isEmpty && bottle.isAvailable
    }

    private var launchButton: some View {
        Button(action: onRun) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Launch")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .buttonStyle(PrimaryCTAButtonStyle(size: .prominent, fillWidth: true))
        .disabled(!canLaunch)
        .accessibilityLabel("Launch \(bottle.displayName)")
    }

    // MARK: - Secondary actions

    private var secondaryActions: some View {
        HStack(spacing: 10) {
            secondaryButton("Check Dependencies", systemImage: "shippingbox") {
                showRuntimesSheet = true
            }
            secondaryButton("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
            }
            secondaryButton("Uninstall", systemImage: "trash", destructive: true) {
                onUninstall()
            }
        }
    }

    @ViewBuilder
    private func secondaryButton(
        _ title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
        }
        .buttonStyle(CrosswireButtonStyle(kind: destructive ? .destructive : .secondary, fillWidth: true))
        .accessibilityLabel(title)
    }

    // MARK: - Advanced

    @ViewBuilder
    private var advancedDisclosure: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 16) {
                advancedConfiguration
                advancedApps
                advancedMaintenance
            }
            .padding(.top, 12)
        } label: {
            Text("Advanced")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CrosswireTheme.textPrimary)
        }
        .tint(CrosswireTheme.accent)
    }

    @ViewBuilder
    private var advancedConfiguration: some View {
        advancedHeader("Configuration")
        HStack {
            Text("Windows version")
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Spacer()
            Picker("", selection: $bottle.settings.windowsVersion) {
                ForEach(WinVersion.allCases.reversed(), id: \.self) {
                    Text($0.pretty()).tag($0)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)
        }
        Toggle("DXVK (DirectX to Vulkan)", isOn: $bottle.settings.dxvk)
            .tint(CrosswireTheme.accent)
            .font(CrosswireTheme.Typography.body)
            .foregroundStyle(CrosswireTheme.textPrimary)
        Toggle("Allow multiple instances", isOn: $bottle.settings.allowMultipleInstances)
            .tint(CrosswireTheme.accent)
            .font(CrosswireTheme.Typography.body)
            .foregroundStyle(CrosswireTheme.textPrimary)
        VStack(alignment: .leading, spacing: 4) {
            Text("Installed at")
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Text(bottle.url.prettyPath())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(CrosswireTheme.textSecondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var advancedApps: some View {
        advancedHeader("Apps")
        HStack {
            Text("Primary launcher")
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Spacer()
            Picker("", selection: $primarySelection) {
                Text("None").tag(URL?.none)
                ForEach(bottle.programs) { program in
                    Text(program.name.replacingOccurrences(of: ".exe", with: ""))
                        .tag(Optional(program.url))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            .onChange(of: primarySelection) { _, newValue in
                bottle.settings.primaryProgramURL = newValue
            }
        }
        if !bottle.programs.isEmpty {
            DisclosureGroup("All installed programs (\(bottle.programs.count))") {
                ForEach(bottle.programs) { program in
                    HStack {
                        Text(program.name.replacingOccurrences(of: ".exe", with: ""))
                            .font(CrosswireTheme.Typography.body)
                            .foregroundStyle(CrosswireTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Run") { onRunProgram(program) }
                            .buttonStyle(CrosswireButtonStyle(kind: .secondary))
                    }
                }
            }
            .tint(CrosswireTheme.accent)
        }
    }

    @ViewBuilder
    private var advancedMaintenance: some View {
        advancedHeader("Maintenance")
        maintenanceRow("stethoscope", "Launch with Diagnostics…") {
            onLaunchDiagnostics()
        }
        maintenanceRow("arrow.clockwise", "Rescan installed programs") {
            bottle.finalizeAppIdentity()
        }
        maintenanceRow("terminal", "Open Terminal") {
            bottle.openTerminal()
        }
        maintenanceRow("play.square", "Run a .exe inside this app…") {
            pickAdHocExecutable()
        }
    }

    @ViewBuilder
    private func advancedHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(CrosswireTheme.textTertiary)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func maintenanceRow(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
        }
        .buttonStyle(CrosswireButtonStyle(kind: .plain, fillWidth: true))
        .accessibilityLabel(title)
    }

    // MARK: - Actions

    private func beginRename() {
        nameDraft = bottle.displayName
        isRenaming = true
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    private func commitRename() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenaming = false
        if trimmed.isEmpty {
            bottle.settings.appDisplayName = nil
        } else if trimmed != bottle.displayName {
            bottle.settings.appDisplayName = trimmed
        }
    }

    private func pickAdHocExecutable() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.exe,
            UTType(exportedAs: "com.microsoft.msi-installer"),
            UTType(exportedAs: "com.microsoft.bat")
        ]
        panel.directoryURL = bottle.url.appending(path: "drive_c")
        panel.begin { result in
            guard result == .OK, let url = panel.urls.first else { return }
            Task { @MainActor in
                await JavaAppDetector.applyDefaultsIfNeeded(forExeAt: url, in: bottle)
                do {
                    if url.pathExtension == "bat" {
                        try await Wine.runBatchFile(url: url, bottle: bottle)
                    } else {
                        try await Wine.runProgram(at: url, bottle: bottle)
                    }
                } catch {
                    print("Failed to run ad-hoc program: \(error)")
                }
                bottle.updateInstalledPrograms()
            }
        }
    }
}
// swiftlint:enable type_body_length
