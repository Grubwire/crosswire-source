//
//  LibraryRail.swift
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

/// Sidebar mode's left column: search field over a scrolling column of
/// `LibraryRow`s. Selection lives in the shared `LibrarySelection`, not here,
/// so it survives a switch to Grid mode and back.
struct LibraryRail: View {
    let bottles: [Bottle]
    @Binding var searchText: String
    @ObservedObject var selection: LibrarySelection
    let actions: BottleActions
    let onRequestRename: (Bottle) -> Void

    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filtered: [Bottle] {
        if searchText.isEmpty { return bottles }
        return bottles.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            if filtered.isEmpty {
                noMatch
            } else {
                rows
            }
        }
        .frame(width: CrosswireLauncherTheme.Layout.sidebarWidth)
        .background(CrosswireLauncherTheme.backgroundRaised)
        // Invisible Cmd-F, matching the accelerator every Mac search field
        // offers, without pulling in a Scene-level `.commands` entry for one
        // field in one mode.
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
        )
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(CrosswireLauncherTheme.textTertiary)
                .accessibilityHidden(true)
            TextField("Search…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(CrosswireLauncherTheme.textPrimary)
                .focused($searchFocused)
                .onSubmit { listFocused = true }
                .accessibilityLabel("Search your library")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(CrosswireLauncherTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(searchFocused ? CrosswireLauncherTheme.accent.opacity(0.55)
                                            : CrosswireLauncherTheme.stroke, lineWidth: 1)
        )
        .padding(10)
        .animation(CrosswireTheme.Motion.hover, value: searchFocused)
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filtered) { bottle in
                        LibraryRow(bottle: bottle,
                                  isSelected: selection.selectedID == bottle.id,
                                  isListFocused: listFocused,
                                  actions: actions.bound(to: bottle),
                                  onSelect: { selection.select(bottle) })
                            .id(bottle.id)
                            .contextMenu {
                                Button { actions.run(bottle) } label: {
                                    Label("Launch", systemImage: "play.fill")
                                }
                                .disabled(!bottle.canLaunch)
                                Button { onRequestRename(bottle) } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button { bottle.revealInFinder() } label: {
                                    Label("Show in Finder", systemImage: "folder")
                                }
                                Divider()
                                Button(role: .destructive) { actions.uninstall(bottle) } label: {
                                    Label("Uninstall…", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .onChange(of: selection.selectedID) { _, id in
                guard let id else { return }
                // No anchor: the minimum scroll to reveal the row, so keyboard
                // nav brings it on screen without yanking the list on a click.
                guard !reduceMotion else { proxy.scrollTo(id); return }
                withAnimation(CrosswireTheme.Motion.navigation) { proxy.scrollTo(id) }
            }
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            selection.move(direction, in: filtered)
        }
        .onKeyPress(.return) {
            guard let id = selection.selectedID,
                  let bottle = filtered.first(where: { $0.id == id }) else { return .ignored }
            actions.run(bottle)
            return .handled
        }
    }

    private var noMatch: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(CrosswireLauncherTheme.textTertiary)
            Text("No matches")
                .font(.system(size: 12))
                .foregroundStyle(CrosswireLauncherTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
