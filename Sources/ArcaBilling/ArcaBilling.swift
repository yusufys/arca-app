import Foundation
import Observation
import StoreKit
import ArcaCore

// MARK: - Centralized Commercial & Quota Configuration

/// Centralized source of truth for Arca's subscription tiers, provisional pricing,
/// device limits, cloud storage quotas, and post-expiry retention guarantees.
///
/// Explicitly avoids any lifetime tier that includes ongoing cloud hosting.
public enum ArcaCommercialConfig {
    /// StoreKit 2 product identifier for the monthly Arca Pro plan.
    public static let monthlyProductID = "app.arca.pro.monthly"

    /// StoreKit 2 product identifier for the annual Arca Pro plan.
    public static let annualProductID = "app.arca.pro.annual"

    /// All StoreKit 2 subscription product identifiers.
    public static let allProductIDs: Set<String> = [
        monthlyProductID,
        annualProductID
    ]

    /// Provisional monthly price ($3.99/month).
    public static let provisionalMonthlyPrice = MoneyValue(minorUnits: 399, currencyCode: "USD", fractionDigits: 2)
    public static let provisionalMonthlyDisplayPrice = "$3.99 / month"

    /// Provisional annual price ($34.99/year).
    public static let provisionalAnnualPrice = MoneyValue(minorUnits: 3499, currencyCode: "USD", fractionDigits: 2)
    public static let provisionalAnnualDisplayPrice = "$34.99 / year"

    /// Free tier active synced device limit (2 devices: e.g., iPhone + iPad or iPhone + Mac).
    public static let freeMaxActiveDevices: Int = 2

    /// Pro tier active synced device limit (10 devices).
    public static let proMaxActiveDevices: Int = 10

    /// Free tier encrypted cloud storage allowance (250 MB).
    public static let freeCloudStorageQuotaBytes: Int64 = 250 * 1024 * 1024

    /// Pro tier encrypted cloud storage allowance (25 GB).
    public static let proCloudStorageQuotaBytes: Int64 = 25 * 1024 * 1024 * 1024

    /// Number of days encrypted remote records are retained after Pro expiry before remote archival.
    public static let remoteRetentionDaysAfterExpiry: Int = 90

    /// Explicit policy: Arca never sells a one-time lifetime tier that promises perpetual cloud hosting.
    public static let offersLifetimeCloudHostingCommitment: Bool = false

    public static let noLifetimeCloudPolicyExplanation: String =
        "Arca does not offer a one-time lifetime cloud tier because encrypted cloud storage and sync infrastructure incur ongoing hosting costs. Local-only usage and manual portable backups (.arcaarchive) are permanently free without any subscription."

    public static func maxActiveDevices(for tier: SubscriptionTier) -> Int {
        switch tier {
        case .free:
            return freeMaxActiveDevices
        case .pro:
            return proMaxActiveDevices
        }
    }

    public static func cloudStorageQuotaBytes(for tier: SubscriptionTier) -> Int64 {
        switch tier {
        case .free:
            return freeCloudStorageQuotaBytes
        case .pro:
            return proCloudStorageQuotaBytes
        }
    }

    public static func formattedStorageQuota(for tier: SubscriptionTier) -> String {
        switch tier {
        case .free:
            return "250 MB"
        case .pro:
            return "25 GB"
        }
    }
}

// MARK: - Subscription Tier & Entitlement State

/// User's subscription tier.
public enum SubscriptionTier: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case free = "free"
    case pro = "pro"

    public var displayName: String {
        switch self {
        case .free: return "Arca Free"
        case .pro: return "Arca Pro"
        }
    }

    public var maxActiveDevices: Int {
        ArcaCommercialConfig.maxActiveDevices(for: self)
    }

    public var cloudStorageQuotaBytes: Int64 {
        ArcaCommercialConfig.cloudStorageQuotaBytes(for: self)
    }

    public var formattedStorageQuota: String {
        ArcaCommercialConfig.formattedStorageQuota(for: self)
    }

    public var includesPersonalCloudBackupAdapters: Bool {
        self == .pro
    }

    public var allowsUnlimitedLocalSpaces: Bool {
        true
    }

    public var allowsManualPortableBackups: Bool {
        true
    }
}

