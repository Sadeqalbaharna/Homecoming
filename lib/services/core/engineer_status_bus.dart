// EngineerStatusBus
//
// Broadcasts the engineer agent's current step so the desktop shell's projects
// panel can show real loop progress (investigating → editing → running → done)
// per workspace — the same decoupled pattern as CortexActivityBus. Drops events
// when nothing is listening.

import 'dart:async';

class EngineerStatus {
  /// Active workspace root the agent is working in (null = none).
  final String? project;

  /// Human label: 'idle', 'investigating', 'editing', 'running', 'done'.
  final String label;

  /// True while actively working (drives the spinner/pulse in the UI).
  final bool busy;

  const EngineerStatus({this.project, required this.label, this.busy = false});
}

class EngineerStatusBus {
  static final EngineerStatusBus instance = EngineerStatusBus._();
  EngineerStatusBus._();

  final _ctrl = StreamController<EngineerStatus>.broadcast();
  EngineerStatus current = const EngineerStatus(label: 'idle');

  Stream<EngineerStatus> get stream => _ctrl.stream;

  void emit(String label, {String? project, bool busy = true}) {
    current = EngineerStatus(project: project, label: label, busy: busy);
    if (!_ctrl.isClosed) _ctrl.add(current);
  }

  void idle() => emit('idle', busy: false);
}
