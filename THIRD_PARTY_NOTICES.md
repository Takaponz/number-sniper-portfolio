# Third-Party Notices

Checked on 2026-08-31.

## Google Mobile Ads Swift Package

- Resolved version: `13.8.0`
- Package: <https://github.com/googleads/swift-package-manager-google-mobile-ads>
- Package wrapper license: Apache License 2.0
- SDK documentation: <https://developers.google.com/admob/ios/quick-start>

The package downloads the Google Mobile Ads SDK binary during dependency
resolution; the binary is not committed to this repository. The public app uses
`StubAdService` by default and does not initialize the SDK. Enabling the retained
integration example requires an appropriate consent flow and remains subject to
Google's applicable SDK and service terms.

## Google User Messaging Platform Swift Package

- Resolved version: `3.1.0`
- Package: <https://github.com/googleads/swift-package-manager-google-user-messaging-platform>
- Package wrapper license: Apache License 2.0

This transitive package and its downloaded binary are not vendored in this
repository.

## Google demo ad identifiers

The public portfolio build uses Google's demo app and ad-unit identifiers only.

- Setup and demo app ID: <https://developers.google.com/admob/ios/quick-start>
- Interstitial and rewarded test units: <https://developers.google.com/admob/ios/test-ads>

## Apple platform frameworks

SwiftUI, Foundation, AVFoundation, GameKit, UIKit, and App Tracking
Transparency are provided by Apple platforms and are not redistributed here.

Project-owned images and audio are documented in
[`docs/ASSET_PROVENANCE.md`](docs/ASSET_PROVENANCE.md).
