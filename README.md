# Crosswire Source Code

This repository is the Source Code for Crosswire, a macOS app for
running Windows software, published by Grubwire. It is provided to meet the
GPL-3.0 / LGPL-2.1 source-availability obligations for the binaries distributed
at [grubwire.io](https://grubwire.io).

It is a **source snapshot of a released build (currently 1.1.10)**, not
the active development tree. To run the app or get updates, download it from
grubwire.io.

## What's here

- **The app** — `Crosswire/`, `CrosswireKit/`, `Crosswire.xcodeproj`. Crosswire
  is a maintained fork of [Whisky](https://github.com/Whisky-App/Whisky)
  (archived April 2025), licensed **GPL-3.0**. See `LICENSE`.
- **Our compatibility-engine changes** — `scripts/patch-*.py` and
  `scripts/patches/*.patch`, applied on top of
  [Gcenx/wine](https://github.com/Gcenx/wine) tag `wine-11.10`
  (**LGPL-2.1**). The unmodified upstream engine is that Gcenx tag; it is
  referenced here, not re-hosted.

## Credits

Crosswire builds on [Whisky](https://github.com/Whisky-App/Whisky) and on
[Gcenx's Wine builds](https://github.com/Gcenx/macOS_Wine_builds) for macOS.
Thanks to both projects.
