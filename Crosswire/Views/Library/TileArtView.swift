//
//  TileArtView.swift
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

/// The art plate on a library tile: `BannerRenderer`'s rendered banner once it
/// resolves, falling back to the entry's extracted icon centred on a tinted
/// ground while it does (or if rendering never succeeds).
///
/// Sizes itself to whatever width the grid cell gives it rather than taking a
/// fixed width, so tiles share the available space evenly and the grid has no
/// leftover gutter down one side.
///
/// This was the Phase 2 seam — wiring `BannerRenderer` in was a body-only
/// change, `GameTile` never touches the art directly.
/// `BannerRenderer.banner(forExe:size:)` takes an arbitrary `CGSize` and
/// composes proportionally, so a future banner needs no change to the
/// renderer, only a different `aspect` here.
struct TileArtView: View {
    @ObservedObject var bottle: Bottle
    /// Width / height of the plate. 1 is square, which is what the extracted
    /// icons are.
    var aspect: CGFloat = 1

    @State private var banner: NSImage?

    var body: some View {
        // GeometryReader inside the aspect-ratio frame, so the art scales with
        // the cell instead of being pinned to a hardcoded size. Without this the
        // art stays one size while the plate grows, which reads as it sitting
        // off-centre in a too-large box.
        Rectangle()
            .fill(ground)
            .overlay {
                GeometryReader { geo in
                    art(size: geo.size)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: CrosswireLauncherTheme.Layout.tileCornerRadius,
                                        style: .continuous))
    }

    @ViewBuilder
    private func art(size: CGSize) -> some View {
        Group {
            if let banner {
                Image(nsImage: banner)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .accessibilityHidden(true)
                    .transition(.opacity)
            } else {
                AppIcon(bottle: bottle, side: min(size.width, size.height) * 0.58)
            }
        }
        .animation(.easeOut(duration: 0.2), value: banner == nil)
        .task(id: BannerRequestKey(urls: bottle.artCandidateURLs, size: size)) {
            banner = await resolveBanner(for: bottle, size: size)
        }
    }

    /// Deterministic per-entry tint, the same hash the monogram tiles use, so
    /// an entry keeps one colour identity everywhere it appears. Shown behind
    /// the icon-only fallback, and briefly beneath it while the banner is
    /// still resolving.
    private var ground: LinearGradient {
        let base = CrosswireTheme.colorForLibraryEntry(name: bottle.displayName)
        return LinearGradient(colors: [base, base.opacity(0.62)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
