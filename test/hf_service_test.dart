import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/llm/hf_service.dart';

void main() {
  group('HfRepoFile', () {
    test('builds the resolve/main download URL', () {
      const f = HfRepoFile(
        repoId: 'bartowski/Qwen2.5-3B-Instruct-GGUF',
        filename: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      );
      expect(
        f.downloadUrl,
        'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/'
        'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      );
    });

    test('HfDownloadProgress.fraction handles zero total safely', () {
      const p = HfDownloadProgress(500, 0);
      expect(p.fraction, 0);
    });

    test('HfDownloadProgress.fraction computes normally', () {
      const p = HfDownloadProgress(500, 1000);
      expect(p.fraction, 0.5);
    });
  });
}
