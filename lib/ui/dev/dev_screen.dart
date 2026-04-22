import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/agent/agent_session.dart';
import '../../core/storage/database.dart';
import '../../core/tools/tool_bootstrap.dart';
import '../../core/tools/tool_registry.dart';
import '../../core/theme_provider.dart';
import '../../core/providers.dart';
import '../../core/providers_state.dart';
import '../chat/input_bar.dart';
import '../shared/page_transitions.dart';

/// Workspace root for dev projects
const kWorkspaceRoot = '/sdcard/KoloProjects';

// Dev message model (simpler than chat's ChatMessageUI)
class _DevMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final bool isTyping;
  _DevMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isTyping = false,
  });
}

// Dev session provider — separate from chat sessions
final devChatProvider = StateProvider<List<_DevMessage>>((ref) => []);
final devToolRegistryProvider = Provider<ToolRegistry>((ref) => bootstrapTools());
final devIsTypingProvider = StateProvider<bool>((ref) => false);

/// DevScreen: Claude Code-like mobile IDE
/// Layout: AI chat (top) + Terminal (bottom), File tree drawer (left swipe)
class DevScreen extends ConsumerStatefulWidget {
  const DevScreen({super.key});

  @override
  ConsumerState<DevScreen> createState() => _DevScreenState();
}

class _DevScreenState extends ConsumerState<DevScreen> {
  // ── Chat state ──
  final ScrollController _chatScrollController = ScrollController();
  final GlobalKey<InputBarState> _inputBarKey = GlobalKey();
  bool _showScrollFab = false;
  String? _lastErrorMessage;
  bool _sessionInitialized = false;

  // ── Terminal state ──
  final List<_TerminalLine> _terminalLines = [];
  final ScrollController _terminalScrollController = ScrollController();
  final TextEditingController _termInputController = TextEditingController();
  String _currentDir = kWorkspaceRoot;
  static const _termChannel = MethodChannel('com.kolo.ai/terminal');
  StreamSubscription? _termOutputSub;

  // ── Layout state ──
  double _chatFraction = 0.45; // How much screen is chat vs terminal
  bool _fileTreeOpen = false;
  List<_FileNode> _fileTree = [];
  bool _fileTreeLoading = false;

  @override
  void initState() {
    super.initState();
    _chatScrollController.addListener(_onChatScroll);
    _initSession();
    _ensureWorkspace();
    _loadFileTree();
  }

  @override
  void dispose() {
    _chatScrollController.dispose();
    _terminalScrollController.dispose();
    _termInputController.dispose();
    _termOutputSub?.cancel();
    super.dispose();
  }

  void _onChatScroll() {
    final max = _chatScrollController.position.maxScrollExtent;
    final current = _chatScrollController.offset;
    setState(() => _showScrollFab = (max - current) > 100);
  }

  // ── Session init ──
  Future<void> _initSession() async {
    if (_sessionInitialized) return;
    _sessionInitialized = true;

    final registry = ref.read(devToolRegistryProvider);
    final notifier = ref.read(agentSessionProvider.notifier);
    notifier.init(registry);
    notifier.session?.permissionManager.loadPersistedSettings();
  }

