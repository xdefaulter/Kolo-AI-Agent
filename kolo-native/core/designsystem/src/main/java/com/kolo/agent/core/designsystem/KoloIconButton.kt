package com.kolo.agent.core.designsystem

import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Touch-target-safe icon button.
 *
 * Material 3 mandates a 48dp minimum interactive size. The previous pattern
 * `IconButton(modifier = Modifier.size(20.dp))` shrank the tap target below
 * that minimum. This wrapper deliberately does NOT constrain the [IconButton]
 * itself (it keeps its 48dp default) and only sizes the inner [Icon] visually
 * via [iconSize]. It also bakes in a non-null [contentDescription], closing
 * the "interactive icon with no description" accessibility gap at every call
 * site.
 *
 * @param onClick click handler
 * @param contentDescription required accessibility label (never null)
 * @param icon the ImageVector to render
 * @param iconSize visual size of the glyph (default 20dp); the tap target stays 48dp
 * @param tint icon color; defaults to the ambient content color
 * @param enabled when false the button is non-interactive
 */
@Composable
fun KoloIconButton(
    onClick: () -> Unit,
    contentDescription: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    iconSize: Dp = 20.dp,
    tint: Color = LocalContentColor.current,
    enabled: Boolean = true,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = tint,
            modifier = Modifier.size(iconSize),
        )
    }
}
