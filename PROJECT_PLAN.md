# Kolo AI Agent — Project Plan

## 1. Vision

Kolo AI Agent is a thin chat client + autonomous AI agent for iOS and Android. It connects to any OpenAI-compatible API endpoint and wields a massive toolbox — from browsing the web to controlling Android apps with sudo-level permissions. The goal: an AI that can do anything your phone can do, and more.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                Flutter UI Layer                  │
│  Chat View │ Tool Output Views │ Settings       │
├─────────────────────────────────────────────────┤
│              Agent Core (Dart)                   │
│  Message Pump │ Tool Router │ Streaming Parser  │
├─────────────────────────────────────────────────┤
│               Tool Bridge                        │
│  ┌──────────┬──────────┬───────────┬───────────┐  │
│  │ Standard │ Platform │ Android   │ Android   │  │
│  │ Tools    │ Tools    │ Shell     │ Automation│  │
│  │ (cross)  │ (ch)     │ (Shizuku)│ (MAccess) │  │
│  └──────────┴──────────┴───────────┴───────────┘  │
├─────────────────────────────────────────────────┤
│          API Provider Layer                      │
│  OpenAI-Compatible │ Custom Headers │ Auth       │
└─────────────────────────────────────────────────┘
```

---

## 3. Tech Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| UI | Flutter 3.x | Single codebase, iOS + Android |
| Language | Dart (UI/core) + Kotlin (Android platform) + Swift (iOS platform) | Platform channels for native access |
| State Mgmt | Riverpod | Lightweight, testable |
| Local DB | Drift (SQLite) | Chat history, tool results, settings |
| Networking | Dio | Streaming SSE for chat completions |
| API Format | OpenAI Chat Completions (function calling) | Any compatible endpoint |
| Android Shell | Shizuku + ADB shell | Sudo-level commands |
| Android Automation | AccessibilityService + AndroidAutomation | App control, UI interaction |
| iOS Automation | Shortcuts / URL schemes | Limited vs Android (by design) |
| File Storage | Platform paths + scoped storage | Documents, Downloads, app-specific |
| Local Server | Shelf (Dart) | Spin up HTTP server on device |
| Code Execution | Dart isolate + process runner | Run scripts, compile & execute |

---

## 4. Core Components

### 4.1 API Provider Manager

- User configures endpoint URL, API key, model name, custom headers
- Supports multiple saved profiles (e.g., OpenAI, local Ollama, Fireworks, custom)
- Hot-swap provider mid-conversation
- Streaming SSE response parser
- Token usage tracking per-request
- Function calling / tool_use format (OpenAI spec)
- Fallback provider if primary fails

### 4.2 Chat Engine

- Full conversation history with token budget management (sliding window)
- System prompt configuration (per-profile or per-chat)
- Multi-turn tool-use loop: model calls tool → tool returns → model continues
- Streaming markdown rendering in chat bubbles
- Code block syntax highlighting
- Image/media in messages (vision models)
- Chat branching (fork conversation at any message)
- Export chat as Markdown / JSON

### 4.3 Tool Router

- Central registry of all available tools
- Maps function names from API response → Dart/Kotlin/Swift executors
- Permission gating: tools marked as dangerous require user confirmation
- Tool output formatted as JSON back to model
- Tool timeout + cancellation
- Async parallel tool execution when model requests multiple tools

### 4.4 Permission & Safety System

- 3-tier permission model:
  - **Safe**: file read, web search, calculator — auto-approved
  - **Sensitive**: file write, install apps, send messages — user prompt
  - **Dangerous**: root shell, system modify, app data modify — require biometric/PIN + explicit
- Per-tool permission toggles in settings
- Audit log of every tool invocation
- Rate limiting per tool
- dry-run mode (preview what tool will do before executing)

---

## 5. Tool Catalog

### 5.1 Cross-Platform Tools (iOS + Android)

| # | Tool | Description | Permission |
|---|------|-------------|-----------|
| 1 | **web_search** | Search the internet (DuckDuckGo, Google, Brave) | Safe |
| 2 | **web_scrape** | Fetch & extract text/links from URL | Safe |
| 3 | **web_scrape_screenshot** | Render page, return screenshot + text | Safe |
| 4 | **read_file** | Read file contents from device storage | Sensitive |
| 5 | **write_file** | Create or overwrite a file | Sensitive |
| 6 | **append_file** | Append to existing file | Sensitive |
| 7 | **delete_file** | Delete a file | Sensitive |
| 8 | **list_directory** | List files in a directory | Safe |
| 9 | **file_info** | Get file metadata (size, date, type) | Safe |
| 10 | **calculator** | Evaluate math expressions | Safe |
| 11 | **run_code** | Execute code in sandboxed Dart isolate (JS, Python via Chaquopy on Android) | Sensitive |
| 12 | **local_server** | Start HTTP server on device (Shelf) | Sensitive |
| 13 | **stop_server** | Stop running local server | Sensitive |
| 14 | **clipboard_read** | Read clipboard contents | Sensitive |
| 15 | **clipboard_write** | Write to clipboard | Sensitive |
| 16 | **share_content** | Share text/file via system share sheet | Safe |
| 17 | **download_file** | Download file from URL to device | Sensitive |
| 18 | **take_photo** | Capture photo from camera | Sensitive |
| 19 | **pick_image** | Pick image from gallery | Safe |
| 20 | **ocr** | Extract text from image | Safe |
| 21 | **qrcode_scan** | Scan QR code from camera/image | Safe |
| 22 | **qrcode_generate** | Generate QR code | Safe |
| 23 | **text_to_speech** | Read text aloud | Safe |
| 24 | **speech_to_text** | Voice input / transcription | Safe |
| 25 | **calendar_read** | Read calendar events | Sensitive |
| 26 | **calendar_create** | Create calendar event | Sensitive |
| 27 | **contacts_read** | Read contacts | Sensitive |
| 28 | **location_get** | Get current GPS location | Sensitive |
| 29 | **maps_open** | Open location in maps app | Safe |
| 30 | **notification_read** | Read notifications (limited on iOS) | Sensitive |
| 31 | **notification_post** | Post local notification | Safe |
| 32 | **alarm_set** | Set alarm | Safe |
| 33 | **timer_set** | Start a timer | Safe |
| 34 | **weather_get** | Fetch weather for location | Safe |
| 35 | **currency_convert** | Real-time currency conversion | Safe |
| 36 | **unit_convert** | Unit conversion | Safe |
| 37 | **json_parse** | Parse/format JSON | Safe |
| 38 | **regex_match** | Run regex on text | Safe |
| 39 | **diff_text** | Compare two texts, show diff | Safe |
| 40 | **password_generate** | Generate secure password | Safe |
| 41 | **hash_compute** | Compute SHA/MD5 hash of file or text | Safe |
| 42 | **base64_encode/decode** | Encode/decode base64 | Safe |
| 43 | **url_encode/decode** | Encode/decode URLs | Safe |
| 44 | **pdf_read** | Extract text from PDF | Safe |
| 45 | **pdf_create** | Generate PDF from content | Sensitive |
| 46 | **image_resize** | Resize/compress image | Safe |
| 47 | **image_convert** | Convert image format | Safe |
| 48 | **zip_create** | Create ZIP archive | Sensitive |
| 49 | **zip_extract** | Extract ZIP archive | Sensitive |
| 50 | **wifi_info** | Get WiFi network info | Sensitive |
| 51 | **bluetooth_scan** | Scan Bluetooth devices | Sensitive |
| 52 | **ping** | Ping a host | Safe |
| 53 | **dns_lookup** | DNS query | Safe |
| 54 | **ip_lookup** | Get public IP, geo info | Safe |
| 55 | **ssh_connect** | SSH into remote server | Dangerous |
| 56 | **ssh_exec** | Execute command on remote server | Dangerous |
| 57 | **ftp_upload/download** | File transfer to/from FTP | Dangerous |
| 58 | **git_clone** | Clone a git repository | Sensitive |
| 59 | **git_commit** | Stage and commit changes | Sensitive |
| 60 | **timestamp** | Get current time in various formats | Safe |

### 5.2 Android-Only Tools

| # | Tool | Description | Permission |
|---|------|-------------|-----------|
| 61 | **shell_exec** | Run shell command (Shizuku/root) | Dangerous |
| 62 | **shell_exec_root** | Run command as root (requires Shizuku/ADB) | Dangerous |
| 63 | **app_install** | Install APK from URL or file | Dangerous |
| 64 | **app_uninstall** | Uninstall an app | Dangerous |
| 65 | **app_launch** | Launch an app by package name | Safe |
| 66 | **app_list** | List installed apps | Safe |
| 67 | **app_info** | Get app version, permissions, data size | Safe |
| 68 | **app_force_stop** | Force stop an app | Sensitive |
| 69 | **app_clear_data** | Clear app data/cache | Dangerous |
| 70 | **app_grant_permission** | Grant permission to an app | Dangerous |
| 71 | **app_revoke_permission** | Revoke permission from an app | Dangerous |
| 72 | **app_enable/disable** | Enable or disable an app component | Dangerous |
| 73 | **automation_tap** | Tap at coordinates on screen | Sensitive |
| 74 | **automation_swipe** | Swipe gesture on screen | Sensitive |
| 75 | **automation_type** | Type text into focused field | Sensitive |
| 76 | **automation_press_key** | Press hardware/software key | Sensitive |
| 77 | **automation_screenshot** | Take screenshot programmatically | Sensitive |
| 78 | **automation_screen_record** | Record screen | Sensitive |
| 79 | **automation_ui_tree** | Dump accessibility/UI tree | Sensitive |
| 80 | **automation_find_element** | Find UI element by text/resource-id | Safe |
| 81 | **automation_wait_element** | Wait for element to appear | Safe |
| 82 | **automation_navigate** | Navigate app using UI tree | Sensitive |
| 83 | **sms_read** | Read SMS messages | Sensitive |
| 84 | **sms_send** | Send SMS | Dangerous |
| 85 | **call_log_read** | Read call log | Sensitive |
| 86 | **call_dial** | Dial a phone number | Dangerous |
| 87 | **contact_create** | Create new contact | Sensitive |
| 88 | **contact_delete** | Delete a contact | Dangerous |
| 89 | **media_play** | Play audio/video file | Safe |
| 90 | **media_pause/stop** | Control media playback | Safe |
| 91 | **media_volume_set** | Set volume level | Sensitive |
| 92 | **brightness_set** | Set screen brightness | Sensitive |
| 93 | **wifi_enable/disable** | Toggle WiFi | Sensitive |
| 94 | **bluetooth_enable/disable** | Toggle Bluetooth | Sensitive |
| 95 | **hotspot_enable** | Enable WiFi hotspot | Sensitive |
| 96 | **nfc_read** | Read NFC tag | Sensitive |
| 97 | **nfc_write** | Write NFC tag | Sensitive |
| 98 | **sensor_read** | Read accelerometer, gyro, proximity, etc. | Safe |
| 99 | **battery_info** | Detailed battery stats | Safe |
| 100 | **flashlight_on/off** | Toggle flashlight | Safe |
| 101 | **vibrate** | Trigger vibration pattern | Safe |
| 102 | **clipboard_monitor** | Monitor clipboard changes | Sensitive |
| 103 | **notification_reply** | Reply to a notification | Sensitive |
| 104 | **notification_dismiss** | Dismiss a notification | Sensitive |
| 105 | **location_mock** | Mock GPS location (developer mode) | Dangerous |
| 106 | **settings_read** | Read system setting value | Sensitive |
| 107 | **settings_write** | Write system setting value | Dangerous |
| 108 | **input_method_set** | Change keyboard/input method | Sensitive |
| 109 | **wallpaper_set** | Set home/lock screen wallpaper | Sensitive |
| 110 | **device_info** | Detailed device info (model, SDK, RAM, CPU) | Safe |
| 111 | **process_list** | List running processes | Safe |
| 112 | **process_kill** | Kill a process | Dangerous |
| 113 | **logcat_read** | Read system logcat | Sensitive |
| 114 | **logcat_clear** | Clear logcat | Dangerous |
| 115 | **db_query** | Query another app's SQLite database (root) | Dangerous |
| 116 | **shared_prefs_read** | Read another app's SharedPreferences (root) | Dangerous |
| 117 | **shared_prefs_write** | Write another app's SharedPreferences (root) | Dangerous |
| 118 | **intent_send** | Send arbitrary Android intent | Dangerous |
| 119 | **content_provider_query** | Query content provider | Sensitive |
| 120 | **backup_create** | Create app data backup (root) | Dangerous |
| 121 | **backup_restore** | Restore app from backup (root) | Dangerous |
| 122 | **cron_job** | Schedule recurring task (WorkManager) | Sensitive |
| 123 | **webhook_listen** | Listen for incoming webhook on local server | Sensitive |
| 124 | **gpio_read/write** | Read/write GPIO pins (root, compatible devices) | Dangerous |
| 125 | **adb_connect** | Connect to remote ADB device | Dangerous |

### 5.3 iOS-Only Tools (Limited by Sandbox)

| # | Tool | Description | Permission |
|---|------|-------------|-----------|
| 126 | **shortcuts_run** | Run a Shortcuts automation | Safe |
| 127 | **url_scheme_open** | Open app via URL scheme | Safe |
| 128 | **applescript_run** | Run AppleScript (macOS only, future) | Dangerous |
| 129 | **focus_mode** | Toggle Focus modes | Sensitive |
| 130 | **open_app** | Open another app (limited) | Safe |

---

## 6. Android Superuser System (Shizuku Integration)

### 6.1 What is Shizuku?

Shizuku is an Android app that provides ADB-level (or root-level) access to apps without requiring a rooted device. It uses ADB credentials, which the user authorizes once via wireless debugging or USB connection.

### 6.2 Permission Tiers on Android

| Tier | Method | Access Level | User Setup |
|------|--------|-------------|-----------|
| **Standard** | Normal Android permissions | Camera, location, storage | Normal app install |
| **ADB** | Shizuku API | Install apps, dump UI tree, clear cache, force-stop, grant permissions | One-time ADB pairing |
| **Root** | Magisk + Shizuku root mode | Full /system, modify any app data, mock locations, system settings | Magisk installed |

### 6.3 How Kolo Uses Shizuku

1. On first launch, detect if Shizuku is installed and running
2. If available, request Shizuku binder — this gives access to `IPackageManager`, `IActivityManager`, `IWindowManager`, etc.
3. All "Dangerous" tools check Shizuku availability before executing
4. If Shizuku not available, offer guided setup (link to Shizuku app, instructions)
5. Fall back gracefully: tools that need elevated access simply fail with clear instructions

### 6.4 Android Automation Engine

The automation engine uses the AccessibilityService + Shizuku ADB commands:

- **AccessibilityService**: Provides UI tree, element interaction, notifications
- **Shizuku ADB shell**: `input tap`, `input swipe`, `input text`, `am`, `pm`, `settings`
- **Combined approach**: Accessibility for reading UI, ADB for performing actions

Automation flow:
1. Agent decides to interact with an app (e.g., "Turn off WiFi in Settings")
2. `automation_ui_tree` dumps current screen hierarchy
3. Model parses the tree, identifies target element (e.g., WiFi toggle)
4. `automation_find_element` locates the element coordinates
5. `automation_tap` taps the toggle
6. `automation_screenshot` confirms the result
7. Agent reports success or retries

---

## 7. Tool Implementation System

### 7.1 Tool Definition Format

Every tool is defined as a JSON schema (OpenAI function calling format):

```json
{
  "type": "function",
  "function": {
    "name": "web_search",
    "description": "Search the web using a search engine",
    "parameters": {
      "type": "object",
      "properties": {
        "query": { "type": "string", "description": "Search query" },
        "engine": { "type": "string", "enum": ["duckduckgo", "google", "brave"], "default": "duckduckgo" },
        "limit": { "type": "integer", "description": "Max results", "default": 10 }
      },
      "required": ["query"]
    }
  }
}
```

### 7.2 Tool Plugin Architecture

Tools are registered dynamically at runtime. Each tool is a Dart class implementing:

```dart
abstract class KoloTool {
  String get name;
  String get description;
  Map<String, dynamic> get parameterSchema;
  ToolPermission get permission;
  Platform get platform; // all, android, ios

  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context);
}
```

This means:
- New tools can be added without touching the core
- Community tools could be loaded as packages in the future
- Tools are discoverable by the model via function definitions
- Each tool is independently testable

### 7.3 Tool Context

Every tool execution receives a `ToolContext` with:
- Current chat ID
- User preferences
- Permission checker (to gate dangerous ops)
- Cancellation token
- Platform services (Shizuku binder, AccessibilityService, etc.)
- Logger

---

## 8. Project Structure

```
kolo_ai_agent/
├── lib/
│   ├── main.dart
│   ├── app.dart                          # Riverpod app wrapper
│   ├── core/
│   │   ├── api/
│   │   │   ├── provider_manager.dart      # Multi-provider config
│   │   │   ├── openai_client.dart         # OpenAI HTTP + SSE client
│   │   │   ├── streaming_parser.dart      # SSE chunk parser
│   │   │   └── token_counter.dart
│   │   ├── agent/
│   │   │   ├── agent_loop.dart           # Main think→act→observe loop
│   │   │   ├── tool_router.dart          # Function call → tool dispatch
│   │   │   ├── tool_registry.dart        # All tool registrations
│   │   │   ├── conversation_manager.dart  # History + token budget
│   │   │   └── system_prompt.dart        # Dynamic system prompt builder
│   │   ├── tools/
│   │   │   ├── tool_base.dart            # Abstract KoloTool class
│   │   │   ├── tool_result.dart
│   │   │   ├── tool_permission.dart       # Permission tiers
│   │   │   ├── cross_platform/            # 60 cross-platform tools
│   │   │   │   ├── web_search.dart
│   │   │   │   ├── web_scrape.dart
│   │   │   │   ├── file_tools.dart
│   │   │   │   ├── code_runner.dart
│   │   │   │   ├── local_server.dart
│   │   │   │   ├── media_tools.dart
│   │   │   │   ├── network_tools.dart
│   │   │   │   ├── crypto_tools.dart
│   │   │   │   ├── document_tools.dart
│   │   │   │   ├── communication_tools.dart
│   │   │   │   ├── device_info_tool.dart
│   │   │   │   └── ...
│   │   │   ├── android/                   # 65 Android-only tools
│   │   │   │   ├── shell_exec.dart
│   │   │   │   ├── shizuku_bridge.dart
│   │   │   │   ├── app_manager.dart
│   │   │   │   ├── automation_engine.dart
│   │   │   │   ├── sms_tools.dart
│   │   │   │   ├── intent_sender.dart
│   │   │   │   ├── settings_tools.dart
│   │   │   │   ├── sensor_tools.dart
│   │   │   │   ├── db_query.dart
│   │   │   │   └── ...
│   │   │   └── ios/                      # 5 iOS-only tools
│   │   │       ├── shortcuts_runner.dart
│   │   │       └── url_scheme.dart
│   │   ├── permissions/
│   │   │   ├── permission_manager.dart
│   │   │   ├── permission_gate.dart       # UI prompt for sensitive/dangerous
│   │   │   ├── shizuku_checker.dart
│   │   │   ├── audit_logger.dart
│   │   │   └── biometric_auth.dart
│   │   └── storage/
│   │       ├── database.dart              # Drift DB setup
│   │       ├── chat_dao.dart
│   │       ├── tool_log_dao.dart
│   │       └── settings_dao.dart
│   ├── ui/
│   │   ├── chat/
│   │   │   ├── chat_screen.dart
│   │   │   ├── message_bubble.dart
│   │   │   ├── tool_result_card.dart     # Rich tool output rendering
│   │   │   ├── code_block.dart           # Syntax highlighted code
│   │   │   ├── streaming_indicator.dart
│   │   │   └── input_bar.dart
│   │   ├── settings/
│   │   │   ├── settings_screen.dart
│   │   │   ├── provider_config_screen.dart
│   │   │   ├── tool_permissions_screen.dart
│   │   │   └── shizuku_setup_screen.dart
│   │   ├── tools/
│   │   │   ├── tool_catalog_screen.dart   # Browse all tools
│   │   │   └── tool_detail_screen.dart
│   │   └── common/
│   │       ├── permission_dialog.dart
│   │       ├── loading_shimmer.dart
│   │       └── markdown_renderer.dart
│   └── platform/
│       ├── platform_channel.dart           # Dart → Native bridge
│       ├── android/
│       │   ├── shizuku_service.dart        # Shizuku integration
│       │   ├── accessibility_bridge.dart   # AccessibilityService
│       │   └── automation_controller.dart
│       └── ios/
│           └── shortcuts_bridge.dart
├── android/
│   ├── app/src/main/kotlin/com/kolo/agent/
│   │   ├── MainActivity.kt
│   │   ├── ShizukuPlugin.kt              # Shizuku ADB access
│   │   ├── AccessibilityHost.kt          # AccessibilityService
│   │   ├── AutomationPlugin.kt           # input tap/swipe/type
│   │   ├── ShellPlugin.kt               # Runtime.exec + Shizuku shell
│   │   ├── AppManagerPlugin.kt           # pm install/uninstall/list
│   │   ├── SmsPlugin.kt                  # SMS read/send
│   │   ├── IntentPlugin.kt               # Send broadcast/activity intents
│   │   ├── SettingsPlugin.kt             # settings get/put
│   │   ├── DbPlugin.kt                   # Root DB query
│   │   ├── SensorPlugin.kt               # Hardware sensors
│   │   └── NotificationListener.kt       # Notification access
│   └── ... (standard Flutter Android files)
├── ios/
│   ├── Runner/
│   │   ├── AppDelegate.swift
│   │   ├── ShortcutsPlugin.swift
│   │   └── UrlSchemePlugin.swift
│   └── ... (standard Flutter iOS files)
├── assets/
│   ├── icons/
│   └── default_system_prompt.txt
├── test/
│   ├── core/
│   │   ├── agent_loop_test.dart
│   │   ├── tool_router_test.dart
│   │   └── streaming_parser_test.dart
│   ├── tools/
│   │   ├── web_search_test.dart
│   │   ├── file_tools_test.dart
│   │   └── shell_exec_test.dart
│   └── ui/
│       └── chat_screen_test.dart
├── pubspec.yaml
├── analysis_options.yaml
└── README.md
```

---

## 9. Flutter Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  # State management
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0
  # Networking
  dio: ^5.4.0
  # Database
  drift: ^2.15.0
  sqlite3_flutter_libs: ^0.5.0
  # UI
  flutter_markdown: ^0.7.0
  flutter_highlight: ^0.7.0
  # Files
  path_provider: ^2.1.0
  file_picker: ^8.0.0
  # Media
  image_picker: ^1.0.0
  camera: ^0.11.0
  # Platform
  permission_handler: ^11.0.0
  url_launcher: ^6.2.0
  share_plus: ^9.0.0
  # Communication
  flutter_local_notifications: ^18.0.0
  # Utility
  crypto: ^3.0.3
  archive: ^3.4.0
  shelf: ^1.4.0
  shelf_router: ^1.1.0
  xml: ^6.5.0
  html: ^0.15.0
  pdf: ^3.10.0
  # Code execution
  flutter_js: ^0.8.0           # JS engine for code runner

dev_dependencies:
  build_runner: ^2.4.0
  drift_dev: ^2.15.0
  riverpod_generator: ^2.3.0
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  mockito: ^5.4.0
```

