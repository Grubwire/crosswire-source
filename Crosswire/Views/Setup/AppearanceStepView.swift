//
//  AppearanceStepView.swift
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

/// First-run appearance step. Choosing here writes the same defaults key
/// Settings › General writes, and the change is live immediately — the swatch
/// the user picks is the window they are already looking at.
struct AppearanceStepView: View {
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Choose your appearance")
                    .font(CrosswireTheme.Typography.title)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Text("You can change this later in Settings.")
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            Spacer(minLength: 16)
            AppearancePicker(swatchWidth: 104, swatchHeight: 68)
            Spacer(minLength: 16)

            HStack {
                Spacer()
                Button("Continue") { path.append(.guide) }
                    .buttonStyle(.borderedProminent)
                    .tint(CrosswireTheme.accent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(height: 32)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .frame(width: 420, height: 320)
        .navigationBarBackButtonHidden(true)
    }
}
