// The ordering contract for accepting one Core outbound into a visible body.
//
//     persist durably  →  confirm visible  →  (caller acknowledges)
//
// This lives outside the widget on purpose. It used to be a private method on
// the desktop shell, which meant the only way to test it was to re-implement
// it in the test file — and a test that re-implements the algorithm can only
// prove the copy agrees with the copy. It cannot catch a race, because the
// copy has the same race. This is the real unit the shell calls.
library;

import 'conversation_store_service.dart';
import 'kai_scheduled_commitment.dart';

/// Is this record already on screen?
typedef KaiOutboundVisibility = bool Function(String recordId);

/// Put this record on screen. May be a no-op if the surface refuses it;
/// [KaiOutboundVisibility] is the authority on whether it worked.
typedef KaiOutboundRender = void Function(ConversationLine line);

/// Accepts Core outbound records on behalf of one visible body.
///
/// Returning false anywhere leaves the record pending in Core, which is the
/// recoverable failure. The unrecoverable one is acknowledging a reminder that
/// was never stored or never seen, so every uncertain path returns false and
/// waits for the next drain.
class KaiOutboundAcceptance {
  KaiOutboundAcceptance({
    required this.personaId,
    required this.surfaceId,
    required this.isMounted,
    required this.isVisible,
    required this.render,
    required this.nowMillis,
    ConversationStoreService? store,
    void Function(Object error)? onPersistError,
  })  : _store = store ?? ConversationStoreService(),
        _onPersistError = onPersistError;

  final String personaId;
  final String surfaceId;

  /// Whether the body can still show anything. A closing window must not let a
  /// reminder be acknowledged.
  final bool Function() isMounted;

  final KaiOutboundVisibility isVisible;
  final KaiOutboundRender render;
  final int Function() nowMillis;

  final ConversationStoreService _store;
  final void Function(Object error)? _onPersistError;

  /// Handle one record. True means "durable and visible — safe to acknowledge".
  Future<bool> accept(Map<String, dynamic> record) async {
    if (!isMounted()) return false;

    final outboundId = record['outboundId']?.toString().trim() ?? '';
    final text = record['text']?.toString() ?? '';
    if (outboundId.isEmpty || text.isEmpty) return false;

    final recordId = KaiScheduledCommitment.transcriptKey(outboundId);

    if (!isVisible(recordId)) {
      ConversationLine line;
      try {
        // Durable FIRST. Rewriting the same deterministic child is idempotent,
        // so a retry after a crash mid-way costs nothing and duplicates
        // nothing.
        line = await _store.saveAssistantOutbound(
          personaId: personaId,
          surfaceId: surfaceId,
          outboundId: outboundId,
          // The exact stored text. No model, no rewording, no formatting.
          exactText: text,
          timestampMillis: nowMillis(),
        );
      } catch (error) {
        // Firebase unavailable or the write was rejected. The promise is not
        // durable, so it stays owed.
        _onPersistError?.call(error);
        return false;
      }

      // The window can close between the write and the paint. The record is
      // durable by now, so a later retry will find it after restore.
      if (!isMounted()) return false;

      // Re-check AFTER the await, never before it.
      //
      // The realtime history watcher sees the write we just made and can put
      // that same recordId on screen while this method is suspended. Deciding
      // from the visibility we read before awaiting would use a boolean that
      // stopped being true mid-flight, and render a second identical bubble
      // for one reminder. The record is still fine to acknowledge — it is
      // durable and it is visible — so this suppresses the duplicate render
      // without holding the promise open.
      if (!isVisible(recordId)) render(line);
    }

    if (!isMounted()) return false;

    // Acknowledge only against what is actually on screen right now. If the
    // render was refused, this is false and the reminder stays owed.
    return isVisible(recordId);
  }
}