---

## 10. Development Phases

### Phase 1 — Foundation (Weeks 1-3)

**Goal**: Chat with any OpenAI-compatible endpoint, basic tool execution

- [ ] Flutter project setup (Android + iOS)
- [ ] API provider manager (URL, key, model, headers config)
- [ ] OpenAI streaming chat client (SSE with Dio)
- [ ] Chat UI (message list, input bar, streaming bubbles)
- [ ] Conversation manager (history, token budget)
- [ ] Tool router + registry skeleton
- [ ] 5 cross-platform tools: `web_search`, `read_file`, `write_file`, `calculator`, `list_directory`
- [ ] Settings screen (provider config)
- [ ] Basic system prompt with tool definitions injected

**Milestone**: Can chat with any endpoint, model can search web and read/write files

### Phase 2 — Core Tools (Weeks 4-6)

**Goal**: Expand to 40+ cross-platform tools, polish chat UX

- [ ] Remaining cross-platform tools (Section 5.1)
- [ ] Permission system (safe/sensitive/dangerous)
- [ ] Permission dialog UI
- [ ] Audit logger
- [ ] Rich tool result cards in chat
- [ ] Code block rendering + syntax highlighting
- [ ] `run_code` tool (JS via flutter_js)
- [ ] `local_server` tool (Shelf)
- [ ] PDF read/write tools
- [ ] Image tools (resize, convert, OCR)
- [ ] Archive tools (zip)
- [ ] Network tools (ping, DNS, SSH)
- [ ] Git tools (clone, commit)
- [ ] Chat export (Markdown, JSON)
- [ ] Multi-provider profiles