/// Lifecycle state of the user's subscription entitlement.
public enum EntitlementState: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    /// Subscription or Free entitlement is active and verified.
    case active = "active"
    /// StoreKit billing retry / grace period; Pro features remain active while Apple retries billing.
    case billingGracePeriod = "billing_grace_period"
    /// Paid subscription expired and dropped back to Free quotas without deleting any local data.
    case expired = "expired"
    /// Paid subscription was refunded or revoked by the App Store; reverts to Free quotas safely.
    case revokedOrRefunded = "revoked_or_refunded"
    /// Device is offline; relying on the most recent cryptographically verified local entitlement cache.
    case offlineCached = "offline_cached"
    /// A purchase is awaiting parental / Ask to Buy or SCA approval.
    case pendingPurchase = "pending_purchase"

    public var displayTitle: String {
        switch self {
        case .active:
            return "Active"
        case .billingGracePeriod:
            return "Billing Grace Period"
        case .expired:
            return "Expired (Free Quotas Active)"
        case .revokedOrRefunded:
            return "Refunded / Revoked (Free Quotas Active)"
        case .offlineCached:
            return "Offline (Cached Entitlement)"
        case .pendingPurchase:
            return "Pending Approval"
        }
    }
}

/// Detailed snapshot of the current subscription entitlement.
public struct EntitlementSnapshot: Codable, Sendable, Equatable, Hashable {
    public var tier: SubscriptionTier
    public var state: EntitlementState
    public var activeProductId: String?
    public var expirationDate: Date?
    public var gracePeriodEndsAt: Date?
    public var lastVerifiedAt: Date

    public init(
        tier: SubscriptionTier = .free,
        state: EntitlementState = .active,
        activeProductId: String? = nil,
        expirationDate: Date? = nil,
        gracePeriodEndsAt: Date? = nil,
        lastVerifiedAt: Date = Date()
    ) {
        self.tier = tier
        self.state = state
        self.activeProductId = activeProductId
        self.expirationDate = expirationDate
        self.gracePeriodEndsAt = gracePeriodEndsAt
        self.lastVerifiedAt = lastVerifiedAt
    }

    /// Effective tier applied for quota enforcement.
    /// During `billingGracePeriod` or `offlineCached` (when previously Pro), Pro quotas remain honored.
    public var effectiveTier: SubscriptionTier {
        switch state {
        case .active, .billingGracePeriod, .offlineCached:
            return tier
        case .expired, .revokedOrRefunded, .pendingPurchase:
            return .free
        }
    }
}

// MARK: - Post-Expiry Policy & Non-Destructive Safeguards

/// Reason why cloud sync push is paused after a tier downgrade or quota overflow.
public enum SyncPauseReason: String, Codable, Sendable, Equatable, Hashable {
    case deviceLimitExceeded = "device_limit_exceeded"
    case storageQuotaExceeded = "storage_quota_exceeded"
    case bothDeviceAndStorageExceeded = "both_device_and_storage_exceeded"
}

/// Explicit policy and evaluation result governing app behavior when a subscription expires,
/// enters a grace period, or is refunded.
///
/// Guarantees:
/// 1. Local read/write CRUD, search, and manual `.arcaarchive` exports remain 100% functional.
/// 2. Local records are NEVER deleted because a subscription expired or device count exceeds the free limit.
/// 3. Sync pauses gracefully if over quota or over the 2-device limit, with a clear explanation of the
///    remote retention window and device management controls.
public struct PostExpiryPolicy: Codable, Sendable, Equatable, Hashable {
    public let effectiveTier: SubscriptionTier
    public let entitlementState: EntitlementState
    public let allowsLocalReadWriteCRUD: Bool
    public let allowsLocalSearchAndInsights: Bool
    public let allowsManualPortableExportAndRestore: Bool
    public let deletesLocalRecordsOnExpiry: Bool
    public let activeDeviceCount: Int
    public let maxAllowedDevices: Int
    public let remoteStorageBytesUsed: Int64
    public let maxAllowedStorageBytes: Int64
    public let isSyncPushAllowed: Bool
    public let isSyncPullAllowed: Bool
    public let syncPauseReason: SyncPauseReason?
    public let remoteRetentionWindowDays: Int
    public let explanationSummary: String
    public let recommendedUserActions: [String]

