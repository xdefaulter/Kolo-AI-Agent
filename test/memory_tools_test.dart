import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/memory/memory_service.dart';
import 'package:kolo_ai_agent/core/memory/memory_tools.dart';
import 'package:kolo_ai_agent/core/storage/database.dart';
import 'package:kolo_ai_agent/core/tools/tool_base.dart';

import 'helpers/test_harness.dart';

ToolContext _ctx({
  bool approve = true,
}) => ToolContext(
  chatId: 'test-chat',
  permissionChecker: (_) async => approve,
);

void main() {
  setUp(() async {
    await installTestHarness();
    AppDatabase.resetForTest();
  });

  test('RememberThisTool rejects empty content', () async {
    final tool = RememberThisTool(onChange: () async {});
    final r = await tool.execute({'kind': 'fact', 'content': '   '}, _ctx());
    expect(r.success, isFalse);
  });

  test('RememberThisTool persists a memory when user approves', () async {
    var changeCalled = 0;
    final tool = RememberThisTool(onChange: () async {
      changeCalled++;
    });
    final r = await tool.execute(
      {'kind': 'preference', 'content': 'User prefers concise code.'},
      _ctx(),
    );
    expect(r.success, isTrue);
    expect(changeCalled, 1);
    final stored = await MemoryService.instance.all();
    expect(stored, hasLength(1));
    expect(stored.single.kind, 'preference');
  });

  test('RememberThisTool skips persisting when user declines', () async {
    final tool = RememberThisTool(onChange: () async {});
    final r = await tool.execute(
      {'kind': 'fact', 'content': 'x'},
      _ctx(approve: false),
    );
    expect(r.success, isFalse);
    expect(await MemoryService.instance.all(), isEmpty);
  });

  test('RecallMemoriesTool returns stored memories', () async {
    await MemoryService.instance.create(
      kind: 'preference',
      content: 'The user likes tabs over spaces.',
    );
    final tool = RecallMemoriesTool();
    final r = await tool.execute({'query': 'tabs'}, _ctx());
    expect(r.success, isTrue);
    expect(r.output.contains('tabs'), isTrue);
  });

  test('RecallMemoriesTool reports empty gracefully', () async {
    final tool = RecallMemoriesTool();
    final r = await tool.execute({'query': 'nothing'}, _ctx());
    expect(r.success, isTrue);
    expect(r.output.contains('no matching'), isTrue);
  });

  test('ForgetMemoryTool removes by id', () async {
    final m = await MemoryService.instance.create(
      kind: 'fact',
      content: 'Stale fact.',
    );
    final tool = ForgetMemoryTool(onChange: () async {});
    final r = await tool.execute({'id': m.id}, _ctx());
    expect(r.success, isTrue);
    expect(await MemoryService.instance.all(), isEmpty);
  });

  test('MemoryService.buildRecallBlock respects disabled flag', () async {
    await AppDatabase.instance.saveSetting(
      kMemoryRecallEnabledSettingKey,
      'false',
    );
    await MemoryService.instance.create(
      kind: 'fact',
      content: 'This should not surface.',
    );
    final block = await MemoryService.instance.buildRecallBlock('surface');
    expect(block, isEmpty);
  });

  test('MemoryService.buildRecallBlock emits a header when memories hit',
      () async {
    await MemoryService.instance.create(
      kind: 'preference',
      content: 'User always uses dark mode.',
    );
    final block = await MemoryService.instance.buildRecallBlock('dark');
    expect(block, isNotEmpty);
    expect(block.contains('[preference]'), isTrue);
    expect(block.contains('dark mode'), isTrue);
  });
}
