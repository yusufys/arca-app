package app.arca.android.crypto

import app.arca.android.model.SpaceMetadata
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Instant
import java.util.Base64
import java.util.Locale
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

// MARK: - Provider-Independent Client-Side E2EE (AES-256-GCM + HKDF-SHA256)

data class EncryptionContextAAD(
    val spaceId: UUID,
    val entityId: UUID,
    val keyVersion: Int,
    val schemaVersion: Int
) {
    fun toCanonicalBytes(): ByteArray {
        val canonical = "arca-aad-v1|space:${spaceId.toString().lowercase(Locale.ROOT)}|entity:${entityId.toString().lowercase(Locale.ROOT)}|kv:$keyVersion|sv:$schemaVersion"
        return canonical.toByteArray(StandardCharsets.UTF_8)
    }
}

data class EncryptedEnvelope(
    val formatVersion: Int = 1,
    val keyVersion: Int,
    val nonceBase64: String,
    val ciphertextAndTagBase64: String,
    val aadSummary: String
)

/**
 * 256-bit Emergency Recovery Key distinct from account password recovery.
 * Uses the exact same 32-word dictionary and `ARCA-RK1:` format as the iOS client.
 */
data class RecoveryKeyCredential(
    val rawKeyBytes: ByteArray,
    val formattedPhrase: String
) {
    companion object {
        private val WORD_LIST = listOf(
            "amber", "anchor", "applet", "arcade", "aurora", "beacon", "breeze", "canyon",
            "cedar", "cobalt", "comet", "coral", "crystal", "cypress", "delta", "ember",
            "falcon", "fjord", "forest", "garnet", "glacier", "granite", "harbor", "horizon",
            "island", "jasper", "lantern", "meadow", "meteor", "mineral", "nebula", "onyx"
        )

        fun generate(masterKey: ByteArray): RecoveryKeyCredential {
            require(masterKey.size == 32) { "Master Account Key must be 256 bits (32 bytes)" }
            val words = masterKey.take(12).map { b ->
                WORD_LIST[(b.toInt() and 0xFF) % WORD_LIST.size]
            }
            val hexPayload = masterKey.joinToString("") { "%02x".format(it) }
            val phrase = "ARCA-RK1:${words.chunked(4).joinToString("-") { it.joinToString(".") }}:$hexPayload"
            return RecoveryKeyCredential(masterKey.copyOf(), phrase)
        }

        fun restoreMasterKey(fromPhrase: String): ByteArray {
            val trimmed = fromPhrase.trim()
            require(trimmed.startsWith("ARCA-RK1:")) { "Invalid Recovery Key header." }
            val parts = trimmed.split(":")
            require(parts.size == 3 && parts[2].length == 64) { "Invalid Recovery Key structure." }
            val hex = parts[2]
            val restored = ByteArray(32)
            for (i in 0 until 32) {
                val byteVal = hex.substring(i * 2, i * 2 + 2).toInt(16)
                restored[i] = byteVal.toByte()
            }
            val expectedWords = restored.take(12).map { b ->
                WORD_LIST[(b.toInt() and 0xFF) % WORD_LIST.size]
            }
            val expectedMnemonic = expectedWords.chunked(4).joinToString("-") { it.joinToString(".") }
            require(parts[1].lowercase(Locale.ROOT) == expectedMnemonic) {
                "Recovery Key mnemonic checksum mismatch."
            }
            return restored
        }
    }
}

object ArcaCryptoEngine {
    private val secureRandom = SecureRandom()
    private const val GCM_NONCE_BYTES = 12
    private const val GCM_TAG_BITS = 128

    fun generateMasterAccountKey(): ByteArray {
        val key = ByteArray(32)
        secureRandom.nextBytes(key)
        return key
    }

    /**
     * Derives a 256-bit Space Encryption Key (SEK) using HKDF-SHA256 (RFC 5869),
     * matching iOS `ClientCryptoEngine.deriveSpaceKey`.
     */
    fun deriveSpaceKey(masterKey: ByteArray, spaceId: UUID, keyVersion: Int): ByteArray {
        val info = "arca-sek-v1|${spaceId.toString().lowercase(Locale.ROOT)}|v$keyVersion".toByteArray(StandardCharsets.UTF_8)
        val salt = "arca-hkdf-salt-v1".toByteArray(StandardCharsets.UTF_8)
        return hkdfSha256(ikm = masterKey, salt = salt, info = info, outputLength = 32)
    }

