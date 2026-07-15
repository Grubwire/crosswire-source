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
                            EngineSetupView(showSetup: $showSetup)
                        }
                    }
            }
        }
        .padding()
        .interactiveDismissDisabled()
    }
}
