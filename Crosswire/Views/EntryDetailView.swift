//
//  EntryDetailView.swift
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
import CrosswireKit

/// Full-bleed inline per-entry detail shown when `AppRoute == .entryDetail`.
/// Slides in over the library (same pattern as inline Settings); the back
/// chevron returns. Replaces the old detached per-app settings sheet.
///
/// Dark-themed to match Sidebar's `LibraryDetailPane` — both delegate to the
/// same `BottleDetailContent` for name/Play/secondary-actions/Advanced. The
/// hero renders separately, at this view's full available width: this is a
/// full-window overlay (`ContentView`'s `.frame(maxWidth: .infinity)`), with
/// more room than Sidebar's rail-adjacent 840pt pane
/// (`CrosswireLauncherTheme.Layout.sidebarWidth` documents the 1080pt window
/// minus the 240pt rail). `BottleDetailContent` stays capped at 620pt below
/// the hero, same width this view used before this redesign — sized for the
/// Advanced section's form rows, not the hero, so it carries over unchanged
/// while only the hero gets to use the extra width.
struct EntryDetailView: View {
    @ObservedObject var bottle: Bottle
    var onBack: () -> Void
    var onRun: () -> Void
    var onRunProgram: (Program) -> Void
    var onUninstall: () -> Void
    /// Launch with full-lifetime diagnostics capture (Advanced › Maintenance).
    var onLaunchDiagnostics: () -> Void

    private var actions: BoundBottleActions {
        BoundBottleActions(run: onRun,
                           runProgram: onRunProgram,
                           uninstall: onUninstall,
                           launchDiagnostics: onLaunchDiagnostics)
    }

    var body: some View {
        VStack(spacing: 0) {
            InlinePanelBackBar(action: onBack)
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HeroArtView(bottle: bottle)
                    BottleDetailContent(bottle: bottle, actions: actions)
                        .frame(maxWidth: 620, alignment: .leading)
                }
                .padding(28)
            }
        }
        .background(CrosswireLauncherTheme.backgroundBase)
        .onAppear {
            if bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
    }
}
