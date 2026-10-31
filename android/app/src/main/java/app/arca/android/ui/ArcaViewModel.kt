package app.arca.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import app.arca.android.crypto.ArcaCryptoEngine
import app.arca.android.crypto.RecoveryKeyCredential
import app.arca.android.model.AttachmentReference
import app.arca.android.model.AttachmentUploadState
import app.arca.android.model.CalendarDate
import app.arca.android.model.CollectionSchema
import app.arca.android.model.FieldDefinition
import app.arca.android.model.FieldDeletionRetentionPolicy
import app.arca.android.model.FieldType
import app.arca.android.model.FieldValue
import app.arca.android.model.MoneyValue
import app.arca.android.model.RecordItem
import app.arca.android.model.SchemaEngine
import app.arca.android.model.SpaceMetadata
import app.arca.android.model.SpaceStorageMode
import app.arca.android.model.StarterTemplate
import app.arca.android.model.StarterTemplateCatalog
import app.arca.android.model.StarterTemplateID
import app.arca.android.sync.EnrolledDevice
import app.arca.android.sync.SubscriptionTier
import app.arca.android.sync.SyncConflict
import java.time.Instant
import java.util.UUID

class ArcaViewModel(startWithCompletedOnboarding: Boolean = true) : ViewModel() {

    var hasCompletedOnboarding by mutableStateOf(startWithCompletedOnboarding)
    var language by mutableStateOf(AppLanguage.ENGLISH)
    var appearanceMode by mutableStateOf(AppAppearanceMode.LIGHT)
    var bannerState by mutableStateOf(OperationalBannerState.NORMAL)
    var biometricLockEnabled by mutableStateOf(false)
    var isAppLocked by mutableStateOf(false)
    var isOfflineSimulated by mutableStateOf(false)
    var subscriptionTier by mutableStateOf(SubscriptionTier.FREE)
    var globalSearchText by mutableStateOf("")

    private val masterAccountKey = ArcaCryptoEngine.generateMasterAccountKey()
    val recoveryKeyPhrase: String = RecoveryKeyCredential.generate(masterAccountKey).formattedPhrase

    val spaces = mutableStateListOf<SpaceMetadata>()
    var currentSpaceId by mutableStateOf<UUID?>(null)
    val collections = mutableStateListOf<CollectionSchema>()
    val records = mutableStateListOf<RecordItem>()
    val enrolledDevices = mutableStateListOf(
        EnrolledDevice(deviceName = "Pixel 9 Pro (This Device)", isCurrentDevice = true),
        EnrolledDevice(deviceName = "iPhone 16 Pro", isCurrentDevice = false)
    )
    val syncConflicts = mutableStateListOf<SyncConflict>()
    val exportedArchiveNames = mutableStateListOf<String>()

    val currentSpace: SpaceMetadata?
        get() = spaces.firstOrNull { it.id == currentSpaceId } ?: spaces.firstOrNull()

    val collectionsInCurrentSpace: List<CollectionSchema>
        get() {
            val sid = currentSpace?.id ?: return emptyList()
            return collections.filter { it.spaceId == sid }
        }

    val recordsInCurrentSpace: List<RecordItem>
        get() {
            val sid = currentSpace?.id ?: return emptyList()
            return records.filter { it.spaceId == sid && it.deletedAt == null }
                .sortedByDescending { it.updatedAt }
        }

    val favoriteRecordsInCurrentSpace: List<RecordItem>
        get() = recordsInCurrentSpace.filter { it.isFavorite }

    val maxAllowedDevices: Int
        get() = subscriptionTier.maxDevices

    val isProSubscriber: Boolean
        get() = subscriptionTier == SubscriptionTier.PRO

    init {
        seedInitialSpacesAndSampleRecords()
    }

