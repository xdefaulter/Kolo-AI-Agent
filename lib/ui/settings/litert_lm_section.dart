import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/provider.dart';
import '../../core/haptics.dart';
import '../../core/llm/litert_lm_service.dart';
import '../../core/providers_state.dart';
import '../../core/ui/toast.dart';

/// Compact surface for managing on-device LiteRT-LM models. Allows picking
/// a .litertlm file and starting/stopping the inference engine.
class LitertLmSection extends ConsumerStatefulWidget {
  const LitertLmSection({super.key});

  @override
  ConsumerState<LitertLmSection> createState() => _LitertLmSectionState();
}

class _LitertLmSectionState extends ConsumerState<LitertLmSection> {
  final _service = LitertLmService.instance;
  StreamSubscription<LitertLmState>? _stateSub;
  StreamSubscription<String>? _logSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _service.stateStream.listen((state) {
      if (mounted) setState(() {});
    });
    _logSub = _service.logStream.listen((line) {
      // Could pipe to a log viewer like LlamaServerLogsScreen
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _logSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Find the local LiteRT-LM provider if one exists.
    final localProvider = ref.watch(
      providersProvider.select((all) {
        for (final p in all) {
          if (p.kind == ProviderKind.localLiteRtLm) return p;
        }
        return null;
      }),
    );

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(Icons.memory, color: cs.primary),
            title: const Text('LiteRT-LM (NPU)'),
            subtitle: Text(_stateSubtitle(_service.state, localProvider)),
            trailing: _StatusChip(state: _service.state),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_service.state == LitertLmState.notLoaded ||
                    _service.state == LitertLmState.stopped ||
                    _service.state == LitertLmState.error)
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Start engine'),
                    onPressed: localProvider?.modelPath == null
                        ? null
                        : () => _startEngine(context, localProvider!),
                  ),
                if (_service.state == LitertLmState.loading)
                  FilledButton.tonalIcon(
                    icon: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: const Text('Loading model...'),
                    onPressed: null,
                  ),
                if (_service.state == LitertLmState.running)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Stop engine'),
                    onPressed: () => _stopEngine(context),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(
                    localProvider?.modelPath == null
                        ? 'Pick .litertlm file'
                        : 'Swap model',
                  ),
                  onPressed: () => _pickModel(context, ref, localProvider),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Download from HF'),
                  onPressed: () => _downloadFromHf(context, ref),
                ),
              ],
            ),
          ),
          if (localProvider?.modelPath != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Model: ${_shortPath(localProvider!.modelPath!)}',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          if (_service.lastError != null &&
              _service.state == LitertLmState.error)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _service.lastError!,
                style: TextStyle(fontSize: 12, color: cs.error),
              ),
            ),
        ],
      ),
    );
  }

  static String _stateSubtitle(LitertLmState s, ProviderConfig? provider) {
    switch (s) {
      case LitertLmState.notLoaded:
        return provider?.modelPath == null
            ? 'On-device inference via Tensor G5 NPU.'
            : 'Model picked. Tap Start to load.';
      case LitertLmState.loading:
        return 'Loading model into memory...';
      case LitertLmState.running:
        return 'Running on ${LitertLmService.instance.activeBackend}';
      case LitertLmState.error:
        return 'Error — check logs.';
      case LitertLmState.stopped:
        return 'Engine stopped.';
    }
  }

  static String _shortPath(String p) {
    if (p.length <= 60) return p;
    return '...${p.substring(p.length - 57)}';
  }

  Future<void> _startEngine(
    BuildContext context,
    ProviderConfig provider,
  ) async {
    Haptics.light();
    final path = provider.modelPath;
    if (path == null) return;
    final ok = await _service.initialize(path);
    if (!context.mounted) return;
    showKoloToast(
      context,
      ok ? 'LiteRT-LM engine running.' : 'Failed to start engine — check logs.',
      kind: ok ? ToastKind.success : ToastKind.error,
    );
  }

  Future<void> _stopEngine(BuildContext context) async {
    Haptics.light();
    await _service.close();
    if (!context.mounted) return;
    showKoloToast(context, 'Engine stopped.');
  }

  Future<void> _pickModel(
    BuildContext context,
    WidgetRef ref,
    ProviderConfig? existing,
  ) async {
    Haptics.light();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      dialogTitle: 'Select a .litertlm model file',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (!path.toLowerCase().endsWith('.litertlm')) {
      if (!context.mounted) return;
      showKoloToast(
        context,
        "That file isn't a .litertlm — LiteRT-LM needs a converted model.",
        kind: ToastKind.warning,
      );
      return;
    }
    if (!context.mounted) return;
    _applyNewModelPath(context, ref, existing, path);
  }

  Future<void> _downloadFromHf(BuildContext context, WidgetRef ref) async {
    // TODO: Implement HF download for .litertlm files, similar to
    // HfBrowserScreen but for LiteRT-LM models. For now, prompt the user
    // to pick a local file.
    showKoloToast(
      context,
      'Download coming soon — pick a local .litertlm file for now.',
      kind: ToastKind.info,
    );
  }

  void _applyNewModelPath(
    BuildContext context,
    WidgetRef ref,
    ProviderConfig? existing,
    String path,
  ) {
    final notifier = ref.read(providersProvider.notifier);
    if (existing != null) {
      notifier.updateProvider(existing.copyWith(modelPath: path));
    } else {
      notifier.addProvider(
        ProviderConfig(
          name: 'LiteRT-LM (on-device)',
          baseUrl: '',
          kind: ProviderKind.localLiteRtLm,
          modelPath: path,
          smallModelMode: true,
          models: [
            ModelConfig(
              modelId: path.split('/').last,
              displayName: path.split('/').last.replaceAll('.litertlm', ''),
              maxTokens: 2048,
              contextWindow: 4096,
              isActive: true,
              isCustom: true,
            ),
          ],
        ),
      );
    }
    showKoloToast(context, 'Model set. Tap Start engine to load it.');
  }
}

class _StatusChip extends StatelessWidget {
  final LitertLmState state;
  const _StatusChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, color) = _tuple(cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (String, Color) _tuple(ColorScheme cs) {
    switch (state) {
      case LitertLmState.notLoaded:
        return ('not loaded', cs.onSurface.withValues(alpha: 0.4));
      case LitertLmState.loading:
        return ('loading', cs.primary);
      case LitertLmState.running:
        return ('running', Colors.green.shade700);
      case LitertLmState.error:
        return ('error', cs.error);
      case LitertLmState.stopped:
        return ('stopped', cs.onSurface.withValues(alpha: 0.7));
    }
  }
}
