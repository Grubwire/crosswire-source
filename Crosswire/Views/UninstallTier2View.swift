//
//  UninstallTier2View.swift
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

/// Tier 2 of the uninstall flow (#110): confirms deletion of installed apps
/// and their data specifically, separate from and harder to trigger than the
/// Tier 1 "clean up Crosswire data" step. Lists every bottle by name with an
/// approximate combined size, and requires an explicit acknowledgement
/// checkbox before the destructive button enables -- bottles are
/// irreplaceable user data (installed games/apps and their save data); the
/// rest of the uninstall flow is not.
struct UninstallTier2View: View {
    let bottles: [Bottle]
    let onDecision: (Bool) -> Void

    @State private var acknowledged = false
    @State private var totalBytes: Int64?
    @State private var sizesLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Also delete your installed apps?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Text("The apps below and all their data will be permanently deleted. This cannot be undone.")
                    .font(.system(size: 12))
                    .foregroundStyle(CrosswireTheme.textSecondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(bottles) { bottle in
                        Text(bottle.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(CrosswireTheme.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)

            Text(sizeSummary)
                .font(.system(size: 11))
                .foregroundStyle(CrosswireTheme.textSecondary)

            Toggle(isOn: $acknowledged) {
                Text("I understand this permanently deletes these apps and their data.")
                    .font(.system(size: 12))
                    .foregroundStyle(CrosswireTheme.textPrimary)
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Keep My Apps") { onDecision(false) }
                    .buttonStyle(CrosswireButtonStyle(kind: .secondary))
                Button("Delete Apps and Data") { onDecision(true) }
                    .buttonStyle(CrosswireButtonStyle(kind: .destructive))
                    .disabled(!acknowledged)
            }
        }
        .padding(20)
        .frame(width: 420)
        .task {
            let bottleURLs = bottles.map(\.url)
            let total = await Task.detached(priority: .utility) { () -> Int64 in
                bottleURLs.reduce(Int64(0)) { partial, url in
                    partial + (BottleDiskUsage.approximateSize(of: url) ?? 0)
                }
            }.value
            totalBytes = total
            sizesLoaded = true
        }
    }

    private var sizeSummary: String {
        guard sizesLoaded else { return "Calculating size…" }
        return UninstallSizeSummary.summary(totalBytes: totalBytes, appCount: bottles.count)
    }
}
