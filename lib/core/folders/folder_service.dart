import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../storage/database.dart';

class FolderService {
  FolderService._();
  static final FolderService instance = FolderService._();

  final _uuid = const Uuid();

  Future<List<FolderEntry>> all() => AppDatabase.instance.getAllFolders();

  Future<FolderEntry> create({required String name, int? color}) async {
    final f = FolderEntry(id: _uuid.v4(), name: name.trim(), color: color);
    await AppDatabase.instance.saveFolder(f);
    return f;
  }

  Future<void> rename(String id, String name) async {
    final existing = (await all()).where((f) => f.id == id).firstOrNull;
    if (existing == null) return;
    await AppDatabase.instance.saveFolder(
      FolderEntry(
        id: existing.id,
        name: name.trim(),
        color: existing.color,
        sortIndex: existing.sortIndex,
        createdAt: existing.createdAt,
      ),
    );
  }

  Future<void> delete(String id) => AppDatabase.instance.deleteFolder(id);

  Future<void> assign(String chatId, String? folderId) =>
      AppDatabase.instance.moveChatToFolder(chatId, folderId);
}

class FoldersNotifier extends StateNotifier<List<FolderEntry>> {
  FoldersNotifier() : super(const []) {
    reload();
  }

  Future<void> reload() async {
    final all = await FolderService.instance.all();
    if (!mounted) return;
    state = all;
  }
}

final foldersProvider =
    StateNotifierProvider<FoldersNotifier, List<FolderEntry>>(
      (ref) => FoldersNotifier(),
    );

/// Active folder filter for the chat drawer. Null means "all chats".
/// Only lives in memory — resets to null when the app restarts.
final activeFolderIdProvider = StateProvider<String?>((ref) => null);
