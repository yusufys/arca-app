package app.arca.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.arca.android.model.CalendarDate
import app.arca.android.model.CollectionSchema
import app.arca.android.model.FieldType
import app.arca.android.model.FieldValue
import app.arca.android.model.MoneyValue
import app.arca.android.model.RecordItem
import app.arca.android.model.SchemaEngine
import app.arca.android.model.SpaceStorageMode
import app.arca.android.model.StarterTemplateCatalog
import app.arca.android.model.StarterTemplateID
import app.arca.android.sync.SubscriptionTier
import java.util.UUID

// MARK: - Root Container (Onboarding + 3-Tab Bottom Navigation + Subscreens)

@Composable
fun ArcaRootApp(viewModel: ArcaViewModel) {
    ArcaTheme(
        appearanceMode = viewModel.appearanceMode,
        language = viewModel.language
    ) {
        if (!viewModel.hasCompletedOnboarding) {
            OnboardingFlowScreen(viewModel = viewModel)
        } else {
            var selectedTab by remember { mutableIntStateOf(0) }
            var selectedCollection by remember { mutableStateOf<CollectionSchema?>(null) }
            var selectedRecord by remember { mutableStateOf<RecordItem?>(null) }
            var editingRecordForCollection by remember { mutableStateOf<Pair<CollectionSchema, RecordItem?>?>(null) }

            Scaffold(
                containerColor = MaterialTheme.colorScheme.background,
                bottomBar = {
                    NavigationBar(
                        containerColor = MaterialTheme.colorScheme.surface,
                        tonalElevation = 2.dp
                    ) {
                        NavigationBarItem(
                            selected = selectedTab == 0,
                            onClick = {
                                selectedTab = 0
                                selectedCollection = null
                                selectedRecord = null
                            },
                            icon = { Icon(Icons.Default.Home, contentDescription = null) },
                            label = { Text(ArcaStrings.text("tab.home", viewModel.language)) }
                        )
                        NavigationBarItem(
                            selected = selectedTab == 1,
                            onClick = {
                                selectedTab = 1
                                selectedCollection = null
                                selectedRecord = null
                            },
                            icon = { Icon(Icons.Default.Info, contentDescription = null) },
                            label = { Text(ArcaStrings.text("tab.insights", viewModel.language)) }
                        )
                        NavigationBarItem(
                            selected = selectedTab == 2,
                            onClick = {
                                selectedTab = 2
                                selectedCollection = null
                                selectedRecord = null
                            },
                            icon = { Icon(Icons.Default.Settings, contentDescription = null) },
                            label = { Text(ArcaStrings.text("tab.settings", viewModel.language)) }
                        )
                    }
                }
            ) { innerPadding ->
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                ) {
                    when {
                        editingRecordForCollection != null -> {
                            val (schema, existing) = editingRecordForCollection!!
                            AddEditRecordScreen(
                                viewModel = viewModel,
                                schema = schema,
                                existingRecord = existing,
                                onClose = { editingRecordForCollection = null }
                            )
                        }
                        selectedRecord != null -> {
                            val rec = selectedRecord!!
                            val schema = viewModel.collections.firstOrNull { it.id == rec.collectionId }
                            if (schema != null) {
                                RecordDetailScreen(
                                    viewModel = viewModel,
                                    record = rec,
                                    schema = schema,
                                    onBack = { selectedRecord = null },
                                    onEdit = { editingRecordForCollection = schema to rec }
                                )
                            } else {
                                selectedRecord = null
                            }
                        }
                        selectedCollection != null -> {
                            val col = selectedCollection!!
                            CollectionRecordListScreen(
                                viewModel = viewModel,
                                schema = col,
                                onBack = { selectedCollection = null },
                                onSelectRecord = { selectedRecord = it },
                                onAddRecord = { editingRecordForCollection = col to null }
                            )
                        }
                        selectedTab == 0 -> {
                            HomeScreen(
                                viewModel = viewModel,
                                onOpenCollection = { selectedCollection = it },
                                onOpenRecord = { selectedRecord = it },
                                onQuickAddRecord = { col -> editingRecordForCollection = col to null }
                            )
                        }
                        selectedTab == 1 -> {
                            InsightsScreen(viewModel = viewModel)
                        }
                        else -> {
                            SettingsHubScreen(viewModel = viewModel)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Screens 1–4: 4-Step Onboarding Flow

@Composable
fun OnboardingFlowScreen(viewModel: ArcaViewModel) {
    var step by remember { mutableIntStateOf(1) }
    var selectedMode by remember { mutableStateOf(SpaceStorageMode.ARCA_SYNC) }
    var acceptedCloudTerms by remember { mutableStateOf(false) }
    var includeSensitiveMedicalLocalSpace by remember { mutableStateOf(true) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        // Progress Pills
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            for (s in 1..4) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(5.dp)
                        .clip(CircleShape)
                        .background(if (s <= step) ArcaPalette.AccentTeal else Color.Gray.copy(alpha = 0.25f))
                )
            }
        }

        when (step) {
            1 -> {
                Text(
                    text = ArcaStrings.text("app.tagline", viewModel.language),
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = ArcaStrings.text("app.heroPrompt", viewModel.language),
                    fontSize = 15.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                )
                ArcaSectionCard(title = "Why People Trust Arca") {
                    Text("• Local-First SQLite Foundation: Read, create, search, and edit records offline.")
                    Text("• Friendly Forms, No Database Jargon: Vehicle Maintenance, Warranties, Home Inventory, and Medical Visits.")
                    Text("• Per-Space Privacy Control: Sync general spaces with client-side E2EE while keeping sensitive spaces Local-Only.")
                }
                ArcaPrimaryButton(text = ArcaStrings.text("welcome.getStarted", viewModel.language)) {
                    step = 2
                }
            }
            2 -> {
                Text(
                    text = ArcaStrings.text("storage.title", viewModel.language),
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold
                )
                ArcaSectionCard(title = "Arca Sync (Recommended Default)") {
                    Text("Records live locally first and synchronize across up to 2 devices for free with client-side AES-256-GCM encryption.")
                    ArcaSecondaryButton(
                        text = if (selectedMode == SpaceStorageMode.ARCA_SYNC) "Selected • Arca Sync" else "Choose Arca Sync",
                        onClick = { selectedMode = SpaceStorageMode.ARCA_SYNC }
                    )
                }
                ArcaSectionCard(title = "On This Device Only (No Account Required)") {
                    Text("Records and attachments stay strictly on this phone unless you export a portable .arcaarchive backup.")
                    ArcaSecondaryButton(
                        text = if (selectedMode == SpaceStorageMode.LOCAL_ONLY) "Selected • Local Only" else "Choose Local Only",
                        tint = ArcaPalette.SecondaryEmerald,
                        onClick = { selectedMode = SpaceStorageMode.LOCAL_ONLY }
                    )
                }
                if (selectedMode == SpaceStorageMode.ARCA_SYNC) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = acceptedCloudTerms, onCheckedChange = { acceptedCloudTerms = it })
                        Text(
                            text = "I accept encrypted cloud storage for synced Spaces.",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
                ArcaPrimaryButton(
                    text = "Continue",
                    enabled = selectedMode != SpaceStorageMode.ARCA_SYNC || acceptedCloudTerms
                ) {
                    step = if (selectedMode == SpaceStorageMode.LOCAL_ONLY) 4 else 3
                }
            }
            3 -> {
                Text("Emergency E2EE Recovery Key", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                ArcaSectionCard(
                    title = "Save Your Recovery Key",
                    subtitle = "Account password recovery cannot decrypt your synced records because Arca servers never hold your keys."
                ) {
                    Text(
                        text = viewModel.recoveryKeyPhrase,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                ArcaPrimaryButton(text = "Enroll Device & Continue") { step = 4 }
                ArcaSecondaryButton(
                    text = "Skip & Use Local-Only Mode Instead",
                    modifier = Modifier.fillMaxWidth()
                ) {
                    selectedMode = SpaceStorageMode.LOCAL_ONLY
                    step = 4
                }
            }
            else -> {
                Text("Choose Starter Collections", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                for (template in StarterTemplateCatalog.all) {
                    ArcaSectionCard(
                        title = if (template.isSensitiveLocalDefault) "${template.name} • Sensitive (Local Default)" else template.name,
                        subtitle = template.subtitle
                    ) {
                        template.sensitivityDisclosure?.let { disc ->
                            Text(disc, fontSize = 11.sp, color = ArcaPalette.PlumSensitive)
                        }
                    }
                }
                ArcaPrimaryButton(text = "Open My Spaces") {
                    viewModel.finishOnboarding(
                        defaultMode = selectedMode,
                        selectedTemplates = setOf(
                            StarterTemplateID.VEHICLE_MAINTENANCE,
                            StarterTemplateID.HOME_INVENTORY,
                            StarterTemplateID.WARRANTIES
                        ),
                        createMedicalLocalSpace = includeSensitiveMedicalLocalSpace
                    )
                }
            }
        }
    }
}

// MARK: - Screen 5: Home Screen

@Composable
fun HomeScreen(
    viewModel: ArcaViewModel,
    onOpenCollection: (CollectionSchema) -> Unit,
    onOpenRecord: (RecordItem) -> Unit,
    onQuickAddRecord: (CollectionSchema) -> Unit
) {
    var newSpaceName by remember { mutableStateOf("") }
    var showCreateSpace by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                val modeText = if (viewModel.currentSpace?.storageMode == SpaceStorageMode.ARCA_SYNC) {
                    "ARCA SYNC • E2EE"
                } else {
                    "ON THIS DEVICE ONLY"
                }
                Text(
                    text = modeText,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = ArcaPalette.AccentTeal
                )
                Text(
                    text = viewModel.currentSpace?.name ?: "Arca",
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            viewModel.collectionsInCurrentSpace.firstOrNull()?.let { firstCol ->
                ArcaPillBadge(
                    text = "+ ${ArcaStrings.text("home.quickAddRecord", viewModel.language)}",
                    tint = ArcaPalette.AccentTeal,
                    onClick = { onQuickAddRecord(firstCol) }
                )
            }
        }

        OperationalStateBannerView(state = viewModel.bannerState) {
            viewModel.bannerState = OperationalBannerState.NORMAL
        }

        // Space Switcher Row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            for (space in viewModel.spaces) {
                val isSelected = space.id == viewModel.currentSpace?.id
                val tint = ArcaPalette.fromHex(space.accentHex)
                Surface(
                    color = if (isSelected) tint else MaterialTheme.colorScheme.surface,
                    shape = CircleShape,
                    border = if (isSelected) null else BorderStroke(1.dp, ArcaPalette.LightBorder),
                    modifier = Modifier.clickable { viewModel.selectSpace(space.id) }
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp)
                    ) {
                        Text(
                            text = space.name,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurface
                        )
                        if (space.storageMode == SpaceStorageMode.LOCAL_ONLY) {
                            Spacer(modifier = Modifier.width(5.dp))
                            Icon(
                                imageVector = Icons.Default.Lock,
                                contentDescription = "Local Only",
                                tint = if (isSelected) Color.White else ArcaPalette.SecondaryEmerald,
                                modifier = Modifier.size(12.dp)
                            )
                        }
                    }
                }
            }
            ArcaPillBadge(text = "+ Space", tint = ArcaPalette.SecondaryEmerald) {
                showCreateSpace = !showCreateSpace
            }
        }

        if (showCreateSpace) {
            ArcaSectionCard(title = "Create Independent Space") {
                OutlinedTextField(
                    value = newSpaceName,
                    onValueChange = { newSpaceName = it },
                    label = { Text("Space Name (e.g., Vacation Cabin)") },
                    modifier = Modifier.fillMaxWidth()
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ArcaPrimaryButton(
                        text = "Create Local Space",
                        modifier = Modifier.weight(1f)
                    ) {
                        viewModel.createSpace(newSpaceName, SpaceStorageMode.LOCAL_ONLY)
                        newSpaceName = ""
                        showCreateSpace = false
                    }
                }
            }
        }

        // Search Bar
        OutlinedTextField(
            value = viewModel.globalSearchText,
            onValueChange = { viewModel.globalSearchText = it },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            placeholder = { Text(ArcaStrings.text("home.searchPlaceholder", viewModel.language)) },
            shape = RoundedCornerShape(14.dp),
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        if (viewModel.globalSearchText.isNotBlank()) {
            val matches = viewModel.searchRecords(viewModel.globalSearchText)
            ArcaSectionCard(title = "Search Results (${matches.size})") {
                if (matches.isEmpty()) {
                    Text("No records matched “${viewModel.globalSearchText}”.", fontSize = 13.sp)
                } else {
                    for (rec in matches) {
                        val schema = viewModel.collections.firstOrNull { it.id == rec.collectionId }
                        if (schema != null) {
                            RecordCardRow(record = rec, schema = schema) { onOpenRecord(rec) }
                        }
                    }
                }
            }
        } else {
            // Collections Section
            ArcaSectionCard(title = ArcaStrings.text("home.collections", viewModel.language)) {
                for (col in viewModel.collectionsInCurrentSpace) {
                    val count = viewModel.recordsInCurrentSpace.count { it.collectionId == col.id }
                    val colTint = ArcaPalette.fromHex(col.colorHex)
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(colTint.copy(alpha = 0.08f))
                            .clickable { onOpenCollection(col) }
                            .padding(14.dp)
                    ) {
                        Box(
                            contentAlignment = Alignment.Center,
                            modifier = Modifier
                                .size(38.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .background(colTint)
                        ) {
                            Icon(Icons.Default.Star, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                        }
                        Spacer(modifier = Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(text = col.name, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                            Text(
                                text = "${col.activeFields.size} fields • Schema v${col.schemaVersion}",
                                fontSize = 11.sp,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                            )
                        }
                        ArcaPillBadge(text = "$count", tint = colTint)
                        Spacer(modifier = Modifier.width(6.dp))
                        Icon(Icons.Default.KeyboardArrowRight, contentDescription = null, tint = Color.Gray)
                    }
                }
            }

            // Favorites Section
            if (viewModel.favoriteRecordsInCurrentSpace.isNotEmpty()) {
                ArcaSectionCard(title = ArcaStrings.text("home.favorites", viewModel.language)) {
                    for (rec in viewModel.favoriteRecordsInCurrentSpace) {
                        val schema = viewModel.collections.firstOrNull { it.id == rec.collectionId }
                        if (schema != null) {
                            RecordCardRow(record = rec, schema = schema) { onOpenRecord(rec) }
                        }
                    }
                }
            }

            // Recent Records Section
            ArcaSectionCard(title = ArcaStrings.text("home.recentRecords", viewModel.language)) {
                for (rec in viewModel.recordsInCurrentSpace.take(8)) {
                    val schema = viewModel.collections.firstOrNull { it.id == rec.collectionId }
                    if (schema != null) {
                        RecordCardRow(record = rec, schema = schema) { onOpenRecord(rec) }
                    }
                }
            }
        }
    }
}

@Composable
fun RecordCardRow(
    record: RecordItem,
    schema: CollectionSchema,
    onClick: () -> Unit
) {
    val tint = ArcaPalette.fromHex(schema.colorHex)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.background.copy(alpha = 0.65f))
            .clickable(onClick = onClick)
            .padding(12.dp)
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(text = record.title(schema), fontSize = 14.sp, fontWeight = FontWeight.Bold)
                if (record.isFavorite) {
                    Icon(
                        imageVector = Icons.Default.Favorite,
                        contentDescription = "Pinned",
                        tint = ArcaPalette.WarmAmber,
                        modifier = Modifier.size(13.dp)
                    )
                }
            }
            val sub = record.subtitle(schema)
            if (sub.isNotEmpty()) {
                Text(
                    text = sub,
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
                )
            }
        }
        ArcaPillBadge(text = schema.name, tint = tint)
    }
}

// MARK: - Screen 10: Collection Record List

@Composable
fun CollectionRecordListScreen(
    viewModel: ArcaViewModel,
    schema: CollectionSchema,
    onBack: () -> Unit,
    onSelectRecord: (RecordItem) -> Unit,
    onAddRecord: () -> Unit
) {
    val records = viewModel.recordsInCurrentSpace.filter { it.collectionId == schema.id }
    val tint = ArcaPalette.fromHex(schema.colorHex)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ArcaSecondaryButton(text = "← Back", onClick = onBack)
            Spacer(modifier = Modifier.weight(1f))
            ArcaPillBadge(text = "+ Add Record", tint = tint, onClick = onAddRecord)
        }

        Text(text = schema.name, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Text(
            text = "${records.size} records • ${schema.activeFields.size} active fields (Schema v${schema.schemaVersion})",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
        )

        ArcaSectionCard(title = "Records") {
            if (records.isEmpty()) {
                Text("No records saved in ${schema.name} yet.", fontSize = 13.sp)
                ArcaPrimaryButton(text = "Add First Record", tint = tint, onClick = onAddRecord)
            } else {
                for (rec in records) {
                    RecordCardRow(record = rec, schema = schema) { onSelectRecord(rec) }
                }
            }
        }
    }
}

