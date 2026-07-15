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

/// Watches `Notification.Name.crosswireProgramDidExit` and presents a
/// failure dialog when a program reports an abnormal exit. Lives for the
/// lifetime of the app — instantiate once in the App body.
///
/// Behaviour rules from the spec:
/// - Trigger only on abnormal exits (currently `exitCode != 0`).
/// - Never auto-submit. The user always reviews + clicks Submit on GitHub.
/// - Don't double-fire: one dialog per exit event.
/// - De-noise repeated rapid failures of the same exe (rate-limit).
@MainActor
final class FailureWatcher: ObservableObject {
    private var cancellable: AnyCancellable?
    /// Most recent report shown, keyed by exe URL — used to debounce.
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
        present(report)
    }

    private func present(_ report: ProgramRunReport) {
        let exeName = report.executableURL.deletingPathExtension().lastPathComponent
        let alert = NSAlert()
        alert.messageText = "\(exeName) stopped unexpectedly"
        alert.informativeText = informativeBody(for: report)
        alert.alertStyle = .warning
        let reportButton = alert.addButton(withTitle: "Report…")
        alert.addButton(withTitle: "View Log")
        alert.addButton(withTitle: "Not Now")
        reportButton.hasDestructiveAction = false

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            openIssueInBrowser(for: report)
        case .alertSecondButtonReturn:
            revealLog(for: report)
        default:
            break
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
        if report.logFileURL != nil {
            lines.append("")
            lines.append("Report includes the run log, engine version, "
                         + "and bottle config. Nothing is submitted automatically — "
                         + "the issue opens in your browser for you to review.")
        }
        return lines.joined(separator: "\n")
    }

    private func openIssueInBrowser(for report: ProgramRunReport) {
        guard let url = FailureReportBuilder.issueURL(for: report) else { return }
        NSWorkspace.shared.open(url)
    }

    private func revealLog(for report: ProgramRunReport) {
        guard let log = report.logFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([log])
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "\(Int(interval))s"
    }
}
