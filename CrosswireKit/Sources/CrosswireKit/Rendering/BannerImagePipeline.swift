//
//  BannerImagePipeline.swift
//  CrosswireKit
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

import Foundation
import AppKit
import CoreImage
import CoreGraphics

/// Pure, dependency-free image pipeline that turns an extracted app icon into a
/// wide banner suitable for a hero / shelf presentation.
///
/// It references no Crosswire types and touches no disk: this is the piece that
/// `BannerRenderer` wraps with icon extraction and caching, and the same code is
/// exercised directly by the offline banner-preview harness so the previews a
/// reviewer sees come from the shipping pipeline, not a stand-in.
///
/// Two background modes, chosen by source resolution:
/// - Ambient (icon's longest side >= 64px): the icon is scaled to cover,
///   heavily blurred, and darkened into an ambient wash. This is the primary
///   path and what modern launcher exes (256px PNG, 128px BMP) hit.
/// - Gradient-map (longest side < 64px): a diagonal gradient in the icon's own
///   palette stands in for a background too small to blur meaningfully. Old
///   exes with tiny icons land here instead of a blown-up smear.
///
/// A bottom scrim is always drawn to guarantee contrast for the title text and
/// the single dominant Play control the UI will place along the lower edge.
public enum BannerImagePipeline {

    /// Below this longest-side pixel count the source is too small to blur into
    /// a convincing ambient background, so the gradient-map fallback is used.
    static let ambientThreshold = 64

    /// A straight (un-premultiplied) RGB colour in 0...1.
    struct RGB {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    /// Hue / saturation / brightness in 0...1.
    struct HSB {
        let hue: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat
    }

    /// A quantized colour bucket accumulating a true-colour sum for averaging.
    private struct Bucket {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0
    }

    /// A bucket's averaged colour paired with how many pixels landed in it.
    private struct Candidate {
        let color: RGB
        let count: Int
    }

    /// A small palette sampled from an icon's opaque pixels.
    public struct Palette {
        /// Deep, low-brightness tone for background fills and scrims.
        public let base: NSColor
        /// Vibrant tone for gradients and glow.
        public let accent: NSColor
        /// True when too few opaque pixels were found to trust the sample, in
        /// which case a neutral slate default is used.
        public let isLowDetail: Bool
    }

    /// Render a banner for `icon` at `size` (pixels).
    /// - Returns: nil only if the icon cannot be rasterised or a context cannot
    ///   be created; every real icon produces an image.
    public static func render(icon: NSImage, size: CGSize) -> NSImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        guard let iconCG = rasterize(icon) else { return nil }

        let longestSide = max(iconCG.width, iconCG.height)
        let palette = palette(from: iconCG)

        let background: CGImage?
        if longestSide >= ambientThreshold {
            background = ambientBackground(iconCG: iconCG, size: size, palette: palette)
        } else {
            background = gradientBackground(size: size, palette: palette)
        }
        guard let background else { return nil }

        guard let ctx = rgbaContext(width: Int(size.width), height: Int(size.height)) else { return nil }
        ctx.interpolationQuality = .high
        let rect = CGRect(origin: .zero, size: size)

        ctx.draw(background, in: rect)
        drawBottomScrim(in: ctx, size: size)
        drawForeground(iconCG: iconCG, in: ctx, size: size)

        guard let outCG = ctx.makeImage() else { return nil }
        return NSImage(cgImage: outCG, size: size)
    }

    /// PNG-encode a rendered banner. Used by `BannerRenderer` to carry the
    /// result across an actor boundary as `Data` (which is `Sendable`, unlike
    /// `NSImage`) and to persist it.
    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Palette

    static func palette(from image: CGImage) -> Palette {
        let dim = 32
        guard let ctx = rgbaContext(width: dim, height: dim), let raw = ctx.data else {
            return defaultPalette()
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: dim, height: dim))
        let buf = raw.bindMemory(to: UInt8.self, capacity: dim * dim * 4)

