# Kolo AI Agent

Kolo is a native Android AI assistant built in Kotlin and Jetpack Compose. It
combines streaming chat, OpenAI-compatible cloud providers, on-device GGUF
inference through llama.cpp, memory, tool calling, phone-control workflows, and
provider/model management in one app.

The active rewrite lives in `kolo-native/`. The older Flutter code is still in
the repository for reference during feature parity work, but new development is
focused on the native Android app.

## Current Highlights

- Native Android UI with Jetpack Compose and Material 3.
- Multi-chat history with folders, pinned chats, search, attachments, prompt
  templates, streaming responses, and cancel generation.
- Provider presets for OpenAI, Groq, OpenRouter, Ollama local, Fireworks,
  Together AI, Ollama Cloud, and custom OpenAI-compatible endpoints.
- Chat-level model picker with fetch/refresh support for provider model lists.
- Full provider editor for base URL, models endpoint, custom headers, API key,
  model selection, and provider activation.
- Local GGUF model management with the in-app llama.cpp JNI runtime.
- CPU or Vulkan GPU offload settings for local llama.cpp inference.
- Prompt-prefix caching for local llama.cpp turns inside the same chat.
- Tool calling with explicit safe, sensitive, and dangerous permission gates.
- Built-in tools for web search, web scrape, HTTP, JSON, base64, hashing,
  calculator, date, Android device info, memory recall, memory writing, and
  phone control.
- Phone-control tools for screen reading, screenshots, taps, swipes, text
  input, key presses, scrolling, long press, click-by-text, status, and stop.
- Memory management, custom tool authoring, skills UI, app instructions,
  appearance settings, and diagnostics.

## Repository Layout

```text
kolo-native/
  app/                    Android app, navigation, DI, theme
  core/model/             Shared models, provider presets, tool schemas
  core/database/          Room entities, DAOs, migrations, repositories
  core/providers/         OpenAI-compatible client, secure provider storage,
                          llama.cpp JNI bridge and native build
  core/agent/             Agent loop, streaming, tool-call orchestration
  core/tools/             Tool contract, registry, built-in tools, permissions
  feature/chat/           Chat screen, drawer, messages, attachments
  feature/settings/       Providers, local models, tools, memory, skills
  feature/phonecontrol/   Android phone-control tools and UI surfaces
  third_party/llama.cpp/  llama.cpp source used by the Android native bridge
  third_party/Vulkan-Headers/

android/, ios/, lib/      Legacy Flutter app kept for reference
docs/                     Planning, audits, and implementation notes
scripts/, tools/, tool/   Project support scripts
```

## Requirements

- Android Studio or Android SDK command-line tools.
- JDK 17.
- Android NDK and CMake installed through the Android SDK.
- A connected Android device or emulator for install/testing.
- For local GGUF inference, use an Android device with enough RAM for the model.
  Vulkan acceleration requires a Vulkan-capable device and driver.

The native project uses the Gradle wrapper checked into `kolo-native/`; no
global Gradle install is required.

## Build

```sh
cd kolo-native
./gradlew :app:assembleDebug
```

The debug APK is written to:

```text
kolo-native/app/build/outputs/apk/debug/app-debug.apk
```

Install it on a connected device:

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The debug app package is `com.kolo.agent.debug`.

## Release Builds

Release builds enable minification, resource shrinking, backup hardening, and
disable cleartext traffic by default:

```sh
cd kolo-native
./gradlew :app:assembleRelease
```

Without signing configuration, Gradle writes an unsigned release APK for local
verification. To produce a signed release artifact, provide these values through
environment variables or Gradle properties outside Git:

```sh
KOLO_RELEASE_STORE_FILE=/absolute/path/to/release.jks
KOLO_RELEASE_STORE_PASSWORD=...
KOLO_RELEASE_KEY_ALIAS=...
KOLO_RELEASE_KEY_PASSWORD=...
```

The build fails if only part of the signing configuration is present. Do not
commit keystores, passwords, generated APKs, or generated AABs.

## Tests

Run the main native unit tests:

```sh
cd kolo-native
./gradlew :core:model:testDebugUnitTest \
  :core:tools:testDebugUnitTest \
  :core:providers:testDebugUnitTest
```

Build plus tests:

```sh
cd kolo-native
./gradlew :app:assembleDebug \
  :core:model:testDebugUnitTest \
  :core:tools:testDebugUnitTest \
  :core:providers:testDebugUnitTest
```

Legacy Flutter tests are still available when working on the old app:

```sh
flutter test --no-pub
flutter test --coverage --no-pub
dart tool/coverage_gate.dart --min-line=14.3
```

## Provider Setup

1. Open Settings.
2. Go to Providers.
3. Add a preset or create a custom OpenAI-compatible provider.
4. Enter the API key if the provider requires one.
5. Use the model picker in chat or the provider detail screen to fetch and
   select models.

Provider configuration supports custom base URLs, model endpoints, headers, API
keys, active model selection, and local llama.cpp providers.

## Local GGUF Models

Local inference is handled in-process through llama.cpp, not through Termux or a
separate server.

1. Open Settings > Local Models.
2. Import a `.gguf` model from device storage.
3. Create or select a `Local llama.cpp` provider.
4. Choose CPU or GPU offload settings.
5. Return to chat and select the local provider/model.

The Android native bridge keeps prompt-prefix cache state for the active local
session, so repeated turns in the same chat avoid reprocessing shared prompt
prefixes where possible.

## Tools And Safety

Kolo separates tools into permission classes:

- `safe`: can run automatically.
- `sensitive`: requires review by default.
- `dangerous`: requires explicit approval and is used for phone-control actions.

The settings UI lets users set each tool to always allow, ask every time, or
never allow. Custom tools and composed tools pass through the same permission
system.

## Development Notes

- Keep active native work inside `kolo-native/` unless intentionally touching
  the legacy Flutter app.
- Prefer existing modules and patterns before adding new abstractions.
- Do not commit API keys, `.env` files, signing credentials, model files, or
  generated APKs.
- Large toolchain archives and model files should stay outside Git history.
- Current planning details are in `docs/native_kotlin_rebuild_plan.md`.

## Status

Kolo Native is under active development. The app already supports a usable
native chat and agent workflow, but provider behavior, local inference
performance, and feature parity with the older Flutter app are still being
iterated.
