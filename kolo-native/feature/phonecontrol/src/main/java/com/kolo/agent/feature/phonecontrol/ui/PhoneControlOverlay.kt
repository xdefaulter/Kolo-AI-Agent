package com.kolo.agent.feature.phonecontrol.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.kolo.agent.feature.phonecontrol.service.PhoneControlAccessibilityService

/**
 * In-app composable overlay that mirrors the system accessibility overlay state.
 * Shows when the phone-control session is active or stopped-by-user.
 *
 * Note: The actual system overlay over other apps uses TYPE_ACCESSIBILITY_OVERLAY
 * in PhoneControlAccessibilityService. This composable is for the in-app view only.
 */
@Composable
fun PhoneControlOverlay(
    onStop: () -> Unit,
) {
    val sessionState by PhoneControlAccessibilityService.sessionState.collectAsState()
    val message by PhoneControlAccessibilityService.overlayMessage.collectAsState()

    if (sessionState == PhoneControlAccessibilityService.SessionState.inactive) return

    val isStopped = sessionState == PhoneControlAccessibilityService.SessionState.stoppedByUser

    Box(
        modifier = Modifier
            .fillMaxSize()
            .border(
                width = if (isStopped) 6.dp else 4.dp,
                color = if (isStopped) Color(0xFFFF1744) else MaterialTheme.colorScheme.error.copy(alpha = 0.7f),
            )
    ) {
        Surface(
            color = if (isStopped) Color(0xFFB71C1C) else MaterialTheme.colorScheme.errorContainer,
            shadowElevation = 8.dp,
            modifier = Modifier.align(Alignment.TopCenter),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(
                        imageVector = if (isStopped) Icons.Filled.Block else Icons.Filled.GpsFixed,
                        contentDescription = null,
                        tint = if (isStopped) Color.White else MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = if (isStopped) "STOPPED — Phone control blocked" else "Kolo is controlling your phone",
                            style = MaterialTheme.typography.labelLarge,
                            color = if (isStopped) Color.White else MaterialTheme.colorScheme.onErrorContainer,
                            fontWeight = FontWeight.SemiBold,
                        )
                        if (message.isNotBlank()) {
                            Text(
                                text = message,
                                style = MaterialTheme.typography.bodySmall,
                                color = if (isStopped) Color.White.copy(alpha = 0.8f) else MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.8f),
                                maxLines = 1,
                            )
                        }
                    }
                }

                if (!isStopped) {
                    FilledIconButton(
                        onClick = {
                            PhoneControlAccessibilityService.emergencyStop()
                            onStop()
                        },
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = MaterialTheme.colorScheme.error,
                            contentColor = Color.White,
                        ),
                        modifier = Modifier.size(48.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Stop,
                            contentDescription = "STOP",
                            modifier = Modifier.size(28.dp),
                        )
                    }
                }
            }
        }
    }
}