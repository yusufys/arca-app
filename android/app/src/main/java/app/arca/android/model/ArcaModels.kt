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
    val storageMode: SpaceStorageMode = SpaceStorageMode.ARCA_SYNC,
    val personalCloudProvider: PersonalCloudProvider? = null,
    val acceptedCloudStorageTermsAt: Instant? = null,
    val currentEncryptionKeyVersion: Int = 1,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now(),
    val containsSensitiveHealthTemplate: Boolean = false,
    val userExplicitlyConfirmedSyncForSensitiveSpace: Boolean = false
) {
    val resolvedStorageMode: SpaceStorageMode
        get() = if (containsSensitiveHealthTemplate && !userExplicitlyConfirmedSyncForSensitiveSpace) {
            SpaceStorageMode.LOCAL_ONLY
        } else {
            storageMode
        }
}

data class AppAnnouncementBanner(
    val id: String,
    val title: String,
    val body: String,
    val ctaLabel: String? = null,
    val ctaUrl: String? = null,
    val placement: String = "home_banner",
    val targetPlatform: String = "android",
    val targetTier: String = "all"
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
    MEDICAL_VISITS("medical_visits"),
    SUBSCRIPTIONS("subscriptions"),
    DOCUMENTS("documents")
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
        name = "Warranties & Serials",
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

    val subscriptions = StarterTemplate(
        id = StarterTemplateID.SUBSCRIPTIONS,
        name = "Subscriptions & Renewals",
        subtitle = "Track recurring memberships, software licenses, renewal dates, and billing amounts.",
        iconName = "autorenew",
        colorHex = "#4A5D4E",
        isSensitiveLocalDefault = false,
        sensitivityDisclosure = null
    ) {
        listOf(
            FieldDefinition(label = "Service / App Name", type = FieldType.SHORT_TEXT, isRequired = true, sortOrder = 0, isPrimaryTitle = true),
            FieldDefinition(label = "Renewal Date", type = FieldType.DATE, isRequired = true, sortOrder = 1),
            FieldDefinition(
                label = "Billing Cycle",
                type = FieldType.SINGLE_SELECT,
                isRequired = false,
                sortOrder = 2,
                options = listOf(
                    SelectOption(id = "monthly", label = "Monthly"),
                    SelectOption(id = "annual", label = "Annual"),
                    SelectOption(id = "weekly", label = "Weekly"),
                    SelectOption(id = "quarterly", label = "Quarterly")
                )
            ),
            FieldDefinition(label = "Cost", type = FieldType.CURRENCY, isRequired = false, sortOrder = 3),
            FieldDefinition(label = "Auto-Renew", type = FieldType.BOOLEAN, isRequired = false, sortOrder = 4),
            FieldDefinition(label = "Payment Method", type = FieldType.SHORT_TEXT, isRequired = false, sortOrder = 5),
            FieldDefinition(label = "Account / Login Email", type = FieldType.SHORT_TEXT, isRequired = false, sortOrder = 6),
            FieldDefinition(label = "Invoices & Receipts", type = FieldType.ATTACHMENT, isRequired = false, sortOrder = 7),
            FieldDefinition(label = "Notes", type = FieldType.LONG_TEXT, isRequired = false, sortOrder = 8)
        )
    }

    val documents = StarterTemplate(
        id = StarterTemplateID.DOCUMENTS,
        name = "Documents & IDs",
        subtitle = "Secure scans of passports, IDs, licenses, insurance policies, and certificates.",
        iconName = "badge",
        colorHex = "#5E4B72",
        isSensitiveLocalDefault = false,
        sensitivityDisclosure = null
    ) {
        listOf(
            FieldDefinition(label = "Document Title", type = FieldType.SHORT_TEXT, isRequired = true, sortOrder = 0, isPrimaryTitle = true),
            FieldDefinition(
                label = "Document Type",
                type = FieldType.SINGLE_SELECT,
                isRequired = false,
                sortOrder = 1,
                options = listOf(
                    SelectOption(id = "passport", label = "Passport"),
                    SelectOption(id = "national_id", label = "National ID"),
                    SelectOption(id = "driver_license", label = "Driver's License"),
                    SelectOption(id = "insurance", label = "Insurance Card"),
                    SelectOption(id = "contract", label = "Contract / Lease"),
                    SelectOption(id = "tax", label = "Tax Document"),
                    SelectOption(id = "certificate", label = "Certificate")
                )
            ),
            FieldDefinition(label = "Identifier / Number", type = FieldType.SHORT_TEXT, isRequired = false, sortOrder = 2),
            FieldDefinition(label = "Issue Date", type = FieldType.DATE, isRequired = false, sortOrder = 3),
            FieldDefinition(label = "Expiration Date", type = FieldType.DATE, isRequired = false, sortOrder = 4),
            FieldDefinition(label = "Issuing Authority", type = FieldType.SHORT_TEXT, isRequired = false, sortOrder = 5),
            FieldDefinition(label = "Scanned Files & Photos", type = FieldType.ATTACHMENT, isRequired = false, sortOrder = 6),
            FieldDefinition(label = "Notes", type = FieldType.LONG_TEXT, isRequired = false, sortOrder = 7)
        )
    }

    val all: List<StarterTemplate> = listOf(vehicleMaintenance, warranties, homeInventory, medicalVisits, subscriptions, documents)
}

