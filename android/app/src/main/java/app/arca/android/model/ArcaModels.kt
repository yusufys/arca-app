package app.arca.android.model

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Currency
import java.util.Locale
import java.util.UUID

// MARK: - Storage & Privacy Modes

enum class SpaceStorageMode(val wireValue: String, val displayTitle: String) {
    LOCAL_ONLY("local_only", "On This Device Only"),
    ARCA_SYNC("arca_sync", "Arca Sync (E2EE)"),
    PERSONAL_CLOUD_BACKUP("personal_cloud_backup", "Personal Cloud Backup (Pro)");

    companion object {
        fun fromWire(value: String): SpaceStorageMode =
            entries.firstOrNull { it.wireValue == value } ?: LOCAL_ONLY
    }
}

enum class PersonalCloudProvider(val wireValue: String, val displayName: String) {
    GOOGLE_DRIVE("google_drive", "Google Drive"),
    ICLOUD_DRIVE("icloud_drive", "iCloud Drive")
}

// MARK: - Space Metadata (Hierarchy Level 1: Database / "Space")

data class SpaceMetadata(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val iconName: String = "folder",
    val accentHex: String = "#1F5673",
    val storageMode: SpaceStorageMode = SpaceStorageMode.LOCAL_ONLY,
    val personalCloudProvider: PersonalCloudProvider? = null,
    val acceptedCloudStorageTermsAt: Instant? = null,
    val currentEncryptionKeyVersion: Int = 1,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now(),
    val containsSensitiveHealthTemplate: Boolean = false
)

// MARK: - Exact Money & Calendar Date Types

/**
 * Exact monetary representation stored in integer minor units (e.g. cents) + ISO 4217 currency code.
 * Never uses binary floating-point (`Double` / `Float`) for storage.
 */
data class MoneyValue(
    val minorUnits: Long,
    val currencyCode: String = "USD",
    val minorUnitScale: Int = 2
) {
    val decimalValue: BigDecimal
        get() = BigDecimal.valueOf(minorUnits, minorUnitScale)

    fun formatted(locale: Locale = Locale.getDefault()): String {
        return try {
            val format = NumberFormat.getCurrencyInstance(locale)
            format.currency = Currency.getInstance(currencyCode.uppercase(Locale.ROOT))
            format.maximumFractionDigits = minorUnitScale
            format.minimumFractionDigits = minorUnitScale
            format.format(decimalValue)
        } catch (_: Exception) {
            "$currencyCode ${decimalValue.toPlainString()}"
        }
    }

    companion object {
        fun fromDecimalString(raw: String, currencyCode: String = "USD", scale: Int = 2): MoneyValue? {
            val cleaned = raw.trim().replace(",", ".")
            if (cleaned.isEmpty()) return null
            return try {
                val bd = BigDecimal(cleaned).setScale(scale, RoundingMode.HALF_UP)
                val multiplier = BigDecimal.TEN.pow(scale)
                val minor = bd.multiply(multiplier).longValueExact()
                MoneyValue(minorUnits = minor, currencyCode = currencyCode.uppercase(Locale.ROOT), minorUnitScale = scale)
            } catch (_: Exception) {
                null
            }
        }
    }
}

/**
 * Timezone-independent calendar date (`YYYY-MM-DD`) so a warranty expiration or medical visit date
 * never shifts across midnight when traveling across time zones.
 */
data class CalendarDate(
    val year: Int,
    val month: Int,
    val day: Int
) : Comparable<CalendarDate> {
    val isoString: String
        get() = String.format(Locale.US, "%04d-%02d-%02d", year, month, day)

    override fun compareTo(other: CalendarDate): Int = isoString.compareTo(other.isoString)

    fun toLocalDate(): LocalDate = LocalDate.of(year, month.coerceIn(1, 12), day.coerceIn(1, 28))

    companion object {
        fun fromIsoString(iso: String): CalendarDate? {
            val parts = iso.trim().split("-")
            if (parts.size != 3) return null
            val y = parts[0].toIntOrNull() ?: return null
            val m = parts[1].toIntOrNull() ?: return null
            val d = parts[2].toIntOrNull() ?: return null
            return CalendarDate(y, m, d)
        }

        fun today(): CalendarDate {
            val now = LocalDate.now(ZoneOffset.UTC)
            return CalendarDate(now.year, now.monthValue, now.dayOfMonth)
        }
    }
}

