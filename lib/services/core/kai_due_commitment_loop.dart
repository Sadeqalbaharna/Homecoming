// When the due-commitment scheduler runs, and — harder — when it stops.
//
// The scheduler decides what to do with a promise. This owns the four moments
// that surround that decision: the drain at startup, the periodic drain, the
// drain woken by a desktop appearing, and shutdown.
//
// Shutdown is why this file exists as its own unit. Cancelling a timer does not
// stop a drain that has ALREADY started — it is suspended inside
// `await commitments(dueOnly: true)`, and when the socket finally answers it
// resumes and dispatches. `stop()` returned long ago; the coordinator is gone;
// a reminder still lands, a body still wakes, a promise still closes. Cancelling
// triggers is not stopping work.
//
// So this loop does three things a timer cannot:
//   1. marks itself inactive BEFORE cancelling anything, so in-flight work is
//      already unauthorized by the time it resumes;
//   2. awaits the in-flight drain, so `stop()` returning means it is finished;
//   3. counts generations, so a drain from before a restart cannot become
//      authorized again just because the loop is running once more.
library;

import 'dart:async';

import 'kai_due_commitment_scheduler.dart';
import 'kai_global_presence_service.dart';

class KaiDueCommitmentLoop {
  /// [createScheduler] receives the authorization predicate this loop owns.
  ///
  /// The scheduler is built here rather than passed in, so there is no way to
  /// construct one that is running without being answerable to a lifecycle.
  KaiDueCommitmentLoop({
    required KaiDueCommitmentScheduler Function(bool Function() isActive)
        createScheduler,
    this.interval = const Duration(seconds: 20),
  }) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }
    scheduler = createScheduler(_authorized);
  }

  final Duration interval;
  late final KaiDueCommitmentScheduler scheduler;

  Timer? _timer;
  bool _running = false;

  /// Incremented on every stop. A drain records the generation it began in and
  /// is only authorized while that is still the current one.
  int _generation = 0;
  int? _drainGeneration;

  /// The drain currently in flight, so [stop] can wait for it.
  Future<void>? _inFlight;

  bool get isRunning => _running;

  bool _authorized() => _running && _drainGeneration == _generation;

  /// Begin. Drains once immediately, then on [interval].
  ///
  /// The immediate drain matters: a coordinator that starts after a laptop has
  /// been shut for a day has promises already overdue, and waiting a full
  /// interval to notice would make it late for no reason.
  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(interval, (_) => unawaited(drainNow()));
    unawaited(drainNow());
  }

  /// Run one drain, if this loop is running. Overlaps collapse.
  Future<void> drainNow() {
    if (!_running) return Future<void>.value();
    final existing = _inFlight;
    if (existing != null) return existing;

    _drainGeneration = _generation;
    final future = scheduler.drain().whenComplete(() {
      _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  /// A presence update arrived. Drain only if it brought a body that can
  /// actually show a reminder.
  Future<void> onPresence(KaiGlobalPresenceSnapshot snapshot) {
    if (!_running) return Future<void>.value();
    // Asked even when not draining, so the eligible-body set stays current and
    // a later appearance is still recognised as new.
    if (!scheduler.shouldWakeFor(snapshot)) return Future<void>.value();
    return drainNow();
  }

  /// Stop, and mean it.
  ///
  /// Order is the contract. Inactive first, then triggers cancelled, then wait
  /// for whatever was already running. Reversing any two of those reopens the
  /// window this class exists to close.
  Future<void> stop() async {
    if (!_running && _inFlight == null) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    // 1. Unauthorize BEFORE anything else. Any suspended drain that resumes
    //    from here on finds itself out of date and touches nothing.
    _running = false;
    _generation++;

    // 2. No new triggers.
    _timer?.cancel();
    _timer = null;

    // 3. Wait for work already in progress. It will do nothing — it is
    //    unauthorized — but `stop()` returning must mean it has finished, or a
    //    test cannot assert anything and a restart could overlap it.
    final inFlight = _inFlight;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // A failing drain is still a finished drain.
      }
    }
    _inFlight = null;
  }
}
