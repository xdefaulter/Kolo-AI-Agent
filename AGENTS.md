# AGENTS.md

Kolo is a phone-resident AI agent for Android. It provides a streaming chat UI, on-device GGUF inference via llama.cpp, an extensible tool-calling system with permission gating, long-term memory, and AccessibilityService-based phone control.

The active codebase is the native Android app in `kolo-native/`. The legacy Flutter app (`lib/`, `pubspec.yaml`, `android/`, `ios/`, `test/`) is retained for reference only.

## Tech stack

- **Language:** Kotlin
- **UI:** Jetpack Compose, Material 3
- **DI:** Hilt (Dagger)
- **Persistence:** Room (SQLite), DataStore (preferences)
- **Networking:** OkHttp (SSE streaming), HttpURLConnection (tools)
- **Serialization:** kotlinx.serialization
- **Local inference:** llama.cpp via JNI/CMake (native bridge `libkolo_llama_bridge.so`)
- **Build:** Gradle Kotlin DSL with version catalog (`kolo-native/gradle/libs.versions.toml`)

## Module map

All paths are relative to `kolo-native/`.

### `app/`
Application shell — `MainActivity`, navigation graph (`KoloNavApp`), Hilt application (`KoloApp`), DI modules, theme, `AndroidManifest.xml`, `proguard-rules.pro`.

### `core/model/`
Shared domain models, ID types, agent events, tool execution result types. No Android dependencies.

### `core/database/`
Room database, entities, DAOs, `Converters`, `RoomMemoryRepository`. Schema exports under `schemas/`.

### `core/providers/`
- `ProviderRepository` — DataStore-backed provider configs + secure API key storage.
- `ProviderConfigKeyStore` — in-memory API key lookup by provider ID.
- `openai/OpenAiStreamClient` — SSE streaming chat client for OpenAI-compatible endpoints.
- `local/` — llama.cpp JNI bridge (`LlamaCppBridge`, `LlamaCppEngine`), `LocalModelManager`, `LocalLlmEngine` interface.
- `secure/SecureKeyStore` — EncryptedSharedPreferences key storage.
- `settings/AppSettings` — DataStore-backed app preferences.
- `ToolPermissionStore` — per-tool permission mode persistence.

### `core/agent/`
- `AgentLoop` — the think-act-observe loop. Streams `AgentEvent`s to the UI. Handles both cloud and local inference paths, tool permission gating, and approval suspension.
- `prompt/SystemPromptComposer` — builds the system prompt from memories, skills, instructions.
- `parser/StreamingToolCallParser` — accumulates streaming tool-call deltas.

### `core/tools/`
- `KoloTool` — abstract tool contract.
- `registry/ToolRegistry` — built-in + custom tool registry, permission enforcement, argument parsing.
- `permissions/ToolPermissions` — permission level definitions (`safe`, `sensitive`, `dangerous`).
- `builtin/` — concrete tools: `CalculatorTool`, `DateTool`, `JsonParseTool`, `Base64Tool`, `HashTool`, `HttpGetTool`, `HttpPostTool`, `WebSearchTool`, `WebScrapeTool`, `AndroidDeviceTools` (clipboard, device info, battery, vibrate, contacts, location, installed apps, launch app, timer), `RememberThisTool`, `RecallMemoriesTool`, `ForgetMemoryTool`.

### `feature/chat/`
`ChatViewModel` + `ChatScreen` — streaming chat UI, model picker, tool approval banner, attachments, message bubbles.

### `feature/settings/`
`SettingsViewModel` + `SettingsScreen`, `LocalModelViewModel` + `LocalModelScreen` — provider config, local model import/management, memory management, custom tools, skills, custom instructions, theme.

### `feature/phonecontrol/`
- `PhoneControlTools` — tool definitions for phone control (tap, swipe, type, screenshot, scroll, press key).
- `service/PhoneControlAccessibilityService` — the AccessibilityService that executes phone-control actions, manages session state, and shows the STOP overlay.
- `ui/PhoneControlOverlay` — Compose-based overlay component for in-app STOP UI.

## Architecture