// MARK: - Dynamic Schema & Field Definitions (Hierarchy Levels 2 & 4)

enum class FieldType(val wireValue: String, val displayLabel: String) {
    SHORT_TEXT("short_text", "Short Text"),
    LONG_TEXT("long_text", "Long Text"),
    NUMBER("number", "Number"),
    CURRENCY("currency", "Currency"),
    DATE("date", "Calendar Date"),
    DATE_TIME("date_time", "Date & Time"),
    BOOLEAN("boolean", "Yes / No"),
    SINGLE_SELECT("single_select", "Single Select"),
    MULTI_SELECT("multi_select", "Multiple Select"),
    RATING("rating", "Rating"),
    ATTACHMENT("attachment", "Photos & Files");

    companion object {
        fun fromWire(value: String): FieldType =
            entries.firstOrNull { it.wireValue == value } ?: SHORT_TEXT
    }
}

data class SelectOption(
    val id: String = UUID.randomUUID().toString(),
    val label: String,
    val colorHex: String? = null
)

data class FieldValidationRules(
    val minNumber: Double? = null,
    val maxNumber: Double? = null,
    val maxLength: Int? = null,
    val maxRating: Int = 5,
    val defaultCurrencyCode: String = "USD"
)

enum class FieldDeletionRetentionPolicy(val wireValue: String) {
    ARCHIVE_AND_RETAIN_VALUES("archive_and_retain_values"),
    PERMANENTLY_PURGE_VALUES("permanently_purge_values")
}

data class FieldDefinition(
    val id: UUID = UUID.randomUUID(),
    val label: String,
    val type: FieldType,
    val isRequired: Boolean = false,
    val sortOrder: Int = 0,
    val options: List<SelectOption> = emptyList(),
    val defaultValue: FieldValue? = null,
    val validation: FieldValidationRules = FieldValidationRules(),
    val isPrimaryTitle: Boolean = false,
    val isArchived: Boolean = false,
    val archivedAt: Instant? = null
)

data class CollectionSchema(
    val id: UUID = UUID.randomUUID(),
    val spaceId: UUID,
    val name: String,
    val iconName: String = "folder",
    val colorHex: String = "#1F5673",
    val schemaVersion: Int = 1,
    val fields: List<FieldDefinition>,
    val isSensitiveTemplate: Boolean = false,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
) {
    val activeFields: List<FieldDefinition>
        get() = fields.filter { !it.isArchived }.sortedBy { it.sortOrder }

    val archivedFields: List<FieldDefinition>
        get() = fields.filter { it.isArchived }.sortedBy { it.sortOrder }
}

// MARK: - Attachments & Typed Field Values

enum class AttachmentUploadState(val wireValue: String) {
    LOCAL_ONLY("local_only"),
    QUEUED_FOR_UPLOAD("queued_for_upload"),
    UPLOADED_VERIFIED("uploaded_verified"),
    FAILED_UPLOAD("failed_upload")
}

data class AttachmentReference(
    val id: UUID = UUID.randomUUID(),
    val filename: String,
    val mimeType: String,
    val byteSize: Long,
    val sha256Hex: String,
    val relativeLocalPath: String,
    val uploadState: AttachmentUploadState = AttachmentUploadState.LOCAL_ONLY,
    val lastUploadError: String? = null,
    val createdAt: Instant = Instant.now()
)

