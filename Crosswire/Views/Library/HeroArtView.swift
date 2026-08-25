//
//  HeroArtView.swift
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

/// The banner behind the selected entry's name in Sidebar mode's detail pane.
///
/// This was the other Phase 2 seam, alongside `TileArtView`. The rendered
/// banner replaces the icon-and-gradient placeholder once it resolves; the
/// scrim and title stay exactly as they were, since they were already sized
/// for real art. `BannerImagePipeline` bakes its own darkening and bottom
/// scrim into every image it produces (see `CrosswireLauncherTheme`'s note on
/// why the hero scrims are fixed-dark, not adaptive) — layering
/// `CrosswireLauncherTheme.heroScrim` on top of that is deliberate double
/// coverage for the title text, not redundant.
struct HeroArtView: View {
    @ObservedObject var bottle: Bottle

    @State private var banner: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [ground, ground.opacity(0.55)],
                          startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    GeometryReader { geo in
                        art(size: geo.size)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            CrosswireLauncherTheme.heroScrim
            Text(bottle.displayName)
                .font(CrosswireLauncherTheme.Typography.heroTitle)
                .foregroundStyle(CrosswireLauncherTheme.textOnArt)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
        .frame(minHeight: CrosswireLauncherTheme.Layout.heroMinHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                AppIcon(bottle: bottle, side: 96)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -18)
            }
        }
        .animation(.easeOut(duration: 0.2), value: banner == nil)
        .task(id: BannerRequestKey(urls: bottle.artCandidateURLs, size: size)) {
            banner = await resolveBanner(for: bottle, size: size)
        }
    }

    private var ground: Color {
        CrosswireTheme.colorForLibraryEntry(name: bottle.displayName)
    }
}
