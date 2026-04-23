import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/agent/agent_session.dart';
import '../../core/agent/agent_loop.dart';
import '../../core/tools/tool_base.dart';
import '../../core/tools/tool_bootstrap.dart';
import '../../core/tools/tool_registry.dart';
import '../../core/tools/android/phone_control_mode.dart';
import '../chat/input_bar.dart';
import '../chat/chat_screen.dart' show toolRegistryProvider;

/// Workspace root for dev projects — resolved lazily to use app-specific
/// storage on Android (no MANAGE_EXTERNAL_STORAGE needed).
String? _workspaceRootCache;
Future<String> getWorkspaceRoot() async {
  if (_workspaceRootCache != null) return _workspaceRootCache!;
  if (Platform.isAndroid) {
    // getExternalStorageDirectory → /storage/emulated/0/Android/data/<pkg>/files
    // This dir is writable without any special permissions.
    final dir = await getExternalStorageDirectory();
    _workspaceRootCache = '${dir!.path}/KoloProjects';
  } else {
    // macOS / iOS / desktop — use documents dir
    final dir = await getApplicationDocumentsDirectory();
    _workspaceRootCache = '${dir.path}/KoloProjects';
  }
  return _workspaceRootCache!;
}

// ── Unified message model ──
// Tracks both AI messages and terminal output in a single interleaved stream.
enum _DevEntryType { userMessage, assistantMessage, toolCall, toolResult, terminalInput, terminalOutput, terminalError }

class _DevEntry {
  final String id;
  final _DevEntryType type;
  final String content;
  final DateTime timestamp;
  final String? toolName;    // for toolCall / toolResult
  final bool? toolSuccess;   // for toolResult

  _DevEntry({
    required this.id,
    required this.type,
    required this.content,
    required this.timestamp,
    this.toolName,
    this.toolSuccess,
  });
}

// 3.4: Share tool registry with chat screen to avoid duplicate bootstrap.
// The agent session is kept separate for isolation.
final devToolRegistryProvider = toolRegistryProvider;

final devAgentSessionProvider =
    StateNotifierProvider<AgentSessionNotifier, AgentSessionState>((ref) {
  return AgentSessionNotifier(ref);
});

final devEntriesProvider = StateProvider<List<_DevEntry>>((ref) => []);
final devIsTypingProvider = StateProvider<bool>((ref) => false);

/// DevScreen: Claude Code-like mobile IDE
/// Unified terminal-style view with interleaved AI + terminal output.
class DevScreen extends ConsumerStatefulWidget {
  const DevScreen({super.key});

  @override
  ConsumerState<DevScreen> createState() => _DevScreenState();
}