        // Quantize opaque pixels into 4-bit-per-channel buckets, accumulating a
        // true-color average per bucket (un-premultiplying, since the context is
        // premultipliedLast).
        var buckets: [UInt16: Bucket] = [:]
        var opaque = 0
        for byteIndex in stride(from: 0, to: dim * dim * 4, by: 4) {
            let alpha = Int(buf[byteIndex + 3])
            if alpha < 128 { continue }
            let red = min(255, Int(buf[byteIndex]) * 255 / alpha)
            let green = min(255, Int(buf[byteIndex + 1]) * 255 / alpha)
            let blue = min(255, Int(buf[byteIndex + 2]) * 255 / alpha)
            opaque += 1
            let key = UInt16((red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4))
            var entry = buckets[key] ?? Bucket()
            entry.count += 1
            entry.red += red; entry.green += green; entry.blue += blue
            buckets[key] = entry
        }

        // Too few opaque pixels to trust: neutral slate.
        if opaque < (dim * dim) / 40 || buckets.isEmpty {
            return defaultPalette()
        }

        let candidates = buckets.values.map { entry -> Candidate in
            let denom = CGFloat(entry.count)
            return Candidate(color: RGB(red: CGFloat(entry.red) / denom / 255,
                                        green: CGFloat(entry.green) / denom / 255,
                                        blue: CGFloat(entry.blue) / denom / 255),
                             count: entry.count)
        }

        // Dominant: most common bucket. Vibrant: maximizes saturation weighted
        // by frequency so a small pop of colour can still win as the accent.
        guard let dominant = candidates.max(by: { $0.count < $1.count }),
              let vibrant = candidates.max(by: { lhs, rhs in
                  saturation(lhs.color) * sqrt(CGFloat(lhs.count)) <
                  saturation(rhs.color) * sqrt(CGFloat(rhs.count))
              }) else {
            return defaultPalette()
        }

        let dom = hsb(dominant.color)
        let vib = hsb(vibrant.color)

