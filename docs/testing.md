# Testing

## Core package

The pure Swift package covers scoring, question generation, cursor timing,
level progression, practice mode, persistence, lifecycle decisions, and revive
behavior.

```bash
cd NumberSniperCore
swift test
```

## iOS Simulator build

The portfolio project does not contain an Apple Development Team. Build it for
the generic Simulator destination without code signing:

```bash
xcodebuild build \
  -project NumberSniper.xcodeproj \
  -scheme NumberSniper \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ./DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

## Manual smoke check

After installing the Simulator product:

1. Launch the title screen.
2. Start a normal game and submit at least one answer.
3. Open Practice, submit an answer, and return to the title.
4. Open Settings and toggle sound, BGM, and haptics.
5. Confirm that the app remains stable without BGM resources.

The public build uses `StubAdService`; these checks do not send ad requests to
Google. `AdMobService` is retained only as an opt-in integration example.

There is no automated UI-test target in this snapshot. UI navigation and visual
layout are verified manually; behavior below the view-model boundary is covered
by the core package tests.