sealed class FieldValue {
    data object NullValue : FieldValue()
    data class ShortText(val value: String) : FieldValue()
    data class LongText(val value: String) : FieldValue()
    data class NumberValue(val value: Double) : FieldValue()
    data class CurrencyValue(val value: MoneyValue) : FieldValue()
    data class DateValue(val value: CalendarDate) : FieldValue()
    data class DateTimeValue(val value: Instant) : FieldValue()
    data class BooleanValue(val value: Boolean) : FieldValue()
    data class SingleSelect(val optionId: String) : FieldValue()
    data class MultiSelect(val optionIds: List<String>) : FieldValue()
    data class Rating(val stars: Int) : FieldValue()
    data class Attachments(val items: List<AttachmentReference>) : FieldValue()

    val isNullOrEmpty: Boolean
        get() = when (this) {
            is NullValue -> true
            is ShortText -> value.trim().isEmpty()
            is LongText -> value.trim().isEmpty()
            is SingleSelect -> optionId.trim().isEmpty()
            is MultiSelect -> optionIds.isEmpty()
            is Attachments -> items.isEmpty()
            else -> false
        }

    fun plainTextSummary(field: FieldDefinition? = null, locale: Locale = Locale.getDefault()): String =
        when (this) {
            is NullValue -> ""
            is ShortText -> value
            is LongText -> value
            is NumberValue -> if (value % 1.0 == 0.0) value.toLong().toString() else value.toString()
            is CurrencyValue -> value.formatted(locale)
            is DateValue -> value.isoString
            is DateTimeValue -> DateTimeFormatter.ISO_INSTANT.format(value)
            is BooleanValue -> if (value) "Yes" else "No"
            is SingleSelect -> field?.options?.firstOrNull { it.id == optionId }?.label ?: optionId
            is MultiSelect -> optionIds.joinToString(", ") { id ->
                field?.options?.firstOrNull { it.id == id }?.label ?: id
            }
            is Rating -> "★".repeat(stars.coerceIn(0, 5))
            is Attachments -> "${items.size} file${if (items.size == 1) "" else "s"}"
        }
}

// MARK: - Record Item (Hierarchy Level 3)

data class RecordItem(
    val id: UUID = UUID.randomUUID(),
    val spaceId: UUID,
    val collectionId: UUID,
    val schemaVersionAtWrite: Int = 1,
    val isFavorite: Boolean = false,
    val values: Map<UUID, FieldValue>,
    val revision: Int = 1,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now(),
    val deletedAt: Instant? = null
) {
    fun title(schema: CollectionSchema): String {
        val primary = schema.activeFields.firstOrNull { it.isPrimaryTitle }
            ?: schema.activeFields.firstOrNull { it.type == FieldType.SHORT_TEXT }
        if (primary != null) {
            val summary = values[primary.id]?.plainTextSummary(primary)?.trim().orEmpty()
            if (summary.isNotEmpty()) return summary
        }
        return "Untitled ${schema.name}"
    }

    fun subtitle(schema: CollectionSchema, locale: Locale = Locale.getDefault()): String {
        val primaryId = (schema.activeFields.firstOrNull { it.isPrimaryTitle }
            ?: schema.activeFields.firstOrNull { it.type == FieldType.SHORT_TEXT })?.id
        val parts = mutableListOf<String>()
        for (field in schema.activeFields) {
            if (field.id == primaryId) continue
            val v = values[field.id] ?: continue
            if (!v.isNullOrEmpty && v !is FieldValue.Attachments) {
                parts.add("${field.label}: ${v.plainTextSummary(field, locale)}")
            }
            if (parts.size >= 2) break
        }
        return parts.joinToString(" • ")
    }

    val allAttachments: List<AttachmentReference>
        get() = values.values.filterIsInstance<FieldValue.Attachments>().flatMap { it.items }
}

// MARK: - Starter Templates & Sensitivity Posture

enum class StarterTemplateID(val wireValue: String) {
    VEHICLE_MAINTENANCE("vehicle_maintenance"),
    HOME_INVENTORY("home_inventory"),
    WARRANTIES("warranties"),
    MEDICAL_VISITS("medical_visits")
}