// MARK: - Record Sort & Snapshots

enum class RecordSortCriterion(val displayLabel: String) {
    UPDATED_DESC("Newest (Updated)"),
    UPDATED_ASC("Oldest (Updated)"),
    TITLE_ASC("Title (A → Z)"),
    TITLE_DESC("Title (Z → A)")
}

data class PublicRecordSnapshot(
    val id: UUID = UUID.randomUUID(),
    val sourceRecordId: UUID,
    val title: String,
    val shareToken: String = "snap-${UUID.randomUUID().toString().take(8)}",
    val selectedFieldPairs: List<Pair<String, String>>,
    val createdAt: Instant = Instant.now(),
    val isRevoked: Boolean = false
)

// MARK: - Dynamic Schema Evolution & Validation Engine

data class RecordValidationError(
    val fieldId: UUID,
    val fieldLabel: String,
    val reason: String
)

data class FieldConversionPreview(
    val fieldId: UUID,
    val fieldLabel: String = "",
    val fromType: FieldType,
    val toType: FieldType,
    val totalRecordsExamined: Int,
    val successCount: Int,
    val failureCount: Int,
    val sampleFailureDescriptions: List<String> = emptyList()
) {
    val isSafeToApplyWithoutLoss: Boolean
        get() = failureCount == 0

    val compatibleCount: Int
        get() = successCount
}

object SimpleJsonParser {
    fun parse(json: String): Any? {
        val tokens = tokenize(json.trim())
        var pos = 0

        fun parseValue(): Any? {
            if (pos >= tokens.size) return null
            val tok = tokens[pos++]
            return when (tok) {
                "{" -> {
                    val map = mutableMapOf<String, Any?>()
                    while (pos < tokens.size && tokens[pos] != "}") {
                        val keyVal = parseValue()
                        val key = keyVal?.toString() ?: break
                        if (pos < tokens.size && tokens[pos] == ":") pos++
                        val value = parseValue()
                        map[key] = value
                        if (pos < tokens.size && tokens[pos] == ",") pos++
                    }
                    if (pos < tokens.size && tokens[pos] == "}") pos++
                    map
                }
                "[" -> {
                    val list = mutableListOf<Any?>()
                    while (pos < tokens.size && tokens[pos] != "]") {
                        val value = parseValue()
                        list.add(value)
                        if (pos < tokens.size && tokens[pos] == ",") pos++
                    }
                    if (pos < tokens.size && tokens[pos] == "]") pos++
                    list
                }
                "true" -> true
                "false" -> false
                "null" -> null
                else -> {
                    if (tok.startsWith("\"") && tok.endsWith("\"") && tok.length >= 2) {
                        tok.substring(1, tok.length - 1)
                            .replace("\\\"", "\"")
                            .replace("\\\\", "\\")
                            .replace("\\n", "\n")
                            .replace("\\r", "\r")
                            .replace("\\t", "\t")
                    } else {
                        tok.toDoubleOrNull() ?: tok.toLongOrNull() ?: tok
                    }
                }
            }
        }

        return parseValue()
    }

