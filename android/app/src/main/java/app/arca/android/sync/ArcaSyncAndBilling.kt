package app.arca.android.sync

import app.arca.android.model.FieldValue
import app.arca.android.model.PersonalCloudProvider
import app.arca.android.model.RecordItem
import app.arca.android.model.SpaceMetadata
import app.arca.android.model.SpaceStorageMode
import java.time.Instant
import java.util.UUID

// MARK: - Sync Conflict Engine & Idempotent Outbox Semantics (No Wall-Clock Timestamp Trust)

data class SyncConflict(
    val id: UUID = UUID.randomUUID(),
    val spaceId: UUID,
    val recordId: UUID,
    val localRecord: RecordItem,
    val remoteRecord: RecordItem,
    val conflictingFieldIds: Set<UUID>,
    val isEditVsDeleteConflict: Boolean = false,
    val summary: String,
    val detectedAt: Instant = Instant.now()
)

sealed class MergeOutcome {
    data class AutoMerged(val mergedRecord: RecordItem) : MergeOutcome()
    data class ConflictPreserved(val conflict: SyncConflict) : MergeOutcome()
}

object SyncConflictEngine {
    /**
     * Merges concurrent changes against `baseRecord` without trusting device wall-clock timestamps.
     * - Disjoint field edits merge automatically.
     * - Overlapping edits to the same field with different values, or edit-vs-delete, preserve both versions in a `SyncConflict`.
     */
    fun mergeConcurrentEdits(
        baseRecord: RecordItem?,
        localRecord: RecordItem,
        remoteRecord: RecordItem
    ): MergeOutcome {
        // Edit vs Delete collision
        if ((localRecord.deletedAt != null) != (remoteRecord.deletedAt != null)) {
            return MergeOutcome.ConflictPreserved(
                SyncConflict(
                    spaceId = localRecord.spaceId,
                    recordId = localRecord.id,
                    localRecord = localRecord,
                    remoteRecord = remoteRecord,
                    conflictingFieldIds = emptySet(),
                    isEditVsDeleteConflict = true,
                    summary = "Edited on one device while deleted on another"
                )
            )
        }

        val allFieldIds = (localRecord.values.keys + remoteRecord.values.keys + (baseRecord?.values?.keys ?: emptySet())).toSet()
        val mergedValues = mutableMapOf<UUID, FieldValue>()
        val conflictingFields = mutableSetOf<UUID>()

        for (fieldId in allFieldIds) {
            val baseVal = baseRecord?.values?.get(fieldId) ?: FieldValue.NullValue
            val localVal = localRecord.values[fieldId] ?: FieldValue.NullValue
            val remoteVal = remoteRecord.values[fieldId] ?: FieldValue.NullValue

            val localChanged = localVal != baseVal
            val remoteChanged = remoteVal != baseVal

            when {
                !localChanged && !remoteChanged -> mergedValues[fieldId] = baseVal
                localChanged && !remoteChanged -> mergedValues[fieldId] = localVal
                !localChanged && remoteChanged -> mergedValues[fieldId] = remoteVal
                localVal == remoteVal -> mergedValues[fieldId] = localVal
                else -> {
                    conflictingFields.add(fieldId)
                    mergedValues[fieldId] = localVal
                }
            }
        }

        if (conflictingFields.isNotEmpty()) {
            return MergeOutcome.ConflictPreserved(
                SyncConflict(
                    spaceId = localRecord.spaceId,
                    recordId = localRecord.id,
                    localRecord = localRecord,
                    remoteRecord = remoteRecord,
                    conflictingFieldIds = conflictingFields,
                    isEditVsDeleteConflict = false,
                    summary = "${conflictingFields.size} field${if (conflictingFields.size == 1) "" else "s"} edited concurrently on two devices"
                )
            )
        }

        val nextRevision = maxOf(localRecord.revision, remoteRecord.revision) + 1
        return MergeOutcome.AutoMerged(
            localRecord.copy(
                values = mergedValues,
                revision = nextRevision,
                updatedAt = Instant.now()
            )
        )
    }
}

// MARK: - Device Enrollment, 2-Device Free Limit, and Key Rotation

data class EnrolledDevice(
    val deviceId: UUID = UUID.randomUUID(),
    val deviceName: String,
    val isCurrentDevice: Boolean,
    val enrolledAt: Instant = Instant.now()
)

