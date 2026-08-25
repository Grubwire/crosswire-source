//
//  LibraryContainerView.swift
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

/// Everything that isn't loading/empty: the mode-specific library content.
///
/// Reads `LibraryViewMode` itself via the same `@AppStorage` key the toolbar
/// switcher writes, so the two never need explicit wiring to stay in sync.
struct LibraryContainerView: View {
    let bottles: [Bottle]
    @Binding var searchText: String
    @ObservedObject var selection: LibrarySelection
    let actions: BottleActions
    /// Grid mode selecting a tile opens the existing slide-over overlay;
    /// Sidebar mode never calls this, since selection alone drives its pane.
    let onOpenDetail: (Bottle) -> Void

    @AppStorage(LibraryViewMode.defaultsKey) private var modeRaw = LibraryViewMode.fallback.rawValue
    @State private var renameRequestID: Bottle.ID?

    private var mode: LibraryViewMode { LibraryViewMode(rawValue: modeRaw) ?? .fallback }

    private var filtered: [Bottle] {
        if searchText.isEmpty { return bottles }
        return bottles.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        switch mode {
        case .grid: gridBody
        case .sidebar: sidebarBody
        }
    }

    // MARK: - Grid

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                LibrarySearchField(text: $searchText)
                Spacer()
                Text("^[\(filtered.count) item](inflect: true)")
                    .font(.system(size: 11))
                    .foregroundStyle(CrosswireLauncherTheme.textTertiary)
                    .padding(.leading, 12)
            }
            .padding(.horizontal, CrosswireLauncherTheme.Layout.shelfPadding)
            .padding(.top, 16)
            .padding(.bottom, 4)

            if filtered.isEmpty {
                gridNoMatch
            } else {
                LibraryGrid(bottles: filtered,
                           selectedID: selection.selectedID,
                           actions: actions,
                           onSelect: { onOpenDetail($0) },
                           // Arrow-key movement only selects — routing this
                           // through onOpenDetail would pop the overlay open
                           // and closed on every keypress.
                           onHighlight: { selection.select($0) },
                           // Grid has no persistent pane to rename in, so
                           // Rename opens the same overlay a click would; the
                           // pencil inside it starts the actual edit.
                           onRequestRename: { onOpenDetail($0) })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CrosswireLauncherTheme.backgroundBase)
    }

    private var gridNoMatch: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(CrosswireLauncherTheme.textTertiary)
            Text("Nothing in your library matches “\(searchText)”")
                .font(.system(size: 13))
                .foregroundStyle(CrosswireLauncherTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sidebar

    private var sidebarBody: some View {
        HStack(spacing: 0) {
            LibraryRail(bottles: bottles,
                       searchText: $searchText,
                       selection: selection,
                       actions: actions,
                       onRequestRename: { bottle in
                           selection.select(bottle)
                           renameRequestID = bottle.id
                       })
            Rectangle()
                .fill(CrosswireLauncherTheme.stroke)
                .frame(width: 1)
            LibraryDetailPane(bottle: bottles.first { $0.id == selection.selectedID },
                              actions: actions,
                              renameRequestID: $renameRequestID)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