data class StarterTemplate(
    val id: StarterTemplateID,
    val name: String,
    val subtitle: String,
    val iconName: String,
    val colorHex: String,
    val isSensitiveLocalDefault: Boolean,
    val sensitivityDisclosure: String?,
    val makeFields: () -> List<FieldDefinition>
) {
    fun instantiateSchema(forSpaceId: UUID): CollectionSchema =
        CollectionSchema(
            spaceId = forSpaceId,
            name = name,
            iconName = iconName,
            colorHex = colorHex,
            schemaVersion = 1,
            fields = makeFields(),
            isSensitiveTemplate = isSensitiveLocalDefault
        )
}

object StarterTemplateCatalog {
    val vehicleMaintenance = StarterTemplate(
        id = StarterTemplateID.VEHICLE_MAINTENANCE,
        name = "Vehicle Maintenance",
        subtitle = "Track oil changes, tire rotations, mileage, service costs, and shop receipts.",
        iconName = "car",
        colorHex = "#2B5B84",
        isSensitiveLocalDefault = false,
        sensitivityDisclosure = null
    ) {
        listOf(
            FieldDefinition(label = "Service Summary", type = FieldType.SHORT_TEXT, isRequired = true, sortOrder = 0, isPrimaryTitle = true),
            FieldDefinition(label = "Service Date", type = FieldType.DATE, isRequired = true, sortOrder = 1),
            FieldDefinition(label = "Odometer (km/mi)", type = FieldType.NUMBER, isRequired = false, sortOrder = 2, validation = FieldValidationRules(minNumber = 0.0)),
            FieldDefinition(label = "Total Cost", type = FieldType.CURRENCY, isRequired = false, sortOrder = 3),
            FieldDefinition(
                label = "Category",
                type = FieldType.SINGLE_SELECT,
                isRequired = false,
                sortOrder = 4,
                options = listOf(
                    SelectOption(id = "oil", label = "Oil & Fluids"),
                    SelectOption(id = "tires", label = "Tires & Brakes"),
                    SelectOption(id = "inspection", label = "Inspection"),
                    SelectOption(id = "repair", label = "Repair")
                )
            ),
            FieldDefinition(label = "Shop / Mechanic", type = FieldType.SHORT_TEXT, isRequired = false, sortOrder = 5),
            FieldDefinition(label = "Invoice / Receipt", type = FieldType.ATTACHMENT, isRequired = false, sortOrder = 6),
            FieldDefinition(label = "Notes", type = FieldType.LONG_TEXT, isRequired = false, sortOrder = 7)
        )
    }

    val homeInventory = StarterTemplate(
        id = StarterTemplateID.HOME_INVENTORY,
        name = "Home Inventory",
        subtitle = "Catalog household items, serial numbers, room locations, and purchase values for insurance.",
        iconName = "home",
        colorHex = "#3A6B5C",
        isSensitiveLocalDefault = false,
        sensitivityDisclosure = null
    ) {
        listOf(
            FieldDefinition(label = "Item Name", type = FieldType.SHORT_TEXT, isRequired = true, sortOrder = 0, isPrimaryTitle = true),
            FieldDefinition(
                label = "Room",
                type = FieldType.SINGLE_SELECT,
                isRequired = false,
                sortOrder = 1,
                options = listOf(
                    SelectOption(id = "living", label = "Living Room"),
                    SelectOption(id = "kitchen", label = "Kitchen"),
                    SelectOption(id = "office", label = "Home Office"),
                    SelectOption(id = "bedroom", label = "Bedroom"),
                    SelectOption(id = "garage", label = "Garage")
                )
            ),
            FieldDefinition(label = "Purchase Price", type = FieldType.CURRENCY, isRequired = false, sortOrder = 2),
            FieldDefinition(label = "Purchase Date", type = FieldType.DATE, isRequired = false, sortOrder = 3),
            FieldDefinition(label = "Serial / Model Number", type = FieldType.SHORT_TEXT, isRequired = false, sortOrder = 4),
            FieldDefinition(label = "Condition Rating", type = FieldType.RATING, isRequired = false, sortOrder = 5),
            FieldDefinition(label = "Photos & Proof", type = FieldType.ATTACHMENT, isRequired = false, sortOrder = 6)
        )
    }

