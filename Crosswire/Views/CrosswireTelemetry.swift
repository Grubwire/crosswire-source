//
//  CrosswireTelemetry.swift
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
import OSLog
import Sentry

/// Crash-reporting wiring (sentry-cocoa). Sends ONLY when a DSN is set AND the
/// user opts in (Settings → Privacy); it is OFF by default. It only ever sees the
/// Crosswire *Swift app* — never the Wine guest, games, or credentials, and PII
/// (e.g. IP) is disabled. `capture()` always logs locally regardless. Plan:
/// docs/specs/sentry-integration.md.
enum CrosswireTelemetry {
    /// Sentry DSN — a publishable client key, safe to ship in the app. Empty = disabled.
    static let sentryDSN =
        "https://41a5b5aac2faa80dc4f821f21d1c2810@o4511386046627840.ingest.us.sentry.io/4511512001380352"
    /// UserDefaults key for the Privacy opt-in toggle (default false).
    static let enabledDefaultsKey = "enableCrashReporting"
    /// UserDefaults flag: has the one-time consent prompt been shown yet?
    static let hasAskedKey = "hasAskedCrashReporting"

    static var isConfigured: Bool { !sentryDSN.isEmpty }
    static var isEnabled: Bool {
        isConfigured && UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    private static let log = Logger(subsystem: "app.Crosswire.Crosswire", category: "telemetry")

    /// Starts Sentry only when configured AND the user has opted in (Settings →
    /// Privacy). No-op otherwise. Called once at launch.
    static func startIfEnabled() {
        guard isEnabled else { return }
        SentrySDK.start { options in
            options.dsn = sentryDSN
            options.sendDefaultPii = false
            #if DEBUG
            options.debug = true
            #endif
        }
    }

    /// First-run consent: ask ONCE whether to send crash reports. Opt-in — nothing
    /// is sent until the user explicitly chooses "Send Reports" (neither button is
    /// pre-selected as enabled). No-op without a DSN or if we've already asked.
    /// Settings → Privacy remains the permanent control.
    @MainActor
    static func requestConsentIfNeeded() {
        guard isConfigured else { return }
        guard !UserDefaults.standard.bool(forKey: hasAskedKey) else { return }
        let alert = NSAlert()
        alert.messageText = "Help improve Crosswire?"
        alert.informativeText = "Send anonymous crash & error reports from the app — never "
            + "your installed apps, your files, or your account. You can change this anytime "
            + "in Settings → Privacy."
        alert.alertStyle = .informational
        alert.icon = NSApplication.shared.applicationIconImage
        alert.addButton(withTitle: "Send Reports")
        alert.addButton(withTitle: "Not Now")
        let optedIn = alert.runModal() == .alertFirstButtonReturn
        UserDefaults.standard.set(true, forKey: hasAskedKey)
        UserDefaults.standard.set(optedIn, forKey: enabledDefaultsKey)
        if optedIn { startIfEnabled() }
    }

    /// Record an app-domain failure (install / engine-download errors). Always
    /// logs locally; also forwards to Sentry when enabled.
    static func capture(_ error: Error, context: String) {
        log.error("[\(context, privacy: .public)] \(error.localizedDescription, privacy: .public)")
        if isEnabled {
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: context, key: "context")
            }
        }
    }
}
