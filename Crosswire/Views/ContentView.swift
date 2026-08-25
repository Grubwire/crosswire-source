//
//  ContentView.swift
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
import AppKit
import CrosswireKit
import SemanticVersion
import Sparkle

// swiftlint:disable type_body_length file_length
struct ContentView: View {
    @AppStorage("checkEngineUpdates") var checkEngineUpdates = true
    @EnvironmentObject var bottleVM: BottleVM
    @Binding var showSetup: Bool
    let sparkleUpdater: SPUUpdater?

    @State var bottlesLoaded: Bool = false
    @State var searchText: String = ""
    @State var openedFileURL: URL?
    @State var setupStartingStage: SetupStage?

    /// Top-level navigation. Library is the default; Settings + per-entry
    /// detail are full-bleed inline destinations that slide in over the
    /// library view. See `AppRoute` for the full rationale.
    @State var route: AppRoute = .library

    @State var provisioningMessage: String?
    @State var runtimesPrompt: RuntimesPrompt?
    @State var dropTargeted: Bool = false
    @StateObject private var selection = LibrarySelection()
    /// Set while waiting for an installer to exit; non-nil drives the overlay's
    /// "Finish Setup" escape hatch so a portable GUI app (which never exits)
    /// can't trap the UI on "Running installer…". See `waitForInstallerOrFinish`.
    @State var finishInstallerWait: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var emptyHeroAppeared = false

    init(showSetup: Binding<Bool>, sparkleUpdater: SPUUpdater? = nil) {
        self._showSetup = showSetup
        self.sparkleUpdater = sparkleUpdater
    }