  Future<void> _ensureWorkspace() async {
    final dir = Directory(kWorkspaceRoot);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  // ── Send message to AI ──
  Future<void> _sendToAI(String text) async {
    if (text.trim().isEmpty) return;

    final messages = ref.read(devChatProvider);
    final userMsg = _DevMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );
    ref.read(devChatProvider.notifier).state = [...messages, userMsg];
    ref.read(devIsTypingProvider.notifier).state = true;

    _scrollChatToBottom();

    try {
      final notifier = ref.read(agentSessionProvider.notifier);
      // Inject workspace context into the system so the model knows where to work
      final workspaceContext = '\n[DEV MODE] You are in a local development environment. '
          'Workspace: $kWorkspaceRoot\n'
          'Current directory: $_currentDir\n'
          'Use read_file, write_file, list_directory, shell_exec, and other tools to code, test, and iterate. '
          'Always use absolute paths starting with $kWorkspaceRoot.';

      await notifier.sendMessage(text + workspaceContext);
    } catch (e) {
      final current = ref.read(devChatProvider);
      final errorMsg = _DevMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: 'assistant',
        content: 'Error: $e',
        timestamp: DateTime.now(),
      );
      ref.read(devChatProvider.notifier).state = [...current, errorMsg];
    } finally {
      ref.read(devIsTypingProvider.notifier).state = false;
    }
    _scrollChatToBottom();
  }

  void _onSessionStateChanged(AgentSessionState? prev, AgentSessionState next) {
    final current = List<_DevMessage>.from(ref.read(devChatProvider));
    switch (next) {
      case AgentSessionRunning(:final currentContent):
        // Update or add streaming assistant message
        current.removeWhere((m) => m.id == 'streaming');
        if (currentContent.isNotEmpty) {
          current.add(_DevMessage(
            id: 'streaming',
            role: 'assistant',
            content: currentContent,
            timestamp: DateTime.now(),
          ));
        }
        ref.read(devChatProvider.notifier).state = current;
        ref.read(devIsTypingProvider.notifier).state = true;
        _scrollChatToBottom();
      case AgentSessionCompleted(:final content, :final wasCancelled):
        current.removeWhere((m) => m.id == 'streaming');
        if (content.isNotEmpty) {
          current.add(_DevMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            role: 'assistant',
            content: wasCancelled ? '$content\n\n⏹ Stopped' : content,
            timestamp: DateTime.now(),
          ));
        }
        ref.read(devChatProvider.notifier).state = current;
        ref.read(devIsTypingProvider.notifier).state = false;
        _scrollChatToBottom();
      case AgentSessionError(:final message):
        current.removeWhere((m) => m.id == 'streaming');
        current.add(_DevMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: 'assistant',
          content: 'Error: $message',
          timestamp: DateTime.now(),
        ));
        ref.read(devChatProvider.notifier).state = current;
        ref.read(devIsTypingProvider.notifier).state = false;
        _scrollChatToBottom();
      case AgentSessionIdle():
        ref.read(devIsTypingProvider.notifier).state = false;
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Terminal ──
  Future<void> _executeTerminalCommand(String command) async {
    if (command.trim().isEmpty) return;

    _terminalLines.add(_TerminalLine(type: _LineType.input, text: '\$ $command'));
    _scrollTerminalToBottom();
    setState(() {});

    // Handle built-in commands
    if (command == 'clear') {
      _terminalLines.clear();
      setState(() {});
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
        _terminalLines.add(_TerminalLine(type: _LineType.output, text: '$_currentDir'));
      } else {
        _terminalLines.add(_TerminalLine(type: _LineType.error, text: 'cd: no such directory: $target'));
      }
      _scrollTerminalToBottom();
      setState(() {});
      _loadFileTree();
      return;
    }

    // Execute via method channel (PTY) or fallback to Process.run
    try {
      if (Platform.isAndroid) {
        await _executeViaPTY(command);
      } else {
        // Fallback for iOS / dev mode
        final result = await Process.run(
          '/bin/sh', ['-c', command],
          workingDirectory: _currentDir,
        ).timeout(const Duration(seconds: 30));

        if (result.stdout.toString().isNotEmpty) {
          _terminalLines.add(_TerminalLine(type: _LineType.output, text: result.stdout.toString()));
        }
        if (result.stderr.toString().isNotEmpty) {
          _terminalLines.add(_TerminalLine(type: _LineType.error, text: result.stderr.toString()));
        }
        if (result.exitCode != 0 && result.stdout.toString().isEmpty && result.stderr.toString().isEmpty) {
          _terminalLines.add(_TerminalLine(type: _LineType.error, text: 'Exit code: ${result.exitCode}'));
        }
      }
    } on TimeoutException {
      _terminalLines.add(_TerminalLine(type: _LineType.error, text: 'Command timed out (30s)'));
    } catch (e) {
      _terminalLines.add(_TerminalLine(type: _LineType.error, text: 'Error: $e'));
    }

    _scrollTerminalToBottom();
    setState(() {});
    _loadFileTree();
  }

  /// Execute command via Termux PTY on Android
  Future<void> _executeViaPTY(String command) async {
    try {
      final result = await _termChannel.invokeMethod<Map>('exec', {
        'command': command,
        'workingDir': _currentDir,
      });
      final stdout = result?['stdout'] as String? ?? '';
      final stderr = result?['stderr'] as String? ?? '';
      final exitCode = result?['exitCode'] as int? ?? 0;

      if (stdout.isNotEmpty) {
        _terminalLines.add(_TerminalLine(type: _LineType.output, text: stdout));
      }
      if (stderr.isNotEmpty) {
        _terminalLines.add(_TerminalLine(type: _LineType.error, text: stderr));
      }
      if (exitCode != 0 && stdout.isEmpty && stderr.isEmpty) {
        _terminalLines.add(_TerminalLine(type: _LineType.error, text: 'Exit code: $exitCode'));
      }
    } on PlatformException catch (e) {
      // Fallback to Process.run if PTY channel not available
      final result = await Process.run(
        '/system/bin/sh', ['-c', command],
        workingDirectory: _currentDir,
      ).timeout(const Duration(seconds: 30));

      if (result.stdout.toString().isNotEmpty) {
        _terminalLines.add(_TerminalLine(type: _LineType.output, text: result.stdout.toString()));
      }
      if (result.stderr.toString().isNotEmpty) {
        _terminalLines.add(_TerminalLine(type: _LineType.error, text: result.stderr.toString()));
      }
    }
  }

  void _scrollTerminalToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_terminalScrollController.hasClients) {
        _terminalScrollController.animateTo(
          _terminalScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── File Tree ──
  Future<void> _loadFileTree() async {
    setState(() => _fileTreeLoading = true);
    try {
      _fileTree = await _loadDirectory(kWorkspaceRoot);
    } catch (_) {}
    setState(() => _fileTreeLoading = false);
  }

  Future<List<_FileNode>> _loadDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return [];
    final nodes = <_FileNode>[];
    await for (final entity in dir.list()) {
      final name = entity.path.split('/').last;
      if (name.startsWith('.')) continue; // Skip hidden files
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
      setState(() => node.children = []); // Collapse
    } else {
      final children = await _loadDirectory(node.path);
      setState(() => node.children = children); // Expand
    }
  }

  void _openFileInTerminal(_FileNode node) {
    if (node.isDirectory) return;
    _termInputController.text = 'cat ${node.path}';
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final messages = ref.watch(devChatProvider);
    final isTyping = ref.watch(devIsTypingProvider);

    // Listen to agent session state changes
    ref.listen<AgentSessionState>(agentSessionProvider, (prev, next) {
      _onSessionStateChanged(prev, next);
    });

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // File tree drawer (slides in from left)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: _fileTreeOpen ? 220 : 0,
              child: _fileTreeOpen
                  ? _buildFileTree(cs)
                  : const SizedBox.shrink(),
            ),
            // Main content: Chat (top) + Terminal (bottom)
            Expanded(
              child: Column(
                children: [
                  // Dev toolbar
                  _buildToolbar(cs),
                  // Chat area
                  Expanded(
                    flex: (_chatFraction * 100).round(),
                    child: _buildChatArea(cs, messages),
                  ),
                  // Draggable divider
                  _buildDivider(cs),
                  // Terminal area
                  Expanded(
                    flex: ((1 - _chatFraction) * 100).round(),
                    child: _buildTerminalArea(cs),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          // File tree toggle
          IconButton(
            icon: Icon(_fileTreeOpen ? Icons.folder_open : Icons.folder_outlined, size: 20),
            onPressed: () {
              setState(() => _fileTreeOpen = !_fileTreeOpen);
              if (_fileTreeOpen) _loadFileTree();
            },
            tooltip: 'File tree',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: 4),
          Icon(Icons.terminal, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          Text('Dev Mode', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          // Current directory breadcrumb
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              _currentDir.replaceFirst(kWorkspaceRoot, '~/Projects'),
              style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7), fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Clear terminal
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            onPressed: () {
              _terminalLines.clear();
              setState(() {});
            },
            tooltip: 'Clear terminal',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea(ColorScheme cs, List<_DevMessage> messages) {
    final isTyping = ref.watch(devIsTypingProvider);
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Column(
        children: [
          // Messages
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.code, size: 48, color: cs.primary.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text('Dev Mode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
                        const SizedBox(height: 4),
                        Text('Ask me to code, debug, or build anything',
                            style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6))),
                        const SizedBox(height: 16),
                        _QuickAction(text: 'Create a new Flutter project', onTap: () => _sendToAI('Create a new Flutter project in $kWorkspaceRoot/my_app')),
                        _QuickAction(text: 'Build a REST API', onTap: () => _sendToAI('Create a Python Flask REST API in $kWorkspaceRoot/api')),
                        _QuickAction(text: 'Write a web scraper', onTap: () => _sendToAI('Write a web scraper in $kWorkspaceRoot/scraper')),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _chatScrollController,
                        padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 60),
                        itemCount: messages.length + (isTyping ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (isTyping && index == messages.length) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                                const SizedBox(width: 8),
                                Text('Thinking...', style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6))),
                              ]),
                            );
                          }
                          final msg = messages[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Align(
                              alignment: msg.role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                                decoration: BoxDecoration(
                                  color: msg.role == 'user' ? cs.primaryContainer : cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SelectableText(
                                  msg.content,
                                  style: TextStyle(fontSize: 13, color: cs.onSurface, fontFamily: 'monospace'),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (_showScrollFab)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: FloatingActionButton.small(
                            onPressed: _scrollChatToBottom,
                            child: const Icon(Icons.arrow_downward, size: 18),
                          ),
                        ),
                    ],
                  ),
          ),
          // Input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
            ),
            child: InputBar(
              key: _inputBarKey,
              onSend: (text, {attachments}) => _sendToAI(text),
              isLoading: isTyping,
              onCancel: () {
                ref.read(agentSessionProvider.notifier).cancel();
                ref.read(devIsTypingProvider.notifier).state = false;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(ColorScheme cs) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          _chatFraction += details.delta.dy / MediaQuery.of(context).size.height;
          _chatFraction = _chatFraction.clamp(0.15, 0.85);
        });
      },
      child: Container(
        height: 12,
        color: cs.surfaceContainerHighest,
        child: Row(
          children: [
            const SizedBox(width: 12),
            // Chat label
            Icon(Icons.chat_bubble_outline, size: 12, color: cs.onSurface.withValues(alpha: 0.4)),
            const SizedBox(width: 4),
            Text('AI', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.w600)),
            const Spacer(),
            // Drag handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)),
            ),
            const Spacer(),
            // Terminal label
            Text('Terminal', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.terminal, size: 12, color: cs.onSurface.withValues(alpha: 0.4)),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalArea(ColorScheme cs) {
    return Container(
      color: const Color(0xFF1E1E1E), // Dark terminal bg
      child: Column(
        children: [
          // Terminal output
          Expanded(
            child: ListView.builder(
              controller: _terminalScrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _terminalLines.length,
              itemBuilder: (context, index) {
                final line = _terminalLines[index];
                Color color;
                switch (line.type) {
                  case _LineType.input:
                    color = const Color(0xFF4EC9B0); // Green for commands
                  case _LineType.output:
                    color = const Color(0xFFD4D4D4); // Light gray
                  case _LineType.error:
                    color = const Color(0xFFF44747); // Red
                }
                return SelectableText(
                  line.text,
                  style: TextStyle(
                    color: color,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.4,
                  ),
                );
              },
            ),
          ),
          // Terminal input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF252526),
              border: Border(top: BorderSide(color: Color(0xFF3C3C3C), width: 0.5)),
            ),
            child: Row(
              children: [
                Text('\$ ', style: const TextStyle(color: Color(0xFF4EC9B0), fontFamily: 'monospace', fontSize: 13)),
                Expanded(
                  child: TextField(
                    controller: _termInputController,
                    style: const TextStyle(color: Color(0xFFD4D4D4), fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'Type a command...',
                      hintStyle: TextStyle(color: Color(0xFF6A6A6A)),
                    ),
                    onSubmitted: (cmd) {
                      _executeTerminalCommand(cmd);
                      _termInputController.clear();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.play_arrow, color: Color(0xFF4EC9B0), size: 20),
                  onPressed: () {
                    _executeTerminalCommand(_termInputController.text);
                    _termInputController.clear();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileTree(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(right: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.folder_special, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text('Projects', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          if (_fileTreeLoading)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (_fileTree.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.create_new_folder_outlined, size: 32, color: cs.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 8),
                  Text('No projects yet', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
                  Text('Ask the AI to create one!', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4))),
                ],
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _fileTree.length,
                itemBuilder: (context, index) => _buildFileTreeNode(_fileTree[index], 0, cs),
              ),
            ),
          // New project button
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _sendToAI('Create a new project in $kWorkspaceRoot'),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Project', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileTreeNode(_FileNode node, int depth, ColorScheme cs) {
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
                  color: node.isDirectory ? const Color(0xFFC09553) : cs.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(fontSize: 12, color: cs.onSurface, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (node.children != null)
          ...node.children!.map((child) => _buildFileTreeNode(child, depth + 1, cs)),
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

enum _LineType { input, output, error }

class _TerminalLine {
  final _LineType type;
  final String text;
  _TerminalLine({required this.type, required this.text});
}

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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 24),
      child: ActionChip(
        label: Text(text, style: TextStyle(fontSize: 12)),
        onPressed: onTap,
        side: BorderSide(color: cs.outlineVariant),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}