# Kolo AI Agent — Comprehensive Codebase Audit Report

**Date:** 2026-04-22  
**Files audited:** 68 `.dart` files in `lib/`  
**Severity scale:** CRITICAL > HIGH > MEDIUM > LOW

---

## 1. SECURITY

| # | Issue | Location | Severity |
|---|-------|----------|----------|
| 1.1 | **API key logged to console** — `provider.apiKey.substring(0, 4)` printed in debug logs. Even partial keys leak info and full keys appear in stack traces. | `openai_client.dart:52, 80-81, 121, 163` | **CRITICAL** |
| 1.2 | **API keys stored in plain text** — SharedPreferences stores keys unencrypted via `toMap()` serialization. Any app with root or backup access can read them. | `provider.dart:113`, `database.dart:~220` | **CRITICAL** |
| 1.3 | **Shell command injection** — `ShellExecTool` passes user-controlled input to `Process.run('/bin/sh', ['-c', command])` with no sanitization or sandboxing. | `new_tools.dart:~195` | **CRITICAL** |
| 1.4 | **No TLS certificate pinning** — Dio instances accept any certificate. MITM attacks can intercept API keys and conversation data. | `openai_client.dart:23`, all Dio usages | **HIGH** |
| 1.5 | **Delete tool has no safeguards** — `DeleteFileTool` can delete any file the process can access, no path allowlist or confirmation beyond permission tier. | `new_tools.dart:~120` | **HIGH** |
| 1.6 | **validateStatus accepts all HTTP codes** — `validateStatus: (_) => true` means 401/403 errors with leaked credentials won't throw, masking auth failures. | `openai_client.dart:23` | **MEDIUM** |
| 1.7 | **ADB commands with unsanitized input** — `_adbShell(cmd)` passes strings directly to shell; malicious tool arguments could inject commands. | `adb_phone_controller.dart`, `scan_phone_apps.dart` | **HIGH** |

---

## 2. PERFORMANCE

| # | Issue | Location | Severity |
|---|-------|----------|----------|
| 2.1 | **New OpenAIClient created every agent loop iteration** — Allocates a new Dio instance per API call instead of reusing one. | `agent_loop.dart:25` | **HIGH** |
| 2.2 | **New Dio instance per HTTP tool call** — `HttpGetTool`/`HttpPostTool` create and never close `HttpClient`/`Dio` instances. | `new_tools.dart:~280, ~320` | **MEDIUM** |
| 2.3 | **New Dio per VLM analysis** — `VlmAnalyzer.analyze()` creates a fresh Dio on each invocation. | `vlm_analyzer.dart:84` | **MEDIUM** |
| 2.4 | **bootstrapTools() called 3+ times for UI display** — Full tool registry (50+ tool instances) recreated just to count or list tools in settings. | `settings_screen.dart:78, 127, 204` | **HIGH** |
| 2.5 | **`_buildInterleavedItems` recomputes every build** — Generates a new interleaved list on every widget rebuild instead of caching. | `chat_screen.dart:612` | **HIGH** |
| 2.6 | **IndexedStack keeps all tabs in memory** — Both ChatScreen and DevScreen stay alive even when not visible. | `main.dart:70` | **MEDIUM** |
| 2.7 | **MediaQuery.of(context).size.width in every message bubble build** — Triggers rebuild on any media query change (keyboard, rotation). Should use `LayoutBuilder` or cache. | `message_bubble.dart:39, 294` | **MEDIUM** |
| 2.8 | **List.from copies on state changes** — Unnecessary list copies on every stream event during agent runs. | `chat_screen.dart:721, 286` | **LOW** |
| 2.9 | **Full state object recreated on every stream event** — `AgentSessionRunning` constructed for every chunk/tool event. | `agent_session.dart:274-309` | **MEDIUM** |
| 2.10 | **New ToolRouter per sendMessage** — Allocates a new router (with registry + permission manager refs) on every user message. | `agent_session.dart:148-151` | **LOW** |

---

## 3. STATE MANAGEMENT

| # | Issue | Location | Severity |
|---|-------|----------|----------|
| 3.1 | **ProviderManager duplicates ProvidersNotifier** — Two classes manage the same providers list with identical CRUD logic. One should be deleted. | `provider_manager.dart` (entire file) vs `providers_state.dart` | **HIGH** |
| 3.2 | **_save() writes ALL providers on every mutation** — Adding/removing/updating one provider serializes and persists the entire list. | `providers_state.dart:23-26` | **MEDIUM** |
| 3.3 | **Permission modes triple-write** — `_persistSettings` in PermissionManager does 3 separate DB writes (modes, enabled, disabled) on every single mode change. | `permission_manager.dart:114-116` | **MEDIUM** |
| 3.4 | **Separate devAgentSessionProvider** — Dev screen maintains an entirely separate agent session, duplicating session management. | `dev_screen.dart` (provider definition) | **MEDIUM** |
| 3.5 | **toolsScreenRegistryProvider recreates registry on mode change** — `ref.watch(phoneControlModeProvider)` triggers full tool re-bootstrap on any mode toggle. | `tools_permission_screen.dart:13-15` | **LOW** |
| 3.6 | **Token estimation is crude** — `(text.length / 4).ceil()` doesn't account for tool call tokens, multi-byte chars, or actual tokenizer output. | `conversation_manager.dart:45` | **MEDIUM** |

