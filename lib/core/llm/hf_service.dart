import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// A GGUF file hosted in a HuggingFace repository. Just enough metadata
/// for the browser UI to show size + for the downloader to verify the
/// file's `lfs.sha256` after transfer.
class HfRepoFile {
  final String repoId;
  final String filename;
  final int? sizeBytes;
  final String? sha256;

  const HfRepoFile({
    required this.repoId,
    required this.filename,
    this.sizeBytes,
    this.sha256,
  });

  /// Direct download URL. HF's `resolve/main/` path 302s to the actual
  /// LFS CDN; Dio follows that automatically when `followRedirects` is on.
  String get downloadUrl =>
      'https://huggingface.co/$repoId/resolve/main/$filename';
}

sealed class HfDownloadEvent {
  const HfDownloadEvent();
}

class HfDownloadProgress extends HfDownloadEvent {
  final int received;
  final int total;
  const HfDownloadProgress(this.received, this.total);
  double get fraction => total <= 0 ? 0 : received / total;
}

class HfDownloadComplete extends HfDownloadEvent {
  final String localPath;
  const HfDownloadComplete(this.localPath);
}

class HfDownloadError extends HfDownloadEvent {
  final String message;
  const HfDownloadError(this.message);
}

class HfDownloadCancelled extends HfDownloadEvent {
  const HfDownloadCancelled();
}

/// HuggingFace Hub client: list `.gguf` files in a repo + fetch them
/// with resume support + SHA256 verification.
///
/// The gated-model path uses a user-owned token stored in the platform
/// keystore (no env-var coupling), so the UI can add a token after the
/// first failed public fetch without restarting the app.
class HfService {
  HfService._();
  static final HfService instance = HfService._();