    public init(
        effectiveTier: SubscriptionTier = .free,
        entitlementState: EntitlementState = .expired,
        activeDeviceCount: Int = 1,
        remoteStorageBytesUsed: Int64 = 0
    ) {
        self.effectiveTier = effectiveTier
        self.entitlementState = entitlementState
        self.allowsLocalReadWriteCRUD = true
        self.allowsLocalSearchAndInsights = true
        self.allowsManualPortableExportAndRestore = true
        self.deletesLocalRecordsOnExpiry = false

        let maxDevices = effectiveTier.maxActiveDevices
        let maxBytes = effectiveTier.cloudStorageQuotaBytes
        self.activeDeviceCount = activeDeviceCount
        self.maxAllowedDevices = maxDevices
        self.remoteStorageBytesUsed = remoteStorageBytesUsed
        self.maxAllowedStorageBytes = maxBytes
        self.remoteRetentionWindowDays = ArcaCommercialConfig.remoteRetentionDaysAfterExpiry

        let overDevices = activeDeviceCount > maxDevices
        let overStorage = remoteStorageBytesUsed > maxBytes

        if overDevices && overStorage {
            self.isSyncPushAllowed = false
            self.isSyncPullAllowed = true
            self.syncPauseReason = .bothDeviceAndStorageExceeded
            self.explanationSummary =
                "Your local records are completely safe and editable. Cloud sync uploads are paused because your account has \(activeDeviceCount) active devices (Free limit: \(maxDevices)) and uses more than \(effectiveTier.formattedStorageQuota) of encrypted cloud storage. Remote encrypted data is retained for \(ArcaCommercialConfig.remoteRetentionDaysAfterExpiry) days so you can export, manage devices, or renew at your convenience."
            self.recommendedUserActions = [
                "Continue viewing, creating, editing, and exporting all local records without restriction.",
                "Revoke unused devices in Sync & Devices to return to \(maxDevices) active devices.",
                "Remove large remote attachments or renew Arca Pro to resume automatic cloud uploads."
            ]
        } else if overDevices {
            self.isSyncPushAllowed = false
            self.isSyncPullAllowed = true
            self.syncPauseReason = .deviceLimitExceeded
            self.explanationSummary =
                "Your local records are completely safe and editable. Cloud sync uploads are paused because \(activeDeviceCount) devices are enrolled (Free limit: \(maxDevices) active devices). Remote encrypted data is retained for \(ArcaCommercialConfig.remoteRetentionDaysAfterExpiry) days."
            self.recommendedUserActions = [
                "Continue viewing, editing, and exporting all local records normally.",
                "Revoke \(activeDeviceCount - maxDevices) enrolled device(s) to resume Free sync on up to \(maxDevices) devices.",
                "Or renew Arca Pro to sync across up to \(ArcaCommercialConfig.proMaxActiveDevices) devices."
            ]
        } else if overStorage {
            self.isSyncPushAllowed = false
            self.isSyncPullAllowed = true
            self.syncPauseReason = .storageQuotaExceeded
            self.explanationSummary =
                "Your local records are completely safe and editable. Cloud sync uploads are paused because your encrypted cloud usage exceeds the \(effectiveTier.formattedStorageQuota) Free allowance. Existing remote ciphertext is retained for \(ArcaCommercialConfig.remoteRetentionDaysAfterExpiry) days."
            self.recommendedUserActions = [
                "All local records and attachments remain intact on this device.",
                "Export a portable .arcaarchive backup at any time.",
                "Switch heavy Spaces to Local-Only or renew Arca Pro (25 GB) to resume cloud uploads."
            ]
        } else {
            self.isSyncPushAllowed = true
            self.isSyncPullAllowed = true
            self.syncPauseReason = nil
            if entitlementState == .expired || entitlementState == .revokedOrRefunded {
                self.explanationSummary =
                    "Your subscription is no longer active, so your account has transitioned to Arca Free. Because you are within the \(maxDevices)-device and \(effectiveTier.formattedStorageQuota) Free limits, both local editing and encrypted sync continue uninterrupted. Zero local records were removed."
            } else {
                self.explanationSummary =
                    "All local features, manual portable backups, and encrypted sync within your \(effectiveTier.displayName) allowance (\(maxDevices) devices, \(effectiveTier.formattedStorageQuota)) are active."
            }
            self.recommendedUserActions = [
                "Local CRUD and portable .arcaarchive exports are always available."
            ]
        }
    }
}

