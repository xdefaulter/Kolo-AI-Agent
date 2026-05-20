import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../storage/database.dart';

/// Facade over [AppDatabase] prompt-template CRUD so the UI doesn't
/// import the storage layer directly.
class PromptLibrary {
  PromptLibrary._();
  static final PromptLibrary instance = PromptLibrary._();

  final _uuid = const Uuid();

  Future<List<PromptTemplate>> all() =>
      AppDatabase.instance.getAllPromptTemplates();

  Future<PromptTemplate> create({
    required String name,
    required String body,
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final template = PromptTemplate(
      id: _uuid.v4(),
      name: name.trim(),
      body: body,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
    await AppDatabase.instance.savePromptTemplate(template);
    return template;
  }

  Future<void> update(PromptTemplate t) =>
      AppDatabase.instance.savePromptTemplate(t);

  Future<void> delete(String id) =>
      AppDatabase.instance.deletePromptTemplate(id);

  Future<void> touch(String id) =>
      AppDatabase.instance.touchPromptTemplate(id);

  // One compile, lifetime-of-process. Both `variables()` and `render()`
  // used to recompile this on every call — regex compilation isn't free
  // and these fire on every prompt-library render.
  static final RegExp _placeholderPattern =
      RegExp(r'\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}');

  /// Extract `{{var_name}}` placeholders from a template body. Used by
  /// the render dialog to ask the user for values.
  static List<String> variables(String body) {
    final matches = _placeholderPattern.allMatches(body);
    final names = <String>{};
    for (final m in matches) {
      names.add(m.group(1)!);
    }
    return names.toList();
  }

  /// Substitute user-provided values into the template. Missing or
  /// empty values stay as the original placeholder so the user can
  /// see what they skipped when the text lands in the composer.
  static String render(String body, Map<String, String> values) {
    return body.replaceAllMapped(_placeholderPattern, (m) {
      final name = m.group(1)!;
      final v = values[name];
      if (v == null || v.isEmpty) return m.group(0)!;
      return v;
    });
  }
}

/// Cached list of prompt templates. Invalidated via `reload()` after
/// any CRUD mutation from the UI or tools.
class PromptLibraryNotifier extends StateNotifier<List<PromptTemplate>> {
  PromptLibraryNotifier() : super(const []) {
    reload();
  }

  Future<void> reload() async {
    final all = await PromptLibrary.instance.all();
    if (!mounted) return;
    state = all;
  }
}

final promptLibraryProvider =
    StateNotifierProvider<PromptLibraryNotifier, List<PromptTemplate>>(
      (ref) => PromptLibraryNotifier(),
    );
