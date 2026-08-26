//
//  BottleActions.swift
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
import CrosswireKit

/// The things a library entry can be told to do, bundled so views take one
/// parameter instead of four.
///
/// Every one of these routes back out through `ContentView`'s run helpers, so
/// single-instance handling and failure watching apply uniformly no matter
/// which view triggered them. The tile, the sidebar and the detail pane all
/// pass the same value straight through.
struct BottleActions {
    /// Launch the entry's primary program.
    var run: (Bottle) -> Void
    /// Launch one specific program within an entry.
    var runProgram: (Bottle, Program) -> Void
    /// Begin the uninstall confirmation flow.
    var uninstall: (Bottle) -> Void
    /// Launch with full-lifetime diagnostics capture.
    var launchDiagnostics: (Bottle) -> Void

    /// Bind the entry-agnostic closures to one entry, for views that only ever
    /// act on a single bottle.
    func bound(to bottle: Bottle) -> BoundBottleActions {
        BoundBottleActions(
            run: { run(bottle) },
            runProgram: { runProgram(bottle, $0) },
            uninstall: { uninstall(bottle) },
            launchDiagnostics: { launchDiagnostics(bottle) }
        )
    }
}

/// `BottleActions` with the entry already applied.
struct BoundBottleActions {
    var run: () -> Void
    var runProgram: (Program) -> Void
    var uninstall: () -> Void
    var launchDiagnostics: () -> Void
}