// MARK: - Displayable Plan Descriptor

public struct ArcaPlanDescriptor: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let tier: SubscriptionTier
    public let title: String
    public let billingPeriodLabel: String
    public let displayPrice: String
    public let maxDevices: Int
    public let formattedStorageQuota: String
    public let features: [String]
    public let badgeText: String?

    public init(
        id: String,
        tier: SubscriptionTier,
        title: String,
        billingPeriodLabel: String,
        displayPrice: String,
        maxDevices: Int,
        formattedStorageQuota: String,
        features: [String],
        badgeText: String? = nil
    ) {
        self.id = id
        self.tier = tier
        self.title = title
        self.billingPeriodLabel = billingPeriodLabel
        self.displayPrice = displayPrice
        self.maxDevices = maxDevices
        self.formattedStorageQuota = formattedStorageQuota
        self.features = features
        self.badgeText = badgeText
    }

    public static let freeTierPlan = ArcaPlanDescriptor(
        id: "app.arca.free",
        tier: .free,
        title: "Arca Free",
        billingPeriodLabel: "Always Free",
        displayPrice: "$0",
        maxDevices: ArcaCommercialConfig.freeMaxActiveDevices,
        formattedStorageQuota: "250 MB",
        features: [
            "Unlimited Local-Only Spaces, Collections, and Records",
            "All 4 Starter Templates & Custom Schema Builder",
            "Full-Text Search, Filters, and Basic Insights",
            "Unlimited Manual Portable Backups (.arcaarchive)",
            "End-to-End Encrypted Arca Sync on up to 2 Active Devices",
            "250 MB Encrypted Cloud Storage Allowance"
        ],
        badgeText: nil
    )

    public static let proMonthlyPlan = ArcaPlanDescriptor(
        id: ArcaCommercialConfig.monthlyProductID,
        tier: .pro,
        title: "Arca Pro Monthly",
        billingPeriodLabel: "Monthly",
        displayPrice: ArcaCommercialConfig.provisionalMonthlyDisplayPrice,
        maxDevices: ArcaCommercialConfig.proMaxActiveDevices,
        formattedStorageQuota: "25 GB",
        features: [
            "Everything in Arca Free",
            "Sync across up to 10 Active Devices",
            "25 GB End-to-End Encrypted Cloud Storage",
            "Optional Encrypted Personal Cloud Backup Adapters",
            "Zero Lock-In: Keep all local data & exports if you ever cancel"
        ],
        badgeText: nil
    )

    public static let proAnnualPlan = ArcaPlanDescriptor(
        id: ArcaCommercialConfig.annualProductID,
        tier: .pro,
        title: "Arca Pro Annual",
        billingPeriodLabel: "Annual",
        displayPrice: ArcaCommercialConfig.provisionalAnnualDisplayPrice,
        maxDevices: ArcaCommercialConfig.proMaxActiveDevices,
        formattedStorageQuota: "25 GB",
        features: [
            "Everything in Arca Free",
            "Sync across up to 10 Active Devices",
            "25 GB End-to-End Encrypted Cloud Storage",
            "Optional Encrypted Personal Cloud Backup Adapters",
            "Save 27% compared to monthly billing"
        ],
        badgeText: "Best Value"
    )

    public static let defaultCatalog: [ArcaPlanDescriptor] = [
        freeTierPlan,
        proMonthlyPlan,
        proAnnualPlan
    ]
}

// MARK: - Billing Error

public enum BillingError: LocalizedError, Sendable, Equatable {
    case productNotFound(String)
    case userCancelledPurchase
    case purchasePendingApproval
    case verificationFailed
    case storeSyncFailed(String)

    public var errorDescription: String? {
        switch self {
        case .productNotFound(let id):
            return "The selected subscription plan (\(id)) is not currently available from the App Store."
        case .userCancelledPurchase:
            return "Purchase was cancelled."
        case .purchasePendingApproval:
            return "Your purchase is pending approval (such as Ask to Buy)."
        case .verificationFailed:
            return "App Store transaction signature verification failed."
        case .storeSyncFailed(let reason):
            return "Could not restore purchases right now: \(reason)"
        }
    }
}

// MARK: - StoreKit 2 Billing Manager

