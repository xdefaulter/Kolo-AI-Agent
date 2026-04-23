import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../api/provider.dart';

/// Max messages stored per chat to prevent unbounded growth
const int kMaxMessagesPerChat = 500;

/// Schema version for JSON storage migration
const int kSchemaVersion = 1;

/// File-based + SharedPreferences storage for app data
class AppDatabase {
  static AppDatabase? _instance;
  static AppDatabase get instance => _instance ??= AppDatabase._();

  AppDatabase._();

  /// Simple async write lock to prevent concurrent file writes
  final _writeLock = _AsyncLock();

  String? _dbPath;

  Future<String> get _path async {
    _dbPath ??= (await getApplicationDocumentsDirectory()).path;
    return _dbPath!;
  }

  // ---- Chats ----

  Future<List<ChatEntry>> getAllChats() async {
    final path = await _path;
    final file = File('$path/chats.json');
    if (!await file.exists()) return [];
    final json = await file.readAsString();
    final decoded = jsonDecode(json);
    // Support both old (bare list) and new (versioned object) formats
    final List list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map && decoded['chats'] is List) {
      list = decoded['chats'] as List;
    } else {
      return [];
    }
    return list.map((e) => ChatEntry.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveChat(ChatEntry chat) async {
    final chats = await getAllChats();
    final idx = chats.indexWhere((c) => c.id == chat.id);
    if (idx >= 0) {
      chats[idx] = chat;
    } else {
      chats.insert(0, chat);
    }
    await _writeChats(chats);
  }

  Future<void> deleteChat(String id) async {
    var chats = await getAllChats();
    chats.removeWhere((c) => c.id == id);
    await _writeChats(chats);
    final path = await _path;
    final file = File('$path/messages_$id.json');
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteAllChats() async {
    final chats = await getAllChats();
    final path = await _path;
    for (final chat in chats) {
      final file = File('$path/messages_${chat.id}.json');
      if (await file.exists()) await file.delete();
    }
    await _writeChats([]);
  }

  Future<void> _writeChats(List<ChatEntry> chats) async {
    await _writeLock.run(() async {
      final path = await _path;
      final file = File('$path/chats.json');
      final data = {'schemaVersion': kSchemaVersion, 'chats': chats.map((c) => c.toMap()).toList()};
      await file.writeAsString(jsonEncode(data));
    });
  }

  // ---- Messages ----

  Future<List<MessageEntry>> getMessages(String chatId) async {
    final path = await _path;
    final file = File('$path/messages_$chatId.json');
    if (!await file.exists()) return [];
    final json = await file.readAsString();
    final list = jsonDecode(json) as List;
    return list.map((e) => MessageEntry.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> addMessage(String chatId, MessageEntry msg) async {
    var messages = await getMessages(chatId);
    messages.add(msg);
    // Enforce message limit — drop oldest messages beyond cap
    if (messages.length > kMaxMessagesPerChat) {
      messages = messages.sublist(messages.length - kMaxMessagesPerChat);
    }
    await _writeMessages(chatId, messages);
  }

  Future<void> _writeMessages(String chatId, List<MessageEntry> messages) async {
    await _writeLock.run(() async {
      final path = await _path;
      final file = File('$path/messages_$chatId.json');
      await file.writeAsString(jsonEncode(messages.map((m) => m.toMap()).toList()));
    });
  }

  // ---- Providers (with models) ----

  Future<List<ProviderConfig>> getAllProviders() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('kolo_providers_v2');
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => ProviderConfig.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveProvider(ProviderConfig provider) async {
    final providers = await getAllProviders();
    final idx = providers.indexWhere((p) => p.id == provider.id);
    if (idx >= 0) {
      providers[idx] = provider.copyWith(); // trigger updatedAt
    } else {
      providers.add(provider);
    }
    await _writeProviders(providers);
  }

  /// 3.2: Bulk-write all providers in one SharedPreferences call
  Future<void> writeAllProviders(List<ProviderConfig> providers) async =>
      _writeProviders(providers);

  Future<void> deleteProvider(String id) async {
    var providers = await getAllProviders();
    providers.removeWhere((p) => p.id == id);
    await _writeProviders(providers);
  }

  Future<void> _writeProviders(List<ProviderConfig> providers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kolo_providers_v2', jsonEncode(providers.map((p) => p.toMap()).toList()));
  }

  Future<ProviderConfig?> getActiveProvider() async {
    final providers = await getAllProviders();
    return providers.where((p) => p.isActive).firstOrNull ??
        (providers.isNotEmpty ? providers.first : null);
  }

  /// 4.2: Fetch models from a provider's /models endpoint.
  /// NOTE: This makes network calls, which violates separation of concerns.
  /// Kept here temporarily for backward compat; callers should migrate to
  /// a dedicated ModelFetcher service.
  Future<List<ModelConfig>> fetchModels(ProviderConfig provider) async {
    if (!provider.canFetchModels) return [];

    try {
      final dio = Dio(BaseOptions(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (status) => status != null && status < 400,
      ));
      final headers = <String, dynamic>{
        'Content-Type': 'application/json',
        ...provider.customHeaders,
      };
      if (provider.apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${provider.apiKey}';
      }
      // Re-attach auth on redirects (Dio strips Authorization on cross-origin redirects)
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (provider.apiKey.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer ${provider.apiKey}';
          }
          handler.next(options);
        },
      ));

      final response = await dio.get(
        provider.effectiveModelsUrl,
        options: Options(headers: headers),
      );

      final data = response.data as Map<String, dynamic>;
      final modelList = data['data'] as List<dynamic>? ?? [];

      return modelList.map((m) {
        final map = m as Map<String, dynamic>;
        final id = map['id'] as String? ?? 'unknown';
        return ModelConfig(
          modelId: id,
          displayName: id,
          maxTokens: 4096,
          isCustom: false,
          description: map['description'] as String?,
        );
      }).toList();
    } catch (e) {
      // silently fail — caller can handle
      return [];
    }
  }

  // ---- Active Model Selection (per chat) ----

  Future<String?> getActiveModelId(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('kolo_active_model_$providerId');
  }

  Future<void> setActiveModelId(String providerId, String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kolo_active_model_$providerId', modelId);
  }

  // ---- Settings ----

  Future<String?> getSetting(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('kolo_setting_$key');
  }

  Future<void> saveSetting(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kolo_setting_$key', value);
  }

  // ---- Drafts ----

  Future<String?> getDraft(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('kolo_draft_$chatId');
  }

  Future<void> saveDraft(String chatId, String text) async {
    final prefs = await SharedPreferences.getInstance();
    if (text.isEmpty) {
      await prefs.remove('kolo_draft_$chatId');
    } else {
      await prefs.setString('kolo_draft_$chatId', text);
    }
  }
}

class ChatEntry {
  final String id;
  String title;
  String? providerId;
  String? modelId;
  DateTime createdAt;
  DateTime updatedAt;
  int messageCount;
  bool isPinned;
  int unreadCount;

