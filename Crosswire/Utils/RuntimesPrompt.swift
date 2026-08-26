//
//  RuntimesPrompt.swift
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
import CrosswireKit

/// State bundle for the `DetectedRuntimesSheet` while it's presented from
/// the install flow. Carries a `CheckedContinuation` so the awaiting
/// `provisionAndInstall` task suspends until the user picks an action.
struct RuntimesPrompt: Identifiable {
    let id = UUID()
    let exeName: String
    let detected: [DetectedRuntime]
    let bottle: Bottle
    let continuation: CheckedContinuation<[String], Never>
}
