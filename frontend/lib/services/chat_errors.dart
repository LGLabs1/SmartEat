import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// Maps any error raised while talking to Sage to a user-facing message that
/// is specific to the underlying cause. Different causes must never collapse
/// into the same generic apology — and the wording should still sound like a
/// helpful person, not a stack trace.
String describeChatError(Object error) {
  // ── Timeouts ───────────────────────────────────────────────────────────
  if (error is TimeoutException) {
    return '⏱️ Sorry — that one took too long'
        '${error.duration != null ? ' (over ${error.duration!.inSeconds}s)' : ''} '
        'and I had to let it go.\n\n'
        'The model is probably just having a heavy moment. Give it a few '
        'seconds and ask me again?';
  }

  // ── Typed API errors (cause is already known) ──────────────────────────
  if (error is ChatApiException) return _describeApiException(error);

  // ── Socket / HTTP transport errors ─────────────────────────────────────
  if (error is SocketException) return _describeSocket(error.message);
  if (error is http.ClientException) return _describeSocket(error.message);
  if (error is TlsException) {
    return '🔒 Hmm, the secure connection to the backend failed.\n\n'
        'Double-check the backend address I\'m talking to, then try me '
        'again.';
  }

  // ── Firebase auth ──────────────────────────────────────────────────────
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'user-token-expired':
      case 'invalid-user-token':
      case 'user-disabled':
        return '🔑 Looks like your session expired — sorry about that!\n\n'
            'Sign out and back in, and I\'ll pick up right where we left off.';
      case 'network-request-failed':
        return '📡 I couldn\'t reach Firebase just then. Check your internet '
            'and I\'ll try again with you.';
      default:
        return '🔑 Something went wrong with your sign-in (${error.code}).\n\n'
            'Try signing out and back in — that usually sorts it.';
    }
  }

  // ── Firestore / data layer ─────────────────────────────────────────────
  if (error is FirebaseException) {
    return '🗄️ I couldn\'t read your live numbers just now '
        '(${error.plugin} ${error.code}).\n\n'
        'Probably a wobbly connection — give it another go in a moment.';
  }

  // ── Malformed payload ──────────────────────────────────────────────────
  if (error is FormatException) {
    return '🧩 Oops — I got an unreadable reply from the backend.\n\n'
        'It probably restarted mid-request. Try that again?';
  }

  // ── Catch-all: keep the cause visible so repeats aren't identical ──────
  final type = error.runtimeType.toString();
  final detail = _firstLine(error.toString());
  return '⚠️ Well, that\'s an unexpected one ($type): $detail\n\n'
      'Give it another try — if it keeps happening, give the backend '
      'a quick restart.';
}

