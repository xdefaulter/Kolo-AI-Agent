import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/provider.dart';
import '../../core/haptics.dart';
import '../../core/llm/llama_server_provider.dart';
import '../../core/llm/llama_server_service.dart';
import '../../core/providers_state.dart';
import '../../core/ui/toast.dart';
import '../shared/page_transitions.dart';
import 'hf_browser_screen.dart';

/// Compact surface that lets the user install llama.cpp, pick a GGUF
/// model, and control the server lifecycle. Designed to live inline in
/// Settings — heavier workflows (logs, advanced args) push onto a
/// dedicated screen via "Show logs" / "Advanced".
class LocalModelSection extends ConsumerWidget {
  const LocalModelSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(llamaServerStateProvider);
    final state = asyncState.value ?? LlamaServerService.instance.state;
    final cs = Theme.of(context).colorScheme;
    // Narrow the watch: we only care about the local provider here, so
    // toggling anything on an OpenAI/Groq provider shouldn't rebuild
    // this section. `select` lets Riverpod skip the rebuild when the
    // selected value is ==.
    final localProvider = ref.watch(providersProvider.select((all) {
      for (final p in all) {
        if (p.kind == ProviderKind.localLlama) return p;
      }
      return null;
    }));

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(Icons.memory, color: cs.primary),
            title: const Text('Local llama.cpp'),
            subtitle: Text(_stateSubtitle(state, localProvider)),
            trailing: _StatusChip(state: state),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (state == LlamaServerState.notInstalled ||
                    state == LlamaServerState.bootstrapPending)
                  FilledButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Install llama.cpp'),
                    onPressed: state == LlamaServerState.bootstrapPending
                        ? null
                        : () => _install(context, ref, withVulkan: false),
                  ),
                if (state == LlamaServerState.installing)
                  FilledButton.tonalIcon(
                    icon: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: const Text('Installing...'),
                    onPressed: null,
                  ),
                if (state == LlamaServerState.stopped ||
                    state == LlamaServerState.crashed)
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Start server'),
                    onPressed: localProvider?.modelPath == null
                        ? null
                        : () => _startServer(context, localProvider!),
                  ),
                if (state == LlamaServerState.running ||
                    state == LlamaServerState.starting)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Stop server'),
                    onPressed: () => _stopServer(context),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: Text(
                    localProvider?.modelPath == null
                        ? 'Download from HF'
                        : 'Swap model (HF)',
                  ),
                  onPressed: () => _downloadFromHf(context, ref, localProvider),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Pick local GGUF'),
                  onPressed: () => _pickModel(context, ref, localProvider),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.article_outlined, size: 18),
                  label: const Text('Logs'),
                  onPressed: () => pushSlideRight(
                    context,
                    const _LlamaServerLogsScreen(),
                  ),
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
          if (LlamaServerService.instance.lastError != null &&
              state == LlamaServerState.crashed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                LlamaServerService.instance.lastError!,
                style: TextStyle(fontSize: 12, color: cs.error),
              ),
            ),
        ],
      ),
    );
  }

  static String _stateSubtitle(LlamaServerState s, ProviderConfig? provider) {
    switch (s) {
      case LlamaServerState.bootstrapPending:
        return 'Waiting for Termux bootstrap...';
      case LlamaServerState.notInstalled:
        return 'Not installed. Tap to download ~116 MB via apt.';
      case LlamaServerState.installing:
        return 'Installing llama.cpp...';
      case LlamaServerState.stopped:
        return provider?.modelPath == null
            ? 'Installed. Pick a model to start the server.'
            : 'Installed. Server is stopped.';
      case LlamaServerState.starting:
        return 'Loading model into memory...';
      case LlamaServerState.running:
        return 'Running on ${LlamaServerService.instance.baseUrl}';
      case LlamaServerState.crashed:
        return 'Crashed — check logs.';
    }
  }

  static String _shortPath(String p) {
    if (p.length <= 60) return p;
    return '...${p.substring(p.length - 57)}';
  }

  Future<void> _install(
    BuildContext context,
    WidgetRef ref, {
    required bool withVulkan,
  }) async {
    Haptics.light();
    final ok = await LlamaServerService.instance.install(withVulkan: withVulkan);
    if (!context.mounted) return;
    showKoloToast(
      context,
      ok ? 'llama.cpp installed.' : 'Install failed — see logs.',
      kind: ok ? ToastKind.success : ToastKind.error,
    );
  }

  /// Push the HF browser. Returns a local path when the user completes
  /// a download; we then mirror the same "set or create provider"
  /// semantics as [_pickModel] so the two entry points produce the
  /// same end state.
  Future<void> _downloadFromHf(
    BuildContext context,
    WidgetRef ref,
    ProviderConfig? existing,
  ) async {
    Haptics.light();
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => HfBrowserScreen(
          // Pre-fill with the current model's repo if we're swapping —
          // saves the user retyping `owner/repo` to try a bigger quant.
          initialRepoId: _inferRepoId(existing?.modelPath),
        ),
      ),
    );
    if (!context.mounted || path == null) return;
    _applyNewModelPath(context, ref, existing, path);
  }

  /// Split the `models/{slug}/file.gguf` path back into `owner/repo` so
  /// the HF browser opens pre-populated. Slug format is
  /// `owner__repo` — matches [HfService.targetPath].
  static String? _inferRepoId(String? path) {
    if (path == null) return null;
    final marker = '/models/';
    final idx = path.indexOf(marker);
    if (idx < 0) return null;
    final after = path.substring(idx + marker.length);
    final slash = after.indexOf('/');
    if (slash < 0) return null;
    return after.substring(0, slash).replaceAll('__', '/');
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
          name: 'Local llama.cpp',
          baseUrl: LlamaServerService.instance.baseUrl,
          kind: ProviderKind.localLlama,
          modelPath: path,
          smallModelMode: true,
          models: [
            ModelConfig(
              modelId: path.split('/').last,
              displayName: path.split('/').last.replaceAll('.gguf', ''),
              maxTokens: 2048,
              contextWindow: 4096,
              isActive: true,
              isCustom: true,
            ),
          ],
        ),
      );
    }
    showKoloToast(context, 'Model set. Tap Start server to load it.');
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
      dialogTitle: 'Select a GGUF model file',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (!path.toLowerCase().endsWith('.gguf')) {
      if (!context.mounted) return;
      showKoloToast(
        context,
        'That file isn\'t a .gguf — llama.cpp needs a GGUF quantized model.',
        kind: ToastKind.warning,
      );
      return;
    }
    if (!context.mounted) return;
    _applyNewModelPath(context, ref, existing, path);
  }

  Future<void> _startServer(
    BuildContext context,
    ProviderConfig provider,
  ) async {
    Haptics.light();
    final path = provider.modelPath;
    if (path == null) return;
    final started = await LlamaServerService.instance.start(path);
    if (!context.mounted) return;
    showKoloToast(
      context,
      started ? 'Server running.' : 'Server failed to start — check logs.',
      kind: started ? ToastKind.success : ToastKind.error,
    );
  }

  Future<void> _stopServer(BuildContext context) async {
    Haptics.light();
    await LlamaServerService.instance.stop();
    if (!context.mounted) return;
    showKoloToast(context, 'Server stopped.');
  }
}

