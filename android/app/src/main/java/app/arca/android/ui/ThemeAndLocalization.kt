package app.arca.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Locale

// MARK: - Localization Foundations (English, Arabic RTL, Turkish)

enum class AppLanguage(val code: String, val displayName: String, val isRtl: Boolean) {
    ENGLISH("en", "English", false),
    ARABIC("ar", "العربية (Arabic)", true),
    TURKISH("tr", "Türkçe (Turkish)", false);

    val layoutDirection: LayoutDirection
        get() = if (isRtl) LayoutDirection.Rtl else LayoutDirection.Ltr

    val locale: Locale
        get() = Locale(code)
}

enum class AppAppearanceMode(val label: String) {
    LIGHT("Light (Default)"),
    DARK("Dark"),
    SYSTEM("System")
}

object ArcaStrings {
    private val table: Map<AppLanguage, Map<String, String>> = mapOf(
        AppLanguage.ENGLISH to mapOf(
            "app.name" to "Arca",
            "app.tagline" to "Your records. Your way.",
            "app.heroPrompt" to "Save something important now. Find it easily when you need it.",
            "tab.home" to "Home",
            "tab.insights" to "Insights",
            "tab.settings" to "Settings",
            "welcome.getStarted" to "Get Started",
            "storage.title" to "Choose How Arca Stores Your Spaces",
            "home.spaces" to "Spaces",
            "home.collections" to "Collections",
            "home.recentRecords" to "Recent Records",
            "home.favorites" to "Pinned & Favorites",
            "home.searchPlaceholder" to "Search records, notes, serial numbers…",
            "home.quickAddRecord" to "New Record",
            "insights.title" to "Insights",
            "settings.title" to "Settings & Storage"
        ),
        AppLanguage.ARABIC to mapOf(
            "app.name" to "أركا (Arca)",
            "app.tagline" to "سجلاتك. بطريقتك.",
            "app.heroPrompt" to "احفظ ما يهمك الآن، واعثر عليه بسهولة عندما تحتاج إليه.",
            "tab.home" to "الرئيسية",
            "tab.insights" to "إحصاءات",
            "tab.settings" to "الإعدادات",
            "welcome.getStarted" to "ابدأ الآن",
            "storage.title" to "اختر طريقة تخزين مساحاتك",
            "home.spaces" to "المساحات",
            "home.collections" to "المجموعات",
            "home.recentRecords" to "السجلات الأخيرة",
            "home.favorites" to "المثبتة والمفضلة",
            "home.searchPlaceholder" to "ابحث في السجلات، الملاحظات، الأرقام التسلسلية…",
            "home.quickAddRecord" to "سجل جديد",
            "insights.title" to "الإحصاءات",
            "settings.title" to "الإعدادات والتخزين"
        ),
        AppLanguage.TURKISH to mapOf(
            "app.name" to "Arca",
            "app.tagline" to "Kayıtlarınız. Sizin yönteminiz.",
            "app.heroPrompt" to "Önemli olanı şimdi kaydedin. İhtiyaç duyduğunuzda kolayca bulun.",
            "tab.home" to "Ana Sayfa",
            "tab.insights" to "Analizler",
            "tab.settings" to "Ayarlar",
            "welcome.getStarted" to "Başlayın",
            "storage.title" to "Alanlarınızın Nasıl Saklanacağını Seçin",
            "home.spaces" to "Alanlar",
            "home.collections" to "Koleksiyonlar",
            "home.recentRecords" to "Son Kayıtlar",
            "home.favorites" to "Sabitlenenler ve Favoriler",
            "home.searchPlaceholder" to "Kayıtlarda, notlarda, seri numaralarında ara…",
            "home.quickAddRecord" to "Yeni Kayıt",
            "insights.title" to "Analizler",
            "settings.title" to "Ayarlar ve Depolama"
        )
    )

    fun text(key: String, language: AppLanguage): String =
        table[language]?.get(key) ?: table[AppLanguage.ENGLISH]?.get(key) ?: key
}

// MARK: - Design Tokens (Warm Stone Alabaster + Deep Slate Teal Accent)

