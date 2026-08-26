//
//  CrosswireUpdaterDelegate.swift
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
import CryptoKit
import Foundation
import Sparkle
import CrosswireKit

extension Notification.Name {
    /// Posted when the user switches update channels. `ContentView` re-provisions
    /// the engine for the new channel (uninstall + run engine setup, which now
    /// resolves the channel-aware manifest). Confirmed by the user beforehand.
    static let crosswireReprovisionEngine = Notification.Name("crosswireReprovisionEngine")
}

/// Sparkle delegate that makes app updates **channel-aware** and powers the
/// "leave beta → reinstall stable" back-out.
///
/// `feedURLString` returns the appcast for the user's current `UpdateChannel`
/// (stable → `appcast.xml`, beta → `appcast-beta.xml`) — that part is plain Sparkle.
///
/// The back-out itself does **not** go through Sparkle's normal update path.
/// A beta build has a higher `CFBundleVersion` than the latest stable, and Sparkle's
/// installer refuses any real downgrade using its own standard comparator — this is
/// documented directly on `versionComparatorForUpdater:` ("the standard version
/// comparator may be used during installation for preventing a downgrade, even if
/// you provide a custom comparator here") and that delegate method is itself marked
/// deprecated by Sparkle as "incompatible with how the system compares different
/// versions of an app." An earlier version of this file tried exactly that trick (a
/// comparator that unconditionally reported the installed build as older): it also
/// broke Sparkle's own `bestItemFromAppcastItems:comparator:` fold, which replaces
/// its running "best" candidate whenever the comparator says the new one wins — an
/// always-true comparator isn't a valid ordering, so the fold walked off the end of
/// the appcast and picked the *oldest* item instead of the newest. Confirmed live:
/// it offered to install a build from May instead of the actual latest stable, and
/// then Sparkle's installer refused that anyway for being older than what's running.
/// `StableChannelReinstaller` sidesteps both problems by downloading, verifying, and
/// swapping in the latest stable build directly, without asking Sparkle's installer
/// to bless a downgrade it will never allow.
final class CrosswireUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    /// One updater per app; shared so Settings can drive the back-out without
    /// threading the instance through the view tree.
    static let shared = CrosswireUpdaterDelegate()

    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateChannel.current.appcastURLString
    }

    /// Force-install the latest **stable** build, even from a higher beta build.
    /// Used by the back-out so toggling beta off actually returns the user to stable.
    @MainActor
    func reinstallLatestStable() {
        Task {
            do {
                try await StableChannelReinstaller.run()
            } catch {
                StableChannelReinstaller.showFailureAlert(for: error)
            }
        }
    }
}

/// Downloads the latest stable `.dmg` straight from the channel's own appcast,
/// verifies its EdDSA signature against the same `SUPublicEDKey` Sparkle already
/// trusts, and swaps it into place — bypassing `SPUUpdater` entirely so Sparkle's
/// non-overridable downgrade guard never gets a say. See the doc comment on
/// `CrosswireUpdaterDelegate` for why the Sparkle-native approach doesn't work.
enum StableChannelReinstaller {
    enum ReinstallError: LocalizedError {
        case noAppcastEnclosure
        case invalidPublicKey
        case invalidSignature
        case signatureMismatch
        case noAppBundleInImage
        case mountFailed

        var errorDescription: String? {
            switch self {
            case .noAppcastEnclosure: "Couldn't find a download link in the stable update feed."
            case .invalidPublicKey: "The app's update signing key is missing or malformed."
            case .invalidSignature: "The downloaded update's signature is malformed."
            case .signatureMismatch: "The downloaded update's signature doesn't match — rejecting it."
            case .noAppBundleInImage: "The downloaded disk image didn't contain an app."
            case .mountFailed: "Couldn't open the downloaded disk image."
            }
        }
    }

    /// Downloads, verifies, and installs the latest stable build, then relaunches
    /// into it. Runs off the main actor; only the final relaunch (and the failure
    /// alert, on the caller's side) touch AppKit.
    static func run() async throws {
        let enclosure = try await fetchLatestStableEnclosure()
        let dmgURL = try await download(enclosure.url)
        defer { try? FileManager.default.removeItem(at: dmgURL) }

        try verify(fileAt: dmgURL, edSignatureBase64: enclosure.edSignatureBase64)

        let mountPoint = try mount(dmgURL)
        defer { unmount(mountPoint) }

        guard let newAppURL = try appBundle(in: mountPoint) else {
            throw ReinstallError.noAppBundleInImage
        }

        try replaceRunningApp(with: newAppURL)
        try await relaunch()
    }

