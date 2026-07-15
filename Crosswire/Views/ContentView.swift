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
    @State private var selectedBottleID: Bottle.ID?
    /// Set while waiting for an installer to exit; non-nil drives the overlay's
    /// "Finish Setup" escape hatch so a portable GUI app (which never exits)
    /// can't trap the UI on "Running installer…". See `waitForInstallerOrFinish`.
    @State var finishInstallerWait: (() -> Void)?

    @FocusState private var searchFocused: Bool
    @FocusState private var libraryFocused: Bool
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
            actionRow
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

    /// Native unified toolbar. Leading: brand icon + chevron menu (Settings /
    /// About / Check for Updates / Quit). The inline window title ("Crosswire")
    /// is set via `.navigationTitle` and renders next to the traffic lights.
    /// Trailing primary-action group: gear (Settings) and the prominent blue
    /// "+" install button — the primary action.
    /// App icon redrawn into a genuinely 18pt bitmap for the leading toolbar
    /// menu. Neither `.resizable().frame()` nor setting `.size` on a copy
    /// constrains the render inside a toolbar `Menu` label — SwiftUI keeps the
    /// source's full-size representations and the icon bleeds over the content
    /// below. Redrawing produces an image whose intrinsic size really is 18pt.
    private static let brandToolbarIcon: NSImage = {
        let side: CGFloat = 18
        let source = NSApplication.shared.applicationIconImage ?? NSImage()
        // Block-based redraw: intrinsic size is a true 18pt (fixes the toolbar
        // Menu label keeping the source's full-size reps), and the closure is
        // invoked at the backing scale so it stays crisp on Retina. Drawing
        // into the full rect centers the source content within the bounds.
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            // INTENTIONAL off-center draw — do NOT "fix" this to y: 0.
            //
            // The toolbar Menu button seats its label ~1.75pt high in the
            // bordered capsule, and the control ignores SwiftUI .offset/.padding
            // on the label (verified: a 2pt .offset moved the icon only ~0.25pt).
            // So we compensate by baking the downward nudge into the bitmap.
            // Drawing the source centered (y: 0) makes the icon visibly sit
            // high in the capsule again — that is the bug this shift corrects.
            //
            // Non-flipped origin is bottom-left, so a negative y shifts the
            // glyph down; the source's built-in bottom margin absorbs the shift
            // without clipping glyph content.
            let shift: CGFloat = 1.75
            source.draw(in: NSRect(x: 0, y: -shift, width: side, height: side),
                        from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }()

    @ToolbarContentBuilder
    private var crosswireToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("Settings…") {
                    withAnimation(CrosswireTheme.Motion.navigation) { route = .settings }
                }
                Button("About Crosswire") { CrosswireApp.openAboutWindow() }
                Button("Check for Updates…") { sparkleUpdater?.checkForUpdates() }
                Divider()
                Button("Quit Crosswire") { NSApp.terminate(nil) }
            } label: {
                Image(nsImage: Self.brandToolbarIcon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            .menuIndicator(.visible)
            .help("Crosswire")
            .accessibilityLabel("Crosswire menu")
            // A touch more inset from the traffic lights.
            .padding(.leading, 6)
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

    // MARK: - Action row (search)

    /// Library search. The "Install a Game or App" CTA moved to the toolbar's
    /// trailing primary-action group (Commit 2); this row now just hosts the
    /// search field below the toolbar.
    private var actionRow: some View {
        HStack(spacing: 12) {
            librarySearchField
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    /// Search field with the theme's surface fill and a blue focus ring that
    /// honors the Crosswire accent instead of the user's system accent
    /// (which could be orange and clash with the icon).
    private var librarySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CrosswireTheme.textTertiary)
                .accessibilityHidden(true)
            TextField("Search your library…", text: $searchText)
                .textFieldStyle(.plain)
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
                .focused($searchFocused)
                .accessibilityLabel("Search your library")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CrosswireTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    searchFocused ? CrosswireTheme.accent.opacity(0.55) : CrosswireTheme.surfaceStroke,
                    lineWidth: 1
                )
        )
        .frame(maxWidth: .infinity)
        .animation(CrosswireTheme.Motion.hover, value: searchFocused)
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if !bottlesLoaded {
            loadingState
        } else if bottleVM.bottles.isEmpty {
            emptyState
        } else if filteredBottles.isEmpty {
            noMatchState
        } else {
            library
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

    private var noMatchState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(CrosswireTheme.textTertiary)
            Text("Nothing in your library matches “\(searchText)”")
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// The library list. Section label sits above the rows so the user
    /// understands what they're looking at — and it gives the surface a
    /// header anchor instead of floating rows on a gradient.
    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Library")
                    .cwSectionHeader()
                Spacer()
                Text("^[\(filteredBottles.count) item](inflect: true)")
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredBottles) { bottle in
                        AppRow(
                            bottle: bottle,
                            isSelected: libraryFocused && selectedBottleID == bottle.id,
                            onRun: { runPrimary(for: bottle) },
                            onRunSpecific: { program in
                                run(program: program, bottle: bottle)
                            },
                            onShowDetails: {
                                selectedBottleID = bottle.id
                                withAnimation(CrosswireTheme.Motion.navigation) {
                                    route = .entryDetail(bottle.id)
                                }
                            },
                            onUninstall: { uninstall(bottle) },
                            onLaunchDiagnostics: { runWithDiagnostics(for: bottle) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .animation(.default, value: bottleVM.bottles)
            .animation(.default, value: searchText)
            // Keyboard navigation: arrow keys move the selection, Return
            // launches it. Selection only shows while the list is focused, so
            // there's no resting highlight for mouse users.
            .focusable()
            .focused($libraryFocused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                moveLibrarySelection(direction)
            }
            .onKeyPress(.return) {
                guard let id = selectedBottleID,
                      let bottle = filteredBottles.first(where: { $0.id == id }) else { return .ignored }
                runPrimary(for: bottle)
                return .handled
            }
            .onChange(of: libraryFocused) { _, focused in
                if focused, selectedBottleID == nil { selectedBottleID = filteredBottles.first?.id }
            }
        }
        // The library is a contained surface (Battle.net favorites-bar
        // pattern): branded hex region over the page gradient, not a material.
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CrosswireTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CrosswireTheme.regionBorder, lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
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

    var filteredBottles: [Bottle] {
        let sorted = bottleVM.bottles.sorted()
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Move the keyboard selection up/down within the current (filtered) list,
    /// clamped at the ends. Seeds to the first row if nothing is selected yet.
    private func moveLibrarySelection(_ direction: MoveCommandDirection) {
        let rows = filteredBottles
        guard !rows.isEmpty else { return }
        guard let current = selectedBottleID,
              let idx = rows.firstIndex(where: { $0.id == current }) else {
            selectedBottleID = rows.first?.id
            return
        }
        switch direction {
        case .up:   selectedBottleID = rows[max(0, idx - 1)].id
        case .down: selectedBottleID = rows[min(rows.count - 1, idx + 1)].id
        default: break
        }
    }

    // MARK: - Lifecycle

    @MainActor
    private func onAppearTask() async {
        bottleVM.loadBottles()
        bottlesLoaded = true

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

        try? FileManager.default.removeItem(at: bottle.url)
        bottleVM.bottlesList.paths.removeAll { $0 == bottle.url }
        bottleVM.loadBottles()
        // If we were uninstalling from the entry's detail view, return to the
        // library (the overlay would otherwise lose its now-deleted bottle).
        withAnimation(CrosswireTheme.Motion.navigation) { route = .library }
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