  ChatEntry({
    required this.id,
    this.title = 'New Chat',
    this.providerId,
    this.modelId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.messageCount = 0,
    this.isPinned = false,
    this.unreadCount = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'providerId': providerId,
        'modelId': modelId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messageCount': messageCount,
        'isPinned': isPinned,
        'unreadCount': unreadCount,
      };

  factory ChatEntry.fromMap(Map<String, dynamic> m) => ChatEntry(
        id: m['id'] as String,
        title: m['title'] as String? ?? 'New Chat',
        providerId: m['providerId'] as String?,
        modelId: m['modelId'] as String?,
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
        messageCount: m['messageCount'] as int? ?? 0,
        isPinned: m['isPinned'] as bool? ?? false,
        unreadCount: m['unreadCount'] as int? ?? 0,
      );
}

class MessageEntry {
  final String id;
  final String chatId;
  final String role;
  final String content;
  final String? toolCallId;
  final String? toolName;
  final bool? toolSuccess;
  final List<Map<String, dynamic>>? toolCalls; // for assistant messages with tool_calls
  final DateTime createdAt;

  MessageEntry({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolName,
    this.toolSuccess,
    this.toolCalls,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'chatId': chatId,
        'role': role,
        'content': content,
        'toolCallId': toolCallId,
        'toolName': toolName,
        'toolSuccess': toolSuccess,
        'toolCalls': toolCalls,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MessageEntry.fromMap(Map<String, dynamic> m) => MessageEntry(
        id: m['id'] as String,
        chatId: m['chatId'] as String,
        role: m['role'] as String,
        content: m['content'] as String,
        toolCallId: m['toolCallId'] as String?,
        toolName: m['toolName'] as String?,
        toolSuccess: m['toolSuccess'] as bool?,
        toolCalls: (m['toolCalls'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        createdAt: DateTime.parse(m['createdAt'] as String),
      );
}

/// Simple async lock to serialize file writes
class _AsyncLock {
  Completer<void>? _completer;

  Future<T> run<T>(Future<T> Function() action) async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
    try {
      return await action();
    } finally {
      final c = _completer!;
      _completer = null;
      c.complete();
    }
  }
}