# Native Kotlin Rebuild Plan

## Direction

Rebuild Kolo as a native Android app in Kotlin with Jetpack Compose, keeping the product scope of the current Flutter app but removing the Flutter runtime and the Termux/bootstrap installation path.

Local inference should use the official llama.cpp Android binding first. The app should treat local llama.cpp as an in-process native engine behind a Kotlin service API, not as a Termux shell, apt package, or spawned Linux-style server.

Primary goals:

- Fast, polished native Android experience.
- Reliable phone control through Android services.
- Preserve current agent, tools, permissions, memory, provider, and chat workflows.
- Support cloud OpenAI-compatible providers and on-device GGUF models.
- Build the app in layers so phone control and chat are useful before local inference is complete.

Non-goals:

- No embedded Termux.
- No runtime package manager install for llama.cpp.
- No React Native bridge for core control or inference paths.
- No attempt to port every implementation detail one-to-one if a native Android API gives a cleaner design.

## Product Surfaces To Preserve

### Chat

- Multi-chat history.
- Chat list with pinned chats, unread counts, drafts, and search.
- Message bubbles for user, assistant, system/tool status, and tool results.
- Streaming assistant responses.
- Tool call visualization while the agent is thinking and acting.
- Stop/cancel generation.
- Retry failed sends and replay saved conversations.
- Prompt library sheet.
- Offline outbox for failed network sends.
- Enter-to-send toggle.
- Export and clear chats.

### Providers

- OpenAI-compatible provider configs:
  - name
  - base URL
  - API key
  - custom headers
  - models endpoint
  - model list
  - active model
  - max tokens
  - temperature
- Presets for common providers.
- Secure API key storage.
- Model fetching from `/models`.
- Provider-specific disabled tools.
- Small-model mode that hides risky or complex tools.
- Local llama.cpp provider using a GGUF model path.

### Agent

- OpenAI-style tool calling loop.
- Streaming parser for deltas and tool calls.
- Max iteration setting.
- Per-turn system prompt composition.
- Tool registry filtered by platform, permissions, provider mode, and disabled tool list.
- Parallel independent tool execution.
- Cancellation between tool calls.
- Agent metrics: timing, token/tool activity where available.
- Long-running phone-control workflow:
  - `phone_control_start`
  - status updates
  - screen inspection/action loop
  - `phone_control_done`

### Tools

Current built-in tools to preserve:

- Web/network:
  - `web_search`
  - `web_scrape`
  - `http_get`
  - `http_post`
- Utility:
  - `calculator`
  - `json_parse`
  - `base64`
  - `hash`
  - `date`
- Device/app:
  - `connectivity`
  - `battery_info`
  - `vibrate`
  - `location`
  - `open_app`
  - `launch_app`
  - `list_installed_apps`
  - `device_info`
  - `contacts`
- Media/input:
  - `clipboard_read`
  - `clipboard_write`
  - `text_to_speech`
  - `speech_to_text`
  - `qr_code`
  - `download_file`
  - `image_metadata`
  - `timer`
- Phone control:
  - `phone_start`
  - `phone_stop`
  - `screen_read`
  - `screenshot`
  - `tap`
  - `swipe`
  - `type_text`
  - `press_key`
  - `scroll`
  - `click_text`
  - `long_press`
  - `show_action`
  - `analyze_screen`
  - `scan_phone_apps`
  - `phone_control_start`
  - `phone_control_status`
  - `phone_control_done`
- Memory:
  - `recall_memories`
  - `remember_this`
  - `forget_memory`
- Skills:
  - `list_skills`
  - `read_skill`
  - `create_skill`
- Custom tools:
  - `list_custom_tools`
  - `create_tool`
  - `delete_custom_tool`
  - prompt-kind custom tools
  - composed custom tools

ADB-mode phone control can be deferred. The native app should prioritize accessibility-mode control because it works on-device without a desktop bridge.

### Permissions And Safety

- Tool permission levels:
  - safe
  - sensitive
  - dangerous
- Per-tool modes:
  - always allow
  - ask every time
  - never allow
- Dangerous tools require explicit confirmation; biometric confirmation should be supported where available.
- Unknown tools default to ask every time.
- Tool permission settings are persisted.
- Custom tool and memory authoring are opt-in capabilities.
- Phone control must visibly indicate active control with border/status/STOP overlay.
- STOP overlay must immediately end phone-control mode and cancel pending actions.

