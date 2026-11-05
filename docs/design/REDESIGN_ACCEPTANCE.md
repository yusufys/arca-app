# Arca iOS redesign acceptance

Reference: `arca-ios-redesign-reference.html`, supplied by the product owner. The HTML is a design prototype, not production behavior or starter data. Target: the next TestFlight build after 1.0 (6).

## Design contract

- Keep Home, Insights and Settings reachable. Home remains the chosen tab name; the prototype studio controls do not ship.
- Forest accent #1F5D3F, paper canvas #F7F4EB and card #FFFDF7. Dark canvas #0D1311 and card #161F1C. Native semantic type and adaptive spacing take precedence over the fixed HTML phone dimensions.
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