**Milestone**: Full-featured chat agent with 60 cross-platform tools

### Phase 3 — Android Power (Weeks 7-11)

**Goal**: Shizuku integration, automation engine, Android-only tools

- [ ] Shizuku Kotlin plugin (binder, permissions check)
- [ ] `shell_exec` / `shell_exec_root` via Shizuku
- [ ] App manager tools (install, uninstall, launch, list, force-stop)
- [ ] App data tools (clear data, grant/revoke permissions, shared_prefs read/write)
- [ ] AccessibilityService setup
- [ ] Automation engine: `automation_ui_tree`, `automation_find_element`, `automation_tap`, `automation_swipe`, `automation_type`, `automation_press_key`
- [ ] `automation_screenshot`, `automation_screen_record`
- [ ] `automation_navigate` (high-level: "Open Settings > WiFi and toggle")
- [ ] SMS/Call tools
- [ ] Notification read/reply/dismiss
- [ ] System settings read/write
- [ ] Intent sender (broadcast, activity, service)
- [ ] Content provider query
- [ ] Shizuku setup guide in app (step-by-step)
- [ ] Sensor tools
- [ ] Device info + process management
- [ ] DB query tool (root)
- [ ] Location mock
- [ ] Media/volume/brightness controls

**Milestone**: Full Android superuser agent with 125+ tools