class _StatusChip extends StatelessWidget {
  final LlamaServerState state;
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
      case LlamaServerState.bootstrapPending:
        return ('pending', cs.onSurface.withValues(alpha: 0.4));
      case LlamaServerState.notInstalled:
        return ('not installed', cs.onSurface.withValues(alpha: 0.55));
      case LlamaServerState.installing:
        return ('installing', cs.primary);
      case LlamaServerState.stopped:
        return ('stopped', cs.onSurface.withValues(alpha: 0.7));
      case LlamaServerState.starting:
        return ('starting', cs.primary);
      case LlamaServerState.running:
        return ('running', Colors.green.shade700);
      case LlamaServerState.crashed:
        return ('crashed', cs.error);
    }
  }
}

/// Full-screen log viewer for install / server output. Uses a scrolling
/// monospace area so the user can see apt progress bars + llama-server
/// load messages without them being clipped.
class _LlamaServerLogsScreen extends ConsumerStatefulWidget {
  const _LlamaServerLogsScreen();

  @override
  ConsumerState<_LlamaServerLogsScreen> createState() =>
      _LlamaServerLogsScreenState();
}

class _LlamaServerLogsScreenState
    extends ConsumerState<_LlamaServerLogsScreen> {
  final _scrollController = ScrollController();

  /// Only auto-scroll when the user is near the bottom. If they've
  /// scrolled up to read earlier lines, we shouldn't yank them back
  /// down on every log flush.
  static const _stickyPixels = 80.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(llamaServerLogsProvider);
    final cs = Theme.of(context).colorScheme;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final atBottom = (pos.maxScrollExtent - pos.pixels) <= _stickyPixels;
      if (!atBottom) return;
      _scrollController.animateTo(
        pos.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear',
            onPressed: () =>
                ref.read(llamaServerLogsProvider.notifier).clear(),
          ),
        ],
      ),
      body: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(12),
        child: logs.isEmpty
            ? Center(
                child: Text(
                  'No output yet.',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontFamily: 'monospace',
                  ),
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                itemCount: logs.length,
                itemBuilder: (ctx, i) => SelectableText(
                  logs[i],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFFD4D4D4),
                    height: 1.35,
                  ),
                ),
              ),
      ),
    );
  }
}