    var body: some View {
        ZStack {
            // Library is the always-present base layer. Settings + per-entry
            // detail overlay it with slide-in transitions. Library doesn't
            // animate out — the overlay just covers it.
            libraryRoot

            if route == .settings {
                InlineSettingsView(updater: sparkleUpdater) {
                    withAnimation(CrosswireTheme.Motion.navigation) {
                        route = .library
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(1)
            }

            if case let .entryDetail(id) = route,
               let bottle = bottleVM.bottles.first(where: { $0.id == id }) {
                EntryDetailView(
                    bottle: bottle,
                    onBack: { withAnimation(CrosswireTheme.Motion.navigation) { route = .library } },
                    onRun: { runPrimary(for: bottle) },
                    onRunProgram: { program in run(program: program, bottle: bottle) },
                    onUninstall: { uninstall(bottle) },
                    onLaunchDiagnostics: { runWithDiagnostics(for: bottle) }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CrosswireTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Crosswire")
        .toolbar { crosswireToolbar }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(fileURL: url,
                         currentBottle: nil,
                         bottles: bottleVM.bottles)
        }
        .sheet(item: $runtimesPrompt) { prompt in
            DetectedRuntimesSheet(
                exeName: prompt.exeName,
                detected: prompt.detected,
                bottle: prompt.bottle
            ) { installed in
                prompt.continuation.resume(returning: installed)
                runtimesPrompt = nil
            }
        }
        .sheet(isPresented: $showSetup, onDismiss: { setupStartingStage = nil }, content: {
            SetupView(startingStage: setupStartingStage, showSetup: $showSetup, firstTime: false)
        })
        .overlay {
            if let message = provisioningMessage {
                ProvisioningOverlay(message: message, onCancel: finishInstallerWait)
            }
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .task {
            await onAppearTask()
        }
        // Reconciles the selection against installs/removals that happen
        // outside `uninstall(_:)` (a fresh install completing, a bottle
        // vanishing on disk). `uninstall(_:)` already reconciles explicitly
        // with the neighbor-selection rule; this is the general-purpose net.
        .onChange(of: bottleVM.bottles) { _, bottles in
            let sorted = bottles.sorted()
            if selection.selectedID == nil {
                selection.seed(from: sorted)
            } else {
                selection.reconcile(with: sorted)
            }
        }
        // Channel switch (Settings → Updates): the user already confirmed the
        // ~200 MB re-download, so swap the engine for the new channel by removing
        // the installed one and re-running setup (the manifest is channel-aware).
        .onReceive(NotificationCenter.default.publisher(for: .crosswireReprovisionEngine)) { _ in
            CrosswireEngine.uninstall()
            setupStartingStage = .engineSetup
            showSetup = true
        }
    }

    // MARK: - Library root (composes header + action row + content)

    /// The library view as a single composed surface. Sits at the base of
    /// the ZStack; the Settings (and per-entry, Section 2) overlays slide
    /// in over it. Extracted as its own var so the body-level ZStack stays
    /// readable.
    private var libraryRoot: some View {
        VStack(spacing: 0) {
            content
        }
        // Drop a Windows installer/executable anywhere on the library to start
        // the same install flow as the "Install" button (the empty state
        // invites exactly this). A faint accent border confirms the target.
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(of: urls)
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CrosswireTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .padding(12)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(CrosswireTheme.Motion.hover, value: dropTargeted)
    }

    // MARK: - Toolbar (native unified, replaces the old custom header)

    /// Native unified toolbar. Leading: the inline window title, set via
    /// `.navigationTitle` — plain text, not a control. Trailing: the settings
    /// gear, then the prominent blue "+" install button (the primary action).
    ///
    /// There is deliberately no brand menu here. About, Check for Updates and
    /// Quit all live in the macOS app menu already — About via
    /// `CommandGroup(replacing: .appInfo)` and updates via the `SparkleView`
    /// command group, both in `CrosswireApp` — so a toolbar menu carrying the
    /// same four items was duplicating the system menu bar.
    @ToolbarContentBuilder
    private var crosswireToolbar: some ToolbarContent {
        // Grid vs Sidebar. Meaningless (and hidden) with an empty library —
        // `emptyState` renders in place of the container then, so there is
        // nothing for it to switch between.
        if !bottleVM.bottles.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                LibraryViewModeSwitcher()
            }
        }

        // Settings gear sits just left of the prominent install CTA (split into
        // its own item below) so a group gap separates the secondary action
        // from the primary one. All actions belong on the trailing side.
        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation(CrosswireTheme.Motion.navigation) { route = .settings }
            } label: {
                Image(systemName: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }

        // Labeled "+ Install" (not a bare icon) — install is the app's primary
        // action and discoverability wins over toolbar minimalism. Its own item
        // so a group gap separates it from the secondary cluster; trailing
        // padding keeps it off the window edge. Suppressed when the library is
        // empty (the centered hero CTA is the single target there).
        if !bottleVM.bottles.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button(action: installWindowsApp) {
                    Label("Install", systemImage: "plus")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .tint(CrosswireTheme.accent)
                .help("Install a Windows game or app")
                .accessibilityLabel("Install a Game or App")
                .padding(.trailing, 6)
            }
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if !bottlesLoaded {
            loadingState
        } else if bottleVM.bottles.isEmpty {
            emptyState
        } else {
            LibraryContainerView(
                bottles: filteredSort,
                searchText: $searchText,
                selection: selection,
                actions: bottleActions,
                onLaunchDiagnostics: { runWithDiagnostics(for: $0) },
                onOpenDetail: { bottle in
                    selection.select(bottle)
                    withAnimation(CrosswireTheme.Motion.navigation) {
                        route = .entryDetail(bottle.id)
                    }
                }
            )
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// The `BottleActions` bundle every library view (grid tile, sidebar row,
    /// detail pane) drives its context menu and Play control through. One
    /// value routes back out through the same run helpers `ContentView`
    /// already used, so single-instance handling applies uniformly no matter
    /// which view triggered it.
    private var bottleActions: BottleActions {
        BottleActions(
            run: { runPrimary(for: $0) },
            runProgram: { bottle, program in run(program: program, bottle: bottle) },
            uninstall: { uninstall($0) },
            launchDiagnostics: { runWithDiagnostics(for: $0) }
        )
    }

    /// First-launch / empty-library state. Uses the app's own icon (single
    /// source of truth — if the icon changes, so does this view), the
    /// brand tagline, and the same blue CTA that drives the action row.
    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)
                .scaleEffect(emptyHeroAppeared ? 1 : 0.92)
                .opacity(emptyHeroAppeared ? 1 : 0)
                .shadow(color: CrosswireTheme.accent.opacity(emptyHeroAppeared ? 0.25 : 0),
                        radius: 24, x: 0, y: 8)
                .onAppear {
                    guard !reduceMotion else { emptyHeroAppeared = true; return }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                        emptyHeroAppeared = true
                    }
                }
            VStack(spacing: 8) {
                Text("Your Windows library, on Mac.")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CrosswireTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Drop a Windows .exe to install your first game or app.")
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: installWindowsApp) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Install a Game or App")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(PrimaryCTAButtonStyle(size: .prominent))
            .padding(.top, 4)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Derived

    /// Sorted, unfiltered. Search narrowing happens inside
    /// `LibraryContainerView` per mode, since Sidebar mode needs the full list
    /// to keep resolving the selected bottle even when search has filtered it
    /// out of the visible rail.
    var filteredSort: [Bottle] {
        bottleVM.bottles.sorted()
    }

    // MARK: - Lifecycle

    @MainActor
    private func onAppearTask() async {
        bottleVM.loadBottles()
        bottlesLoaded = true
        selection.seed(from: filteredSort)

        if !CrosswireEngine.isEnginePresent() {
            setupStartingStage = nil
            showSetup = true
            return
        }

        // First-run: ask once whether to send crash reports (opt-in, nothing sent
        // until the user chooses). No-op after the first answer.
        CrosswireTelemetry.requestConsentIfNeeded()

        let updateInfo = await CrosswireEngine.shouldUpdateEngine()
        guard checkEngineUpdates, updateInfo.0 else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "update.engine.title")
        alert.informativeText = String(format: String(localized: "update.engine.description"),
                                       String(CrosswireEngine.engineVersion()
                                              ?? SemanticVersion(0, 0, 0)),
                                       String(updateInfo.1))
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "update.engine.update"))
        alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            CrosswireEngine.uninstall()
            setupStartingStage = .engineSetup
            showSetup = true
        }
    }

    /// Confirm + remove an entry from the library (context-menu "Uninstall…").
    /// Deletes the bottle's files, drops it from the persisted path list, and
    /// reloads. Mirrors the per-app sheet's delete so both entry points behave
    /// identically.
    @MainActor
    private func uninstall(_ bottle: Bottle) {
        let alert = NSAlert()
        alert.messageText = "Uninstall \(bottle.displayName)?"
        alert.informativeText = "This removes the app's files and cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let before = filteredSort
        let removedIndex = before.firstIndex { $0.id == bottle.id }

        try? FileManager.default.removeItem(at: bottle.url)
        bottleVM.bottlesList.paths.removeAll { $0 == bottle.url }
        bottleVM.loadBottles()

        // Sidebar mode's pane follows the selection automatically; picking the
        // neighbor here means it never has to show a blank pane just because
        // the entry it was showing is gone.
        if let removedIndex {
            selection.selectAfterRemoval(indexBeforeRemoval: removedIndex, in: filteredSort)
        } else {
            selection.reconcile(with: filteredSort)
        }

        // Grid mode's overlay has no bottle left to resolve, so it would
        // otherwise disappear into a blank slide-in. Sidebar mode never routes
        // to .entryDetail, so this is a no-op there.
        if case .entryDetail = route {
            withAnimation(CrosswireTheme.Motion.navigation) { route = .library }
        }
    }
}

