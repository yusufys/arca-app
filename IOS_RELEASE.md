# Arca iOS release handoff

App Store Connect record: **Arca - Personal Records**, Apple ID **6830898859**, bundle **app.arca.personalrecords**. Internal beta first. Use fictional data and the supplied build number in all feedback.

## App Store Connect listing draft

- Primary category: Productivity. Suggested subtitle: **Warranties, inventory & more**.
- Description: Keep warranties, vehicle service records and home inventory together. Create a Space, choose a template or design your own collection, and find a record by searching its fields. Use a Local-Only Space to keep records on one device, or connect an Arca account to sync encrypted changes across your devices. Export an encrypted archive for recovery. Arca Pro provides higher device and storage limits.
- Keywords: inventory,warranty,maintenance,organizer,receipts,collections
- Support: https://arca-api.on-forge.com/support.html · Privacy: https://arca-api.on-forge.com/privacy.html · Support and beta feedback: hi@kawkbi.com
- Release note: First iOS release. Save, search and organize records on your iPhone, protect sensitive data, and recover synced collections on a second device.
- Review access: Provide a disposable working review account and its recovery phrase in App Store Connect’s private review notes when cloud testing is required. Confirm the backend is reachable throughout review. Keep sign-in details out of Git.
- Before submission: use the [English iPhone and iPad screenshots](artifacts/app-store-screenshots/en-US/); finish the age-rating and content-rights questionnaires, regional business details, privacy disclosures, and the encryption assessment for the final binary. Compare connected account identifiers, email, purchase history, cloud operations and RevenueCat diagnostic data with the actual configuration. Document the intended storefronts, pricing and renewal terms. Apple and RevenueCat credentials belong in their own consoles.

## Suggested collections and AI design (build 5)

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