### Phase 4 — iOS + Polish (Weeks 12-14)

**Goal**: iOS-specific tools, UI polish, performance

- [ ] iOS Shortcuts runner
- [ ] iOS URL scheme opener
- [ ] iOS-specific permission handling
- [ ] UI polish: animations, transitions, themes (dark/light)
- [ ] Chat branching (fork at any message)
- [ ] Conversation search
- [ ] Widget (quick chat from home screen)
- [ ] Keyboard shortcuts (iPad)
- [ ] Performance optimization (lazy loading, image caching)
- [ ] Accessibility (TalkBack/VoiceOver support)

**Milestone**: Polished, production-ready app on both platforms

### Phase 5 — Advanced Features (Weeks 15-18)

**Goal**: Multi-agent, scheduling, plugin system

- [ ] Scheduled tasks (cron-like, WorkManager on Android)
- [ ] Background agent execution (Android foreground service)
- [ ] Webhook listener (incoming triggers)
- [ ] Multi-agent conversations (agent talks to itself or other models)
- [ ] Tool plugin system (load community tools as Dart packages)
- [ ] RAG: index local files, let agent search them
- [ ] Vision: screenshot → model analysis → action (see-think-act loop)
- [ ] Workflows: chain of tools saved as reusable macro
- [ ] NFC read/write
- [ ] GPIO read/write (root, IoT devices)
- [ ] Remote ADB connect
- [ ] Auto-authorization mode (skip all permission prompts, power user mode)

