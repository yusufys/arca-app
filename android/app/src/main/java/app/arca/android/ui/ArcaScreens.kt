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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
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
import app.arca.android.model.AttachmentReference
import app.arca.android.model.CalendarDate
import app.arca.android.model.CollectionSchema
import app.arca.android.model.FieldConversionPreview
import app.arca.android.model.FieldDefinition
import app.arca.android.model.FieldDeletionRetentionPolicy
import app.arca.android.model.FieldType
import app.arca.android.model.FieldValue
import app.arca.android.model.MoneyValue
import app.arca.android.model.RecordItem
import app.arca.android.model.RecordSortCriterion
import app.arca.android.model.SchemaEngine
import app.arca.android.model.SelectOption
import app.arca.android.model.SpaceMetadata
import app.arca.android.model.SpaceStorageMode
import app.arca.android.model.StarterTemplate
import app.arca.android.model.StarterTemplateCatalog
import app.arca.android.model.StarterTemplateID
import app.arca.android.sync.SubscriptionTier
import java.time.Instant
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
            var managingFieldsForCollection by remember { mutableStateOf<CollectionSchema?>(null) }

            Scaffold(
                containerColor = MaterialTheme.colorScheme.background,
                bottomBar = {
                    NavigationBar(
                        containerColor = MaterialTheme.colorScheme.surface,
                        tonalElevation = 2.dp
                    ) {
                        NavigationBarItem(
                            selected = selectedTab == 0 && managingFieldsForCollection == null && editingRecordForCollection == null && selectedRecord == null && selectedCollection == null,
                            onClick = {
                                selectedTab = 0
                                selectedCollection = null
                                selectedRecord = null
                                editingRecordForCollection = null
                                managingFieldsForCollection = null
                            },
                            icon = { Icon(Icons.Default.Home, contentDescription = null) },
                            label = { Text(ArcaStrings.text("tab.home", viewModel.language)) }
                        )
                        NavigationBarItem(
                            selected = selectedTab == 1 && managingFieldsForCollection == null && editingRecordForCollection == null && selectedRecord == null && selectedCollection == null,
                            onClick = {
                                selectedTab = 1
                                selectedCollection = null
                                selectedRecord = null
                                editingRecordForCollection = null
                                managingFieldsForCollection = null
                            },
                            icon = { Icon(Icons.Default.Info, contentDescription = null) },
                            label = { Text(ArcaStrings.text("tab.insights", viewModel.language)) }
                        )
                        NavigationBarItem(
                            selected = selectedTab == 2 && managingFieldsForCollection == null && editingRecordForCollection == null && selectedRecord == null && selectedCollection == null,
                            onClick = {
                                selectedTab = 2
                                selectedCollection = null
                                selectedRecord = null
                                editingRecordForCollection = null
                                managingFieldsForCollection = null
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
                        managingFieldsForCollection != null -> {
                            val targetSchema = viewModel.collections.firstOrNull { it.id == managingFieldsForCollection!!.id }
                                ?: managingFieldsForCollection!!
                            FieldEditorScreen(
                                viewModel = viewModel,
                                schema = targetSchema,
                                onBack = {
                                    managingFieldsForCollection = null
                                    selectedCollection = viewModel.collections.firstOrNull { it.id == targetSchema.id }
                                }
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
                            val col = viewModel.collections.firstOrNull { it.id == selectedCollection!!.id } ?: selectedCollection!!
                            CollectionRecordListScreen(
                                viewModel = viewModel,
                                schema = col,
                                onBack = { selectedCollection = null },
                                onSelectRecord = { selectedRecord = it },
                                onAddRecord = { editingRecordForCollection = col to null },
                                onManageFields = { managingFieldsForCollection = col }
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
    var showSpacesDialog by remember { mutableStateOf(false) }
    var showTemplateGallery by remember { mutableStateOf(false) }
    var showCustomCollectionBuilder by remember { mutableStateOf(false) }

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
                    text = "$modeText (TAP TO SWITCH)",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (viewModel.currentSpace?.storageMode == SpaceStorageMode.ARCA_SYNC) ArcaPalette.AccentTeal else ArcaPalette.SecondaryEmerald,
                    modifier = Modifier.clickable {
                        viewModel.currentSpace?.id?.let { viewModel.toggleSpaceStorageMode(it) }
                    }
                )
                Text(
                    text = viewModel.currentSpace?.name ?: "Arca",
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ArcaPillBadge(
                    text = "Spaces",
                    tint = ArcaPalette.AccentTeal,
                    onClick = { showSpacesDialog = true }
                )
                viewModel.collectionsInCurrentSpace.firstOrNull()?.let { firstCol ->
                    ArcaPillBadge(
                        text = "+ Quick Add",
                        tint = ArcaPalette.SecondaryEmerald,
                        onClick = { onQuickAddRecord(firstCol) }
                    )
                }
            }
        }

        OperationalStateBannerView(state = viewModel.bannerState) {
            viewModel.bannerState = OperationalBannerState.NORMAL
        }

        // Space Quick Switcher Row
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
                showSpacesDialog = true
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
            // Collections Section Header with "+ Templates" and "+ Custom" buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "${ArcaStrings.text("home.collections", viewModel.language)} (${viewModel.collectionsInCurrentSpace.size})",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f)
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    ArcaPillBadge(
                        text = "+ Templates",
                        tint = ArcaPalette.AccentTeal,
                        onClick = { showTemplateGallery = true }
                    )
                    ArcaPillBadge(
                        text = "+ Custom",
                        tint = ArcaPalette.SecondaryEmerald,
                        onClick = { showCustomCollectionBuilder = true }
                    )
                }
            }

            if (viewModel.collectionsInCurrentSpace.isEmpty()) {
                ArcaSectionCard(
                    title = "No Collections in this Space",
                    subtitle = "Organize this Space by choosing ready-made templates or creating your own custom schema."
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        ArcaPrimaryButton(
                            text = "+ Templates",
                            tint = ArcaPalette.AccentTeal,
                            modifier = Modifier.weight(1f),
                            onClick = { showTemplateGallery = true }
                        )
                        ArcaPrimaryButton(
                            text = "+ Custom Collection",
                            tint = ArcaPalette.SecondaryEmerald,
                            modifier = Modifier.weight(1f),
                            onClick = { showCustomCollectionBuilder = true }
                        )
                    }
                }
            } else {
                // 2-Column Grid of Collection Cards
                val cols = viewModel.collectionsInCurrentSpace
                val chunkedCols = cols.chunked(2)
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (row in chunkedCols) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            for (col in row) {
                                val recCount = viewModel.recordsInCurrentSpace.count { it.collectionId == col.id }
                                val colTint = ArcaPalette.fromHex(col.colorHex)
                                Surface(
                                    color = MaterialTheme.colorScheme.surface,
                                    shape = RoundedCornerShape(14.dp),
                                    border = BorderStroke(1.dp, ArcaPalette.LightBorder),
                                    modifier = Modifier
                                        .weight(1f)
                                        .clickable { onOpenCollection(col) }
                                ) {
                                    Column(
                                        modifier = Modifier.padding(14.dp),
                                        verticalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Box(
                                                contentAlignment = Alignment.Center,
                                                modifier = Modifier
                                                    .size(36.dp)
                                                    .clip(RoundedCornerShape(8.dp))
                                                    .background(colTint)
                                            ) {
                                                Icon(
                                                    Icons.Default.Star,
                                                    contentDescription = null,
                                                    tint = Color.White,
                                                    modifier = Modifier.size(18.dp)
                                                )
                                            }
                                            ArcaPillBadge(text = "$recCount", tint = colTint)
                                        }
                                        Text(
                                            text = col.name,
                                            fontSize = 15.sp,
                                            fontWeight = FontWeight.Bold,
                                            maxLines = 1
                                        )
                                        Text(
                                            text = "${col.activeFields.size} fields • v${col.schemaVersion}",
                                            fontSize = 11.sp,
                                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                                        )
                                    }
                                }
                            }
                            if (row.size == 1) {
                                Spacer(modifier = Modifier.weight(1f))
                            }
                        }
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
                val recs = viewModel.recordsInCurrentSpace.take(8)
                if (recs.isEmpty()) {
                    Text("No records created yet in this space.", fontSize = 13.sp, color = Color.Gray)
                } else {
                    for (rec in recs) {
                        val schema = viewModel.collections.firstOrNull { it.id == rec.collectionId }
                        if (schema != null) {
                            RecordCardRow(record = rec, schema = schema) { onOpenRecord(rec) }
                        }
                    }
                }
            }
        }
    }

    if (showSpacesDialog) {
        ManageSpacesDialog(
            viewModel = viewModel,
            onDismiss = { showSpacesDialog = false }
        )
    }

    if (showTemplateGallery) {
        TemplateGalleryDialog(
            viewModel = viewModel,
            onDismiss = { showTemplateGallery = false },
            onTemplateSelected = { schema ->
                showTemplateGallery = false
                onOpenCollection(schema)
            }
        )
    }

    if (showCustomCollectionBuilder) {
        ManualCollectionBuilderDialog(
            viewModel = viewModel,
            onDismiss = { showCustomCollectionBuilder = false },
            onCollectionCreated = { schema ->
                showCustomCollectionBuilder = false
                onOpenCollection(schema)
            }
        )
    }
}