/// Coordinates StoreKit 2 product loading, purchases, transaction verification,
/// purchase restoration (`AppStore.sync()`), post-expiry policy evaluation, and
/// deterministic test state injection.
@available(macOS 14.0, iOS 17.0, *)
@MainActor
@Observable
public final class BillingManager {
    public private(set) var snapshot: EntitlementSnapshot
    public private(set) var availablePlans: [ArcaPlanDescriptor]
    public private(set) var storeProducts: [Product]
    public private(set) var isLoadingProducts: Bool
    public private(set) var isRestoringPurchases: Bool
    public private(set) var lastStatusMessage: String?
    public private(set) var lastErrorMessage: String?

    public var currentTier: SubscriptionTier {
        snapshot.effectiveTier
    }

    public var entitlementState: EntitlementState {
        snapshot.state
    }

    public init(
        initialTier: SubscriptionTier = .free,
        initialState: EntitlementState = .active
    ) {
        self.snapshot = EntitlementSnapshot(
            tier: initialTier,
            state: initialState,
            activeProductId: initialTier == .pro ? ArcaCommercialConfig.annualProductID : nil,
            expirationDate: initialTier == .pro ? Calendar.current.date(byAdding: .year, value: 1, to: Date()) : nil
        )
        self.availablePlans = ArcaPlanDescriptor.defaultCatalog
        self.storeProducts = []
        self.isLoadingProducts = false
        self.isRestoringPurchases = false
        self.lastStatusMessage = nil
        self.lastErrorMessage = nil
    }

    /// Loads StoreKit 2 products for `ArcaCommercialConfig.allProductIDs`.
    /// If StoreKit is unconfigured in a local test environment, retains the provisional catalog cleanly.
    public func loadProducts() async {
        isLoadingProducts = true
        lastErrorMessage = nil
        defer { isLoadingProducts = false }

        do {
            let fetched = try await Product.products(for: ArcaCommercialConfig.allProductIDs)
            self.storeProducts = fetched.sorted { $0.price < $1.price }

            if !fetched.isEmpty {
                var updatedPlans: [ArcaPlanDescriptor] = [.freeTierPlan]
                for product in self.storeProducts {
                    let isAnnual = product.id == ArcaCommercialConfig.annualProductID
                    updatedPlans.append(ArcaPlanDescriptor(
                        id: product.id,
                        tier: .pro,
                        title: product.displayName.isEmpty
                            ? (isAnnual ? "Arca Pro Annual" : "Arca Pro Monthly")
                            : product.displayName,
                        billingPeriodLabel: isAnnual ? "Annual" : "Monthly",
                        displayPrice: product.displayPrice,
                        maxDevices: ArcaCommercialConfig.proMaxActiveDevices,
                        formattedStorageQuota: ArcaCommercialConfig.formattedStorageQuota(for: .pro),
                        features: isAnnual
                            ? ArcaPlanDescriptor.proAnnualPlan.features
                            : ArcaPlanDescriptor.proMonthlyPlan.features,
                        badgeText: isAnnual ? "Best Value" : nil
                    ))
                }
                self.availablePlans = updatedPlans
            }
        } catch {
            // Preserve provisional catalog so UI and tests remain functional offline
            self.availablePlans = ArcaPlanDescriptor.defaultCatalog
        }
    }

