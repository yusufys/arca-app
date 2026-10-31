package app.arca.android

import app.arca.android.crypto.ArcaCryptoEngine
import app.arca.android.crypto.ArchivePathValidator
import app.arca.android.crypto.EncryptionContextAAD
import app.arca.android.crypto.RecoveryKeyCredential
import app.arca.android.model.FieldType
import app.arca.android.model.FieldValue
import app.arca.android.model.MoneyValue
import app.arca.android.model.PersonalCloudProvider
import app.arca.android.model.RecordItem
import app.arca.android.model.SchemaEngine
import app.arca.android.model.SpaceMetadata
import app.arca.android.model.SpaceStorageMode
import app.arca.android.model.StarterTemplateCatalog
import app.arca.android.sync.MergeOutcome
import app.arca.android.sync.PostExpiryPolicy
import app.arca.android.sync.ProviderPolicyAssessment
import app.arca.android.sync.SubscriptionTier
import app.arca.android.sync.SyncConflictEngine
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

        // Verify ARCAENC1 passphrase archive compatibility with iOS
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
            storageMode = SpaceStorageMode.LOCAL_ONLY,
            containsSensitiveHealthTemplate = true
        )
        val policy = ProviderPolicyAssessment.evaluate(PersonalCloudProvider.ICLOUD_DRIVE, sensitiveMedicalSpace)
        assertFalse(policy.isPermittedForBackup)
        assertFalse(policy.allowsSilentFallbackToArcaCloud)
    }

    @Test(expected = IllegalArgumentException::class)
    fun verifyPathTraversalRejected() {
        val tempRoot = File(System.getProperty("java.io.tmpdir"), "arca-stage-test")
        tempRoot.mkdirs()
        ArchivePathValidator.validateRelativePath("../escaped.txt", tempRoot)
    }
}
