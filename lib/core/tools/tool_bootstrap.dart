import 'tool_registry.dart';
import 'cross_platform/read_file.dart';
import 'cross_platform/write_file.dart';
import 'cross_platform/list_directory.dart';
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
import 'android/analyze_screen.dart';
import 'android/app_launcher.dart';
import 'android/phone_control_overlay.dart';

/// Bootstrap: Register all tools into the registry
/// Called once at app startup
ToolRegistry bootstrapTools() {
  final registry = ToolRegistry();

  // ── File & directory (7) ──
  registry.register(ReadFileTool());
  registry.register(WriteFileTool());
  registry.register(ListDirectoryTool());
  registry.register(ListFilesTool());
  registry.register(DeleteFileTool());
  registry.register(CreateDirectoryTool());
  registry.register(FindFileTool());

  // ── File operations (4) ──
  registry.register(AppendFileTool());
  registry.register(CopyFileTool());
  registry.register(MoveFileTool());
  registry.register(FileStatTool());

  // ── Web & network (4) ──
  registry.register(WebSearchTool());
  registry.register(WebScrapeTool());
  registry.register(HttpGetTool());
  registry.register(HttpPostTool());

  // ── Utility (5) ──
  registry.register(CalculatorTool());
  registry.register(JsonParseTool());
  registry.register(Base64Tool());
  registry.register(HashTool());
  registry.register(DateTool());

  // ── Clipboard (2) ──
  registry.register(ClipboardReadTool());
  registry.register(ClipboardWriteTool());

  // ── Shell & system (2) ──
  registry.register(ShellExecTool());
  registry.register(EnvInfoTool());

  // ── Platform capabilities (7) ──
  registry.register(LocationTool());
  registry.register(ConnectivityTool());
  registry.register(BatteryInfoTool());
  registry.register(VibrateTool());
  registry.register(TextToSpeechTool());
  registry.register(SpeechToTextTool());
  registry.register(OpenAppTool());

  // ── Media & downloads (3) ──
  registry.register(QrCodeTool());
  registry.register(DownloadFileTool());
  registry.register(ImageMetadataTool());

  // ── Contacts & search (2) ──
  registry.register(GrepTool());
  registry.register(ContactsTool());

  // ── Timers (1) ──
  registry.register(TimerTool());

  // ── Android Phone Controller (11) ──
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
  registry.register(ShowActionTool());
  registry.register(AnalyzeScreenTool());

  // ── Android App Management (3) ──
  registry.register(LaunchAppTool());
  registry.register(ListInstalledAppsTool());
  registry.register(DeviceInfoTool());

  // ── Android Phone Control Overlay (3) ──
  registry.register(PhoneControlStartTool());
  registry.register(PhoneControlDoneTool());
  registry.register(PhoneControlStatusTool());

  return registry;
}