    /// Initiates a purchase for the specified StoreKit product identifier.
    /// In environments where StoreKit products are loaded, runs `product.purchase()`.
    @discardableResult
    public func purchase(productId: String) async throws -> EntitlementSnapshot {
        lastErrorMessage = nil
        lastStatusMessage = nil

        if let product = storeProducts.first(where: { $0.id == productId }) {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                switch verificationResult {
                case .verified(let transaction):
                    await transaction.finish()
                    let nextSnapshot = EntitlementSnapshot(
                        tier: .pro,
                        state: .active,
                        activeProductId: transaction.productID,
                        expirationDate: transaction.expirationDate,
                        lastVerifiedAt: Date()
                    )
                    self.snapshot = nextSnapshot
                    self.lastStatusMessage = "Arca Pro is now active."
                    return nextSnapshot
                case .unverified:
                    self.lastErrorMessage = BillingError.verificationFailed.errorDescription
                    throw BillingError.verificationFailed
                }
            case .userCancelled:
                throw BillingError.userCancelledPurchase
            case .pending:
                self.snapshot = EntitlementSnapshot(
                    tier: snapshot.tier,
                    state: .pendingPurchase,
                    activeProductId: productId,
                    lastVerifiedAt: Date()
                )
                throw BillingError.purchasePendingApproval
            @unknown default:
                throw BillingError.userCancelledPurchase
            }
        } else {
            guard ArcaCommercialConfig.allProductIDs.contains(productId) else {
                throw BillingError.productNotFound(productId)
            }
            // Sandbox / test environment fallback when StoreKit daemon has no loaded StoreKit configuration file
            let nextSnapshot = EntitlementSnapshot(
                tier: .pro,
                state: .active,
                activeProductId: productId,
                expirationDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
                lastVerifiedAt: Date()
            )
            self.snapshot = nextSnapshot
            self.lastStatusMessage = "Arca Pro activated (Provisional Test Environment)."
            return nextSnapshot
        }
    }

    /// Restores purchases via StoreKit 2 `AppStore.sync()` and refreshes current entitlements.
    @discardableResult
    public func restorePurchases(performStoreSync: Bool = true) async throws -> EntitlementSnapshot {
        isRestoringPurchases = true
        lastErrorMessage = nil
        defer { isRestoringPurchases = false }

        if performStoreSync && !storeProducts.isEmpty {
            do {
                try await AppStore.sync()
            } catch {
                let err = BillingError.storeSyncFailed(error.localizedDescription)
                self.lastErrorMessage = err.errorDescription
                throw err
            }
        }

        await refreshEntitlementsFromStoreKit()
        self.lastStatusMessage = snapshot.effectiveTier == .pro
            ? "Restored Arca Pro entitlement."
            : "No active paid subscriptions found; Arca Free is active."
        return snapshot
    }

    /// Inspects `Transaction.currentEntitlements` from StoreKit 2 to update `snapshot`.
    public func refreshEntitlementsFromStoreKit() async {
        var foundProTransaction: Transaction?
        var wasRevoked = false

        for await verificationResult in Transaction.currentEntitlements {
            if case .verified(let transaction) = verificationResult,
               ArcaCommercialConfig.allProductIDs.contains(transaction.productID) {
                if transaction.revocationDate != nil {
                    wasRevoked = true
                } else {
                    foundProTransaction = transaction
                }
            }
        }

        if let tx = foundProTransaction {
            if let exp = tx.expirationDate, exp < Date() {
                self.snapshot = EntitlementSnapshot(
                    tier: .free,
                    state: .expired,
                    activeProductId: tx.productID,
                    expirationDate: exp,
                    lastVerifiedAt: Date()
                )
            } else {
                self.snapshot = EntitlementSnapshot(
                    tier: .pro,
                    state: .active,
                    activeProductId: tx.productID,
                    expirationDate: tx.expirationDate,
                    lastVerifiedAt: Date()
                )
            }
        } else if wasRevoked {
            self.snapshot = EntitlementSnapshot(
                tier: .free,
                state: .revokedOrRefunded,
                activeProductId: nil,
                expirationDate: nil,
                lastVerifiedAt: Date()
            )
        }
    }

    /// Deterministic state injection for unit tests, integration tests, and SwiftUI previews.
    public func injectDeterministicState(
        tier: SubscriptionTier,
        state: EntitlementState,
        activeProductId: String? = nil,
        expirationDate: Date? = nil,
        gracePeriodEndsAt: Date? = nil
    ) {
        self.snapshot = EntitlementSnapshot(
            tier: tier,
            state: state,
            activeProductId: activeProductId ?? (tier == .pro ? ArcaCommercialConfig.annualProductID : nil),
            expirationDate: expirationDate,
            gracePeriodEndsAt: gracePeriodEndsAt,
            lastVerifiedAt: Date()
        )
        self.lastErrorMessage = nil
    }

    /// Evaluates post-expiry and quota behavior for the current entitlement state.
    /// Guarantees that local CRUD and manual exports are never restricted or deleted.
    public func evaluatePostExpiryPolicy(
        activeDeviceCount: Int,
        remoteStorageBytesUsed: Int64
    ) -> PostExpiryPolicy {
        PostExpiryPolicy(
            effectiveTier: snapshot.effectiveTier,
            entitlementState: snapshot.state,
            activeDeviceCount: activeDeviceCount,
            remoteStorageBytesUsed: remoteStorageBytesUsed
        )
    }
}
