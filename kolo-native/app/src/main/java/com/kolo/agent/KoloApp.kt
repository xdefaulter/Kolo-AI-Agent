package com.kolo.agent

import android.app.Application
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import com.kolo.agent.core.settings.AppSettings
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.android.HiltAndroidApp
import dagger.hilt.components.SingletonComponent

@HiltAndroidApp
class KoloApp : Application()

/**
 * Hilt EntryPoint to access AppSettings from a @Composable
 * that isn't inside a @HiltViewModel or @AndroidEntryPoint.
 */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface AppSettingsEntryPoint {
    fun appSettings(): AppSettings
}

/**
 * Theme wrapper that reads AppSettings.themeMode from DataStore
 * and applies the correct Material3 color scheme.
 *
 * Uses Hilt's EntryPoint to get the singleton AppSettings,
 * avoiding the "multiple DataStores for the same file" crash.
 */
@Composable
fun KoloTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val app = context.applicationContext as Application

    // Get the Hilt-provided singleton AppSettings via EntryPoint
    val settings = remember {
        EntryPointAccessors.fromApplication(app, AppSettingsEntryPoint::class.java).appSettings()
    }

    var themeMode by remember { mutableStateOf(AppSettings.ThemeMode.SYSTEM) }

    LaunchedEffect(settings) {
        settings.themeMode.collect { mode ->
            themeMode = mode
        }
    }

    val darkTheme = when (themeMode) {
        AppSettings.ThemeMode.SYSTEM -> isSystemInDarkTheme()
        AppSettings.ThemeMode.LIGHT -> false
        AppSettings.ThemeMode.DARK -> true
    }

    val colorScheme = when {
        darkTheme -> dynamicDarkColorScheme(context)
        else -> dynamicLightColorScheme(context)
    }

    MaterialTheme(
        colorScheme = colorScheme,
        content = content,
    )
}