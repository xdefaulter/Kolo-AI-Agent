import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prompts/prompt_library.dart';
import '../../core/storage/database.dart';

/// Bottom sheet that lists saved prompt templates. Tapping one resolves
/// `{{var}}` placeholders (asking the user for values) and returns the
/// final text to the composer via [onPromptResolved].
///
/// The sheet takes its chrome from the chat screen's theme but stays
/// small enough to overlay the composer — it doesn't scroll the whole
/// chat out of view on tablets.
class PromptLibrarySheet extends ConsumerStatefulWidget {
  final void Function(String resolvedText) onPromptResolved;

  const PromptLibrarySheet({super.key, required this.onPromptResolved});

  @override
  ConsumerState<PromptLibrarySheet> createState() =>
      _PromptLibrarySheetState();
}

class _PromptLibrarySheetState extends ConsumerState<PromptLibrarySheet> {
  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(promptLibraryProvider);
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (ctx, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  'Prompt library',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'New template',
                  icon: const Icon(Icons.add),
                  onPressed: () => _editTemplate(context, null),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: templates.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No saved prompts.\nTap + to add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: templates.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final t = templates[i];
                      return ListTile(
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: Text(t.name),
                        subtitle: Text(
                          t.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.65),
                            fontSize: 12,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                          onSelected: (v) async {
                            if (v == 'edit') {
                              if (ctx.mounted) _editTemplate(ctx, t);
                            } else if (v == 'delete') {
                              await PromptLibrary.instance.delete(t.id);
                              ref
                                  .read(promptLibraryProvider.notifier)
                                  .reload();
                            }
                          },
                        ),
                        onTap: () => _usePrompt(t),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _usePrompt(PromptTemplate t) async {
    final vars = PromptLibrary.variables(t.body);
    String resolved = t.body;
    if (vars.isNotEmpty) {
      final values = await _promptForVariables(context, vars);
      if (values == null) return;
      resolved = PromptLibrary.render(t.body, values);
    }
    await PromptLibrary.instance.touch(t.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onPromptResolved(resolved);
  }

  Future<Map<String, String>?> _promptForVariables(
    BuildContext context,
    List<String> vars,
  ) async {
    final controllers = {for (final v in vars) v: TextEditingController()};
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fill in placeholders'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in vars)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: TextField(
                    controller: controllers[v],
                    decoration: InputDecoration(labelText: v),
                    autofocus: v == vars.first,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    if (done != true) return null;
    return {for (final e in controllers.entries) e.key: e.value.text};
  }

  Future<void> _editTemplate(BuildContext ctx, PromptTemplate? existing) async {
    final nameC = TextEditingController(text: existing?.name);
    final bodyC = TextEditingController(text: existing?.body);
    final saved = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: Text(existing == null ? 'New template' : 'Edit template'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: bodyC,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Body (use {{variable}} for placeholders)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final name = nameC.text.trim();
    final body = bodyC.text;
    if (name.isEmpty || body.isEmpty) return;
    if (existing == null) {
      await PromptLibrary.instance.create(name: name, body: body);
    } else {
      await PromptLibrary.instance.update(
        PromptTemplate(
          id: existing.id,
          name: name,
          body: body,
          tags: existing.tags,
          useCount: existing.useCount,
          createdAt: existing.createdAt,
          updatedAt: DateTime.now(),
        ),
      );
    }
    if (!mounted) return;
    ref.read(promptLibraryProvider.notifier).reload();
  }
}