    private fun tokenize(s: String): List<String> {
        val tokens = mutableListOf<String>()
        var i = 0
        while (i < s.length) {
            val c = s[i]
            when {
                c.isWhitespace() -> i++
                c in listOf('{', '}', '[', ']', ':', ',') -> {
                    tokens.add(c.toString())
                    i++
                }
                c == '"' -> {
                    val sb = StringBuilder()
                    sb.append('"')
                    i++
                    var escaped = false
                    while (i < s.length) {
                        val ch = s[i]
                        sb.append(ch)
                        i++
                        if (escaped) {
                            escaped = false
                        } else if (ch == '\\') {
                            escaped = true
                        } else if (ch == '"') {
                            break
                        }
                    }
                    tokens.add(sb.toString())
                }
                else -> {
                    val sb = StringBuilder()
                    while (i < s.length && !s[i].isWhitespace() && s[i] !in listOf('{', '}', '[', ']', ':', ',')) {
                        sb.append(s[i])
                        i++
                    }
                    tokens.add(sb.toString())
                }
            }
        }
        return tokens
    }
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
     * Reorders active fields deterministically and increments schemaVersion.
     */
    fun reorderFields(schema: CollectionSchema, orderedFieldIds: List<UUID>): CollectionSchema {
        var nextOrder = 0
        val updatedFields = schema.fields.toMutableList()
        for (id in orderedFieldIds) {
            val idx = updatedFields.indexOfFirst { it.id == id }
            if (idx >= 0) {
                updatedFields[idx] = updatedFields[idx].copy(sortOrder = nextOrder++)
            }
        }
        for (i in updatedFields.indices) {
            if (!orderedFieldIds.contains(updatedFields[i].id)) {
                updatedFields[i] = updatedFields[i].copy(sortOrder = nextOrder++)
            }
        }
        updatedFields.sortBy { it.sortOrder }
        return schema.copy(
            schemaVersion = schema.schemaVersion + 1,
            fields = updatedFields,
            updatedAt = Instant.now()
        )
    }

    /**
     * Restores a previously archived field, immediately exposing all preserved historical record values.
     */
    fun restoreArchivedField(schema: CollectionSchema, fieldId: UUID): CollectionSchema {
        val updated = schema.fields.map { f ->
            if (f.id == fieldId) f.copy(isArchived = false, archivedAt = null) else f
        }
        return schema.copy(
            schemaVersion = schema.schemaVersion + 1,
            fields = updated,
            updatedAt = Instant.now()
        )
    }

