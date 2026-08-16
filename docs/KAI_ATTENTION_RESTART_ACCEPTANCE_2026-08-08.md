# Kai Central Attention — Live Restart Acceptance

Date: 2026-08-08

Verdict: PASS for real Release coordinator hydration, watchdog recovery, durable
pending state, one-body routing, and exactly-once terminal delivery.

Proof state: Verified live for crash/resume and exactly-once desktop delivery.
Natural `KaiProactiveService` intake was not exercised by this run.

## Test identity

- Event and correlation ID:
  `acceptance-restart-20260808T103800695Z`
- Release executable:
  `build/windows/x64/runner/Release/Kai.exe`
- Original attention state: version 1, zero pending, zero processed, zero
  deliveries, Bahrain budget day `20260808`, sequence 0.
- Controlled seed:
  `(proactive) Live restart acceptance: crooked is allowed.`
- Evidence archive:
  `C:\Users\sadeq\AppData\Local\Homecoming\KaiCore\acceptance\20260808T103759780Z`

## Observed sequence

1. Rebuilt the Windows Release application with Briefs 008–010 accepted code.
2. Started Central Kai without an eligible visible body.
3. Preserved the exact original `attention.json`, then staged one schema-valid
   pending acceptance event. This was necessary because desktop `/nudge` is an
   in-process developer command and does not enter the headless coordinator.
4. Coordinator PID 44884 loaded the event and repeatedly decided
   `storeForLater / no_suitable_body_online`; the event remained byte-for-byte
   identifiable in `attention.json` and no terminal event existed.
5. Force-terminated only coordinator PID 44884 while watchdog PID 48556 stayed
   alive.
6. The production watchdog started coordinator PID 60752. It recorded
   `attention_state_loaded` with `pending: 1` and `deliveriesUsed: 0`.
7. Before any body returned, the same event remained pending and terminal count
   stayed zero.
8. Started one Release desktop body. The coordinator selected exactly
   `desktop-body-858e11f86ddd` with `deliverNow / most_relevant_friend_body`.
9. One `proactive_delivered` record was written. After another evaluation
   window there was still exactly one `deliverNow`, one delivery, zero empty,
   and zero failed terminal records.
10. Durable state showed zero pending, the original event ID in
    `processedEventIds`, `deliveriesUsed: 1`, and the original sequence.
11. Archived the test state and correlated journal, stopped only the verified
    test processes, restored the exact original attention snapshot, removed the
    test-generated backup, and relaunched Central Kai plus desktop.

## Acceptance matrix

| Criterion | Result | Evidence |
|---|---|---|
| Release coordinator runs accepted code | PASS | Release build succeeded; coordinator and watchdog healthy |
| No eligible body keeps event pending | PASS | `storeForLater`; state retained pending event |
| Forced coordinator death invokes watchdog recovery | PASS | PID 44884 replaced by recovered PID 60752 |
| Restart hydrates original event and budget | PASS | `attention_state_loaded`, pending 1, deliveries 0 |
| No delivery occurs without a body | PASS | terminal count 0 before desktop start |
| One body is selected | PASS | exact desktop body ID in `deliverNow` decision |
| Event delivers once | PASS | one `proactive_delivered` |
| Event does not redeliver | PASS | one route/one delivery after an additional evaluation window |
| Completion is durable | PASS | pending empty; processed ID present; delivery budget incremented |
| Pre-test state restored | PASS | zero pending, zero processed, zero deliveries, sequence 0 |
| Natural proactive intake survives restart | UNVERIFIED | controlled schema-valid fixture used; no `attention_event_received` in this run |

## Follow-up observations

- A bodyless pending event records identical `storeForLater` decisions on
  multiple presence/timer ticks. This does not lose or duplicate the event, but
  it creates unnecessary journal volume and should be deduplicated or paced.
- The decision JSON reports `remainsDurable: false` for ordinary proactive
  `storeForLater`, while the production queue correctly retains it. The field
  describes domain durability, not actual queue retention, and is easy to
  misread in operations evidence.
- Desktop `/nudge` cannot trigger the headless coordinator because its
  `KaiProactiveService` stream is process-local. A production-safe diagnostic
  intake seam is still needed if future acceptance must prove natural enqueue
  without waiting for randomized timers.
