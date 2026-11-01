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
import app.arca.android.model.PublicRecordSnapshot
import app.arca.android.model.RecordItem
import app.arca.android.model.RecordSortCriterion
import app.arca.android.model.SchemaEngine
import app.arca.android.model.SelectOption
import app.arca.android.model.SpaceInsightsReport
import app.arca.android.model.SpaceMetadata
import app.arca.android.model.SpaceStorageMode
import app.arca.android.model.StarterTemplate
import app.arca.android.model.StarterTemplateCatalog
import app.arca.android.model.StarterTemplateID
import app.arca.android.sync.CloudAccountSession
import app.arca.android.sync.EnrolledDevice
import app.arca.android.sync.SubscriptionTier
import app.arca.android.sync.SyncConflict
import java.time.Instant
import java.util.Locale
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

    // Device token registration & cloud account session
    var currentDevice by mutableStateOf(
        EnrolledDevice(
            deviceName = "Pixel 9 Pro (This Device)",
            platform = "android",
            userId = null,
            isCurrentDevice = true
        )
    )
    var cloudAccountSession by mutableStateOf<CloudAccountSession?>(null)

    val spaces = mutableStateListOf<SpaceMetadata>()
    var currentSpaceId by mutableStateOf<UUID?>(null)
    val collections = mutableStateListOf<CollectionSchema>()
    val records = mutableStateListOf<RecordItem>()
    val enrolledDevices = mutableStateListOf<EnrolledDevice>()
    val syncConflicts = mutableStateListOf<SyncConflict>()
    val exportedArchiveNames = mutableStateListOf<String>()
    val publicSnapshots = mutableStateListOf<PublicRecordSnapshot>()

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

    val currentSpaceInsights: SpaceInsightsReport
        get() = SpaceInsightsReport.compute(
            spaceId = currentSpace?.id ?: UUID.randomUUID(),
            collections = collectionsInCurrentSpace,
            records = recordsInCurrentSpace
        )

    val maxAllowedDevices: Int
        get() = subscriptionTier.maxDevices

    val isProSubscriber: Boolean
        get() = subscriptionTier == SubscriptionTier.PRO

    init {
        enrolledDevices.add(currentDevice)
        enrolledDevices.add(
            EnrolledDevice(
                deviceName = "iPhone 16 Pro",
                platform = "ios",
                userId = null,
                isCurrentDevice = false
            )
        )
        registerOrUpdateAnonymousDevice()
        bootstrapDefaultWorkspace()
    }

    // MARK: - Device Registration & Cloud Account

    fun registerOrUpdateAnonymousDevice() {
        val idx = enrolledDevices.indexOfFirst { it.deviceId == currentDevice.deviceId }
        if (idx < 0) {
            enrolledDevices.add(0, currentDevice)
        } else {
            enrolledDevices[idx] = currentDevice
        }

        // Asynchronously register or update anonymous device with backend without blocking or failing offline
        Thread {
            try {
                val url = java.net.URL("${app.arca.android.BuildConfig.ARCA_API_BASE_URL}/api/v1/devices/register")
                val conn = url.openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 1500
                conn.readTimeout = 1500
                conn.requestMethod = "POST"
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Accept", "application/json")
                val json = """{"device_id":"${currentDevice.deviceId}","device_token":"${currentDevice.deviceToken}","device_name":"${currentDevice.deviceName}","platform":"android","public_key_x25519":"${currentDevice.publicKeyX25519}"}"""
                conn.outputStream.use { it.write(json.toByteArray(Charsets.UTF_8)) }
                conn.responseCode
                conn.disconnect()
            } catch (_: Exception) {
                // Safely ignore when offline or testing without live server
            }
        }.start()
    }

    fun loginOrRegisterCloudAccount(
        name: String,
        email: String,
        password: String,
        isRegistration: Boolean
    ): Result<CloudAccountSession> {
        val trimmedEmail = email.trim()
        val trimmedName = name.trim().ifBlank { "Arca User" }
        if (trimmedEmail.isEmpty() || password.isEmpty()) {
            return Result.failure(IllegalArgumentException("Email and password are required"))
        }

        var resolvedUserId = 101L
        var resolvedUuid = UUID.randomUUID().toString()
        var resolvedName = trimmedName
        var resolvedToken = "arca_tok_${UUID.randomUUID().toString().replace("-", "").take(24)}"
        var resolvedTier = SubscriptionTier.FREE

        // Attempt HTTP request if backend is reachable
        try {
            val endpoint = if (isRegistration) "/api/v1/auth/register" else "/api/v1/auth/login"
            val url = java.net.URL("${app.arca.android.BuildConfig.ARCA_API_BASE_URL}$endpoint")
            val conn = url.openConnection() as java.net.HttpURLConnection
            conn.connectTimeout = 2000
            conn.readTimeout = 2000
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Accept", "application/json")
            val payload = if (isRegistration) {
                """{"name":"$trimmedName","email":"$trimmedEmail","password":"$password"}"""
            } else {
                """{"email":"$trimmedEmail","password":"$password"}"""
            }
            conn.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            if (code in 200..299) {
                val resp = conn.inputStream.bufferedReader().use { it.readText() }
                val root = app.arca.android.model.SimpleJsonParser.parse(resp) as? Map<*, *>
                val userObj = root?.get("user") as? Map<*, *>
                if (userObj != null) {
                    resolvedUserId = (userObj["id"] as? Number)?.toLong() ?: 101L
                    resolvedUuid = (userObj["uuid"] as? String) ?: resolvedUuid
                    resolvedName = (userObj["name"] as? String) ?: resolvedName
                    val tierStr = (userObj["subscription_tier"] as? String) ?: "free"
                    resolvedTier = if (tierStr.equals("pro", ignoreCase = true)) SubscriptionTier.PRO else SubscriptionTier.FREE
                }
                resolvedToken = (root?.get("api_token") as? String) ?: resolvedToken
            }
            conn.disconnect()
        } catch (_: Exception) {
            // Local fallback for offline mode or test environment
        }

        // Associate currentDevice with the user's userId
        val updatedDevice = currentDevice.copy(userId = resolvedUserId)
        currentDevice = updatedDevice
        val idx = enrolledDevices.indexOfFirst { it.deviceId == updatedDevice.deviceId }
        if (idx >= 0) {
            enrolledDevices[idx] = updatedDevice
        } else {
            enrolledDevices.add(0, updatedDevice)
        }

        val session = CloudAccountSession(
            userId = resolvedUserId,
            userUuid = resolvedUuid,
            name = resolvedName,
            email = trimmedEmail,
            apiToken = resolvedToken,
            tier = resolvedTier,
            associatedDeviceId = updatedDevice.deviceId,
            associatedDeviceToken = updatedDevice.deviceToken
        )
        cloudAccountSession = session
        subscriptionTier = resolvedTier
        return Result.success(session)
    }

    fun logoutCloudAccount() {
        cloudAccountSession = null
        val unlinkedDevice = currentDevice.copy(userId = null)
        currentDevice = unlinkedDevice
        val idx = enrolledDevices.indexOfFirst { it.deviceId == unlinkedDevice.deviceId }
        if (idx >= 0) {
            enrolledDevices[idx] = unlinkedDevice
        }
        subscriptionTier = SubscriptionTier.FREE
    }

    // MARK: - Workspace & Seeding

    fun bootstrapDefaultWorkspace() {
        seedInitialSpacesAndSampleRecords()
    }

    private fun seedInitialSpacesAndSampleRecords() {
        if (spaces.isNotEmpty()) return

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

        // Warranties & Serials
        val warrantySchema = StarterTemplateCatalog.warranties.instantiateSchema(personalSpace.id)
        val inventorySchema = StarterTemplateCatalog.homeInventory.instantiateSchema(personalSpace.id)
        collections.add(warrantySchema)
        collections.add(inventorySchema)

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

    // MARK: - Space Management

    fun selectSpace(spaceId: UUID) {
        currentSpaceId = spaceId
    }

    fun createSpace(
        name: String,
        iconName: String = "folder",
        storageMode: SpaceStorageMode = SpaceStorageMode.ARCA_SYNC
    ): SpaceMetadata {
        val trimmed = name.trim()
        val spaceName = if (trimmed.isEmpty()) "New Space" else trimmed
        val newSpace = SpaceMetadata(
            name = spaceName,
            iconName = iconName,
            accentHex = "#1F5673",
            storageMode = storageMode,
            acceptedCloudStorageTermsAt = if (storageMode == SpaceStorageMode.ARCA_SYNC) Instant.now() else null
        )
        spaces.add(newSpace)
        currentSpaceId = newSpace.id
        return newSpace
    }

    fun createSpace(name: String, storageMode: SpaceStorageMode): SpaceMetadata =
        createSpace(name = name, iconName = "folder", storageMode = storageMode)

    fun renameSpace(spaceId: UUID, newName: String) {
        val trimmed = newName.trim()
        if (trimmed.isEmpty()) return
        val idx = spaces.indexOfFirst { it.id == spaceId }
        if (idx >= 0) {
            spaces[idx] = spaces[idx].copy(name = trimmed, updatedAt = Instant.now())
        }
    }

    fun deleteSpace(spaceId: UUID) {
        if (spaces.size <= 1) return
        val idx = spaces.indexOfFirst { it.id == spaceId }
        if (idx >= 0) {
            spaces.removeAt(idx)
            collections.removeAll { it.spaceId == spaceId }
            records.removeAll { it.spaceId == spaceId }
            if (currentSpaceId == spaceId) {
                currentSpaceId = spaces.firstOrNull()?.id
            }
        }
    }

    fun toggleSpaceStorageMode(spaceId: UUID) {
        val idx = spaces.indexOfFirst { it.id == spaceId }
        if (idx >= 0) {
            val space = spaces[idx]
            val newMode = if (space.storageMode == SpaceStorageMode.ARCA_SYNC) {
                SpaceStorageMode.LOCAL_ONLY
            } else {
                SpaceStorageMode.ARCA_SYNC
            }
            spaces[idx] = space.copy(
                storageMode = newMode,
                userExplicitlyConfirmedSyncForSensitiveSpace = newMode == SpaceStorageMode.ARCA_SYNC,
                acceptedCloudStorageTermsAt = if (newMode == SpaceStorageMode.ARCA_SYNC) Instant.now() else space.acceptedCloudStorageTermsAt,
                updatedAt = Instant.now()
            )
        }
    }

    fun updateSpaceStorageMode(spaceId: UUID, mode: SpaceStorageMode, deleteRemoteVerified: Boolean = false) {
        val idx = spaces.indexOfFirst { it.id == spaceId }
        if (idx >= 0) {
            val space = spaces[idx]
            spaces[idx] = space.copy(
                storageMode = mode,
                userExplicitlyConfirmedSyncForSensitiveSpace = mode == SpaceStorageMode.ARCA_SYNC,
                acceptedCloudStorageTermsAt = if (mode == SpaceStorageMode.ARCA_SYNC) Instant.now() else space.acceptedCloudStorageTermsAt,
                updatedAt = Instant.now()
            )
        }
    }

    // MARK: - Collection Creation (3 Ways)

    fun addCollectionFromTemplate(template: StarterTemplate, inDedicatedLocalSpace: Boolean = false): CollectionSchema {
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
            currentSpace?.id ?: spaces.firstOrNull()?.id ?: createSpace("Personal & Home").id
        }
        val schema = template.instantiateSchema(targetSpaceId)
        collections.add(schema)
        return schema
    }

    fun createCustomCollection(
        name: String,
        iconName: String = "folder",
        colorHex: String = "#1F5673",
        fields: List<FieldDefinition>
    ): CollectionSchema {
        val spaceId = currentSpace?.id ?: spaces.firstOrNull()?.id ?: createSpace("Personal & Home").id
        val schema = CollectionSchema(
            id = UUID.randomUUID(),
            spaceId = spaceId,
            name = name.trim().ifBlank { "Custom Collection" },
            iconName = iconName,
            colorHex = colorHex,
            schemaVersion = 1,
            fields = fields
        )
        collections.add(schema)
        return schema
    }

    fun importCollectionSchemaFromJson(jsonString: String): Result<CollectionSchema> {
        val spaceId = currentSpace?.id ?: spaces.firstOrNull()?.id ?: createSpace("Personal & Home").id
        val result = SchemaEngine.parseAndValidateImportedSchemaJson(jsonString, spaceId)
        result.onSuccess { collections.add(it) }
        return result
    }

    // MARK: - Dynamic Field Evolution & Schema Mutation

    fun addField(
        collectionId: UUID,
        label: String,
        type: FieldType,
        isRequired: Boolean = false,
        options: List<SelectOption> = emptyList()
    ) {
        val idx = collections.indexOfFirst { it.id == collectionId }
        if (idx < 0) return
        val current = collections[idx]
        val trimmed = label.trim()
        if (trimmed.isEmpty()) return
        val newField = FieldDefinition(
            id = UUID.randomUUID(),
            label = trimmed,
            type = type,
            isRequired = isRequired,
            sortOrder = current.fields.size,
            options = options
        )
        collections[idx] = current.copy(
            schemaVersion = current.schemaVersion + 1,
            fields = current.fields + newField,
            updatedAt = Instant.now()
        )
    }

    fun renameField(collectionId: UUID, fieldId: UUID, newLabel: String) {
        val idx = collections.indexOfFirst { it.id == collectionId }
        if (idx >= 0) {
            collections[idx] = SchemaEngine.renameField(collections[idx], fieldId, newLabel)
        }
    }

    fun moveField(collectionId: UUID, fromIndex: Int, direction: Int) {
        val idx = collections.indexOfFirst { it.id == collectionId }
        if (idx < 0) return
        val schema = collections[idx]
        val active = schema.activeFields.toMutableList()
        val targetIndex = fromIndex + direction
        if (fromIndex in active.indices && targetIndex in active.indices) {
            val item = active.removeAt(fromIndex)
            active.add(targetIndex, item)
            val newOrder = active.map { it.id }
            collections[idx] = SchemaEngine.reorderFields(schema, newOrder)
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
            collections[idx] = schema.copy(fields = updated, schemaVersion = schema.schemaVersion + 1, updatedAt = Instant.now())
        } else {
            val updated = schema.fields.filterNot { it.id == fieldId }
            collections[idx] = schema.copy(fields = updated, schemaVersion = schema.schemaVersion + 1, updatedAt = Instant.now())
            // Purge values from existing records
            for (i in records.indices) {
                if (records[i].collectionId == collectionId && records[i].values.containsKey(fieldId)) {
                    val newValues = records[i].values.toMutableMap()
                    newValues.remove(fieldId)
                    records[i] = records[i].copy(values = newValues, revision = records[i].revision + 1, updatedAt = Instant.now())
                }
            }
        }
    }

    fun restoreArchivedField(collectionId: UUID, fieldId: UUID) {
        val idx = collections.indexOfFirst { it.id == collectionId }
        if (idx >= 0) {
            collections[idx] = SchemaEngine.restoreArchivedField(collections[idx], fieldId)
        }
    }

    fun previewFieldConversion(collectionId: UUID, field: FieldDefinition, targetType: FieldType) =
        SchemaEngine.previewFieldTypeConversion(field, targetType, recordsInCurrentSpace.filter { it.collectionId == collectionId })

    fun applyFieldConversion(collectionId: UUID, fieldId: UUID, targetType: FieldType): Result<Unit> {
        val idx = collections.indexOfFirst { it.id == collectionId }
        if (idx < 0) return Result.failure(NoSuchElementException("Collection not found"))
        val schema = collections[idx]
        return try {
            val (updatedSchema, updatedRecords) = SchemaEngine.applyFieldTypeConversion(
                schema = schema,
                fieldId = fieldId,
                targetType = targetType,
                records = records.filter { it.collectionId == collectionId }
            )
            collections[idx] = updatedSchema
            for (upRec in updatedRecords) {
                val rIdx = records.indexOfFirst { it.id == upRec.id }
                if (rIdx >= 0) {
                    records[rIdx] = upRec
                }
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    // MARK: - Record CRUD, Queries, Attachments & Search

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

    fun queryRecords(
        collectionId: UUID? = null,
        searchText: String = "",
        favoritesOnly: Boolean = false,
        hasAttachmentsOnly: Boolean = false,
        selectOptionFilter: Pair<UUID, String>? = null,
        sort: RecordSortCriterion = RecordSortCriterion.UPDATED_DESC
    ): List<RecordItem> {
        var base = recordsInCurrentSpace
        if (collectionId != null) {
            base = base.filter { it.collectionId == collectionId }
        }
        if (favoritesOnly) {
            base = base.filter { it.isFavorite }
        }
        if (hasAttachmentsOnly) {
            base = base.filter { it.allAttachments.isNotEmpty() }
        }
        if (selectOptionFilter != null) {
            val (fId, opt) = selectOptionFilter
            base = base.filter { rec ->
                when (val v = rec.values[fId]) {
                    is FieldValue.SingleSelect -> v.optionId == opt
                    is FieldValue.MultiSelect -> v.optionIds.contains(opt)
                    else -> false
                }
            }
        }
        val q = searchText.trim().lowercase(Locale.ROOT)
        if (q.isNotEmpty()) {
            base = base.filter { rec ->
                val schema = collections.firstOrNull { it.id == rec.collectionId }
                val titleMatch = schema?.let { rec.title(it).lowercase(Locale.ROOT).contains(q) } ?: false
                val valMatch = rec.values.values.any { it.plainTextSummary().lowercase(Locale.ROOT).contains(q) }
                titleMatch || valMatch
            }
        }
        return when (sort) {
            RecordSortCriterion.UPDATED_DESC -> base.sortedByDescending { it.updatedAt }
            RecordSortCriterion.UPDATED_ASC -> base.sortedBy { it.updatedAt }
            RecordSortCriterion.TITLE_ASC -> base.sortedBy { rec ->
                val schema = collections.firstOrNull { it.id == rec.collectionId }
                schema?.let { rec.title(it).lowercase(Locale.ROOT) } ?: ""
            }
            RecordSortCriterion.TITLE_DESC -> base.sortedByDescending { rec ->
                val schema = collections.firstOrNull { it.id == rec.collectionId }
                schema?.let { rec.title(it).lowercase(Locale.ROOT) } ?: ""
            }
        }
    }

    fun searchRecords(query: String): List<RecordItem> =
        queryRecords(searchText = query)

    fun attachSampleReceiptFile(): AttachmentReference {
        val randNum = (1000..9999).random()
        return AttachmentReference(
            id = UUID.randomUUID(),
            filename = "receipt-$randNum.pdf",
            mimeType = "application/pdf",
            byteSize = (75_000L..250_000L).random(),
            sha256Hex = UUID.randomUUID().toString().replace("-", "") + UUID.randomUUID().toString().replace("-", ""),
            relativeLocalPath = "attachments/receipt-$randNum.pdf",
            uploadState = AttachmentUploadState.LOCAL_ONLY
        )
    }

    // MARK: - Public Snapshots

    fun createPublicSnapshot(
        record: RecordItem,
        schema: CollectionSchema,
        selectedFieldIds: Set<UUID>
    ): PublicRecordSnapshot {
        val pairs = schema.activeFields
            .filter { selectedFieldIds.contains(it.id) }
            .map { field ->
                val summary = (record.values[field.id] ?: FieldValue.NullValue).plainTextSummary(field)
                Pair(field.label, summary)
            }
        val snapshot = PublicRecordSnapshot(
            sourceRecordId = record.id,
            title = record.title(schema),
            selectedFieldPairs = pairs
        )
        publicSnapshots.add(0, snapshot)
        return snapshot
    }

    fun revokePublicSnapshot(snapshotId: UUID) {
        val idx = publicSnapshots.indexOfFirst { it.id == snapshotId }
        if (idx >= 0) {
            publicSnapshots[idx] = publicSnapshots[idx].copy(isRevoked = true)
        }
    }

    // MARK: - Backups, Sync Conflicts & Device Limits

    fun exportCurrentSpaceBackup(encrypted: Boolean): String {
        val spaceName = (currentSpace?.name ?: "Space").replace(" ", "-").lowercase(Locale.ROOT)
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
        val dev = EnrolledDevice(
            deviceName = name.ifBlank { "Secondary Device" },
            platform = "android",
            userId = currentDevice.userId,
            isCurrentDevice = false
        )
        enrolledDevices.add(dev)
        return Result.success(dev)
    }

    fun revokeDevice(deviceId: UUID) {
        enrolledDevices.removeAll { it.deviceId == deviceId && !it.isCurrentDevice }
        currentSpace?.let { cur ->
            val idx = spaces.indexOfFirst { it.id == cur.id }
            if (idx >= 0) {
                spaces[idx] = cur.copy(currentEncryptionKeyVersion = cur.currentEncryptionKeyVersion + 1)
            }
        }
    }
}
