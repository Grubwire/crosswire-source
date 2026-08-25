//
//  BannerArt.swift
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

/// Shared machinery for `TileArtView` and `HeroArtView`: resolving a rendered
/// banner for a bottle's candidate `.exe`s at a given pixel size.

/// Identifies one banner request: which exe candidates to try, at what size.
/// Rounds the size to whole pixels so sub-pixel layout jitter across redraws
/// doesn't retrigger a render `BannerRenderer` would cache identically anyway.
struct BannerRequestKey: Equatable {
    let urls: [URL]
    let width: Int
    let height: Int

    init(urls: [URL], size: CGSize) {
        self.urls = urls
        self.width = Int(size.width)
        self.height = Int(size.height)
    }
}

/// Tries `bottle`'s candidate `.exe`s in order, returning the first rendered
/// banner. Mirrors `AppIcon`'s fallback chain (`Bottle.artCandidateURLs`) so a
/// title without a usable icon on its primary exe still gets a banner if a
/// secondary program has one.
@MainActor
func resolveBanner(for bottle: Bottle, size: CGSize) async -> NSImage? {
    for url in bottle.artCandidateURLs {
        if let banner = await BannerRenderer.banner(forExe: url, size: size) {
            return banner
        }
    }
    return nil
}
