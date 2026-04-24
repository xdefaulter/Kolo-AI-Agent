import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../api/provider.dart';
import '../api/model_fetcher.dart';
import '../tools/custom_tool_def.dart';

/// Max messages stored per chat to prevent unbounded growth. Enforced
/// lazily via [AppDatabase._trimChatIfNeeded] after inserts.
const int kMaxMessagesPerChat = 500;

/// Current app-level schema version. Bumping this triggers any
/// registered pre-DB migrations (rarely needed now that structured data
/// lives in SQLite). SQLite has its own `user_version` that tracks DDL
/// migrations independently — see [_dbSchemaVersion].
const int kSchemaVersion = 2;

const String _kSchemaVersionPrefKey = 'kolo_schema_version';
const String _kJsonImportedPrefKey = 'kolo_sqlite_imported_from_json_v1';

typedef Migration =
    Future<void> Function(String dataDir, SharedPreferences prefs);

/// SQLite schema version. Add a new branch to [_onUpgrade] whenever you
/// raise this so existing installs run the new DDL.
const int _dbSchemaVersion = 1;

/// Single-process SQLite backend for structured app data (chats,
/// messages, memories, folders, prompt templates). Simple key/value data
/// (settings, drafts, custom tools, provider configs, API keys) still
/// lives in SharedPreferences + flutter_secure_storage — moving them
/// would be churn with no payoff.
///
/// On first launch after upgrade, [_importLegacyJsonIfNeeded] reads any
/// existing `chats.json` + `messages_*.json` files and inserts them into
/// SQLite. The JSON files are left in place as a rollback safety net;
/// subsequent launches skip re-import via [_kJsonImportedPrefKey].
class AppDatabase {
  static AppDatabase? _instance;
  static AppDatabase get instance => _instance ??= AppDatabase._();

  AppDatabase._();

  /// Test hook — lets widget tests reset the singleton between cases.
  @visibleForTesting
  static void resetForTest() {
    _instance?._db?.close();
    _instance = null;
  }

  Database? _db;
  Completer<void>? _initCompleter;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static final Map<int, Migration> _migrations = {
    // v1: JSON-only baseline. No migration.
    // v2: JSON -> SQLite (imported lazily by _importLegacyJsonIfNeeded).
  };

  bool _initialized = false;

  /// Whether the opened SQLite build includes the FTS5 extension. Android's
  /// system SQLite historically omits it, so we detect at CREATE time and
  /// fall back to LIKE-based search when missing. Set by [_onCreate] and
  /// [_onOpen]; read by [searchMessages] + [recallMemories].
  bool _ftsEnabled = false;

