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
/// - Normal operation: `feedURLString` returns the appcast for the user's current
///   `UpdateChannel` (stable → `appcast.xml`, beta → `appcast-beta.xml`).
/// - Back-out: a beta build is a *higher* version than the latest stable, so Sparkle
///   refuses to "update" to stable on its own. `reinstallLatestStable(using:)` flips
///   `forcingStableReinstall` on, which (a) pins the feed to stable and (b) installs a
///   comparator that reports the stable build as newer, so Sparkle accepts the downgrade.
///   The flag resets after the check so normal updates behave normally again.
final class CrosswireUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    /// One updater per app; shared so Settings can drive the back-out without
    /// threading the instance through the view tree.
    static let shared = CrosswireUpdaterDelegate()

    private var forcingStableReinstall = false

    func feedURLString(for updater: SPUUpdater) -> String? {
        forcingStableReinstall
            ? UpdateChannel.stable.appcastURLString
            : UpdateChannel.current.appcastURLString
    }

    func versionComparator(for updater: SPUUpdater) -> (any SUVersionComparison)? {
        forcingStableReinstall ? ForceDowngradeComparator() : nil
    }

    /// Force-install the latest **stable** build, even from a higher beta build.
    /// Used by the back-out so toggling beta off actually returns the user to stable.
    @MainActor
    func reinstallLatestStable(using updater: SPUUpdater) {
        forcingStableReinstall = true
        // Reset once the check has been kicked off so any later, normal update
        // check uses real comparison again. The in-flight check keeps the forced
        // behavior because feedURLString/versionComparator were already consulted.
        updater.checkForUpdates()
        DispatchQueue.main.async { [weak self] in
            self?.forcingStableReinstall = false
        }
    }
}

/// Reports the installed version as strictly older than any candidate, so Sparkle
/// will install it — turning the stable build into an accepted "update" (downgrade).
private final class ForceDowngradeComparator: NSObject, SUVersionComparison {
    func compareVersion(_ versionA: String, toVersion versionB: String) -> ComparisonResult {
        // Sparkle asks "is installed (A) older than candidate (B)?" — always yes.
        .orderedAscending
    }
}