object ArcaPalette {
    val AccentTeal = Color(0xFF1F5673)
    val SecondaryEmerald = Color(0xFF2A7B63)
    val WarmAmber = Color(0xFFB96E21)
    val PlumSensitive = Color(0xFF863C60)
    val DangerRed = Color(0xFFC33636)

    val LightCanvas = Color(0xFFF5F4F0)
    val LightCard = Color(0xFFFFFFFF)
    val LightSubtleField = Color(0xFFF1F0EB)
    val LightBorder = Color(0x12000000)

    val DarkCanvas = Color(0xFF111317)
    val DarkCard = Color(0xFF1D2026)
    val DarkSubtleField = Color(0xFF272B32)
    val DarkBorder = Color(0x18FFFFFF)

    fun fromHex(hex: String): Color {
        val cleaned = hex.trim().removePrefix("#")
        return runCatching {
            val rgb = cleaned.toLong(16)
            Color(0xFF000000 or rgb)
        }.getOrDefault(AccentTeal)
    }
}

private val LightColors = lightColorScheme(
    primary = ArcaPalette.AccentTeal,
    onPrimary = Color.White,
    secondary = ArcaPalette.SecondaryEmerald,
    background = ArcaPalette.LightCanvas,
    surface = ArcaPalette.LightCard,
    onBackground = Color(0xFF15181E),
    onSurface = Color(0xFF15181E)
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF5CA4C9),
    onPrimary = Color.White,
    secondary = ArcaPalette.SecondaryEmerald,
    background = ArcaPalette.DarkCanvas,
    surface = ArcaPalette.DarkCard,
    onBackground = Color(0xFFF3F4F6),
    onSurface = Color(0xFFF3F4F6)
)

@Composable
fun ArcaTheme(
    appearanceMode: AppAppearanceMode = AppAppearanceMode.LIGHT,
    language: AppLanguage = AppLanguage.ENGLISH,
    content: @Composable () -> Unit
) {
    val darkTheme = when (appearanceMode) {
        AppAppearanceMode.LIGHT -> false
        AppAppearanceMode.DARK -> true
        AppAppearanceMode.SYSTEM -> isSystemInDarkTheme()
    }
    val colors = if (darkTheme) DarkColors else LightColors

    CompositionLocalProvider(LocalLayoutDirection provides language.layoutDirection) {
        MaterialTheme(
            colorScheme = colors,
            content = content
        )
    }
}

// MARK: - Reusable Elevated Card & Buttons

@Composable
fun ArcaSectionCard(
    title: String? = null,
    subtitle: String? = null,
    accentColor: Color = ArcaPalette.AccentTeal,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    val isDark = MaterialTheme.colorScheme.background == ArcaPalette.DarkCanvas
    val cardBg = if (isDark) ArcaPalette.DarkCard else ArcaPalette.LightCard
    val borderColor = if (isDark) ArcaPalette.DarkBorder else ArcaPalette.LightBorder

    Column(modifier = modifier.fillMaxWidth()) {
        if (title != null) {
            Text(
                text = title.uppercase(Locale.getDefault()),
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 0.6.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp)
            )
        }
        Surface(
            color = cardBg,
            shape = RoundedCornerShape(18.dp),
            border = BorderStroke(1.dp, borderColor),
            shadowElevation = if (isDark) 0.dp else 2.dp,
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (subtitle != null) {
                    Text(
                        text = subtitle,
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
                    )
                }
                content()
            }
        }
    }
}

