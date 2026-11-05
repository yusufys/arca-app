# Arca iOS redesign acceptance

Reference: `arca-ios-redesign-reference.html`, supplied by the product owner. The HTML is a design prototype, not production behavior or starter data. Target: the next TestFlight build after 1.0 (6).

## Design contract

- Keep Home, Insights and Settings reachable. Home remains the chosen tab name; the prototype studio controls do not ship.
- Forest accent #1F5D3F, paper canvas #F7F4EB and card #FFFDF7. Dark canvas #0D1311 and card #161F1C. Native semantic type (IBM Plex Sans Arabic in Arabic only) and adaptive spacing take precedence over the fixed HTML phone dimensions.
- Home: space switcher, search, collection cards with color strip/count/badge, Add/View/Edit action cluster, and AI-first New Collection choices. Retain favorites, recent records and operational notices.
- Collection: Normal, Compact and Box record layouts; search, sort and actual filters. Compact secondary-field choice belongs only in collection settings.
- Collection settings: persisted name/color, icon choices, compact secondary field, popup/full-screen add form choice, existing schema and sensitive-data controls.
- Both Home Add and Collection Add use the same saved presentation preference and actual validated record editor.
- Settings: independent app accent, spaces, and existing language/appearance/account/sync/recovery/privacy/billing controls.
- Use real records and backend-managed suggested collections. Do not seed the prototype examples or medical demos.
- Export must preserve the existing encrypted backup path. The prototype CSV/JSON buttons do not authorize disclosure of sensitive data.

## Required regression coverage

1. EN/AR/TR catalogs complete for new copy, semantic RTL, user-authored values unchanged.
2. Largest Dynamic Type, VoiceOver labels and selected traits, 44-point targets, Reduce Motion, light/dark contrast.
3. Tap-outside keyboard dismissal, Next/Done, cancel/save behavior and unsaved edits.
4. Existing records, attachments and keys survive relaunch and update; preferences survive relaunch and recover safely from stale/corrupt values.
5. All creation paths work with an empty collection list; backend suggestions and strict JSON import remain intact.
6. Schema metadata edits persist without dropping fields, record values, privacy rules or pending sync work.
7. Archive/restore, app lock, sensitive local-only exclusion and password consent remain reachable and unchanged.
8. Billing stays connected to RevenueCat; no fake prices or entitlements.

## Release evidence

Implementation PRs: #1 (collections), #2 (shell), integrated in #3. Follow-up shell and collection reviews are recorded on #3; correctness fixes are in `a61025d`, `a9da3de`, `5ec9af1`, and `27ad3fa`. Arabic typography is in `0faab54`; final large-text navigation and stable test-fixture selection are in `3e7934e`.

- Full Swift suite: 61 tests, zero failures, two existing opt-in HTTP tests skipped. Includes font registration/Arabic glyphs, EN/TR font isolation, collection preferences, exact range boundaries, concurrent metadata/field/privacy changes, strict write failures, encryption and relaunch behavior.
- Eight distinct native iOS acceptance scenarios passed across the initial run and focused recheck: Arabic onboarding/keyboard, largest-text language switching, appearance restoration, Arabic dark/large-text screens, Home Add/View/Edit and AI input, six key screens in EN/AR/TR, record layout/data relaunch, and collection rename/full-screen add restoration.
- Initial UI failures were test-harness defects: the AI input was queried as a TextView instead of its actual native control, and the fixture reopened the first display-sorted collection after a rename changed that order. The corrected tests verify actual input and a stable collection UUID. Both passed on recheck.
- Screenshot inspection identified oversized bottom navigation at maximum text size. It now uses compact icons with spoken labels and iOS large-content viewing; rechecked screenshots and accessibility-label audits passed.
- Local evidence: `/tmp/arca-redesign-acceptance.xcresult`, `/tmp/arca-redesign-recheck.xcresult`, and `/tmp/arca-redesign-coordination/swift-final-tests.log`. Generated screenshot files are not source-controlled.
- The UI pass does not replace physical-device VoiceOver/Switch Control, real App Store product purchase tests or live two-device sync acceptance. Backend, sync protocol and encryption algorithms are unchanged.

TestFlight delivery status is recorded in `IOS_RELEASE.md`; upload alone does not establish tester availability.

## Arabic typography

Arabic app text uses IBM Plex Sans Arabic (Regular, Medium, SemiBold, Bold), bundled offline under the included SIL Open Font License. English and Turkish retain native system typography. `ArcaTypography` selects using SwiftUI's locale environment and uses `Font.custom(_:size:relativeTo:)` for Dynamic Type, with heavier faces for accessibility Bold Text. Technical monospaced values, emoji, SF Symbols, and platform-controlled navigation/purchase sheets retain their native rendering.

Font source: [IBM Plex official repository](https://github.com/IBM/plex/tree/48e8676114c04f29033b4b53da4ec579f8846297/packages/plex-sans-arabic), pinned to commit `48e8676114c04f29033b4b53da4ec579f8846297`. Original files and license are in `Sources/ArcaUI/Resources/Fonts`. Verify real PostScript names when updating: they differ from the filenames. Font registration/glyph tests and Arabic onboarding/large-text screenshots are part of the release checks.