**Milestone**: Advanced autonomous agent with unlimited extensibility

---

## 11. Key Design Decisions

### 11.1 "Thin Client" Philosophy

The app is a thin client — all intelligence comes from the connected API model. The app only:
1. Sends messages + tool definitions
2. Executes tool calls the model requests
3. Feeds results back

No local LLM, no local reasoning. This keeps the app tiny and battery-efficient.

### 11.2 OpenAI-Compatible as the Standard

By targeting the OpenAI Chat Completions API format (with function calling), we get:
- Compatibility with: OpenAI, Anthropic (via gateway), Ollama, LM Studio, vLLM, Fireworks, Together, Groq, Mistral, Cohere, any OpenAI-compatible server
- Function calling is the standard way to grant tools to models
- No custom protocol needed

### 11.3 Shizuku Over Root

Shizuku gives ADB-level access without a full root. This means:
- Works on non-rooted devices (just wireless debugging pairing)
- If user has Magisk, Shizuku can run in root mode for full access
- No custom su binary needed
- Widely trusted app (500K+ downloads on Play Store)

### 11.4 See-Think-Act Loop (Automation)

For app automation, the agent follows this loop:
1. **See**: `automation_screenshot` + `automation_ui_tree` → model sees the screen
2. **Think**: Model decides what to tap/type/swipe
3. **Act**: `automation_tap` / `automation_type` / `automation_swipe`
4. **Verify**: Screenshot again to confirm result
5. Repeat until task complete

