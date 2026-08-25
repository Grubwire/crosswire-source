//
//  CrosswireApp+Uninstall.swift
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
import SwiftUI
import CrosswireKit

/// Tiered uninstall flow (#110). Tier 1 (this file's `confirmUninstall`)
/// removes the engine, caches, logs, and preferences -- nothing
/// irreplaceable. Tier 2 (`presentTier2Confirmation`) is a separate, harder
/// confirmation that only deletes installed apps and their data when the
/// user explicitly opts in, and only when there's at least one bottle to
/// ask about.
extension CrosswireApp {
    /// Entry point for both the app-menu item and Settings > Advanced.
    /// Shows the Tier 1 confirmation. On confirm, `killBottles()` runs
    /// unconditionally before anything is touched, then Tier 2 is offered
    /// as a separate, harder confirmation only when there's actually
    /// something at stake to ask about.
    @MainActor static func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = String(localized: "uninstall.confirm.title")
        alert.informativeText = String(localized: "uninstall.confirm.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "uninstall.confirm.uninstall"))
        alert.addButton(withTitle: String(localized: "uninstall.confirm.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            await runUninstallFlow()
        }
    }

    /// Kill first, always -- a running Wine process can hold file handles
    /// Tier 1's cleanup needs released, regardless of whether Tier 2 (bottle
    /// deletion) ends up running at all. Tier 2 is only offered when there's
    /// at least one installed bottle; with zero bottles there's nothing
    /// irreplaceable to ask about, so it's skipped rather than shown empty.
    /// Both tiers' actual file removal happen together at the end via
    /// `performDataCleanup`, since the flow only reveals-in-Finder-and-quits
    /// once -- Tier 2's answer has to be known before that single terminal
    /// step, not requested after it.
    @MainActor static func runUninstallFlow() async {
        killBottles()

        let bottles = BottleVM.shared.bottles
        var deleteBottles = false
        if !bottles.isEmpty {
            deleteBottles = await presentTier2Confirmation(bottles: bottles)
        }

        performDataCleanup(deletingBottles: deleteBottles, bottles: bottles)
    }

    /// Presents the Tier 2 confirmation sheet (`UninstallTier2View`) in its
    /// own panel -- `confirmUninstall()` is reached from a `CommandGroup`
    /// button and a Settings action row, neither of which own a SwiftUI view
    /// hierarchy a `.sheet()` modifier could attach to, so this follows the
    /// same NSPanel + NSHostingView pattern as `openDiagnosticsWindow()`.
    /// Returns `true` if the user confirmed deletion, `false` for "Keep My
    /// Apps" or closing the panel any other way (red-dot close counts as
    /// declining, never as confirming).
    @MainActor static func presentTier2Confirmation(bottles: [Bottle]) async -> Bool {
        await withCheckedContinuation { continuation in
            var didResume = false
            func resume(_ value: Bool) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: value)
            }

            var panel: NSPanel?
            let view = UninstallTier2View(bottles: bottles) { deleteBottles in
                resume(deleteBottles)
                panel?.close()
            }
            let hosting = NSHostingView(rootView: view)
            let newPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            newPanel.title = "Delete Installed Apps?"
            newPanel.contentView = hosting
            newPanel.center()
            newPanel.isReleasedWhenClosed = false
            panel = newPanel

            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: newPanel,
                queue: .main
            ) { _ in resume(false) }

            newPanel.makeKeyAndOrderFront(nil)
        }
    }

    /// Removes Crosswire's data. `deletingBottles` gates the irreplaceable
    /// part (installed apps and their save data, plus the sandbox container
    /// that indexes them) -- when `false`, only the redownloadable/regenerable
    /// tier (engine, caches, logs, prefs) is removed and bottles are left
    /// exactly where they are. Reveals the app in Finder and quits either
    /// way; the user just has to drag it to the Trash to finish.
    @MainActor static func performDataCleanup(deletingBottles: Bool, bottles: [Bottle]) {
        if deletingBottles {
            // Bottles outside the sandbox container are removed here, in
            // process. In-container bottles are wiped along with the whole
            // container (which also holds the bottle index) by the detached
            // script below, once this process has exited.
            let containerPrefix = NSHomeDirectory() + "/Library/Containers/"
            for bottle in bottles where !bottle.url.path.hasPrefix(containerPrefix) {
                try? FileManager.default.removeItem(at: bottle.url)
            }
        }

        // Drop every persisted preference for this app.
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.synchronize()
        }

        launchCleanupScript(deletingBottles: deletingBottles)

        // Final dialog so the user knows something is actually happening.
        let done = NSAlert()
        done.messageText = String(localized: "uninstall.done.title")
        done.informativeText = String(localized: deletingBottles
            ? "uninstall.done.bottlesDeleted.message"
            : "uninstall.done.message")
        done.addButton(withTitle: String(localized: "uninstall.done.ok"))
        done.runModal()

        NSApp.terminate(nil)
    }

    /// Spawn a detached cleanup script that waits for this process to exit,
    /// then removes every remaining trace -- Application Support, Logs,
    /// Caches, Saved Application State always; the sandbox container
    /// (bottles + the bottle index) only when Tier 2 was confirmed -- and
    /// finally reveals the .app in Finder so the user can drag it to Trash.
    /// The script then deletes itself.
    private static func launchCleanupScript(deletingBottles: Bool) {
        let bundleID = Bundle.main.bundleIdentifier ?? "app.Crosswire.Crosswire"
        let home = NSHomeDirectory()
        let appBundlePath = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptPath = "/tmp/crosswire-uninstall-\(UUID().uuidString.prefix(8)).sh"
        let containerLine = deletingBottles
            ? "rm -rf \"\(home)/Library/Containers/\(bundleID)\"\n"
            : ""
        let script = """
        #!/bin/bash
        # Wait for the Crosswire process to fully exit before touching its
        # sandbox container, otherwise macOS will refuse the removal.
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        sleep 1

        \(containerLine)rm -rf "\(home)/Library/Application Support/\(bundleID)"
        rm -rf "\(home)/Library/Logs/\(bundleID)"
        rm -rf "\(home)/Library/Caches/\(bundleID)"
        rm -rf "\(home)/Library/Saved Application State/\(bundleID).savedState"

        # Surface the app bundle in Finder so the user can drag it to Trash.
        open -R "\(appBundlePath)"

        # Self-delete.
        rm -f "$0"
        """
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath
        )

        // Launch the script fully detached so it survives our termination.
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = ["-c", "nohup bash \(scriptPath) >/dev/null 2>&1 </dev/null & disown"]
        try? launcher.run()
    }
}
