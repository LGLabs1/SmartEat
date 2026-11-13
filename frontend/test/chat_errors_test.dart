import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/services/api_service.dart';
import 'package:smarteat/services/chat_errors.dart';

void main() {
  test('different causes produce different messages', () {
    final messages = <String>[
      describeChatError(TimeoutException('AI response took too long',
          const Duration(seconds: 65))),
      describeChatError(const ChatApiException(
          code: 'gemini_unreachable', message: 'down', statusCode: 503)),
      describeChatError(const ChatApiException(
          code: 'ai_timeout', message: 'slow', statusCode: 504)),
      describeChatError(const ChatApiException(
          code: 'gemini_connection_lost', message: 'reset', statusCode: 502)),
      describeChatError(const ChatApiException(
          code: 'invalid_message', message: 'empty', statusCode: 400)),
      describeChatError(const ChatApiException(
          code: 'empty_response', message: 'blank', statusCode: 502)),
      describeChatError(const ChatApiException(
          code: 'weird_new_code', message: 'boom', statusCode: 418)),
      describeChatError(const SocketException('Connection refused')),
      describeChatError(const SocketException('Failed host lookup')),
      describeChatError(const FormatException('Unexpected character')),
      describeChatError(StateError('bad state')),
    ];

    final unique = messages.toSet();
    expect(unique.length, messages.length,
        reason: 'each distinct cause must get its own message');
  });

  test('points at the right fix for each cause', () {
    expect(
      describeChatError(const SocketException('Connection refused')),
      contains('backend'),
    );
    expect(
      describeChatError(const ChatApiException(
          code: 'gemini_unreachable', message: 'down', statusCode: 503)),
      contains('AI service'),
    );
    expect(
      describeChatError(TimeoutException('slow', const Duration(seconds: 65))),
      contains('too long'),
    );
    expect(
      describeChatError(const ChatApiException(
          code: 'server_error', message: 'kaboom', statusCode: 500)),
      contains('kaboom'),
    );
    expect(
      describeChatError(const ChatApiException(
          code: 'unauthorized', message: 'nope', statusCode: 401)),
      contains('session'),
    );
  });

  test('unknown errors keep their cause visible in the message', () {
    final message = describeChatError(StateError('cache miss while building'));

    expect(message, contains('StateError'));
    expect(message, contains('cache miss while building'));
  });
}
