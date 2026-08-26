//
//  ProgramPickerList.swift
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

/// "Run…" list of an entry's launchers, shown when it has more than one and
/// the user asks to launch it. Extracted from the old row's popover so the
/// tile and the detail pane present the same list rather than two lookalikes.
struct ProgramPickerList: View {
    let programs: [Program]
    let onPick: (Program) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Run…")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CrosswireTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(programs) { program in
                Button {
                    onPick(program)
                } label: {
                    Text(program.displayName)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 200)
    }
}