    val warranties = StarterTemplate(
        id = StarterTemplateID.WARRANTIES,
        name = "Warranties",
        subtitle = "Keep expiration dates, coverage terms, retailer receipts, and support contacts in one place.",
        iconName = "verified_user",
        colorHex = "#8C5A2B",
        isSensitiveLocalDefault = false,
        sensitivityDisclosure = null
    ) {
        listOf(
            FieldDefinition(label = "Product Name", type = FieldType.SHORT_TEXT, isRequired = true, sortOrder = 0, isPrimaryTitle = true),
            FieldDefinition(label = "Brand / Retailer", type = FieldType.SHORT_TEXT, isRequired = false, sortOrder = 1),
            FieldDefinition(label = "Purchase Date", type = FieldType.DATE, isRequired = false, sortOrder = 2),
            FieldDefinition(label = "Warranty Expires On", type = FieldType.DATE, isRequired = true, sortOrder = 3),
            FieldDefinition(label = "Extended Coverage", type = FieldType.BOOLEAN, isRequired = false, sortOrder = 4),
            FieldDefinition(label = "Receipt / Certificate", type = FieldType.ATTACHMENT, isRequired = false, sortOrder = 5),
            FieldDefinition(label = "Claim Notes", type = FieldType.LONG_TEXT, isRequired = false, sortOrder = 6)
        )
    }

    val medicalVisits = StarterTemplate(
        id = StarterTemplateID.MEDICAL_VISITS,
        name = "Medical Visits",
        subtitle = "Organize clinician visits, questions asked, follow-up dates, and discharge summaries.",
        iconName = "medical_services",
        colorHex = "#7A3E58",
        isSensitiveLocalDefault = true,
        sensitivityDisclosure = "Medical Visits is marked as a sensitive collection and defaults to Local-Only storage so your health records stay strictly on this device unless you explicitly choose encrypted Arca Sync. Custom collections with other names may also hold sensitive information—you can set any Space to Local-Only at any time."
    ) {
        listOf(
            FieldDefinition(label = "Visit Summary / Specialty", type = FieldType.SHORT_TEXT, isRequired = true, sortOrder = 0, isPrimaryTitle = true),
            FieldDefinition(label = "Visit Date", type = FieldType.DATE, isRequired = true, sortOrder = 1),
            FieldDefinition(label = "Clinician / Facility", type = FieldType.SHORT_TEXT, isRequired = false, sortOrder = 2),
            FieldDefinition(label = "Out-of-Pocket Cost", type = FieldType.CURRENCY, isRequired = false, sortOrder = 3),
            FieldDefinition(label = "Follow-Up Needed", type = FieldType.BOOLEAN, isRequired = false, sortOrder = 4),
            FieldDefinition(label = "Visit Notes & Takeaways", type = FieldType.LONG_TEXT, isRequired = false, sortOrder = 5),
            FieldDefinition(label = "Documents", type = FieldType.ATTACHMENT, isRequired = false, sortOrder = 6)
        )
    }

    val all: List<StarterTemplate> = listOf(vehicleMaintenance, homeInventory, warranties, medicalVisits)
}

// MARK: - Dynamic Schema Evolution & Validation Engine

data class RecordValidationError(
    val fieldId: UUID,
    val fieldLabel: String,
    val reason: String
)

data class FieldConversionPreview(
    val fieldId: UUID,
    val fieldLabel: String,
    val fromType: FieldType,
    val toType: FieldType,
    val totalRecordsExamined: Int,
    val compatibleCount: Int,
    val failureCount: Int,
    val sampleFailureDescriptions: List<String>
) {
    val isSafeToApplyWithoutLoss: Boolean
        get() = failureCount == 0
}