### Agent loop
`AgentLoop.run()` emits a `Flow<AgentEvent>`. Cloud mode streams from `OpenAiStreamClient.chatStream()`, parses tool calls via `StreamingToolCallParser`, executes tools through `ToolRegistry`, and loops until completion or max iterations. Local mode builds a text prompt, streams from `LocalLlmEngine.completeStream()`, and parses tool calls from the raw text output.

Tool execution is permission-gated: `safe` tools auto-execute, `sensitive` tools prompt the user (with remember choice), `dangerous` tools always prompt. The agent loop suspends via `approvalCallback` until the UI resumes the continuation.

### Tool system
Tools implement `KoloTool` with a `name`, `description`, `parameterSchema` (JSON schema string), `permission` level, and `execute()` returning `ToolExecutionResult`. `ToolRegistry` filters tools by platform (Android/iOS), provider disabled-tools config, and small-model mode. Custom tools (`CustomToolDef`) can be prompt-based (sub-LLM call) or composed (chained tool steps).

### Memory
`RoomMemoryRepository` backs the `MemoryRepository` interface. `RememberThisTool` saves memories, `RecallMemoriesTool` searches them with LIKE queries, `ForgetMemoryTool` deletes. Memories are included in the system prompt via `SystemPromptComposer`.

### Phone control
The `PhoneControlAccessibilityService` runs as a bound accessibility service. `phone_control_start` begins a session, `phone_control_done` ends it. The STOP overlay (TYPE_ACCESSIBILITY_OVERLAY) is always visible during an active session. Session state machine: `inactive → active → stoppedByUser`.

## Conventions

- **Coroutines:** Use `viewModelScope` in ViewModels. IO operations must use `withContext(Dispatchers.IO)`. Never block the main thread.
- **Null safety:** Avoid `!!`. Use safe calls, `?.let`, and `orEmpty()`. Prefer `runCatching` for deserialization.
- **State management:** `MutableStateFlow` / `StateFlow` for UI state. Use `combine` for multi-source state. Collect flows in `init` blocks.
- **Serialization:** Use a lenient `Json { ignoreUnknownKeys = true }` instance for deserialization. Never use the default strict `Json` for reading from storage.
- **Threading:** Shared mutable state accessed from multiple coroutines must be thread-safe (`ConcurrentHashMap`, `@Volatile`, `Mutex`, or `AtomicReference`).
- **Tool permissions:** `safe` = always allow, `sensitive` = ask (remember choice), `dangerous` = always ask. Never bypass the permission check.
- **Naming:** Packages are `com.kolo.agent.{module}`. Kotlin conventions (PascalCase classes, camelCase functions).

## Build and test

```bash
# All commands run from kolo-native/
cd kolo-native

# Debug build
./gradlew :app:assembleDebug

# Release build (requires signing config)
./gradlew :app:assembleRelease

# Run unit tests (no device needed)
./gradlew :core:model:testDebugUnitTest :core:tools:testDebugUnitTest :core:providers:testDebugUnitTest :core:agent:testDebugUnitTest :core:database:testDebugUnitTest

# Run all tests
./gradlew testDebugUnitTest

# Lint
./gradlew lintDebug
```

The llama.cpp native bridge requires the NDK and CMake. The submodule at `kolo-native/third_party/llama.cpp` must be fetched (`git submodule update --init`).

There is no CI/CD. All builds and tests are run locally.

## Key files

| File | Purpose |
|------|---------|
| `core/agent/.../AgentLoop.kt` | Think-act-observe loop (cloud + local) |
| `core/tools/.../registry/ToolRegistry.kt` | Tool registration, execution, permissions |
| `core/providers/.../openai/OpenAiStreamClient.kt` | SSE streaming client |
| `core/providers/.../local/LocalLlmEngine.kt` | llama.cpp engine + factory |
| `core/database/.../AppDatabase.kt` | Room database (version 2) |
| `feature/chat/.../ChatViewModel.kt` | Chat state management + agent loop collector |
| `feature/phonecontrol/.../PhoneControlAccessibilityService.kt` | Phone control service |
| `app/src/main/AndroidManifest.xml` | Permissions, service declaration |
| `app/proguard-rules.pro` | R8 keep rules |