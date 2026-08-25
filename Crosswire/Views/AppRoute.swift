//
//  AppRoute.swift
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

/// The top-level navigation state of the Crosswire main window.
///
/// Crosswire is single-window — Settings and per-entry detail are NOT
/// separate macOS windows or modal sheets. They're full-bleed inline
/// destinations within the same window, replacing the library view
/// underneath. Matches Battle.net's pattern (slide-in from the right,
/// title-bar + nav stays put, Done returns to the library).
///
/// Adding a new destination: add a case here, add a matching overlay
/// branch in `ContentView.body`, route to it from a button. The
/// `withAnimation { route = .x }` pattern + the `.transition(.move(...))`
/// modifier on each overlay handles the slide animation.
enum AppRoute: Equatable, Hashable {
    /// The default library view. The user lands here on launch.
    case library

    /// Inline settings panel — General / Updates / Privacy / About / Advanced.
    /// Replaces the prior separate-window SwiftUI Settings scene.
    case settings

    /// Per-entry detail view. The associated value is the bottle's stable
    /// identity (`Bottle.id`, which is the bottle directory URL) so the
    /// route is `Equatable`/`Hashable` — a `Bottle` reference would break
    /// both. The view resolves the bottle from `BottleVM.bottles` at render
    /// time; if it's been removed (uninstalled while showing), the overlay
    /// disappears and the library shows through underneath.
    case entryDetail(URL)
}
