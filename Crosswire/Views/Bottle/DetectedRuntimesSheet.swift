//
//  DetectedRuntimesSheet.swift
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

// swiftlint:disable type_body_length
// Shown by the install flow when Crosswire detects an exe needs runtimes
// the bottle doesn't already have. The user confirms what to install (all
// detected items pre-selected), the sheet drives a winetricks run, then
// the install flow continues to launch the exe.
struct DetectedRuntimesSheet: View {
    let exeName: String
    let detected: [DetectedRuntime]
    let bottle: Bottle
    /// Called when the user dismisses with a final decision.
    /// `installed` reports the verbs that were actually run (empty if the
    /// user chose to skip).
    let onFinish: (_ installed: [String]) -> Void

    @State private var selected: Set<String>
    @State private var showDetails: Bool = false
    @State private var phase: Phase = .review
    @State private var currentVerb: String?
    @State private var logURL: URL?

    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case review
        case installing
        case finished(success: Bool)
    }

    init(
        exeName: String, detected: [DetectedRuntime], bottle: Bottle,
        onFinish: @escaping (_ installed: [String]) -> Void
    ) {
        self.exeName = exeName
        self.detected = detected
        self.bottle = bottle
        self.onFinish = onFinish
        // Pre-select everything detected. The user can deselect things they
        // know they don't need (rare).
        self._selected = State(initialValue: Set(detected.map(\.verb)))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
                .frame(maxHeight: .infinity)
            Divider().opacity(0.4)
            footer
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 460, idealHeight: 520)
        .interactiveDismissDisabled(phase == .installing)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: phaseIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(phaseTint)
                    .symbolRenderingMode(.hierarchical)
                Text(phaseTitle)
                    .font(CrosswireTheme.Typography.title)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Spacer()
            }
            Text(phaseSubtitle)
                .font(CrosswireTheme.Typography.entryMeta)
                .foregroundStyle(CrosswireTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var phaseIcon: String {
        switch phase {
        case .review: return "shippingbox"
        case .installing: return "arrow.triangle.2.circlepath"
        case .finished(let success): return success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        }
    }
    private var phaseTint: Color {
        switch phase {
        case .review, .installing: return CrosswireTheme.accent
        case .finished(let success): return success ? CrosswireTheme.success : CrosswireTheme.warning
        }
    }
    private var phaseTitle: String {
        switch phase {
        case .review: return "\(exeName) needs a few runtimes"
        case .installing: return "Installing runtimes…"
        case .finished(true): return "Runtimes installed"
        case .finished(false): return "Install didn't complete cleanly"
        }
    }
    private var phaseSubtitle: String {
        switch phase {
        case .review:
            return "Crosswire scanned the .exe's imports and noticed it expects "
                + "the following to be available. They'll install into this app's environment only."
        case .installing:
            return currentVerb.map { "Currently installing \($0)…" } ?? "Working…"
        case .finished(true):
            return "Launching \(exeName) now."
        case .finished(false):
            return "winetricks reported an error. The exe will still try to launch — "
                + "if it crashes, you can install runtimes manually from the per-app Advanced panel."
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .review: reviewList
        case .installing: installingProgress
        case .finished: finishedSummary
        }
    }

    @ViewBuilder
    private var reviewList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(detected.enumerated()), id: \.element.id) { index, item in
                    runtimeRow(item)
                    if index < detected.count - 1 {
                        Divider().opacity(0.4).padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CrosswireTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(CrosswireTheme.surfaceStroke, lineWidth: 0.5)
            )
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func runtimeRow(_ item: DetectedRuntime) -> some View {
        let isSelected = selected.contains(item.verb)
        Button {
            if isSelected { selected.remove(item.verb) } else { selected.insert(item.verb) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                RuntimeCheckbox(selected: isSelected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CrosswireTheme.textPrimary)
                        Text(item.verb)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(CrosswireTheme.textTertiary)
                    }
                    Text("Triggered by: \(item.triggeringDLLs.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundStyle(CrosswireTheme.textSecondary)
                        .lineLimit(showDetails ? nil : 1)
                        .truncationMode(.tail)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var installingProgress: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(CrosswireTheme.accent.opacity(0.10))
                    .frame(width: 96, height: 96)
                ProgressView()
                    .controlSize(.large)
            }
            VStack(spacing: 4) {
                if let verb = currentVerb {
                    Text(verb)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(CrosswireTheme.textPrimary)
                }
                Text("This can take several minutes per runtime.")
                    .font(.system(size: 11))
                    .foregroundStyle(CrosswireTheme.textSecondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var finishedSummary: some View {
        VStack(spacing: 14) {
            Spacer()
            if case .finished(let success) = phase {
                let tint = success ? CrosswireTheme.success : CrosswireTheme.warning
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.12))
                        .frame(width: 84, height: 84)
                    Image(systemName: success ? "checkmark" : "exclamationmark")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            if let logURL {
                Button("View log") {
                    NSWorkspace.shared.activateFileViewerSelecting([logURL])
                }
                .buttonStyle(.plain)
                .foregroundStyle(CrosswireTheme.accent)
                .controlSize(.small)
            }
            Spacer()
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            switch phase {
            case .review:
                Text(selected.isEmpty
                     ? "Nothing selected — will launch without installing"
                     : "\(selected.count) runtime\(selected.count == 1 ? "" : "s") selected")
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                Spacer()
                Button("Skip & launch") {
                    onFinish([])
                    dismiss()
                }
                Button(selected.isEmpty ? "Launch" : "Install & launch") {
                    startInstall()
                }
                .buttonStyle(.borderedProminent)
                .tint(CrosswireTheme.accent)
                .keyboardShortcut(.defaultAction)
            case .installing:
                Spacer()
                Text("Installing…")
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .font(CrosswireTheme.Typography.entryMeta)
            case .finished:
                Spacer()
                Button("Continue") {
                    onFinish(Array(selected))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(CrosswireTheme.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private func startInstall() {
        let toInstall = selected.isEmpty
            ? []
            : detected.filter { selected.contains($0.verb) }.map(\.verb)
        guard !toInstall.isEmpty else {
            // Nothing selected — same as "skip"
            onFinish([])
            dismiss()
            return
        }
        phase = .installing
        Task {
            let (success, logURL) = await Winetricks.runVerbs(toInstall, bottle: bottle) { current in
                self.currentVerb = current
            }
            self.logURL = logURL
            self.phase = .finished(success: success)
        }
    }
}
// swiftlint:enable type_body_length
