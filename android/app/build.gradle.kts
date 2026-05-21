import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing configuration from `android/key.properties` when present.
// That file is gitignored (see android/.gitignore) so keystore paths +
// passwords never land in source control. If it's missing, `release`
// falls back to debug signing so the local `flutter run --release` flow
// still works on developer machines that don't have a keystore set up.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        load(FileInputStream(f))
    }
}
val hasReleaseKeystore =
    keystoreProperties.containsKey("storeFile") &&
        keystoreProperties.containsKey("storePassword") &&
        keystoreProperties.containsKey("keyAlias") &&
        keystoreProperties.containsKey("keyPassword")

android {
    namespace = "com.kolo.kolo_ai_agent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.kolo.kolo_ai_agent"
        minSdk = maxOf(flutter.minSdkVersion, 31)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // No production keystore on this machine — fall back to
                // debug keys so `flutter run --release` still installs.
                // Publishable builds MUST set up android/key.properties.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Tensor G5 dispatch libraries need extraction from the APK at runtime.
    packaging {
        jniLibs {
            useLegacyPackaging = true
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // LiteRT-LM on-device inference engine. Local AAR keeps Google's 0.12.0
    // Kotlin API and uses a patched Android JNI library that avoids the
    // Tensor G5 runtime's unsupported edgetpu_performance_mode directive.
    implementation(files("libs/litertlm-android-0.12.0-g5-patched.aar"))
    // Kotlin coroutines (used by LiteRT-LM streaming API)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // Gson (used by LiteRT-LM for JSON parsing)
    implementation("com.google.code.gson:gson:2.11.0")
}
