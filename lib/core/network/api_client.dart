import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_store.dart';
import '../constants/app_constants.dart';

/// Kliyan HTTP santral pou tout apèl API.
class ApiClient {
  ApiClient(this._tokenStore) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));
    // Dezaktive keep-alive — evite "unsolicited response" bug ak WARP/VPN
    // proxies ki entèfere ak koneksyon reyitilize.
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.maxConnectionsPerHost = 4;
        client.idleTimeout = const Duration(seconds: 1);
        return client;
      },
    );
    _dio.interceptors.add(_AuthInterceptor(_tokenStore));
    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: false,
      responseBody: true,
      error: true,
      logPrint: (msg) {
        try { stderr.writeln('[dio] $msg'); } catch (_) {}
      },
    ));
  }

  final TokenStore _tokenStore;
  late final Dio _dio;

  Dio get dio => _dio;

  /// Mete `X-Store-Id` header pou tout pwochen rekèt.
  void setActiveStoreId(String? storeId) {
    if (storeId == null) {
      _dio.options.headers.remove('X-Store-Id');
    } else {
      _dio.options.headers['X-Store-Id'] = storeId;
    }
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._tokenStore);
  final TokenStore _tokenStore;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStore.read();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      await _tokenStore.clear();
    }
    handler.next(err);
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(tokenStoreProvider));
});