    fun encrypt(plaintext: ByteArray, spaceKey: ByteArray, aad: EncryptionContextAAD): EncryptedEnvelope {
        val nonce = ByteArray(GCM_NONCE_BYTES)
        secureRandom.nextBytes(nonce)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(GCM_TAG_BITS, nonce)
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(spaceKey, "AES"), spec)
        cipher.updateAAD(aad.toCanonicalBytes())
        val cipherAndTag = cipher.doFinal(plaintext)
        return EncryptedEnvelope(
            formatVersion = 1,
            keyVersion = aad.keyVersion,
            nonceBase64 = Base64.getEncoder().encodeToString(nonce),
            ciphertextAndTagBase64 = Base64.getEncoder().encodeToString(cipherAndTag),
            aadSummary = "kv:${aad.keyVersion}|sv:${aad.schemaVersion}"
        )
    }

    fun decrypt(envelope: EncryptedEnvelope, spaceKey: ByteArray, expectedAAD: EncryptionContextAAD): ByteArray {
        require(envelope.keyVersion == expectedAAD.keyVersion) {
            "Key version mismatch: envelope v${envelope.keyVersion} vs expected v${expectedAAD.keyVersion}"
        }
        val nonce = Base64.getDecoder().decode(envelope.nonceBase64)
        val cipherAndTag = Base64.getDecoder().decode(envelope.ciphertextAndTagBase64)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(GCM_TAG_BITS, nonce)
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(spaceKey, "AES"), spec)
        cipher.updateAAD(expectedAAD.toCanonicalBytes())
        return cipher.doFinal(cipherAndTag)
    }

    /**
     * Encrypts a portable archive payload with a user passphrase using `ARCAENC1` magic header +
     * 16-byte salt + 12-byte nonce + AES-256-GCM ciphertext+tag (PBKDF2-HMAC-SHA256, 100,000 iterations).
     */
    fun encryptArchiveWithPassphrase(plainArchiveBytes: ByteArray, passphrase: String): ByteArray {
        val salt = ByteArray(16).also { secureRandom.nextBytes(it) }
        val nonce = ByteArray(GCM_NONCE_BYTES).also { secureRandom.nextBytes(it) }
        val derivedKey = deriveKeyFromPassphrase(passphrase, salt)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(derivedKey, "AES"), GCMParameterSpec(GCM_TAG_BITS, nonce))
        val header = "ARCAENC1".toByteArray(StandardCharsets.UTF_8)
        cipher.updateAAD(header)
        val ciphertext = cipher.doFinal(plainArchiveBytes)

        val buffer = ByteBuffer.allocate(header.size + salt.size + nonce.size + ciphertext.size)
        buffer.put(header)
        buffer.put(salt)
        buffer.put(nonce)
        buffer.put(ciphertext)
        return buffer.array()
    }

    fun decryptArchiveWithPassphrase(encryptedBytes: ByteArray, passphrase: String): ByteArray {
        val header = "ARCAENC1".toByteArray(StandardCharsets.UTF_8)
        require(encryptedBytes.size > header.size + 16 + GCM_NONCE_BYTES + 16) {
            "Archive is truncated or invalid."
        }
        val actualHeader = encryptedBytes.copyOfRange(0, header.size)
        require(actualHeader.contentEquals(header)) { "Missing ARCAENC1 header." }

        val salt = encryptedBytes.copyOfRange(header.size, header.size + 16)
        val nonce = encryptedBytes.copyOfRange(header.size + 16, header.size + 16 + GCM_NONCE_BYTES)
        val ciphertext = encryptedBytes.copyOfRange(header.size + 16 + GCM_NONCE_BYTES, encryptedBytes.size)

        val derivedKey = deriveKeyFromPassphrase(passphrase, salt)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(derivedKey, "AES"), GCMParameterSpec(GCM_TAG_BITS, nonce))
        cipher.updateAAD(header)
        return cipher.doFinal(ciphertext)
    }

    fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun deriveKeyFromPassphrase(passphrase: String, salt: ByteArray): ByteArray {
        val spec = PBEKeySpec(passphrase.toCharArray(), salt, 100_000, 256)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        return factory.generateSecret(spec).encoded
    }

    private fun hkdfSha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, outputLength: Int): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(salt, "HmacSHA256"))
        val prk = mac.doFinal(ikm)

        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        mac.update(info)
        mac.update(0x01.toByte())
        return mac.doFinal().copyOf(outputLength)
    }
}

// MARK: - Portable `.arcaarchive` Path Safety & Manifest Verification (Cross-Platform with iOS)

data class ArchiveManifest(
    val formatVersion: String = "1.0",
    val archiveId: UUID = UUID.randomUUID(),
    val exportedAtEpochSeconds: Long = Instant.now().epochSecond,
    val spaceMetadata: SpaceMetadata,
    val collectionCount: Int,
    val recordCount: Int,
    val attachmentDigests: Map<String, String>,
    val collectionsSha256Hex: String,
    val recordsSha256Hex: String,
    val manifestIntegritySha256Hex: String = ""
) {
    fun computeCanonicalIntegrityDigest(): String {
        val sortedAttachments = attachmentDigests.entries
            .sortedBy { it.key }
            .joinToString(";") { "${it.key}=${it.value.lowercase(Locale.ROOT)}" }

        val canonical = listOf(
            "v:$formatVersion",
            "archive:${archiveId.toString().lowercase(Locale.ROOT)}",
            "exported:$exportedAtEpochSeconds",
            "space:${spaceMetadata.id.toString().lowercase(Locale.ROOT)}",
            "collectionsCount:$collectionCount",
            "recordsCount:$recordCount",
            "collectionsSha:${collectionsSha256Hex.lowercase(Locale.ROOT)}",
            "recordsSha:${recordsSha256Hex.lowercase(Locale.ROOT)}",
            "attachments:[$sortedAttachments]"
        ).joinToString("|")

        return ArcaCryptoEngine.sha256Hex(canonical.toByteArray(StandardCharsets.UTF_8))
    }
}

object ArchivePathValidator {
    fun validateRelativePath(relativePath: String, stagingRoot: File) {
        val trimmed = relativePath.trim()
        require(trimmed.isNotEmpty()) { "Empty path in archive." }
        require(!trimmed.startsWith("/") && !trimmed.startsWith("~")) {
            "Absolute or home-relative path prohibited in archive."
        }
        require(!trimmed.contains("\\") && !trimmed.contains("\u0000")) {
            "Unsafe characters in archive path."
        }
        val segments = trimmed.split("/")
        for (seg in segments) {
            require(seg.isNotEmpty() && seg != "." && seg != "..") {
                "Path traversal segment '$seg' prohibited."
            }
        }
        val canonicalRoot = stagingRoot.canonicalPath + File.separator
        val candidate = File(stagingRoot, trimmed)
        require(!Files.isSymbolicLink(candidate.toPath())) {
            "Symbolic links are prohibited in portable archives."
        }
        require(candidate.canonicalPath.startsWith(canonicalRoot)) {
            "Resolved path escapes staging directory."
        }
    }
}
