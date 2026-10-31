import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/env.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Thin wrapper around Dio for the NTP API.
///
/// The backend reports most failures as HTTP 200 with `{ result: false,
/// message }`, so every response goes through [_unwrap] which turns those
/// into [ApiException]s.
class ApiClient {
  ApiClient(this._tokenStorage, {String? baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? Env.apiBaseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 60),
            headers: {'Content-Type': 'application/json'},
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _tokenStorage.token;
          if (token != null) {
            options.headers['x-access-token'] = token;
          }
          handler.next(options);
        },
        onError: (error, handler) {
          final code = error.response?.statusCode;
          if ((code == 401 || code == 403) &&
              !error.requestOptions.path.startsWith('/auth/login')) {
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(requestBody: false, responseBody: false),
      );
    }
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;

  /// Called when the server rejects the token (expired / revoked).
  VoidCallback? onUnauthorized;

  String get baseUrl => _dio.options.baseUrl;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? data}) =>
      _send(() => _dio.post(path, data: data));

  Future<dynamic> put(String path, {Object? data}) =>
      _send(() => _dio.put(path, data: data));

  Future<dynamic> delete(String path, {Object? data}) =>
      _send(() => _dio.delete(path, data: data));

  /// GET an endpoint that returns a JSON array and map each item.
  Future<List<T>> getList<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? query,
  }) async {
    final data = await get(path, query: query);
    if (data is! List) {
      return [];
    }
    return data
        .whereType<Map>()
        .map((e) => fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// GET an endpoint that returns a single JSON object.
  Future<T> getOne<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson,
  ) async {
    final data = await get(path);
    if (data is! Map) {
      throw const ApiException('ไม่พบข้อมูล');
    }
    return fromJson(Map<String, dynamic>.from(data));
  }

  Future<dynamic> postMultipart(String path, FormData form) => _send(
        () => _dio.post(
          path,
          data: form,
          options: Options(contentType: 'multipart/form-data'),
        ),
      );

  /// Downloads a file (e.g. a server generated PDF) with auth headers and
  /// returns the local file.
  Future<File> download(String path, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    try {
      final res = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      await file.writeAsBytes(res.data ?? const []);
      return file;
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Absolute URL for static resources such as car images.
  String url(String path) => '$baseUrl$path';

  Map<String, String> get authHeaders {
    final token = _tokenStorage.token;
    return token == null ? const {} : {'x-access-token': token};
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final res = await request();
      return _unwrap(res.data);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  dynamic _unwrap(dynamic data) {
    if (data is Map) {
      if (data['result'] == false) {
        throw ApiException(_message(data) ?? 'เกิดข้อผิดพลาด');
      }
      // crud.findOne / findAll report errors as a bare `{ message }`.
      if (data.length == 1 && data.containsKey('message')) {
        final msg = data['message']?.toString() ?? '';
        if (msg.startsWith('Cannot find') || msg.startsWith('Some error')) {
          throw ApiException(msg);
        }
      }
    }
    return data;
  }

  ApiException _mapDioError(DioException e) {
    final res = e.response;
    if (res == null) {
      return const ApiException(
        'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้ กรุณาตรวจสอบอินเทอร์เน็ต',
      );
    }
    final code = res.statusCode;
    if (code == 401 || code == 403) {
      return ApiException(
        'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่',
        statusCode: code,
      );
    }
    final msg = res.data is Map ? _message(res.data as Map) : null;
    return ApiException(msg ?? 'เกิดข้อผิดพลาด ($code)', statusCode: code);
  }

  String? _message(Map data) {
    return data['message']?.toString();
  }
}