// MARK: - Manage Spaces Dialog

@Composable
fun ManageSpacesDialog(
    viewModel: ArcaViewModel,
    onDismiss: () -> Unit
) {
    var newSpaceName by remember { mutableStateOf("") }
    var newSpaceMode by remember { mutableStateOf(SpaceStorageMode.ARCA_SYNC) }
    var spaceToRename by remember { mutableStateOf<Pair<UUID, String>?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Spaces Management", fontWeight = FontWeight.Bold, fontSize = 20.sp) },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Text(
                    text = "Each Space is an isolated database with its own encryption key and storage mode.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                )

                Text("Active Spaces:", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                for (space in viewModel.spaces) {
                    val isCurrent = space.id == viewModel.currentSpace?.id
                    Surface(
                        color = MaterialTheme.colorScheme.background,
                        shape = RoundedCornerShape(10.dp),
                        border = BorderStroke(1.dp, if (isCurrent) ArcaPalette.AccentTeal else ArcaPalette.LightBorder),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    text = space.name,
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 14.sp,
                                    modifier = Modifier.weight(1f)
                                )
                                ArcaPillBadge(
                                    text = if (space.storageMode == SpaceStorageMode.ARCA_SYNC) "E2EE Cloud" else "Local Only",
                                    tint = if (space.storageMode == SpaceStorageMode.ARCA_SYNC) ArcaPalette.AccentTeal else ArcaPalette.SecondaryEmerald
                                )
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (!isCurrent) {
                                    ArcaSecondaryButton(
                                        text = "Switch",
                                        onClick = { viewModel.selectSpace(space.id) }
                                    )
                                }
                                ArcaSecondaryButton(
                                    text = "Rename",
                                    onClick = { spaceToRename = Pair(space.id, space.name) }
                                )
                                if (viewModel.spaces.size > 1) {
                                    ArcaSecondaryButton(
                                        text = "Delete",
                                        tint = ArcaPalette.DangerRed,
                                        onClick = { viewModel.deleteSpace(space.id) }
                                    )
                                }
                            }
                        }
                    }
                }

                if (spaceToRename != null) {
                    var editName by remember(spaceToRename) { mutableStateOf(spaceToRename!!.second) }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = editName,
                            onValueChange = { editName = it },
                            label = { Text("New Name") },
                            modifier = Modifier.weight(1f)
                        )
                        ArcaPrimaryButton(text = "Save") {
                            viewModel.renameSpace(spaceToRename!!.first, editName)
                            spaceToRename = null
                        }
                    }
                }

                HorizontalDivider()

                Text("Create New Space:", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                OutlinedTextField(
                    value = newSpaceName,
                    onValueChange = { newSpaceName = it },
                    label = { Text("Space Name (e.g. Travel Vault)") },
                    modifier = Modifier.fillMaxWidth()
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ArcaPillBadge(
                        text = if (newSpaceMode == SpaceStorageMode.ARCA_SYNC) "✓ Arca Sync" else "Arca Sync",
                        tint = if (newSpaceMode == SpaceStorageMode.ARCA_SYNC) ArcaPalette.AccentTeal else Color.Gray,
                        onClick = { newSpaceMode = SpaceStorageMode.ARCA_SYNC }
                    )
                    ArcaPillBadge(
                        text = if (newSpaceMode == SpaceStorageMode.LOCAL_ONLY) "✓ Local Only" else "Local Only",
                        tint = if (newSpaceMode == SpaceStorageMode.LOCAL_ONLY) ArcaPalette.SecondaryEmerald else Color.Gray,
                        onClick = { newSpaceMode = SpaceStorageMode.LOCAL_ONLY }
                    )
                }
                ArcaPrimaryButton(
                    text = "Create Space",
                    enabled = newSpaceName.isNotBlank()
                ) {
                    viewModel.createSpace(name = newSpaceName, storageMode = newSpaceMode)
                    newSpaceName = ""
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Done", fontWeight = FontWeight.Bold) }
        }
    )
}

// MARK: - Template Gallery Dialog (All 6 Templates + AI JSON Importer)

