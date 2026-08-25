//
//  LibraryGrid.swift
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

/// The library as a grid of cover tiles.
///
/// Columns are `.adaptive`, so the grid fits as many tiles as the width allows
/// and then divides the *whole* width between them. Fixed-width tiles would
/// leave a ragged gutter down the trailing edge whenever the pane width was not
/// an exact multiple of the tile size; this way every row spans the pane and
/// the tiles stay evenly spaced at any window size.
struct LibraryGrid: View {
    let bottles: [Bottle]
    let selectedID: Bottle.ID?
    let actions: BottleActions
    /// Click (or Return): select AND open the entry — Grid mode has no
    /// permanent pane, so opening is what a click has always meant here.
    let onSelect: (Bottle) -> Void
    /// Arrow-key movement: select only. Using `onSelect` for this would pop
    /// the detail overlay open and closed on every keypress, which is not
    /// what arrow-key browsing should do — it should just move the highlight,
    /// the same way the old row list's arrow keys never opened anything.
    let onHighlight: (Bottle) -> Void
    let onRequestRename: (Bottle) -> Void

    /// Minimum before the grid drops a column. Below roughly this width the
    /// name and the Launch button start truncating.
    private static let minTileWidth: CGFloat = 190

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Self.minTileWidth), spacing: spacing, alignment: .top)]
    }

    private var spacing: CGFloat { CrosswireLauncherTheme.Layout.tileSpacing }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var gridFocused: Bool
    /// How many columns `.adaptive` is actually rendering right now, so arrow
    /// keys can jump by a real row stride instead of guessing. There is no
    /// public API for this — `.adaptive` computes it internally — so it's
    /// measured via the same formula SwiftUI uses and kept in sync with the
    /// pane's real width through the preference key below.
    @State private var columnCount = 1

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                    ForEach(bottles) { bottle in
                        GameTile(bottle: bottle,
                                 isSelected: bottle.id == selectedID,
                                 isListFocused: gridFocused,
                                 actions: actions.bound(to: bottle),
                                 onRequestRename: { onRequestRename(bottle) },
                                 onSelect: { onSelect(bottle) })
                            .id(bottle.id)
                    }
                }
                .padding(.horizontal, CrosswireLauncherTheme.Layout.shelfPadding)
                .padding(.vertical, 18)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: GridWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(GridWidthKey.self) { width in
                columnCount = Self.columnCount(forPaneWidth: width, spacing: spacing, minWidth: Self.minTileWidth)
            }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                // No anchor: SwiftUI scrolls the minimum distance to reveal the
                // tile, so keyboard navigation brings it into view while a mouse
                // click on an already-visible tile does not yank the grid.
                guard !reduceMotion else { proxy.scrollTo(id); return }
                withAnimation(CrosswireTheme.Motion.navigation) { proxy.scrollTo(id) }
            }
            .focusable()
            .focused($gridFocused)
            .focusEffectDisabled()
            .onMoveCommand { moveHighlight($0) }
            .onKeyPress(.return) {
                guard let id = selectedID, let bottle = bottles.first(where: { $0.id == id }) else {
                    return .ignored
                }
                onSelect(bottle)
                return .handled
            }
            .onChange(of: gridFocused) { _, focused in
                guard focused, selectedID == nil, let first = bottles.first else { return }
                onHighlight(first)
            }
        }
    }

    /// Moves the highlight by one row (`columnCount` positions) or one column,
    /// clamped at the grid's edges — never wrapping, matching the row list and
    /// `LibraryRail`'s behavior. Seeds to the first tile if nothing is
    /// highlighted yet.
    private func moveHighlight(_ direction: MoveCommandDirection) {
        guard !bottles.isEmpty else { return }
        guard let current = selectedID, let idx = bottles.firstIndex(where: { $0.id == current }) else {
            if let first = bottles.first { onHighlight(first) }
            return
        }
        let stride = max(1, columnCount)
        let target: Int
        switch direction {
        case .up:    target = idx - stride
        case .down:  target = idx + stride
        case .left:  target = idx - 1
        case .right: target = idx + 1
        default: return
        }
        guard bottles.indices.contains(target) else { return }
        onHighlight(bottles[target])
    }

    /// Mirrors the formula SwiftUI's `GridItem(.adaptive(minimum:))` uses
    /// internally: as many `minWidth`-or-larger columns as fit in the
    /// available width, each stretched to fill it evenly. `paneWidth` is the
    /// raw measured width; the grid's own horizontal padding is subtracted
    /// before the column math so this matches what `.adaptive` actually sees.
    private static func columnCount(forPaneWidth paneWidth: CGFloat, spacing: CGFloat, minWidth: CGFloat) -> Int {
        let usable = paneWidth - 2 * CrosswireLauncherTheme.Layout.shelfPadding
        guard usable > 0 else { return 1 }
        return max(1, Int((usable + spacing) / (minWidth + spacing)))
    }
}

private struct GridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