  static const _tokenKey = 'hf_token_v1';
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    // Model files are big; DON'T cap receiveTimeout at the default 2min.
    // Give slow cellular + large-file downloads plenty of headroom.
    receiveTimeout: const Duration(minutes: 30),
    followRedirects: true,
    maxRedirects: 5,
  ));

  CancelToken? _cancelToken;

  Future<String?> getToken() => _secureStorage.read(key: _tokenKey);

  Future<void> setToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _secureStorage.delete(key: _tokenKey);
    } else {
      await _secureStorage.write(key: _tokenKey, value: token);
    }
  }

  /// Fetch the repo's file tree and return only `.gguf` siblings.
  /// Uses the `/api/models/{repo}/tree/main` endpoint because it gives
  /// us LFS size + SHA256 which the lighter `/api/models/{repo}` doesn't.
  Future<List<HfRepoFile>> listGgufFiles(String repoId) async {
    final token = await getToken();
    try {
      final response = await _dio.getUri<List<dynamic>>(
        Uri.parse(
          'https://huggingface.co/api/models/$repoId/tree/main?recursive=true',
        ),
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode == 404) {
        throw HfException('Repo not found: $repoId');
      }
      if (response.statusCode == 401) {
        throw HfException(
          'Repo requires a token. Open HF settings and paste a read token.',
        );
      }
      if (response.statusCode != 200) {
        throw HfException('HF API error ${response.statusCode}');
      }
      final data = response.data ?? const [];
      final files = <HfRepoFile>[];
      for (final entry in data) {
        if (entry is! Map) continue;
        if (entry['type'] != 'file') continue;
        final path = entry['path']?.toString() ?? '';
        if (!path.toLowerCase().endsWith('.gguf')) continue;
        final size = (entry['size'] as num?)?.toInt();
        // LFS pointer files have the real SHA inside `lfs.sha256`; plain
        // files use `blob_id` which is a git hash, not content SHA.
        final lfs = entry['lfs'];
        final sha = lfs is Map ? lfs['sha256']?.toString() : null;
        files.add(HfRepoFile(
          repoId: repoId,
          filename: path,
          sizeBytes: size,
          sha256: sha,
        ));
      }
      // Sort smallest-first so the tiny quants show up top.
      files.sort(
        (a, b) => (a.sizeBytes ?? 0).compareTo(b.sizeBytes ?? 0),
      );
      return files;
    } on DioException catch (e) {
      throw HfException('Network error: ${e.message ?? e.type.name}');
    }
  }

  /// Absolute on-disk path where [file] will live.
  /// `/data/data/<pkg>/files/models/<repo_slug>/<filename>`.
  Future<String> targetPath(HfRepoFile file) async {
    final base = await getApplicationSupportDirectory();
    final slug = file.repoId.replaceAll('/', '__');
    return '${base.parent.path}/files/models/$slug/${file.filename}';
  }

  /// Stream a download with resume + progress + optional SHA256 verify.
  ///
  /// Cancellation: [cancelActive] flips the internal Dio CancelToken,
  /// which surfaces as an [HfDownloadCancelled] event + partial file
  /// left on disk so the next call resumes from the same byte offset.
  Stream<HfDownloadEvent> download(HfRepoFile file) async* {
    final controller = StreamController<HfDownloadEvent>();
    _cancelToken = CancelToken();

    // Let the caller start listening before we kick off network I/O so
    // the initial progress event isn't lost to a race.
    unawaited(_runDownload(file, controller));
    yield* controller.stream;
  }

  Future<void> _runDownload(
    HfRepoFile file,
    StreamController<HfDownloadEvent> out,
  ) async {
    try {
      final destPath = await targetPath(file);
      final dest = File(destPath);
      await dest.parent.create(recursive: true);

      // Resume support: if a partial file exists, ask the server for
      // the remaining bytes via a Range header. LFS backends behave
      // correctly here; a small minority refuse and we then restart
      // from scratch after a fresh 200.
      final existingLen =
          await dest.exists() ? await dest.length() : 0;
      final token = await getToken();
      final headers = <String, String>{
        if (token != null && token.isNotEmpty)
          'Authorization': 'Bearer $token',
        if (existingLen > 0) 'Range': 'bytes=$existingLen-',
      };

      IOSink? sink;
      int received = existingLen;

      final response = await _dio.getUri<ResponseBody>(
        Uri.parse(file.downloadUrl),
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          validateStatus: (s) => s != null && s < 500,
        ),
        cancelToken: _cancelToken,
      );

      if (response.statusCode == 416) {
        // Already fully downloaded per the server's view — treat as done
        // after we've verified what's on disk.
      } else if (response.statusCode == 200) {
        // Server refused our Range — restart from scratch.
        if (existingLen > 0) {
          await dest.delete();
          received = 0;
        }
      } else if (response.statusCode == 206) {
        // Partial content — our Range was honoured. Good.
      } else if (response.statusCode == 404) {
        out.add(HfDownloadError('File not found on HF: ${file.filename}'));
        await out.close();
        return;
      } else if (response.statusCode == 401) {
        out.add(HfDownloadError(
          'Authentication required. Paste a read token in HF settings.',
        ));
        await out.close();
        return;
      } else {
        out.add(HfDownloadError('Unexpected HTTP ${response.statusCode}'));
        await out.close();
        return;
      }

      // Total size: prefer the metadata value we cached from the
      // repo listing. HF's resume path returns a `Content-Length` of
      // just the remaining bytes, so adding it to `received` gives us
      // the true total when metadata wasn't available.
      final contentLen = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      final total = file.sizeBytes ??
          (contentLen != null ? received + contentLen : 0);

      if (response.statusCode != 416) {
        sink = dest.openWrite(mode: FileMode.append);
        // Emit at most one progress event per 100ms OR per 256 KB,
        // whichever comes first. Dio yields 16 KB chunks on fast WiFi
        // (~6000/s), which floods the UI with setState calls and tanks
        // frame rate. 10 Hz is plenty for a human-readable progress bar.
        var lastEmitAt = DateTime.now();
        var lastEmitBytes = received;
        const emitInterval = Duration(milliseconds: 100);
        const emitByteThreshold = 256 * 1024;
        await for (final chunk in response.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastEmitAt) >= emitInterval ||
              received - lastEmitBytes >= emitByteThreshold) {
            out.add(HfDownloadProgress(received, total));
            lastEmitAt = now;
            lastEmitBytes = received;
          }
        }
        await sink.flush();
        await sink.close();
        // Always emit a final 100%-of-known-total event so the UI
        // doesn't leave the bar stuck at 99.x%.
        out.add(HfDownloadProgress(received, total));
      }

      // Verify SHA256 if HF gave us one. Skipped for repos without LFS
      // metadata; in practice all non-trivial GGUFs are LFS-hosted.
      if (file.sha256 != null && file.sha256!.isNotEmpty) {
        out.add(const HfDownloadProgress(-1, -1)); // sentinel "verifying"
        final actual = await _sha256(dest);
        if (actual != file.sha256) {
          out.add(HfDownloadError(
            'SHA256 mismatch. Expected ${file.sha256}, got $actual. '
            'Delete the file and retry.',
          ));
          await out.close();
          return;
        }
      }

      out.add(HfDownloadComplete(destPath));
      await out.close();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        out.add(const HfDownloadCancelled());
      } else {
        out.add(HfDownloadError('Network error: ${e.message ?? e.type.name}'));
      }
      await out.close();
    } catch (e, st) {
      debugPrint('[hf] download failed: $e\n$st');
      out.add(HfDownloadError('Download failed: $e'));
      await out.close();
    } finally {
      _cancelToken = null;
    }
  }

  void cancelActive() {
    final t = _cancelToken;
    if (t != null && !t.isCancelled) {
      t.cancel('User cancelled download');
    }
  }

  /// Stream-hashed SHA256 so we don't hold the full multi-GB file in
  /// memory during verify. Uses a one-shot sink that captures the
  /// final `Digest` the hasher emits on close.
  static Future<String> _sha256(File f) async {
    final completer = Completer<Digest>();
    final sink = _DigestSink(completer);
    final hasher = sha256.startChunkedConversion(sink);
    await for (final chunk in f.openRead()) {
      hasher.add(chunk);
    }
    hasher.close();
    return (await completer.future).toString();
  }
}

/// Minimal `Sink<Digest>` that latches the first digest it receives
/// into a [Completer]. `sha256.startChunkedConversion` calls `.add`
/// exactly once (on close), so this is equivalent to the `AccumulatorSink`
/// pattern without pulling in package:convert.
class _DigestSink implements Sink<Digest> {
  final Completer<Digest> _completer;
  _DigestSink(this._completer);

  @override
  void add(Digest data) {
    if (!_completer.isCompleted) _completer.complete(data);
  }

  @override
  void close() {
    if (!_completer.isCompleted) {
      _completer.completeError(StateError('digest sink closed without data'));
    }
  }
}

class HfException implements Exception {
  final String message;
  HfException(this.message);
  @override
  String toString() => message;
}