  /// Idempotent + safe to call from multiple places (main() does it
  /// eagerly, every getter awaits it). First call does the work; all
  /// concurrent callers wait on the same completer.
  Future<void> initialize() async {
    if (_initialized) return;
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    _initCompleter = Completer<void>();
    try {
      await _doInitialize();
      _initialized = true;
      _initCompleter!.complete();
    } catch (e, st) {
      debugPrint('[db] init failed: $e\n$st');
      _initCompleter!.completeError(e, st);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<void> _doInitialize() async {
    final prefs = await SharedPreferences.getInstance();
    final dataDir = await _documentsPath();

    // Run any pending KV-level migrations first — these may touch
    // SharedPreferences or on-disk JSON before SQLite takes over.
    final current = prefs.getInt(_kSchemaVersionPrefKey) ?? 0;
    if (current < kSchemaVersion) {
      for (var v = current + 1; v <= kSchemaVersion; v++) {
        final m = _migrations[v];
        if (m != null) {
          debugPrint('[db] Running KV migration to v$v');
          try {
            await m(dataDir, prefs);
          } catch (e, st) {
            debugPrint('[db] KV migration v$v failed: $e\n$st');
          }
        }
        await prefs.setInt(_kSchemaVersionPrefKey, v);
      }
    }

    _db = await _openDatabase(dataDir);
    await _importLegacyJsonIfNeeded(dataDir, prefs);
  }

  Future<Database> _openDatabase(String dataDir) async {
    final dbPath = p.join(dataDir, 'kolo.db');
    // sqflite uses a native impl on Android/iOS. For desktop + widget
    // tests, route through sqflite_common_ffi.
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      return databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: _dbSchemaVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          onConfigure: _onConfigure,
          onOpen: _onOpen,
        ),
      );
    }
    return openDatabase(
      dbPath,
      version: _dbSchemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
      onOpen: _onOpen,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Probe whether the underlying SQLite build supports FTS5. Android's
  /// system SQLite often omits it; desktop + test (sqlite3_flutter_libs
  /// via ffi) typically includes it. We record the result so search
  /// paths can degrade gracefully instead of throwing on every query.
  Future<void> _onOpen(Database db) async {
    try {
      await db.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS _fts_probe USING fts5(c)",
      );
      await db.execute('DROP TABLE IF EXISTS _fts_probe');
      _ftsEnabled = true;
    } catch (_) {
      _ftsEnabled = false;
      debugPrint(
        '[db] FTS5 unavailable on this SQLite build — falling back to LIKE search',
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER,
        sort_index INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE chats (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        provider_id TEXT,
        model_id TEXT,
        folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        message_count INTEGER NOT NULL DEFAULT 0,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        unread_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('CREATE INDEX idx_chats_updated ON chats(updated_at DESC)');
    batch.execute('CREATE INDEX idx_chats_folder ON chats(folder_id)');

    batch.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        tool_call_id TEXT,
        tool_name TEXT,
        tool_success INTEGER,
        tool_calls_json TEXT,
        status TEXT,
        error TEXT,
        created_at INTEGER NOT NULL,
        edited_at INTEGER
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_messages_chat_created ON messages(chat_id, created_at)',
    );

    batch.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        source_chat_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_used_at INTEGER NOT NULL,
        use_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_memories_last_used ON memories(last_used_at DESC)',
    );

    batch.execute('''
      CREATE TABLE prompt_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        body TEXT NOT NULL,
        tags TEXT,
        use_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await batch.commit(noResult: true);

    // FTS5 is a best-effort add-on. Android's system SQLite often omits
    // it, so creating these virtual tables + triggers may fail. We try
    // each block separately so core tables are already committed when
    // we get here; a failure here just disables full-text search.
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE messages_fts USING fts5(
          content,
          chat_id UNINDEXED,
          message_id UNINDEXED,
          tokenize='porter'
        )
      ''');
      await db.execute('''
        CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
          INSERT INTO messages_fts(rowid, content, chat_id, message_id)
          VALUES (new.rowid, new.content, new.chat_id, new.id);
        END
      ''');
      await db.execute('''
        CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
          DELETE FROM messages_fts WHERE rowid = old.rowid;
        END
      ''');
      await db.execute('''
        CREATE TRIGGER messages_au AFTER UPDATE OF content ON messages BEGIN
          UPDATE messages_fts SET content = new.content WHERE rowid = old.rowid;
        END
      ''');
      _ftsEnabled = true;
    } catch (e) {
      debugPrint('[db] messages FTS5 unavailable: $e');
    }
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE memories_fts USING fts5(
          content,
          memory_id UNINDEXED,
          tokenize='porter'
        )
      ''');
      await db.execute('''
        CREATE TRIGGER memories_ai AFTER INSERT ON memories BEGIN
          INSERT INTO memories_fts(rowid, content, memory_id)
          VALUES (new.rowid, new.content, new.id);
        END
      ''');
      await db.execute('''
        CREATE TRIGGER memories_ad AFTER DELETE ON memories BEGIN
          DELETE FROM memories_fts WHERE rowid = old.rowid;
        END
      ''');
      await db.execute('''
        CREATE TRIGGER memories_au AFTER UPDATE OF content ON memories BEGIN
          UPDATE memories_fts SET content = new.content WHERE rowid = old.rowid;
        END
      ''');
    } catch (e) {
      debugPrint('[db] memories FTS5 unavailable: $e');
    }
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // Placeholder — current version is 1. Future additive migrations go
    // here, one branch per new version, forward-only.
  }

  /// Read `chats.json` + per-chat message files and insert them into
  /// SQLite on first SQLite launch. JSON files are left on disk so a
  /// downgrade is still possible.
  Future<void> _importLegacyJsonIfNeeded(
    String dataDir,
    SharedPreferences prefs,
  ) async {
    if (prefs.getBool(_kJsonImportedPrefKey) ?? false) return;

    final chatsFile = File(p.join(dataDir, 'chats.json'));
    if (!await chatsFile.exists()) {
      await prefs.setBool(_kJsonImportedPrefKey, true);
      return;
    }
    try {
      final raw = await chatsFile.readAsString();
      final decoded = jsonDecode(raw);
      final List<dynamic> chatsList;
      if (decoded is List) {
        chatsList = decoded;
      } else if (decoded is Map && decoded['chats'] is List) {
        chatsList = decoded['chats'] as List;
      } else {
        chatsList = const [];
      }
      debugPrint('[db] Importing ${chatsList.length} chats from JSON...');
      await _db!.transaction((txn) async {
        for (final chatMap in chatsList) {
          if (chatMap is! Map<String, dynamic>) continue;
          final chat = ChatEntry.fromMap(chatMap);
          await txn.insert(
            'chats',
            _chatToRow(chat),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          final msgFile = File(p.join(dataDir, 'messages_${chat.id}.json'));
          if (!await msgFile.exists()) continue;
          try {
            final msgRaw = await msgFile.readAsString();
            if (msgRaw.trim().isEmpty) continue;
            final msgDecoded = jsonDecode(msgRaw);
            final List<dynamic> list;
            if (msgDecoded is List) {
              list = msgDecoded;
            } else if (msgDecoded is Map && msgDecoded['messages'] is List) {
              list = msgDecoded['messages'] as List;
            } else {
              list = const [];
            }
            for (final m in list) {
              if (m is! Map<String, dynamic>) continue;
              try {
                final entry = MessageEntry.fromMap(m);
                await txn.insert(
                  'messages',
                  _messageToRow(entry),
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
              } catch (_) {
                // Skip malformed entries — don't fail the whole import.
              }
            }
          } catch (e) {
            debugPrint('[db] skip messages for ${chat.id}: $e');
          }
        }
      });
      await prefs.setBool(_kJsonImportedPrefKey, true);
      debugPrint('[db] JSON import complete');
    } catch (e, st) {
      debugPrint('[db] JSON import failed: $e\n$st');
      // Do not mark as imported — we'll retry next launch.
    }
  }

  Future<String> _documentsPath() async =>
      (await getApplicationDocumentsDirectory()).path;

  Future<Database> get _database async {
    if (!_initialized) await initialize();
    return _db!;
  }

  // ---------------- Chats ----------------

  Future<List<ChatEntry>> getAllChats() async {
    final db = await _database;
    final rows = await db.query(
      'chats',
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return rows.map(_rowToChat).toList();
  }

  Future<void> saveChat(ChatEntry chat) async {
    final db = await _database;
    await db.insert(
      'chats',
      _chatToRow(chat),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteChat(String id) async {
    final db = await _database;
    // ON DELETE CASCADE on messages handles message cleanup.
    await db.delete('chats', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllChats() async {
    final db = await _database;
    await db.delete('chats');
  }

  Future<void> moveChatToFolder(String chatId, String? folderId) async {
    final db = await _database;
    await db.update(
      'chats',
      {'folder_id': folderId},
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  // ---------------- Messages ----------------

  Future<List<MessageEntry>> getMessages(String chatId) async {
    final db = await _database;
    final rows = await db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at ASC, rowid ASC',
    );
    return rows.map(_rowToMessage).toList();
  }

  Future<void> addMessage(String chatId, MessageEntry msg) async {
    final db = await _database;
    await db.insert(
      'messages',
      _messageToRow(msg),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Bump message_count + trim oldest if we cross the cap. Cheap to
    // do inline; a single SELECT COUNT on indexed rows is sub-ms.
    await _trimChatIfNeeded(db, chatId);
  }

  Future<void> updateMessage(MessageEntry msg) async {
    final db = await _database;
    await db.update(
      'messages',
      _messageToRow(msg),
      where: 'id = ?',
      whereArgs: [msg.id],
    );
  }

  Future<void> deleteMessage(String id) async {
    final db = await _database;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete every message in [chatId] whose createdAt is strictly greater
  /// than [cutoff]. Used by edit/retry flows to roll back to a point in
  /// the transcript.
  Future<void> deleteMessagesAfter(String chatId, DateTime cutoff) async {
    final db = await _database;
    await db.delete(
      'messages',
      where: 'chat_id = ? AND created_at > ?',
      whereArgs: [chatId, cutoff.millisecondsSinceEpoch],
    );
  }

  /// Full-text search across all messages (or within a single chat if
  /// [chatId] is set). Returns at most [limit] hits, newest first.
  ///
  /// Uses FTS5 when available, otherwise falls back to a case-insensitive
  /// LIKE scan over the messages table. The LIKE path is O(n) but fine
  /// for the sizes we care about (tens of thousands of messages scan
  /// in a few ms on mobile SQLite), and avoids shipping a custom SQLite
  /// build just to get search working everywhere.
  Future<List<MessageSearchHit>> searchMessages(
    String query, {
    String? chatId,
    int limit = 50,
  }) async {
    if (query.trim().isEmpty) return const [];
    final db = await _database;
    final String sql;
    final List<Object?> args;
    if (_ftsEnabled) {
      final ftsQuery = _sanitiseFtsQuery(query);
      if (ftsQuery.isEmpty) return const [];
      args = <Object?>[ftsQuery];
      sql = 'SELECT m.id, m.chat_id, m.role, m.content, m.created_at, c.title '
          'FROM messages_fts f '
          'JOIN messages m ON m.id = f.message_id '
          'JOIN chats c ON c.id = m.chat_id '
          'WHERE messages_fts MATCH ?'
          '${chatId != null ? ' AND m.chat_id = ?' : ''}'
          ' ORDER BY m.created_at DESC LIMIT ?';
      if (chatId != null) args.add(chatId);
      args.add(limit);
    } else {
      final like = '%${query.trim().toLowerCase()}%';
      args = <Object?>[like];
      sql = 'SELECT m.id, m.chat_id, m.role, m.content, m.created_at, c.title '
          'FROM messages m '
          'JOIN chats c ON c.id = m.chat_id '
          'WHERE LOWER(m.content) LIKE ?'
          '${chatId != null ? ' AND m.chat_id = ?' : ''}'
          ' ORDER BY m.created_at DESC LIMIT ?';
      if (chatId != null) args.add(chatId);
      args.add(limit);
    }
    final rows = await db.rawQuery(sql, args);
    return rows
        .map(
          (r) => MessageSearchHit(
            messageId: r['id'] as String,
            chatId: r['chat_id'] as String,
            chatTitle: r['title'] as String,
            role: r['role'] as String,
            snippet: r['content'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              r['created_at'] as int,
            ),
          ),
        )
        .toList();
  }

  /// Strip FTS5 syntax characters from user input so a raw query like
  /// `rm -rf *` doesn't blow up parsing. Wraps each token in quotes so
  /// the matcher treats punctuation as literal text.
  static String _sanitiseFtsQuery(String q) {
    final tokens = q
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return '';
    return tokens.map((t) => '"$t"').join(' ');
  }

  Future<void> _trimChatIfNeeded(Database db, String chatId) async {
    final countRes = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM messages WHERE chat_id = ?',
        [chatId],
      ),
    );
    final count = countRes ?? 0;
    if (count <= kMaxMessagesPerChat) return;
    final overflow = count - kMaxMessagesPerChat;
    // Delete the oldest `overflow` messages by created_at.
    await db.rawDelete(
      'DELETE FROM messages WHERE id IN ('
      ' SELECT id FROM messages WHERE chat_id = ? '
      ' ORDER BY created_at ASC LIMIT ?'
      ')',
      [chatId, overflow],
    );
  }

  // ---------------- Memories ----------------

  Future<List<MemoryEntry>> getAllMemories({int? limit}) async {
    final db = await _database;
    final rows = await db.query(
      'memories',
      orderBy: 'last_used_at DESC',
      limit: limit,
    );
    return rows.map(_rowToMemory).toList();
  }

  Future<MemoryEntry> saveMemory(MemoryEntry memory) async {
    final db = await _database;
    await db.insert(
      'memories',
      _memoryToRow(memory),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return memory;
  }

  Future<void> deleteMemory(String id) async {
    final db = await _database;
    await db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllMemories() async {
    final db = await _database;
    await db.delete('memories');
  }

  Future<void> touchMemory(String id) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate(
      'UPDATE memories SET last_used_at = ?, use_count = use_count + 1 WHERE id = ?',
      [now, id],
    );
  }

  /// Best-effort recall: FTS against [query] if non-empty, otherwise
  /// most-recently-used. Capped at [limit] for prompt-size control.
  /// Falls back to LIKE when FTS5 isn't available (see [_ftsEnabled]).
  Future<List<MemoryEntry>> recallMemories(String query, {int limit = 6}) async {
    final db = await _database;
    final trimmed = query.trim();
    if (trimmed.isEmpty) return getAllMemories(limit: limit);
    if (_ftsEnabled) {
      final ftsQuery = _sanitiseFtsQuery(trimmed);
      if (ftsQuery.isEmpty) return getAllMemories(limit: limit);
      final rows = await db.rawQuery(
        'SELECT m.* FROM memories_fts f '
        'JOIN memories m ON m.id = f.memory_id '
        'WHERE memories_fts MATCH ? '
        'ORDER BY m.last_used_at DESC LIMIT ?',
        [ftsQuery, limit],
      );
      return rows.map(_rowToMemory).toList();
    }
    final rows = await db.query(
      'memories',
      where: 'LOWER(content) LIKE ?',
      whereArgs: ['%${trimmed.toLowerCase()}%'],
      orderBy: 'last_used_at DESC',
      limit: limit,
    );
    return rows.map(_rowToMemory).toList();
  }

  // ---------------- Folders ----------------

  Future<List<FolderEntry>> getAllFolders() async {
    final db = await _database;
    final rows = await db.query(
      'folders',
      orderBy: 'sort_index ASC, created_at ASC',
    );
    return rows.map(_rowToFolder).toList();
  }

  Future<void> saveFolder(FolderEntry folder) async {
    final db = await _database;
    await db.insert(
      'folders',
      _folderToRow(folder),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteFolder(String id) async {
    final db = await _database;
    // ON DELETE SET NULL on chats.folder_id untags chats in this folder.
    await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Prompt templates ----------------

  Future<List<PromptTemplate>> getAllPromptTemplates() async {
    final db = await _database;
    final rows = await db.query(
      'prompt_templates',
      orderBy: 'use_count DESC, updated_at DESC',
    );
    return rows.map(_rowToTemplate).toList();
  }

  Future<void> savePromptTemplate(PromptTemplate t) async {
    final db = await _database;
    await db.insert(
      'prompt_templates',
      _templateToRow(t),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePromptTemplate(String id) async {
    final db = await _database;
    await db.delete('prompt_templates', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> touchPromptTemplate(String id) async {
    final db = await _database;
    await db.rawUpdate(
      'UPDATE prompt_templates SET use_count = use_count + 1, updated_at = ? '
      'WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  // ---------------- Providers (SharedPreferences) ----------------

  Future<List<ProviderConfig>> getAllProviders() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('kolo_providers_v2');
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    final providers = list
        .map((e) => ProviderConfig.fromMap(e as Map<String, dynamic>))
        .toList();
    await Future.wait(providers.map((p) async {
      final secureKey = await _secureStorage.read(
        key: 'provider_apikey_${p.id}',
      );
      if (secureKey != null && secureKey.isNotEmpty) {
        p.apiKey = secureKey;
      }
    }));
    return providers;
  }

  Future<void> saveProvider(ProviderConfig provider) async {
    final providers = await getAllProviders();
    final idx = providers.indexWhere((p) => p.id == provider.id);
    if (idx >= 0) {
      providers[idx] = provider.copyWith();
    } else {
      providers.add(provider);
    }
    await _writeProviders(providers);
  }

  Future<void> writeAllProviders(List<ProviderConfig> providers) async =>
      _writeProviders(providers);

  Future<void> deleteProvider(String id) async {
    var providers = await getAllProviders();
    providers.removeWhere((p) => p.id == id);
    await _secureStorage.delete(key: 'provider_apikey_$id');
    await _writeProviders(providers);
  }

  Future<void> _writeProviders(List<ProviderConfig> providers) async {
    await Future.wait(providers.map((p) {
      if (p.apiKey.isNotEmpty) {
        return _secureStorage.write(
          key: 'provider_apikey_${p.id}',
          value: p.apiKey,
        );
      } else {
        return _secureStorage.delete(key: 'provider_apikey_${p.id}');
      }
    }));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'kolo_providers_v2',
      jsonEncode(providers.map((p) => p.toMapWithoutApiKey()).toList()),
    );
  }

  Future<ProviderConfig?> getActiveProvider() async {
    final providers = await getAllProviders();
    return providers.where((p) => p.isActive).firstOrNull ??
        (providers.isNotEmpty ? providers.first : null);
  }

  /// Delegates to [ModelFetcher]; kept as an instance method so existing
  /// callers don't need to import ModelFetcher directly.
  Future<List<ModelConfig>> fetchModels(ProviderConfig provider) =>
      ModelFetcher.fetchModels(provider);

  // ---------------- Active Model Selection ----------------

  Future<String?> getActiveModelId(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('kolo_active_model_$providerId');
  }

  Future<void> setActiveModelId(String providerId, String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kolo_active_model_$providerId', modelId);
  }

  // ---------------- Settings ----------------

  Future<String?> getSetting(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('kolo_setting_$key');
  }

  Future<void> saveSetting(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kolo_setting_$key', value);
  }

  // ---------------- Custom tools ----------------

  static const String _kCustomToolsKey = 'kolo_custom_tools_v1';
  static const int kMaxCustomTools = 50;

  Future<List<CustomToolDef>> getAllCustomTools() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCustomToolsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => CustomToolDef.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<CustomToolDef> saveCustomTool(CustomToolDef def) async {
    final all = await getAllCustomTools();
    final idx = all.indexWhere((t) => t.id == def.id);
    if (idx >= 0) {
      all[idx] = def;
    } else {
      if (all.length >= kMaxCustomTools) {
        throw StateError(
          'Custom-tool limit reached ($kMaxCustomTools). Delete one first.',
        );
      }
      all.add(def);
    }
    await _writeCustomTools(all);
    return def;
  }

  Future<void> deleteCustomTool(String id) async {
    final all = await getAllCustomTools();
    all.removeWhere((t) => t.id == id);
    await _writeCustomTools(all);
  }

  Future<void> _writeCustomTools(List<CustomToolDef> tools) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kCustomToolsKey,
      jsonEncode(tools.map((t) => t.toMap()).toList()),
    );
  }

  // ---------------- Drafts ----------------

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

  // ---------------- Row <-> entity mapping ----------------

  Map<String, Object?> _chatToRow(ChatEntry c) => {
    'id': c.id,
    'title': c.title,
    'provider_id': c.providerId,
    'model_id': c.modelId,
    'folder_id': c.folderId,
    'created_at': c.createdAt.millisecondsSinceEpoch,
    'updated_at': c.updatedAt.millisecondsSinceEpoch,
    'message_count': c.messageCount,
    'is_pinned': c.isPinned ? 1 : 0,
    'unread_count': c.unreadCount,
  };

  ChatEntry _rowToChat(Map<String, Object?> r) => ChatEntry(
    id: r['id'] as String,
    title: r['title'] as String,
    providerId: r['provider_id'] as String?,
    modelId: r['model_id'] as String?,
    folderId: r['folder_id'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    messageCount: (r['message_count'] as int?) ?? 0,
    isPinned: ((r['is_pinned'] as int?) ?? 0) != 0,
    unreadCount: (r['unread_count'] as int?) ?? 0,
  );

  Map<String, Object?> _messageToRow(MessageEntry m) => {
    'id': m.id,
    'chat_id': m.chatId,
    'role': m.role,
    'content': m.content,
    'tool_call_id': m.toolCallId,
    'tool_name': m.toolName,
    'tool_success': m.toolSuccess == null ? null : (m.toolSuccess! ? 1 : 0),
    'tool_calls_json': m.toolCalls == null ? null : jsonEncode(m.toolCalls),
    'status': m.status,
    'error': m.error,
    'created_at': m.createdAt.millisecondsSinceEpoch,
    'edited_at': m.editedAt?.millisecondsSinceEpoch,
  };

  MessageEntry _rowToMessage(Map<String, Object?> r) => MessageEntry(
    id: r['id'] as String,
    chatId: r['chat_id'] as String,
    role: r['role'] as String,
    content: r['content'] as String,
    toolCallId: r['tool_call_id'] as String?,
    toolName: r['tool_name'] as String?,
    toolSuccess: r['tool_success'] == null
        ? null
        : (r['tool_success'] as int) != 0,
    toolCalls: r['tool_calls_json'] == null
        ? null
        : (jsonDecode(r['tool_calls_json'] as String) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
    status: r['status'] as String?,
    error: r['error'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    editedAt: r['edited_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r['edited_at'] as int),
  );

  Map<String, Object?> _memoryToRow(MemoryEntry m) => {
    'id': m.id,
    'kind': m.kind,
    'content': m.content,
    'source_chat_id': m.sourceChatId,
    'created_at': m.createdAt.millisecondsSinceEpoch,
    'updated_at': m.updatedAt.millisecondsSinceEpoch,
    'last_used_at': m.lastUsedAt.millisecondsSinceEpoch,
    'use_count': m.useCount,
  };

  MemoryEntry _rowToMemory(Map<String, Object?> r) => MemoryEntry(
    id: r['id'] as String,
    kind: r['kind'] as String,
    content: r['content'] as String,
    sourceChatId: r['source_chat_id'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    lastUsedAt: DateTime.fromMillisecondsSinceEpoch(r['last_used_at'] as int),
    useCount: (r['use_count'] as int?) ?? 0,
  );

  Map<String, Object?> _folderToRow(FolderEntry f) => {
    'id': f.id,
    'name': f.name,
    'color': f.color,
    'sort_index': f.sortIndex,
    'created_at': f.createdAt.millisecondsSinceEpoch,
  };

  FolderEntry _rowToFolder(Map<String, Object?> r) => FolderEntry(
    id: r['id'] as String,
    name: r['name'] as String,
    color: r['color'] as int?,
    sortIndex: (r['sort_index'] as int?) ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
  );

  Map<String, Object?> _templateToRow(PromptTemplate t) => {
    'id': t.id,
    'name': t.name,
    'body': t.body,
    'tags': t.tags.isEmpty ? null : t.tags.join(','),
    'use_count': t.useCount,
    'created_at': t.createdAt.millisecondsSinceEpoch,
    'updated_at': t.updatedAt.millisecondsSinceEpoch,
  };

  PromptTemplate _rowToTemplate(Map<String, Object?> r) => PromptTemplate(
    id: r['id'] as String,
    name: r['name'] as String,
    body: r['body'] as String,
    tags: (r['tags'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ??
        const [],
    useCount: (r['use_count'] as int?) ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
  );
}

// ---------------- Entity models ----------------

class ChatEntry {
  final String id;
  String title;
  String? providerId;
  String? modelId;
  String? folderId;
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
    this.folderId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.messageCount = 0,
    this.isPinned = false,
    this.unreadCount = 0,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'providerId': providerId,
    'modelId': modelId,
    'folderId': folderId,
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
    folderId: m['folderId'] as String?,
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
  final List<Map<String, dynamic>>? toolCalls;
  final String? status;
  final String? error;
  final DateTime createdAt;
  final DateTime? editedAt;

  MessageEntry({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolName,
    this.toolSuccess,
    this.toolCalls,
    this.status,
    this.error,
    DateTime? createdAt,
    this.editedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  MessageEntry copyWith({
    String? content,
    String? status,
    String? error,
    DateTime? editedAt,
  }) => MessageEntry(
    id: id,
    chatId: chatId,
    role: role,
    content: content ?? this.content,
    toolCallId: toolCallId,
    toolName: toolName,
    toolSuccess: toolSuccess,
    toolCalls: toolCalls,
    status: status ?? this.status,
    error: error ?? this.error,
    createdAt: createdAt,
    editedAt: editedAt ?? this.editedAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'chatId': chatId,
    'role': role,
    'content': content,
    'toolCallId': toolCallId,
    'toolName': toolName,
    'toolSuccess': toolSuccess,
    'toolCalls': toolCalls,
    'status': status,
    'error': error,
    'createdAt': createdAt.toIso8601String(),
    'editedAt': editedAt?.toIso8601String(),
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
    status: m['status'] as String?,
    error: m['error'] as String?,
    createdAt: DateTime.parse(m['createdAt'] as String),
    editedAt: m['editedAt'] == null
        ? null
        : DateTime.parse(m['editedAt'] as String),
  );
}

class MemoryEntry {
  final String id;
  final String kind;
  final String content;
  final String? sourceChatId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastUsedAt;
  final int useCount;

  MemoryEntry({
    required this.id,
    required this.kind,
    required this.content,
    this.sourceChatId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    this.useCount = 0,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       lastUsedAt = lastUsedAt ?? DateTime.now();
}

class FolderEntry {
  final String id;
  final String name;
  final int? color;
  final int sortIndex;
  final DateTime createdAt;

  FolderEntry({
    required this.id,
    required this.name,
    this.color,
    this.sortIndex = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

class PromptTemplate {
  final String id;
  final String name;
  final String body;
  final List<String> tags;
  final int useCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  PromptTemplate({
    required this.id,
    required this.name,
    required this.body,
    this.tags = const [],
    this.useCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();
}

class MessageSearchHit {
  final String messageId;
  final String chatId;
  final String chatTitle;
  final String role;
  final String snippet;
  final DateTime createdAt;

  const MessageSearchHit({
    required this.messageId,
    required this.chatId,
    required this.chatTitle,
    required this.role,
    required this.snippet,
    required this.createdAt,
  });
}
