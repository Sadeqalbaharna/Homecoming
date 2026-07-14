// CortexActivityBus
//
// A tiny app-wide event bus that lets any service announce brain activity —
// which stem fired, which memory was touched, when the two brains collaborated —
// without knowing anything about the UI. The KaiCortexScreen subscribes and
// forwards these into the 3D cortex WebView; when no cortex is open, events are
// simply dropped. Zero dependency on the visualization existing.

import 'dart:async';

/// Which brain stem an event belongs to.
enum CortexBrain { gpt, claude, collab }

/// A single activity event.
class CortexEvent {
  /// 'brain' (a stem fired), 'memory' (a node was tapped), or 'reset'.
  final String type;
  final CortexBrain? brain;

  /// For 'memory' events: -1 = GPT/left, 0 = shared, 1 = Claude/right.
  final int? side;

  /// Optional knowledge-graph node id the event relates to.
  final String? nodeId;

  /// How long (ms) the stem should stay lit for a 'brain' event.
  final int? ms;

  const CortexEvent(this.type, {this.brain, this.side, this.nodeId, this.ms});

  Map<String, dynamic> toJson() => {
        'type': type,
        if (brain != null) 'brain': brain!.name,
        if (side != null) 'side': side,
        if (nodeId != null) 'nodeId': nodeId,
        if (ms != null) 'ms': ms,
      };
}

class CortexActivityBus {
  static final CortexActivityBus instance = CortexActivityBus._();
  CortexActivityBus._();

  final _ctrl = StreamController<CortexEvent>.broadcast();

  /// Subscribe (the cortex screen does this).
  Stream<CortexEvent> get stream => _ctrl.stream;

  /// Announce that a brain stem fired.
  void brain(CortexBrain b, {int ms = 2600}) =>
      _emit(CortexEvent('brain', brain: b, ms: ms));

  /// Announce a memory/node was tapped (side: -1 gpt, 0 shared, 1 claude).
  void memory({int? side, String? nodeId}) =>
      _emit(CortexEvent('memory', side: side, nodeId: nodeId));

  /// Return the cortex to its idle ambient state.
  void reset() => _emit(const CortexEvent('reset'));

  void _emit(CortexEvent e) {
    if (!_ctrl.isClosed) _ctrl.add(e);
  }
}
