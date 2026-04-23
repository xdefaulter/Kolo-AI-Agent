import 'package:dio/dio.dart';

/// Shared Dio instance for non-authenticated HTTP requests.
/// Reuses connection pools across the app.
class SharedDio {
  static Dio? _instance;

  static Dio get instance {
    _instance ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      validateStatus: (s) => s != null && s < 500,
    ));
    return _instance!;
  }

  SharedDio._();
}
