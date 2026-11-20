import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PasswordResetApiException implements Exception {
  const PasswordResetApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryAfterSeconds,
  });

  final int? statusCode;
  final String code;
  final String message;
  final int? retryAfterSeconds;

  @override
  String toString() => message;
}

class PasswordResetRequestResult {
  const PasswordResetRequestResult({
    required this.message,
    required this.retryAfterSeconds,
  });

  final String message;
  final int retryAfterSeconds;
}

class PasswordResetVerification {
  const PasswordResetVerification({
    required this.resetToken,
    this.expiresAt,
  });

  final String resetToken;
  final DateTime? expiresAt;
}

class PasswordResetApi {
  PasswordResetApi({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = _trimTrailingSlash(baseUrl ?? resolveDefaultBaseUrl());

  static const String deployedBaseUrl =
      'https://smarteat-backend-n5ta.onrender.com/api';
  static const Duration _timeout = Duration(seconds: 45);

  static String resolveDefaultBaseUrl() {
    const configured = String.fromEnvironment('PASSWORD_RESET_API_BASE_URL');
    if (configured.trim().isNotEmpty) return configured.trim();
    if (!kDebugMode) return deployedBaseUrl;
    if (kIsWeb) return 'http://localhost:3000/api';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000/api';
    }
    return 'http://localhost:3000/api';
  }

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<PasswordResetRequestResult> requestCode({
    required String email,
    required String channel,
  }) async {
    final data = await _post('auth/password-reset/request', {
      'email': email,
      'channel': channel,
    });
    return PasswordResetRequestResult(
      message: (data['message'] ?? 'Verification code sent.').toString(),
      retryAfterSeconds: _asInt(data['retryAfterSeconds']) ?? 60,
    );
  }

  Future<PasswordResetVerification> verifyCode({
    required String email,
    required String code,
  }) async {
    final data = await _post('auth/password-reset/verify', {
      'email': email,
      'code': code,
    });
    final token = (data['resetToken'] ?? '').toString();
    if (token.isEmpty) {
      throw const PasswordResetApiException(
        code: 'invalid_response',
        message: 'The server returned an invalid verification response.',
      );
    }
    final expiresAtMillis = _asInt(data['expiresAt']);
    return PasswordResetVerification(
      resetToken: token,
      expiresAt: expiresAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAtMillis),
    );
  }

  Future<String> confirmReset({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    final data = await _post('auth/password-reset/confirm', {
      'email': email,
      'resetToken': resetToken,
      'newPassword': newPassword,
    });
    return (data['message'] ?? 'Password reset successfully.').toString();
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/$path'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      final data = _decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data;
      }

      final message = (data['error'] ??
              data['message'] ??
              'Request failed. Please try again.')
          .toString();
      throw PasswordResetApiException(
        statusCode: response.statusCode,
        code: (data['code'] ?? 'request_failed').toString(),
        message: message,
        retryAfterSeconds: _asInt(data['retryAfterSeconds']),
      );
    } on TimeoutException {
      throw const PasswordResetApiException(
        code: 'timeout',
        message: 'The request timed out. Please try again.',
      );
    } on http.ClientException {
      throw const PasswordResetApiException(
        code: 'network_error',
        message: 'Unable to reach the server. Check your connection.',
      );
    }
  }

  Map<String, dynamic> _decode(String body) {
    if (body.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const {};
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _trimTrailingSlash(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