    @MainActor
    static func showFailureAlert(for error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't reinstall the stable build"
        alert.informativeText = "Crosswire will stay on this build for now. You can grab the "
            + "latest stable release from the website, or try leaving beta again from "
            + "Settings → Updates.\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Appcast

    private struct Enclosure {
        let url: URL
        let edSignatureBase64: String
    }

    /// Appcast items are published newest-first (confirmed against the real feed);
    /// the first `<enclosure>` is the latest stable release.
    private static func fetchLatestStableEnclosure() async throws -> Enclosure {
        guard let feedURL = URL(string: UpdateChannel.stable.appcastURLString) else {
            throw ReinstallError.noAppcastEnclosure
        }
        let (data, _) = try await URLSession.shared.data(from: feedURL)
        let parser = XMLParser(data: data)
        let delegate = EnclosureParserDelegate()
        parser.delegate = delegate
        parser.parse()
        guard let enclosure = delegate.firstEnclosure else {
            throw ReinstallError.noAppcastEnclosure
        }
        return enclosure
    }

    /// Namespace-unaware by design: Sparkle's `sparkle:` prefixed attributes come
    /// through as literal keys ("sparkle:edSignature") without needing namespace
    /// processing enabled.
    private final class EnclosureParserDelegate: NSObject, XMLParserDelegate {
        private(set) var firstEnclosure: Enclosure?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard firstEnclosure == nil,
                  elementName == "enclosure",
                  let urlString = attributeDict["url"],
                  let url = URL(string: urlString),
                  let signature = attributeDict["sparkle:edSignature"] else { return }
            firstEnclosure = Enclosure(url: url, edSignatureBase64: signature)
            parser.abortParsing()
        }
    }

    // MARK: - Download + verify

    private static func download(_ url: URL) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        let dmgURL = FileManager.default.temporaryDirectory
            .appending(path: "crosswire-stable-\(UUID().uuidString).dmg")
        try FileManager.default.moveItem(at: tempURL, to: dmgURL)
        return dmgURL
    }

    /// Same EdDSA scheme Sparkle itself uses for update archives: a raw Ed25519
    /// signature over the whole file, checked against the `SUPublicEDKey` already
    /// embedded in Info.plist for Sparkle's own (non-downgrade) update checks.
    private static func verify(fileAt url: URL, edSignatureBase64: String) throws {
        guard let signature = Data(base64Encoded: edSignatureBase64), signature.count == 64 else {
            throw ReinstallError.invalidSignature
        }
        guard let publicKeyBase64 = Bundle.main.infoDictionary?["SUPublicEDKey"] as? String,
              let publicKeyData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            throw ReinstallError.invalidPublicKey
        }
        let fileData = try Data(contentsOf: url, options: .mappedIfSafe)
        guard publicKey.isValidSignature(signature, for: fileData) else {
            throw ReinstallError.signatureMismatch
        }
    }

    // MARK: - Disk image

    private static func mount(_ dmgURL: URL) throws -> URL {
        let mountPoint = FileManager.default.temporaryDirectory
            .appending(path: "crosswire-stable-mount-\(UUID().uuidString.prefix(8))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", dmgURL.path, "-nobrowse", "-quiet", "-mountpoint", mountPoint.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ReinstallError.mountFailed
        }
        return mountPoint
    }

    private static func unmount(_ mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-quiet"]
        try? process.run()
        process.waitUntilExit()
    }

    private static func appBundle(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return contents.first { $0.pathExtension == "app" }
    }

    // MARK: - Install + relaunch

    /// Copies the new bundle in under a staging name first, then swaps it into the
    /// running app's own path — minimizing how long that path is missing. Deleting
    /// and replacing the directory a running process's executable lives under is
    /// safe on macOS: the OS keeps the old file's bytes alive via the still-open
    /// inode until this process actually exits, which only happens after `relaunch()`
    /// hands off to the new one.
    private static func replaceRunningApp(with newAppURL: URL) throws {
        let fileManager = FileManager.default
        let currentURL = Bundle.main.bundleURL
        let stagingURL = currentURL.deletingLastPathComponent()
            .appending(path: ".\(currentURL.lastPathComponent)-stable-staging")

        try? fileManager.removeItem(at: stagingURL)
        try fileManager.copyItem(at: newAppURL, to: stagingURL)
        clearQuarantine(stagingURL)

        try? fileManager.removeItem(at: currentURL)
        try fileManager.moveItem(at: stagingURL, to: currentURL)
    }

    /// Copies from a mounted disk image can inherit `com.apple.quarantine` from the
    /// downloaded `.dmg`; without stripping it, the relaunch below would hit
    /// Gatekeeper's "unidentified developer" prompt instead of just reopening.
    private static func clearQuarantine(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    /// Fire-and-forget via `/usr/bin/open -n` rather than `NSWorkspace.openApplication`:
    /// the async `openApplication` completion did not reliably resolve in testing,
    /// which left the old process never reaching the `terminate(nil)` call after it —
    /// a zombie beta instance sitting alongside the freshly relaunched stable one.
    /// `open -n` returns as soon as the new process is spawned, so termination here
    /// isn't waiting on anything that could hang.
    ///
    /// `NSApp.terminate(nil)` alone still isn't enough: this back-out is triggered
    /// alongside the engine reprovision flow (`commitChannelChange` in
    /// `SettingsUpdatesGroup` fires both off the same toggle), which can leave its own
    /// "Dependencies Setup" sheet attached to the main window. AppKit's termination
    /// sequence tries to close that window as part of quitting, and a window with an
    /// unanswered sheet attached won't close — reproduced twice live: `terminate(nil)`
    /// returns, but the process just sits there indefinitely instead of exiting.
    /// Since the new process has already been spawned from the already-replaced bundle
    /// by this point, there's nothing left worth keeping this process alive for — give
    /// the graceful path a couple seconds (it still runs `applicationWillTerminate`'s
    /// bottle-killing when nothing is blocking it) and hard-exit if it doesn't take.
    @MainActor
    private static func relaunch() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundleURL.path]
        try process.run()

        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            exit(0)
        }
    }
}
