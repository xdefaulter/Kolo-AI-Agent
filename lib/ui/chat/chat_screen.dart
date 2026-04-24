import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import 'breathing_icon.dart';
import 'chat_message_ui.dart';
import 'chat_search_screen.dart';
import 'message_bubble.dart';
import 'prompt_library_sheet.dart';
import 'input_bar.dart';
import 'tool_result_card.dart';
import 'date_separator.dart';
import 'scroll_to_bottom_fab.dart';
import 'slide_in_message.dart';

export 'chat_message_ui.dart' show ChatMessageUI;
import '../../core/agent/agent_session.dart';
import '../../core/agent/conversation_manager.dart';
import '../../core/storage/database.dart';
import '../../core/tools/tool_bootstrap.dart';
import '../../core/tools/tool_registry.dart';
import '../../core/tools/custom_tools_state.dart';
import '../../core/memory/memory_service.dart';
import '../../core/tools/android/phone_control_mode.dart';
import '../../core/tools/tool_base.dart';
import '../../core/theme_provider.dart';
import '../../core/providers.dart';
import '../../core/providers_state.dart';
import '../../core/haptics.dart';
import '../../core/connectivity_service.dart';
import '../../core/folders/folder_service.dart';
import '../../core/outbox/outbox_service.dart';
import '../../core/ui/toast.dart';
import '../settings/settings_screen.dart';
import '../settings/tools_permission_screen.dart';
import '../shared/metrics_chip.dart';
import '../shared/page_transitions.dart';

const _uuid = Uuid();

