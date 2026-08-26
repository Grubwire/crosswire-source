//
//  LibraryDetailPane.swift
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

/// Sidebar mode's right column: whatever is selected in `LibraryRail`, always
/// on screen. This is the "hero always visible" half of the direction doc —
/// selecting a different row never hides it, it replaces its contents.
///
/// Just a switch between the placeholder and `LibraryDetailPaneContent`.
/// `bottle` has to be `Bottle?` here since there might be no selection, but an
/// `@ObservedObject` can't be declared `Optional` and still notice a
/// `@Published` change on the wrapped object reliably — so the moment a
/// bottle exists, it gets handed to a view that observes it directly.
struct LibraryDetailPane: View {
    let bottle: Bottle?
    let actions: BottleActions
    @Binding var renameRequestID: Bottle.ID?

    var body: some View {
        Group {
            if let bottle {
                LibraryDetailPaneContent(bottle: bottle,
                                        actions: actions,
                                        renameRequestID: $renameRequestID)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CrosswireLauncherTheme.backgroundBase)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(CrosswireLauncherTheme.textTertiary)
            Text("Select an app from your library")
                .font(.system(size: 13))
                .foregroundStyle(CrosswireLauncherTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The actual pane content for one bottle: the hero, at the pane's full
/// width, followed by `BottleDetailContent` for everything below it.
private struct LibraryDetailPaneContent: View {
    @ObservedObject var bottle: Bottle
    let actions: BottleActions
    @Binding var renameRequestID: Bottle.ID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeroArtView(bottle: bottle)
                BottleDetailContent(bottle: bottle,
                                    actions: actions.bound(to: bottle),
                                    renameRequestID: $renameRequestID)
            }
            .padding(24)
        }
    }
}
