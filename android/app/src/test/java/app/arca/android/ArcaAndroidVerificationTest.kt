package app.arca.android

import app.arca.android.crypto.ArcaCryptoEngine
import app.arca.android.crypto.ArchivePathValidator
import app.arca.android.crypto.EncryptionContextAAD
import app.arca.android.crypto.RecoveryKeyCredential
import app.arca.android.model.CalendarDate
import app.arca.android.model.CollectionSchema
import app.arca.android.model.FieldDefinition
import app.arca.android.model.FieldDeletionRetentionPolicy
import app.arca.android.model.FieldType
import app.arca.android.model.FieldValue
import app.arca.android.model.MoneyValue
import app.arca.android.model.PersonalCloudProvider
import app.arca.android.model.RecordItem
import app.arca.android.model.RecordSortCriterion
import app.arca.android.model.SchemaEngine
import app.arca.android.model.SelectOption
import app.arca.android.model.SpaceInsightsReport
import app.arca.android.model.SpaceMetadata
import app.arca.android.model.SpaceStorageMode
import app.arca.android.model.StarterTemplateCatalog
import app.arca.android.sync.MergeOutcome
import app.arca.android.sync.PostExpiryPolicy
import app.arca.android.sync.ProviderPolicyAssessment
import app.arca.android.sync.SubscriptionTier
import app.arca.android.sync.SyncConflictEngine
import app.arca.android.ui.ArcaViewModel
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.charset.StandardCharsets
import java.util.UUID

class ArcaAndroidVerificationTest {

    @Test
    fun verifySchemaRenameAndConversionPreview() {
        val spaceId = UUID.randomUUID()
        val schema = StarterTemplateCatalog.vehicleMaintenance.instantiateSchema(spaceId)
        val odometerField = schema.fields[2]
        val renamed = SchemaEngine.renameField(schema, odometerField.id, "Mileage (km)")
        assertEquals(odometerField.id, renamed.fields[2].id)
        assertEquals("Mileage (km)", renamed.fields[2].label)

        val record = RecordItem(
            spaceId = spaceId,
            collectionId = schema.id,
            values = mapOf(odometerField.id to FieldValue.NumberValue(42000.0))
        )
        val preview = SchemaEngine.previewFieldConversion(odometerField, FieldType.SHORT_TEXT, listOf(record))
        assertTrue(preview.isSafeToApplyWithoutLoss)
    }

    @Test
    fun verifyE2EEAndRecoveryKeyAndPassphraseArchive() {
        val mak = ArcaCryptoEngine.generateMasterAccountKey()
        val rk = RecoveryKeyCredential.generate(mak)
        val restoredMak = RecoveryKeyCredential.restoreMasterKey(rk.formattedPhrase)
        assertArrayEquals(mak, restoredMak)

        val spaceId = UUID.randomUUID()
        val recordId = UUID.randomUUID()
        val sek = ArcaCryptoEngine.deriveSpaceKey(mak, spaceId, keyVersion = 1)
        val aad = EncryptionContextAAD(spaceId = spaceId, entityId = recordId, keyVersion = 1, schemaVersion = 1)
        val plaintext = "{\"title\":\"Brake Pad Replacement\"}".toByteArray(StandardCharsets.UTF_8)
        val env = ArcaCryptoEngine.encrypt(plaintext, sek, aad)
        val decrypted = ArcaCryptoEngine.decrypt(env, sek, aad)
        assertArrayEquals(plaintext, decrypted)

        val archivePayload = "{\"formatVersion\":\"1.0\"}".toByteArray(StandardCharsets.UTF_8)
        val encryptedArchive = ArcaCryptoEngine.encryptArchiveWithPassphrase(archivePayload, "correct-horse-battery")
        val decryptedArchive = ArcaCryptoEngine.decryptArchiveWithPassphrase(encryptedArchive, "correct-horse-battery")
        assertArrayEquals(archivePayload, decryptedArchive)
    }

