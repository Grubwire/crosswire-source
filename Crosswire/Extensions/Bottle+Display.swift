//
//  Bottle+Display.swift
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

import AppKit
import CrosswireKit

/// Presentation helpers shared by every view that renders a library entry.
///
/// These were duplicated between `AppRow` and `EntryDetailView` — two copies of
/// the relative-date formatter, two `canLaunch`, two `revealInFinder`. The
/// library redesign adds a third and fourth consumer (the sidebar tile and the
/// hero pane), so they live here instead. Kept out of `Bottle+Extensions.swift`
/// deliberately: that file is already over the SwiftLint length limit and
/// carries its own `file_length` exemption.
extension Bottle {

    /// Whether the primary Launch action can do anything right now.
    var canLaunch: Bool {
        !programs.isEmpty && isAvailable
    }

    /// "2 hours ago" — relative, spelled out. `nil` when never launched, so
    /// callers choose their own phrasing for that case.
    var lastPlayedDescription: String? {
        guard let last = settings.lastLaunched else { return nil }
        return Self.relativeFormatter.localizedString(for: last, relativeTo: Date())
    }

    /// The metadata line under an entry's name:
    /// - "Setting up…" while the entry is being provisioned (in-flight)
    /// - "Last played <relative>" once it has been launched
    /// - "Never launched" before the first launch
    var librarySecondaryLine: String {
        if inFlight { return "Setting up…" }
        guard let relative = lastPlayedDescription else { return "Never launched" }
        return "Last played \(relative)"
    }

    /// Reveal the entry's folder in Finder.
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Ordered `.exe`s that could represent this entry: the primary launcher
    /// first, then other user-visible programs, then any other installed
    /// program. Shared by icon extraction (`AppIcon`) and banner rendering
    /// (`resolveBanner`) so both land on the same exe when an earlier
    /// candidate's icon fails to decode.
    var artCandidateURLs: [URL] {
        var seen: Set<URL> = []
        var candidates: [URL] = []
        func add(_ url: URL?) {
            guard let url, seen.insert(url).inserted else { return }
            candidates.append(url)
        }
        add(settings.primaryProgramURL)
        for program in userVisiblePrograms { add(program.url) }
        for program in programs { add(program.url) }
        return candidates
    }

    /// One formatter for the whole app. `RelativeDateTimeFormatter` is
    /// comparatively expensive to build, and every row previously made its own.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

extension Program {
    /// The program's name without its extension — what a user should see in a
    /// picker or a program list. `name` itself is the raw filename, and three
    /// separate call sites were each stripping ".exe" inline.
    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }
}