### Memory And Skills

- Persistent memory CRUD.
- Memory recall injection into the system prompt.
- Toggle for agent-authored memories.
- Memory management screen.
- Skills as persisted multi-step playbooks.
- Skills injected into system prompt when enabled.
- Toggle for skills.
- Agent-created skill approval path.

### Settings

- Provider list and provider detail screens.
- Add provider from preset.
- Local model management.
- Tool permissions screen.
- Agent capabilities section.
- Memory section.
- Vision model selection.
- Phone control mode section.
- Web search provider settings.
- Max agent iterations.
- Data management.
- Input settings.
- Appearance theme mode.
- About/debug diagnostics.

## Native Android Architecture

### Recommended Stack

- Language: Kotlin.
- UI: Jetpack Compose + Material 3.
- Navigation: Navigation Compose.
- State: ViewModel + Kotlin Flow/StateFlow.
- Persistence:
  - Room for chats, messages, memories, folders, prompt templates, skills, custom tools.
  - DataStore for simple settings.
  - Android Keystore-backed encrypted storage for API keys.
- Networking:
  - OkHttp for streaming SSE and ordinary HTTP.
  - Kotlin serialization for JSON.
- Background work:
  - Foreground service for active phone control.
  - WorkManager for non-interactive downloads and retries.
- Native inference:
  - Official llama.cpp Android binding through NDK/JNI.
  - A Kotlin `LocalLlamaEngine` facade returning streaming tokens as `Flow`.

### Modules

Use a multi-module Android project once the first vertical slice works:

- `app`: Compose UI, navigation, dependency wiring.
- `core:model`: shared data classes and JSON schemas.
- `core:database`: Room entities, DAOs, migrations.
- `core:providers`: OpenAI-compatible client, provider management, secure keys.
- `core:agent`: agent loop, tool-call parser, system prompt builder.
- `core:tools`: tool contracts, registry, permission manager.
- `feature:chat`: chat list, thread, input bar, tool result UI.
- `feature:settings`: settings screens.
- `feature:phonecontrol`: accessibility service, overlay, screenshot, gestures.
- `feature:localllm`: llama.cpp binding facade, model manager.

Start as fewer modules if speed matters, but keep package boundaries matching this shape.

## Core Data Model

Room tables:

- `folders`
- `chats`
- `messages`
- `memories`
- `prompt_templates`
- `providers`
- `provider_models`
- `custom_tools`
- `skills`
- `settings` only if DataStore is not enough

Message fields:

- id
- chat id
- role
- content
- tool call id
- tool name
- tool success
- tool calls JSON
- status
- error
- created at
- edited at

Provider fields:

- id
- name
- kind: `openai_compat` or `local_llama`
- base URL
- models endpoint
- active flag
- model path
- disabled tools
- small model mode
- created/updated timestamps

API keys should not be stored in Room.

## UI Direction

The app should feel like a serious Android agent tool, not a generic chatbot clone.

Primary layout:

- First screen is the chat workspace.
- Navigation rail or modal drawer for chat history on large screens.
- Bottom input bar with attachment, voice, prompt library, and send/stop controls.
- Top app bar:
  - active provider/model
  - connection/local status
  - search
  - settings
- Tool activity appears inline as compact expandable result rows.
- Phone control status appears both inline and in the system overlay when active.

Visual style:

- Material 3, restrained, dense, fast.
- Avoid oversized decorative cards.
- Use compact surfaces, clear typography, predictable spacing.
- Use icons for commands.
- Support dynamic color but keep a manually tuned fallback palette.
- Light/dark/system themes.

Important polish:

- Smooth streaming without full-list recomposition.
- Stable input bar height.
- Clear empty states.
- Clear permission onboarding for accessibility and overlay.
- Model download/progress states.
- Tool permission prompts that explain the exact action.
- Error surfaces that show next steps, not stack traces.

## Local llama.cpp Plan

Use the official llama.cpp Android binding as the first implementation target.

Required Kotlin API:

```kotlin
interface LocalLlamaEngine {
    val state: StateFlow<LocalLlamaState>

    suspend fun loadModel(config: LocalModelConfig)
    fun generate(request: ChatRequest): Flow<ChatDelta>
    suspend fun cancel()
    suspend fun unload()
}
```