This is how the agent can navigate any app, even ones it has never seen before.

### 11.5 No Root Required, Root Enhances

The app should work fully on a stock Android device with standard permissions. Shizuku/ADB unlocks elevated tools. Root via Magisk unlocks everything. The experience degrades gracefully:
- **No Shizuku/Root**: 60 cross-platform tools + standard Android APIs
- **Shizuku (ADB)**: +40 Android tools (shell, app management, automation)
- **Shizuku (Root)**: +25 more tools (system modify, app data, mock location, DB access)

---

## 12. Security Considerations

1. **API keys stored in flutter_secure_storage** (encrypted on device)
2. **Tool audit log** — every call recorded with timestamp, params, result
3. **Biometric gate** for dangerous tools (fingerprint/Face ID before executing)
4. **Network isolation option** — block tools from reaching local network IPs
5. **No internet egress for shell commands** — unless user explicitly allows
6. **Rate limiting** — max N tool calls per minute (configurable)
7. **Permission profiles** — "full access", "safe only", "read only" presets
8. **Model sandbox** — model cannot execute tools without going through permission gate
9. **Self-protection** — model cannot modify Kolo's own data/preferences
10. **Emergency kill switch** — long-press power to stop all tool execution immediately

---

## 13. Monetization (Future)

| Tier | Price | Features |
|------|-------|----------|
| Free | $0 | All cross-platform tools, single API provider |
| Pro | $5/mo | All 130+ tools, unlimited providers, scheduled tasks, workflows |
| Enterprise | Custom | Self-hosted tool server, team management, audit compliance |

API costs are the user's own — Kolo never proxies or marks up API calls.

---

## 14. Success Metrics

1. Can chat with any OpenAI-compatible endpoint
2. Can search web and read/write files on device
3. Can run code locally and serve a local HTTP server
4. Can automate any Android app via accessibility + Shizuku
5. Can install/uninstall Android apps
6. Can read/write another app's data (root)
7. Can execute shell commands at ADB or root level
8. Works fully on iOS (with sandbox limitations)
9. All 130+ tools accessible in tool catalog
10. Single developer can add a new tool in <30 minutes

---

## 15. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Shizuku pairing is confusing for users | Low adoption | In-app guided setup with screenshots + video |
| Google/Apple reject app for "dangerous" tools | Store removal | Staged rollout, Shizuku as opt-in, not required |
| Model hallucinates tool calls | Unexpected actions | Schema validation before execution, user confirmation for sensitive ops |
| Battery drain from background agent | Bad reviews | Strict lifecycle management, WorkManager constraints |
| API key leaked from device | Account compromise | flutter_secure_storage, key rotation UI |
| Automation breaks on app updates | Failed tasks | Screenshot verification loop, retry with model re-analysis |

---

*Last updated: April 2026*
*Version: 1.0*