@Composable
fun ArcaPrimaryButton(
    text: String,
    tint: Color = ArcaPalette.AccentTeal,
    enabled: Boolean = true,
    modifier: Modifier = Modifier.fillMaxWidth(),
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(containerColor = tint, contentColor = Color.White),
        contentPadding = PaddingValues(horizontal = 18.dp, vertical = 13.dp),
        modifier = modifier
    ) {
        Text(text = text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun ArcaSecondaryButton(
    text: String,
    tint: Color = ArcaPalette.AccentTeal,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(12.dp),
        border = BorderStroke(1.dp, if (enabled) tint.copy(alpha = 0.35f) else Color.Gray.copy(alpha = 0.25f)),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = if (enabled) tint.copy(alpha = 0.09f) else Color.Transparent,
            contentColor = if (enabled) tint else Color.Gray
        ),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 11.dp),
        modifier = modifier
    ) {
        Text(text = text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun ArcaPillBadge(
    text: String,
    tint: Color = ArcaPalette.AccentTeal,
    onClick: (() -> Unit)? = null
) {
    val mod = if (onClick != null) {
        Modifier
            .clip(CircleShape)
            .background(tint.copy(alpha = 0.14f))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 5.dp)
    } else {
        Modifier
            .clip(CircleShape)
            .background(tint.copy(alpha = 0.14f))
            .padding(horizontal = 10.dp, vertical = 5.dp)
    }
    Box(modifier = mod) {
        Text(
            text = text,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = tint
        )
    }
}

// MARK: - Operational Edge-State Banner (Offline, Sync Conflict, Quota Full, Failed Upload, Restore Rejected)

enum class OperationalBannerState(val label: String) {
    NORMAL("Normal Online"),
    OFFLINE_QUEUED("Offline (2 Queued Edits)"),
    SYNC_CONFLICT("Sync Edit Conflict Preserved"),
    FAILED_UPLOAD("Attachment Upload Paused"),
    STORAGE_QUOTA_FULL("Cloud Storage Quota Reached"),
    THIRD_DEVICE_BLOCKED("Free 2-Device Limit Reached"),
    PERMISSION_DENIED("Camera Permission Not Granted"),
    RESTORE_REJECTED("Corrupt Backup Rejected Safely")
}

@Composable
fun OperationalStateBannerView(
    state: OperationalBannerState,
    onAction: () -> Unit
) {
    if (state == OperationalBannerState.NORMAL) return

    val (icon, title, subtitle, tint) = when (state) {
        OperationalBannerState.OFFLINE_QUEUED -> Quad(
            Icons.Default.Info,
            "Working Offline • Local Storage Active",
            "2 changes saved safely on this device and queued for sync when reconnected.",
            ArcaPalette.WarmAmber
        )
        OperationalBannerState.SYNC_CONFLICT -> Quad(
            Icons.Default.Warning,
            "1 Sync Edit Conflict Preserved",
            "Both versions were kept safely so nothing was lost. Review and choose which edits to keep.",
            ArcaPalette.PlumSensitive
        )
        OperationalBannerState.FAILED_UPLOAD -> Quad(
            Icons.Default.Warning,
            "Attachment Upload Paused",
            "Network timeout while uploading invoice.pdf. Your local record and file remain safe.",
            ArcaPalette.DangerRed
        )
        OperationalBannerState.STORAGE_QUOTA_FULL -> Quad(
            Icons.Default.Warning,
            "Cloud Sync Allowance Reached",
            "New records continue saving locally on this device. Upgrade to Arca Pro to resume sync.",
            ArcaPalette.WarmAmber
        )
        OperationalBannerState.THIRD_DEVICE_BLOCKED -> Quad(
            Icons.Default.Warning,
            "Free Plan 2-Device Limit Reached",
            "Local records remain accessible. Revoke an older device or upgrade to Arca Pro.",
            ArcaPalette.WarmAmber
        )
        OperationalBannerState.PERMISSION_DENIED -> Quad(
            Icons.Default.Lock,
            "Camera Access Not Granted",
            "Enable permission in Android Settings or attach files from the system document picker.",
            ArcaPalette.AccentTeal
        )
        OperationalBannerState.RESTORE_REJECTED -> Quad(
            Icons.Default.Warning,
            "Backup Restore Rejected Safely",
            "SHA-256 manifest digest mismatch on records.json. Your live spaces were not modified.",
            ArcaPalette.DangerRed
        )
        OperationalBannerState.NORMAL -> return
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(tint.copy(alpha = 0.10f))
            .border(1.dp, tint.copy(alpha = 0.28f), RoundedCornerShape(16.dp))
            .padding(14.dp)
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(tint.copy(alpha = 0.18f))
        ) {
            Icon(imageVector = icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        }
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, fontSize = 13.sp, fontWeight = FontWeight.Bold)
            Text(
                text = subtitle,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
            )
        }
        Spacer(modifier = Modifier.width(8.dp))
        ArcaPillBadge(text = "Review", tint = tint, onClick = onAction)
    }
}

private data class Quad(
    val icon: ImageVector,
    val title: String,
    val subtitle: String,
    val tint: Color
)
