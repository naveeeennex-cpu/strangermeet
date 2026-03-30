import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';

import '../config/constants.dart';
import 'storage_service.dart';

// Conditionally import for mobile SSL fix
import 'api_service_mobile.dart' if (dart.library.html) 'api_service_web.dart' as platform;

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  Dio get dio => _dio;
  final StorageService _storageService = StorageService();

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 45),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Fix SSL/TLS issues on Android mobile data
    platform.configureDio(_dio);

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storageService.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          // Retry up to 2 times on connection errors (mobile data flakiness)
          final retryCount = error.requestOptions.extra['retryCount'] ?? 0;
          if (retryCount < 2 &&
              (error.type == DioExceptionType.connectionError ||
               error.type == DioExceptionType.connectionTimeout ||
               error.type == DioExceptionType.sendTimeout ||
               error.type == DioExceptionType.receiveTimeout)) {
            try {
              await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
              error.requestOptions.extra['retryCount'] = retryCount + 1;
              final response = await _dio.fetch(error.requestOptions);
              handler.resolve(response);
              return;
            } catch (_) {}
          }
          handler.next(error);
        },
      ),
    );
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get(path, queryParameters: queryParameters);
      return response;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      return response;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      return response;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      return response;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> uploadFile(
    String path, {
    required FormData formData,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
        ),
      );
      return response;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  ApiException _handleError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('Connection timed out. Please try again.');
      case DioExceptionType.connectionError:
        return ApiException('No internet connection. Please check your network.');
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final data = error.response?.data;
        String message = 'Something went wrong.';
        if (data is Map<String, dynamic>) {
          message = data['message'] ?? data['detail'] ?? message;
        }
        if (statusCode == 401) {
          message = 'Unauthorized. Please login again.';
        } else if (statusCode == 403) {
          message = 'You do not have permission to perform this action.';
        } else if (statusCode == 404) {
          message = 'Resource not found.';
        } else if (statusCode == 422) {
          message = data is Map ? (data['message'] ?? 'Validation error.') : 'Validation error.';
        } else if (statusCode != null && statusCode >= 500) {
          message = 'Server error. Please try again later.';
        }
        return ApiException(message, statusCode: statusCode);
      default:
        return ApiException('An unexpected error occurred.');
    }
  }
}
