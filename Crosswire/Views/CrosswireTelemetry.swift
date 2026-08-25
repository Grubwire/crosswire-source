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
import CrosswireKit
import OSLog
import Sentry

/// Crash- and incident-reporting wiring (sentry-cocoa). A single pipeline carries
/// two kinds of incident — the Crosswire *Swift app* crashing/erroring, and a
/// guest program (a game / engine) exiting abnormally (see `FailureWatcher`).
///
/// Reporting is governed by a three-state consent mode (Settings → Privacy):
///   • `.always` — send automatically, no prompt.
///   • `.ask`    — prompt per incident (the default until the user chooses).
///   • `.never`  — send nothing.
/// It is OFF (`.never`-equivalent: nothing leaves the machine) until the user
/// makes a choice. PII (e.g. IP) is disabled; usernames and home paths are
/// scrubbed from report bodies. It never sees your files, installed apps, or
/// account. `capture()` always logs locally regardless. Plan:
/// docs/specs/sentry-integration.md.
enum CrosswireTelemetry {
    /// Sentry DSN — a publishable client key, safe to ship in the app. Empty = disabled.
    static let sentryDSN =
        "https://41a5b5aac2faa80dc4f821f21d1c2810@o4511386046627840.ingest.us.sentry.io/4511512001380352"

    /// How aggressively to send crash & incident reports.
    enum CrashReportingMode: String, CaseIterable, Identifiable {
        case never
        case ask
        case always

        var id: String { rawValue }

        var label: String {
            switch self {
            case .never:  return "Don’t send"
            case .ask:    return "Ask each time"
            case .always: return "Send automatically"
            }
        }
    }

    /// UserDefaults key holding the `CrashReportingMode` raw value.
    static let modeDefaultsKey = "crashReportingMode"
    /// Legacy on/off key (pre-three-state). Read once for migration, kept loosely
    /// in sync afterwards so any stale reader still sees a sane value.
    static let enabledDefaultsKey = "enableCrashReporting"
    /// UserDefaults flag: has the one-time consent prompt been answered yet?
    static let hasAskedKey = "hasAskedCrashReporting"

    static var isConfigured: Bool { !sentryDSN.isEmpty }
    static var hasAsked: Bool { UserDefaults.standard.bool(forKey: hasAskedKey) }

