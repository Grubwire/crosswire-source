# How to contribute

Thanks for your interest! Fork Crosswire, make a new branch for your changes, and get coding.

# Build environment

Crosswire is built with Xcode 26 on macOS and targets macOS 14.6 or later. All dependencies come through the Swift Package Manager, so opening `Crosswire.xcodeproj` and building is all it takes.

One caveat: the app icon and appearance rely on the macOS 26 SDK. Older Xcode versions will still build and run the app, but they silently drop the icon and fall back to the legacy look. Don't be alarmed if a local build looks plain, and don't try to "fix" it in a PR.

# Code style

Every Crosswire commit is automatically linted using SwiftLint. You can run these checks locally simply by building in Xcode; violations will appear as errors or warnings. For your pull request to be merged, you must meet all the requirements outlined by SwiftLint and have no violations.

Generally, it is not advised to disable a SwiftLint rule, but there are certain situations where it is necessary. Please use your discretion when disabling rules temporarily.

SwiftLint does not fully check indentation, but we ask that you indent with 4-width spaces. This can be automatically configured in Xcode's settings.

All added strings must be properly localised and added to the EN strings file. Do not add keys for other languages or translate within your PR.

# Making your PR

Please provide a detailed description of your changes in your PR. If your commits contain UI changes, we ask that you provide screenshots.

# Review

Once your pull request passes the SwiftLint and test checks, it will be ready for review. You may receive feedback on code that should be changed. Once you have received an approval, your code will be merged!
