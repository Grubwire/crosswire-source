//
//  AppearancePicker.swift
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

/// Three swatches — Dark, Light, System — each a miniature of the window it
/// produces. One component shared by the first-run setup step and Settings ›
/// General, so the choice looks identical wherever it is made.
///
/// Writing `AppearancePreference.defaultsKey` is the whole mechanism: the root
/// `.preferredColorScheme` in `CrosswireApp` observes the same key, and every
/// `Color(light:dark:)` token in both theme files follows from there.
struct AppearancePicker: View {
    @AppStorage(AppearancePreference.defaultsKey) private var raw =
        AppearancePreference.fallback.rawValue

    /// Swatch size. The setup step wants a larger target than Settings does.
    var swatchWidth: CGFloat = 96
    var swatchHeight: CGFloat = 62

    private var selection: AppearancePreference {
        AppearancePreference(rawValue: raw) ?? .fallback
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppearancePreference.allCases) { option in
                swatch(for: option)
            }
        }
        .animation(CrosswireTheme.Motion.hover, value: raw)
    }

    @ViewBuilder
    private func swatch(for option: AppearancePreference) -> some View {
        let isSelected = selection == option
        Button {
            raw = option.rawValue
        } label: {
            VStack(spacing: 7) {
                AppearanceSwatchPreview(option: option)
                    .frame(width: swatchWidth, height: swatchHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isSelected ? CrosswireTheme.accent
                                                     : CrosswireTheme.surfaceStroke,
                                          lineWidth: isSelected ? 2.5 : 1)
                    )
                HStack(spacing: 4) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? CrosswireTheme.accent
                                                    : CrosswireTheme.textTertiary)
                    Text(option.title)
                        .font(CrosswireTheme.Typography.buttonLabel)
                        .foregroundStyle(CrosswireTheme.textPrimary)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Use the \(option.title.lowercased()) appearance")
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The miniature window drawn inside a swatch: title bar, sidebar, content.
/// Hardcoded greys rather than theme tokens on purpose — each swatch must show
/// its OWN appearance regardless of which one is currently active, so these
/// cannot follow the environment the way a token would.
private struct AppearanceSwatchPreview: View {
    let option: AppearancePreference

    var body: some View {
        switch option {
        case .dark:  Self.miniature(dark: true)
        case .light: Self.miniature(dark: false)
        case .system:
            // Split diagonally: light leading, dark trailing.
            ZStack {
                Self.miniature(dark: false)
                Self.miniature(dark: true)
                    .clipShape(TrailingWedge())
            }
        }
    }

    @ViewBuilder
    static func miniature(dark: Bool) -> some View {
        let page = dark ? Color(hex: 0x0A0D13) : Color(hex: 0xE7EBF1)
        let bar = dark ? Color(hex: 0x11151E) : Color(hex: 0xF8FAFC)
        let tile = dark ? Color(hex: 0x2A3242) : Color(hex: 0xD3DAE4)
        VStack(spacing: 0) {
            Rectangle()
                .fill(bar)
                .frame(height: 9)
                .overlay(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(tile).frame(width: 2.5, height: 2.5)
                        }
                    }
                    .padding(.leading, 4)
                }
            HStack(spacing: 0) {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5).fill(tile).frame(height: 9)
                    }
                    Spacer(minLength: 0)
                }
                .padding(4)
                .frame(width: 30)
                .background(bar)
                ZStack {
                    page
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: 0x418DF7).opacity(dark ? 0.85 : 0.7))
                        .padding(8)
                }
            }
        }
        .background(page)
    }
}

/// The trailing half of a rectangle, cut on a diagonal — the "System" swatch's
/// dark side.
private struct TrailingWedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