String _describeApiException(ChatApiException error) {
  final code = error.code;
  final status = error.statusCode;
  final serverMessage = error.message.trim();

  switch (code) {
    case 'network_unavailable':
      return _describeSocket(serverMessage);
    case 'gemini_not_configured':
      return '🔧 Sage\'s AI (Gemini) isn\'t configured on the backend yet.\n\n'
          'A GEMINI_API_KEY needs to be set there — everything else in '
          'SmartEat still works fine.';
    case 'gemini_invalid_key':
      return '🔑 Sage\'s AI (Gemini) rejected the server\'s API key.\n\n'
          'Ask whoever runs the backend to set a valid GEMINI_API_KEY and '
          'I\'ll be right back with you 💚';
    case 'gemini_quota':
      return '🚦 Sage\'s AI hit its rate/quota limit just now.\n\n'
          'It usually resets on its own shortly — give me a few minutes '
          'and ask again.';
    case 'gemini_unreachable':
      return '🤖 I can\'t reach Sage\'s AI service at the moment.\n\n'
          'It\'s probably a temporary blip on the provider side — pop the '
          'question again in a moment?';
    case 'gemini_connection_lost':
      return '🔌 The link to my AI dropped halfway through that answer.\n\n'
          'Probably a transient hiccup — pop the question again?';
    case 'gemini_error':
      return '🤖 The model threw a wobble'
          '${serverMessage.isNotEmpty ? ': $serverMessage' : '.'}\n\n'
          'Try rephrasing and I\'ll have another go.';
    case 'sage_disabled':
      return '🌿 Sage is disabled in this demo.\n\n'
          'Analytics, inventory, finance, and other SmartEat features '
          'remain available.';
    case 'AI service unavailable':
    case 'ollama_unavailable':
      return '🤖 Sage\'s AI service is offline at the moment.\n\n'
          'It should be back shortly — try me again in a bit 💚';
    case 'ollama_timeout':
    case 'AI request timed out':
    case 'ai_timeout':
      return '⏱️ The model is being slow to answer right now — it may still '
          'be warming up.\n\nGive it a breather and ask me again.';
    case 'ollama_connection_lost':
      return '🔌 The link to my brain dropped halfway through that answer.\n\n'
          'Probably a transient hiccup — pop the question again?';
    case 'ollama_host_unreachable':
      return '🤖 I can\'t find the AI service at the configured address.\n\n'
          'Worth checking the backend config — I\'ll wait.';
    case 'ollama_error':
      return '🤖 The model threw a wobble'
          '${serverMessage.isNotEmpty ? ': $serverMessage' : '.'}\n\n'
          'Try rephrasing and I\'ll have another go.';
    case 'invalid_message':
      return '💬 I\'d love to help — I just need a bit more to go on.\n\n'
          'Try naming a period, metric, menu item, order, or stock item.';
    case 'message_too_long':
      return '📝 That\'s a whole essay in one message! 😅\n\n'
          'Could you trim it down and send it again?';
    case 'empty_response':
      return '🤔 Hmm, that came back completely empty — not like me!\n\n'
          'Try rephrasing your question and I\'ll give it another shot.';
    case 'server_error':
      return status != null && status >= 500
          ? '⚠️ I hit a snag on the backend'
              '${serverMessage.isNotEmpty ? ' ($serverMessage)' : ''}.\n\n'
              'Try me again in a moment — if it persists, a quick backend '
              'restart should do the trick.'
          : '⚠️ I couldn\'t quite process that'
              '${serverMessage.isNotEmpty ? ': $serverMessage' : '.'}';
    case 'status_unavailable':
      return '📡 I couldn\'t check my own status just then'
          '${serverMessage.isNotEmpty ? ' ($serverMessage)' : ''}.';
    default:
      break;
  }

  // Unknown code — fall back to HTTP status so different causes stay apart.
  if (status == 401 || status == 403) {
    return '🔑 Your session is no longer valid — sorry about that!\n\n'
        'Sign out and back in, and we\'ll carry on.';
  }
  if (status == 404) {
    return '🧭 The backend doesn\'t seem to know this chat route (404).\n\n'
        'It\'s probably out of date — a quick restart should fix it.';
  }
  if (status == 429) {
    return '🚦 Whoa, easy there — too many requests at once.\n\n'
        'Give it a few seconds before asking again.';
  }
  if (status != null && status >= 500) {
    return '⚠️ The backend tripped over itself ($status)'
        '${serverMessage.isNotEmpty ? ': $serverMessage' : ''}.\n\n'
        'Try again shortly — if it keeps happening, restart it for me?';
  }

  return '💬 I couldn\'t finish that one'
      '${code.isNotEmpty ? ' [$code]' : ''}'
      '${serverMessage.isNotEmpty ? ': $serverMessage' : '.'}\n\n'
      'Try putting it as a business question about sales, stock, menu, or '
      'finances.';
}

String _describeSocket(String message) {
  final m = message.toLowerCase();
  if (m.contains('refused')) {
    return '📡 I can\'t reach the SmartEat backend — it looks like nothing is '
        'listening on the backend address.\n\n'
        'Start the backend (`npm run dev` in the backend folder) and I\'ll '
        'be right here waiting 💚';
  }
  if (m.contains('failed host lookup') ||
      m.contains('nodename nor servname') ||
      m.contains('no address associated')) {
    return '📡 Looks like you\'re offline — I can\'t even resolve the '
        'backend address.\n\n'
        'Check your Wi-Fi and come back to me, I\'m not going anywhere.';
  }
  if (m.contains('reset') || m.contains('broken pipe')) {
    return '🔌 Our connection got cut while I was thinking.\n\n'
        'The backend may have restarted — try that again for me?';
  }
  if (m.contains('timed out') || m.contains('timeout')) {
    return '⏱️ The backend took too long to pick up — it might be busy '
        'starting up.\n\nTry again in a moment?';
  }
  if (m.contains('unreachable')) {
    return '📡 I can\'t reach the backend address from this device.\n\n'
        'Check that it\'s running and that the URL in the app config '
        'matches it.';
  }
  return '📡 I couldn\'t reach the backend ($message).\n\n'
      'Check your connection and that the backend is running, then come '
      'back to me.';
}

String _firstLine(String text) {
  final line = text.split(RegExp(r'\r?\n')).first.trim();
  if (line.length > 140) return '${line.substring(0, 140)}…';
  return line;
}
