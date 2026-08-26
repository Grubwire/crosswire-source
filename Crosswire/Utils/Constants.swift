//
//  Constants.swift
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

import Foundation

enum ViewWidth {
    static let small: Double = 400
    static let medium: Double = 500
    static let large: Double = 600
}

/// The app's fixed window size. Crosswire is a launcher, not a document
/// window, so it does not resize: one size, chosen to hold the library
/// sidebar plus the hero pane without the user having to arrange anything.
///
/// Sized to fit comfortably on a 13" MacBook Air (1470x956 logical points)
/// with room for the menu bar and Dock.
enum WindowSize {
    static let width: CGFloat = 1080
    static let height: CGFloat = 720
}
