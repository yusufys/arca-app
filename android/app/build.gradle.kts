import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
}

val localProps = Properties().apply {
    val propFile = rootProject.file("local.properties")
    if (propFile.exists()) {
        propFile.inputStream().use { load(it) }
    }
}

fun envOrProp(key: String, default: String): String {
    return System.getenv(key) ?: localProps.getProperty(key) ?: default
}

android {
    namespace = "app.arca.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.arca.personalrecords"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("String", "ARCA_API_BASE_URL", "\"${envOrProp("ARCA_API_BASE_URL", "http://192.168.1.4:8000")}\"")
        buildConfigField("String", "REVENUECAT_ANDROID_PUBLIC_KEY", "\"${envOrProp("REVENUECAT_ANDROID_PUBLIC_KEY", "goog_replace_with_your_revenuecat_android_public_sdk_key")}\"")
        buildConfigField("String", "REVENUECAT_PRO_ENTITLEMENT_ID", "\"${envOrProp("REVENUECAT_PRO_ENTITLEMENT_ID", "arca_pro")}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    buildFeatures {
        compose = true
        aidl = false
        buildConfig = true
        shaders = false
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    val composeBom = platform(libs.androidx.compose.bom)
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation("androidx.compose.material:material-icons-core:1.7.8")

    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    testImplementation(libs.junit)
}
