import 'tool_base.dart';
import 'tool_registry.dart';
import 'custom_tool_adapter.dart';
import 'custom_tool_def.dart';
import 'create_tool_tool.dart';
import 'skills.dart';
import '../memory/memory_tools.dart';
import 'cross_platform/calculator.dart';
import 'cross_platform/web_search.dart';
import 'cross_platform/clipboard.dart';
import 'cross_platform/new_tools.dart';
import 'cross_platform/web_scrape.dart';
import 'cross_platform/qr_code.dart';
import 'cross_platform/location.dart';
import 'cross_platform/timer.dart';
import 'cross_platform/download_file.dart';
import 'cross_platform/device_tools.dart';
import 'cross_platform/text_to_speech.dart';
import 'cross_platform/speech_to_text.dart';
import 'cross_platform/open_app.dart';
import 'cross_platform/contacts.dart';
// Android phone controller tools
import 'android/phone_controller.dart';
import 'android/adb_phone_controller.dart';
import 'android/analyze_screen.dart';
import 'android/app_launcher.dart';
import 'android/phone_control_overlay.dart';
import 'android/phone_control_mode.dart';
import 'android/scan_phone_apps.dart';

/// Cached cross-platform tools — only created once, reused across mode changes
List<KoloTool>? _cachedCrossPlatformTools;

List<KoloTool> _buildCrossPlatformTools() {
  if (_cachedCrossPlatformTools != null) return _cachedCrossPlatformTools!;
  _cachedCrossPlatformTools = [
    // Web & network
    WebSearchTool(), WebScrapeTool(), HttpGetTool(), HttpPostTool(),
    // Utility
    CalculatorTool(), JsonParseTool(), Base64Tool(), HashTool(), DateTool(),
    // Clipboard
    ClipboardReadTool(), ClipboardWriteTool(),
    // Platform capabilities
    LocationTool(), ConnectivityTool(), BatteryInfoTool(), VibrateTool(),
    TextToSpeechTool(), SpeechToTextTool(), OpenAppTool(),
    // Media & downloads
    QrCodeTool(), DownloadFileTool(), ImageMetadataTool(),
    // Contacts
    ContactsTool(),
    // Timers
    TimerTool(),
  ];
  return _cachedCrossPlatformTools!;
}

/// Bootstrap: Register all tools into the registry.
///
/// [mode] determines whether phone control tools use Accessibility or ADB.
/// [customTools] are user/agent-defined tools that have been persisted to
/// the database; each is wrapped in a [CustomToolAdapter]. Names that
/// collide with built-ins are skipped (built-ins always win).
/// [agentCanCreateTools], when true, registers the [CreateToolTool] +
/// [ListCustomToolsTool] + [DeleteCustomToolTool] meta-tools. [onCustomToolsChanged]
/// is the callback those tools fire after mutation — typically an invocation
/// that re-reads from the database and triggers provider rebuild.
ToolRegistry bootstrapTools({
  PhoneControlMode mode = PhoneControlMode.accessibility,
  List<CustomToolDef> customTools = const [],
  bool agentCanCreateTools = false,
  bool skillsEnabled = true,
  bool agentCanCreateMemories = false,
  Future<void> Function()? onCustomToolsChanged,
  Future<void> Function()? onMemoriesChanged,
}) {
  final registry = ToolRegistry();

  // Register cached cross-platform tools (not recreated on mode change)
  for (final tool in _buildCrossPlatformTools()) {
    registry.register(tool);
  }

  // ── Android Phone Controller — mode-dependent ──
  if (mode == PhoneControlMode.adb) {
    // ADB-based tools (no accessibility service needed)
    registry.register(AdbTapTool());
    registry.register(AdbSwipeTool());
    registry.register(AdbTypeTextTool());
    registry.register(AdbPressKeyTool());
    registry.register(AdbScreenshotTool());
    registry.register(AdbDumpUiTool());
    registry.register(AdbScrollTool());
    registry.register(AdbLongPressTool());
  } else {
    // Accessibility-based tools (default)
    registry.register(StartControllerTool());
    registry.register(StopControllerTool());
    registry.register(ReadScreenTool());
    registry.register(ScreenshotTool());
    registry.register(TapTool());
    registry.register(SwipeTool());
    registry.register(TypeTextTool());
    registry.register(PressKeyTool());
    registry.register(ScrollTool());
    registry.register(ClickByTextTool());
    registry.register(LongPressTool());
  }
  registry.register(ShowActionTool());
  registry.register(AnalyzeScreenTool());

  // ── Android App Management (3) ──
  registry.register(LaunchAppTool());
  registry.register(ListInstalledAppsTool());
  registry.register(DeviceInfoTool());

  // ── App Scanner (ADB) ──
  registry.register(ScanPhoneAppsTool());

  // ── Android Phone Control Overlay (3) ──
  registry.register(PhoneControlStartTool());
  registry.register(PhoneControlDoneTool());
  registry.register(PhoneControlStatusTool());

  // ── Custom tools & meta-tools ─────────────────────────────────────
  //
  // Custom tools registered first so a later-registered meta-tool with
  // the same name would collide — but our collision rule is "last
  // wins" (registry.register overwrites), so built-ins always trump
  // custom. Defensive: skip any custom tool whose name is already in
  // the registry.
  //
  // list_custom_tools is always registered (read-only + cheap) so the
  // agent can query what it has even before the user enables creation.
  if (customTools.isNotEmpty || agentCanCreateTools) {
    registry.register(ListCustomToolsTool());
  }
  for (final def in customTools) {
    if (def.kind == CustomToolKind.shell) continue;
    if (registry.get(def.name) != null) continue; // built-in wins
    registry.register(CustomToolAdapter(def));
  }
  if (agentCanCreateTools && onCustomToolsChanged != null) {
    registry.register(CreateToolTool(onChange: onCustomToolsChanged));
    registry.register(DeleteCustomToolTool(onChange: onCustomToolsChanged));
  }

  // ── Skills ────────────────────────────────────────────────────────
  if (skillsEnabled) {
    registry.register(ListSkillsTool());
    registry.register(ReadSkillTool());
    registry.register(CreateSkillTool());
  }

  // ── Memory tools ──────────────────────────────────────────────────
  // recall_memories is always registered — read-only + cheap. Authoring
  // tools are gated by the settings toggle.
  registry.register(RecallMemoriesTool());
  if (agentCanCreateMemories && onMemoriesChanged != null) {
    registry.register(RememberThisTool(onChange: onMemoriesChanged));
    registry.register(ForgetMemoryTool(onChange: onMemoriesChanged));
  }

  return registry;
}
