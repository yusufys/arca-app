# Arca Pro on iOS

Arca uses the same account UUID for Forge and RevenueCat. A signed-in user opens **Settings → Arca Plan & Quotas** to purchase, restore or manage Pro. Local-only use requires no billing identity.

## 1. Install the package and run Debug

Open `Arca.xcodeproj`. The iOS app target links **RevenueCat** and **RevenueCatUI** from [purchases-ios-spm](https://github.com/RevenueCat/purchases-ios-spm.git). The project resolves version 5.102.0. Xcode’s Package Dependencies and the committed Package.resolved record the integration. [Installation instructions](https://www.revenuecat.com/docs/getting-started/installation/ios#install-via-swift-package-manager)

Debug uses the supplied Test Store public key. Sign into an Arca test account and open the plan screen. The Test Store API returned the current offering `default` and all three package mappings below on 5 November 2026. That lookup verifies the catalog. The Apple public SDK key returned the same current offering with zero packages for Apple. Link the Apple products in step 3. A successful checkout and restore must still be recorded for each store.

## 2. Connect the real Apple app

1. Open [App Store Connect](https://appstoreconnect.apple.com/) → **Apps**. Select **Arca - Personal Records** (Apple ID 6830898859), which uses `app.arca.personalrecords`, the registered identifier on Yusuf’s team. Complete the Paid Apps Agreement and any missing tax or banking items in Business.
2. Open **Users and Access → Integrations → In-App Purchase**. Generate an In-App Purchase key, securely download its .p8 file, and copy the Issuer ID. Store the download securely.
3. Open [RevenueCat](https://app.revenuecat.com/) → Arca → **Apps & providers**. Add an Apple App Store app with that same bundle ID. Upload the .p8 directly to its In-app purchase key configuration, enter the Issuer ID and save. Complete Apple server notifications using the URL in that app’s RevenueCat configuration. [Apple credential guide](https://www.revenuecat.com/docs/service-credentials/itunesconnect-app-specific-shared-secret/in-app-purchase-key-configuration)
4. In RevenueCat **Project settings → API keys → Public app-specific API keys**, select the Apple app and copy its `appl_…` key. The supplied Apple public key for RevenueCat app `appcf1b74bb7d` is configured in the Xcode app target’s **Release** build setting `ARCA_RC_PUBLIC_KEY`, or supply it to the archive command. The Test Store key is scoped to Debug. Use the Apple app key for TestFlight, where Apple purchases run in its sandbox.

## 3. Set up three products and one entitlement

| Apple product ID | App Store Connect product type | Package in the current offering |
| --- | --- | --- |
| `monthly` | Auto-renewable subscription, one month | Monthly / `$rc_monthly` |
| `yearly` | Auto-renewable subscription, one year | Annual / `$rc_annual` |
| `lifetime` | Non-consumable in-app purchase | Lifetime / `$rc_lifetime` |

In the Apple app’s **Subscriptions**, create one subscription group for monthly and yearly. Use the same access level for both. Create lifetime under **In-App Purchases**. Supply prices, availability, localizations and review information using the intended commercial terms.

In RevenueCat **Product catalog → Products**, import or add those Apple products. Under **Entitlements**, attach all three to the exact identifier `arca_app_pro`. Under **Offerings → default**, attach each Apple product to the matching existing package alongside its Test Store counterpart. Set the offering as current. Publish a paywall for that offering with all three choices, localized prices, restore and the required legal links. Configure Customer Center support with **hi@kawkbi.com** and verify that the project’s plan includes Customer Center. [Paywalls](https://www.revenuecat.com/docs/tools/paywalls) · [Customer Center](https://www.revenuecat.com/docs/tools/customer-center)

## 4. SwiftUI implementation

The complete, compiling example is [ArcaPurchases.swift](iOSApp/ArcaPurchases.swift). [ArcaiOSApp.swift](iOSApp/ArcaiOSApp.swift) owns it for the app lifetime and injects its plan screen into Settings. It configures the SDK only after Arca knows the real account UUID. When an account changes, it uses RevenueCat login. It fetches CustomerInfo and observes subsequent updates. Restore is an explicit user action. Prices and product choices come from the current offering.

The essential flow, with the state and error handling shown in full in the linked implementation:

```swift
// Once, after obtaining the authenticated Arca account UUID.
Purchases.configure(withAPIKey: publicSDKKey, appUserID: accountUUID)
let info = try await Purchases.shared.customerInfo()
let hasPro = info.entitlements["arca_app_pro"]?.isActive == true
let offering = try await Purchases.shared.offerings().current

// In a SwiftUI sheet once the current offering has loaded:
if let offering {
    PaywallView(offering: offering, displayCloseButton: true)
        .onPurchaseCompleted { info in purchases.apply(info, to: model) }
        .onRestoreCompleted { info in purchases.apply(info, to: model) }
}
```

The screen offers retry for network failures and unavailable offerings. Customer Center is presented from **Manage purchases**. The paywall handles cancellation, and the app grants Pro only from active entitlement information. Restoring refreshes CustomerInfo even if the previous transaction was made on another installation.

## 5. Connect Forge to RevenueCat

1. In RevenueCat **Project settings → API keys**, create a **v1 secret API key** for server-side customer reads. Store it in Forge → **thekernel → Arca site → Environment** as `REVENUECAT_SERVER_API_KEY`. Keep this key on the server.
2. Generate a random webhook password in a password manager. In the same Forge environment set `REVENUECAT_WEBHOOK_SECRET` to the password alone, `REVENUECAT_PRO_ENTITLEMENT_ID=arca_app_pro` and `REVENUECAT_ENVIRONMENT=PRODUCTION`. Save and redeploy to refresh cached configuration.
3. In RevenueCat **Integrations → Webhooks**, add `https://arca-api.on-forge.com/api/v1/webhooks/revenuecat`. Supply **Bearer** followed by a space and the same webhook password in **Authorization header**. Select production deliveries. Use a separate staging backend and SANDBOX webhook for Test Store and TestFlight quota testing.
4. Send a test webhook, then exercise a purchase. Check delivery history and the Arca account UUID. The server verifies the header, handles duplicate deliveries, and queries current subscriber entitlements before setting cloud quotas. A generic TEST event confirms connectivity only. [Webhook guide](https://www.revenuecat.com/docs/integrations/webhooks)

## 6. Sign off each path

Use disposable accounts. Record build, environment, device, product, CustomerInfo state and the account’s Forge entitlement after the webhook. Check successful and cancelled purchase, restore on a fresh install, expiry, refund, billing retry, lifetime access with no expiration, loss of network, and Customer Center. Run again on the Apple sandbox TestFlight build before public submission. Verify the privacy disclosures against [RevenueCat’s Apple privacy guidance](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy).

To prepare a signed archive once the public Apple key is available, run <code>ARCA_RC_PUBLIC_KEY=appl_YOUR_PUBLIC_KEY ./ci/archive-ios.sh</code>. In Xcode Organizer validate the archive, distribute it to App Store Connect and select the processed build for the internal tester group. Complete Apple’s export compliance questions for the actual encryption implementation. Support: https://arca-api.on-forge.com/support.html · Privacy: https://arca-api.on-forge.com/privacy.html
