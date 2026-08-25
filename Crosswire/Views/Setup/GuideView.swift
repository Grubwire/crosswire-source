//
//  GuideView.swift
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

/// The last first-run step: how to actually use the app.
///
/// Deliberately four lines, not a tour. Everything Crosswire asks of a user is
/// "add a Windows app, then press Play", and a longer walkthrough would imply
/// more ceremony than the product has. Per the naming rule, nothing here names
/// the compatibility layer, wrappers, or versions — the user installs apps and
/// runs them, and the machinery stays invisible.
struct GuideView: View {
    @Binding var showSetup: Bool

    private struct Step: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private static let steps: [Step] = [
        Step(icon: "square.and.arrow.down",
             title: "Add a Windows app",
             detail: "Drag its installer onto the window, or use + Install in the toolbar. "
                   + "Discs and .iso files work too."),
        Step(icon: "play.fill",
             title: "Press Play",
             detail: "Pick anything in your library and launch it. Crosswire sets up whatever "
                   + "that app needs the first time it runs."),
        Step(icon: "square.grid.2x2",
             title: "Everything stays separate",
             detail: "Each app gets its own space, so one app's files and settings can never "
                   + "disturb another's."),
        Step(icon: "lifepreserver",
             title: "If something goes wrong",
             detail: "Open the Crosswire menu for Settings and diagnostics. If an app stops "
                   + "unexpectedly, you'll be offered a report you can review before sending.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("You're all set")
                    .font(CrosswireTheme.Typography.title)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Text("Here's the whole app in four lines.")
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textSecondary)
            }
            .padding(.top, 8)

            Spacer(minLength: 14)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.steps) { step in
                    row(step)
                }
            }
            Spacer(minLength: 14)

            HStack {
                Spacer()
                Button("Get Started") {
                    SetupFlow.markGuideCompleted()
                    showSetup = false
                }
                    .buttonStyle(.borderedProminent)
                    .tint(CrosswireTheme.accent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(height: 32)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .frame(width: 460, height: 420)
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func row(_ step: Step) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(CrosswireTheme.accent)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Text(step.detail)
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