    @Test
    fun verifyConcurrentConflictPreservationAndPostExpirySafeguards() {
        val spaceId = UUID.randomUUID()
        val colId = UUID.randomUUID()
        val fieldA = UUID.randomUUID()
        val base = RecordItem(spaceId = spaceId, collectionId = colId, values = mapOf(fieldA to FieldValue.ShortText("Original")))
        val local = base.copy(values = mapOf(fieldA to FieldValue.ShortText("Local Edit")), revision = 2)
        val remote = base.copy(values = mapOf(fieldA to FieldValue.ShortText("Remote Edit")), revision = 2)

        val outcome = SyncConflictEngine.mergeConcurrentEdits(base, local, remote)
        assertTrue(outcome is MergeOutcome.ConflictPreserved)

        val expiryPolicy = PostExpiryPolicy.evaluate(
            tier = SubscriptionTier.FREE,
            activeDeviceCount = 3,
            remoteStorageBytesUsed = 400L * 1024L * 1024L
        )
        assertTrue(expiryPolicy.allowsLocalReadWriteCRUD)
        assertTrue(expiryPolicy.allowsManualPortableExportAndRestore)
        assertFalse(expiryPolicy.deletesLocalRecordsOnExpiry)
        assertFalse(expiryPolicy.isSyncPushAllowed)

        val sensitiveMedicalSpace = SpaceMetadata(
            name = "Medical Visits",
            containsSensitiveHealthTemplate = true
        )
        assertEquals(SpaceStorageMode.LOCAL_ONLY, sensitiveMedicalSpace.resolvedStorageMode)
        val policy = ProviderPolicyAssessment.evaluate(PersonalCloudProvider.ICLOUD_DRIVE, sensitiveMedicalSpace)
        assertFalse(policy.isPermittedForBackup)
        assertFalse(policy.allowsSilentFallbackToArcaCloud)
    }

    @Test
    fun verifySpaceStorageModeDefaultsAndSwitching() {
        val regularSpace = SpaceMetadata(name = "Personal Projects")
        assertEquals(SpaceStorageMode.ARCA_SYNC, regularSpace.storageMode)
        assertEquals(SpaceStorageMode.ARCA_SYNC, regularSpace.resolvedStorageMode)

        val sensitiveMedicalSpace = SpaceMetadata(
            name = "Medical Visits",
            containsSensitiveHealthTemplate = true
        )
        assertEquals(SpaceStorageMode.LOCAL_ONLY, sensitiveMedicalSpace.resolvedStorageMode)

        val confirmedSensitiveSpace = SpaceMetadata(
            name = "Confirmed Medical",
            storageMode = SpaceStorageMode.ARCA_SYNC,
            containsSensitiveHealthTemplate = true,
            userExplicitlyConfirmedSyncForSensitiveSpace = true
        )
        assertEquals(SpaceStorageMode.ARCA_SYNC, confirmedSensitiveSpace.resolvedStorageMode)

        val switchedLocalSpace = regularSpace.copy(storageMode = SpaceStorageMode.LOCAL_ONLY)
        assertEquals(SpaceStorageMode.LOCAL_ONLY, switchedLocalSpace.storageMode)
        assertEquals(SpaceStorageMode.LOCAL_ONLY, switchedLocalSpace.resolvedStorageMode)

        val vm = ArcaViewModel(startWithCompletedOnboarding = true)
        val initialDefaultSpace = vm.currentSpace
        assertEquals(SpaceStorageMode.ARCA_SYNC, initialDefaultSpace?.storageMode)

        vm.createSpace(name = "Workshop", iconName = "build")
        val createdSpace = vm.spaces.first { it.name == "Workshop" }
        assertEquals(SpaceStorageMode.ARCA_SYNC, createdSpace.storageMode)

        vm.createSpace(name = "Private Vault", iconName = "lock", storageMode = SpaceStorageMode.LOCAL_ONLY)
        val privateSpace = vm.spaces.first { it.name == "Private Vault" }
        assertEquals(SpaceStorageMode.LOCAL_ONLY, privateSpace.storageMode)

        vm.toggleSpaceStorageMode(createdSpace.id)
        val toggledSpace = vm.spaces.first { it.id == createdSpace.id }
        assertEquals(SpaceStorageMode.LOCAL_ONLY, toggledSpace.storageMode)
    }