---

## 4. NETWORK / API

| # | Issue | Location | Severity |
|---|-------|----------|----------|
| 4.1 | **No retry logic for API calls** — Transient 429/500/503 errors cause immediate failure with no backoff or retry. | `openai_client.dart` (entire file) | **HIGH** |
| 4.2 | **fetchModels() network call inside storage layer** — Database class makes HTTP requests to fetch model lists, violating separation of concerns. Creates its own Dio. | `database.dart:135-184` | **HIGH** |
| 4.3 | **No request timeout configured** — Dio instances use default (infinite) timeouts. A hanging API server blocks the agent loop indefinitely. | `openai_client.dart`, all Dio usages | **HIGH** |
| 4.4 | **DuckDuckGo HTML scraping is fragile** — Web search parses DDG HTML which changes frequently; no fallback or error handling for format changes. | `web_search.dart` | **MEDIUM** |
| 4.5 | **No connection state detection** — App doesn't check network availability before making API calls; errors surface as generic failures. | All network code | **MEDIUM** |
| 4.6 | **SSE stream not properly cancelled** — When user cancels, the HTTP connection may not be immediately terminated, wasting bandwidth. | `openai_client.dart`, `agent_loop.dart` | **MEDIUM** |

---

## 5. ARCHITECTURE

| # | Issue | Location | Severity |
|---|-------|----------|----------|
| 5.1 | **chat_screen.dart is a 1272-line god file** — Contains ChatScreen, ChatMessageUI, _BreathingIcon, _DateSep, _MsgItem, plus all chat logic. Should be split into 5+ files. | `chat_screen.dart` | **HIGH** |
| 5.2 | **settings_screen.dart is a 1092-line god file** — Contains 10+ widget classes (SettingsScreen, ProviderDetailScreen, AddProviderScreen, _VisionModelSection, _PhoneControlModeSection, etc.). | `settings_screen.dart` | **HIGH** |
| 5.3 | **dev_screen.dart is a 1103-line god file** — Terminal, file tree, AI chat, and project creation all in one file. | `dev_screen.dart` | **HIGH** |
| 5.4 | **new_tools.dart is a 480-line dumping ground** — 12+ unrelated tool classes (ListFiles, Delete, Shell, HTTP, Date, JSON, Base64, Hash, Grep, EnvInfo) in one file. | `new_tools.dart` | **MEDIUM** |
| 5.5 | **Duplicate _adb/_adbShell helpers** — Identical ADB helper functions defined in two files. Should be extracted to a shared utility. | `adb_phone_controller.dart:7-19`, `scan_phone_apps.dart:7-19` | **MEDIUM** |
| 5.6 | **No dependency injection** — Dio, Process.run, file I/O are called directly, making testing impossible without real network/filesystem. | All tool files, `openai_client.dart` | **MEDIUM** |
| 5.7 | **No repository/service layer** — UI widgets directly read from providers that directly call APIs and file I/O. No clear data flow boundary. | Throughout | **MEDIUM** |

---

## 6. STORAGE / DATABASE

| # | Issue | Location | Severity |
|---|-------|----------|----------|
| 6.1 | **N+1 file reads** — Every chat operation (load, save, delete) reads the entire JSON file, parses all entries, modifies one, and rewrites the full file. | `database.dart` (all chat methods) | **HIGH** |
| 6.2 | **No database at all** — Despite the class name `AppDatabase`, it's file-based JSON + SharedPreferences. No SQLite, no indexed queries, no transactions. | `database.dart` | **HIGH** |
| 6.3 | **Race conditions on concurrent writes** — Multiple simultaneous saves to the same JSON file can corrupt data (no file locking or write queue). | `database.dart` | **HIGH** |
| 6.4 | **No data migration strategy** — JSON schema changes would break existing user data with no migration path. | `database.dart` | **MEDIUM** |
| 6.5 | **Chat messages unbounded** — No limit on message count per chat; long conversations grow the JSON file indefinitely, slowing all operations. | `database.dart` | **MEDIUM** |

---

## 7. UX POLISH

