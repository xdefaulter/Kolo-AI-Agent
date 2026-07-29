package com.kolo.agent.core.designsystem

import androidx.compose.ui.unit.dp

/**
 * Centralized spacing tokens for the Kolo UI.
 *
 * Replaces the previous spread of inline magic numbers (2/3/4/6/8/10/12/14/16/18/20 dp)
 * with a small, named scale. All paddings, gaps, and gutters should reference these.
 *
 * Scale:
 *  - [xs]   4dp  — tight spacing inside dense components (icon-to-text, chip padding)
 *  - [sm]   8dp  — small component gaps
 *  - [md]  12dp  — medium component gaps, inner card padding
 *  - [lg]  16dp  — standard Material 3 spacing; primary content padding
 *  - [screen] 16dp — the standard horizontal gutter for list content (alias of [lg])
 *  - [content] 10dp — message-bubble inner padding
 *  - [between] 6dp — spacing between sibling actions / tight rows
 */
object Spacing {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp

    /** Standard horizontal gutter for list/screen content (M3 spacing). */
    val screen = 16.dp

    /** Inner padding for message bubbles. */
    val content = 10.dp

    /** Tight gap between sibling actions or dense rows. */
    val between = 6.dp

    /** Sub-token smaller than [xs], used for very tight groupings (e.g. separator spacing). */
    val xxs = 2.dp
}
