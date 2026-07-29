package com.kolo.agent.core.designsystem

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

/**
 * Centralized shape tokens for the Kolo UI.
 *
 * Replaces the previous mix of 6/8/10/12/14/20 dp hardcoded radii with three tiers.
 * Wired into [MaterialTheme] via [KoloTheme] so `MaterialTheme.shapes.small|medium|large`
 * resolve app-wide.
 *
 *  - [Shapes.small]  8dp  — banners, panels, inputs (compact surfaces)
 *  - [Shapes.medium] 14dp — message bubbles, date separators (primary content)
 *  - [Shapes.large]  20dp — chat input field, large cards (prominent surfaces)
 */
val KoloShapes = Shapes(
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(14.dp),
    large = RoundedCornerShape(20.dp),
)
