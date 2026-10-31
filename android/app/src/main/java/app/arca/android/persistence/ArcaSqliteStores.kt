package app.arca.android.persistence

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import app.arca.android.model.CalendarDate
import app.arca.android.model.CollectionSchema
import app.arca.android.model.FieldDefinition
import app.arca.android.model.FieldType
import app.arca.android.model.FieldValue
import app.arca.android.model.MoneyValue
import app.arca.android.model.RecordItem
import app.arca.android.model.SpaceMetadata
import app.arca.android.model.SpaceStorageMode
import java.io.File
import java.time.Instant
import java.util.UUID

/**
 * Per-Space isolated SQLite database (`spaces/<spaceId>/space.sqlite`) and lightweight `catalog.sqlite`.
 * Matches the iOS `CatalogStore` and `SpaceStore` relational + projection + FTS schema.
 */
class AndroidCatalogStore(rootDir: File) {
    private val dbFile: File
    private val db: SQLiteDatabase

    init {
        rootDir.mkdirs()
        dbFile = File(rootDir, "catalog.sqlite")
        db = SQLiteDatabase.openOrCreateDatabase(dbFile, null)
        db.enableWriteAheadLogging()
        createTables()
    }

    private fun createTables() {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS spaces (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                icon_name TEXT NOT NULL,
                accent_hex TEXT NOT NULL,
                storage_mode TEXT NOT NULL,
                key_version INTEGER NOT NULL DEFAULT 1,
                contains_sensitive_health INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """.trimIndent()
        )
    }

    fun upsertSpace(space: SpaceMetadata) {
        val cv = ContentValues().apply {
            put("id", space.id.toString())
            put("name", space.name)
            put("icon_name", space.iconName)
            put("accent_hex", space.accentHex)
            put("storage_mode", space.storageMode.wireValue)
            put("key_version", space.currentEncryptionKeyVersion)
            put("contains_sensitive_health", if (space.containsSensitiveHealthTemplate) 1 else 0)
            put("created_at", space.createdAt.epochSecond)
            put("updated_at", space.updatedAt.epochSecond)
        }
        db.insertWithOnConflict("spaces", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    fun listSpaces(): List<SpaceMetadata> {
        val result = mutableListOf<SpaceMetadata>()
        db.rawQuery(
            "SELECT id, name, icon_name, accent_hex, storage_mode, key_version, contains_sensitive_health, created_at, updated_at FROM spaces ORDER BY created_at ASC",
            null
        ).use { cursor ->
            while (cursor.moveToNext()) {
                result.add(
                    SpaceMetadata(
                        id = UUID.fromString(cursor.getString(0)),
                        name = cursor.getString(1),
                        iconName = cursor.getString(2),
                        accentHex = cursor.getString(3),
                        storageMode = SpaceStorageMode.fromWire(cursor.getString(4)),
                        currentEncryptionKeyVersion = cursor.getInt(5),
                        containsSensitiveHealthTemplate = cursor.getInt(6) != 0,
                        createdAt = Instant.ofEpochSecond(cursor.getLong(7)),
                        updatedAt = Instant.ofEpochSecond(cursor.getLong(8))
                    )
                )
            }
        }
        return result
    }

    fun deleteSpace(spaceId: UUID) {
        db.delete("spaces", "id = ?", arrayOf(spaceId.toString()))
    }
}

class AndroidSpaceStore(spaceRootDir: File, val spaceId: UUID) {
    val dbFile: File
    val attachmentsDir: File
    private val db: SQLiteDatabase

    init {
        spaceRootDir.mkdirs()
        attachmentsDir = File(spaceRootDir, "attachments").also { it.mkdirs() }
        dbFile = File(spaceRootDir, "space.sqlite")
        db = SQLiteDatabase.openOrCreateDatabase(dbFile, null)
        db.enableWriteAheadLogging()
        createTables()
    }

    private fun createTables() {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS record_field_projections (
                record_id TEXT NOT NULL,
                collection_id TEXT NOT NULL,
                field_id TEXT NOT NULL,
                text_value TEXT,
                number_value REAL,
                date_iso TEXT,
                PRIMARY KEY (record_id, field_id)
            );
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_proj_text ON record_field_projections(field_id, text_value);")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_proj_num ON record_field_projections(field_id, number_value);")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_proj_date ON record_field_projections(field_id, date_iso);")

        // Full-text search virtual table
        db.execSQL(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS records_fts USING fts4(
                record_id,
                collection_id,
                title,
                body_text
            );
            """.trimIndent()
        )
    }

    fun indexRecordProjections(record: RecordItem, schema: CollectionSchema) {
        db.beginTransaction()
        try {
            db.delete("record_field_projections", "record_id = ?", arrayOf(record.id.toString()))
            db.delete("records_fts", "record_id = ?", arrayOf(record.id.toString()))

            if (record.deletedAt == null) {
                val ftsTokens = mutableListOf<String>()
                for ((fieldId, value) in record.values) {
                    val cv = ContentValues().apply {
                        put("record_id", record.id.toString())
                        put("collection_id", record.collectionId.toString())
                        put("field_id", fieldId.toString())
                    }
                    when (value) {
                        is FieldValue.ShortText -> {
                            cv.put("text_value", value.value)
                            ftsTokens.add(value.value)
                        }
                        is FieldValue.LongText -> {
                            cv.put("text_value", value.value)
                            ftsTokens.add(value.value)
                        }
                        is FieldValue.NumberValue -> cv.put("number_value", value.value)
                        is FieldValue.CurrencyValue -> cv.put("number_value", value.value.decimalValue.toDouble())
                        is FieldValue.DateValue -> cv.put("date_iso", value.value.isoString)
                        is FieldValue.SingleSelect -> cv.put("text_value", value.optionId)
                        else -> {}
                    }
                    db.insertWithOnConflict("record_field_projections", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
                }

                val ftsCv = ContentValues().apply {
                    put("record_id", record.id.toString())
                    put("collection_id", record.collectionId.toString())
                    put("title", record.title(schema))
                    put("body_text", ftsTokens.joinToString(" "))
                }
                db.insert("records_fts", null, ftsCv)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun searchRecordIdsFts(query: String): Set<UUID> {
        val sanitized = query.trim().replace("\"", "")
        if (sanitized.isEmpty()) return emptySet()
        val ids = mutableSetOf<UUID>()
        db.rawQuery(
            "SELECT record_id FROM records_fts WHERE records_fts MATCH ?",
            arrayOf("$sanitized*")
        ).use { cursor ->
            while (cursor.moveToNext()) {
                runCatching { UUID.fromString(cursor.getString(0)) }.getOrNull()?.let { ids.add(it) }
            }
        }
        return ids
    }
}
