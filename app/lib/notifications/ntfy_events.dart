import 'dart:convert';

class NtfyMessage {
  const NtfyMessage({
    required this.id,
    required this.topic,
    required this.title,
    required this.message,
  });

  final String id;
  final String topic;
  final String? title;
  final String? message;

  factory NtfyMessage.fromJson(Map<String, dynamic> json) {
    return NtfyMessage(
      id: json['id'] as String? ?? '',
      topic: json['topic'] as String? ?? '',
      title: json['title'] as String?,
      message: json['message'] as String?,
    );
  }
}

class NtfyParseResult {
  const NtfyParseResult(this.messages, this.remainder);

  /// Completed, line-broken messages found in the chunk.
  final List<NtfyMessage> messages;

  /// Trailing bytes that did not yet end with a newline; keep for next chunk.
  final String remainder;
}

/// Parses one arbitrary chunk of an ntfy JSON-event stream.
///
/// ntfy (v2.28) serves subscription events as newline-delimited JSON on
/// `GET /{topic}/json`; each line is one object over a persistent connection.
/// This parser consumes complete lines and returns any unfinished tail as
/// [NtfyParseResult.remainder].
NtfyParseResult parseNtfyEvents(String chunk) {
  final lastNewline = chunk.lastIndexOf('\n');
  if (lastNewline < 0) {
    return NtfyParseResult(const [], chunk);
  }
  final completePart = chunk.substring(0, lastNewline);
  final remainder = chunk.substring(lastNewline + 1);
  final messages = <NtfyMessage>[];
  if (completePart.isNotEmpty) {
    for (final line in completePart.split('\n')) {
      final message = tryParseNtfyMessageLine(line);
      if (message != null) {
        messages.add(message);
      }
    }
  }
  return NtfyParseResult(messages, remainder);
}

/// Decodes a single newline-delimited JSON event line. Returns null for
/// non-message housekeeping events (`open`, `keepalive`) or garbage.
NtfyMessage? tryParseNtfyMessageLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) {
    return null;
  }
  if (decoded['event'] != 'message') {
    return null;
  }
  return NtfyMessage.fromJson(decoded);
}