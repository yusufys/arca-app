import ArcaUI
import RevenueCat
import RevenueCatUI
import SwiftUI

@MainActor
final class ArcaPurchases: ObservableObject {
    static let entitlementID = "arca_app_pro"
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var ready = false
    @Published private(set) var refreshID = 0

    func retryConnection() { refreshID += 1 }
    @Published var message: String?

    // The same opaque account UUID is used by Forge and RevenueCat webhooks.
    func observe(_ model: ArcaAppViewModel) async {
        let account = model.purchaseAccountID
        ready = false
        customerInfo = nil
        message = nil
        model.isProSubscriber = false
        guard let account else { return }
        let key = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_IOS_PUBLIC_KEY") as? String ?? ""
        #if DEBUG
        let validKey = key.hasPrefix("test_") || key.hasPrefix("appl_")
        #else
        let validKey = key.hasPrefix("appl_")
        #endif
        guard validKey else {
            message = "Purchases are unavailable in this build."
            return
        }
        do {
            if !Purchases.isConfigured {
                Purchases.configure(withAPIKey: key, appUserID: account)
            } else if Purchases.shared.appUserID != account {
                _ = try await Purchases.shared.logIn(account)
            }
            Purchases.shared.overridePreferredUILocale(model.language.rawValue)
            let info = try await Purchases.shared.customerInfo()
            guard !Task.isCancelled, model.purchaseAccountID == account else { return }
            apply(info, to: model)
            ready = true
            for await update in Purchases.shared.customerInfoStream {
                guard !Task.isCancelled, model.purchaseAccountID == account else { return }
                apply(update, to: model)
            }
        } catch {
            if !Task.isCancelled { message = error.localizedDescription }
        }
    }

    func apply(_ info: CustomerInfo, to model: ArcaAppViewModel) {
        guard Purchases.isConfigured, Purchases.shared.appUserID == model.purchaseAccountID else { return }
        customerInfo = info
        model.isProSubscriber = info.entitlements[Self.entitlementID]?.isActive == true
    }
}

struct ArcaPlanView: View {
    @ObservedObject var purchases: ArcaPurchases
    let model: ArcaAppViewModel
    @State private var offering: Offering?
    @State private var showPaywall = false
    @State private var showCenter = false
    @State private var working = false
    @State private var feedback: String?
    @State private var retry = 0

    var body: some View {
        List {
            Section(model.language.localized("Your plan")) {
                Text(model.language.localized(model.isProSubscriber ? "Arca Pro" : "Arca Free"))
                if let active = purchases.customerInfo?.entitlements[ArcaPurchases.entitlementID], active.isActive {
                    if let date = active.expirationDate {
                        Text(model.language.format("Access through %@", date.formatted(.dateTime.day().month().year().locale(model.language.locale))))
                    } else { Text(model.language.localized("Lifetime access")) }
                }
            }
            if model.purchaseAccountID == nil {
                Text(model.language.localized("Connect your Arca account in Settings to purchase or restore Pro."))
            } else if purchases.ready {
                Section {
                    if !model.isProSubscriber {
                        Button(model.language.localized("View plans")) { showPaywall = true }
                            .disabled(offering == nil || working)
                    }
                    Button(model.language.localized("Restore purchases")) {
                        Task {
                            working = true
                            defer { working = false }
                            do {
                                purchases.apply(try await Purchases.shared.restorePurchases(), to: model)
                                feedback = model.isProSubscriber ? "Arca Pro restored." : "No active Arca Pro purchase found."
                            } catch { feedback = error.localizedDescription }
                        }
                    }.disabled(working)
                    Button(model.language.localized("Manage purchases")) { showCenter = true }
                }
            }
            if let text = feedback ?? purchases.message {
                Text(model.language.localized(text))
                Button(model.language.localized("Retry")) {
                    if purchases.ready { retry += 1 } else { purchases.retryConnection() }
                }
            }
        }
        .navigationTitle(model.language.localized("Arca Pro"))
        .environment(\.locale, model.language.locale)
        .environment(\.layoutDirection, model.language.layoutDirection)
        .task(id: "\(purchases.ready)-\(retry)-\(model.language.rawValue)") {
            guard purchases.ready else { offering = nil; return }
            Purchases.shared.overridePreferredUILocale(model.language.rawValue)
            do {
                feedback = nil
                offering = try await Purchases.shared.offerings().current
                if offering == nil { feedback = "Plans are temporarily unavailable. Try again later." }
            } catch { if !Task.isCancelled { feedback = error.localizedDescription } }
        }
        .sheet(isPresented: $showPaywall) {
            if let offering {
                PaywallView(offering: offering, displayCloseButton: true)
                    .environment(\.locale, model.language.locale)
                    .environment(\.layoutDirection, model.language.layoutDirection)
                    .onPurchaseCompleted { info in
                        purchases.apply(info, to: model)
                        showPaywall = false
                    }
                    .onRestoreCompleted { info in
                        purchases.apply(info, to: model)
                        showPaywall = false
                    }
                    .onPurchaseFailure { _ in feedback = "The purchase could not be completed. Please try again." }
                    .onRestoreFailure { _ in feedback = "The purchase could not be completed. Please try again." }
            }
        }
        .presentCustomerCenter(isPresented: $showCenter)
    }
}