        let base = NSColor(hue: dom.hue,
                           saturation: min(dom.saturation * 0.7 + 0.12, 0.85),
                           brightness: 0.16,
                           alpha: 1)
        let accent = NSColor(hue: vib.hue,
                             saturation: max(vib.saturation, 0.55),
                             brightness: max(vib.brightness, 0.55),
                             alpha: 1)
        return Palette(base: base, accent: accent, isLowDetail: false)
    }

    static func defaultPalette() -> Palette {
        Palette(base: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.14, alpha: 1),
                accent: NSColor(srgbRed: 0.22, green: 0.30, blue: 0.46, alpha: 1),
                isLowDetail: true)
    }

    // MARK: - Backgrounds

    static func ambientBackground(iconCG: CGImage, size: CGSize, palette: Palette) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard let fillCtx = rgbaContext(width: width, height: height) else {
            return solidFill(size: size, color: palette.base)
        }
        fillCtx.interpolationQuality = .high
        fillCtx.setFillColor(palette.base.cgColor)
        fillCtx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Scale the icon to more than cover, so the blurred wash is dense and
        // the edges do not fall inside the frame.
        let cover = aspectFillRect(source: CGSize(width: iconCG.width, height: iconCG.height),
                                   into: CGRect(origin: .zero, size: size),
                                   scaleUp: 1.35)
        fillCtx.draw(iconCG, in: cover)

        guard let filled = fillCtx.makeImage() else {
            return solidFill(size: size, color: palette.base)
        }
        let radius = max(size.width, size.height) * 0.09
        let blurred = gaussianBlur(filled, radius: radius) ?? filled

        guard let outCtx = rgbaContext(width: width, height: height) else { return blurred }
        outCtx.interpolationQuality = .high
        outCtx.draw(blurred, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Darken so the crisp foreground and future text read against it.
        outCtx.setFillColor(NSColor(white: 0, alpha: 0.42).cgColor)
        outCtx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return outCtx.makeImage() ?? blurred
    }

    static func gradientBackground(size: CGSize, palette: Palette) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard let ctx = rgbaContext(width: width, height: height) else {
            return solidFill(size: size, color: palette.base)
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let topColor = palette.accent.blended(withFraction: 0.35, of: .black)?.cgColor ?? palette.accent.cgColor
        let colors = [topColor, palette.base.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: height),
                                   end: CGPoint(x: width, y: 0),
                                   options: [])
        } else {
            ctx.setFillColor(palette.base.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        // Corner vignette for depth.
        if let vignette = CGGradient(colorsSpace: space,
                                     colors: [NSColor(white: 0, alpha: 0).cgColor,
                                              NSColor(white: 0, alpha: 0.45).cgColor] as CFArray,
                                     locations: [0, 1]) {
            let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            ctx.drawRadialGradient(vignette,
                                   startCenter: center, startRadius: CGFloat(min(width, height)) * 0.2,
                                   endCenter: center, endRadius: CGFloat(max(width, height)) * 0.75,
                                   options: [])
        }
        return ctx.makeImage() ?? solidFill(size: size, color: palette.base)
    }

    // MARK: - Overlays

    static func drawBottomScrim(in ctx: CGContext, size: CGSize) {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: space,
                                        colors: [NSColor(white: 0, alpha: 0).cgColor,
                                                 NSColor(white: 0, alpha: 0.78).cgColor] as CFArray,
                                        locations: [0, 1]) else { return }
        // Origin is bottom-left: the scrim runs from 60% height (transparent)
        // down to the bottom edge (dark), where title + Play will sit.
        let top = size.height * 0.6
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: size.width, height: top))
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: top),
                               end: CGPoint(x: 0, y: 0),
                               options: [])
        ctx.restoreGState()
    }

    static func drawForeground(iconCG: CGImage, in ctx: CGContext, size: CGSize) {
        let iconWidth = CGFloat(iconCG.width), iconHeight = CGFloat(iconCG.height)
        let maxWidth = size.width * 0.42
        let maxHeight = size.height * 0.50
        let longestSide = max(iconWidth, iconHeight)
        // Fit inside the focal box. Already-large art (>=256px, e.g. a 256px PNG
        // wordmark) is drawn at native size and never upscaled into mush. Smaller
        // sources scale up to fill the box: at native size a 128px ring/emblem
        // reads as a tiny shape lost in the panel, and an emblem needs to be
        // drawn larger than a full wordmark to carry equal visual weight. The 3x
        // ceiling keeps genuinely tiny icons (sub-64px) from turning to mush.
        let fit = min(maxWidth / iconWidth, maxHeight / iconHeight)
        let scale = longestSide >= 256 ? min(fit, 1.0) : min(fit, 3.0)
        let drawWidth = iconWidth * scale
        let drawHeight = iconHeight * scale
        let originX = (size.width - drawWidth) / 2
        // Nudge up off the exact centre so the scrim/title band has room.
        let originY = (size.height - drawHeight) / 2 + size.height * 0.06

        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.setShadow(offset: CGSize(width: 0, height: -6),
                      blur: 24,
                      color: NSColor(white: 0, alpha: 0.55).cgColor)
        ctx.draw(iconCG, in: CGRect(x: originX, y: originY, width: drawWidth, height: drawHeight))
        ctx.restoreGState()
    }

    // MARK: - Primitives

    static func rasterize(_ image: NSImage) -> CGImage? {
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let cgImage = rep.cgImage {
            return cgImage
        }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func rgbaContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(data: nil,
                         width: width,
                         height: height,
                         bitsPerComponent: 8,
                         bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func solidFill(size: CGSize, color: NSColor) -> CGImage? {
        guard let ctx = rgbaContext(width: Int(size.width), height: Int(size.height)) else { return nil }
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    static func gaussianBlur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        return CIContext(options: nil).createCGImage(output, from: input.extent)
    }

    static func aspectFillRect(source: CGSize, into frame: CGRect, scaleUp: CGFloat) -> CGRect {
        let scale = max(frame.width / source.width, frame.height / source.height) * scaleUp
        let width = source.width * scale
        let height = source.height * scale
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
    }

    // MARK: - Colour helpers

    static func saturation(_ color: RGB) -> CGFloat {
        let maxC = max(color.red, color.green, color.blue)
        let minC = min(color.red, color.green, color.blue)
        return maxC <= 0 ? 0 : (maxC - minC) / maxC
    }

    static func hsb(_ color: RGB) -> HSB {
        let nsColor = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        nsColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        return HSB(hue: hue, saturation: sat, brightness: bri)
    }
}
