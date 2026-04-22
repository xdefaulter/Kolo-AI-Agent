import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import 'message_bubble.dart';
import 'input_bar.dart';
import 'tool_result_card.dart';
import 'date_separator.dart';
import 'scroll_to_bottom_fab.dart';
import 'slide_in_message.dart';
import '../../core/agent/agent_session.dart';
import '../../core/agent/conversation_manager.dart';
import '../../core/storage/database.dart';
import '../../core/tools/tool_bootstrap.dart';
import '../../core/tools/tool_registry.dart';
import '../../core/tools/tool_base.dart';
import '../../core/theme_provider.dart';
import '../../core/providers.dart';
import '../../core/providers_state.dart';
import '../../core/haptics.dart';
import '../../core/connectivity_service.dart';
import '../settings/settings_screen.dart';
import '../settings/tools_permission_screen.dart';
import '../shared/page_transitions.dart';

const _uuid = Uuid();

// Tool registry — initialized once
final toolRegistryProvider = Provider<ToolRegistry>((ref) => bootstrapTools());

// Chat messages UI state — now includes timestamp
final chatMessagesProvider = StateProvider<List<ChatMessageUI>>((ref) => []);

// Chat list state
final chatListProvider = StateProvider<List<ChatEntry>>((ref) => []);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<InputBarState> _inputBarKey = GlobalKey();
  bool _sessionInitialized = false;
  String? _lastErrorMessage;
  bool _showScrollFab = false;
  String _searchQuery = '';
  bool _enterToSend = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSession();
      _loadChats();
      _loadSettings();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final show = maxScroll - currentScroll > 200;
    if (show != _showScrollFab) {
      setState(() => _showScrollFab = show);
    }
  }

  void _initSession() {
    if (_sessionInitialized) return;
    final registry = ref.read(toolRegistryProvider);
    final notifier = ref.read(agentSessionProvider.notifier);
    notifier.init(registry);
    // Load persisted permission settings
    notifier.session?.permissionManager.loadPersistedSettings();
    _sessionInitialized = true;
  }

  Future<void> _loadChats() async {
    final chats = await AppDatabase.instance.getAllChats();
    ref.read(chatListProvider.notifier).state = chats;
    if (chats.isNotEmpty) {
      await _loadChat(chats.first);
    }
  }

  Future<void> _loadSettings() async {
    final val = await AppDatabase.instance.getSetting('enter_to_send');
    if (mounted) {
      setState(() => _enterToSend = val == 'true');
    }
  }

  Future<void> _togglePin(ChatEntry chat) async {
    Haptics.selection();
    chat.isPinned = !chat.isPinned;
    await AppDatabase.instance.saveChat(chat);
    // Refresh list — pinned sort first
    final chats = await AppDatabase.instance.getAllChats();
    chats.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    ref.read(chatListProvider.notifier).state = chats;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(chat.isPinned ? 'Chat pinned' : 'Chat unpinned'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ));
    }
  }

  Future<void> _markRead(String chatId) async {
    final chats = ref.read(chatListProvider);
    final idx = chats.indexWhere((c) => c.id == chatId);
    if (idx >= 0 && chats[idx].unreadCount > 0) {
      chats[idx].unreadCount = 0;
      ref.read(chatListProvider.notifier).state = List.from(chats);
      await AppDatabase.instance.saveChat(chats[idx]);
    }
  }

  Future<void> _loadChat(ChatEntry chat) async {
    // Save draft of current chat before switching
    final oldChatId = ref.read(activeChatIdProvider);
    if (oldChatId != chat.id) {
      final currentText = _inputBarKey.currentState?.currentText ?? '';
      if (currentText.isNotEmpty) {
        await AppDatabase.instance.saveDraft(oldChatId, currentText);
      } else {
        await AppDatabase.instance.saveDraft(oldChatId, '');
      }
    }

    ref.read(activeChatIdProvider.notifier).state = chat.id;
    final messages = await AppDatabase.instance.getMessages(chat.id);
    final uiMessages = messages.map((m) => ChatMessageUI(
      role: m.role,
      content: m.content,
      toolName: m.toolName,
      toolSuccess: m.toolSuccess,
      timestamp: m.createdAt,
    )).toList();
    ref.read(chatMessagesProvider.notifier).state = uiMessages;

    // Replay messages into the conversation manager so context is preserved
    final chatMessages = messages.map((m) => ChatMessage(
      role: m.role,
      content: m.content,
      toolCallId: m.toolCallId,
      toolCalls: m.toolCalls != null
          ? (m.toolCalls is List ? m.toolCalls as List<Map<String, dynamic>> : null)
          : null,
    )).toList();
    ref.read(agentSessionProvider.notifier).loadMessages(chatMessages);

    // Restore draft
    final draft = await AppDatabase.instance.getDraft(chat.id);
    if (draft != null && draft.isNotEmpty) {
      _inputBarKey.currentState?.setText(draft);
    } else {
      _inputBarKey.currentState?.setText('');
    }

    _scrollToBottom();
  }

  Future<void> _startNewChat() async {
    final chatId = _uuid.v4();
    final chat = ChatEntry(id: chatId);
    await AppDatabase.instance.saveChat(chat);
    ref.read(activeChatIdProvider.notifier).state = chatId;
    ref.read(chatMessagesProvider.notifier).state = [];
    ref.read(agentSessionProvider.notifier).clearConversation();
    final chats = await AppDatabase.instance.getAllChats();
    ref.read(chatListProvider.notifier).state = chats;
  }

  Future<void> _deleteChat(String chatId) async {
    final chats = ref.read(chatListProvider);
    final chatToDelete = chats.where((c) => c.id == chatId).firstOrNull;
    if (chatToDelete == null) return;

    Haptics.medium();

    // Immediately remove from UI
    final remainingChats = chats.where((c) => c.id != chatId).toList();
    ref.read(chatListProvider.notifier).state = remainingChats;

    // If deleting active chat, switch to another
    if (chatId == ref.read(activeChatIdProvider)) {
      if (remainingChats.isNotEmpty) {
        await _loadChat(remainingChats.first);
      } else {
        await _startNewChat();
      }
    }

    // Show undo snackbar
    ScaffoldMessenger.of(context).clearSnackBars();
    final snackbar = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${chatToDelete.title}"'),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            // Restore the chat
            final restored = List<ChatEntry>.from(ref.read(chatListProvider));
            restored.insert(0, chatToDelete);
            ref.read(chatListProvider.notifier).state = restored;
          },
        ),
      ),
    );

    // Wait for snackbar to finish, then actually delete from DB
    snackbar.closed.then((reason) async {
      if (reason == SnackBarClosedReason.action) {
        // User undid — re-save the chat
        await AppDatabase.instance.saveChat(chatToDelete);
      } else {
        // User didn't undo — delete from DB permanently
        await AppDatabase.instance.deleteChat(chatId);
      }
    });
  }

  Future<void> _sendMessage(String text, {List<ChatAttachment>? attachments}) async {
    if (text.trim().isEmpty && (attachments == null || attachments.isEmpty)) return;

    Haptics.light();
    _lastErrorMessage = null;

    // Build display text (include attachment names)
    final displayText = text.isEmpty && attachments != null && attachments.isNotEmpty
        ? '[${attachments.map((a) => a.name).join(', ')}]'
        : text;

    // Compose full content for LLM (include text + file contents)
    String fullContent = text;
    if (attachments != null && attachments.isNotEmpty) {
      for (final att in attachments) {
        if (att.mimeType.startsWith('image/')) continue;
        if (att.mimeType.startsWith('text/') || att.mimeType == 'application/json') {
          try {
            final decoded = String.fromCharCodes(base64Decode(att.base64Data));
            fullContent += '\n\n--- File: ${att.name} ---\n$decoded\n--- End of ${att.name} ---';
          } catch (_) {}
        } else if (att.mimeType == 'application/pdf') {
          fullContent += '\n\n[Attached PDF: ${att.name} (${(att.base64Data.length * 0.75 / 1024).round()}KB)]';
        } else {
          fullContent += '\n\n[Attached file: ${att.name} (${att.mimeType})]';
        }
      }
    }

    // Add user message to UI immediately with timestamp
    final now = DateTime.now();
    final messages = List<ChatMessageUI>.from(ref.read(chatMessagesProvider));
    messages.add(ChatMessageUI(
      role: 'user',
      content: displayText,
      imagePaths: attachments?.where((a) => a.mimeType.startsWith('image/')).map((a) => a.filePath).whereType<String>().toList(),
      timestamp: now,
      isNew: true,
    ));
    ref.read(chatMessagesProvider.notifier).state = messages;

    // Persist user message
    final chatId = ref.read(activeChatIdProvider);
    await AppDatabase.instance.addMessage(chatId, MessageEntry(
      id: _uuid.v4(),
      chatId: chatId,
      role: 'user',
      content: displayText,
    ));

    _scrollToBottom();

    // Set permission callbacks fresh
    final notifier = ref.read(agentSessionProvider.notifier);
    notifier.setPermissionCallbacks(
      promptUser: (toolName, params, permission) => _showPermissionDialog(
        toolName: toolName,
        params: params,
        permission: permission,
      ),
      biometricPrompt: (toolName, params, permission) => _showPermissionDialog(
        toolName: toolName,
        params: params,
        permission: permission,
        isDangerous: true,
      ),
    );

    // Build vision attachments for the LLM
    List<ChatAttachment>? imageAttachments;
    if (attachments != null) {
      imageAttachments = attachments.where((a) => a.mimeType.startsWith('image/')).toList();
    }

    // Run agent loop with attachments
    notifier.sendMessage(fullContent, imageAttachments: imageAttachments);

    // Auto-title: update chat title from first user message
    final chatList = ref.read(chatListProvider);
    final currentChat = chatList.where((c) => c.id == chatId).firstOrNull;
    if (currentChat != null && currentChat.title == 'New Chat') {
      currentChat.title = text.length > 50 ? '${text.substring(0, 50)}...' : text;
      await AppDatabase.instance.saveChat(currentChat);
      final chats = await AppDatabase.instance.getAllChats();
      ref.read(chatListProvider.notifier).state = chats;
    }
  }

  /// Retry the last user message
  void _retryLastMessage() {
    Haptics.light();
    final messages = ref.read(chatMessagesProvider);
    final lastUserMsg = messages.lastWhere(
      (m) => m.role == 'user',
      orElse: () => ChatMessageUI(role: 'user', content: ''),
    );
    if (lastUserMsg.content.isNotEmpty) {
      final updated = List<ChatMessageUI>.from(messages);
      if (updated.isNotEmpty && updated.last.role == 'assistant' && _lastErrorMessage != null) {
        updated.removeLast();
        ref.read(chatMessagesProvider.notifier).state = updated;
      }
      _sendMessage(lastUserMsg.content);
    }
  }

  /// Edit the last user message
  void _editLastMessage() {
    Haptics.selection();
    final messages = ref.read(chatMessagesProvider);
    final lastUserIdx = messages.lastIndexWhere((m) => m.role == 'user');
    if (lastUserIdx >= 0) {
      final updated = messages.sublist(0, lastUserIdx);
      ref.read(chatMessagesProvider.notifier).state = updated;
    }
  }

  void _cancelRun() {
    Haptics.medium();
    ref.read(agentSessionProvider.notifier).cancel();
  }

  void _shareMessage(String content) {
    Share.share(content);
  }

  void _copyMessage(String content) {
    Haptics.light();
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _showPermissionDialog({
    required String toolName,
    required Map<String, dynamic> params,
    required ToolPermission permission,
    bool isDangerous = false,
  }) async {
    if (!mounted) return false;
    bool alwaysAllow = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          icon: Icon(
            isDangerous ? Icons.warning_amber_rounded : Icons.shield_outlined,
            color: isDangerous ? Colors.orange : Colors.blue,
          ),
          title: Text(isDangerous ? 'Dangerous Action' : 'Permission Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tool "$toolName" wants to execute:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Text(
                    params.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
              if (isDangerous) ...[
                const SizedBox(height: 12),
                Text(
                  'This is a dangerous operation. Are you sure?',
                  style: TextStyle(color: Colors.orange.shade300, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: alwaysAllow,
                onChanged: (v) => setDialogState(() => alwaysAllow = v ?? false),
                title: const Text('Always allow this tool'),
                subtitle: const Text('Don\'t ask again for this session'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Deny'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: isDangerous
                  ? FilledButton.styleFrom(backgroundColor: Colors.orange.shade800)
                  : null,
              child: Text(isDangerous ? 'Allow (Dangerous)' : 'Allow'),
            ),
          ],
        ),
      ),
    );
    if (result == true && alwaysAllow) {
      final session = ref.read(agentSessionProvider.notifier).session;
      session?.permissionManager.alwaysAllow(toolName);
    }
    return result ?? false;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Format a DateTime as a short time string
  String _formatTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour12:$m $period';
  }

  /// Format a DateTime as a date separator label
  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${_monthName(dt.month)} ${dt.day}';
  }

  String _monthName(int month) => [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][month];

  /// Check if two DateTimes are on the same day
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    final sessionState = ref.watch(agentSessionProvider);

    // Listen to session state changes for real-time UI updates
    ref.listen<AgentSessionState>(agentSessionProvider, (prev, next) {
      _onSessionStateChanged(prev, next);
    });

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: _buildAppBarTitle(),
        centerTitle: true,
        actions: [
          if (sessionState.isRunning)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
              tooltip: 'Stop',
              onPressed: _cancelRun,
            ),
          _buildModelSwitcher(),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => pushSlideRight(
              context,
              const SettingsScreen(),
            ),
          ),
        ],
      ),
      drawer: _buildChatDrawer(),
      body: Column(
        children: [
          // Offline banner
          Consumer(builder: (context, ref, _) {
            final isOnline = ref.watch(isOnlineProvider);
            if (isOnline) return const SizedBox.shrink();
            return MaterialBanner(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              content: Text(
                'You are offline. Messages will be sent when connection is restored.',
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
              actions: [const SizedBox.shrink()],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            );
          }),
          Expanded(
            child: Stack(
              children: [
                messages.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: messages.length + _dateSeparatorCount(messages),
                        itemBuilder: (context, index) {
                          // Interleave date separators
                          return _buildMessageOrSeparator(messages, index);
                        },
                      ),
                // Scroll-to-bottom FAB
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: ScrollToBottomFab(
                    visible: _showScrollFab,
                    onTap: _scrollToBottom,
                  ),
                ),
              ],
            ),
          ),
          InputBar(
            onSend: _sendMessage,
            isLoading: sessionState.isRunning,
            onCancel: sessionState.isRunning ? _cancelRun : null,
            enterToSend: _enterToSend,
          ),
        ],
      ),
    );
  }

  /// Calculate how many date separators to add
  int _dateSeparatorCount(List<ChatMessageUI> messages) {
    int count = 0;
    DateTime? lastDate;
    for (final m in messages) {
      if (m.timestamp != null) {
        if (lastDate == null || !_sameDay(lastDate, m.timestamp!)) {
          count++;
          lastDate = m.timestamp;
        }
      }
    }
    return count;
  }

  /// Build either a date separator or a message bubble
  Widget _buildMessageOrSeparator(List<ChatMessageUI> messages, int index) {
    // We need to interleave date separators as virtual items
    int msgIndex = 0;
    int virtualIndex = 0;
    DateTime? lastDate;

    for (final m in messages) {
      if (m.timestamp != null && (lastDate == null || !_sameDay(lastDate, m.timestamp!))) {
        if (virtualIndex == index) {
          return DateSeparator(label: _dateLabel(m.timestamp!));
        }
        virtualIndex++;
        lastDate = m.timestamp;
      }
      if (virtualIndex == index) {
        final msg = messages[msgIndex];
        // Determine if next message is same role for grouping
        final isLastInGroup = msgIndex == messages.length - 1 ||
            messages[msgIndex + 1].role != msg.role;

        if (msg.role == 'tool') {
          return ToolResultCard(
            toolName: msg.toolName ?? 'unknown',
            result: msg.content,
            success: msg.toolSuccess,
          );
        }

        final isError = msg.role == 'assistant' &&
            msg.content.startsWith('Error:') &&
            msgIndex == messages.length - 1;

        return SlideInMessage(
          isActive: msg.isNew,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MessageBubble(
              role: msg.role,
              content: msg.content,
              thinkingContent: msg.thinkingContent,
              isStreaming: msg.isStreaming,
              imagePaths: msg.imagePaths,
              timestamp: msg.timestamp != null ? _formatTime(msg.timestamp!) : null,
            ),
            // Action buttons for messages
            if (msg.role == 'assistant' && !msg.isStreaming) ...[
              Padding(
                padding: EdgeInsets.only(left: 48, bottom: isLastInGroup ? 8.0 : 2.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _actionChip(Icons.share_outlined, 'Share', () => _shareMessage(msg.content)),
                    const SizedBox(width: 6),
                    _actionChip(Icons.copy, 'Copy', () => _copyMessage(msg.content)),
                    if (isError) ...[
                      const SizedBox(width: 6),
                      _actionChip(Icons.refresh, 'Retry', _retryLastMessage),
                      const SizedBox(width: 6),
                      _actionChip(Icons.edit_outlined, 'Edit', _editLastMessage),
                    ],
                  ],
                ),
              ),
            ],
            if (msg.role == 'user' && !msg.isStreaming && isLastInGroup) ...[
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _actionChip(Icons.copy, 'Copy', () => _copyMessage(msg.content)),
                  ],
                ),
              ),
            ],
          ],
        ),
        );
      }
      virtualIndex++;
      msgIndex++;
    }
    return const SizedBox.shrink();
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        Haptics.light();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), // 48dp min touch target
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          ],
        ),
      ),
    );
  }

  /// React to agent session state for real-time streaming UI
  void _onSessionStateChanged(AgentSessionState? prev, AgentSessionState next) {
    final chatId = ref.read(activeChatIdProvider);
    final messages = List<ChatMessageUI>.from(ref.read(chatMessagesProvider));

    // Remove previous streaming assistant message if any
    messages.removeWhere((m) => m.isStreaming);

    switch (next) {
      case AgentSessionRunning(:final currentContent, :final currentThinking, :final toolResults):
        // Update streaming assistant content
        if (currentContent.isNotEmpty || currentThinking.isNotEmpty) {
          messages.add(ChatMessageUI(
            role: 'assistant',
            content: currentContent.isEmpty && currentThinking.isNotEmpty ? '...' : currentContent,
            thinkingContent: currentThinking.isNotEmpty ? currentThinking : null,
            isStreaming: true,
            timestamp: DateTime.now(),
            isNew: true,
          ));
        }
        // Add tool results that aren't already shown
        final existingToolIds = messages
            .where((m) => m.role == 'tool' && m.toolCallId != null)
            .map((m) => m.toolCallId)
            .toSet();
        for (final tr in toolResults) {
          if (!existingToolIds.contains(tr.toolCallId)) {
            messages.add(ChatMessageUI(
              role: 'tool',
              content: tr.result.toDisplayString(),
              toolName: tr.toolName,
              toolSuccess: tr.result.success,
              toolCallId: tr.toolCallId,
              timestamp: DateTime.now(),
              isNew: true,
            ));
            // Persist tool result
            AppDatabase.instance.addMessage(chatId, MessageEntry(
              id: _uuid.v4(),
              chatId: chatId,
              role: 'tool',
              content: tr.result.toDisplayString(),
              toolName: tr.toolName,
              toolSuccess: tr.result.success,
              toolCallId: tr.toolCallId,
            ));
          }
        }
      case AgentSessionCompleted(:final content, :final thinkingContent, :final toolResults, :final wasCancelled):
        // Finalize assistant message
        if (content.isNotEmpty) {
          messages.add(ChatMessageUI(
            role: 'assistant',
            content: wasCancelled ? '$content\n\n⏹ Stopped' : content,
            thinkingContent: thinkingContent.isNotEmpty ? thinkingContent : null,
            timestamp: DateTime.now(),
            isNew: true,
          ));
          // Persist assistant message
          AppDatabase.instance.addMessage(chatId, MessageEntry(
            id: _uuid.v4(),
            chatId: chatId,
            role: 'assistant',
            content: content,
          ));
        }
        // Add any remaining tool results not yet shown
        final existingToolIds = messages
            .where((m) => m.role == 'tool' && m.toolCallId != null)
            .map((m) => m.toolCallId)
            .toSet();
        for (final tr in toolResults) {
          if (!existingToolIds.contains(tr.toolCallId)) {
            messages.add(ChatMessageUI(
              role: 'tool',
              content: tr.result.toDisplayString(),
              toolName: tr.toolName,
              toolSuccess: tr.result.success,
              toolCallId: tr.toolCallId,
              timestamp: DateTime.now(),
              isNew: true,
            ));
            AppDatabase.instance.addMessage(chatId, MessageEntry(
              id: _uuid.v4(),
              chatId: chatId,
              role: 'tool',
              content: tr.result.toDisplayString(),
              toolName: tr.toolName,
              toolSuccess: tr.result.success,
              toolCallId: tr.toolCallId,
            ));
          }
        }
        // Update chat metadata
        _updateChatMeta(chatId, messages.length);
        Haptics.light(); // done haptic
      case AgentSessionError(:final message):
        Haptics.heavy();
        _lastErrorMessage = message;
        messages.add(ChatMessageUI(role: 'assistant', content: 'Error: $message', timestamp: DateTime.now(), isNew: true));
        AppDatabase.instance.addMessage(chatId, MessageEntry(
          id: _uuid.v4(),
          chatId: chatId,
          role: 'assistant',
          content: 'Error: $message',
        ));
      case AgentSessionIdle():
        break;
    }

    ref.read(chatMessagesProvider.notifier).state = messages;
    _scrollToBottom();
  }

  Future<void> _updateChatMeta(String chatId, int msgCount) async {
    final chats = ref.read(chatListProvider);
    final chat = chats.where((c) => c.id == chatId).firstOrNull;
    if (chat != null) {
      chat.messageCount = msgCount;
      chat.updatedAt = DateTime.now();
      await AppDatabase.instance.saveChat(chat);
      ref.read(chatListProvider.notifier).state = List.from(chats);
    }
  }

  Widget _buildAppBarTitle() {
    final chatId = ref.watch(activeChatIdProvider);
    final chats = ref.watch(chatListProvider);
    final currentChat = chats.where((c) => c.id == chatId).firstOrNull;
    return Text(
      currentChat?.title ?? 'Kolo AI Agent',
      style: const TextStyle(fontSize: 16),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildModelSwitcher() {
    final providers = ref.watch(providersProvider);
    if (providers.isEmpty) return const SizedBox.shrink();
    final provider = providers.firstWhere((p) => p.isActive, orElse: () => providers.first);
    final models = provider.models;
    final activeModel = provider.activeModel;
    if (models.length <= 1) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 18, color: Theme.of(context).colorScheme.onSurface),
        ],
      ),
      tooltip: 'Switch model',
      onSelected: (modelId) {
        Haptics.selection();
        ref.read(providersProvider.notifier).setActiveModel(provider.id, modelId);
      },
      itemBuilder: (ctx) => models.map((m) => PopupMenuItem(
            value: m.modelId,
            child: Row(
              children: [
                if (m.modelId == activeModel?.modelId)
                  Icon(Icons.check, size: 16, color: Theme.of(ctx).colorScheme.primary)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(m.displayName ?? m.modelId, overflow: TextOverflow.ellipsis)),
              ],
            ),
          )).toList(),
        );
  }

  Widget _buildChatDrawer() {
    final chats = ref.watch(chatListProvider);
    final activeId = ref.watch(activeChatIdProvider);
    final cs = Theme.of(context).colorScheme;

    // Filter chats by search
    final filteredChats = _searchQuery.isEmpty
        ? chats
        : chats.where((c) => c.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    // Sort: pinned first, then by updatedAt
    filteredChats.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header with brand gradient
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary.withValues(alpha: 0.15), cs.primaryContainer.withValues(alpha: 0.1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.smart_toy, color: cs.primary, size: 28),
                  const SizedBox(width: 10),
                  Text('Kolo AI Agent', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.primary)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _startNewChat();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New Chat'),
                ),
              ),
            ),
            // Search bar
            if (chats.length > 3) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search chats...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(height: 4),
            ],
            const Divider(height: 1),
            Expanded(
              child: filteredChats.isEmpty
                  ? Center(child: Text('No chats found', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))))
                  : ListView.builder(
                      itemCount: filteredChats.length,
                      itemBuilder: (ctx, i) {
                        final chat = filteredChats[i];
                        final isActive = chat.id == activeId;
                        return ListTile(
                          selected: isActive,
                          selectedTileColor: cs.primary.withValues(alpha: 0.1),
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(chat.isPinned ? Icons.push_pin : Icons.chat_bubble_outline, size: 20,
                                  color: chat.isPinned ? cs.primary : null),
                              if (chat.unreadCount > 0)
                                Positioned(
                                  right: -4, top: -4,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle),
                                    constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                                    child: Text(
                                      chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              color: chat.unreadCount > 0 ? cs.onSurface : cs.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          subtitle: Text(
                            '${chat.messageCount} msgs · ${_timeAgo(chat.updatedAt)}',
                            style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _deleteChat(chat.id),
                          ),
                          onLongPress: () => _togglePin(chat),
                          onTap: () {
                            Haptics.selection();
                            Navigator.pop(context);
                            _loadChat(chat);
                            _markRead(chat.id);
                          },
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Custom Instructions'),
              onTap: () {
                Navigator.pop(context);
                _showCustomInstructionsDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.build_outlined),
              title: const Text('Tools & Permissions'),
              subtitle: Text('${bootstrapTools().all.length} tools', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
              onTap: () {
                Navigator.pop(context);
                pushSlideRight(context, const ToolsPermissionScreen());
              },
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('Theme'),
              trailing: _buildThemeToggle(),
              onTap: () => _cycleTheme(),
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _cycleTheme() {
    Haptics.selection();
    ref.read(themeModeProvider.notifier).cycle();
  }

  Widget _buildThemeToggle() {
    final mode = ref.watch(themeModeProvider);
    final icon = switch (mode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    };
    return Icon(icon, size: 20);
  }

  Future<void> _showCustomInstructionsDialog() async {
    final saved = await AppDatabase.instance.getSetting('custom_instructions') ?? '';
    if (!mounted) return;
    final controller = TextEditingController(text: ref.read(customInstructionsProvider).isEmpty ? saved : ref.read(customInstructionsProvider));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Instructions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add instructions that modify the AI\'s behavior across all chats.',
              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'e.g. Always respond in French. Prefer concise answers.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result != null) {
      ref.read(customInstructionsProvider.notifier).state = result;
      await AppDatabase.instance.saveSetting('custom_instructions', result);
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated robot icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.95, end: 1.05),
              duration: const Duration(seconds: 2),
              curve: Curves.easeInOut,
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: Icon(Icons.smart_toy_outlined, size: 80, color: cs.primary.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 16),
            Text('Kolo AI Agent', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: cs.primary)),
            const SizedBox(height: 8),
            Text(
              'Your unlimited AI assistant\n${bootstrapTools().all.length} tools ready',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),
            // Quick action suggestion chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _suggestionChip(Icons.search, 'Search the web', 'Search the web for '),
                _suggestionChip(Icons.phone_android, 'Open an app', 'Open '),
                _suggestionChip(Icons.screenshot, 'Take a screenshot', 'Take a screenshot'),
                _suggestionChip(Icons.calculate, 'Calculate', 'Calculate '),
                _suggestionChip(Icons.location_on, 'Find nearby', 'What\'s near me?'),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => pushSlideRight(context, const SettingsScreen()),
              icon: const Icon(Icons.settings),
              label: const Text('Configure Provider'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionChip(IconData icon, String label, String prefix) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: cs.primary),
      label: Text(label),
      labelStyle: TextStyle(fontSize: 13, color: cs.onSurface),
      onPressed: () {
        Haptics.light();
        _sendMessage(prefix);
      },
    );
  }
}

/// UI model for a chat message — now includes timestamp
class ChatMessageUI {
  final String role;
  final String content;
  final String? thinkingContent;
  final String? toolName;
  final bool? toolSuccess;
  final bool isStreaming;
  final String? toolCallId;
  final List<String>? imagePaths;
  final DateTime? timestamp;
  final bool isNew; // true for real-time messages, false for loaded history
  ChatMessageUI({
    required this.role,
    required this.content,
    this.thinkingContent,
    this.toolName,
    this.toolSuccess,
    this.isStreaming = false,
    this.toolCallId,
    this.imagePaths,
    this.timestamp,
    this.isNew = false,
  });
}