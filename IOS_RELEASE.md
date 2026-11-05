# Arca iOS release handoff

App Store Connect record: **Arca - Personal Records**, Apple ID **6830898859**, bundle **app.arca.personalrecords**. Internal beta first. Use fictional data and the supplied build number in all feedback.

## Native redesign and Arabic typography — build 7

- Home collection cards expose Add/View/Edit. Collection records support Normal, Compact and Box layouts, search/sort and text/number/date filters. Collection settings save name, color, icon, compact secondary field and popup/full-screen entry preferences. App accent and light/dark/system appearance remain independent of collection colors.
- Arabic app text uses bundled IBM Plex Sans Arabic with semantic Dynamic Type and Bold Text. English and Turkish retain native system fonts. At accessibility text sizes the bottom bar uses compact icons with spoken labels and the iOS large-content viewer.
- Follow-up review fixed metadata write failures and concurrent schema edits, appearance restoration, filter boundaries, icon handling and large-text layout. Existing encryption, sensitive consent, AI creation, billing and sync paths remain connected.
- Validation: 61 Swift tests, zero failures, two existing opt-in HTTP skips; eight distinct iOS UI scenarios passed across acceptance and focused reruns. These cover Arabic onboarding/keyboard, language switching, EN/AR/TR key screens, dark/large text, Home actions/AI input, and records/layout/name/appearance after process termination. Screenshot inspection complemented selected accessibility-label audits. See [acceptance evidence](docs/design/REDESIGN_ACCEPTANCE.md).
- [PR #3](https://github.com/yusufys/arca-app/pull/3) integrates implementation PRs #1 and #2 and the two follow-up reviews. Merged to main as `24e600e`; final app source is `3e7934e` (later commits record evidence).
- Signed Release 1.0 (7) uploaded successfully on November 6, 2026. Archive verification confirmed the production bundle, live Forge endpoint, Apple RevenueCat key, all four Arabic font files/license and EN/AR/TR resources. Apple processed build ID `1d06ecfe-250c-42b4-b4c3-460567e5dc01` as VALID. Internal and external states are both IN_BETA_TESTING, with Arca Internal and Testers assigned and automatic tester notification enabled. The public link is https://testflight.apple.com/join/mUFpH7YX. Build 6 remains available.
- Designer update: [50 native screen captures and an offline gallery](artifacts/ux-handoff-build7/index.html), plus [the ZIP](artifacts/Arca-UX-Handoff-Build7.zip). This covers updated flows and Arabic onboarding; the earlier complete flow pack remains separate. All pictured records are fictional fixtures.
- Physical-device VoiceOver/Switch Control, actual StoreKit purchases/RevenueCat paywall variants and live two-device sync were not newly certified by this UI pass. Continue those release checks using the new TestFlight build.

## Localization and accessibility — build 6

- Native Apple String Catalogs now supply English, Arabic and Turkish UI copy, plural forms, core validation and the Face ID permission explanation. Arabic uses RTL layout; saved personal records are never translated by language changes.
- The backend catalog supports validated translated schemas and subtitles, cached offline on iOS. AI prompts request labels and options in the selected language while keeping the shared JSON contract unchanged. Forge deployment 82202588 completed; the live catalog returned all three starters with Arabic/Turkish schemas, and the Arabic prompt request passed.
- Account inputs support email/password semantics, Next/Done and tap-outside keyboard dismissal. Dynamic Type reflows grids and sheet headers; icon choices have spoken labels and selection traits. Reduce Motion is respected.
- Validation: 44 Swift tests, 48 backend tests, iOS simulator host build, three-language native screen/keyboard/AI/account walkthroughs, and automated accessibility-label audits on selected screens at normal and largest text sizes.
- Designer handoff: **147 distinct PNG screenshots** (45 English, 45 Arabic, 45 Turkish, 12 enlarged-text views), an offline HTML gallery and flow map. Regenerate with `ci/UXFlowCapture`; implementation guidance is in [I18N_ACCESSIBILITY.html](I18N_ACCESSIBILITY.html). The generated pack is excluded from Git.
- Build 1.0 (6): signed Release archive verified and uploaded successfully on November 5, 2026. Apple processing completed as VALID (build ID `c84aaad1-4331-4dce-9730-f800e25831ff`). The encryption declaration is complete and test instructions are saved. Build 6 is IN_BETA_TESTING and belongs to Arca Internal, so existing internal testers can install it. Submitted through App Store Connect. Apple now reports IN_BETA_TESTING for both internal and external testing; build 6 belongs to both Arca Internal and Testers. Automatic tester notification is enabled. Public beta link: https://testflight.apple.com/join/mUFpH7YX. Build 5 is EXPIRED for both audiences. The archive contains EN/AR/TR resources and uses the live Forge backend and Apple RevenueCat key.
- Remaining: install build 6 from TestFlight; verify on-device VoiceOver and Switch Control, complete contrast and translation review, and test actual App Store products and RevenueCat-authored paywalls in each language. Build 5 does not contain this pass.

## App Store Connect listing draft

- Primary category: Productivity. Suggested subtitle: **Warranties, inventory & more**.
- Description: Keep warranties, vehicle service records and home inventory together. Create a Space, choose a template or design your own collection, and find a record by searching its fields. Use a Local-Only Space to keep records on one device, or connect an Arca account to sync encrypted changes across your devices. Export an encrypted archive for recovery. Arca Pro provides higher device and storage limits.
- Keywords: inventory,warranty,maintenance,organizer,receipts,collections
- Support: https://arca-api.on-forge.com/support.html · Privacy: https://arca-api.on-forge.com/privacy.html · Support and beta feedback: hi@kawkbi.com
- Release note: First iOS release. Save, search and organize records on your iPhone, protect sensitive data, and recover synced collections on a second device.
- Review access: Provide a disposable working review account and its recovery phrase in App Store Connect’s private review notes when cloud testing is required. Confirm the backend is reachable throughout review. Keep sign-in details out of Git.
- Before submission: use the [English iPhone and iPad screenshots](artifacts/app-store-screenshots/en-US/); finish the age-rating and content-rights questionnaires, regional business details, privacy disclosures, and the encryption assessment for the final binary. Compare connected account identifiers, email, purchase history, cloud operations and RevenueCat diagnostic data with the actual configuration. Document the intended storefronts, pricing and renewal terms. Apple and RevenueCat credentials belong in their own consoles.

## Suggested collections and AI design (build 5)

Build 5 introduced the features below. Build 6 includes them together with the localization and accessibility pass. Build 4 was withdrawn from beta review when build 5 was submitted; build 5 has now been expired at the owner’s request and replaced by build 6 for internal and external testing.

Simulator acceptance covered the published gallery, editing a copied template, prompt preparation against Forge, opening the three assistant sites, native cross-app paste of a fenced reply, invalid schema rejection, and saving then reopening a four-field collection offline. A separate clipboard-writer app supplied the reply for the native paste test; no test prompt was submitted to a provider.

Manage suggestions in the [Forge catalog editor](https://arca-api.on-forge.com/admin/collection-templates) with an Arca administrator account. Publish a collection to make it available at the next launch or gallery refresh. Unpublishing removes it from refreshed suggestions. Existing copies belong to the user.

In **Home → New Collection → Create with AI**, describe the fields you need, prepare the prompt, then copy and paste it into ChatGPT, Claude or Gemini. Paste the response back in Arca, review the fields and create the collection. **I already have an AI reply** supports offline import. Only the description is sent to Arca for prompt preparation. Test a fenced JSON reply, an unknown field type, a required attachment in a synced Space, and an offline launch with and without a previously loaded catalog.

## What to test in TestFlight

1. Install fresh. Create a Local-Only Space and a fictional warranty. Search, favorite, edit, force-quit and reopen it. Then update over a previous installation and verify the same record and attachment bytes.
2. Enable app lock. Cancel authentication and confirm records and the app-switcher preview are hidden. Authenticate, background the app and reopen it. Check the lock with VoiceOver and the largest text size.
3. Save an encrypted archive through Files. Restore into a clean installation. Check the record, schema and attachment bytes. A wrong password, blank password for an encrypted export, or corrupt file must never expose plaintext or change existing data.
4. Use a disposable account on two iPhones. Sync and edit in both directions. Mark a serial number sensitive and keep it local. Verify an ordinary sibling field syncs without leaking the private value. Repeat for the whole collection, interrupted network, wrong master password, conflicts and pending removal of previously synced copies. Deliberately revoke one test device.
5. Use a sandbox Apple purchase account. Verify monthly, yearly and lifetime, cancel a purchase, restore on a new installation, handle expiration/refund, and open Customer Center. Check the correct Arca account gets and loses server quota as expected. Configure sandbox billing on a separate staging backend; production ignores sandbox webhooks.
6. Delete the disposable cloud account through Settings. Check old cloud access fails and the restored local data remains local. Test large text, VoiceOver, Turkish and right-to-left Arabic on each major screen.

Use the exact build that passed the final checks for external beta. The internal-only export option prevents that particular upload from going to external testers. For external beta, prepare a new build, select App Store Connect distribution, provide beta review information and tester instructions, and review Apple’s processing results.

## What still needs the owner

- In RevenueCat, map the three **Apple** products to the entitlement and offering, confirm the Apple In-App Purchase key and complete webhook setup. See [the integration guide](REVENUECAT.md).
- On November 5, 2026, Apple processed internal-only build **1.0 (3)** as **VALID**. It was uploaded using manual signing with the Arca App Store provisioning profile and the local Apple Distribution identity. App Store Connect cleared build 3 for internal testing. Verified that the **Arca Internal** group contains build 3 and Yusuf’s tester account. Installation from TestFlight and the device tests above are pending.
- App Store Connect contains drafts for `monthly`, `yearly` and the non-consumable `lifetime`. Apple declined the API updates for subscription durations. Set and verify the one-month and one-year renewal periods, pricing, availability and review metadata before Apple sandbox billing tests.
- Select an off-server backup destination in Forge and enter its credentials there. After the first scheduled run, restore into an isolated database, record recovery time and verify schema and data before marking recurring recovery complete.
- Confirm commercial terms, privacy answers, legal owner and regional declarations before public submission.

For an internal-only upload with an App Store Connect key on the build Mac, use `ci/upload-internal-testflight.sh "/path/to/Arca.xcarchive" "/path/to/AuthKey_KEYID.p8" "ISSUER_ID"`. With a working Xcode account, omit the last two arguments. Confirm processing in the app’s TestFlight tab before assigning testers.
