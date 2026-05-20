import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/llm/hf_service.dart';
import '../../core/ui/toast.dart';

/// Browse a HuggingFace repo for .gguf files and download the one the
/// user picks, streaming progress + verifying SHA256 on completion.
/// Returns the local path via `Navigator.pop` so the caller can plug it
/// into the active provider's `modelPath`.
class HfBrowserScreen extends ConsumerStatefulWidget {
  /// Pre-populated repo id so a "change model" flow doesn't make the
  /// user retype the same owner/repo.
  final String? initialRepoId;

  const HfBrowserScreen({super.key, this.initialRepoId});

  @override
  ConsumerState<HfBrowserScreen> createState() => _HfBrowserScreenState();
}

class _HfBrowserScreenState extends ConsumerState<HfBrowserScreen> {
  final _repoController = TextEditingController();
  final _tokenController = TextEditingController();
  List<HfRepoFile>? _files;
  bool _loadingFiles = false;
  String? _listError;

  HfRepoFile? _activeDownload;
  StreamSubscription<HfDownloadEvent>? _downloadSub;
  int _received = 0;
  int _total = 0;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _repoController.text = widget.initialRepoId ?? '';
    _loadToken();
  }

  Future<void> _loadToken() async {
    final t = await HfService.instance.getToken();
    if (t != null && mounted) {
      _tokenController.text = t;
    }
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    HfService.instance.cancelActive();
    _repoController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final raw = _repoController.text.trim();
    if (raw.isEmpty) return;
    // Normalise "https://huggingface.co/owner/repo" → "owner/repo".
    var repoId = raw;
    if (repoId.startsWith('http')) {
      final uri = Uri.tryParse(repoId);
      if (uri != null && uri.host.contains('huggingface')) {
        final parts = uri.pathSegments
            .where((s) => s.isNotEmpty && s != 'tree' && s != 'main')
            .toList();
        if (parts.length >= 2) repoId = '${parts[0]}/${parts[1]}';
      }
    }
    setState(() {
      _loadingFiles = true;
      _listError = null;
      _files = null;
    });
    try {
      final files = await HfService.instance.listGgufFiles(repoId);
      if (!mounted) return;
      setState(() {
        _files = files;
        _loadingFiles = false;
      });
      if (files.isEmpty) {
        showKoloToast(
          context,
          'No .gguf files in this repo. Try a repo that ends with "-GGUF".',
          kind: ToastKind.warning,
        );
      }
    } on HfException catch (e) {
      if (!mounted) return;
      setState(() {
        _listError = e.message;
        _loadingFiles = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listError = e.toString();
        _loadingFiles = false;
      });
    }
  }

  Future<void> _saveToken() async {
    await HfService.instance.setToken(_tokenController.text.trim());
    if (!mounted) return;
    showKoloToast(context, 'HF token saved.');
  }

  Future<void> _download(HfRepoFile file) async {
    // Only one download at a time — downloads are hundreds of MB each
    // and running multiple over mobile data is a bad default.
    if (_activeDownload != null) return;
    Haptics.light();
    setState(() {
      _activeDownload = file;
      _received = 0;
      _total = file.sizeBytes ?? 0;
      _verifying = false;
    });
    _downloadSub = HfService.instance.download(file).listen((event) {
      if (!mounted) return;
      if (event is HfDownloadProgress) {
        setState(() {
          if (event.received == -1 && event.total == -1) {
            _verifying = true;
          } else {
            _received = event.received;
            _total = event.total;
          }
        });
      } else if (event is HfDownloadComplete) {
        _downloadSub = null;
        if (mounted) {
          Navigator.of(context).pop(event.localPath);
        }
      } else if (event is HfDownloadCancelled) {
        setState(() {
          _activeDownload = null;
          _verifying = false;
        });
        showKoloToast(context, 'Download cancelled.', kind: ToastKind.info);
      } else if (event is HfDownloadError) {
        setState(() {
          _activeDownload = null;
          _verifying = false;
        });
        showKoloToast(context, event.message, kind: ToastKind.error);
      }
    });
  }

  void _cancelDownload() {
    HfService.instance.cancelActive();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Download model from Hugging Face')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Paste an HF repo id (`owner/repo`) or a full HF URL. '
            'Repos named like `Qwen/Qwen2.5-3B-Instruct-GGUF` or '
            '`bartowski/Llama-3.2-3B-Instruct-GGUF` work out of the box.',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _repoController,
                  decoration: const InputDecoration(
                    labelText: 'Repo id',
                    hintText: 'bartowski/Qwen2.5-3B-Instruct-GGUF',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _browse(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _loadingFiles ? null : _browse,
                child: const Text('Browse'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('HF token (optional, for gated models)'),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tokenController,
                      decoration: const InputDecoration(
                        labelText: 'hf_...',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saveToken,
                    child: const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Stored in the device keystore. Only sent in '
                'Authorization headers to huggingface.co.',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingFiles)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )),
          if (_listError != null)
            Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _listError!,
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
            ),
          if (_files != null && _files!.isNotEmpty) ...[
            Text(
              '${_files!.length} GGUF file${_files!.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ..._files!.map((f) => _FileTile(
                  file: f,
                  isDownloading: identical(_activeDownload, f),
                  onDownload: () => _download(f),
                )),
          ],
          if (_activeDownload != null) ...[
            const Divider(height: 32),
            _DownloadPanel(
              file: _activeDownload!,
              received: _received,
              total: _total,
              verifying: _verifying,
              onCancel: _cancelDownload,
            ),
          ],
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final HfRepoFile file;
  final bool isDownloading;
  final VoidCallback onDownload;

  const _FileTile({
    required this.file,
    required this.isDownloading,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(
          file.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        subtitle: Text(_humanSize(file.sizeBytes)),
        trailing: FilledButton.tonalIcon(
          onPressed: isDownloading ? null : onDownload,
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Download'),
        ),
      ),
    );
  }

  static String _humanSize(int? bytes) {
    if (bytes == null || bytes <= 0) return 'unknown size';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
  }
}

class _DownloadPanel extends StatelessWidget {
  final HfRepoFile file;
  final int received;
  final int total;
  final bool verifying;
  final VoidCallback onCancel;

  const _DownloadPanel({
    required this.file,
    required this.received,
    required this.total,
    required this.verifying,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fraction = total <= 0 ? null : received / total;
    return Card(
      color: cs.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    verifying
                        ? 'Verifying SHA256...'
                        : 'Downloading ${file.filename}',
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined),
                  tooltip: 'Cancel',
                  onPressed: verifying ? null : onCancel,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: verifying ? null : fraction),
            const SizedBox(height: 6),
            Text(
              verifying
                  ? 'Hashing the file...'
                  : '${_fmt(received)} / ${_fmt(total)}'
                      '${fraction == null ? '' : ' (${(fraction * 100).toStringAsFixed(1)}%)'}',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.7),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
  }
}