@Composable
fun TemplateGalleryDialog(
    viewModel: ArcaViewModel,
    onDismiss: () -> Unit,
    onTemplateSelected: (CollectionSchema) -> Unit
) {
    var pastedJson by remember { mutableStateOf("") }
    var importError by remember { mutableStateOf<String?>(null) }
    var sensitiveTemplatePrompt by remember { mutableStateOf<StarterTemplate?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Collection Templates", fontWeight = FontWeight.Bold, fontSize = 20.sp) },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Text(
                    text = "Add verified starter templates with pre-configured typed fields, or import custom JSON schema.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                )

                for (template in StarterTemplateCatalog.all) {
                    val tint = ArcaPalette.fromHex(template.colorHex)
                    Surface(
                        color = MaterialTheme.colorScheme.background,
                        shape = RoundedCornerShape(12.dp),
                        border = BorderStroke(1.dp, ArcaPalette.LightBorder),
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                if (template.isSensitiveLocalDefault) {
                                    sensitiveTemplatePrompt = template
                                } else {
                                    val schema = viewModel.addCollectionFromTemplate(template)
                                    onTemplateSelected(schema)
                                }
                            }
                    ) {
                        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    text = template.name,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.weight(1f)
                                )
                                if (template.isSensitiveLocalDefault) {
                                    ArcaPillBadge(text = "Sensitive (Local)", tint = ArcaPalette.PlumSensitive)
                                } else {
                                    ArcaPillBadge(text = "Ready to Use", tint = tint)
                                }
                            }
                            Text(
                                text = template.subtitle,
                                fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
                            )
                        }
                    }
                }

                HorizontalDivider()

                Text("AI-Assisted JSON Schema Importer", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Text(
                    text = "Paste collection schema generated by ChatGPT or Claude to build instant forms.",
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                )

                OutlinedTextField(
                    value = pastedJson,
                    onValueChange = {
                        pastedJson = it
                        importError = null
                    },
                    label = { Text("Paste Schema JSON") },
                    placeholder = { Text("{\n  \"name\": \"Books\",\n  \"fields\": [...]\n}") },
                    minLines = 3,
                    maxLines = 6,
                    modifier = Modifier.fillMaxWidth()
                )

                importError?.let { err ->
                    Text(err, color = ArcaPalette.DangerRed, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    ArcaSecondaryButton(
                        text = "Copy Sample AI Prompt",
                        modifier = Modifier.weight(1f)
                    ) {
                        pastedJson = SchemaEngine.chatGptSchemaPrompt("Board Games & Valuables")
                    }
                    ArcaPrimaryButton(
                        text = "Import Schema",
                        modifier = Modifier.weight(1f),
                        enabled = pastedJson.isNotBlank()
                    ) {
                        val res = viewModel.importCollectionSchemaFromJson(pastedJson)
                        res.onSuccess { schema ->
                            onTemplateSelected(schema)
                        }.onFailure { err ->
                            importError = err.message ?: "Failed to import schema JSON"
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Close") }
        }
    )

    sensitiveTemplatePrompt?.let { tmpl ->
        AlertDialog(
            onDismissRequest = { sensitiveTemplatePrompt = null },
            title = { Text("Sensitive Collection Posture", fontWeight = FontWeight.Bold) },
            text = {
                Text(
                    tmpl.sensitivityDisclosure
                        ?: "Medical Visits defaults to Local-Only storage so health records stay strictly on this device.",
                    fontSize = 13.sp
                )
            },
            confirmButton = {
                ArcaPrimaryButton(text = "Add to Dedicated Local Space") {
                    val schema = viewModel.addCollectionFromTemplate(tmpl, inDedicatedLocalSpace = true)
                    sensitiveTemplatePrompt = null
                    onTemplateSelected(schema)
                }
            },
            dismissButton = {
                ArcaSecondaryButton(text = "Add to Current Space") {
                    val schema = viewModel.addCollectionFromTemplate(tmpl, inDedicatedLocalSpace = false)
                    sensitiveTemplatePrompt = null
                    onTemplateSelected(schema)
                }
            }
        )
    }
}

// MARK: - Manual Custom Collection Builder Dialog

@Composable
fun ManualCollectionBuilderDialog(
    viewModel: ArcaViewModel,
    onDismiss: () -> Unit,
    onCollectionCreated: (CollectionSchema) -> Unit
) {
    var collectionName by remember { mutableStateOf("") }
    var selectedColor by remember { mutableStateOf("#1F5673") }
    val draftFields = remember {
        mutableStateListOf(
            FieldDefinition(label = "Title", type = FieldType.SHORT_TEXT, isRequired = true, sortOrder = 0, isPrimaryTitle = true),
            FieldDefinition(label = "Date", type = FieldType.DATE, isRequired = false, sortOrder = 1),
            FieldDefinition(label = "Notes", type = FieldType.LONG_TEXT, isRequired = false, sortOrder = 2)
        )
    }

    var newFieldLabel by remember { mutableStateOf("") }
    var newFieldType by remember { mutableStateOf(FieldType.SHORT_TEXT) }
    var newFieldRequired by remember { mutableStateOf(false) }
    var newFieldOptionsText by remember { mutableStateOf("") }
    var validationError by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Build Custom Collection", fontWeight = FontWeight.Bold, fontSize = 20.sp) },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                OutlinedTextField(
                    value = collectionName,
                    onValueChange = { collectionName = it },
                    label = { Text("Collection Name (e.g. Wine Cellar)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                Text("Theme Accent:", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val colors = listOf("#1F5673", "#2B5B84", "#3A6B5C", "#8C5A2B", "#7A3E58", "#5E4B72")
                    for (c in colors) {
                        Box(
                            modifier = Modifier
                                .size(28.dp)
                                .clip(CircleShape)
                                .background(ArcaPalette.fromHex(c))
                                .clickable { selectedColor = c }
                        ) {
                            if (selectedColor == c) {
                                Box(
                                    modifier = Modifier
                                        .size(10.dp)
                                        .clip(CircleShape)
                                        .background(Color.White)
                                        .align(Alignment.Center)
                                )
                            }
                        }
                    }
                }

                Text("Draft Fields (${draftFields.size}):", fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                for ((idx, field) in draftFields.withIndex()) {
                    Surface(
                        color = MaterialTheme.colorScheme.background,
                        shape = RoundedCornerShape(8.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.padding(8.dp)
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "${field.label}${if (field.isPrimaryTitle) " (Primary Title)" else ""}",
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 13.sp
                                )
                                Text(
                                    text = "${field.type.displayLabel}${if (field.isRequired) " • Required" else ""}",
                                    fontSize = 11.sp,
                                    color = Color.Gray
                                )
                            }
                            if (draftFields.size > 1 && !field.isPrimaryTitle) {
                                ArcaPillBadge(text = "✕", tint = ArcaPalette.DangerRed) {
                                    draftFields.removeAt(idx)
                                }
                            }
                        }
                    }
                }

                HorizontalDivider()

                Text("Add Custom Field:", fontSize = 14.sp, fontWeight = FontWeight.Bold)
                OutlinedTextField(
                    value = newFieldLabel,
                    onValueChange = { newFieldLabel = it },
                    label = { Text("Field Label (e.g. Serial #, Rating)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                Text("Field Type:", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    for (t in FieldType.entries) {
                        ArcaPillBadge(
                            text = t.displayLabel,
                            tint = if (newFieldType == t) ArcaPalette.AccentTeal else Color.Gray,
                            onClick = { newFieldType = t }
                        )
                    }
                }

                if (newFieldType == FieldType.SINGLE_SELECT || newFieldType == FieldType.MULTI_SELECT) {
                    OutlinedTextField(
                        value = newFieldOptionsText,
                        onValueChange = { newFieldOptionsText = it },
                        label = { Text("Options (comma-separated, e.g. Red, White, Rose)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                }

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Is Required Field", modifier = Modifier.weight(1f), fontSize = 13.sp)
                    Switch(checked = newFieldRequired, onCheckedChange = { newFieldRequired = it })
                }

                ArcaSecondaryButton(
                    text = "+ Add Field to Draft",
                    modifier = Modifier.fillMaxWidth()
                ) {
                    val trimmed = newFieldLabel.trim()
                    if (trimmed.isNotEmpty()) {
                        val options = if (newFieldType == FieldType.SINGLE_SELECT || newFieldType == FieldType.MULTI_SELECT) {
                            newFieldOptionsText.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                                .map { SelectOption(id = it.lowercase().replace(" ", "_"), label = it) }
                        } else emptyList()

                        draftFields.add(
                            FieldDefinition(
                                id = UUID.randomUUID(),
                                label = trimmed,
                                type = newFieldType,
                                isRequired = newFieldRequired,
                                sortOrder = draftFields.size,
                                options = options
                            )
                        )
                        newFieldLabel = ""
                        newFieldOptionsText = ""
                        newFieldRequired = false
                    }
                }

                validationError?.let { err ->
                    Text(err, color = ArcaPalette.DangerRed, fontSize = 12.sp)
                }
            }
        },
        confirmButton = {
            ArcaPrimaryButton(text = "Create Collection") {
                val trimmedName = collectionName.trim()
                if (trimmedName.isEmpty()) {
                    validationError = "Please enter a collection name"
                } else if (draftFields.isEmpty()) {
                    validationError = "At least one field is required"
                } else {
                    val schema = viewModel.createCustomCollection(
                        name = trimmedName,
                        iconName = "folder",
                        colorHex = selectedColor,
                        fields = draftFields.toList()
                    )
                    onCollectionCreated(schema)
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

// MARK: - Record Card Row

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
    onAddRecord: () -> Unit,
    onManageFields: () -> Unit
) {
    var searchText by remember { mutableStateOf("") }
    var sortCriterion by remember { mutableStateOf(RecordSortCriterion.UPDATED_DESC) }
    var favoritesOnly by remember { mutableStateOf(false) }
    var hasAttachmentsOnly by remember { mutableStateOf(false) }
    var selectedOptionFilter by remember { mutableStateOf<Pair<UUID, String>?>(null) }

    val tint = ArcaPalette.fromHex(schema.colorHex)
    val filteredRecords = viewModel.queryRecords(
        collectionId = schema.id,
        searchText = searchText,
        favoritesOnly = favoritesOnly,
        hasAttachmentsOnly = hasAttachmentsOnly,
        selectOptionFilter = selectedOptionFilter,
        sort = sortCriterion
    )

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
            ArcaPillBadge(text = "Manage Fields", tint = ArcaPalette.AccentTeal, onClick = onManageFields)
            Spacer(modifier = Modifier.width(8.dp))
            ArcaPillBadge(text = "+ Add Record", tint = tint, onClick = onAddRecord)
        }

        Column {
            Text(text = schema.name, fontSize = 24.sp, fontWeight = FontWeight.Bold)
            Text(
                text = "${filteredRecords.size} records • ${schema.activeFields.size} active fields (Schema v${schema.schemaVersion})",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
            )
        }

        // Search in Collection
        OutlinedTextField(
            value = searchText,
            onValueChange = { searchText = it },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            placeholder = { Text("Filter ${schema.name} records…") },
            shape = RoundedCornerShape(12.dp),
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        // Filter & Sort Chips Row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Sort Selector Chip
            ArcaPillBadge(
                text = "Sort: ${sortCriterion.displayLabel}",
                tint = ArcaPalette.AccentTeal,
                onClick = {
                    sortCriterion = when (sortCriterion) {
                        RecordSortCriterion.UPDATED_DESC -> RecordSortCriterion.UPDATED_ASC
                        RecordSortCriterion.UPDATED_ASC -> RecordSortCriterion.TITLE_ASC
                        RecordSortCriterion.TITLE_ASC -> RecordSortCriterion.TITLE_DESC
                        RecordSortCriterion.TITLE_DESC -> RecordSortCriterion.UPDATED_DESC
                    }
                }
            )

            // Pinned Filter Chip
            ArcaPillBadge(
                text = if (favoritesOnly) "★ Pinned Only" else "Pinned",
                tint = if (favoritesOnly) ArcaPalette.WarmAmber else Color.Gray,
                onClick = { favoritesOnly = !favoritesOnly }
            )

            // Files Filter Chip
            ArcaPillBadge(
                text = if (hasAttachmentsOnly) "📎 With Files Only" else "With Files",
                tint = if (hasAttachmentsOnly) ArcaPalette.SecondaryEmerald else Color.Gray,
                onClick = { hasAttachmentsOnly = !hasAttachmentsOnly }
            )

            // Dynamic Select Option Chips
            val singleSelectField = schema.activeFields.firstOrNull { it.type == FieldType.SINGLE_SELECT }
            if (singleSelectField != null) {
                for (opt in singleSelectField.options) {
                    val isSelected = selectedOptionFilter?.second == opt.id
                    ArcaPillBadge(
                        text = opt.label,
                        tint = if (isSelected) tint else Color.Gray,
                        onClick = {
                            selectedOptionFilter = if (isSelected) null else Pair(singleSelectField.id, opt.id)
                        }
                    )
                }
            }
        }

        ArcaSectionCard(title = "Records (${filteredRecords.size})") {
            if (filteredRecords.isEmpty()) {
                Text("No records match the selected criteria.", fontSize = 13.sp)
                ArcaPrimaryButton(text = "+ Add Record", tint = tint, onClick = onAddRecord)
            } else {
                for (rec in filteredRecords) {
                    RecordCardRow(record = rec, schema = schema) { onSelectRecord(rec) }
                }
            }
        }
    }
}

// MARK: - Field Editor Screen (Schema Evolution, Reordering, Renaming, Conversion, Archiving)

@Composable
fun FieldEditorScreen(
    viewModel: ArcaViewModel,
    schema: CollectionSchema,
    onBack: () -> Unit
) {
    var fieldToRename by remember { mutableStateOf<FieldDefinition?>(null) }
    var fieldToConvert by remember { mutableStateOf<FieldDefinition?>(null) }

    var newLabel by remember { mutableStateOf("") }
    var newType by remember { mutableStateOf(FieldType.SHORT_TEXT) }
    var newRequired by remember { mutableStateOf(false) }
    var newOptionsText by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ArcaSecondaryButton(text = "← Back to Collection", onClick = onBack)
            Spacer(modifier = Modifier.weight(1f))
            ArcaPillBadge(text = "Schema v${schema.schemaVersion}", tint = ArcaPalette.AccentTeal)
        }

        Column {
            Text(text = "Manage Fields • ${schema.name}", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Text(
                text = "Add, reorder, rename, dry-run convert types, and archive fields safely.",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
            )
        }

        // Active Fields
        ArcaSectionCard(title = "Active Fields (${schema.activeFields.size})") {
            val active = schema.activeFields
            for ((idx, field) in active.withIndex()) {
                Surface(
                    color = MaterialTheme.colorScheme.background,
                    shape = RoundedCornerShape(10.dp),
                    border = BorderStroke(1.dp, ArcaPalette.LightBorder),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "${idx + 1}. ${field.label}",
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp,
                                modifier = Modifier.weight(1f)
                            )
                            ArcaPillBadge(text = field.type.displayLabel, tint = ArcaPalette.AccentTeal)
                            if (field.isRequired) {
                                Spacer(modifier = Modifier.width(4.dp))
                                ArcaPillBadge(text = "Required", tint = ArcaPalette.WarmAmber)
                            }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            ArcaSecondaryButton(
                                text = "↑",
                                enabled = idx > 0,
                                onClick = { viewModel.moveField(schema.id, idx, -1) }
                            )
                            ArcaSecondaryButton(
                                text = "↓",
                                enabled = idx < active.lastIndex,
                                onClick = { viewModel.moveField(schema.id, idx, 1) }
                            )
                            ArcaSecondaryButton(
                                text = "Rename",
                                onClick = { fieldToRename = field }
                            )
                            ArcaSecondaryButton(
                                text = "Convert Type",
                                onClick = { fieldToConvert = field }
                            )
                            ArcaSecondaryButton(
                                text = "Archive",
                                onClick = {
                                    viewModel.archiveOrRemoveField(
                                        schema.id,
                                        field.id,
                                        FieldDeletionRetentionPolicy.ARCHIVE_AND_RETAIN_VALUES
                                    )
                                }
                            )
                            ArcaSecondaryButton(
                                text = "Purge",
                                tint = ArcaPalette.DangerRed,
                                onClick = {
                                    viewModel.archiveOrRemoveField(
                                        schema.id,
                                        field.id,
                                        FieldDeletionRetentionPolicy.PERMANENTLY_PURGE_VALUES
                                    )
                                }
                            )
                        }
                    }
                }
            }
        }

        // Archived Fields (Recoverable)
        if (schema.archivedFields.isNotEmpty()) {
            ArcaSectionCard(
                title = "Archived Fields (${schema.archivedFields.size})",
                subtitle = "Historical record values are preserved and can be restored anytime."
            ) {
                for (field in schema.archivedFields) {
                    Surface(
                        color = MaterialTheme.colorScheme.background,
                        shape = RoundedCornerShape(10.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.padding(10.dp)
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(field.label, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                Text("${field.type.displayLabel} • Archived", fontSize = 11.sp, color = Color.Gray)
                            }
                            ArcaPrimaryButton(text = "Restore") {
                                viewModel.restoreArchivedField(schema.id, field.id)
                            }
                        }
                    }
                }
            }
        }

        // Add New Field Card
        ArcaSectionCard(title = "Add New Field to ${schema.name}") {
            OutlinedTextField(
                value = newLabel,
                onValueChange = { newLabel = it },
                label = { Text("Field Label (e.g. Mileage, Warranty Provider)") },
                modifier = Modifier.fillMaxWidth()
            )

            Text("Field Type:", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                for (t in FieldType.entries) {
                    ArcaPillBadge(
                        text = t.displayLabel,
                        tint = if (newType == t) ArcaPalette.AccentTeal else Color.Gray,
                        onClick = { newType = t }
                    )
                }
            }

            if (newType == FieldType.SINGLE_SELECT || newType == FieldType.MULTI_SELECT) {
                OutlinedTextField(
                    value = newOptionsText,
                    onValueChange = { newOptionsText = it },
                    label = { Text("Options (comma-separated)") },
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Is Required Field", modifier = Modifier.weight(1f), fontSize = 13.sp)
                Switch(checked = newRequired, onCheckedChange = { newRequired = it })
            }

            ArcaPrimaryButton(
                text = "+ Add Field to Collection",
                enabled = newLabel.isNotBlank()
            ) {
                val opts = if (newType == FieldType.SINGLE_SELECT || newType == FieldType.MULTI_SELECT) {
                    newOptionsText.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                        .map { SelectOption(id = it.lowercase().replace(" ", "_"), label = it) }
                } else emptyList()

                viewModel.addField(
                    collectionId = schema.id,
                    label = newLabel,
                    type = newType,
                    isRequired = newRequired,
                    options = opts
                )
                newLabel = ""
                newOptionsText = ""
                newRequired = false
            }
        }
    }

    // Rename Field Dialog
    fieldToRename?.let { field ->
        var renameInput by remember(field) { mutableStateOf(field.label) }
        AlertDialog(
            onDismissRequest = { fieldToRename = null },
            title = { Text("Rename Field") },
            text = {
                OutlinedTextField(
                    value = renameInput,
                    onValueChange = { renameInput = it },
                    label = { Text("Field Label") },
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                ArcaPrimaryButton(text = "Save") {
                    viewModel.renameField(schema.id, field.id, renameInput)
                    fieldToRename = null
                }
            },
            dismissButton = {
                TextButton(onClick = { fieldToRename = null }) { Text("Cancel") }
            }
        )
    }

    // Convert Field Type Dialog with Dry-Run Preview
    fieldToConvert?.let { field ->
        var targetType by remember(field) { mutableStateOf(FieldType.SHORT_TEXT) }
        val preview = viewModel.previewFieldConversion(schema.id, field, targetType)

        AlertDialog(
            onDismissRequest = { fieldToConvert = null },
            title = { Text("Convert Field Type", fontWeight = FontWeight.Bold) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Converting “${field.label}” (${field.type.displayLabel}) to:", fontSize = 13.sp)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        for (t in FieldType.entries) {
                            if (t != field.type) {
                                ArcaPillBadge(
                                    text = t.displayLabel,
                                    tint = if (targetType == t) ArcaPalette.AccentTeal else Color.Gray,
                                    onClick = { targetType = t }
                                )
                            }
                        }
                    }

                    HorizontalDivider()

                    Text("Dry-Run Safety Assessment:", fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    Text("Total records examined: ${preview.totalRecordsExamined}", fontSize = 12.sp)
                    Text("Compatible: ${preview.successCount}", fontSize = 12.sp, color = ArcaPalette.SecondaryEmerald)
                    if (preview.failureCount > 0) {
                        Text("Failures: ${preview.failureCount}", fontSize = 12.sp, color = ArcaPalette.DangerRed, fontWeight = FontWeight.Bold)
                        for (desc in preview.sampleFailureDescriptions) {
                            Text("• $desc", fontSize = 11.sp, color = ArcaPalette.DangerRed)
                        }
                        Text("Conversion would cause data loss and cannot be applied automatically.", fontSize = 11.sp, color = ArcaPalette.DangerRed)
                    } else {
                        Text("✓ Safe to convert without loss of data", fontSize = 12.sp, color = ArcaPalette.SecondaryEmerald, fontWeight = FontWeight.Bold)
                    }
                }
            },
            confirmButton = {
                ArcaPrimaryButton(
                    text = "Apply Conversion",
                    enabled = preview.isSafeToApplyWithoutLoss
                ) {
                    viewModel.applyFieldConversion(schema.id, field.id, targetType)
                    fieldToConvert = null
                }
            },
            dismissButton = {
                TextButton(onClick = { fieldToConvert = null }) { Text("Cancel") }
            }
        )
    }
}

// MARK: - Screen 11: Add / Edit Record Form (All Field Types Supported)

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
    val draftBooleans = remember {
        mutableStateMapOf<UUID, Boolean>().apply {
            existingRecord?.values?.forEach { (fid, v) ->
                if (v is FieldValue.BooleanValue) put(fid, v.value)
            }
        }
    }
    val draftMultiSelect = remember {
        mutableStateMapOf<UUID, List<String>>().apply {
            existingRecord?.values?.forEach { (fid, v) ->
                if (v is FieldValue.MultiSelect) put(fid, v.optionIds)
            }
        }
    }
    val draftRatings = remember {
        mutableStateMapOf<UUID, Int>().apply {
            existingRecord?.values?.forEach { (fid, v) ->
                if (v is FieldValue.Rating) put(fid, v.stars)
            }
        }
    }
    val draftAttachments = remember {
        mutableStateMapOf<UUID, List<AttachmentReference>>().apply {
            existingRecord?.values?.forEach { (fid, v) ->
                if (v is FieldValue.Attachments) put(fid, v.items)
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
            ArcaSectionCard(title = "Validation Error", accentColor = ArcaPalette.DangerRed) {
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
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        text = "${field.label}${if (field.isRequired) " *" else ""}",
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp
                    )

                    when (field.type) {
                        FieldType.SHORT_TEXT -> {
                            OutlinedTextField(
                                value = draftText[field.id] ?: "",
                                onValueChange = { draftText[field.id] = it },
                                placeholder = { Text("Enter ${field.label.lowercase()}") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                        FieldType.LONG_TEXT -> {
                            OutlinedTextField(
                                value = draftText[field.id] ?: "",
                                onValueChange = { draftText[field.id] = it },
                                placeholder = { Text("Enter detailed notes…") },
                                minLines = 3,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                        FieldType.NUMBER -> {
                            OutlinedTextField(
                                value = draftText[field.id] ?: "",
                                onValueChange = { draftText[field.id] = it },
                                placeholder = { Text("0.0") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                        FieldType.CURRENCY -> {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                OutlinedTextField(
                                    value = draftText[field.id] ?: "",
                                    onValueChange = { draftText[field.id] = it },
                                    placeholder = { Text("0.00") },
                                    singleLine = true,
                                    modifier = Modifier.weight(1f)
                                )
                                ArcaPillBadge(text = field.validation.defaultCurrencyCode, tint = ArcaPalette.AccentTeal)
                            }
                        }
                        FieldType.DATE -> {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                OutlinedTextField(
                                    value = draftText[field.id] ?: "",
                                    onValueChange = { draftText[field.id] = it },
                                    placeholder = { Text("YYYY-MM-DD") },
                                    singleLine = true,
                                    modifier = Modifier.weight(1f)
                                )
                                ArcaPillBadge(
                                    text = "Today",
                                    tint = ArcaPalette.AccentTeal,
                                    onClick = { draftText[field.id] = CalendarDate.today().isoString }
                                )
                                ArcaPillBadge(
                                    text = "+1 Yr",
                                    tint = ArcaPalette.SecondaryEmerald,
                                    onClick = {
                                        val today = CalendarDate.today()
                                        draftText[field.id] = CalendarDate(today.year + 1, today.month, today.day).isoString
                                    }
                                )
                            }
                        }
                        FieldType.DATE_TIME -> {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                OutlinedTextField(
                                    value = draftText[field.id] ?: "",
                                    onValueChange = { draftText[field.id] = it },
                                    placeholder = { Text("ISO Instant (e.g. 2026-11-01T12:00:00Z)") },
                                    singleLine = true,
                                    modifier = Modifier.weight(1f)
                                )
                                ArcaPillBadge(
                                    text = "Now",
                                    tint = ArcaPalette.AccentTeal,
                                    onClick = { draftText[field.id] = Instant.now().toString() }
                                )
                            }
                        }
                        FieldType.BOOLEAN -> {
                            val currentBool = draftBooleans[field.id] ?: false
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(if (currentBool) "Yes" else "No", modifier = Modifier.weight(1f), fontSize = 13.sp)
                                Switch(checked = currentBool, onCheckedChange = { draftBooleans[field.id] = it })
                            }
                        }
                        FieldType.SINGLE_SELECT -> {
                            val currentOpt = draftText[field.id] ?: ""
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                for (opt in field.options) {
                                    val isSelected = currentOpt == opt.id || currentOpt == opt.label
                                    ArcaPillBadge(
                                        text = opt.label,
                                        tint = if (isSelected) ArcaPalette.AccentTeal else Color.Gray,
                                        onClick = { draftText[field.id] = opt.id }
                                    )
                                }
                            }
                        }
                        FieldType.MULTI_SELECT -> {
                            val currentOpts = draftMultiSelect[field.id] ?: emptyList()
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                for (opt in field.options) {
                                    val isSelected = currentOpts.contains(opt.id)
                                    ArcaPillBadge(
                                        text = if (isSelected) "✓ ${opt.label}" else opt.label,
                                        tint = if (isSelected) ArcaPalette.AccentTeal else Color.Gray,
                                        onClick = {
                                            draftMultiSelect[field.id] = if (isSelected) {
                                                currentOpts - opt.id
                                            } else {
                                                currentOpts + opt.id
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        FieldType.RATING -> {
                            val currentStars = draftRatings[field.id] ?: 0
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                for (star in 1..field.validation.maxRating) {
                                    val active = star <= currentStars
                                    Text(
                                        text = "★",
                                        fontSize = 24.sp,
                                        color = if (active) ArcaPalette.WarmAmber else Color.Gray.copy(alpha = 0.35f),
                                        modifier = Modifier.clickable { draftRatings[field.id] = star }
                                    )
                                }
                                if (currentStars > 0) {
                                    Spacer(modifier = Modifier.width(6.dp))
                                    ArcaPillBadge(text = "Clear", tint = Color.Gray, onClick = { draftRatings[field.id] = 0 })
                                }
                            }
                        }
                        FieldType.ATTACHMENT -> {
                            val attachments = draftAttachments[field.id] ?: emptyList()
                            for (att in attachments) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(att.filename, fontSize = 12.sp, modifier = Modifier.weight(1f))
                                    ArcaPillBadge(text = "Remove", tint = ArcaPalette.DangerRed) {
                                        draftAttachments[field.id] = attachments - att
                                    }
                                }
                            }
                            ArcaSecondaryButton(text = "+ Attach Receipt / Photo") {
                                val newAtt = viewModel.attachSampleReceiptFile()
                                draftAttachments[field.id] = attachments + newAtt
                            }
                        }
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                }
            }
        }

        ArcaPrimaryButton(text = "Save Record") {
            val builtValues = mutableMapOf<UUID, FieldValue>()
            for (field in schema.activeFields) {
                when (field.type) {
                    FieldType.BOOLEAN -> {
                        builtValues[field.id] = FieldValue.BooleanValue(draftBooleans[field.id] ?: false)
                    }
                    FieldType.RATING -> {
                        val stars = draftRatings[field.id] ?: 0
                        builtValues[field.id] = if (stars > 0) FieldValue.Rating(stars) else FieldValue.NullValue
                    }
                    FieldType.MULTI_SELECT -> {
                        val opts = draftMultiSelect[field.id] ?: emptyList()
                        builtValues[field.id] = if (opts.isNotEmpty()) FieldValue.MultiSelect(opts) else FieldValue.NullValue
                    }
                    FieldType.ATTACHMENT -> {
                        val items = draftAttachments[field.id] ?: emptyList()
                        builtValues[field.id] = if (items.isNotEmpty()) FieldValue.Attachments(items) else FieldValue.NullValue
                    }
                    else -> {
                        val raw = draftText[field.id]?.trim().orEmpty()
                        if (raw.isEmpty()) {
                            builtValues[field.id] = FieldValue.NullValue
                        } else {
                            builtValues[field.id] = when (field.type) {
                                FieldType.NUMBER -> raw.toDoubleOrNull()?.let { FieldValue.NumberValue(it) } ?: FieldValue.ShortText(raw)
                                FieldType.CURRENCY -> MoneyValue.fromDecimalString(raw, field.validation.defaultCurrencyCode)?.let { FieldValue.CurrencyValue(it) } ?: FieldValue.ShortText(raw)
                                FieldType.DATE -> CalendarDate.fromIsoString(raw)?.let { FieldValue.DateValue(it) } ?: FieldValue.DateValue(CalendarDate.today())
                                FieldType.DATE_TIME -> try {
                                    FieldValue.DateTimeValue(Instant.parse(raw))
                                } catch (_: Exception) {
                                    FieldValue.DateTimeValue(Instant.now())
                                }
                                FieldType.SINGLE_SELECT -> FieldValue.SingleSelect(raw)
                                FieldType.LONG_TEXT -> FieldValue.LongText(raw)
                                else -> FieldValue.ShortText(raw)
                            }
                        }
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

// MARK: - Screen 12: Record Detail Screen (QR deep links & Public Snapshots)

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
    var showQrTag by remember { mutableStateOf(false) }
    var showSnapshotDialog by remember { mutableStateOf(false) }

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
            ArcaPillBadge(text = if (record.isFavorite) "★ Pinned" else "Pin", tint = ArcaPalette.WarmAmber) {
                viewModel.toggleFavorite(record.id)
            }
            Spacer(modifier = Modifier.width(6.dp))
            ArcaPillBadge(text = "Edit", tint = tint, onClick = onEdit)
        }

        ArcaSectionCard {
            Text(text = record.title(schema), fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Text(
                text = "${schema.name} • Revision ${record.revision} • Updated ${record.updatedAt}",
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
            ArcaSectionCard(title = "Attachments (${record.allAttachments.size})") {
                for (att in record.allAttachments) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.CheckCircle, contentDescription = null, tint = ArcaPalette.SecondaryEmerald)
                        Spacer(modifier = Modifier.width(10.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(att.filename, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                            Text(
                                "SHA-256 ${att.sha256Hex.take(16)}… • ${att.byteSize / 1024} KB",
                                fontSize = 11.sp,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                            )
                        }
                    }
                }
            }
        }

        if (showQrTag) {
            ArcaSectionCard(
                title = "Local QR Asset Tag Deep Link",
                subtitle = "Identifies this record locally by UUID without cloud transmission or privacy exposure."
            ) {
                Text(text = deepLink, fontFamily = FontFamily.Monospace, fontSize = 11.sp)
                Text(
                    text = "Print or scan this tag on physical items (appliances, vehicle doors, warranty folders) to immediately jump to this record locally.",
                    fontSize = 11.sp,
                    color = Color.Gray
                )
            }
        }

        ArcaSectionCard(title = "Actions & Sharing") {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                ArcaSecondaryButton(
                    text = "Duplicate",
                    modifier = Modifier.weight(1f)
                ) {
                    viewModel.duplicateRecord(record)
                    onBack()
                }
                ArcaSecondaryButton(
                    text = if (showQrTag) "Hide QR Tag" else "Local QR Tag",
                    modifier = Modifier.weight(1f)
                ) {
                    showQrTag = !showQrTag
                }
            }
            ArcaSecondaryButton(
                text = "Share Public Snapshot…",
                tint = ArcaPalette.AccentTeal,
                modifier = Modifier.fillMaxWidth()
            ) {
                showSnapshotDialog = true
            }
            ArcaSecondaryButton(
                text = "Delete Record",
                tint = ArcaPalette.DangerRed,
                modifier = Modifier.fillMaxWidth()
            ) {
                viewModel.deleteRecord(record.id)
                onBack()
            }
        }
    }

    if (showSnapshotDialog) {
        val selectedIds = remember { mutableStateListOf<UUID>().apply { addAll(schema.activeFields.map { it.id }) } }
        var publishedToken by remember { mutableStateOf<String?>(null) }

        AlertDialog(
            onDismissRequest = { showSnapshotDialog = false },
            title = { Text("Share Public Snapshot", fontWeight = FontWeight.Bold) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        "Select specific fields to expose as a revocable public snapshot. Never shares encryption keys or unselected data.",
                        fontSize = 12.sp
                    )
                    for (field in schema.activeFields) {
                        val isChecked = selectedIds.contains(field.id)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(
                                checked = isChecked,
                                onCheckedChange = {
                                    if (isChecked) selectedIds.remove(field.id) else selectedIds.add(field.id)
                                }
                            )
                            Text(field.label, fontSize = 13.sp)
                        }
                    }

                    publishedToken?.let { tok ->
                        Surface(
                            color = ArcaPalette.SecondaryEmerald.copy(alpha = 0.1f),
                            shape = RoundedCornerShape(8.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Column(modifier = Modifier.padding(10.dp)) {
                                Text("Snapshot Published!", fontWeight = FontWeight.Bold, color = ArcaPalette.SecondaryEmerald)
                                Text("Token: $tok", fontFamily = FontFamily.Monospace, fontSize = 11.sp)
                                Text("Link: https://arca.app/s/$tok", fontSize = 11.sp)
                            }
                        }
                    }
                }
            },
            confirmButton = {
                if (publishedToken == null) {
                    ArcaPrimaryButton(text = "Publish Snapshot") {
                        val snap = viewModel.createPublicSnapshot(record, schema, selectedIds.toSet())
                        publishedToken = snap.shareToken
                    }
                } else {
                    ArcaPrimaryButton(text = "Done") {
                        showSnapshotDialog = false
                    }
                }
            },
            dismissButton = {
                TextButton(onClick = { showSnapshotDialog = false }) { Text("Cancel") }
            }
        )
    }
}

// MARK: - Screen 13: Insights Screen (Dynamic KPI, Expirations, Totals, Distributions)

@Composable
fun InsightsScreen(viewModel: ArcaViewModel) {
    val report = viewModel.currentSpaceInsights

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

        // KPI Cards
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            ArcaSectionCard(modifier = Modifier.weight(1f)) {
                Text("${report.totalRecords}", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = ArcaPalette.AccentTeal)
                Text("Records", fontSize = 11.sp)
            }
            ArcaSectionCard(modifier = Modifier.weight(1f)) {
                Text("${report.favoriteRecords}", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = ArcaPalette.WarmAmber)
                Text("Pinned", fontSize = 11.sp)
            }
            ArcaSectionCard(modifier = Modifier.weight(1f)) {
                Text("${report.totalAttachments}", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = ArcaPalette.SecondaryEmerald)
                Text("Files", fontSize = 11.sp)
            }
        }

        // Upcoming Expirations Card
        ArcaSectionCard(title = "Upcoming Expirations (${report.upcomingExpirations.size})") {
            if (report.upcomingExpirations.isEmpty()) {
                Text("No upcoming warranty or renewal expirations in this space.", fontSize = 13.sp, color = Color.Gray)
            } else {
                for (exp in report.upcomingExpirations.take(6)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(exp.title, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            Text("${exp.fieldLabel}: ${exp.expirationDate.isoString}", fontSize = 11.sp, color = Color.Gray)
                        }
                        if (exp.isExpired) {
                            ArcaPillBadge(text = "Expired (${-exp.daysRemaining}d ago)", tint = ArcaPalette.DangerRed)
                        } else {
                            ArcaPillBadge(text = "In ${exp.daysRemaining} days", tint = ArcaPalette.WarmAmber)
                        }
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                }
            }
        }

        // Totals & Averages Card (Number & Currency fields)
        ArcaSectionCard(title = "Totals & Averages (${report.numericSummaries.size})") {
            if (report.numericSummaries.isEmpty()) {
                Text("No numeric or currency values recorded in this space yet.", fontSize = 13.sp, color = Color.Gray)
            } else {
                for (num in report.numericSummaries) {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text("${num.collectionName} • ${num.fieldLabel}", fontSize = 12.sp, color = Color.Gray)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "Sum: ${num.formattedSum}",
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp,
                                modifier = Modifier.weight(1f)
                            )
                            Text("Avg: ${num.formattedAverage} (${num.count} recs)", fontSize = 12.sp)
                        }
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                }
            }
        }

        // Category Distributions (Single & Multi Select)
        if (report.selectDistributions.isNotEmpty()) {
            ArcaSectionCard(title = "Category Breakdown (${report.selectDistributions.size})") {
                val maxCount = report.selectDistributions.maxOfOrNull { it.count }?.toFloat() ?: 1f
                for (dist in report.selectDistributions.take(8)) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(dist.fieldLabel, fontSize = 11.sp, color = Color.Gray, modifier = Modifier.weight(1f))
                            Text("${dist.optionLabel}: ${dist.count}", fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
                        }
                        LinearProgressIndicator(
                            progress = { (dist.count / maxCount).coerceIn(0f, 1f) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(6.dp)
                                .clip(RoundedCornerShape(3.dp)),
                            color = ArcaPalette.AccentTeal,
                            trackColor = ArcaPalette.LightBorder
                        )
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                }
            }
        }
    }
}

// MARK: - Screens 14–19: Settings Hub, Cloud Login, Devices, Backups, Billing

@Composable
fun SettingsHubScreen(viewModel: ArcaViewModel) {
    var backupStatus by remember { mutableStateOf<String?>(null) }
    var deviceError by remember { mutableStateOf<String?>(null) }

    // Cloud Login / Register Inputs
    var authName by remember { mutableStateOf("") }
    var authEmail by remember { mutableStateOf("") }
    var authPassword by remember { mutableStateOf("") }
    var authStatus by remember { mutableStateOf<String?>(null) }

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

        // 1. Cloud Account & Device Registration Card
        ArcaSectionCard(
            title = "Cloud Account & Device Token Registration",
            subtitle = "Anonymous pre-login token automatically associates with your account upon login."
        ) {
            Surface(
                color = MaterialTheme.colorScheme.background,
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("This Device Identity:", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Text("Device ID: ${viewModel.currentDevice.deviceId}", fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    Text("Device Token: ${viewModel.currentDevice.deviceToken}", fontSize = 11.sp, fontFamily = FontFamily.Monospace)

                    val isPreLogin = viewModel.currentDevice.userId == null
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Device State: ", fontSize = 12.sp)
                        if (isPreLogin) {
                            ArcaPillBadge(text = "Pre-Login (user_id: null)", tint = ArcaPalette.WarmAmber)
                        } else {
                            ArcaPillBadge(text = "Linked to User #${viewModel.currentDevice.userId}", tint = ArcaPalette.SecondaryEmerald)
                        }
                    }
                }
            }

            if (viewModel.cloudAccountSession == null) {
                Text("Login or Register Cloud Account:", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                OutlinedTextField(
                    value = authName,
                    onValueChange = { authName = it },
                    label = { Text("Full Name (for new register)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = authEmail,
                    onValueChange = { authEmail = it },
                    label = { Text("Account Email") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = authPassword,
                    onValueChange = { authPassword = it },
                    label = { Text("Password") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                authStatus?.let { msg ->
                    Text(msg, fontSize = 12.sp, color = ArcaPalette.AccentTeal, fontWeight = FontWeight.SemiBold)
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    ArcaPrimaryButton(
                        text = "Login & Link Device",
                        modifier = Modifier.weight(1f)
                    ) {
                        val res = viewModel.loginOrRegisterCloudAccount(authName, authEmail, authPassword, isRegistration = false)
                        res.onSuccess { session ->
                            authStatus = "Logged in as ${session.email} (User #${session.userId})"
                        }.onFailure { err ->
                            authStatus = "Login error: ${err.message}"
                        }
                    }
                    ArcaSecondaryButton(
                        text = "Register & Link",
                        modifier = Modifier.weight(1f)
                    ) {
                        val res = viewModel.loginOrRegisterCloudAccount(authName, authEmail, authPassword, isRegistration = true)
                        res.onSuccess { session ->
                            authStatus = "Registered as ${session.email} (User #${session.userId})"
                        }.onFailure { err ->
                            authStatus = "Register error: ${err.message}"
                        }
                    }
                }
            } else {
                val sess = viewModel.cloudAccountSession!!
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Logged in as ${sess.name} (${sess.email})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Text("Plan: ${sess.tier.name} • User UUID: ${sess.userUuid.take(8)}…", fontSize = 12.sp, color = Color.Gray)
                    Text("Device Associated: ${sess.associatedDeviceToken.take(16)}…", fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    ArcaSecondaryButton(
                        text = "Log Out Cloud Account",
                        tint = ArcaPalette.WarmAmber,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        viewModel.logoutCloudAccount()
                        authStatus = "Logged out. Local device token preserved."
                    }
                }
            }
        }

        // 2. Storage Mode & Migration Preview Card
        viewModel.currentSpace?.let { curSpace ->
            ArcaSectionCard(
                title = "Current Space Storage Mode",
                subtitle = "Active Space: ${curSpace.name} (${if (curSpace.storageMode == SpaceStorageMode.ARCA_SYNC) "Arca Sync E2EE" else "Local-Only"})"
            ) {
                Text(
                    text = if (curSpace.storageMode == SpaceStorageMode.ARCA_SYNC) {
                        "Records in “${curSpace.name}” are encrypted on-device with AES-256-GCM before syncing to the cloud."
                    } else {
                        "Records in “${curSpace.name}” are strictly local and never transmit to any server."
                    },
                    fontSize = 12.sp
                )
                ArcaSecondaryButton(
                    text = if (curSpace.storageMode == SpaceStorageMode.ARCA_SYNC) "Switch “${curSpace.name}” to Local-Only" else "Switch “${curSpace.name}” to Arca Sync",
                    onClick = { viewModel.toggleSpaceStorageMode(curSpace.id) }
                )
            }
        }

        // 3. Portable Backups (.arcaarchive)
        ArcaSectionCard(
            title = "Portable Backups (.arcaarchive)",
            subtitle = "Cross-platform encrypted archives compatible between Arca iOS and Arca Android."
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

        // 4. Sync Status & Preserved Conflicts
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

        // 5. Active Device Management (2-Device Free Limit)
        ArcaSectionCard(
            title = "Active Synced Devices (${viewModel.enrolledDevices.size}/${viewModel.maxAllowedDevices})",
            subtitle = "Revoking a device stops future sync and rotates Space Encryption Keys."
        ) {
            for (dev in viewModel.enrolledDevices) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(dev.deviceName, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        Text(
                            "${dev.platform} • Token: ${dev.deviceToken.take(14)}…${if (dev.userId != null) " • User #${dev.userId}" else ""}",
                            fontSize = 11.sp,
                            color = Color.Gray
                        )
                    }
                    if (!dev.isCurrentDevice) {
                        ArcaPillBadge(text = "Revoke", tint = ArcaPalette.DangerRed) {
                            viewModel.revokeDevice(dev.deviceId)
                            deviceError = null
                        }
                    }
                }
                HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
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

        // 6. Arca Plan & Subscriptions
        ArcaSectionCard(
            title = "Arca Plan & Subscriptions",
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

        // 7. Public Shared Snapshots Manager
        if (viewModel.publicSnapshots.isNotEmpty()) {
            ArcaSectionCard(title = "Public Shared Snapshots (${viewModel.publicSnapshots.size})") {
                for (snap in viewModel.publicSnapshots) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(snap.title, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            Text(
                                "Token: ${snap.shareToken} • ${snap.selectedFieldPairs.size} fields${if (snap.isRevoked) " • REVOKED" else " • Active"}",
                                fontSize = 11.sp,
                                color = if (snap.isRevoked) ArcaPalette.DangerRed else ArcaPalette.SecondaryEmerald
                            )
                        }
                        if (!snap.isRevoked) {
                            ArcaPillBadge(text = "Revoke Link", tint = ArcaPalette.DangerRed) {
                                viewModel.revokePublicSnapshot(snap.id)
                            }
                        }
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                }
            }
        }

        // 8. Security & E2EE Recovery Key
        ArcaSectionCard(title = "Security & E2EE Recovery Key") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Biometric App Lock", modifier = Modifier.weight(1f), fontSize = 14.sp)
                Switch(checked = viewModel.biometricLockEnabled, onCheckedChange = { viewModel.biometricLockEnabled = it })
            }
            Text("Emergency E2EE Recovery Key:", fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
            Text(
                text = viewModel.recoveryKeyPhrase,
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium
            )
        }

        // 9. Appearance, Language & Edge-State Banners
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

// MARK: - Jetpack Compose @Preview Functions

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