class _DevScreenState extends ConsumerState<DevScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<InputBarState> _inputBarKey = GlobalKey();
  bool _showScrollFab = false;
  bool _sessionInitialized = false;

  // Terminal state
  String _currentDir = '';  // resolved in initState via getWorkspaceRoot()
  static const _termChannel = MethodChannel('com.kolo.ai/terminal');

  // File tree state
  bool _fileTreeOpen = false;
  List<_FileNode> _fileTree = [];
  bool _fileTreeLoading = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initSession();
    _initWorkspace();
  }

  /// Initialize workspace root and current directory.
  Future<void> _initWorkspace() async {
    final root = await getWorkspaceRoot();
    if (!mounted) return;
    setState(() {
      if (_currentDir.isEmpty) _currentDir = root;
    });
    await _ensureWorkspace();
    _loadFileTree();
  }

  Future<void> _ensureWorkspace() async {
    final root = await getWorkspaceRoot();
    final dir = Directory(root);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    final show = (max - current) > 100;
    if (show != _showScrollFab) setState(() => _showScrollFab = show);
  }

  // ── Session init (uses dev-specific provider) ──
  Future<void> _initSession() async {
    if (_sessionInitialized) return;
    _sessionInitialized = true;

    final registry = ref.read(devToolRegistryProvider);
    final notifier = ref.read(devAgentSessionProvider.notifier);
    notifier.init(registry);
    notifier.session?.permissionManager.loadPersistedSettings();
  }

  // ── Unified input handler ──
  Future<void> _handleInput(String text) async {
    if (text.trim().isEmpty) return;

    // If starts with $, treat as terminal command
    if (text.startsWith('\$')) {
      final command = text.substring(1).trim();
      if (command.isNotEmpty) {
        await _executeTerminalCommand(command);
      }
      return;
    }

    // Otherwise send to AI
    await _sendToAI(text);
  }

  // ── Send message to AI ──
  Future<void> _sendToAI(String text) async {
    if (text.trim().isEmpty) return;

    final entries = ref.read(devEntriesProvider);
    final userEntry = _DevEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: _DevEntryType.userMessage,
      content: text,
      timestamp: DateTime.now(),
    );
    ref.read(devEntriesProvider.notifier).state = [...entries, userEntry];
    ref.read(devIsTypingProvider.notifier).state = true;
    _scrollToBottom();

    try {
      final notifier = ref.read(devAgentSessionProvider.notifier);
      final workspaceContext = '\n[DEV MODE] You are in a local development environment. '
          'Workspace: $_currentDir\n'
          'Current directory: $_currentDir\n'
          'Use read_file, write_file, list_directory, shell_exec, and other tools to code, test, and iterate. '
          'Always use absolute paths starting with $_currentDir.';

      await notifier.sendMessage(text + workspaceContext);
    } catch (e) {
      final current = ref.read(devEntriesProvider);
      final errorEntry = _DevEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: _DevEntryType.assistantMessage,
        content: 'Error: $e',
        timestamp: DateTime.now(),
      );
      ref.read(devEntriesProvider.notifier).state = [...current, errorEntry];
    } finally {
      ref.read(devIsTypingProvider.notifier).state = false;
    }
    _scrollToBottom();
  }

  void _onSessionStateChanged(AgentSessionState? prev, AgentSessionState next) {
    final current = List<_DevEntry>.from(ref.read(devEntriesProvider));
    final existingToolIds = current
        .where((e) => e.type == _DevEntryType.toolResult || e.type == _DevEntryType.toolCall)
        .map((e) => e.id)
        .toSet();

    switch (next) {
      case AgentSessionRunning(:final currentContent, :final currentThinking, :final toolCalls, :final toolResults):
        // Update streaming assistant message
        current.removeWhere((e) => e.id == 'streaming');
        if (currentContent.isNotEmpty || currentThinking.isNotEmpty) {
          current.add(_DevEntry(
            id: 'streaming',
            type: _DevEntryType.assistantMessage,
            content: currentContent.isEmpty && currentThinking.isNotEmpty ? '...' : currentContent,
            timestamp: DateTime.now(),
          ));
        }
        // Add tool call indicators
        for (final tc in toolCalls) {
          for (final call in tc.calls) {
            final callId = 'toolcall_${call.id}';
            if (!existingToolIds.contains(callId)) {
              current.add(_DevEntry(
                id: callId,
                type: _DevEntryType.toolCall,
                content: call.name,
                timestamp: DateTime.now(),
                toolName: call.name,
              ));
              existingToolIds.add(callId);
            }
          }
        }
        // Add tool results
        for (final tr in toolResults) {
          if (!existingToolIds.contains(tr.toolCallId)) {
            current.add(_DevEntry(
              id: tr.toolCallId,
              type: _DevEntryType.toolResult,
              content: tr.result.toDisplayString(),
              timestamp: DateTime.now(),
              toolName: tr.toolName,
              toolSuccess: tr.result.success,
            ));
            existingToolIds.add(tr.toolCallId);
          }
        }
        ref.read(devEntriesProvider.notifier).state = current;
        ref.read(devIsTypingProvider.notifier).state = true;
        _scrollToBottom();
      case AgentSessionCompleted(:final content, :final wasCancelled, :final toolCalls, :final toolResults):
        current.removeWhere((e) => e.id == 'streaming');
        // Add tool calls
        for (final tc in toolCalls) {
          for (final call in tc.calls) {
            final callId = 'toolcall_${call.id}';
            if (!existingToolIds.contains(callId)) {
              current.add(_DevEntry(
                id: callId,
                type: _DevEntryType.toolCall,
                content: call.name,
                timestamp: DateTime.now(),
                toolName: call.name,
              ));
              existingToolIds.add(callId);
            }
          }
        }
        // Add tool results
        for (final tr in toolResults) {
          if (!existingToolIds.contains(tr.toolCallId)) {
            current.add(_DevEntry(
              id: tr.toolCallId,
              type: _DevEntryType.toolResult,
              content: tr.result.toDisplayString(),
              timestamp: DateTime.now(),
              toolName: tr.toolName,
              toolSuccess: tr.result.success,
            ));
            existingToolIds.add(tr.toolCallId);
          }
        }
        if (content.isNotEmpty) {
          current.add(_DevEntry(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: _DevEntryType.assistantMessage,
            content: wasCancelled ? '$content\n\n⏹ Stopped' : content,
            timestamp: DateTime.now(),
          ));
        }
        ref.read(devEntriesProvider.notifier).state = current;
        ref.read(devIsTypingProvider.notifier).state = false;
        _scrollToBottom();
      case AgentSessionError(:final message):
        current.removeWhere((e) => e.id == 'streaming');
        current.add(_DevEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: _DevEntryType.assistantMessage,
          content: 'Error: $message',
          timestamp: DateTime.now(),
        ));
        ref.read(devEntriesProvider.notifier).state = current;
        ref.read(devIsTypingProvider.notifier).state = false;
        _scrollToBottom();
      case AgentSessionIdle():
        ref.read(devIsTypingProvider.notifier).state = false;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Terminal ──
  Future<void> _executeTerminalCommand(String command) async {
    if (command.trim().isEmpty) return;

    // Add input entry
    final entries = ref.read(devEntriesProvider);
    ref.read(devEntriesProvider.notifier).state = [
      ...entries,
      _DevEntry(
        id: 'term_in_${DateTime.now().millisecondsSinceEpoch}',
        type: _DevEntryType.terminalInput,
        content: '\$ $command',
        timestamp: DateTime.now(),
      ),
    ];
    _scrollToBottom();

    // Handle built-in commands
    if (command == 'clear') {
      ref.read(devEntriesProvider.notifier).state = [];
      return;
    }
    if (command.startsWith('cd ')) {
      final target = command.substring(3).trim();
      final newDir = target.startsWith('/')
          ? target
          : '$_currentDir/$target'.replaceAll('//', '/');
      final dir = Directory(newDir);
      if (await dir.exists()) {
        _currentDir = newDir;
        _addTermOutput(newDir);
      } else {
        _addTermError('cd: no such directory: $target');
      }
      _loadFileTree();
      return;
    }

    // Execute command
    try {
      if (Platform.isAndroid) {
        await _executeViaPTY(command);
      } else {
        final result = await Process.run(
          '/bin/sh', ['-c', command],
          workingDirectory: _currentDir,
        ).timeout(const Duration(seconds: 30));

        if (result.stdout.toString().isNotEmpty) {
          _addTermOutput(result.stdout.toString());
        }
        if (result.stderr.toString().isNotEmpty) {
          _addTermError(result.stderr.toString());
        }
        if (result.exitCode != 0 && result.stdout.toString().isEmpty && result.stderr.toString().isEmpty) {
          _addTermError('Exit code: ${result.exitCode}');
        }
      }
    } on TimeoutException {
      _addTermError('Command timed out (30s)');
    } catch (e) {
      _addTermError('Error: $e');
    }

    _scrollToBottom();
    _loadFileTree();
  }

  Future<void> _executeViaPTY(String command) async {
    try {
      final result = await _termChannel.invokeMethod<Map>('exec', {
        'command': command,
        'workingDir': _currentDir,
      });
      final stdout = result?['stdout'] as String? ?? '';
      final stderr = result?['stderr'] as String? ?? '';
      final exitCode = result?['exitCode'] as int? ?? 0;

      if (stdout.isNotEmpty) _addTermOutput(stdout);
      if (stderr.isNotEmpty) _addTermError(stderr);
      if (exitCode != 0 && stdout.isEmpty && stderr.isEmpty) {
        _addTermError('Exit code: $exitCode');
      }
    } on PlatformException {
      final result = await Process.run(
        '/system/bin/sh', ['-c', command],
        workingDirectory: _currentDir,
      ).timeout(const Duration(seconds: 30));

      if (result.stdout.toString().isNotEmpty) {
        _addTermOutput(result.stdout.toString());
      }
      if (result.stderr.toString().isNotEmpty) {
        _addTermError(result.stderr.toString());
      }
    }
  }

  void _addTermOutput(String text) {
    final entries = List<_DevEntry>.from(ref.read(devEntriesProvider));
    entries.add(_DevEntry(
      id: 'term_out_${DateTime.now().millisecondsSinceEpoch}',
      type: _DevEntryType.terminalOutput,
      content: text,
      timestamp: DateTime.now(),
    ));
    ref.read(devEntriesProvider.notifier).state = entries;
  }

  void _addTermError(String text) {
    final entries = List<_DevEntry>.from(ref.read(devEntriesProvider));
    entries.add(_DevEntry(
      id: 'term_err_${DateTime.now().millisecondsSinceEpoch}',
      type: _DevEntryType.terminalError,
      content: text,
      timestamp: DateTime.now(),
    ));
    ref.read(devEntriesProvider.notifier).state = entries;
  }

  // ── File Tree ──
  Future<void> _loadFileTree() async {
    setState(() => _fileTreeLoading = true);
    try {
      final root = await getWorkspaceRoot();
      _fileTree = await _loadDirectory(root);
    } catch (_) {}
    setState(() => _fileTreeLoading = false);
  }

  Future<List<_FileNode>> _loadDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return [];
    final nodes = <_FileNode>[];
    await for (final entity in dir.list()) {
      final name = entity.path.split('/').last;
      if (name.startsWith('.')) continue;
      final isDir = entity is Directory;
      nodes.add(_FileNode(
        name: name,
        path: entity.path,
        isDirectory: isDir,
        children: isDir ? null : [],
      ));
    }
    nodes.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return nodes;
  }

  Future<void> _toggleNode(_FileNode node) async {
    if (!node.isDirectory) return;
    if (node.children != null && node.children!.isNotEmpty) {
      setState(() => node.children = []);
    } else {
      final children = await _loadDirectory(node.path);
      setState(() => node.children = children);
    }
  }

  void _openFileInTerminal(_FileNode node) {
    if (node.isDirectory) return;
    _executeTerminalCommand('cat ${node.path}');
  }

  // ── Create Project Dialog (Issue 3) ──
  void _showCreateProjectDialog() {
    final nameController = TextEditingController();
    String selectedType = 'Blank';
    final types = ['Flutter', 'Python', 'Node.js', 'Blank'];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final cs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.create_new_folder, color: cs.primary),
                  const SizedBox(width: 8),
                  const Text('New Project'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: cs.onSurface),
                    cursorColor: cs.primary,
                    decoration: InputDecoration(
                      labelText: 'Project name',
                      hintText: 'my_app',
                      hintStyle: TextStyle(color: cs.onSurfaceVariant),
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Project type',
                      border: OutlineInputBorder(),
                    ),
                    items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedType = v);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(ctx);
                    _createProject(name, selectedType);
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createProject(String name, String type) async {
    final root = await getWorkspaceRoot();
    final projectPath = '$root/$name';
    final dir = Directory(projectPath);

    if (await dir.exists()) {
      _addTermError('Project "$name" already exists at $projectPath');
      return;
    }

    _addTermOutput('Creating $type project "$name"...');

    try {
      await dir.create(recursive: true);

      switch (type) {
        case 'Flutter':
          _addTermOutput('Running flutter create $name...');
          await _executeTerminalCommand('flutter create $projectPath');
        case 'Python':
          await File('$projectPath/main.py').writeAsString('# $name\n\ndef main():\n    print("Hello from $name!")\n\nif __name__ == "__main__":\n    main()\n');
          await File('$projectPath/requirements.txt').writeAsString('# Add dependencies here\n');
          await File('$projectPath/README.md').writeAsString('# $name\n\nA Python project.\n');
          _addTermOutput('Created Python project with main.py, requirements.txt, README.md');
        case 'Node.js':
          await File('$projectPath/index.js').writeAsString('// $name\n\nconsole.log("Hello from $name!");\n');
          await File('$projectPath/package.json').writeAsString('{\n  "name": "$name",\n  "version": "1.0.0",\n  "main": "index.js",\n  "scripts": {\n    "start": "node index.js"\n  }\n}\n');
          await File('$projectPath/README.md').writeAsString('# $name\n\nA Node.js project.\n');
          _addTermOutput('Created Node.js project with index.js, package.json, README.md');
        default: // Blank
          await File('$projectPath/README.md').writeAsString('# $name\n\nA new project.\n');
          _addTermOutput('Created blank project with README.md');
      }

      _currentDir = projectPath;
      await _loadFileTree();
      if (_fileTreeOpen == false) setState(() => _fileTreeOpen = true);
      _scrollToBottom();
    } catch (e) {
      _addTermError('Failed to create project: $e');
    }
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = ref.watch(devEntriesProvider);
    final isTyping = ref.watch(devIsTypingProvider);

    // Listen to dev agent session state changes (isolated from main chat)
    ref.listen<AgentSessionState>(devAgentSessionProvider, (prev, next) {
      _onSessionStateChanged(prev, next);
    });

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: SafeArea(
        child: Row(
          children: [
            // File tree drawer
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: _fileTreeOpen ? 220 : 0,
              child: _fileTreeOpen ? _buildFileTree(cs) : const SizedBox.shrink(),
            ),
            // Main content: unified terminal-style view
            Expanded(
              child: Column(
                children: [
                  _buildToolbar(cs),
                  Expanded(child: _buildUnifiedView(cs, entries, isTyping)),
                  _buildInputArea(cs, isTyping),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: null,
    );
  }

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        border: Border(bottom: BorderSide(color: const Color(0xFF3C3C3C), width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _fileTreeOpen ? Icons.folder_open : Icons.folder_outlined,
              size: 20,
              color: const Color(0xFFCCCCCC),
            ),
            onPressed: () {
              setState(() => _fileTreeOpen = !_fileTreeOpen);
              if (_fileTreeOpen) _loadFileTree();
            },
            tooltip: 'File tree',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.terminal, size: 18, color: Color(0xFF4EC9B0)),
          const SizedBox(width: 6),
          const Text(
            'Dev Mode',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFCCCCCC)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(6),
            ),
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              _currentDir.isEmpty ? '...' : _currentDir.replaceFirst(RegExp(r'^/storage/emulated/0/Android/data/[^/]+/files'), '~/app'),
              style: const TextStyle(fontSize: 11, color: Color(0xFF9D9D9D), fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined, size: 18, color: Color(0xFF9D9D9D)),
            onPressed: () {
              ref.read(devEntriesProvider.notifier).state = [];
            },
            tooltip: 'Clear',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder, size: 18, color: Color(0xFF4EC9B0)),
            onPressed: _showCreateProjectDialog,
            tooltip: 'New Project',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedView(ColorScheme cs, List<_DevEntry> entries, bool isTyping) {
    if (entries.isEmpty && !isTyping) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal, size: 48, color: Color(0xFF4EC9B0)),
            const SizedBox(height: 12),
            const Text(
              'Dev Mode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFCCCCCC)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Type a message for AI, or prefix with \$ for shell commands',
              style: TextStyle(fontSize: 13, color: Color(0xFF808080)),
            ),
            const SizedBox(height: 16),
            _QuickAction(
              text: 'Create a Flutter project',
              onTap: () => _sendToAI('Create a new Flutter project in ${_currentDir.isEmpty ? "/KoloProjects" : _currentDir}/my_app'),
            ),
            _QuickAction(
              text: 'Build a REST API',
              onTap: () => _sendToAI('Create a Python Flask REST API in ${_currentDir.isEmpty ? "/KoloProjects" : _currentDir}/api'),
            ),
            _QuickAction(
              text: '\$ ls -la',
              onTap: () => _executeTerminalCommand('ls -la'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 60),
          itemCount: entries.length + (isTyping ? 1 : 0),
          itemBuilder: (context, index) {
            if (isTyping && index == entries.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4EC9B0)),
                  ),
                  const SizedBox(width: 8),
                  const Text('Thinking...', style: TextStyle(fontSize: 13, color: Color(0xFF808080), fontFamily: 'monospace')),
                ]),
              );
            }
            return _buildEntry(entries[index]);
          },
        ),
        if (_showScrollFab)
          Positioned(
            right: 8,
            bottom: 8,
            child: FloatingActionButton.small(
              onPressed: _scrollToBottom,
              backgroundColor: const Color(0xFF333333),
              child: const Icon(Icons.arrow_downward, size: 18, color: Color(0xFFCCCCCC)),
            ),
          ),
      ],
    );
  }

  Widget _buildEntry(_DevEntry entry) {
    switch (entry.type) {
      case _DevEntryType.userMessage:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('❯ ', style: TextStyle(color: Color(0xFF569CD6), fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold)),
              Expanded(
                child: SelectableText(
                  entry.content,
                  style: const TextStyle(color: Color(0xFFD4D4D4), fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ],
          ),
        );
      case _DevEntryType.assistantMessage:
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF252526),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3C3C3C), width: 0.5),
          ),
          child: SelectableText(
            entry.content,
            style: const TextStyle(color: Color(0xFFD4D4D4), fontFamily: 'monospace', fontSize: 13, height: 1.5),
          ),
        );
      case _DevEntryType.toolCall:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A3A5C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF264F78), width: 0.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.build_outlined, size: 14, color: Color(0xFF569CD6)),
              const SizedBox(width: 6),
              Text(
                entry.toolName ?? entry.content,
                style: const TextStyle(
                  color: Color(0xFF569CD6),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      case _DevEntryType.toolResult:
        final isSuccess = entry.toolSuccess ?? true;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSuccess ? const Color(0xFF1E3A1E) : const Color(0xFF3A1E1E),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSuccess ? const Color(0xFF2D5A2D) : const Color(0xFF5A2D2D),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                    size: 13,
                    color: isSuccess ? const Color(0xFF6A9955) : const Color(0xFFF44747),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    entry.toolName ?? 'tool',
                    style: TextStyle(
                      color: isSuccess ? const Color(0xFF6A9955) : const Color(0xFFF44747),
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (entry.content.isNotEmpty) ...[
                const SizedBox(height: 4),
                SelectableText(
                  entry.content.length > 500 ? '${entry.content.substring(0, 500)}...' : entry.content,
                  style: TextStyle(
                    color: isSuccess ? const Color(0xFFD4D4D4) : const Color(0xFFF44747),
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        );
      case _DevEntryType.terminalInput:
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: SelectableText(
            entry.content,
            style: const TextStyle(color: Color(0xFF4EC9B0), fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600),
          ),
        );
      case _DevEntryType.terminalOutput:
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: SelectableText(
            entry.content,
            style: const TextStyle(color: Color(0xFFD4D4D4), fontFamily: 'monospace', fontSize: 12, height: 1.4),
          ),
        );
      case _DevEntryType.terminalError:
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: SelectableText(
            entry.content,
            style: const TextStyle(color: Color(0xFFF44747), fontFamily: 'monospace', fontSize: 12, height: 1.4),
          ),
        );
    }
  }

  Widget _buildInputArea(ColorScheme cs, bool isTyping) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF252526),
        border: Border(top: BorderSide(color: Color(0xFF3C3C3C), width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: InputBar(
        key: _inputBarKey,
        onSend: (text, {attachments}) => _handleInput(text),
        isLoading: isTyping,
        onCancel: () {
          ref.read(devAgentSessionProvider.notifier).cancel();
          ref.read(devIsTypingProvider.notifier).state = false;
        },
      ),
    );
  }

  Widget _buildFileTree(ColorScheme cs) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF252526),
        border: Border(right: BorderSide(color: Color(0xFF3C3C3C), width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.folder_special, size: 18, color: Color(0xFFC09553)),
                const SizedBox(width: 8),
                const Text(
                  'Projects',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFCCCCCC)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF3C3C3C)),
          if (_fileTreeLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF4EC9B0))),
            )
          else if (_fileTree.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.create_new_folder_outlined, size: 32, color: Color(0xFF555555)),
                  const SizedBox(height: 8),
                  const Text('No projects yet', style: TextStyle(fontSize: 12, color: Color(0xFF808080))),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _showCreateProjectDialog,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Create one', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _fileTree.length,
                itemBuilder: (context, index) => _buildFileTreeNode(_fileTree[index], 0),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showCreateProjectDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Project', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFCCCCCC),
                  side: const BorderSide(color: Color(0xFF555555)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileTreeNode(_FileNode node, int depth) {
    final indent = depth * 16.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            if (node.isDirectory) {
              _toggleNode(node);
            } else {
              _openFileInTerminal(node);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(left: indent + 8, top: 4, bottom: 4),
            child: Row(
              children: [
                Icon(
                  node.isDirectory
                      ? (node.children?.isNotEmpty == true ? Icons.folder_open : Icons.folder)
                      : _fileIcon(node.name),
                  size: 16,
                  color: node.isDirectory
                      ? const Color(0xFFC09553)
                      : const Color(0xFF9D9D9D),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC), fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (node.children != null)
          ...node.children!.map((child) => _buildFileTreeNode(child, depth + 1)),
      ],
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return Icons.code;
      case 'py': return Icons.code;
      case 'js': case 'ts': return Icons.javascript;
      case 'json': case 'yaml': case 'yml': return Icons.settings;
      case 'md': return Icons.description;
      case 'png': case 'jpg': case 'webp': return Icons.image;
      default: return Icons.insert_drive_file;
    }
  }
}

// ── Models ──

class _FileNode {
  final String name;
  final String path;
  final bool isDirectory;
  List<_FileNode>? children;
  _FileNode({required this.name, required this.path, required this.isDirectory, this.children});
}

// ── Quick action chip ──

class _QuickAction extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _QuickAction({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 24),
      child: ActionChip(
        label: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC))),
        onPressed: onTap,
        side: const BorderSide(color: Color(0xFF555555)),
        backgroundColor: const Color(0xFF333333),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}
