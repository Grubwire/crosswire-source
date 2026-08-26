//
//  LibrarySelection.swift
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

/// Which library entry is selected, shared by Grid and Sidebar mode so
/// switching modes never loses or resets it.
///
/// The rules that matter, in order of how often they get violated by a naive
/// `@State selectedID`:
///
/// 1. **Filtering never clears the selection.** Search narrows what is
///    scrollable, not what is selected — if it did, the Sidebar pane would
///    blank on every keystroke.
/// 2. **Deletion selects a neighbor**, not nil, so the pane never goes empty
///    just because the thing it was showing is gone.
/// 3. **Selection survives a mode switch.** Grid and Sidebar both read this
///    one object.
@MainActor
final class LibrarySelection: ObservableObject {
    @Published var selectedID: Bottle.ID?

    /// Where the selection is remembered across launches. A path, not a
    /// `Bottle.ID` — `UserDefaults` has no first-class `URL` array API and a
    /// bare `URL` round-trips fine as a string.
    private static let lastSelectedKey = "librarySelectionLastPath"

    /// Seed the selection on first load: the remembered entry if it still
    /// exists, otherwise the first entry in the (unfiltered) list.
    func seed(from bottles: [Bottle]) {
        guard selectedID == nil else { return }
        if let savedPath = UserDefaults.standard.string(forKey: Self.lastSelectedKey),
           let match = bottles.first(where: { $0.id.path == savedPath }) {
            selectedID = match.id
        } else {
            selectedID = bottles.first?.id
        }
    }

    /// Called whenever the full (unfiltered) bottle list changes. Keeps the
    /// selection if it still exists; otherwise falls back to the first entry,
    /// or nil if the library is now empty.
    func reconcile(with bottles: [Bottle]) {
        if let id = selectedID, bottles.contains(where: { $0.id == id }) { return }
        selectedID = bottles.first?.id
    }

    /// Select the entry directly.
    func select(_ bottle: Bottle) {
        selectedID = bottle.id
        persist()
    }

    /// After removing `bottle` from `remaining` (the list with it already
    /// gone), select its former neighbor rather than dropping to nil.
    /// `indexBeforeRemoval` is `bottle`'s index in the list as it stood right
    /// before removal.
    func selectAfterRemoval(indexBeforeRemoval: Int, in remaining: [Bottle]) {
        guard !remaining.isEmpty else { selectedID = nil; return }
        let clamped = min(indexBeforeRemoval, remaining.count - 1)
        selectedID = remaining[clamped].id
        persist()
    }

    /// Move the selection up/down within `filtered`, clamped at the ends —
    /// never wrapping, matching the row list's prior behavior. If the current
    /// selection isn't in `filtered` (search narrowed it out), arrow-down
    /// jumps to the first visible match and arrow-up to the last, so search
    /// constrains traversal without touching the selection rule above.
    /// Takes SwiftUI's own `MoveCommandDirection` directly rather than a
    /// second direction type — `.left`/`.right` fall through, matching the
    /// row list this replaces.
    func move(_ direction: MoveCommandDirection, in filtered: [Bottle]) {
        guard !filtered.isEmpty else { return }
        guard let current = selectedID,
              let idx = filtered.firstIndex(where: { $0.id == current }) else {
            selectedID = direction == .up ? filtered.last?.id : filtered.first?.id
            return
        }
        switch direction {
        case .up:   selectedID = filtered[max(0, idx - 1)].id
        case .down: selectedID = filtered[min(filtered.count - 1, idx + 1)].id
        default: break
        }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(selectedID?.path, forKey: Self.lastSelectedKey)
    }
}
