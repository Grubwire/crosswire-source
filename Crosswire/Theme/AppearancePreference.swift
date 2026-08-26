//
//  AppearancePreference.swift
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

/// The user's chosen appearance: follow the system, or pin light / dark.
///
/// Every color token in `CrosswireTheme` and `CrosswireLauncherTheme` resolves
/// through `Color(light:dark:)`, which reads the SwiftUI environment appearance.
/// Applying `.preferredColorScheme(_:)` once at the window root therefore drives
/// the entire palette; nothing else needs to know this preference exists.
///
/// Storage follows the `UpdateChannel` pattern: a `defaultsKey` constant here,
/// `@AppStorage(AppearancePreference.defaultsKey)` at the call sites.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// UserDefaults key for the appearance picker (setup flow + Settings).
    static let defaultsKey = "appearancePreference"

    /// The value stored when the user has never chosen. Following the system is
    /// the least surprising default and the only one that needs no explanation.
    static let fallback: AppearancePreference = .system

    var id: String { rawValue }

    /// What to hand `.preferredColorScheme(_:)`. `nil` means "don't override",
    /// which is exactly how SwiftUI expresses "follow the system".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// User-facing label for the picker.
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Read the stored preference, falling back when unset or unrecognized.
    /// For views prefer `@AppStorage(AppearancePreference.defaultsKey)`; this is
    /// for the non-view paths that only need to read once.
    static var current: AppearancePreference {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let value = AppearancePreference(rawValue: raw) else { return fallback }
        return value
    }
}