    private fun seedInitialSpacesAndSampleRecords() {
        val personalSpace = SpaceMetadata(
            name = "Personal & Home",
            iconName = "home",
            accentHex = "#1F5673",
            storageMode = SpaceStorageMode.ARCA_SYNC,
            acceptedCloudStorageTermsAt = Instant.now()
        )
        val vehiclesSpace = SpaceMetadata(
            name = "Vehicles",
            iconName = "car",
            accentHex = "#2B5B84",
            storageMode = SpaceStorageMode.ARCA_SYNC,
            acceptedCloudStorageTermsAt = Instant.now()
        )
        val healthSpace = SpaceMetadata(
            name = "Health Notes (Local)",
            iconName = "medical_services",
            accentHex = "#7A3E58",
            storageMode = SpaceStorageMode.LOCAL_ONLY,
            containsSensitiveHealthTemplate = true
        )

        spaces.addAll(listOf(personalSpace, vehiclesSpace, healthSpace))
        currentSpaceId = personalSpace.id

        // Personal collections: Warranties & Home Inventory
        val warrantySchema = StarterTemplateCatalog.warranties.instantiateSchema(personalSpace.id)
        val inventorySchema = StarterTemplateCatalog.homeInventory.instantiateSchema(personalSpace.id)
        collections.add(warrantySchema)
        collections.add(inventorySchema)

        // Seed Warranties
        val wFields = warrantySchema.fields
        records.add(
            RecordItem(
                spaceId = personalSpace.id,
                collectionId = warrantySchema.id,
                isFavorite = true,
                values = mapOf(
                    wFields[0].id to FieldValue.ShortText("Espresso Machine Pro 300"),
                    wFields[1].id to FieldValue.ShortText("Seattle Coffee Gear"),
                    wFields[2].id to FieldValue.DateValue(CalendarDate(2025, 4, 12)),
                    wFields[3].id to FieldValue.DateValue(CalendarDate(2027, 4, 12)),
                    wFields[4].id to FieldValue.BooleanValue(true),
                    wFields[5].id to FieldValue.Attachments(
                        listOf(
                            AttachmentReference(
                                filename = "espresso-warranty-receipt.pdf",
                                mimeType = "application/pdf",
                                byteSize = 184_320L,
                                sha256Hex = "8f4b2e9c7a1d3f5069214e8a7c0b3d1e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c",
                                relativeLocalPath = "attachments/espresso-warranty-receipt.pdf",
                                uploadState = AttachmentUploadState.UPLOADED_VERIFIED
                            )
                        )
                    ),
                    wFields[6].id to FieldValue.LongText("Covers boiler and pump replacement for 24 months.")
                )
            )
        )

        // Seed Home Inventory
        val invFields = inventorySchema.fields
        records.add(
            RecordItem(
                spaceId = personalSpace.id,
                collectionId = inventorySchema.id,
                isFavorite = false,
                values = mapOf(
                    invFields[0].id to FieldValue.ShortText("OLED 65-inch Living Room TV"),
                    invFields[1].id to FieldValue.SingleSelect("living"),
                    invFields[2].id to FieldValue.CurrencyValue(MoneyValue(169900, "USD", 2)),
                    invFields[3].id to FieldValue.DateValue(CalendarDate(2025, 11, 20)),
                    invFields[4].id to FieldValue.ShortText("SN-LG65C4-99481A"),
                    invFields[5].id to FieldValue.Rating(5)
                )
            )
        )

        // Seed Vehicle Maintenance
        val vehicleSchema = StarterTemplateCatalog.vehicleMaintenance.instantiateSchema(vehiclesSpace.id)
        collections.add(vehicleSchema)
        val vFields = vehicleSchema.fields
        records.add(
            RecordItem(
                spaceId = vehiclesSpace.id,
                collectionId = vehicleSchema.id,
                isFavorite = true,
                values = mapOf(
                    vFields[0].id to FieldValue.ShortText("60,000 km Synthetic Oil & Brake Fluid Service"),
                    vFields[1].id to FieldValue.DateValue(CalendarDate(2026, 8, 14)),
                    vFields[2].id to FieldValue.NumberValue(60240.0),
                    vFields[3].id to FieldValue.CurrencyValue(MoneyValue(24500, "USD", 2)),
                    vFields[4].id to FieldValue.SingleSelect("oil"),
                    vFields[5].id to FieldValue.ShortText("Nordic Auto Care")
                )
            )
        )

        // Seed Sensitive Medical Visits (strictly Local-Only)
        val medicalSchema = StarterTemplateCatalog.medicalVisits.instantiateSchema(healthSpace.id)
        collections.add(medicalSchema)
        val mFields = medicalSchema.fields
        records.add(
            RecordItem(
                spaceId = healthSpace.id,
                collectionId = medicalSchema.id,
                isFavorite = false,
                values = mapOf(
                    mFields[0].id to FieldValue.ShortText("Annual Preventive Checkup (Fictional Sample)"),
                    mFields[1].id to FieldValue.DateValue(CalendarDate(2026, 6, 10)),
                    mFields[2].id to FieldValue.ShortText("Harborview Family Clinic"),
                    mFields[3].id to FieldValue.CurrencyValue(MoneyValue(3500, "USD", 2)),
                    mFields[4].id to FieldValue.BooleanValue(false),
                    mFields[5].id to FieldValue.LongText("Routine fictional sample entry demonstrating local-only storage posture.")
                )
            )
        )
    }