Capabilities to verify early:

- GGUF metadata read.
- Model load from app-private storage.
- Streaming generation as `Flow`.
- Cancellation latency.
- Chat template support.
- Context size control.
- Thread count control.
- Memory pressure behavior.
- Tool-call JSON reliability with small models.
- App background/foreground lifecycle.

Local model manager:

- Import GGUF from Android file picker.
- Copy or move model into app-private storage.
- Show model metadata, size, quantization, context defaults.
- Delete model.
- Set active local model.
- Optional Hugging Face browser later; do not block MVP on it.

## Migration Phases

### Phase 0: Product Spec And Design

Deliverables:

- Final screen map.
- Tool inventory and risk matrix.
- Database schema.
- Agent protocol contract.
- Local llama.cpp spike criteria.
- Visual design reference for chat, settings, phone overlay, and model manager.

Exit criteria:

- We can point to each current Flutter feature and mark it as preserve, redesign, defer, or remove.

### Phase 1: Native Shell

Deliverables:

- New Kotlin Android project.
- Compose theme and navigation.
- Empty chat workspace.
- Settings shell.
- Room/DataStore setup.
- Provider CRUD with encrypted API keys.
- OpenAI-compatible streaming client.

Exit criteria:

- User can add an OpenAI-compatible provider and stream a normal chat response.

### Phase 2: Agent Loop And Tool Core

Deliverables:

- Tool contract and registry.
- Tool permission manager.
- Tool-call parser.
- Agent loop with streaming and tool execution.
- Core safe tools: calculator, date, JSON, base64, hash, HTTP GET/POST.
- Tool result UI.

Exit criteria:

- Model can call simple tools and continue the conversation.

### Phase 3: Phone Control

Deliverables:

- Accessibility service.
- Foreground service.
- Overlay manager with border, STOP, and status text.
- Screen tree reader.
- Gesture tools: tap, swipe, long press, scroll, type, key events, click by text.
- Screenshot via accessibility.
- App launcher and installed app list.
- Phone-control workflow tools.

Exit criteria:

- Agent can visibly control the phone in a bounded workflow and STOP always works.

### Phase 4: Memory, Skills, Custom Tools

Deliverables:

- Memory CRUD and prompt injection.
- Agent-authored memory toggle.
- Skills storage and prompt injection.
- Custom prompt/composed tools.
- Management screens.

Exit criteria:

- Current extensibility model works without Flutter dependencies.

### Phase 5: Local llama.cpp

Deliverables:

- Official llama.cpp binding integrated.
- Local model import and metadata.
- Local provider kind.
- Streaming local generation.
- Cancellation/unload lifecycle.
- Small-model tool filtering.

Exit criteria:

- A selected GGUF model can answer locally and participate in the agent loop with an intentionally reduced tool set.

### Phase 6: Polish And Performance

Deliverables:

- Large-chat performance pass.
- Streaming recomposition profiling.
- Accessibility-service reliability tests.
- Model memory pressure tests.
- Error and retry polish.
- UI polish pass for every screen.

Exit criteria:

- App feels native and stable under real phone-control sessions.

## Risks

- Local model RAM pressure can kill the process. Mitigation: conservative defaults, model metadata warnings, unload controls, and foreground-service lifecycle awareness.
- Small local models may not reliably emit complex tool calls. Mitigation: provider-level disabled tools and small-model mode.
- Accessibility APIs vary by app and Android version. Mitigation: combine accessibility tree, screenshot analysis, and explicit recovery prompts.
- JNI crashes can take down the app. Mitigation: isolate llama.cpp lifecycle, test model load/unload heavily, and keep cloud provider fallback.
- Feature parity can bloat the first release. Mitigation: ship vertical slices in phases and keep ADB mode/Hugging Face browser as deferrable.

## First Implementation Milestone

The first build should not include every feature. It should prove the native direction:

1. Chat screen.
2. Provider setup.
3. Streaming OpenAI-compatible chat.
4. Tool loop with calculator/date.
5. Accessibility permission onboarding.
6. Basic phone-control overlay and STOP button.

Once that feels fast and stable, continue into the full phone-control and local llama.cpp work.
