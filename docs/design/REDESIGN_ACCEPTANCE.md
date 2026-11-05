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

Record final commits, PR reviews, test results, screenshot evidence and the Apple build status here before release. An upload is not evidence of TestFlight availability.

## Arabic typography

Arabic app text uses IBM Plex Sans Arabic (Regular, Medium, SemiBold, Bold), bundled offline under the included SIL Open Font License. English and Turkish retain native system typography. `ArcaTypography` selects using SwiftUI's locale environment and uses `Font.custom(_:size:relativeTo:)` for Dynamic Type, with heavier faces for accessibility Bold Text. Technical monospaced values, emoji, SF Symbols, and platform-controlled navigation/purchase sheets retain their native rendering.

Font source: [IBM Plex official repository](https://github.com/IBM/plex/tree/48e8676114c04f29033b4b53da4ec579f8846297/packages/plex-sans-arabic), pinned to commit `48e8676114c04f29033b4b53da4ec579f8846297`. Original files and license are in `Sources/ArcaUI/Resources/Fonts`. Verify real PostScript names when updating: they differ from the filenames. Font registration/glyph tests and Arabic onboarding/large-text screenshots are part of the release checks.
