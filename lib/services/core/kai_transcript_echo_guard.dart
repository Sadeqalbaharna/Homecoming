// Prevents a surface from rendering its own persisted transcript event twice.
//
// The live history stream is still authoritative for messages from elsewhere.
// This guard consumes only exact speaker + text echoes that the local surface
// explicitly registered, and expires them quickly if persistence never lands.
class KaiTranscriptEchoGuard {
  KaiTranscriptEchoGuard({this.ttl = const Duration(minutes: 2)});

  final Duration ttl;
  final List<_ExpectedEcho> _expected = [];

  void expect({required bool fromKai, required String text, DateTime? now}) {
    final normalized = _normalize(text);
    if (normalized.isEmpty) return;
    final time = now ?? DateTime.now();
    _purge(time);
    _expected.add(_ExpectedEcho(
      fromKai: fromKai,
      text: normalized,
      expiresAt: time.add(ttl),
    ));
  }

  bool consumeIfExpected({
    required bool fromKai,
    required String text,
    DateTime? now,
  }) {
    final time = now ?? DateTime.now();
    _purge(time);
    final normalized = _normalize(text);
    final index = _expected.indexWhere(
      (echo) => echo.fromKai == fromKai && echo.text == normalized,
    );
    if (index < 0) return false;
    _expected.removeAt(index);
    return true;
  }

  void cancel({required bool fromKai, required String text}) {
    final normalized = _normalize(text);
    final index = _expected.indexWhere(
      (echo) => echo.fromKai == fromKai && echo.text == normalized,
    );
    if (index >= 0) _expected.removeAt(index);
  }

  void clear() => _expected.clear();

  void _purge(DateTime now) {
    _expected.removeWhere((echo) => !echo.expiresAt.isAfter(now));
  }

  static String _normalize(String text) => text.replaceAll('\r\n', '\n').trim();
}

class _ExpectedEcho {
  const _ExpectedEcho({
    required this.fromKai,
    required this.text,
    required this.expiresAt,
  });

  final bool fromKai;
  final String text;
  final DateTime expiresAt;
}
