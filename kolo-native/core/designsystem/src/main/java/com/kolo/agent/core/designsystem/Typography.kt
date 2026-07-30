package com.kolo.agent.core.designsystem

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight

/**
 * Centralized typography tokens for the Kolo UI.
 *
 * Starts from the Material 3 default scale and tunes the title tiers so the
 * previously ad-hoc `fontWeight = FontWeight.SemiBold` overrides (applied
 * inconsistently across ~28 sites) become unnecessary — titles are SemiBold
 * by default. Wired into [MaterialTheme] via [KoloTheme] so
 * `MaterialTheme.typography.*` resolves app-wide.
 *
 * Weight policy:
 *  - titleLarge / titleMedium / titleSmall — [FontWeight.SemiBold] (primary headings)
 *  - headline / body — default (Normal)
 *  - labels — default (Medium)
 *
 * No custom font family — the system font is used, so there are no bundled
 * font resources and no licensing surface.
 */
val KoloTypography = Typography(
    titleLarge = TextStyle(fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontWeight = FontWeight.SemiBold),
    titleSmall = TextStyle(fontWeight = FontWeight.SemiBold),
)