    /**
     * Dry-run previews converting a field to `targetType` without mutating or discarding any record values.
     */
    fun previewFieldTypeConversion(
        field: FieldDefinition,
        targetType: FieldType,
        records: List<RecordItem>
    ): FieldConversionPreview {
        var successes = 0
        var failures = 0
        val samples = mutableListOf<String>()
        val activeRecords = records.filter { it.deletedAt == null }

        for (rec in activeRecords) {
            val current = rec.values[field.id] ?: FieldValue.NullValue
            if (current.isNullOrEmpty) {
                successes++
                continue
            }
            val converted = attemptConvert(current, targetType, field.validation)
            if (converted != null) {
                successes++
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
            totalRecordsExamined = activeRecords.size,
            successCount = successes,
            failureCount = failures,
            sampleFailureDescriptions = samples
        )
    }

    fun previewFieldConversion(
        field: FieldDefinition,
        targetType: FieldType,
        records: List<RecordItem>
    ): FieldConversionPreview = previewFieldTypeConversion(field, targetType, records)

    fun applyFieldTypeConversion(
        schema: CollectionSchema,
        fieldId: UUID,
        targetType: FieldType,
        records: List<RecordItem>
    ): Pair<CollectionSchema, List<RecordItem>> {
        val field = schema.fields.firstOrNull { it.id == fieldId }
            ?: throw NoSuchElementException("Field $fieldId not found in collection ${schema.name}")
        val preview = previewFieldTypeConversion(field, targetType, records)
        if (!preview.isSafeToApplyWithoutLoss) {
            throw IllegalStateException("Field conversion would lose data for ${preview.failureCount} record(s)")
        }

        val updatedFields = schema.fields.map { f ->
            if (f.id == fieldId) f.copy(type = targetType) else f
        }
        val updatedSchema = schema.copy(
            schemaVersion = schema.schemaVersion + 1,
            fields = updatedFields,
            updatedAt = Instant.now()
        )

        val updatedRecords = records.map { rec ->
            if (rec.deletedAt != null) return@map rec
            val current = rec.values[fieldId] ?: FieldValue.NullValue
            if (current.isNullOrEmpty) return@map rec
            val converted = attemptConvert(current, targetType, field.validation) ?: current
            val newValues = rec.values.toMutableMap()
            newValues[fieldId] = converted
            rec.copy(
                values = newValues,
                schemaVersionAtWrite = updatedSchema.schemaVersion,
                revision = rec.revision + 1,
                updatedAt = Instant.now()
            )
        }

        return Pair(updatedSchema, updatedRecords)
    }

    fun chatGptSchemaPrompt(topic: String): String {
        return """
        Generate a JSON collection schema for the Arca personal records app for the topic: "$topic".
        Respond ONLY with valid JSON matching this structure:
        {
          "name": "Collection Name",
          "iconName": "folder",
          "colorHex": "#2B5B84",
          "fields": [
            {
              "label": "Primary Title",
              "type": "short_text",
              "isRequired": true,
              "isPrimaryTitle": true,
              "options": []
            }
          ]
        }
        Allowed field types: short_text, long_text, number, currency, date, date_time, boolean, single_select, multi_select, rating, attachment.
        """.trimIndent()
    }

    fun parseAndValidateImportedSchemaJson(json: String, spaceId: UUID): Result<CollectionSchema> {
        return try {
            val trimmed = json.trim()
            if (trimmed.isEmpty()) {
                return Result.failure(IllegalArgumentException("Imported JSON cannot be empty"))
            }
            val cleanJson = trimmed
                .removePrefix("```json")
                .removePrefix("```JSON")
                .removePrefix("```")
                .removeSuffix("```")
                .trim()

            val parsed = SimpleJsonParser.parse(cleanJson) as? Map<*, *>
                ?: return Result.failure(IllegalArgumentException("Invalid JSON root object"))

            val name = (parsed["name"] as? String)?.trim().orEmpty()
            if (name.isEmpty()) {
                return Result.failure(IllegalArgumentException("Schema must contain a non-empty collection 'name'"))
            }
            val iconName = (parsed["iconName"] as? String)?.trim()?.ifBlank { "folder" } ?: "folder"
            val colorHex = (parsed["colorHex"] as? String)?.trim()?.ifBlank { "#1F5673" } ?: "#1F5673"
            val fieldsRaw = (parsed["fields"] as? List<*>)
                ?: return Result.failure(IllegalArgumentException("Schema must contain a 'fields' array"))
            if (fieldsRaw.isEmpty()) {
                return Result.failure(IllegalArgumentException("Schema must define at least one field"))
            }

            val fields = mutableListOf<FieldDefinition>()
            for ((i, fItem) in fieldsRaw.withIndex()) {
                val fMap = fItem as? Map<*, *>
                    ?: return Result.failure(IllegalArgumentException("Field #$i must be a JSON object"))
                val label = (fMap["label"] as? String)?.trim().orEmpty()
                if (label.isEmpty()) {
                    return Result.failure(IllegalArgumentException("Field #${i + 1} has an empty label"))
                }
                val typeStr = (fMap["type"] as? String)?.trim() ?: "short_text"
                val type = FieldType.fromWire(typeStr)
                val isRequired = (fMap["isRequired"] as? Boolean) ?: (i == 0)
                val isPrimaryTitle = (fMap["isPrimaryTitle"] as? Boolean) ?: (i == 0)

                val optionsList = mutableListOf<SelectOption>()
                val optsRaw = fMap["options"] as? List<*>
                if (optsRaw != null) {
                    for ((j, optItem) in optsRaw.withIndex()) {
                        when (optItem) {
                            is Map<*, *> -> {
                                val optId = (optItem["id"] as? String) ?: UUID.randomUUID().toString()
                                val optLabel = (optItem["label"] as? String) ?: "Option ${j + 1}"
                                optionsList.add(SelectOption(id = optId, label = optLabel))
                            }
                            else -> {
                                val optStr = optItem?.toString()?.trim().orEmpty()
                                if (optStr.isNotEmpty()) {
                                    optionsList.add(SelectOption(label = optStr))
                                }
                            }
                        }
                    }
                }

                fields.add(
                    FieldDefinition(
                        id = UUID.randomUUID(),
                        label = label,
                        type = type,
                        isRequired = isRequired,
                        sortOrder = i,
                        options = optionsList,
                        isPrimaryTitle = isPrimaryTitle
                    )
                )
            }

            Result.success(
                CollectionSchema(
                    id = UUID.randomUUID(),
                    spaceId = spaceId,
                    name = name,
                    iconName = iconName,
                    colorHex = colorHex,
                    schemaVersion = 1,
                    fields = fields
                )
            )
        } catch (e: Exception) {
            Result.failure(IllegalArgumentException("Failed to parse JSON schema: ${e.message}", e))
        }
    }

    fun attemptConvert(value: FieldValue, targetType: FieldType, rules: FieldValidationRules = FieldValidationRules()): FieldValue? {
        if (value is FieldValue.NullValue) return FieldValue.NullValue
        return when (targetType) {
            FieldType.SHORT_TEXT -> FieldValue.ShortText(value.plainTextSummary())
            FieldType.LONG_TEXT -> FieldValue.LongText(value.plainTextSummary())
            FieldType.NUMBER -> when (value) {
                is FieldValue.NumberValue -> value
                is FieldValue.ShortText -> value.value.trim().toDoubleOrNull()?.let { FieldValue.NumberValue(it) }
                is FieldValue.LongText -> value.value.trim().toDoubleOrNull()?.let { FieldValue.NumberValue(it) }
                is FieldValue.Rating -> FieldValue.NumberValue(value.stars.toDouble())
                is FieldValue.CurrencyValue -> FieldValue.NumberValue(value.value.decimalValue.toDouble())
                else -> null
            }
            FieldType.CURRENCY -> when (value) {
                is FieldValue.CurrencyValue -> value
                is FieldValue.NumberValue -> MoneyValue.fromDecimalString(value.value.toString(), rules.defaultCurrencyCode)?.let { FieldValue.CurrencyValue(it) }
                is FieldValue.ShortText -> MoneyValue.fromDecimalString(value.value, rules.defaultCurrencyCode)?.let { FieldValue.CurrencyValue(it) }
                is FieldValue.LongText -> MoneyValue.fromDecimalString(value.value, rules.defaultCurrencyCode)?.let { FieldValue.CurrencyValue(it) }
                else -> null
            }
            FieldType.DATE -> when (value) {
                is FieldValue.DateValue -> value
                is FieldValue.ShortText -> CalendarDate.fromIsoString(value.value)?.let { FieldValue.DateValue(it) }
                is FieldValue.DateTimeValue -> {
                    val zdt = value.value.atOffset(ZoneOffset.UTC)
                    FieldValue.DateValue(CalendarDate(zdt.year, zdt.monthValue, zdt.dayOfMonth))
                }
                else -> null
            }
            FieldType.DATE_TIME -> when (value) {
                is FieldValue.DateTimeValue -> value
                is FieldValue.DateValue -> {
                    val inst = value.value.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant()
                    FieldValue.DateTimeValue(inst)
                }
                is FieldValue.ShortText -> {
                    try {
                        FieldValue.DateTimeValue(Instant.parse(value.value))
                    } catch (_: Exception) {
                        CalendarDate.fromIsoString(value.value)?.let {
                            FieldValue.DateTimeValue(it.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant())
                        }
                    }
                }
                else -> null
            }
            FieldType.BOOLEAN -> when (value) {
                is FieldValue.BooleanValue -> value
                is FieldValue.ShortText -> when (value.value.trim().lowercase(Locale.ROOT)) {
                    "true", "yes", "1", "y" -> FieldValue.BooleanValue(true)
                    "false", "no", "0", "n" -> FieldValue.BooleanValue(false)
                    else -> null
                }
                else -> null
            }
            FieldType.RATING -> when (value) {
                is FieldValue.Rating -> value
                is FieldValue.NumberValue -> {
                    val stars = value.value.toInt()
                    if (stars in 0..rules.maxRating) FieldValue.Rating(stars) else null
                }
                is FieldValue.ShortText -> value.value.trim().toIntOrNull()?.let {
                    if (it in 0..rules.maxRating) FieldValue.Rating(it) else null
                }
                else -> null
            }
            FieldType.SINGLE_SELECT -> when (value) {
                is FieldValue.SingleSelect -> value
                is FieldValue.ShortText -> FieldValue.SingleSelect(value.value)
                is FieldValue.MultiSelect -> value.optionIds.firstOrNull()?.let { FieldValue.SingleSelect(it) }
                else -> null
            }
            FieldType.MULTI_SELECT -> when (value) {
                is FieldValue.MultiSelect -> value
                is FieldValue.SingleSelect -> FieldValue.MultiSelect(listOf(value.optionId))
                is FieldValue.ShortText -> FieldValue.MultiSelect(listOf(value.value))
                else -> null
            }
            FieldType.ATTACHMENT -> when (value) {
                is FieldValue.Attachments -> value
                else -> null
            }
        }
    }
}

// MARK: - Space Insights Engine

data class NumericSummary(
    val fieldId: UUID,
    val collectionName: String,
    val fieldLabel: String,
    val isCurrency: Boolean,
    val currencyCode: String?,
    val count: Int,
    val sum: Double,
    val average: Double,
    val formattedSum: String,
    val formattedAverage: String
)

data class UpcomingExpiration(
    val recordId: UUID,
    val collectionId: UUID,
    val title: String,
    val fieldLabel: String,
    val expirationDate: CalendarDate,
    val daysRemaining: Long,
    val isExpired: Boolean
)

data class SelectDistribution(
    val fieldId: UUID,
    val fieldLabel: String,
    val optionLabel: String,
    val count: Int
)

data class SpaceInsightsReport(
    val spaceId: UUID,
    val totalRecords: Int,
    val favoriteRecords: Int,
    val totalAttachments: Int,
    val numericSummaries: List<NumericSummary>,
    val upcomingExpirations: List<UpcomingExpiration>,
    val selectDistributions: List<SelectDistribution>
) {
    companion object {
        fun compute(
            spaceId: UUID,
            collections: List<CollectionSchema>,
            records: List<RecordItem>,
            referenceDate: CalendarDate = CalendarDate.today()
        ): SpaceInsightsReport {
            val activeCollections = collections.filter { it.spaceId == spaceId }
            val activeRecords = records.filter { it.spaceId == spaceId && it.deletedAt == null }

            val totalRecords = activeRecords.size
            val favoriteRecords = activeRecords.count { it.isFavorite }
            val totalAttachments = activeRecords.sumOf { it.allAttachments.size }

            val numericSummaries = mutableListOf<NumericSummary>()
            val selectDistributions = mutableListOf<SelectDistribution>()
            val upcomingExpirations = mutableListOf<UpcomingExpiration>()

            val refLocalDate = referenceDate.toLocalDate()

            for (col in activeCollections) {
                val colRecords = activeRecords.filter { it.collectionId == col.id }

                for (field in col.activeFields) {
                    when (field.type) {
                        FieldType.NUMBER -> {
                            val nums = colRecords.mapNotNull {
                                (it.values[field.id] as? FieldValue.NumberValue)?.value
                            }
                            if (nums.isNotEmpty()) {
                                val sum = nums.sum()
                                val avg = sum / nums.size
                                val fmtSum = if (sum % 1.0 == 0.0) sum.toLong().toString() else String.format(Locale.US, "%.1f", sum)
                                val fmtAvg = if (avg % 1.0 == 0.0) avg.toLong().toString() else String.format(Locale.US, "%.1f", avg)
                                numericSummaries.add(
                                    NumericSummary(
                                        fieldId = field.id,
                                        collectionName = col.name,
                                        fieldLabel = field.label,
                                        isCurrency = false,
                                        currencyCode = null,
                                        count = nums.size,
                                        sum = sum,
                                        average = avg,
                                        formattedSum = fmtSum,
                                        formattedAverage = fmtAvg
                                    )
                                )
                            }
                        }
                        FieldType.CURRENCY -> {
                            val moneyItems = colRecords.mapNotNull {
                                (it.values[field.id] as? FieldValue.CurrencyValue)?.value
                            }
                            if (moneyItems.isNotEmpty()) {
                                val code = moneyItems.firstOrNull()?.currencyCode ?: field.validation.defaultCurrencyCode
                                val totalMinor = moneyItems.sumOf { it.minorUnits }
                                val avgMinor = totalMinor / moneyItems.size
                                val totalMoney = MoneyValue(minorUnits = totalMinor, currencyCode = code)
                                val avgMoney = MoneyValue(minorUnits = avgMinor, currencyCode = code)
                                numericSummaries.add(
                                    NumericSummary(
                                        fieldId = field.id,
                                        collectionName = col.name,
                                        fieldLabel = field.label,
                                        isCurrency = true,
                                        currencyCode = code,
                                        count = moneyItems.size,
                                        sum = totalMoney.decimalValue.toDouble(),
                                        average = avgMoney.decimalValue.toDouble(),
                                        formattedSum = totalMoney.formatted(),
                                        formattedAverage = avgMoney.formatted()
                                    )
                                )
                            }
                        }
                        FieldType.SINGLE_SELECT -> {
                            val counts = mutableMapOf<String, Int>()
                            for (rec in colRecords) {
                                val optId = (rec.values[field.id] as? FieldValue.SingleSelect)?.optionId ?: continue
                                val label = field.options.firstOrNull { it.id == optId || it.label == optId }?.label ?: optId
                                counts[label] = (counts[label] ?: 0) + 1
                            }
                            for ((label, count) in counts.entries.sortedByDescending { it.value }) {
                                selectDistributions.add(
                                    SelectDistribution(
                                        fieldId = field.id,
                                        fieldLabel = "${col.name} • ${field.label}",
                                        optionLabel = label,
                                        count = count
                                    )
                                )
                            }
                        }
                        FieldType.MULTI_SELECT -> {
                            val counts = mutableMapOf<String, Int>()
                            for (rec in colRecords) {
                                val optIds = (rec.values[field.id] as? FieldValue.MultiSelect)?.optionIds ?: continue
                                for (optId in optIds) {
                                    val label = field.options.firstOrNull { it.id == optId || it.label == optId }?.label ?: optId
                                    counts[label] = (counts[label] ?: 0) + 1
                                }
                            }
                            for ((label, count) in counts.entries.sortedByDescending { it.value }) {
                                selectDistributions.add(
                                    SelectDistribution(
                                        fieldId = field.id,
                                        fieldLabel = "${col.name} • ${field.label}",
                                        optionLabel = label,
                                        count = count
                                    )
                                )
                            }
                        }
                        FieldType.DATE -> {
                            for (rec in colRecords) {
                                val calDate = (rec.values[field.id] as? FieldValue.DateValue)?.value ?: continue
                                val recDate = calDate.toLocalDate()
                                val days = java.time.temporal.ChronoUnit.DAYS.between(refLocalDate, recDate)
                                upcomingExpirations.add(
                                    UpcomingExpiration(
                                        recordId = rec.id,
                                        collectionId = col.id,
                                        title = rec.title(col),
                                        fieldLabel = field.label,
                                        expirationDate = calDate,
                                        daysRemaining = days,
                                        isExpired = days < 0
                                    )
                                )
                            }
                        }
                        else -> {}
                    }
                }
            }

            upcomingExpirations.sortBy { it.daysRemaining }

            return SpaceInsightsReport(
                spaceId = spaceId,
                totalRecords = totalRecords,
                favoriteRecords = favoriteRecords,
                totalAttachments = totalAttachments,
                numericSummaries = numericSummaries,
                upcomingExpirations = upcomingExpirations,
                selectDistributions = selectDistributions
            )
        }
    }
}
