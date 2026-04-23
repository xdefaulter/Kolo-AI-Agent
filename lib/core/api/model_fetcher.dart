import 'package:dio/dio.dart';
import 'provider.dart';

/// Fetches available models from a provider's /models endpoint.
/// Separated from AppDatabase to maintain storage layer purity.
class ModelFetcher {
  static Future<List<ModelConfig>> fetchModels(ProviderConfig provider) async {
    if (!provider.canFetchModels) return [];

    try {
      final dio = Dio(BaseOptions(
        followRedirects: true,
        maxRedirects: 5,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (status) => status != null && status < 400,
      ));
      final headers = <String, dynamic>{
        'Content-Type': 'application/json',
        ...provider.customHeaders,
      };
      if (provider.apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${provider.apiKey}';
      }
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (provider.apiKey.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer ${provider.apiKey}';
          }
          handler.next(options);
        },
      ));

      final response = await dio.get(
        provider.effectiveModelsUrl,
        options: Options(headers: headers),
      );

      final data = response.data as Map<String, dynamic>;
      final modelList = data['data'] as List<dynamic>? ?? [];

      return modelList.map((m) {
        final map = m as Map<String, dynamic>;
        final id = map['id'] as String? ?? 'unknown';
        return ModelConfig(
          modelId: id,
          displayName: id,
          maxTokens: 4096,
          isCustom: false,
          description: map['description'] as String?,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }
}
