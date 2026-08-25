//
//  EntryDetailAdvancedSection.swift
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

/// The "Advanced" disclosure inside the per-entry detail view: configuration,
/// the app list, and maintenance actions.
///
/// A real child view rather than an extension on `EntryDetailView` for two
/// reasons: the disclosure's own `showAdvanced` and `primarySelection` state
/// belongs with the section that uses it, and `private` members cannot cross
/// files in an extension anyway. Splitting it also lets `EntryDetailView` drop
/// its `type_body_length` exemption.
struct EntryDetailAdvancedSection: View {
    @ObservedObject var bottle: Bottle
    var onRunProgram: (Program) -> Void
    /// Launch with full-lifetime diagnostics capture.
    var onLaunchDiagnostics: () -> Void

    @State private var isExpanded: Bool = false
    @State private var primarySelection: URL?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                configuration
                apps
                maintenance
            }
            .padding(.top, 12)
        } label: {
            Text("Advanced")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CrosswireTheme.textPrimary)
        }
        .tint(CrosswireTheme.accent)
        .onAppear { primarySelection = bottle.settings.primaryProgramURL }
    }

    // MARK: - Configuration

    @ViewBuilder
    private var configuration: some View {
        header("Configuration")
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

    // MARK: - Apps

    @ViewBuilder
    private var apps: some View {
        header("Apps")
        HStack {
            Text("Primary launcher")
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Spacer()
            Picker("", selection: $primarySelection) {
                Text("None").tag(URL?.none)
                ForEach(bottle.programs) { program in
                    Text(program.displayName).tag(Optional(program.url))
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
                        Text(program.displayName)
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

    // MARK: - Maintenance

    @ViewBuilder
    private var maintenance: some View {
        header("Maintenance")
        maintenanceRow("stethoscope", "Launch with Diagnostics…") { onLaunchDiagnostics() }
        maintenanceRow("arrow.clockwise", "Rescan installed programs") { bottle.finalizeAppIdentity() }
        maintenanceRow("terminal", "Open Terminal") { bottle.openTerminal() }
        maintenanceRow("play.square", "Run a .exe inside this app…") { pickAdHocExecutable() }
    }

    @ViewBuilder
    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(CrosswireTheme.textTertiary)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func maintenanceRow(_ systemImage: String,
                                _ title: String,
                                action: @escaping () -> Void) -> some View {
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