    @Test
    fun verifyCollectionCreationAndFieldLifecycleParity() {
        val vm = ArcaViewModel(startWithCompletedOnboarding = true)

        // 1. Add from template (Subscriptions & Renewals)
        val subSchema = vm.addCollectionFromTemplate(StarterTemplateCatalog.subscriptions)
        assertNotNull(subSchema)
        assertEquals("Subscriptions & Renewals", subSchema.name)
        assertTrue(vm.collections.any { it.id == subSchema.id })

        // 2. Add Documents & IDs template
        val docSchema = vm.addCollectionFromTemplate(StarterTemplateCatalog.documents)
        assertNotNull(docSchema)
        assertEquals("Documents & IDs", docSchema.name)

        // 3. Create Custom Collection with custom fields
        val customFields = listOf(
            FieldDefinition(label = "Game Title", type = FieldType.SHORT_TEXT, isRequired = true, sortOrder = 0, isPrimaryTitle = true),
            FieldDefinition(label = "Player Count", type = FieldType.NUMBER, isRequired = false, sortOrder = 1),
            FieldDefinition(label = "Complexity Rating", type = FieldType.RATING, isRequired = false, sortOrder = 2)
        )
        val customCol = vm.createCustomCollection(
            name = "Board Game Library",
            iconName = "extension",
            colorHex = "#3A6B5C",
            fields = customFields
        )
        assertEquals("Board Game Library", customCol.name)
        assertEquals(3, customCol.fields.size)
        assertTrue(vm.collections.any { it.id == customCol.id })

        // 4. Add field to collection
        vm.addField(
            collectionId = customCol.id,
            label = "Expansion Pack Included",
            type = FieldType.BOOLEAN,
            isRequired = false
        )
        val afterAddCol = vm.collections.first { it.id == customCol.id }
        assertEquals(4, afterAddCol.fields.size)
        val addedField = afterAddCol.fields.first { it.label == "Expansion Pack Included" }
        assertEquals(FieldType.BOOLEAN, addedField.type)

        // 5. Rename field
        vm.renameField(customCol.id, addedField.id, "Has Expansions")
        val afterRenameCol = vm.collections.first { it.id == customCol.id }
        val renamedField = afterRenameCol.fields.first { it.id == addedField.id }
        assertEquals("Has Expansions", renamedField.label)

        // 6. Reorder / Move field
        val initialOrder = afterRenameCol.activeFields.map { it.label }
        vm.moveField(customCol.id, fromIndex = 3, direction = -1)
        val afterMoveCol = vm.collections.first { it.id == customCol.id }
        assertEquals("Has Expansions", afterMoveCol.activeFields[2].label)

        // 7. Field conversion preview & apply
        val playerCountField = afterMoveCol.fields.first { it.label == "Player Count" }
        // Seed record with a player count number
        val sampleRecord = RecordItem(
            spaceId = vm.currentSpace!!.id,
            collectionId = customCol.id,
            values = mapOf(
                customCol.fields[0].id to FieldValue.ShortText("Catan"),
                playerCountField.id to FieldValue.NumberValue(4.0)
            )
        )
        vm.records.add(sampleRecord)

        val preview = vm.previewFieldConversion(customCol.id, playerCountField, FieldType.SHORT_TEXT)
        assertTrue(preview.isSafeToApplyWithoutLoss)
        assertEquals(1, preview.successCount)
        assertEquals(0, preview.failureCount)

        val applyResult = vm.applyFieldConversion(customCol.id, playerCountField.id, FieldType.SHORT_TEXT)
        assertTrue(applyResult.isSuccess)
        val afterConvertCol = vm.collections.first { it.id == customCol.id }
        assertEquals(FieldType.SHORT_TEXT, afterConvertCol.fields.first { it.id == playerCountField.id }.type)
        val convertedRecord = vm.records.first { it.id == sampleRecord.id }
        assertTrue(convertedRecord.values[playerCountField.id] is FieldValue.ShortText)

        // 8. Archive field (keep values)
        vm.archiveOrRemoveField(customCol.id, playerCountField.id, FieldDeletionRetentionPolicy.ARCHIVE_AND_RETAIN_VALUES)
        val afterArchiveCol = vm.collections.first { it.id == customCol.id }
        assertTrue(afterArchiveCol.archivedFields.any { it.id == playerCountField.id })
        assertFalse(afterArchiveCol.activeFields.any { it.id == playerCountField.id })

        // 9. Restore archived field
        vm.restoreArchivedField(customCol.id, playerCountField.id)
        val afterRestoreCol = vm.collections.first { it.id == customCol.id }
        assertTrue(afterRestoreCol.activeFields.any { it.id == playerCountField.id })
        assertFalse(afterRestoreCol.archivedFields.any { it.id == playerCountField.id })
    }