object SchemaEngine {
    fun validate(values: Map<UUID, FieldValue>, schema: CollectionSchema): List<RecordValidationError> {
        val errors = mutableListOf<RecordValidationError>()
        for (field in schema.activeFields) {
            val v = values[field.id] ?: FieldValue.NullValue
            if (field.isRequired && v.isNullOrEmpty) {
                errors.add(RecordValidationError(field.id, field.label, "“${field.label}” is required."))
                continue
            }
            if (v is FieldValue.NumberValue) {
                field.validation.minNumber?.let { min ->
                    if (v.value < min) errors.add(RecordValidationError(field.id, field.label, "“${field.label}” must be at least $min."))
                }
                field.validation.maxNumber?.let { max ->
                    if (v.value > max) errors.add(RecordValidationError(field.id, field.label, "“${field.label}” must be at most $max."))
                }
            }
        }
        return errors
    }

    /**
     * Renames a field's display label while keeping its UUID unchanged so all existing record values remain intact.
     */
    fun renameField(schema: CollectionSchema, fieldId: UUID, newLabel: String): CollectionSchema {
        val trimmed = newLabel.trim()
        if (trimmed.isEmpty()) return schema
        val updatedFields = schema.fields.map { f ->
            if (f.id == fieldId) f.copy(label = trimmed) else f
        }
        return schema.copy(
            schemaVersion = schema.schemaVersion + 1,
            fields = updatedFields,
            updatedAt = Instant.now()
        )
    }

    /**
     * Dry-run previews converting a field to `targetType` without mutating or discarding any record values.
     */
    fun previewFieldConversion(
        field: FieldDefinition,
        targetType: FieldType,
        records: List<RecordItem>
    ): FieldConversionPreview {
        var compatible = 0
        var failures = 0
        val samples = mutableListOf<String>()

        for (rec in records) {
            val current = rec.values[field.id] ?: FieldValue.NullValue
            if (current.isNullOrEmpty) {
                compatible++
                continue
            }
            val converted = attemptConvert(current, targetType, field.validation)
            if (converted != null) {
                compatible++
            } else {
                failures++
                if (samples.size < 3) {
                    samples.add("Record ${rec.id.toString().take(6)}: cannot convert “${current.plainTextSummary(field)}” to ${targetType.displayLabel}")
                }
            }
        }

        return FieldConversionPreview(
            fieldId = field.id,
            fieldLabel = field.label,
            fromType = field.type,
            toType = targetType,
            totalRecordsExamined = records.size,
            compatibleCount = compatible,
            failureCount = failures,
            sampleFailureDescriptions = samples
        )
    }

    fun attemptConvert(value: FieldValue, targetType: FieldType, rules: FieldValidationRules = FieldValidationRules()): FieldValue? {
        if (value is FieldValue.NullValue) return FieldValue.NullValue
        return when (targetType) {
            FieldType.SHORT_TEXT -> FieldValue.ShortText(value.plainTextSummary())
            FieldType.LONG_TEXT -> FieldValue.LongText(value.plainTextSummary())
            FieldType.NUMBER -> when (value) {
                is FieldValue.NumberValue -> value
                is FieldValue.ShortText -> value.value.trim().toDoubleOrNull()?.let { FieldValue.NumberValue(it) }
                is FieldValue.Rating -> FieldValue.NumberValue(value.stars.toDouble())
                else -> null
            }
            FieldType.CURRENCY -> when (value) {
                is FieldValue.CurrencyValue -> value
                is FieldValue.NumberValue -> MoneyValue.fromDecimalString(value.value.toString(), rules.defaultCurrencyCode)?.let { FieldValue.CurrencyValue(it) }
                is FieldValue.ShortText -> MoneyValue.fromDecimalString(value.value, rules.defaultCurrencyCode)?.let { FieldValue.CurrencyValue(it) }
                else -> null
            }
            else -> null
        }
    }
}
