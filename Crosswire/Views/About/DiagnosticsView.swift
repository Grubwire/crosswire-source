//
//  DiagnosticsView.swift
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
import CrosswireKit

/// Shows technical state: app version, engine version, and beta channel state.
/// Present from the first release so bug reports include this info.
struct DiagnosticsView: View {
    /// Live beta-channel state. Same `@AppStorage` key the Settings toggle
    /// writes, so a channel flip is reflected here without a restart.
    @AppStorage(UpdateChannel.defaultsKey) private var betaChannel = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var engineState: CrosswireKit.InstalledEngineVersion? {
        CrosswireEngine.installedEngineState()
    }

    var body: some View {
        Form {
            Section("App") {
                DiagnosticRow(label: "Version", value: appVersion)
            }

            Section("Compatibility") {
                if let state = engineState {
                    DiagnosticRow(label: "Version", value: state.engineVersion)
                    DiagnosticRow(label: "Build", value: state.upstreamTag)
                } else {
                    DiagnosticRow(label: "Version", value: "Not installed")
                }
            }

            Section("Updates") {
                DiagnosticRow(label: "Beta channel", value: betaChannel ? "on" : "off")
            }

            Section("Paths") {
                DiagnosticRow(label: "Compatibility", value: CrosswireEngine.engineFolder.path)
                DiagnosticRow(label: "Libraries", value: CrosswireEngine.libraryFolder.path)
            }

            Section("Logs & support") {
                Button("Reveal Logs in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Wine.logsFolder.path)
                }
                Button("Copy Diagnostics") { copyDiagnostics() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 360)
        .navigationTitle("Diagnostics")
    }

    /// Copy the key version/path info to the clipboard so it can be pasted into
    /// a bug report — no telemetry, the user explicitly initiates and shares it.
    private func copyDiagnostics() {
        var lines = [
            "Crosswire \(appVersion)",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        ]
        if let state = engineState {
            lines.append("Engine \(state.engineVersion) (build \(state.upstreamTag))")
        } else {
            lines.append("Engine: not installed")
        }
        lines.append("Logs: \(Wine.logsFolder.path)")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

// MARK: - Supporting views

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}