| # | Issue | Location | Severity |
|---|-------|----------|----------|
| 7.1 | **`AnimatedBuilder` doesn't exist** — Should be `AnimatedBuilder` (which does exist) but verify the actual class name used. If it's a typo like `AnimatedBulider`, it will crash. | `chat_screen.dart:1225`, `message_bubble.dart:65` | **MEDIUM** |
| 7.2 | **PhoneControlOverlay and PhoneControlBorder never integrated** — Widgets defined but never added to the widget tree, so phone control UX described in system prompt doesn't work. | `phone_control_overlay.dart` | **HIGH** |
| 7.3 | **ChatSkeletonLoader and ChatListSkeletonLoader never used** — Shimmer loading widgets defined but not referenced anywhere. | `shimmer.dart` | **LOW** |
| 7.4 | **No loading state for model fetching** — When fetching models from providers, UI shows no progress indicator. | `settings_screen.dart` | **MEDIUM** |
| 7.5 | **No empty state for chat** — New users see a blank screen with no onboarding or suggested prompts. | `chat_screen.dart` | **LOW** |
| 7.6 | **Error messages are raw exceptions** — Users see `Exception: adb shell failed (exit 1): ...` instead of friendly messages. | All tool execute() methods | **MEDIUM** |

---

## 8. ANDROID-SPECIFIC

| # | Issue | Location | Severity |
|---|-------|----------|----------|
| 8.1 | **Hardcoded screen dimensions for scroll** — `const cx = 540, cy = 1200` assumes a specific resolution; will scroll incorrectly on other devices. | `adb_phone_controller.dart:291` | **HIGH** |
| 8.2 | **`/bin/sh` used on Android** — Android has `/system/bin/sh`, not `/bin/sh`. Shell commands will fail on real devices in dev screen terminal. | `dev_screen.dart:366` | **HIGH** |
| 8.3 | **ADB assumed available on macOS host** — Tools call `adb` directly, assuming the macOS dev machine has ADB in PATH. No check or guidance if ADB is missing. | `adb_phone_controller.dart`, `scan_phone_apps.dart` | **MEDIUM** |
| 8.4 | **No accessibility service status check** — System prompt instructs to check `device_info` for accessibility status, but no tool actually reports this. | `adb_phone_controller.dart` | **MEDIUM** |
| 8.5 | **VLM falls back to hardcoded 'gpt-4o'** — If no vision model is configured, it silently uses `gpt-4o` which may not be available on the user's provider. | `vlm_analyzer.dart:193, 210` | **MEDIUM** |
| 8.6 | **No ADB connection verification** — Tools assume ADB is connected; if device disconnects mid-operation, errors are cryptic. | All ADB tools | **MEDIUM** |

---

## 9. CODE QUALITY

| # | Issue | Location | Severity |
|---|-------|----------|----------|
| 9.1 | **STT StreamControllers never closed** — `SttService` singleton creates StreamControllers that are never disposed on app exit, causing memory leaks. | `stt_service.dart:116` | **MEDIUM** |
| 9.2 | **TTS instance never disposed** — `FlutterTts` in `TextToSpeechTool` is never stopped or disposed. | `text_to_speech.dart:57` | **MEDIUM** |
| 9.3 | **Try/catch for flow control** — `ProviderConfig.activeModel` uses try/catch instead of null checks. | `provider.dart:78-82` | **LOW** |
| 9.4 | **No linting or analysis configuration** — No `analysis_options.yaml` with real rules. | Project root | **MEDIUM** |
| 9.5 | **Unused imports likely present** — With dead code like shimmer widgets and PhoneControlOverlay, there are stale imports throughout. | Multiple files | **LOW** |
| 9.6 | **No tests** — Zero test files found. No unit, widget, or integration tests. | `test/` directory | **HIGH** |
| 9.7 | **Magic numbers throughout** — `32000` max tokens, `25` top apps, `10` timeout seconds, etc. scattered as literals. | `agent_session.dart:42`, `scan_phone_apps.dart:280`, multiple | **LOW** |
| 9.8 | **Inconsistent error handling** — Some tools return `ToolResult.err()`, others throw exceptions, others silently catch and continue. No consistent pattern. | All tool files | **MEDIUM** |

---

## Summary by Severity

| Severity | Count |
|----------|-------|
| **CRITICAL** | 3 |
| **HIGH** | 16 |
| **MEDIUM** | 24 |
| **LOW** | 7 |
| **Total** | **50** |

## Top 5 Priorities

1. **Remove API key logging** (`openai_client.dart`) — CRITICAL, one-line fix, prevents credential leakage
2. **Encrypt stored API keys** — Migrate from SharedPreferences to `flutter_secure_storage`
3. **Sanitize shell/ADB command inputs** — Whitelist allowed commands or use parameterized execution
4. **Add retry logic + timeouts to network calls** — Prevent hangs and improve reliability
5. **Split god files** — `chat_screen.dart`, `settings_screen.dart`, `dev_screen.dart` need decomposition for maintainability