// swiftlint:enable type_body_length

/// Floating-card background: Liquid Glass on macOS 26, the branded surface fill
/// on older systems. Only for *transient* floating elements (overlays, popovers) —
/// persistent surfaces stay branded hex per the materials-vs-hex rule.
private struct FloatingGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 14
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(in: shape)
        } else {
            content
                .background(shape.fill(CrosswireTheme.surface))
                .overlay(shape.strokeBorder(CrosswireTheme.surfaceStroke, lineWidth: 1))
        }
    }
}

/// Modal overlay shown while a new app is being provisioned. When `onCancel`
/// is provided (during the installer-run wait), it offers a "Finish Setup"
/// escape hatch so a portable GUI app — which never exits, unlike an installer —
/// can't trap the UI on "Running installer…".
struct ProvisioningOverlay: View {
    let message: String
    var onCancel: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                Text(message)
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                    .multilineTextAlignment(.center)
                if let onCancel {
                    VStack(spacing: 8) {
                        Text("If your app is already open, you can finish setup.")
                            .font(CrosswireTheme.Typography.entryMeta)
                            .foregroundStyle(CrosswireTheme.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Finish Setup", action: onCancel)
                            .buttonStyle(CrosswireButtonStyle(kind: .secondary))
                    }
                    .padding(.top, 4)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: 320)
            .padding(28)
            .animation(CrosswireTheme.Motion.hover, value: onCancel == nil)
            .modifier(FloatingGlassCard())
            .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
        }
    }
}

#Preview {
    ContentView(showSetup: .constant(false))
        .environmentObject(BottleVM.shared)
}