    fun finishOnboarding(
        defaultMode: SpaceStorageMode,
        selectedTemplates: Set<StarterTemplateID>,
        createMedicalLocalSpace: Boolean
    ) {
        if (spaces.isEmpty()) {
            seedInitialSpacesAndSampleRecords()
        }
        currentSpace?.let { cur ->
            val idx = spaces.indexOfFirst { it.id == cur.id }
            if (idx >= 0) {
                spaces[idx] = cur.copy(storageMode = defaultMode)
            }
        }
        if (createMedicalLocalSpace && spaces.none { it.containsSensitiveHealthTemplate }) {
            val medSpace = SpaceMetadata(
                name = "Health Notes (Local)",
                iconName = "medical_services",
                accentHex = "#7A3E58",
                storageMode = SpaceStorageMode.LOCAL_ONLY,
                containsSensitiveHealthTemplate = true
            )
            spaces.add(medSpace)
            collections.add(StarterTemplateCatalog.medicalVisits.instantiateSchema(medSpace.id))
        }
        hasCompletedOnboarding = true
    }

    fun selectSpace(spaceId: UUID) {
        currentSpaceId = spaceId
    }

    fun createSpace(name: String, storageMode: SpaceStorageMode) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        val newSpace = SpaceMetadata(
            name = trimmed,
            iconName = "folder",
            accentHex = "#1F5673",
            storageMode = storageMode
        )
        spaces.add(newSpace)
        currentSpaceId = newSpace.id
    }

    fun addCollectionFromTemplate(template: StarterTemplate, inDedicatedLocalSpace: Boolean) {
        val targetSpaceId = if (inDedicatedLocalSpace) {
            val localSpace = SpaceMetadata(
                name = "${template.name} (Local)",
                iconName = template.iconName,
                accentHex = template.colorHex,
                storageMode = SpaceStorageMode.LOCAL_ONLY,
                containsSensitiveHealthTemplate = template.isSensitiveLocalDefault
            )
            spaces.add(localSpace)
            currentSpaceId = localSpace.id
            localSpace.id
        } else {
            currentSpace?.id ?: return
        }
        collections.add(template.instantiateSchema(targetSpaceId))
    }

    fun saveRecord(
        existingRecord: RecordItem?,
        schema: CollectionSchema,
        values: Map<UUID, FieldValue>,
        isFavorite: Boolean
    ) {
        if (existingRecord != null) {
            val idx = records.indexOfFirst { it.id == existingRecord.id }
            if (idx >= 0) {
                records[idx] = existingRecord.copy(
                    values = values,
                    isFavorite = isFavorite,
                    revision = existingRecord.revision + 1,
                    updatedAt = Instant.now()
                )
            }
        } else {
            records.add(
                0,
                RecordItem(
                    spaceId = schema.spaceId,
                    collectionId = schema.id,
                    schemaVersionAtWrite = schema.schemaVersion,
                    isFavorite = isFavorite,
                    values = values
                )
            )
        }
    }

    fun toggleFavorite(recordId: UUID) {
        val idx = records.indexOfFirst { it.id == recordId }
        if (idx >= 0) {
            val rec = records[idx]
            records[idx] = rec.copy(isFavorite = !rec.isFavorite, updatedAt = Instant.now())
        }
    }

    fun duplicateRecord(record: RecordItem) {
        records.add(
            0,
            record.copy(
                id = UUID.randomUUID(),
                revision = 1,
                createdAt = Instant.now(),
                updatedAt = Instant.now()
            )
        )
    }

    fun deleteRecord(recordId: UUID) {
        val idx = records.indexOfFirst { it.id == recordId }
        if (idx >= 0) {
            records[idx] = records[idx].copy(deletedAt = Instant.now())
        }
    }

    fun renameField(collectionId: UUID, fieldId: UUID, newLabel: String) {
        val idx = collections.indexOfFirst { it.id == collectionId }
        if (idx >= 0) {
            collections[idx] = SchemaEngine.renameField(collections[idx], fieldId, newLabel)
        }
    }

    fun archiveOrRemoveField(collectionId: UUID, fieldId: UUID, policy: FieldDeletionRetentionPolicy) {
        val idx = collections.indexOfFirst { it.id == collectionId }
        if (idx < 0) return
        val schema = collections[idx]
        if (policy == FieldDeletionRetentionPolicy.ARCHIVE_AND_RETAIN_VALUES) {
            val updated = schema.fields.map { f ->
                if (f.id == fieldId) f.copy(isArchived = true, archivedAt = Instant.now()) else f
            }
            collections[idx] = schema.copy(fields = updated, schemaVersion = schema.schemaVersion + 1)
        } else {
            val updated = schema.fields.filterNot { it.id == fieldId }
            collections[idx] = schema.copy(fields = updated, schemaVersion = schema.schemaVersion + 1)
        }
    }

    fun searchRecords(query: String): List<RecordItem> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return recordsInCurrentSpace
        return recordsInCurrentSpace.filter { rec ->
            val schema = collections.firstOrNull { it.id == rec.collectionId }
            val titleMatch = schema?.let { rec.title(it).lowercase().contains(q) } ?: false
            val valueMatch = rec.values.values.any { it.plainTextSummary().lowercase().contains(q) }
            titleMatch || valueMatch
        }
    }

    fun exportCurrentSpaceBackup(encrypted: Boolean): String {
        val spaceName = (currentSpace?.name ?: "Space").replace(" ", "-").lowercase()
        val ext = if (encrypted) "arcaarchive.enc" else "arcaarchive"
        val filename = "$spaceName-${Instant.now().epochSecond}.$ext"
        exportedArchiveNames.add(0, filename)
        return filename
    }

    fun restoreBackupAsNewSpace(archiveName: String): SpaceMetadata {
        val restored = SpaceMetadata(
            name = "${currentSpace?.name ?: "Restored"} (Restored)",
            iconName = "folder",
            accentHex = "#2A7B63",
            storageMode = SpaceStorageMode.LOCAL_ONLY
        )
        spaces.add(restored)
        currentSpaceId = restored.id
        return restored
    }

    fun simulateConcurrentConflict() {
        val sample = recordsInCurrentSpace.firstOrNull() ?: return
        val remoteCopy = sample.copy(revision = sample.revision + 1)
        syncConflicts.add(
            SyncConflict(
                spaceId = sample.spaceId,
                recordId = sample.id,
                localRecord = sample,
                remoteRecord = remoteCopy,
                conflictingFieldIds = sample.values.keys.take(1).toSet(),
                summary = "Concurrent edit on ${sample.id.toString().take(6)} preserved safely"
            )
        )
        bannerState = OperationalBannerState.SYNC_CONFLICT
    }

    fun resolveConflict(conflictId: UUID) {
        syncConflicts.removeAll { it.id == conflictId }
        if (syncConflicts.isEmpty() && bannerState == OperationalBannerState.SYNC_CONFLICT) {
            bannerState = OperationalBannerState.NORMAL
        }
    }

    fun enrollDevice(name: String): Result<EnrolledDevice> {
        if (enrolledDevices.size >= maxAllowedDevices) {
            bannerState = OperationalBannerState.THIRD_DEVICE_BLOCKED
            return Result.failure(
                IllegalStateException("Free accounts support up to $maxAllowedDevices active devices. Revoke an older device or upgrade to Arca Pro.")
            )
        }
        val dev = EnrolledDevice(deviceName = name.ifBlank { "Secondary Android" }, isCurrentDevice = false)
        enrolledDevices.add(dev)
        return Result.success(dev)
    }

    fun revokeDevice(deviceId: UUID) {
        enrolledDevices.removeAll { it.deviceId == deviceId && !it.isCurrentDevice }
        // Rotate current Space Encryption Key version for forward secrecy
        currentSpace?.let { cur ->
            val idx = spaces.indexOfFirst { it.id == cur.id }
            if (idx >= 0) {
                spaces[idx] = cur.copy(currentEncryptionKeyVersion = cur.currentEncryptionKeyVersion + 1)
            }
        }
    }
}
