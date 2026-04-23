import 'tool_base.dart';
import 'tool_registry.dart';
import 'cross_platform/read_file.dart';
import 'cross_platform/write_file.dart';
import 'cross_platform/list_directory.dart';
import 'cross_platform/calculator.dart';
import 'cross_platform/web_search.dart';
import 'cross_platform/clipboard.dart';
import 'cross_platform/new_tools.dart';
import 'cross_platform/edit_file.dart';
import 'cross_platform/search_files.dart';
import 'cross_platform/project_tools.dart';
import 'cross_platform/flutter_task.dart';
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
import 'android/bootstrap_status_tool.dart';

/// Cached cross-platform tools — only created once, reused across mode changes
List<KoloTool>? _cachedCrossPlatformTools;

List<KoloTool> _buildCrossPlatformTools() {
  if (_cachedCrossPlatformTools != null) return _cachedCrossPlatformTools!;
  _cachedCrossPlatformTools = [
    // File & directory
    ReadFileTool(), WriteFileTool(), ListDirectoryTool(), ListFilesTool(),
    DeleteFileTool(), CreateDirectoryTool(), FindFileTool(),
    // File operations
    AppendFileTool(), CopyFileTool(), MoveFileTool(), FileStatTool(),
    // Web & network
    WebSearchTool(), WebScrapeTool(), HttpGetTool(), HttpPostTool(),
    // Utility
    CalculatorTool(), JsonParseTool(), Base64Tool(), HashTool(), DateTool(),
    // Clipboard
    ClipboardReadTool(), ClipboardWriteTool(),
    // Shell & system
    ShellExecTool(), EnvInfoTool(),
    // Platform capabilities
    LocationTool(), ConnectivityTool(), BatteryInfoTool(), VibrateTool(),
    TextToSpeechTool(), SpeechToTextTool(), OpenAppTool(),
    // Media & downloads
    QrCodeTool(), DownloadFileTool(), ImageMetadataTool(),
    // Contacts & search
    GrepTool(), ContactsTool(),
    // Coding tools
    EditFileTool(), SearchFilesTool(), SetProjectRootTool(), FlutterTaskTool(),
    // Timers
    TimerTool(),
  ];
  return _cachedCrossPlatformTools!;
}

/// Bootstrap: Register all tools into the registry
/// Called once at app startup
/// [mode] determines whether phone control tools use Accessibility or ADB.
ToolRegistry bootstrapTools({PhoneControlMode mode = PhoneControlMode.accessibility}) {
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

  // ── Bootstrap / Dev Tools Status ──
  registry.register(BootstrapStatusTool());

  // ── Android Phone Control Overlay (3) ──
  registry.register(PhoneControlStartTool());
  registry.register(PhoneControlDoneTool());
  registry.register(PhoneControlStatusTool());

  return registry;
}