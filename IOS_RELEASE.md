# Arca iOS release handoff

App Store Connect record: **Arca - Personal Records**, Apple ID **6830898859**, bundle **app.arca.personalrecords**. Internal beta first. Use fictional data and the supplied build number in all feedback.

## Record images — build 8

- Collections support multiple Image fields, with one image per field. The only image field automatically supplies record thumbnails. With several fields, Collection Settings lets the user choose a source; this presentation preference is device-local and survives relaunch. Normal, Compact, Box, Home and search rows use the selected image. Record details show each image separately.
- Photos and Files imports are decoded with Image I/O, normalized to JPEG at a maximum 2048 pixels, and stripped of source metadata. Input is capped at 15 MB and stored images at 5 MB. Replacing or removing one field does not clear another. Duplicates receive independent image references.
- Image bytes and metadata use the existing authenticated client encryption. The Laravel transport stores bounded ciphertext blobs transactionally, checks account/device access and quotas, and fences uploads with privacy generations. Scoped privacy deletion removes image ciphertext before sanitized records are republished. General file attachments remain local-only.
- Forge deployment `82252041` completed on November 6, 2026 from main commit `970f730`, including the `add_encrypted_blobs_to_attachments` migration (batch 6). The deployment script now follows main explicitly; its original is saved on the server. An initial attempt stopped before checkout because the old clone tracked only its release branch; the corrected deployment succeeded. The migration adds nullable columns and an index; do not roll it back after images have been uploaded because dropping the ciphertext column destroys those cloud copies. Original file bytes are not sent to third-party image services.
- The version 2 collection contract adds `image`; old catalog clients retain version 1 and do not receive incompatible templates. Update both sync devices to the new app before adding Image fields: build 7 cannot decode the new field type in synced collection schemas.
- Validation: 66 Swift tests passed with the isolated Laravel HTTP server, including two clients exchanging images, reopening storage, and verified privacy removal. All 53 backend tests passed; the targeted security tests were rerun after tightening tenant and size checks. Native iOS simulator acceptance passed multiple-image rendering, choosing a thumbnail source, persistence after process termination, removing one image while retaining the other, Normal/Box thumbnails and Arabic controls. See [the offline screenshot gallery](artifacts/record-images/index.html). After deployment, `testImagesRoundTripOverLaravelHTTPAndPrivacyPurge` passed against the live Forge endpoint: two enrolled clients, independent image bytes, reopened storage, confirmed private-image removal, retained allowed sibling and disposable account cleanup. This is HTTP-client evidence, not a two-iPhone acceptance result.
- [PR #4](https://github.com/yusufys/arca-app/pull/4) merged to main as `970f730`. Signed Release 1.0 (8) archived and uploaded successfully on November 6, 2026. Archive checks confirmed the production bundle, build number, encryption declaration, four Arabic fonts and EN/AR/TR bundles. Apple processed build ID `3b6346bf-bd0d-4f25-9bf3-b2d600bcd7bb` as VALID. Internal and external states are both `IN_BETA_TESTING`, with Arca Internal and Testers assigned. Automatic tester notification is enabled. Install through https://testflight.apple.com/join/mUFpH7YX (the existing public group limit is 10 testers).

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

## App Store Connect listing — current draft

Verified November 6, 2026. English description, keywords, support URL, subtitle **Your records, your way**, primary category **Productivity**, and privacy-policy URL are saved in App Store Connect. The owner saved the private review contact; review notes are populated. Release mode is **manual**, and public version 1.0 remains `PREPARE_FOR_SUBMISSION`.

- Prepared source copy for English, Arabic and Turkish is in [ci/app-store-metadata.json](ci/app-store-metadata.json). Arabic/Turkish store localizations still need uploading and native-language sign-off.
- [Fresh build 8 screenshot gallery](artifacts/app-store-build8/index.html): 54 unedited native screenshots, six screens per language and device family. iPhone images are 1206 × 2622 and 1320 × 2868; iPad images are 2064 × 2752. Capture tests passed for all three languages on both devices. Six English iPhone and six English iPad screenshots are uploaded to App Store Connect; Arabic/Turkish sets remain to upload. Do not use the older pre-redesign pack.
- Support: https://arca-api.on-forge.com/support.html · Privacy: https://arca-api.on-forge.com/privacy.html · hi@kawkbi.com
- Provide a disposable working review account and its recovery phrase privately in App Store Connect when cloud testing is required. Keep credentials out of Git.
- Owner decisions still needed: copyright/legal owner, privacy disclosures, age rating/content rights, storefronts, regional business declarations, commercial agreements and product prices. Existing credentials do not need replacing.

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

## Public release gates — verified November 6, 2026

TestFlight 8 is available. **Public release is not yet ready.** Use [the release board](RELEASE_READINESS.html) for a compact checklist.

### Completed this pass

- Live Forge image round-trip and privacy purge passed using two isolated HTTP clients. Live device revocation, unauthorized-access rejection and disposable-account deletion checks also passed.
- Ten Swift recovery/key-persistence/account-cleanup tests passed. The new archive test restores multiple images into a new Space, rejects a wrong password and confirms original records are unchanged.
- Six focused backend security/image tests passed (41 assertions). Native screenshot capture passed across EN/AR/TR on iPhone and iPad. These supplement the feature's 66 Swift and 53 backend tests documented above.
- A private PostgreSQL custom dump was created on the server and verified readable, including the encrypted-image table. It is not an off-server backup or a completed restore rehearsal.
- English listing fields and private review details are saved. Public release mode is manual. Image/privacy/recovery guidance is prepared in the public support and privacy pages.

### Remaining, in release order

1. **Owner: commercial choices.** Confirm monthly/yearly/lifetime prices, storefronts, legal owner and Paid Apps Agreement/tax/banking status. **Engineering after that:** finish product localizations/review screenshots and align equivalent subscription levels and map all three Apple products to RevenueCat entitlement `arca_app_pro` and current offering `default`. Apple reports `MISSING_METADATA`; monthly/yearly periods are saved as one month/one year; English monthly/yearly product names and descriptions and the Arca Pro group display name are saved. A fresh Apple SDK lookup returned zero packages. See [REVENUECAT.md](REVENUECAT.md).
2. **Engineering: paid E2E after catalog setup.** Verify purchase/cancel/restore/expiration/refund and server quotas using a separate sandbox backend. Production deliberately ignores sandbox webhooks; do not relax that guard. Test Store success does not certify Apple sandbox purchases.
3. **Owner: backup destination and database-admin access.** Choose off-server storage in Forge and place secrets there. **Engineering after access:** schedule backups and rehearse restoration into an isolated database, check records and encrypted image bytes, record recovery time, and verify monitoring. Current app DB role cannot create databases, and unattended admin access was unavailable. Do not grant production runtime credentials permanent database-admin privileges just for a rehearsal.
4. **Owner + engineering: two physical-device acceptance.** Update both devices to build 8. Verify records/keys/images after force-quit, both-way sync, offline recovery, local-only removal, export/restore, device revocation and disposable-account deletion. Complete Arabic/Turkish review, VoiceOver, large text and Switch Control. HTTP clients and simulators provide supporting evidence; they do not replace this check.
5. **Store preparation:** English iPhone/iPad screenshot sets are uploaded. Upload Arabic/Turkish screenshots and listing copy. **Owner:** confirm privacy disclosures, age rating, content rights, regional declarations, copyright and working private cloud-review access. Keep all review secrets in Apple's form.
6. **Public submission only after these gates pass:** attach the tested candidate and first purchases/subscriptions, submit for App Review and address feedback. Release manually after approval. [Apple's first-purchase submission requirements](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase).

### Database recovery helper

`ci/postgres-recovery.py` reads Laravel's PostgreSQL configuration privately and writes a restrictive custom dump plus SHA-256 manifest outside the application. Run it on the backend host:

```sh
python3 ci/postgres-recovery.py --laravel-root /home/forge/arca-api.on-forge.com/backend --output-directory /home/forge/arca-private-backups
```

`--verify-restore` additionally creates a fresh UUID-named temporary database, restores the dump, checks the encrypted-image schema and count, and drops only that temporary database. It needs an appropriately authorized database role. It does not test application-level decryption, configure schedules, retain generations or copy off-server; those are separate release checks. Backups contain sensitive account information even though record/image payloads are encrypted.

For an internal-only upload with an App Store Connect key on the build Mac, use `ci/upload-internal-testflight.sh "/path/to/Arca.xcarchive" "/path/to/AuthKey_KEYID.p8" "ISSUER_ID"`. With a working Xcode account, omit the last two arguments. Confirm processing in the app’s TestFlight tab before assigning testers.