// MARK: - Commercial Quotas & Non-Destructive Post-Expiry Policy (Google Play Billing)

enum class SubscriptionTier(val maxDevices: Int, val cloudQuotaBytes: Long) {
    FREE(maxDevices = 2, cloudQuotaBytes = 250L * 1024L * 1024L),
    PRO(maxDevices = 10, cloudQuotaBytes = 25L * 1024L * 1024L * 1024L)
}

object ArcaCommercialConfig {
    const val MONTHLY_PRODUCT_ID = "app.arca.subscription.pro.monthly"
    const val ANNUAL_PRODUCT_ID = "app.arca.subscription.pro.annual"
    const val PROVISIONAL_MONTHLY_PRICE = "$3.99 / month"
    const val PROVISIONAL_ANNUAL_PRICE = "$34.99 / year"
    const val REMOTE_RETENTION_DAYS_AFTER_EXPIRY = 90
    const val OFFERS_LIFETIME_CLOUD_HOSTING = false
}

data class PostExpiryPolicy(
    val effectiveTier: SubscriptionTier,
    val allowsLocalReadWriteCRUD: Boolean = true,
    val allowsLocalSearchAndInsights: Boolean = true,
    val allowsManualPortableExportAndRestore: Boolean = true,
    val deletesLocalRecordsOnExpiry: Boolean = false,
    val isSyncPushAllowed: Boolean,
    val explanationSummary: String
) {
    companion object {
        fun evaluate(tier: SubscriptionTier, activeDeviceCount: Int, remoteStorageBytesUsed: Long): PostExpiryPolicy {
            val overDevices = activeDeviceCount > tier.maxDevices
            val overStorage = remoteStorageBytesUsed > tier.cloudQuotaBytes
            val pushAllowed = !overDevices && !overStorage
            val summary = if (pushAllowed) {
                "All local and synced features are active within your plan limits."
            } else {
                "Cloud sync uploads are paused because your account exceeds the Free plan allowance (${tier.maxDevices} devices / 250 MB). Your local spaces, records, search, and manual .arcaarchive backups remain 100% functional and local records are never deleted."
            }
            return PostExpiryPolicy(
                effectiveTier = tier,
                allowsLocalReadWriteCRUD = true,
                allowsLocalSearchAndInsights = true,
                allowsManualPortableExportAndRestore = true,
                deletesLocalRecordsOnExpiry = false,
                isSyncPushAllowed = pushAllowed,
                explanationSummary = summary
            )
        }
    }
}

// MARK: - Personal Cloud Backup Policy Assessment (Zero Silent Fallback to Arca Cloud)

data class ProviderPolicyAssessment(
    val provider: PersonalCloudProvider,
    val isPermittedForBackup: Boolean,
    val allowsSilentFallbackToArcaCloud: Boolean = false,
    val policySummary: String
) {
    companion object {
        fun evaluate(provider: PersonalCloudProvider, space: SpaceMetadata): ProviderPolicyAssessment {
            if (provider == PersonalCloudProvider.ICLOUD_DRIVE && space.containsSensitiveHealthTemplate) {
                return ProviderPolicyAssessment(
                    provider = provider,
                    isPermittedForBackup = false,
                    allowsSilentFallbackToArcaCloud = false,
                    policySummary = "Sensitive health template Spaces are excluded from automatic iCloud backup."
                )
            }
            return ProviderPolicyAssessment(
                provider = provider,
                isPermittedForBackup = true,
                allowsSilentFallbackToArcaCloud = false,
                policySummary = "Encrypted .arcaarchive.enc backup uploads directly to ${provider.displayName} using app-scoped credentials and never falls back to Arca Cloud."
            )
        }
    }
}

// MARK: - Laravel Arca Sync HTTP Client Configuration

data class LaravelHttpConfig(
    val baseUrl: String = app.arca.android.BuildConfig.ARCA_API_BASE_URL,
    val apiToken: String? = null,
    val revenueCatPublicSdkKey: String = app.arca.android.BuildConfig.REVENUECAT_ANDROID_PUBLIC_KEY,
    val revenueCatProEntitlementId: String = app.arca.android.BuildConfig.REVENUECAT_PRO_ENTITLEMENT_ID,
    val defaultStorageMode: SpaceStorageMode = SpaceStorageMode.ARCA_SYNC
)
