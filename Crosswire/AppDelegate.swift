//
//  AppDelegate.swift
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

import Foundation
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("hasShownMoveToApplicationsAlert") private var hasShownMoveToApplicationsAlert = false

    func application(_ application: NSApplication, open urls: [URL]) {
        // Test if automatic window tabbing is enabled
        // as it is disabled when ContentView appears
        if NSWindow.allowsAutomaticWindowTabbing, let url = urls.first {
            // Reopen the file after Crosswire has been opened
            // so that the `onOpenURL` handler is actually called.
            // Dispatched async: calling NSWorkspace.shared.open(url) synchronously
            // from inside this Apple Event handler blocks the main thread on a
            // Launch Services round-trip that needs this same handler to have
            // returned before it can redeliver the event - a self-referential
            // wait that showed up in Sentry as repeated 2s+ app hangs
            // (CROSSWIRE-S). Deferring to the next run loop turn lets this
            // handler return first, so there's nothing left to wait on.
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !hasShownMoveToApplicationsAlert && !AppDelegate.insideAppsFolder {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                NSApp.activate(ignoringOtherApps: true)
                self.showAlertOnFirstLaunch()
                self.hasShownMoveToApplicationsAlert = true
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "killOnTerminate") {
            CrosswireApp.killBottles()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    /// #127: without this, AppKit falls back to a legacy window-state
    /// restoration path on quit (macOS logs a warning that the app doesn't
    /// implement this and defaults to insecure/legacy restoration). Traced
    /// the uninstall-flow quit hang to exactly this: the unified log shows
    /// NSPersistentUIManager's flushAllChanges reaching "writing records"
    /// right after NSApp.terminate(nil), with nothing after it and the main
    /// thread's run loop sitting idle rather than inside terminate's call
    /// chain -- the legacy restoration write was the thing not completing,
    /// not an applicationShouldTerminate veto or a stuck modal session (both
    /// checked and ruled out first). Returning true opts into the modern,
    /// faster, recommended path.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private static var appUrl: URL? {
        Bundle.main.resourceURL?.deletingLastPathComponent().deletingLastPathComponent()
    }

    private static let expectedUrl = URL(fileURLWithPath: "/Applications/Crosswire.app")

    private static var insideAppsFolder: Bool {
        if let url = appUrl {
            return url.path.contains("Xcode") || url.path.contains(expectedUrl.path)
        }
        return false
    }

    @MainActor
    private func showAlertOnFirstLaunch() {
        let alert = NSAlert()
        alert.messageText = String(localized: "showAlertOnFirstLaunch.messageText")
        alert.informativeText = String(localized: "showAlertOnFirstLaunch.informativeText")
        alert.addButton(withTitle: String(localized: "showAlertOnFirstLaunch.button.moveToApplications"))
        alert.addButton(withTitle: String(localized: "showAlertOnFirstLaunch.button.dontMove"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let appURL = Bundle.main.bundleURL

            do {
                _ = try FileManager.default.replaceItemAt(AppDelegate.expectedUrl, withItemAt: appURL)
                NSWorkspace.shared.open(AppDelegate.expectedUrl)
            } catch {
                print("Failed to move the app: \(error)")
            }
        }
    }
}
