plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

val releaseStoreFile = providers.gradleProperty("KOLO_RELEASE_STORE_FILE")
    .orElse(providers.environmentVariable("KOLO_RELEASE_STORE_FILE"))
val releaseStorePassword = providers.gradleProperty("KOLO_RELEASE_STORE_PASSWORD")
    .orElse(providers.environmentVariable("KOLO_RELEASE_STORE_PASSWORD"))
val releaseKeyAlias = providers.gradleProperty("KOLO_RELEASE_KEY_ALIAS")
    .orElse(providers.environmentVariable("KOLO_RELEASE_KEY_ALIAS"))
val releaseKeyPassword = providers.gradleProperty("KOLO_RELEASE_KEY_PASSWORD")
    .orElse(providers.environmentVariable("KOLO_RELEASE_KEY_PASSWORD"))
val releaseSigningValues = listOf(
    releaseStoreFile.orNull,
    releaseStorePassword.orNull,
    releaseKeyAlias.orNull,
    releaseKeyPassword.orNull,
)
val hasAnyReleaseSigningValue = releaseSigningValues.any { !it.isNullOrBlank() }
val hasReleaseSigning = releaseSigningValues.all { !it.isNullOrBlank() }

if (hasAnyReleaseSigningValue && !hasReleaseSigning) {
    throw GradleException(
        "Release signing requires KOLO_RELEASE_STORE_FILE, KOLO_RELEASE_STORE_PASSWORD, " +
            "KOLO_RELEASE_KEY_ALIAS, and KOLO_RELEASE_KEY_PASSWORD.",
    )
}

android {
    namespace = "com.kolo.agent"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.kolo.agent"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = "1.0.0"
        manifestPlaceholders["usesCleartextTraffic"] = "false"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ksp {
            arg("room.schemaLocation", "$projectDir/schemas")
        }
    }

    if (hasReleaseSigning) {
        val releaseKeystore = file(releaseStoreFile.get())
        if (!releaseKeystore.isFile) {
            throw GradleException("Release signing store file does not exist: ${releaseKeystore.path}")
        }
        signingConfigs {
            create("release") {
                storeFile = releaseKeystore
                storePassword = releaseStorePassword.get()
                keyAlias = releaseKeyAlias.get()
                keyPassword = releaseKeyPassword.get()
            }
        }
    }

    buildTypes {
        release {
            manifestPlaceholders["usesCleartextTraffic"] = "false"
            isMinifyEnabled = true
            isShrinkResources = true
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            manifestPlaceholders["usesCleartextTraffic"] = "true"
            isDebuggable = true
            applicationIdSuffix = ".debug"
        }
    }

    buildFeatures {
        compose = true
    }

    lint {
        // AGP 8.7/Kotlin 2.0 can crash this lifecycle detector while analyzing this module.
        disable += "NullSafeMutableLiveData"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation(project(":core:model"))
    implementation(project(":core:database"))
    implementation(project(":core:providers"))
    implementation(project(":core:agent"))
    implementation(project(":core:tools"))
    implementation(project(":feature:chat"))
    implementation(project(":feature:settings"))
    implementation(project(":feature:phonecontrol"))

    // Compose BOM
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.compose.animation)
    implementation(libs.compose.foundation)
    implementation(libs.compose.runtime)

    // Navigation
    implementation(libs.navigation.compose)

    // AndroidX
    implementation(libs.core.ktx)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.lifecycle.runtime.ktx)
    implementation(libs.lifecycle.viewmodel.compose)

    // Room
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)

    // DataStore
    implementation(libs.datastore.preferences)

    // Networking
    implementation(libs.okhttp)
    implementation(libs.okhttp.sse)
    implementation(libs.okhttp.logging)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)

    // Hilt DI
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.hilt.navigation.compose)

    // Security
    implementation(libs.security.crypto)

    // Debug
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    // Testing
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.turbine)

    androidTestImplementation(libs.junit.ext)
    androidTestImplementation(libs.espresso.core)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
}
