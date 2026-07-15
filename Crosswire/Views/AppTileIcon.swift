//
//  AppTileIcon.swift
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

/// Up to two uppercase initials drawn from the leading word characters of an
/// app name. Falls back to the first two characters if no word boundary is
/// found.
func initialsForProgramName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "?" }
    let words = trimmed.split { !$0.isLetter && !$0.isNumber }
    if words.isEmpty {
        return String(trimmed.prefix(2)).uppercased()
    }
    if words.count == 1 {
        return String(words[0].prefix(2)).uppercased()
    }
    let first = words[0].first.map { String($0) } ?? ""
    let second = words[1].first.map { String($0) } ?? ""
    return (first + second).uppercased()
}

/// Compatibility shim — old call sites used `colorForProgramName` directly;
/// canonical access is `CrosswireTheme.colorForLibraryEntry(name:)`.
func colorForProgramName(_ name: String) -> Color {
    return CrosswireTheme.colorForLibraryEntry(name: name)
}

/// Rounded-square tile rendering a library entry's monogram on top of one
/// of the four icon-derived tile colors (deterministic per name — same entry
/// always gets the same color). Sized at `side` points; corner radius
/// matches macOS icon convention (`side * 0.22`).
///
/// This is the monogram-FALLBACK appearance — used when an extracted .exe
/// icon isn't available (Brief 4 work). Real icons render at the same
/// size + corner radius so they coexist visually in the library row.
struct AppTileIcon: View {
    let name: String
    var side: CGFloat = CrosswireTheme.Layout.libraryRowIconSide

    private var base: Color { CrosswireTheme.colorForLibraryEntry(name: name) }
    private var cornerRadius: CGFloat { max(6, side * 0.22) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [base, base.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            // Inner top highlight — reads as light catching the surface
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.75)
                .blendMode(.plusLighter)
                .mask(
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            Text(initialsForProgramName(name))
                .font(.system(size: side * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
        }
        .frame(width: side, height: side)
        .shadow(color: base.opacity(0.35), radius: side * 0.06, x: 0, y: side * 0.04)
        // Decorative monogram fallback — the entry name always sits beside it,
        // so VoiceOver should read the name, not the initials.
        .accessibilityHidden(true)
    }
}

/// A library entry's icon: the real icon extracted from the bottle's primary
/// `.exe` when one is embedded, falling back to the monogram tile otherwise.
/// Extraction is off the main actor + cached (see `AppIconExtractor`), so the
/// list never janks re-parsing PE resources on every row appearance.
struct AppIcon: View {
    @ObservedObject var bottle: Bottle
    var side: CGFloat = CrosswireTheme.Layout.libraryRowIconSide

    @State private var image: NSImage?

    private var cornerRadius: CGFloat { max(6, side * 0.22) }

    /// Which `.exe`'s icon represents this entry: the primary launcher if set,
    /// else the first user-visible program, else the first installed program.
    private var iconSourceURL: URL? {
        if let primary = bottle.settings.primaryProgramURL { return primary }
        if let visible = bottle.userVisiblePrograms.first?.url { return visible }
        return bottle.programs.first?.url
    }

    var body: some View {
        Group {
            if let image, image.isValid, image.size.width > 0 {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: side * 0.06, x: 0, y: side * 0.04)
                    .accessibilityHidden(true)
            } else {
                AppTileIcon(name: bottle.displayName, side: side)
            }
        }
        .task(id: iconSourceURL) {
            guard let url = iconSourceURL else { image = nil; return }
            image = await AppIconExtractor.icon(at: url)
        }
    }
}

/// Extracts + memoizes the best embedded icon from a Windows `.exe`. The PE
/// parse + icon decode is file I/O, so it runs off the main actor; results
/// (positive and negative) are cached on the main actor keyed by the exe URL.
@MainActor
enum AppIconExtractor {
    private static var cache: [URL: NSImage] = [:]
    private static var noIcon: Set<URL> = []

    static func icon(at url: URL) async -> NSImage? {
        if let cached = cache[url] { return cached }
        if noIcon.contains(url) { return nil }
        let extracted = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let peFile = try? PEFile(url: url),
                  let icon = peFile.bestIcon(),
                  icon.isValid, icon.size.width > 0 else { return nil }
            return icon
        }.value
        if let extracted {
            cache[url] = extracted
        } else {
            noIcon.insert(url)
        }
        return extracted
    }
}