// MARK: - Screen 11: Add / Edit Record Form

@Composable
fun AddEditRecordScreen(
    viewModel: ArcaViewModel,
    schema: CollectionSchema,
    existingRecord: RecordItem?,
    onClose: () -> Unit
) {
    val draftText = remember {
        mutableStateMapOf<UUID, String>().apply {
            existingRecord?.values?.forEach { (fid, v) ->
                put(fid, v.plainTextSummary())
            }
        }
    }
    var isFavorite by remember { mutableStateOf(existingRecord?.isFavorite ?: false) }
    var validationError by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ArcaSecondaryButton(text = "Cancel", onClick = onClose)
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = if (existingRecord == null) "New ${schema.name}" else "Edit Record",
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.weight(1f))
        }

        validationError?.let { err ->
            ArcaSectionCard(title = "Validation", accentColor = ArcaPalette.DangerRed) {
                Text(err, color = ArcaPalette.DangerRed, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }

        ArcaSectionCard(title = "${schema.name} Fields") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Pin to Favorites", modifier = Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                Switch(checked = isFavorite, onCheckedChange = { isFavorite = it })
            }
            HorizontalDivider()
            for (field in schema.activeFields) {
                OutlinedTextField(
                    value = draftText[field.id] ?: "",
                    onValueChange = { draftText[field.id] = it },
                    label = {
                        Text("${field.label}${if (field.isRequired) " *" else ""} (${field.type.displayLabel})")
                    },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        ArcaPrimaryButton(text = "Save Record") {
            val builtValues = mutableMapOf<UUID, FieldValue>()
            for (field in schema.activeFields) {
                val raw = draftText[field.id]?.trim().orEmpty()
                if (raw.isEmpty()) {
                    builtValues[field.id] = FieldValue.NullValue
                } else {
                    builtValues[field.id] = when (field.type) {
                        FieldType.NUMBER -> raw.toDoubleOrNull()?.let { FieldValue.NumberValue(it) } ?: FieldValue.ShortText(raw)
                        FieldType.CURRENCY -> MoneyValue.fromDecimalString(raw)?.let { FieldValue.CurrencyValue(it) } ?: FieldValue.ShortText(raw)
                        FieldType.DATE -> CalendarDate.fromIsoString(raw)?.let { FieldValue.DateValue(it) } ?: FieldValue.DateValue(CalendarDate.today())
                        FieldType.LONG_TEXT -> FieldValue.LongText(raw)
                        else -> FieldValue.ShortText(raw)
                    }
                }
            }
            val errs = SchemaEngine.validate(builtValues, schema)
            if (errs.isNotEmpty()) {
                validationError = errs.first().reason
            } else {
                viewModel.saveRecord(existingRecord, schema, builtValues, isFavorite)
                onClose()
            }
        }
    }
}

// MARK: - Screen 12: Record Detail Screen

@Composable
fun RecordDetailScreen(
    viewModel: ArcaViewModel,
    record: RecordItem,
    schema: CollectionSchema,
    onBack: () -> Unit,
    onEdit: () -> Unit
) {
    val tint = ArcaPalette.fromHex(schema.colorHex)
    val deepLink = "arca://space/${record.spaceId}/collection/${record.collectionId}/record/${record.id}"

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ArcaSecondaryButton(text = "← ${schema.name}", onClick = onBack)
            Spacer(modifier = Modifier.weight(1f))
            ArcaPillBadge(text = "Edit", tint = tint, onClick = onEdit)
        }

        ArcaSectionCard {
            Text(text = record.title(schema), fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Text(
                text = "${schema.name} • Revision ${record.revision}",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
            )
        }

        ArcaSectionCard(title = "Saved Fields") {
            for (field in schema.activeFields) {
                val v = record.values[field.id] ?: FieldValue.NullValue
                if (!v.isNullOrEmpty) {
                    Column {
                        Text(
                            text = field.label.uppercase(),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f)
                        )
                        Text(text = v.plainTextSummary(field), fontSize = 15.sp, fontWeight = FontWeight.Medium)
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                }
            }
        }

        if (record.allAttachments.isNotEmpty()) {
            ArcaSectionCard(title = "Attachments (SHA-256 Verified)") {
                for (att in record.allAttachments) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.CheckCircle, contentDescription = null, tint = ArcaPalette.SecondaryEmerald)
                        Spacer(modifier = Modifier.width(10.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(att.filename, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                            Text(
                                "SHA-256 ${att.sha256Hex.take(12)}…",
                                fontSize = 11.sp,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                            )
                        }
                    }
                }
            }
        }

        ArcaSectionCard(
            title = "Local QR Asset Tag Deep Link",
            subtitle = "Identifies this record locally by UUID without embedding private content."
        ) {
            Text(text = deepLink, fontFamily = FontFamily.Monospace, fontSize = 11.sp)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ArcaSecondaryButton(
                text = if (record.isFavorite) "Unpin" else "Pin Record",
                modifier = Modifier.weight(1f)
            ) {
                viewModel.toggleFavorite(record.id)
            }
            ArcaSecondaryButton(
                text = "Duplicate",
                modifier = Modifier.weight(1f)
            ) {
                viewModel.duplicateRecord(record)
                onBack()
            }
            ArcaSecondaryButton(
                text = "Delete",
                tint = ArcaPalette.DangerRed,
                modifier = Modifier.weight(1f)
            ) {
                viewModel.deleteRecord(record.id)
                onBack()
            }
        }
    }
}

