//
//  FailureWatcher.swift
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

import AppKit
import CrosswireKit
import Combine

/// Watches `Notification.Name.crosswireProgramDidExit` and routes abnormal guest
/// exits (game / engine crashes) through the consent-gated reporter
/// (`CrosswireTelemetry`). Lives for the lifetime of the app — instantiate once
/// in the App body.
///
/// Behaviour rules:
/// - Trigger only on abnormal exits (currently `exitCode != 0`).
/// - Respect the user's reporting mode:
///     • `.always` — capture silently (no interruption; the user already saw the
///       game vanish).
///     • `.ask`    — present a per-incident dialog; never send without an explicit
///       click. The user can review exactly what's included first.
///     • `.never`  — do nothing.
/// - Don't double-fire: one dialog per exit event.
/// - De-noise repeated rapid failures of the same exe (rate-limit).
@MainActor
final class FailureWatcher: ObservableObject {
    private var cancellable: AnyCancellable?
    /// Most recent report handled, keyed by exe URL — used to debounce.
    private var lastShownByExe: [URL: Date] = [:]
    private let debounceWindow: TimeInterval = 30

    init() {
        cancellable = NotificationCenter.default
            .publisher(for: .crosswireProgramDidExit)
            .sink { [weak self] note in
                guard let report = note.object as? ProgramRunReport else { return }
                Task { @MainActor in self?.handle(report) }
            }
    }

    private func handle(_ report: ProgramRunReport) {
        guard report.isAbnormal else { return }
        if let last = lastShownByExe[report.executableURL],
           Date().timeIntervalSince(last) < debounceWindow {
            return
        }
        lastShownByExe[report.executableURL] = Date()

        switch CrosswireTelemetry.mode {
        case .always:
            CrosswireTelemetry.captureFailure(report, consented: true)
        case .ask:
            present(report)
        case .never:
            break
        }
    }

    /// Per-incident consent dialog (`.ask` mode). Loops so "View Details" can show
    /// the scrubbed report and return the user to the Send / Not Now choice.
    private func present(_ report: ProgramRunReport) {
        let exeName = report.executableURL.deletingPathExtension().lastPathComponent
        while true {
            let alert = NSAlert()
            alert.messageText = "\(exeName) stopped unexpectedly"
            alert.informativeText = informativeBody(for: report)
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Send Report")
            alert.addButton(withTitle: "View Details")
            alert.addButton(withTitle: "Not Now")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Always send reports automatically"

            let response = alert.runModal()
            let always = alert.suppressionButton?.state == .on
            switch response {
            case .alertFirstButtonReturn:
                if always { CrosswireTelemetry.mode = .always }
                CrosswireTelemetry.captureFailure(report, consented: true)
                return
            case .alertSecondButtonReturn:
                showDetails(for: report)
                continue
            default:
                return
            }
        }
    }

    private func informativeBody(for report: ProgramRunReport) -> String {
        var lines: [String] = []
        lines.append("App: \(report.bottleDisplayName)")
        lines.append("Exit code: \(report.exitCode)")
        if report.duration < 5 {
            lines.append("Exited \(String(format: "%.1f", report.duration))s after launch — likely a crash on startup.")
        } else {
            lines.append("Ran for \(formatDuration(report.duration)).")
        }
        lines.append("")
        lines.append("The report includes the run log, version information, and that "
                     + "app's settings, with your username and file paths removed. It never "
                     + "includes your files, your installed apps, or your account. Use "
                     + "“View Details” to see exactly what's sent.")
        return lines.joined(separator: "\n")
    }

    /// Writes the scrubbed report to a temp file and opens it so the user can see
    /// precisely what a report would contain before deciding.
    private func showDetails(for report: ProgramRunReport) {
        let text = CrosswireTelemetry.scrubbedReport(for: report)
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "crosswire-report-\(UUID().uuidString.prefix(8)).txt")
        do {
            try text.write(to: tmp, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tmp)
        } catch {
            if let log = report.logFileURL {
                NSWorkspace.shared.activateFileViewerSelecting([log])
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "\(Int(interval))s"
    }
}
