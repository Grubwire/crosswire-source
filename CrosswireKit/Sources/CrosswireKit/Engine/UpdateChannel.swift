//
//  UpdateChannel.swift
//  CrosswireKit
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

/// The update channel the user is subscribed to. Drives BOTH feeds:
/// - the Sparkle **app** appcast (`appcastURLString`), and
/// - the **engine** manifest (`engineManifestURL`).
/// Stable = the shipped `engine/prod` + `app/appcast.xml`. Beta = the opt-in
/// `engine/beta` + `app/appcast-beta.xml`, the vehicle for validating risky
/// engine changes (e.g. DXVK) before they reach stable. Default is stable; the
/// in-app "Receive beta updates" toggle flips it. This is the one isolated config
/// point the beta-ready checklist promised — both URLs key off it.
public enum UpdateChannel: String, Sendable, CaseIterable {
    case stable
    case beta

    /// UserDefaults key for the in-app "Receive beta updates" toggle. `false` = stable.
    public static let defaultsKey = "betaChannel"

    /// The channel the user is currently on (reads the shared default).
    public static var current: UpdateChannel {
        UserDefaults.standard.bool(forKey: defaultsKey) ? .beta : .stable
    }

    private static let host = "https://download.grubwire.io"

    /// R2 engine prefix: `prod` for stable, `beta` for beta.
    private var enginePrefix: String { self == .beta ? "beta" : "prod" }

    /// The signed engine manifest URL for this channel.
    public var engineManifestURL: URL {
        Self.url("engine/\(enginePrefix)/engine-manifest.json")
    }

    /// The engine manifest Ed25519 signature URL for this channel.
    public var engineManifestSigURL: URL {
        Self.url("engine/\(enginePrefix)/engine-manifest.json.sig")
    }

    /// The Sparkle appcast feed for this channel (consumed by the updater delegate).
    public var appcastURLString: String {
        "\(Self.host)/app/\(self == .beta ? "appcast-beta.xml" : "appcast.xml")"
    }

    /// The always-latest **stable** DMG — used by the "leave beta → reinstall stable"
    /// back-out, which force-installs this regardless of the running version.
    public static var stableDMGURLString: String {
        "\(host)/app/Crosswire.dmg"
    }

    // host + a constant path is always a valid URL; the fallback is unreachable
    // and only there to avoid a force-unwrap.
    private static func url(_ path: String) -> URL {
        URL(string: "\(host)/\(path)") ?? URL(fileURLWithPath: "/")
    }
}
