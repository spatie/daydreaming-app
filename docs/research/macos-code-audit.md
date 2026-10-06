# macOS code and interface audit

Reviewed on 6 October 2026 against the relevant macOS architecture, concurrency, AppKit bridge, capabilities, design, accessibility, copy, build and release skills. The approved sidebar layout and automatic preview behavior remain the product constraints.

## Changes

- Preserve purchased images and damaged index bytes when the wallpaper manifest cannot be decoded. Block new paid creation instead of replacing history and pruning unindexed files.
- Treat a corrupt current usage ledger as unavailable storage, not as a fresh daily allowance. Preserve the bytes, block new paid requests, and allow cached application without a charge. Legacy counts migrate only when the current ledger is absent.
- Share desktop application and timestamp persistence. Original restoration and cache clearing now advance the successful-update time only after the desktop accepts the image. A failed apply does not change it.
- Keep the active desktop file when the original needed for cache clearing is missing.
- Share background picture importing. Decode, hash and write away from the main actor, keep the security scope alive in the worker, and discard cancelled replacements. Setup cannot finish with the old picture while a replacement is importing.
- Assign the new picture name before recording its history.
- Remove unused palette sampling from ready artwork and thumbnails.
- Move the frequency picker, window viewport bridge and saved-variation scroll bridge out of ContentView without changing their behavior.
- Use current NSApplication.activate() rather than the deprecated ignoringOtherApps overload.
- Share the wallpaper-action name across buttons, help and accessibility. Distinguish original-picture history from generated-image storage in Settings. Use Preview consistently, label daily limits with their unit, and state that the quality setting concerns desktop wallpapers.
- Add accessible step headers, grouped sidebar controls, localized timeline labels, keyboard gallery focus and Command-Return for the wallpaper decision.
- Regenerate the Xcode project from project.yml. The generated changes contain only the new source files; test Info.plist settings are preserved.
- Add Sparkle with a signed feed, sandbox-compatible helpers and an installation boundary that preserves pending work and blocks new paid requests before relaunch. Automatic installation is disabled.
- Add optional anonymous installation reports. Only the agreed version, build, OS, architecture, time and random installation token leave the app. Preview and test builds never report.
- Add a reproducible release preparation command with immutable source, nested signing, notarization, signed artifacts and a signed appcast. Publication is a separate operation.

## Existing strengths

Swift 6 complete concurrency checking, macOS 26 deployment, security-scoped source access, isolated preview identifiers and fake services, a counted willSend payment boundary, cancellation revisions, injected clocks and sleepers, separate preview/full caches, and shared desktop-fill geometry already exist. Native SwiftUI controls handle Settings, focus and the frequency picker. Reduced motion, reduced transparency, contrast, Low Power Mode and window visibility constrain animation.

## Deliberately deferred

AppModel still owns too much orchestration. Further extraction should keep prompt editing, debounce and payment lifetimes together rather than distribute the state across unrelated views. Cache manifest writes, pruning and export copying still include synchronous disk work on the main actor. Move these behind an ordered storage service after profiling and preserving queue cancellation guarantees. The wake-notification observer also needs a dedicated lifetime owner.

There is no SwiftData domain store to migrate. Adopting SwiftData or Observation merely to use a newer API is not a correctness improvement. Profile update frequency before replacing the current ObservableObject model, especially because startup hydration and scheduling are covered by regression tests.

Codex feasibility is documented separately in [codex-stock-integration.md](codex-stock-integration.md). Local model experiments remain stopped and isolated. No publication, model inference or paid generation is part of this audit.
