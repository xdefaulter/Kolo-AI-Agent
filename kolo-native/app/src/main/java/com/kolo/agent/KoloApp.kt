package com.kolo.agent

import android.app.Application
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import com.kolo.agent.core.settings.AppSettings
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class KoloApp : Application()

/**
 * Theme wrapper that reads AppSettings.themeMode from DataStore
 * and applies the correct Material3 color scheme.
 */
@Composable
fun KoloTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    var themeMode by remember { mutableStateOf(AppSettings.ThemeMode.SYSTEM) }

    LaunchedEffect(Unit) {
        val settings = AppSettings(context)
        settings.themeMode.collect { mode ->
            themeMode = mode
        }
    }

    val darkTheme = when (themeMode) {
        AppSettings.ThemeMode.SYSTEM -> isSystemInDarkTheme()
        AppSettings.ThemeMode.LIGHT -> false
        AppSettings.ThemeMode.DARK -> true
    }

    val colorScheme = if (darkTheme) {
        dynamicDarkColorScheme(context)
    } else {
        dynamicLightColorScheme(context)
    }

    MaterialTheme(
        colorScheme = colorScheme,
        content = content,
    )
}