    @Test
    fun verifyPreLoginDeviceTokenAndUserAssociation() {
        val vm = ArcaViewModel(startWithCompletedOnboarding = true)

        // Pre-login state: currentDevice has persistent ID and token, userId is null
        assertNotNull(vm.currentDevice)
        assertNull(vm.currentDevice.userId)
        assertTrue(vm.currentDevice.deviceToken.startsWith("arca_android_tok_"))
        assertEquals("android", vm.currentDevice.platform)
        assertTrue(vm.currentDevice.isCurrentDevice)
        assertNull(vm.cloudAccountSession)

        // Device is registered in enrolledDevices
        assertTrue(vm.enrolledDevices.any { it.deviceId == vm.currentDevice.deviceId })

        // Login / Register cloud account
        val loginResult = vm.loginOrRegisterCloudAccount(
            name = "Alex Mercer",
            email = "alex@arca.example",
            password = "test-secure-password-123",
            isRegistration = true
        )
        assertTrue(loginResult.isSuccess)

        // Verify device token association with user_id
        val session = vm.cloudAccountSession
        assertNotNull(session)
        assertEquals("alex@arca.example", session?.email)
        assertNotNull(session?.userId)
        assertEquals(session?.userId, vm.currentDevice.userId)
        assertEquals(vm.currentDevice.deviceId, session?.associatedDeviceId)
        assertEquals(vm.currentDevice.deviceToken, session?.associatedDeviceToken)

        // Enrolled devices list reflects user association
        val enrolledCurrent = vm.enrolledDevices.first { it.deviceId == vm.currentDevice.deviceId }
        assertEquals(session?.userId, enrolledCurrent.userId)

        // Logout clears cloudAccountSession and resets userId to null, keeping deviceToken stable
        val originalToken = vm.currentDevice.deviceToken
        vm.logoutCloudAccount()
        assertNull(vm.cloudAccountSession)
        assertNull(vm.currentDevice.userId)
        assertEquals(originalToken, vm.currentDevice.deviceToken)
        assertNull(vm.enrolledDevices.first { it.deviceId == vm.currentDevice.deviceId }.userId)
    }

    @Test
    fun verifyPublicRecordSnapshotCreationAndRevocation() {
        val vm = ArcaViewModel(startWithCompletedOnboarding = true)
        val spaceId = vm.currentSpace!!.id
        val warrantySchema = vm.collections.first { it.name == "Warranties & Serials" }
        val sampleRecord = vm.recordsInCurrentSpace.first { it.collectionId == warrantySchema.id }

        val selectedFields = warrantySchema.activeFields.take(3).map { it.id }.toSet()
        val snapshot = vm.createPublicSnapshot(sampleRecord, warrantySchema, selectedFields)

        assertNotNull(snapshot)
        assertEquals(sampleRecord.id, snapshot.sourceRecordId)
        assertTrue(snapshot.shareToken.startsWith("snap-"))
        assertEquals(3, snapshot.selectedFieldPairs.size)
        assertFalse(snapshot.isRevoked)
        assertTrue(vm.publicSnapshots.any { it.id == snapshot.id })

        // Revoke snapshot
        vm.revokePublicSnapshot(snapshot.id)
        val revoked = vm.publicSnapshots.first { it.id == snapshot.id }
        assertTrue(revoked.isRevoked)
    }