// Tool registry — rebuilds when phone-control mode, the custom-tools set,
// or the "agent can create tools" toggle changes. Skills toggle isn't
// watched here because skills don't add new tools; they get injected into
// the system prompt at send time.
final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  final mode = ref.watch(phoneControlModeProvider);
  final customTools = ref.watch(customToolsProvider);
  final canCreate = ref.watch(agentCanCreateToolsProvider);
  final skills = ref.watch(skillsEnabledProvider);
  final canCreateMemories = ref.watch(agentCanCreateMemoriesProvider);
  return bootstrapTools(
    mode: mode,
    customTools: customTools,
    agentCanCreateTools: canCreate,
    skillsEnabled: skills,
    agentCanCreateMemories: canCreateMemories,
    onCustomToolsChanged: () => ref.read(customToolsProvider.notifier).reload(),
    onMemoriesChanged: () => ref.read(memoriesProvider.notifier).reload(),
  );
});

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
  bool _showScrollFab = false;
  String _searchQuery = '';
  bool _enterToSend = false;
  ProviderSubscription<AgentSessionState>? _sessionSub;
  ProviderSubscription<bool>? _connectivitySub;
  // 2.5: Cache interleaved items to avoid recomputation on every build
  List<dynamic>? _cachedInterleavedItems;
  int _cachedMessageCount = -1;
  int _cachedContentHash = -1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSession();
      _loadChats();
      _loadSettings();
      _sessionSub = ref.listenManual<AgentSessionState>(
        agentSessionProvider,
        (prev, next) => _onSessionStateChanged(prev, next),
      );
      // Drain the outbox on reconnect. The provider emits on every
      // connectivity change; filter to the offline → online transition
      // so we don't re-try on every WiFi flake.
      _connectivitySub = ref.listenManual<bool>(isOnlineProvider, (prev, next) {
        if (prev != true && next == true) {
          _drainOutbox();
        }
      }, fireImmediately: false);
    });
  }

  @override
  void dispose() {
    _sessionSub?.close();
    _connectivitySub?.close();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(chat.isPinned ? 'Chat pinned' : 'Chat unpinned'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
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
    final uiMessages = messages
        .map(
          (m) => ChatMessageUI(
            role: m.role,
            content: m.content,
            toolName: m.toolName,
            toolSuccess: m.toolSuccess,
            timestamp: m.createdAt,
            dbId: m.id,
            status: m.status,
            isError: m.role == 'assistant' && m.content.startsWith('Error:'),
          ),
        )
        .toList();
    ref.read(chatMessagesProvider.notifier).state = uiMessages;

    // Replay messages into the conversation manager so context is preserved
    final chatMessages = messages
        .map(
          (m) => ChatMessage(
            role: m.role,
            content: m.content,
            toolCallId: m.toolCallId,
            toolCalls: m.toolCalls != null
                ? (m.toolCalls is List
                      ? m.toolCalls as List<Map<String, dynamic>>
                      : null)
                : null,
          ),
        )
        .toList();
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

  Future<void> _sendMessage(
    String text, {
    List<ChatAttachment>? attachments,
  }) async {
    if (text.trim().isEmpty && (attachments == null || attachments.isEmpty))
      return;

    Haptics.light();

    // Build display text (include attachment names)
    final displayText =
        text.isEmpty && attachments != null && attachments.isNotEmpty
        ? '[${attachments.map((a) => a.name).join(', ')}]'
        : text;

    // Compose full content for LLM (include text + file contents).
    // StringBuffer avoids O(n) string reallocation per attachment.
    final contentBuf = StringBuffer(text);
    if (attachments != null && attachments.isNotEmpty) {
      for (final att in attachments) {
        if (att.mimeType.startsWith('image/')) continue;
        if (att.mimeType.startsWith('text/') ||
            att.mimeType == 'application/json') {
          try {
            final decoded = String.fromCharCodes(base64Decode(att.base64Data));
            contentBuf.write(
                '\n\n--- File: ${att.name} ---\n$decoded\n--- End of ${att.name} ---');
          } catch (_) {}
        } else if (att.mimeType == 'application/pdf') {
          contentBuf.write(
              '\n\n[Attached PDF: ${att.name} (${(att.base64Data.length * 0.75 / 1024).round()}KB)]');
        } else {
          contentBuf.write('\n\n[Attached file: ${att.name} (${att.mimeType})]');
        }
      }
    }
    final fullContent = contentBuf.toString();

    // Add user message to UI immediately with timestamp
    final now = DateTime.now();
    final messages = List<ChatMessageUI>.from(ref.read(chatMessagesProvider));
    final userMsgDbId = _uuid.v4();
    messages.add(
      ChatMessageUI(
        role: 'user',
        content: displayText,
        imagePaths: attachments
            ?.where((a) => a.mimeType.startsWith('image/'))
            .map((a) => a.filePath)
            .whereType<String>()
            .toList(),
        timestamp: now,
        isNew: true,
        dbId: userMsgDbId,
      ),
    );
    ref.read(chatMessagesProvider.notifier).state = messages;

    // Persist user message. If we're offline, mark it queued + enqueue
    // to the outbox; the connectivity listener below drains it on reconnect.
    final chatId = ref.read(activeChatIdProvider);
    final isOnline = ref.read(isOnlineProvider);
    await AppDatabase.instance.addMessage(
      chatId,
      MessageEntry(
        id: userMsgDbId,
        chatId: chatId,
        role: 'user',
        content: fullContent,
        status: isOnline ? null : 'queued',
      ),
    );
    if (!isOnline) {
      await OutboxService.instance.enqueue(
        OutboxItem(
          chatId: chatId,
          messageDbId: userMsgDbId,
          text: fullContent,
          queuedAt: now,
        ),
      );
      // Mark the already-added bubble as queued so its indicator renders
      // immediately; the drain path removes it on reconnect.
      final current = List<ChatMessageUI>.from(
        ref.read(chatMessagesProvider),
      );
      final i = current.lastIndexWhere((m) => m.dbId == userMsgDbId);
      if (i >= 0) {
        final old = current[i];
        current[i] = ChatMessageUI(
          role: old.role,
          content: old.content,
          thinkingContent: old.thinkingContent,
          toolName: old.toolName,
          toolSuccess: old.toolSuccess,
          toolCallId: old.toolCallId,
          imagePaths: old.imagePaths,
          timestamp: old.timestamp,
          isNew: old.isNew,
          dbId: old.dbId,
          isError: old.isError,
          status: 'queued',
        );
        ref.read(chatMessagesProvider.notifier).state = current;
      }
      showKoloToast(
        context,
        'Offline — message will send when you reconnect.',
        kind: ToastKind.info,
      );
      _scrollToBottom();
      return;
    }

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
      imageAttachments = attachments
          .where((a) => a.mimeType.startsWith('image/'))
          .toList();
    }

    // Run agent loop with attachments
    notifier.sendMessage(fullContent, imageAttachments: imageAttachments);

    // Auto-title: update chat title from first user message
    final chatList = ref.read(chatListProvider);
    final currentChat = chatList.where((c) => c.id == chatId).firstOrNull;
    if (currentChat != null && currentChat.title == 'New Chat') {
      currentChat.title = text.length > 50
          ? '${text.substring(0, 50)}...'
          : text;
      await AppDatabase.instance.saveChat(currentChat);
      final chats = await AppDatabase.instance.getAllChats();
      ref.read(chatListProvider.notifier).state = chats;
    }
  }

  /// Edit the last user message in the current transcript. Wired to the
  /// chip-row "Edit" action on an errored assistant bubble so the user
  /// can rewrite what they asked without opening the preceding bubble's
  /// menu manually.
  Future<void> _editLastUserMessage(List<ChatMessageUI> messages) async {
    Haptics.selection();
    final idx = messages.lastIndexWhere((m) => m.role == 'user');
    if (idx < 0) return;
    await _editMessage(messages[idx], idx);
  }

  void _cancelRun() {
    Haptics.medium();
    ref.read(agentSessionProvider.notifier).cancel();
  }

  void _shareMessage(String content) {
    SharePlus.instance.share(ShareParams(text: content));
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
                    params.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              if (isDangerous) ...[
                const SizedBox(height: 12),
                Text(
                  'This is a dangerous operation. Are you sure?',
                  style: TextStyle(
                    color: Colors.orange.shade300,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: alwaysAllow,
                onChanged: (v) =>
                    setDialogState(() => alwaysAllow = v ?? false),
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
                  ? FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                    )
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

  /// Throttled auto-scroll. Coalesces scroll requests during rapid streaming
  /// and respects user having scrolled up — only animates if already within
  /// 120px of the bottom, unless [force] is true (explicit FAB tap).
  bool _scrollScheduled = false;
  void _scrollToBottom({bool force = false}) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (!force && pos.maxScrollExtent - pos.pixels > 120) return;
      _scrollController.animateTo(
        pos.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Format a DateTime as a date separator label
  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(msgDay).inDays;
    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    return '${_monthName(dt.month)} ${dt.day}';
  }

  String _monthName(int month) => [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month];

  /// Check if two DateTimes are on the same day
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    final sessionState = ref.watch(agentSessionProvider);
    // Tablet + landscape phones: pin the chat list as a left rail so
    // users don't have to open the drawer on every switch. Threshold
    // picked so 600dp+ layouts (standard tablet breakpoint) get the
    // two-pane view; portrait phones stay single-pane.
    final width = MediaQuery.sizeOf(context).width;
    final twoPane = width >= 720;

    return Scaffold(
      appBar: AppBar(
        leading: twoPane
            ? null
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Open chat list',
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        title: _buildAppBarTitle(),
        centerTitle: !twoPane,
        actions: [
          if (sessionState.isRunning)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
              tooltip: 'Stop',
              onPressed: _cancelRun,
            ),
          // Compact token/speed chip. Rebuilds only when metrics tick
          // (≤5Hz during streaming), so it doesn't drag the app bar into
          // the chat-list's paint budget.
          const MetricsChip(),
          _buildModelSwitcher(),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => pushSlideRight(context, const SettingsScreen()),
          ),
        ],
      ),
      drawer: twoPane ? null : _buildChatDrawer(isDrawer: true),
      body: twoPane
          ? Row(
              children: [
                SizedBox(
                  width: 320,
                  child: Material(
                    elevation: 1,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerLow,
                    child: _buildChatDrawer(isDrawer: false),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildChatPane(messages, sessionState)),
              ],
            )
          : _buildChatPane(messages, sessionState),
    );
  }

  /// Close the drawer if one is actually open. In two-pane mode the chat
  /// list is a pinned rail — there's no drawer to pop, so this is a
  /// no-op. Without the guard, `Navigator.pop` would kick us back to the
  /// dev tab.
  void _closeDrawerIfOpen() {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
  }

  /// The "chat viewer" column. Extracted so the single-pane and two-pane
  /// layouts can share it without duplicating the composer + offline
  /// banner + scroll FAB tree.
  Widget _buildChatPane(
    List<ChatMessageUI> messages,
    AgentSessionState sessionState,
  ) {
    return Column(
        children: [
          // Offline banner
          Consumer(
            builder: (context, ref, _) {
              final isOnline = ref.watch(isOnlineProvider);
              if (isOnline) return const SizedBox.shrink();
              // Hoist colorScheme once so Flutter doesn't walk the
              // InheritedWidget chain for every child access.
              final cs = Theme.of(context).colorScheme;
              return MaterialBanner(
                backgroundColor: cs.errorContainer,
                content: Text(
                  'You are offline. Messages will be sent when connection is restored.',
                  style: TextStyle(color: cs.onErrorContainer),
                ),
                actions: [const SizedBox.shrink()],
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
              );
            },
          ),
          Expanded(
            child: Stack(
              children: [
                messages.isEmpty
                    ? _buildEmptyState(context)
                    : Builder(
                        builder: (context) {
                          final items = _buildInterleavedItems(messages);
                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              if (item is _DateSep) {
                                return DateSeparator(label: item.label);
                              }
                              final mi = item as _MsgItem;
                              return _buildMessageBubble(
                                mi.msg,
                                messages,
                                mi.index,
                              );
                            },
                          );
                        },
                      ),
                // Scroll-to-bottom FAB
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: ScrollToBottomFab(
                    visible: _showScrollFab,
                    onTap: () => _scrollToBottom(force: true),
                  ),
                ),
              ],
            ),
          ),
          InputBar(
            key: _inputBarKey,
            onSend: _sendMessage,
            isLoading: sessionState.isRunning,
            onCancel: sessionState.isRunning ? _cancelRun : null,
            enterToSend: _enterToSend,
            onDraftChanged: (text) {
              final chatId = ref.read(activeChatIdProvider);
              AppDatabase.instance.saveDraft(chatId, text);
            },
            onOpenPromptLibrary: () => _openPromptLibrary(),
          ),
        ],
      );
  }

  /// Pre-compute the interleaved list of date separators and messages.
  /// 2.5: Cached — only recomputed when message count changes.
  List<dynamic> _buildInterleavedItems(List<ChatMessageUI> messages) {
    // Hash includes count + last message content to detect streaming updates
    final contentHash = messages.isEmpty
        ? 0
        : Object.hash(
            messages.length,
            messages.last.content.length,
            messages.last.isStreaming,
          );
    if (_cachedInterleavedItems != null &&
        _cachedMessageCount == messages.length &&
        _cachedContentHash == contentHash) {
      return _cachedInterleavedItems!;
    }
    final items = <dynamic>[];
    DateTime? lastDate;
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.timestamp != null &&
          (lastDate == null || !_sameDay(lastDate, m.timestamp!))) {
        items.add(_DateSep(label: _dateLabel(m.timestamp!)));
        lastDate = m.timestamp;
      }
      items.add(_MsgItem(msg: m, index: i));
    }
    _cachedInterleavedItems = items;
    _cachedMessageCount = messages.length;
    _cachedContentHash = contentHash;
    return items;
  }

  /// Build a single message bubble (date separators handled in ListView).
  ///
  /// Perf: wrapped in a [RepaintBoundary] so streaming updates to the last
  /// message don't invalidate the paint layers of earlier bubbles. Also
  /// uses the message's own ID as a [ValueKey] so Flutter's element tree
  /// reconciles by identity (preserving [SlideInMessage] state correctly)
  /// rather than by index when the list grows.
  Widget _buildMessageBubble(
    ChatMessageUI msg,
    List<ChatMessageUI> messages,
    int msgIndex,
  ) {
    // Determine if next message is same role for grouping
    final isLastInGroup =
        msgIndex == messages.length - 1 ||
        messages[msgIndex + 1].role != msg.role;

    if (msg.role == 'tool') {
      return RepaintBoundary(
        key: ValueKey(msg.id),
        child: ToolResultCard(
          toolName: msg.toolName ?? 'unknown',
          result: msg.content,
          success: msg.toolSuccess,
        ),
      );
    }

    final isError =
        msg.role == 'assistant' &&
        msg.content.startsWith('Error:') &&
        msgIndex == messages.length - 1;

    return RepaintBoundary(
      key: ValueKey(msg.id),
      child: SlideInMessage(
        isActive: msg.isNew,
        child: Padding(
          padding: EdgeInsets.only(bottom: isLastInGroup ? 12.0 : 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MessageBubble(
                role: msg.role,
                content: msg.content,
                thinkingContent: msg.thinkingContent,
                isStreaming: msg.isStreaming,
                imagePaths: msg.imagePaths,
                timestamp: msg.formattedTimestamp,
                onLongPress: msg.role == 'user' && !msg.isStreaming
                    ? () => _showMessageActions(msg, msgIndex)
                    : null,
                isQueued: msg.status == 'queued',
              ),
              // Action buttons for messages
              if (msg.role == 'assistant' && !msg.isStreaming) ...[
                Padding(
                  padding: EdgeInsets.only(
                    left: 48,
                    bottom: isLastInGroup ? 8.0 : 2.0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _actionChip(
                        Icons.share_outlined,
                        'Share',
                        () => _shareMessage(msg.content),
                      ),
                      const SizedBox(width: 6),
                      _actionChip(
                        Icons.copy,
                        'Copy',
                        () => _copyMessage(msg.content),
                      ),
                      if (isError) ...[
                        const SizedBox(width: 6),
                        _actionChip(
                          Icons.refresh,
                          'Retry',
                          () => _retryErroredMessage(msg, msgIndex),
                        ),
                        const SizedBox(width: 6),
                        _actionChip(
                          Icons.edit_outlined,
                          'Edit last',
                          () => _editLastUserMessage(messages),
                        ),
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
                      _actionChip(
                        Icons.copy,
                        'Copy',
                        () => _copyMessage(msg.content),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        Haptics.light();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ), // 48dp min touch target
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
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
      case AgentSessionRunning(
        :final currentContent,
        :final currentThinking,
        :final toolResults,
      ):
        // Update streaming assistant content
        if (currentContent.isNotEmpty || currentThinking.isNotEmpty) {
          messages.add(
            ChatMessageUI(
              role: 'assistant',
              content: currentContent.isEmpty && currentThinking.isNotEmpty
                  ? '...'
                  : currentContent,
              thinkingContent: currentThinking.isNotEmpty
                  ? currentThinking
                  : null,
              isStreaming: true,
              timestamp: DateTime.now(),
              isNew: true,
            ),
          );
        }
        // Add tool results that aren't already shown
        final existingToolIds = messages
            .where((m) => m.role == 'tool' && m.toolCallId != null)
            .map((m) => m.toolCallId)
            .toSet();
        for (final tr in toolResults) {
          if (!existingToolIds.contains(tr.toolCallId)) {
            messages.add(
              ChatMessageUI(
                role: 'tool',
                content: tr.result.toDisplayString(),
                toolName: tr.toolName,
                toolSuccess: tr.result.success,
                toolCallId: tr.toolCallId,
                timestamp: DateTime.now(),
                isNew: true,
              ),
            );
            // Persist tool result
            _persistMessage(
              MessageEntry(
                id: _uuid.v4(),
                chatId: chatId,
                role: 'tool',
                content: tr.result.toDisplayString(),
                toolName: tr.toolName,
                toolSuccess: tr.result.success,
                toolCallId: tr.toolCallId,
              ),
            );
          }
        }
      case AgentSessionCompleted(
        :final content,
        :final thinkingContent,
        :final toolResults,
        :final wasCancelled,
      ):
        // Finalize assistant message
        if (content.isNotEmpty) {
          messages.add(
            ChatMessageUI(
              role: 'assistant',
              content: wasCancelled ? '$content\n\n⏹ Stopped' : content,
              thinkingContent: thinkingContent.isNotEmpty
                  ? thinkingContent
                  : null,
              timestamp: DateTime.now(),
              isNew: true,
            ),
          );
          // Persist assistant message
          _persistMessage(
            MessageEntry(
              id: _uuid.v4(),
              chatId: chatId,
              role: 'assistant',
              content: content,
            ),
          );
        }
        // Add any remaining tool results not yet shown
        final existingToolIds = messages
            .where((m) => m.role == 'tool' && m.toolCallId != null)
            .map((m) => m.toolCallId)
            .toSet();
        for (final tr in toolResults) {
          if (!existingToolIds.contains(tr.toolCallId)) {
            messages.add(
              ChatMessageUI(
                role: 'tool',
                content: tr.result.toDisplayString(),
                toolName: tr.toolName,
                toolSuccess: tr.result.success,
                toolCallId: tr.toolCallId,
                timestamp: DateTime.now(),
                isNew: true,
              ),
            );
            _persistMessage(
              MessageEntry(
                id: _uuid.v4(),
                chatId: chatId,
                role: 'tool',
                content: tr.result.toDisplayString(),
                toolName: tr.toolName,
                toolSuccess: tr.result.success,
                toolCallId: tr.toolCallId,
              ),
            );
          }
        }
        // Update chat metadata
        _updateChatMeta(chatId, messages.length);
        Haptics.light(); // done haptic
      case AgentSessionError(:final message):
        Haptics.heavy();
        final errorDbId = _uuid.v4();
        messages.add(
          ChatMessageUI(
            role: 'assistant',
            content: 'Error: $message',
            timestamp: DateTime.now(),
            isNew: true,
            isError: true,
            dbId: errorDbId,
          ),
        );
        _persistMessage(
          MessageEntry(
            id: errorDbId,
            chatId: chatId,
            role: 'assistant',
            content: 'Error: $message',
          ),
        );
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

  /// Whether we've already surfaced a persistence-failed banner for the
  /// current session. Avoids stacking snackbars on repeated failures.
  bool _persistenceWarned = false;

  /// Persist a message to the DB. Fire-and-forget per message, but errors
  /// get logged AND surface a single toast so the user knows their
  /// conversation is no longer being saved (instead of silent data loss).
  void _persistMessage(MessageEntry msg) {
    AppDatabase.instance.addMessage(msg.chatId, msg).catchError((e, st) {
      debugPrint('[chat] persist failed for ${msg.role}: $e\n$st');
      if (mounted && !_persistenceWarned) {
        _persistenceWarned = true;
        showKoloToast(
          context,
          "Couldn't save message to disk ($e)",
          kind: ToastKind.warning,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Dismiss',
            onPressed: () => _persistenceWarned = false,
          ),
        );
      }
    });
  }

  void _showChatMenu(ChatEntry chat) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                chat.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(chat.isPinned ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(ctx);
                _togglePin(chat);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Move to folder'),
              onTap: () {
                Navigator.pop(ctx);
                _moveChatToFolder(chat);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteChat(chat.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveChatToFolder(ChatEntry chat) async {
    final folders = ref.read(foldersProvider);
    final picked = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('No folder'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            const Divider(height: 1),
            for (final f in folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f.name),
                selected: chat.folderId == f.id,
                onTap: () => Navigator.pop(ctx, f.id),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New folder...'),
              onTap: () async {
                Navigator.pop(ctx);
                final newId = await _createFolder();
                if (newId != null) {
                  await FolderService.instance.assign(chat.id, newId);
                  ref.read(foldersProvider.notifier).reload();
                  _refreshChatList();
                }
              },
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await FolderService.instance.assign(chat.id, picked.isEmpty ? null : picked);
    _refreshChatList();
  }

  Future<String?> _createFolder() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true || ctl.text.trim().isEmpty) return null;
    final f = await FolderService.instance.create(name: ctl.text.trim());
    ref.read(foldersProvider.notifier).reload();
    return f.id;
  }

  Future<void> _renameOrDeleteFolder(FolderEntry f) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete folder'),
              subtitle: const Text('Chats inside are not deleted.'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') {
      final ctl = TextEditingController(text: f.name);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename folder'),
          content: TextField(controller: ctl, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (ok == true && ctl.text.trim().isNotEmpty) {
        await FolderService.instance.rename(f.id, ctl.text.trim());
        ref.read(foldersProvider.notifier).reload();
      }
    } else if (action == 'delete') {
      await FolderService.instance.delete(f.id);
      if (ref.read(activeFolderIdProvider) == f.id) {
        ref.read(activeFolderIdProvider.notifier).state = null;
      }
      ref.read(foldersProvider.notifier).reload();
      _refreshChatList();
    }
  }

  /// Called when connectivity flips back to online. Picks up queued
  /// messages for the CURRENTLY active chat + fires them through the
  /// normal send path. Messages in other chats are left until the user
  /// opens that chat (simpler than resuming in background; keeps tool
  /// permission prompts tied to a visible chat).
  Future<void> _drainOutbox() async {
    final currentChatId = ref.read(activeChatIdProvider);
    final items = await OutboxService.instance.all();
    final mine = items.where((i) => i.chatId == currentChatId).toList();
    if (mine.isEmpty) return;
    // Process one at a time so tool-prompt dialogs don't stack.
    for (final item in mine) {
      await OutboxService.instance.remove(item.messageDbId);
      // Clear the queued status on the DB row so the re-fire path can
      // add a fresh message without a status conflict. Easiest: delete
      // the old queued row, then re-send as a new message.
      await AppDatabase.instance.deleteMessage(item.messageDbId);
      // Also drop the queued bubble from the UI list so the re-sent
      // message lands in its place.
      final messages =
          List<ChatMessageUI>.from(ref.read(chatMessagesProvider));
      messages.removeWhere((m) => m.dbId == item.messageDbId);
      ref.read(chatMessagesProvider.notifier).state = messages;
      await _sendMessage(item.text);
      // Stop if we went offline again mid-drain.
      if (!ref.read(isOnlineProvider)) break;
    }
    if (mounted) {
      showKoloToast(context, 'Reconnected — queued messages sent.');
    }
  }

  Future<void> _refreshChatList() async {
    final chats = await AppDatabase.instance.getAllChats();
    ref.read(chatListProvider.notifier).state = chats;
  }

  /// Show the prompt library bottom sheet. Resolved prompts are piped
  /// straight into the composer so the user can tweak before sending.
  void _openPromptLibrary() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => PromptLibrarySheet(
        onPromptResolved: (text) {
          _inputBarKey.currentState?.insertText(text);
        },
      ),
    );
  }

  /// Open the global-search modal. Tapping a hit closes the screen,
  /// switches to the containing chat, and (best-effort) scrolls to the
  /// matching message.
  void _openGlobalSearch() {
    pushSlideRight(
      context,
      ChatSearchScreen(
        onHitTapped: (chatId, messageId) async {
          final chats = ref.read(chatListProvider);
          final target = chats.where((c) => c.id == chatId).firstOrNull;
          if (target == null) return;
          await _loadChat(target);
          if (!mounted) return;
          // Scroll to the matching bubble after a frame so the list has
          // time to lay out. ListView.builder doesn't give us per-item
          // positions, so approximate: place the target at 70% of the
          // way through the visible viewport, bounded by maxScrollExtent.
          // Feels better than a fixed 96px/row heuristic because it
          // scales with actual content rather than assumed bubble size.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final messages = ref.read(chatMessagesProvider);
            final i = messages.indexWhere((m) => m.dbId == messageId);
            if (i < 0 || !_scrollController.hasClients) return;
            final position = _scrollController.position;
            final fraction = i / messages.length;
            final target = (fraction * position.maxScrollExtent).clamp(
              0.0,
              position.maxScrollExtent,
            );
            _scrollController.animateTo(
              target,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        },
      ),
    );
  }

  /// Bottom-sheet menu surfaced when the user long-presses their own
  /// message. Offers edit + copy. Wired via MessageBubble.onLongPress so
  /// the gesture stays inside a child widget and doesn't fight with the
  /// bubble's own selectable markdown.
  void _showMessageActions(ChatMessageUI msg, int index) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit message'),
              subtitle: const Text(
                'Rewrite this message — subsequent replies are discarded.',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _editMessage(msg, index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: msg.content));
                if (ctx.mounted) Navigator.pop(ctx);
                Haptics.selection();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMessage(ChatMessageUI msg, int index) async {
    final controller = TextEditingController(text: msg.content);
    final newText = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          minLines: 2,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save & resend'),
          ),
        ],
      ),
    );
    if (newText == null || newText.isEmpty || newText == msg.content) return;

    // Truncate UI list + DB at this index, then send as a new message.
    final chatId = ref.read(activeChatIdProvider);
    final current = List<ChatMessageUI>.from(ref.read(chatMessagesProvider));
    if (index >= current.length) return;
    final keep = current.sublist(0, index);
    ref.read(chatMessagesProvider.notifier).state = keep;

    // Delete everything in the DB from this message onward. Two-step so
    // same-millisecond neighbours don't get clobbered: drop messages
    // strictly after the target's timestamp, then delete the target by
    // its own id.
    if (msg.dbId != null) {
      final db = AppDatabase.instance;
      final storedMessages = await db.getMessages(chatId);
      final target =
          storedMessages.where((m) => m.id == msg.dbId).firstOrNull;
      if (target != null) {
        await db.deleteMessagesAfter(chatId, target.createdAt);
      }
      await db.deleteMessage(msg.dbId!);
    }

    // Sync the agent session's in-memory conversation with the UI.
    final session = ref.read(agentSessionProvider.notifier).session;
    session?.conversationManager.truncateFrom(index);

    // Now run the normal send flow with the edited text.
    await _sendMessage(newText);
  }

  Future<void> _retryErroredMessage(ChatMessageUI msg, int index) async {
    // Drop the error bubble from the UI + DB.
    final current = List<ChatMessageUI>.from(ref.read(chatMessagesProvider));
    if (index < current.length) {
      current.removeAt(index);
      ref.read(chatMessagesProvider.notifier).state = current;
    }
    if (msg.dbId != null) {
      await AppDatabase.instance.deleteMessage(msg.dbId!);
    }
    // Kick the agent's retry path — it strips trailing assistant/tool
    // messages and reruns the loop over what remains.
    await ref.read(agentSessionProvider.notifier).retryLast();
    if (!mounted) return;
    _scrollToBottom();
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
    final provider = providers.firstWhere(
      (p) => p.isActive,
      orElse: () => providers.first,
    );
    final models = provider.models;
    final activeModel = provider.activeModel;
    if (models.length <= 1) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy, size: 18, color: cs.primary),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 18, color: cs.onSurface),
        ],
      ),
      tooltip: 'Switch model',
      onSelected: (modelId) {
        Haptics.selection();
        ref
            .read(providersProvider.notifier)
            .setActiveModel(provider.id, modelId);
      },
      itemBuilder: (ctx) => models
          .map(
            (m) => PopupMenuItem(
              value: m.modelId,
              child: Row(
                children: [
                  if (m.modelId == activeModel?.modelId)
                    Icon(
                      Icons.check,
                      size: 16,
                      color: Theme.of(ctx).colorScheme.primary,
                    )
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.displayName ?? m.modelId,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildChatDrawer({required bool isDrawer}) {
    final chats = ref.watch(chatListProvider);
    final activeId = ref.watch(activeChatIdProvider);
    final cs = Theme.of(context).colorScheme;

    final folders = ref.watch(foldersProvider);
    final activeFolderId = ref.watch(activeFolderIdProvider);

    // Filter by folder first, then by search query, then sort: pinned
    // first, then by updatedAt.
    Iterable<ChatEntry> visible = chats;
    if (activeFolderId != null) {
      visible = visible.where((c) => c.folderId == activeFolderId);
    }
    if (_searchQuery.isNotEmpty) {
      final lowerQuery = _searchQuery.toLowerCase();
      visible = visible.where(
        (c) => c.title.toLowerCase().contains(lowerQuery),
      );
    }
    final filteredChats = visible.toList();
    filteredChats.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header with brand gradient
            Semantics(
              header: true,
              label: 'Kolo AI Agent',
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.15),
                      cs.primaryContainer.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.smart_toy, color: cs.primary, size: 28),
                    const SizedBox(width: 10),
                    Text(
                      'Kolo AI Agent',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        _closeDrawerIfOpen();
                        _startNewChat();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('New Chat'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Search all chats',
                    icon: const Icon(Icons.search),
                    onPressed: () {
                      _closeDrawerIfOpen();
                      _openGlobalSearch();
                    },
                  ),
                ],
              ),
            ),
            // Search bar
            if (chats.length > 3) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search chats...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(height: 4),
            ],
            // Folder filter strip — only renders when the user has folders
            // OR when we want to expose the "+ New folder" affordance
            // next to other chats-management controls. Kept hidden until
            // the first folder is created to avoid visual noise.
            if (folders.isNotEmpty)
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          _FolderChip(
                            label: 'All',
                            selected: activeFolderId == null,
                            onTap: () => ref
                                .read(activeFolderIdProvider.notifier)
                                .state = null,
                          ),
                          for (final f in folders)
                            _FolderChip(
                              label: f.name,
                              selected: activeFolderId == f.id,
                              onTap: () => ref
                                  .read(activeFolderIdProvider.notifier)
                                  .state = f.id,
                              onLongPress: () => _renameOrDeleteFolder(f),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.create_new_folder_outlined),
                      tooltip: 'New folder',
                      visualDensity: VisualDensity.compact,
                      onPressed: _createFolder,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: filteredChats.isEmpty
                  ? Center(
                      child: Text(
                        'No chats found',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredChats.length,
                      itemBuilder: (ctx, i) {
                        final chat = filteredChats[i];
                        final isActive = chat.id == activeId;
                        return Dismissible(
                          key: ValueKey(chat.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red,
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (_) async => true,
                          onDismissed: (_) => _deleteChat(chat.id),
                          child: ListTile(
                            selected: isActive,
                            selectedTileColor: cs.primary.withValues(
                              alpha: 0.1,
                            ),
                            leading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  chat.isPinned
                                      ? Icons.push_pin
                                      : Icons.chat_bubble_outline,
                                  size: 20,
                                  color: chat.isPinned ? cs.primary : null,
                                ),
                                if (chat.unreadCount > 0)
                                  Positioned(
                                    right: -4,
                                    top: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: cs.error,
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 12,
                                        minHeight: 12,
                                      ),
                                      child: Text(
                                        chat.unreadCount > 99
                                            ? '99+'
                                            : '${chat.unreadCount}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
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
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: chat.unreadCount > 0
                                    ? cs.onSurface
                                    : cs.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                            subtitle: Text(
                              '${chat.messageCount} msgs · ${_timeAgo(chat.updatedAt)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              tooltip: 'Delete chat',
                              onPressed: () => _deleteChat(chat.id),
                            ),
                            onLongPress: () => _showChatMenu(chat),
                            onTap: () {
                              Haptics.selection();
                              _closeDrawerIfOpen();
                              _loadChat(chat);
                              _markRead(chat.id);
                            },
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Custom Instructions'),
              onTap: () {
                _closeDrawerIfOpen();
                _showCustomInstructionsDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.build_outlined),
              title: const Text('Tools & Permissions'),
              subtitle: Text(
                '${ref.read(toolRegistryProvider).all.length} tools',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
              onTap: () {
                _closeDrawerIfOpen();
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
    final saved =
        await AppDatabase.instance.getSetting('custom_instructions') ?? '';
    if (!mounted) return;
    final controller = TextEditingController(
      text: ref.read(customInstructionsProvider).isEmpty
          ? saved
          : ref.read(customInstructionsProvider),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Instructions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add instructions that modify the AI\'s behavior across all chats.',
              style: TextStyle(
                color: Theme.of(
                  ctx,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText:
                    'e.g. Always respond in French. Prefer concise answers.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      ref.read(customInstructionsProvider.notifier).state = result;
      await AppDatabase.instance.saveSetting('custom_instructions', result);
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    // Read theme once — avoids multiple InheritedWidget lookups across the
    // ~100 lines of empty-state widget tree below.
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final toolCount = ref.watch(toolRegistryProvider).all.length;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BreathingIcon(color: cs.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(
              'Kolo AI Agent',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$toolCount tools ready',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 22),
            // Tip card — quick overview of what this app can do.
            Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ChatTipLine(
                    icon: Icons.chat_bubble_outline,
                    text: 'Ask anything, attach images or files',
                    color: cs.primary,
                  ),
                  const SizedBox(height: 8),
                  _ChatTipLine(
                    icon: Icons.auto_awesome_outlined,
                    text: 'The agent runs tools on your behalf',
                    color: cs.primary,
                  ),
                  const SizedBox(height: 8),
                  _ChatTipLine(
                    icon: Icons.mic_none_outlined,
                    text: 'Tap the mic to dictate — hands-free',
                    color: cs.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Try one of these:',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _suggestionChip(
                    Icons.search,
                    'Search the web',
                    'Search the web for ',
                  ),
                  _suggestionChip(Icons.phone_android, 'Open an app', 'Open '),
                  _suggestionChip(
                    Icons.screenshot,
                    'Take a screenshot',
                    'Take a screenshot',
                  ),
                  _suggestionChip(Icons.calculate, 'Calculate', 'Calculate '),
                  _suggestionChip(
                    Icons.location_on,
                    'Find nearby',
                    'What\'s near me?',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () => pushSlideRight(context, const SettingsScreen()),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Configure provider'),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurface.withValues(alpha: 0.7),
              ),
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
        _inputBarKey.currentState?.setText(prefix);
        _inputBarKey.currentState?.focus();
      },
    );
  }
}

/// One row in the chat empty-state tip box. Fully const-constructed so
/// nothing is allocated on rebuild while the user looks at the welcome.
class _ChatTipLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _ChatTipLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: cs.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}

/// Breathing scale animation for the empty-state icon
// _BreathingIcon moved to breathing_icon.dart (public as BreathingIcon).

/// Simple data class for date separators in the interleaved list
class _DateSep {
  final String label;
  const _DateSep({required this.label});
}

/// Wrapper to carry the original index alongside the message
class _MsgItem {
  final ChatMessageUI msg;
  final int index;
  const _MsgItem({required this.msg, required this.index});
}

// ChatMessageUI moved to chat_message_ui.dart — imported above.

/// Horizontal folder filter pill used in the chat drawer. Uses a bare
/// InkWell rather than ChoiceChip because ChoiceChip's internal tap
/// recogniser eats long-press on Android, hiding the rename/delete menu.
class _FolderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FolderChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: Material(
        color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? cs.onPrimaryContainer : cs.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
