//
//  SetupView.swift
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

enum SetupStage {
    case rosetta
    case engineSetup
    /// Pick Dark / Light / System. First run only.
    case appearance
    /// The four-line "how to use this" screen. First run only.
    case guide
}

/// Shared terminal step for the setup flow.
///
/// Setup can end at three different places depending on what was already
/// installed: `WelcomeView` when nothing needs doing, `RosettaView`, or
/// `EngineSetupView`. All three call `finish` rather than dismissing directly,
/// so the appearance + guide screens cannot be skipped just because a machine
/// happened to arrive with the prerequisites already in place.
enum SetupFlow {
    /// Set once the guide has been shown. Gates the two first-run-only stages.
    static let guideCompletedKey = "hasCompletedGuide"

    static var hasCompletedGuide: Bool {
        UserDefaults.standard.bool(forKey: guideCompletedKey)
    }

    static func markGuideCompleted() {
        UserDefaults.standard.set(true, forKey: guideCompletedKey)
    }

    /// Either continue into the first-run screens, or close setup.
    @MainActor
    static func finish(path: Binding<[SetupStage]>, showSetup: Binding<Bool>) {
        if hasCompletedGuide {
            showSetup.wrappedValue = false
        } else {
            path.wrappedValue.append(.appearance)
        }
    }
}

struct SetupView: View {
    @State private var path: [SetupStage]
    @Binding var showSetup: Bool
    var firstTime: Bool

    init(startingStage: SetupStage? = nil, showSetup: Binding<Bool>, firstTime: Bool = true) {
        self._path = State(initialValue: startingStage.map { [$0] } ?? [])
        self._showSetup = showSetup
        self.firstTime = firstTime
    }

    var body: some View {
        VStack {
            NavigationStack(path: $path) {
                WelcomeView(path: $path, showSetup: $showSetup, firstTime: firstTime)
                    .navigationBarBackButtonHidden(true)
                    .navigationDestination(for: SetupStage.self) { stage in
                        switch stage {
                        case .rosetta:
                            RosettaView(path: $path, showSetup: $showSetup)
                        case .engineSetup:
                            EngineSetupView(path: $path, showSetup: $showSetup)
                        case .appearance:
                            AppearanceStepView(path: $path, showSetup: $showSetup)
                        case .guide:
                            GuideView(showSetup: $showSetup)
                        }
                    }
            }
        }
        .padding()
        .interactiveDismissDisabled()
    }
}
