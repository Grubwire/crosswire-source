//
//  BottleRenameField.swift
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

/// An entry's name, which becomes an editable field while `isEditing` is true.
///
/// One implementation for every place a library entry can be renamed. The row
/// and the detail view each had their own copy, identical apart from the font,
/// which meant two chances for the commit rules to drift apart.
///
/// Commit rules, unchanged from the originals: Return commits, Escape cancels
/// without saving, and committing an empty or whitespace-only name clears the
/// override so the entry falls back to its detected name rather than becoming
/// nameless.
struct BottleRenameField: View {
    @ObservedObject var bottle: Bottle
    /// Owned by the caller so a rename can be started from elsewhere — a
    /// context menu on one view driving the field on another.
    @Binding var isEditing: Bool
    var font: Font
    var maxWidth: CGFloat?

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("App name", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { commit() }
                    .onExitCommand { isEditing = false }
                    .frame(maxWidth: maxWidth)
                    // Seeded here rather than in an onChange of `isEditing`, so
                    // the draft is populated before the field can render, and
                    // focus lands on a field that already holds the old name.
                    .onAppear {
                        draft = bottle.displayName
                        DispatchQueue.main.async { focused = true }
                    }
            } else {
                Text(bottle.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(font)
        .foregroundStyle(CrosswireTheme.textPrimary)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        if trimmed.isEmpty {
            bottle.settings.appDisplayName = nil
        } else if trimmed != bottle.displayName {
            bottle.settings.appDisplayName = trimmed
        }
    }
}
