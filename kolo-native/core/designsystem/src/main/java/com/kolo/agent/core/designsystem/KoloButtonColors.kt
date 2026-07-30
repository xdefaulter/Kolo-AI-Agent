package com.kolo.agent.core.designsystem

import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable

/**
 * Shared destructive-action button color helpers.
 *
 * Replaces the ~8 inlined `ButtonDefaults.…Colors(contentColor = error)`
 * duplicates and unifies the three previously inconsistent destructive
 * treatments (text vs outlined vs filled-tonal) into one style per kind.
 */

/** Text button used for destructive actions (e.g. inline "Delete"). */
@Composable
fun destructiveTextButtonColors(): ButtonColors =
    ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)

/** Outlined button used for destructive actions. */
@Composable
fun destructiveOutlinedButtonColors(): ButtonColors =
    ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)

/** Filled-tonal button used for destructive actions (e.g. prominent delete). */
@Composable
fun destructiveTonalButtonColors(): ButtonColors =
    ButtonDefaults.filledTonalButtonColors(
        containerColor = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
    )