    /// Current consent mode. Reads the stored value; if absent, migrates from the
    /// old on/off bool (only once the user had answered the old prompt), otherwise
    /// defaults to `.ask`. Writing it records the choice and marks consent as asked.
    static var mode: CrashReportingMode {
        get {
            let defaults = UserDefaults.standard
            if let raw = defaults.string(forKey: modeDefaultsKey),
               let resolved = CrashReportingMode(rawValue: raw) {
                return resolved
            }
            if defaults.bool(forKey: hasAskedKey) {
                return defaults.bool(forKey: enabledDefaultsKey) ? .always : .never
            }
            return .ask
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.rawValue, forKey: modeDefaultsKey)
            defaults.set(true, forKey: hasAskedKey)
            defaults.set(newValue != .never, forKey: enabledDefaultsKey)
            if newValue != .never { startSentryOnce() }
        }
    }

    /// Convenience for older call sites: anything other than `.never` (and a DSN).
    static var isEnabled: Bool { isConfigured && mode != .never }

    private static let log = Logger(subsystem: "app.Crosswire.Crosswire", category: "telemetry")
    /// One-shot SDK boot guard. Mutated only from the main thread (launch, the
    /// consent prompt, and the failure dialog all run on the main actor).
    nonisolated(unsafe) private static var started = false

    /// One-time migration: persist the resolved mode so the stored key is always
    /// present after first run (keeps Settings' @AppStorage and `mode` in sync).
    /// Brand-new users are left unset on purpose so the first-run prompt decides.
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: modeDefaultsKey) == nil else { return }
        guard defaults.bool(forKey: hasAskedKey) else { return }
        let resolved: CrashReportingMode = defaults.bool(forKey: enabledDefaultsKey) ? .always : .never
        defaults.set(resolved.rawValue, forKey: modeDefaultsKey)
    }

    /// Starts Sentry once the user has answered consent with anything but `.never`.
    /// No-op for new (un-asked) users until they choose. Called at launch.
    static func startIfEnabled() {
        migrateIfNeeded()
        guard isConfigured, hasAsked, mode != .never else { return }
        startSentryOnce()
    }

    /// Idempotently boots the SDK with the consent gate installed. The gate is
    /// re-evaluated on every event, so a later mode change takes effect without a
    /// restart.
    private static func startSentryOnce() {
        guard !started, isConfigured else { return }
        started = true
        SentrySDK.start { options in
            options.dsn = sentryDSN
            options.sendDefaultPii = false
            options.beforeSend = { event in
                switch mode {
                case .never:  return nil
                case .always: return event
                case .ask:    return event.tags?["cw_consent"] == "user" ? event : nil
                }
            }
            #if DEBUG
            options.debug = true
            #endif
        }
    }

    /// First-run consent: ask ONCE how to handle reports. Opt-in — no option is
    /// pre-selected as enabled. No-op without a DSN or once already answered (in
    /// which case it just (re)starts the SDK per the stored mode).
    @MainActor
    static func requestConsentIfNeeded() {
        guard isConfigured else { return }
        guard !hasAsked else { startIfEnabled(); return }
        let alert = NSAlert()
        alert.messageText = "Help improve Crosswire?"
        alert.informativeText = "When the app or one of your games crashes, Crosswire can send a "
            + "report. It includes the run log, version information, and that app's settings, "
            + "with your username and file paths removed. It never includes your files, your "
            + "installed apps, or your account.\n\n"
            + "You can change this anytime in Settings → Privacy."
        alert.alertStyle = .informational
        alert.icon = NSApplication.shared.applicationIconImage
        alert.addButton(withTitle: "Send Automatically")
        alert.addButton(withTitle: "Ask Each Time")
        alert.addButton(withTitle: "Don’t Send")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  mode = .always
        case .alertSecondButtonReturn: mode = .ask
        default:                       mode = .never
        }
    }

    /// Record an app-domain failure (install / engine-download errors). Always
    /// logs locally; forwards to Sentry only in `.always` mode (these have no
    /// per-incident prompt, so `.ask` holds them back via the consent gate).
    static func capture(_ error: Error, context: String) {
        log.error("[\(context, privacy: .public)] \(error.localizedDescription, privacy: .public)")
        guard isConfigured, mode == .always, started else { return }
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: context, key: "context")
            scope.setTag(value: "auto", key: "cw_consent")
        }
    }

    /// Report an abnormal guest-program exit (game / engine crash). `consented`
    /// marks the event as user-approved so it passes the `.ask` gate; `.always`
    /// passes everything, `.never` drops it. Attaches a credential/PII-scrubbed
    /// report (run log tail, engine version, bottle config). No-op in `.never`.
    static func captureFailure(_ report: ProgramRunReport, consented: Bool) {
        let exe = report.executableURL.deletingPathExtension().lastPathComponent
        log.error("program failure: \(exe, privacy: .public) exit \(report.exitCode, privacy: .public)")
        guard isConfigured, mode != .never else { return }
        startSentryOnce()
        let body = scrubbedReport(for: report)
        SentrySDK.capture(message: "program-failure: \(exe) (exit \(report.exitCode))") { scope in
            scope.setLevel(.error)
            scope.setTag(value: consented ? "user" : "auto", key: "cw_consent")
            scope.setTag(value: String(report.exitCode), key: "exit_code")
            if let data = body.data(using: .utf8) {
                scope.addAttachment(
                    Attachment(data: data, filename: "crosswire-report.txt", contentType: "text/plain")
                )
            }
        }
    }

    /// The exact report text a failure report would carry, credential/PII-scrubbed.
    /// Surfaced so the per-incident dialog can show the user what's included.
    static func scrubbedReport(for report: ProgramRunReport) -> String {
        scrub(FailureReportBuilder.buildBody(for: report))
    }

    /// Best-effort scrub: collapse the home directory and replace the macOS short
    /// username wherever it appears. Not a guarantee against every secret a guest
    /// program might log, but removes the obvious PII (paths, account name).
    private static func scrub(_ text: String) -> String {
        var scrubbed = text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let user = NSUserName()
        if !user.isEmpty {
            scrubbed = scrubbed.replacingOccurrences(of: "/Users/\(user)", with: "/Users/<user>")
            scrubbed = scrubbed.replacingOccurrences(of: user, with: "<user>")
        }
        return scrubbed
    }
}
