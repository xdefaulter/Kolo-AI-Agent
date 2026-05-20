import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/storage/database.dart';
import 'package:uuid/uuid.dart';

import 'helpers/test_harness.dart';

void main() {
  const uuid = Uuid();

  setUp(() async {
    await installTestHarness();
    AppDatabase.resetForTest();
  });

  test('chats round-trip', () async {
    final db = AppDatabase.instance;
    await db.initialize();
    final c = ChatEntry(id: uuid.v4(), title: 'Hello', messageCount: 0);
    await db.saveChat(c);
    final all = await db.getAllChats();
    expect(all, hasLength(1));
    expect(all.first.title, 'Hello');
    expect(all.first.id, c.id);
  });

  test('messages insert + ordering + CASCADE on chat delete', () async {
    final db = AppDatabase.instance;
    await db.initialize();
    final chatId = uuid.v4();
    await db.saveChat(ChatEntry(id: chatId, title: 'T'));
    final t0 = DateTime(2026, 1, 1);
    for (int i = 0; i < 3; i++) {
      await db.addMessage(
        chatId,
        MessageEntry(
          id: uuid.v4(),
          chatId: chatId,
          role: 'user',
          content: 'msg $i',
          createdAt: t0.add(Duration(seconds: i)),
        ),
      );
    }
    final msgs = await db.getMessages(chatId);
    expect(msgs, hasLength(3));
    expect(msgs.map((m) => m.content).toList(), ['msg 0', 'msg 1', 'msg 2']);

    // Delete the chat — messages must cascade.
    await db.deleteChat(chatId);
    expect(await db.getMessages(chatId), isEmpty);
  });

  test('searchMessages via FTS finds content across chats', () async {
    final db = AppDatabase.instance;
    await db.initialize();
    final chatA = uuid.v4();
    final chatB = uuid.v4();
    await db.saveChat(ChatEntry(id: chatA, title: 'A'));
    await db.saveChat(ChatEntry(id: chatB, title: 'B'));
    await db.addMessage(
      chatA,
      MessageEntry(
        id: uuid.v4(),
        chatId: chatA,
        role: 'user',
        content: 'The quick brown fox jumps',
      ),
    );
    await db.addMessage(
      chatB,
      MessageEntry(
        id: uuid.v4(),
        chatId: chatB,
        role: 'assistant',
        content: 'Lazy dogs were jumping over things',
      ),
    );

    final hits = await db.searchMessages('jump');
    expect(hits, isNotEmpty);
    // Porter stemming should match both 'jumps' and 'jumping'.
    expect(hits.length, greaterThanOrEqualTo(2));

    final scoped = await db.searchMessages('jump', chatId: chatA);
    expect(scoped, hasLength(1));
    expect(scoped.single.chatId, chatA);
  });

  test('deleteMessagesAfter truncates transcript at a point', () async {
    final db = AppDatabase.instance;
    await db.initialize();
    final chatId = uuid.v4();
    await db.saveChat(ChatEntry(id: chatId, title: 'T'));
    final base = DateTime(2026, 2, 1, 12);
    final cutoff = base.add(const Duration(minutes: 5));
    for (int i = 0; i < 5; i++) {
      await db.addMessage(
        chatId,
        MessageEntry(
          id: uuid.v4(),
          chatId: chatId,
          role: 'user',
          content: 'm$i',
          createdAt: base.add(Duration(minutes: i * 2)),
        ),
      );
    }
    // Messages at t+0, t+2, t+4 survive (<=cutoff); t+6, t+8 truncate.
    await db.deleteMessagesAfter(chatId, cutoff);
    final remaining = await db.getMessages(chatId);
    expect(remaining, hasLength(3));
    expect(remaining.last.content, 'm2');
  });

  test('memories save, recall, and delete', () async {
    final db = AppDatabase.instance;
    await db.initialize();
    await db.saveMemory(
      MemoryEntry(
        id: 'm1',
        kind: 'preference',
        content: 'The user prefers concise Dart code with no comments.',
      ),
    );
    await db.saveMemory(
      MemoryEntry(
        id: 'm2',
        kind: 'fact',
        content: 'The user is building a mobile AI assistant app.',
      ),
    );
    final all = await db.getAllMemories();
    expect(all, hasLength(2));

    final hits = await db.recallMemories('dart');
    expect(hits, isNotEmpty);
    expect(hits.any((m) => m.id == 'm1'), isTrue);

    await db.deleteMemory('m1');
    expect((await db.getAllMemories()).map((m) => m.id), ['m2']);
  });

  test('folders + moveChatToFolder + ON DELETE SET NULL', () async {
    final db = AppDatabase.instance;
    await db.initialize();
    final chatId = uuid.v4();
    const folderId = 'f1';
    await db.saveFolder(FolderEntry(id: folderId, name: 'Work'));
    await db.saveChat(ChatEntry(id: chatId, title: 'C'));
    await db.moveChatToFolder(chatId, folderId);
    final chat = (await db.getAllChats()).first;
    expect(chat.folderId, folderId);

    await db.deleteFolder(folderId);
    final reread = (await db.getAllChats()).first;
    expect(reread.folderId, isNull);
  });

  test('prompt templates round-trip + touch', () async {
    final db = AppDatabase.instance;
    await db.initialize();
    final t = PromptTemplate(
      id: 't1',
      name: 'Summarise',
      body: 'Summarise the following in 3 bullets: {{input}}',
      tags: ['writing', 'tl;dr'],
    );
    await db.savePromptTemplate(t);
    var fetched = (await db.getAllPromptTemplates()).single;
    expect(fetched.name, 'Summarise');
    expect(fetched.tags, ['writing', 'tl;dr']);
    await db.touchPromptTemplate('t1');
    fetched = (await db.getAllPromptTemplates()).single;
    expect(fetched.useCount, 1);
  });

  test('searchMessages rejects pure-punctuation query safely', () async {
    final db = AppDatabase.instance;
    await db.initialize();
    expect(await db.searchMessages('---'), isEmpty);
    expect(await db.searchMessages(''), isEmpty);
  });
}