// MARK: - Screen 13: Insights Screen

@Composable
fun InsightsScreen(viewModel: ArcaViewModel) {
    val spaceRecords = viewModel.recordsInCurrentSpace
    val totalAttachments = spaceRecords.sumOf { it.allAttachments.size }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = ArcaStrings.text("insights.title", viewModel.language),
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold
        )

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            ArcaSectionCard(modifier = Modifier.weight(1f)) {
                Text("${spaceRecords.size}", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = ArcaPalette.AccentTeal)
                Text("Records", fontSize = 11.sp)
            }
            ArcaSectionCard(modifier = Modifier.weight(1f)) {
                Text("${viewModel.favoriteRecordsInCurrentSpace.size}", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = ArcaPalette.WarmAmber)
                Text("Pinned", fontSize = 11.sp)
            }
            ArcaSectionCard(modifier = Modifier.weight(1f)) {
                Text("$totalAttachments", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = ArcaPalette.SecondaryEmerald)
                Text("Files", fontSize = 11.sp)
            }
        }

        ArcaSectionCard(title = "Upcoming Warranty Expirations") {
            Text("• Espresso Machine Pro 300 — Expires 2027-04-12 (Active)", fontSize = 13.sp, fontWeight = FontWeight.Medium)
        }

        ArcaSectionCard(title = "Spending & Valuation Summary") {
            Text("• Home Inventory Total Value: $1,699.00", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Text("• Vehicle Maintenance Logged: $245.00", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

// MARK: - Screens 14–19: Settings Hub, Backups, Sync Conflicts, Active Devices & Subscriptions

@Composable
fun SettingsHubScreen(viewModel: ArcaViewModel) {
    var backupStatus by remember { mutableStateOf<String?>(null) }
    var deviceError by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = ArcaStrings.text("settings.title", viewModel.language),
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold
        )

        // Screen 14: Portable Backups (.arcaarchive)
        ArcaSectionCard(
            title = "Portable Backups (.arcaarchive)",
            subtitle = "Cross-platform archives compatible between Arca iOS and Arca Android."
        ) {
            ArcaPrimaryButton(text = "Export Encrypted Space Backup (.arcaarchive.enc)") {
                val exported = viewModel.exportCurrentSpaceBackup(encrypted = true)
                backupStatus = "Exported verified archive: $exported"
            }
            backupStatus?.let { msg ->
                Text(msg, fontSize = 12.sp, color = ArcaPalette.SecondaryEmerald, fontWeight = FontWeight.SemiBold)
            }
            for (archive in viewModel.exportedArchiveNames) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(archive, fontSize = 12.sp, modifier = Modifier.weight(1f))
                    ArcaPillBadge(text = "Staged Restore", tint = ArcaPalette.SecondaryEmerald) {
                        val restored = viewModel.restoreBackupAsNewSpace(archive)
                        backupStatus = "Restored cleanly into new Space: ${restored.name}"
                    }
                }
            }
        }

        // Screen 15: Sync Status & Preserved Conflicts
        ArcaSectionCard(
            title = "Sync Engine & Preserved Conflicts (${viewModel.syncConflicts.size})",
            subtitle = "Concurrent edits never overwrite each other using wall-clock timestamps."
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Simulate Offline Mode", modifier = Modifier.weight(1f), fontSize = 14.sp)
                Switch(
                    checked = viewModel.isOfflineSimulated,
                    onCheckedChange = {
                        viewModel.isOfflineSimulated = it
                        viewModel.bannerState = if (it) OperationalBannerState.OFFLINE_QUEUED else OperationalBannerState.NORMAL
                    }
                )
            }
            for (conflict in viewModel.syncConflicts) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(conflict.summary, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ArcaSecondaryButton(text = "Keep Local") { viewModel.resolveConflict(conflict.id) }
                        ArcaSecondaryButton(text = "Keep Remote") { viewModel.resolveConflict(conflict.id) }
                    }
                }
            }
            ArcaSecondaryButton(
                text = "Simulate Concurrent Edit Conflict",
                tint = ArcaPalette.PlumSensitive,
                modifier = Modifier.fillMaxWidth()
            ) {
                viewModel.simulateConcurrentConflict()
            }
        }

        // Screen 16: Active Device Management (2-Device Free Limit)
        ArcaSectionCard(
            title = "Active Sync Devices (${viewModel.enrolledDevices.size}/${viewModel.maxAllowedDevices})",
            subtitle = "Revoking a device stops future sync and rotates Space Encryption Keys."
        ) {
            for (dev in viewModel.enrolledDevices) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(dev.deviceName, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    if (!dev.isCurrentDevice) {
                        ArcaPillBadge(text = "Revoke", tint = ArcaPalette.DangerRed) {
                            viewModel.revokeDevice(dev.deviceId)
                            deviceError = null
                        }
                    }
                }
            }
            deviceError?.let { err ->
                Text(err, fontSize = 12.sp, color = ArcaPalette.DangerRed)
            }
            ArcaSecondaryButton(
                text = "Test Enroll 3rd Device",
                modifier = Modifier.fillMaxWidth()
            ) {
                val res = viewModel.enrollDevice("Tablet Android")
                deviceError = res.exceptionOrNull()?.message
            }
        }

        // Screen 18: Subscriptions & Non-Destructive Expiry
        ArcaSectionCard(
            title = "Arca Plan & Google Play Billing",
            subtitle = "Current Tier: ${viewModel.subscriptionTier.name} • Local records are NEVER deleted on expiry."
        ) {
            if (!viewModel.isProSubscriber) {
                ArcaPrimaryButton(text = "Upgrade to Arca Pro ($34.99/yr • Up to 10 Devices)") {
                    viewModel.subscriptionTier = SubscriptionTier.PRO
                }
            } else {
                ArcaSecondaryButton(
                    text = "Simulate Subscription Expiry (Verify Zero Data Loss)",
                    tint = ArcaPalette.WarmAmber,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    viewModel.subscriptionTier = SubscriptionTier.FREE
                }
            }
        }

        // Screen 19: Appearance, Language (EN / AR RTL / TR) & E2EE Recovery Key
        ArcaSectionCard(title = "Appearance & Language (RTL Support)") {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (lang in AppLanguage.entries) {
                    ArcaPillBadge(
                        text = lang.displayName,
                        tint = if (viewModel.language == lang) ArcaPalette.AccentTeal else Color.Gray
                    ) {
                        viewModel.language = lang
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (mode in AppAppearanceMode.entries) {
                    ArcaPillBadge(
                        text = mode.label,
                        tint = if (viewModel.appearanceMode == mode) ArcaPalette.AccentTeal else Color.Gray
                    ) {
                        viewModel.appearanceMode = mode
                    }
                }
            }
            ArcaSecondaryButton(
                text = "Replay 4-Step Welcome Onboarding",
                modifier = Modifier.fillMaxWidth()
            ) {
                viewModel.hasCompletedOnboarding = false
            }
        }
    }
}

// MARK: - Jetpack Compose @Preview Functions (For Android Compose Preview Sidecar)

@Preview(showBackground = true, widthDp = 393, heightDp = 852)
@Composable
fun ArcaHomeScreenPreview() {
    val vm = remember { ArcaViewModel(startWithCompletedOnboarding = true) }
    ArcaRootApp(viewModel = vm)
}

@Preview(showBackground = true, widthDp = 393, heightDp = 852)
@Composable
fun ArcaOnboardingScreenPreview() {
    val vm = remember { ArcaViewModel(startWithCompletedOnboarding = false) }
    ArcaRootApp(viewModel = vm)
}