    @Test
    fun verifyRecordQueryFilteringAndSorting() {
        val vm = ArcaViewModel(startWithCompletedOnboarding = true)
        val allRecords = vm.recordsInCurrentSpace
        assertTrue(allRecords.isNotEmpty())

        // 1. Favorites only
        val favs = vm.queryRecords(favoritesOnly = true)
        assertTrue(favs.all { it.isFavorite })

        // 2. Attachments only
        val withFiles = vm.queryRecords(hasAttachmentsOnly = true)
        assertTrue(withFiles.all { it.allAttachments.isNotEmpty() })

        // 3. Search text
        val searched = vm.queryRecords(searchText = "Espresso")
        assertTrue(searched.isNotEmpty())

        // 4. Sorting
        val sortedAsc = vm.queryRecords(sort = RecordSortCriterion.TITLE_ASC)
        val sortedDesc = vm.queryRecords(sort = RecordSortCriterion.TITLE_DESC)
        assertEquals(allRecords.size, sortedAsc.size)
        assertEquals(allRecords.size, sortedDesc.size)
    }

    @Test
    fun verifyDynamicSpaceInsightsEngine() {
        val vm = ArcaViewModel(startWithCompletedOnboarding = true)
        val report = vm.currentSpaceInsights

        assertNotNull(report)
        assertTrue(report.totalRecords > 0)
        assertTrue(report.favoriteRecords >= 0)

        // Check numeric summaries (home inventory has currency, warranties has date)
        val currencySummary = report.numericSummaries.firstOrNull { it.isCurrency }
        assertNotNull(currencySummary)
        assertTrue(currencySummary!!.sum > 0.0)

        // Check upcoming expirations (from warranties date field)
        assertTrue(report.upcomingExpirations.isNotEmpty())
        val firstExp = report.upcomingExpirations.first()
        assertNotNull(firstExp.expirationDate)

        // Check select distributions
        assertTrue(report.selectDistributions.isNotEmpty())
    }

    @Test
    fun verifySchemaEngineJsonImportAndPrompt() {
        val prompt = SchemaEngine.chatGptSchemaPrompt("Drone Inventory")
        assertTrue(prompt.contains("Drone Inventory"))
        assertTrue(prompt.contains("short_text"))

        val validJson = """
        {
          "name": "Drone Gear",
          "iconName": "flight",
          "colorHex": "#2B5B84",
          "fields": [
            {
              "label": "Drone Model",
              "type": "short_text",
              "isRequired": true,
              "isPrimaryTitle": true
            },
            {
              "label": "Battery Cycles",
              "type": "number",
              "isRequired": false
            },
            {
              "label": "Category",
              "type": "single_select",
              "options": ["FPV", "Cinema", "Inspection"]
            }
          ]
        }
        """.trimIndent()

        val spaceId = UUID.randomUUID()
        val parseResult = SchemaEngine.parseAndValidateImportedSchemaJson(validJson, spaceId)
        assertTrue(parseResult.isSuccess)

        val schema = parseResult.getOrThrow()
        assertEquals("Drone Gear", schema.name)
        assertEquals(3, schema.fields.size)
        assertEquals(FieldType.SINGLE_SELECT, schema.fields[2].type)
        assertEquals(3, schema.fields[2].options.size)

        // Rejects invalid JSON
        val invalidResult = SchemaEngine.parseAndValidateImportedSchemaJson("not json", spaceId)
        assertTrue(invalidResult.isFailure)

        // Rejects missing name
        val noNameResult = SchemaEngine.parseAndValidateImportedSchemaJson("""{"fields":[]}""", spaceId)
        assertTrue(noNameResult.isFailure)
    }

    @Test
    fun verifyAppAnnouncementBannerAndLaravelHttpConfigDefaults() {
        val banner = app.arca.android.model.AppAnnouncementBanner(
            id = "ann-1",
            title = "Welcome to Arca Sync",
            body = "End-to-end encrypted cloud sync is now default."
        )
        assertEquals("home_banner", banner.placement)
        assertEquals("android", banner.targetPlatform)
        assertEquals("all", banner.targetTier)

        val config = app.arca.android.sync.LaravelHttpConfig()
        assertEquals("http://10.0.2.2:8000", config.baseUrl)
        assertEquals(null, config.apiToken)
        assertEquals(SpaceStorageMode.ARCA_SYNC, config.defaultStorageMode)
    }

    @Test(expected = IllegalArgumentException::class)
    fun verifyPathTraversalRejected() {
        val tempRoot = File(System.getProperty("java.io.tmpdir"), "arca-stage-test")
        tempRoot.mkdirs()
        ArchivePathValidator.validateRelativePath("../escaped.txt", tempRoot)
    }
}
