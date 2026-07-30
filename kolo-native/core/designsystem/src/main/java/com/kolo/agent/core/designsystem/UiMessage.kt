package com.kolo.agent.core.designsystem

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier

/**
 * One-shot UI message (Snackbar) model shared across screens.
 *
 * ViewModels expose a `Flow<UiMessage>` of results (save/delete/import success
 * or failure); screens collect it and hand it to [rememberKoloSnackbarController].
 *
 * @param text message body
 * @param kind visual treatment (error → red, success → primary, neutral → default)
 * @param actionLabel optional action button label (e.g. "Retry"); requires [onAction]
 * @param onAction invoked when the action button is tapped
 */
data class UiMessage(
    val text: String,
    val kind: Kind = Kind.NEUTRAL,
    val actionLabel: String? = null,
    val onAction: (() -> Unit)? = null,
) {
    enum class Kind { NEUTRAL, SUCCESS, ERROR }

    companion object {
        fun success(text: String) = UiMessage(text, Kind.SUCCESS)
        fun error(text: String, actionLabel: String? = null, onAction: (() -> Unit)? = null) =
            UiMessage(text, Kind.ERROR, actionLabel, onAction)
    }
}

/**
 * Tracks the active message [UiMessage.Kind] so [KoloSnackbarHost] can color the
 * Snackbar by kind (the platform [SnackbarHostState] does not expose kind).
 */
class KoloSnackbarController {
    val hostState: SnackbarHostState = SnackbarHostState()
    var activeKind by mutableStateOf<UiMessage.Kind?>(null)
        private set

    suspend fun show(message: UiMessage) {
        activeKind = message.kind
        val result = hostState.showSnackbar(
            message = message.text,
            actionLabel = message.actionLabel,
            duration = if (message.kind == UiMessage.Kind.ERROR) SnackbarDuration.Long else SnackbarDuration.Short,
        )
        if (result == SnackbarResult.ActionPerformed) message.onAction?.invoke()
    }
}

/**
 * Non-suspend entry point for posting a [UiMessage] from deep call sites
 * (e.g. clipboard helpers, menu onClick lambdas) that don't have a coroutine
 * scope. Provided via [LocalMessageSink]; defaults to a no-op so previews/tests
 * don't crash. The host wraps it in a coroutine launch.
 */
typealias MessageSink = (UiMessage) -> Unit

/** CompositionLocal carrying the ambient message sink. Defaults to no-op. */
val LocalMessageSink = compositionLocalOf<MessageSink> { { } }

/** Remembers a single [KoloSnackbarController] per composition. */
@Composable
fun rememberKoloSnackbarController(): KoloSnackbarController = remember { KoloSnackbarController() }

/**
 * [SnackbarHost] variant that tints the Snackbar by the active message kind:
 * error → [errorContainer], success → [primaryContainer], neutral → default inverse surface.
 */
@Composable
fun KoloSnackbarHost(
    controller: KoloSnackbarController,
    modifier: Modifier = Modifier,
) {
    val container = when (controller.activeKind) {
        UiMessage.Kind.ERROR -> MaterialTheme.colorScheme.errorContainer
        UiMessage.Kind.SUCCESS -> MaterialTheme.colorScheme.primaryContainer
        else -> MaterialTheme.colorScheme.inverseSurface
    }
    val contentColor = when (controller.activeKind) {
        UiMessage.Kind.ERROR -> MaterialTheme.colorScheme.onErrorContainer
        UiMessage.Kind.SUCCESS -> MaterialTheme.colorScheme.onPrimaryContainer
        else -> MaterialTheme.colorScheme.inverseOnSurface
    }
    SnackbarHost(hostState = controller.hostState, modifier = modifier) { data ->
        Snackbar(
            snackbarData = data,
            containerColor = container,
            contentColor = contentColor,
        )
    }
}
