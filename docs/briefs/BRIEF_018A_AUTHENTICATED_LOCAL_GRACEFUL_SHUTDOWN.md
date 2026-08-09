# Brief 018A — Authenticated local graceful coordinator shutdown

Owner: Homecoming Kai + persistent Claude partner
Reviewer: supervising Kai
Status: DRAFT — requires separate implementation authority

## Goal

Provide one product-supported, authenticated, local-only command that asks the
running Windows coordinator to finish its Dart teardown, flush durable evidence,
exit with code zero, and let its paired watchdog exit without recovery.

This brief creates a capability for a future built runtime. It cannot control
the currently running `C:\code\homecoming_app` binary and must never be cited as
proof that PID 36184 shut down gracefully.

## Why this is next

Brief 018 cannot enter its attended restart because the running binary exposes
only a private tray-menu return path. Its `WM_CLOSE` branch hides the coordinator;
it has no CLI command, named pipe, loopback shutdown route, registered window
message, or other externally invocable graceful-quit protocol. Coordinate and
message injection cannot replace the local `TrackPopupMenu` return value.

## Entry gate

- Separate sponsor authorization for this production Dart/native behavior change.
- Brief 018 remains open and its accepted artifact binding remains historical
  evidence only; implementation of this brief requires a new build and binding.
- The sponsor-owned dirty worktree is captured and a reversible branch/rollback
  point exists.
- The live `C:\code\homecoming_app` source and binary are not edited or overwritten.

## In scope

- One loopback-only, authenticated graceful-shutdown request for the Windows
  coordinator.
- A per-run unguessable shutdown capability stored outside source control with
  restrictive current-user access and removed or invalidated at process exit.
- A stable run identity bound into the request so a capability from another run
  or PID is refused.
- Idempotent request handling: an accepted duplicate returns the same bounded
  result and cannot start a second teardown.
- Dart teardown that awaits `KaiHeadlessCoordinator.stop()`, embedded Core stop,
  journal flush, and any other durable local writers before native window exit.
- Native termination through the same `quitting_ = true`, tray removal, and
  `DestroyWindow` path used by `QuitFromTray()` so `wWinMain` returns
  `EXIT_SUCCESS` and the paired watchdog does not recover.
- Privacy-safe journal evidence for request accepted/refused, teardown started,
  durable flush completed, and terminal intent; never record the capability.
- A bounded command-line helper or script that performs identity preflight,
  reads the capability under the same user, requests shutdown, and verifies both
  the coordinator and its matching watchdog exit.

## Out of scope

- Controlling or rebuilding the currently running old binary.
- `taskkill`, `Stop-Process`, process-tree termination, watchdog kill,
  `WM_DESTROY`, synthetic tray input, logoff, reboot, or source mutation in the
  live root.
- Remote/network listeners, Firebase, credentials, provider secrets, deployment,
  installation, auto-start mutation, reminder creation, or Brief 018 acceptance.
- A general administration/control API or write-capable MCP surface.

## Invariants

- The listener is loopback-only; non-loopback requests are impossible by bind
  construction.
- Loopback is not authentication. Every request requires the per-run capability
  and exact run identity.
- The capability is never compiled into the application, passed on the command
  line, logged, returned by `/health`, committed, or exposed to other users.
- A stale, missing, malformed, cross-run, wrong-PID, or wrong-root request fails
  closed without changing coordinator state.
- Teardown cannot award project progress, acknowledge reminders, mutate unrelated
  commitments, or cross any sponsor/live authority boundary.
- The watchdog must observe a normal zero exit. Any design that can trigger
  recovery fails acceptance.
- The shutdown response is written before terminal window destruction so the
  caller can distinguish acceptance from a dropped connection.

## Authoritative evidence to inspect

- `windows/runner/flutter_window.cpp`
- `windows/runner/flutter_window.h`
- `windows/runner/main.cpp`
- `lib/main_mobile.dart`
- `lib/services/core/kai_headless_coordinator.dart`
- `lib/services/core/kai_core_server.dart`
- `lib/services/core/kai_operations_journal.dart`
- `scripts/test/kai_reminder_runtime_acceptance.ps1`
- `docs/briefs/BRIEF_018_ATTENDED_DESKTOP_REMINDER_RESTART_ACCEPTANCE.md`
- `docs/evidence/BRIEF_018_ACCEPTED_ARTIFACT.json`

## Procedure

1. Map every Dart and native writer that must stop or flush before exit, and
   specify their awaited order before changing code.
2. Add a narrow shutdown coordinator that owns one state machine:
   `idle -> accepted -> draining -> flushed -> exiting`, with refusal terminal
   states that do not mutate runtime behavior.
3. Generate and protect the per-run capability, bind it to the run identity,
   and expose only the minimum local request contract.
4. Route an accepted request through awaited Dart teardown, return a bounded
   acceptance receipt, then marshal exactly one quit request onto the Windows UI
   thread and reuse `QuitFromTray()`.
5. Add the identity-aware helper and fail-closed verification of coordinator,
   watchdog, root, artifact hash, PID relationship, and port closure.
6. Add deterministic negative and lifecycle tests before any attended runtime
   exercise.
7. Build and bind a new governed artifact. Stop before replacing or controlling
   any live runtime unless that separate attended action is explicitly authorized.

## Pass criteria

- One authenticated local request causes the coordinator and its paired watchdog
  to exit, with coordinator exit code zero and no recovered coordinator created.
- `KaiHeadlessCoordinator.stop()`, embedded Core stop, and journal/durable writer
  flushes complete before native destruction.
- Duplicate accepted requests are idempotent; concurrent requests cannot start
  parallel teardown.
- Missing, wrong, stale, cross-run, wrong-root, wrong-PID, and replayed
  capabilities are refused without state mutation.
- No remote interface, static secret, command-line secret, log disclosure,
  Firebase dependency, model call, or provider-credential dependency exists.
- Normal `WM_CLOSE` continues to hide the coordinator, while tray quit and the
  authenticated seam share one normal-exit implementation.
- The helper refuses an identity mismatch before sending a request and verifies
  both processes plus port 8790 are gone afterward.

Any missing criterion is `FAIL` or `UNVERIFIED`, never a partial pass.

## Required verification

- Native source tests for the shared quit path, zero-exit watchdog behavior, and
  preservation of hide-on-`WM_CLOSE` semantics.
- Dart tests for teardown ordering, flush completion, idempotency, concurrency,
  refusal cases, capability redaction, and response-before-exit ordering.
- Static checks for loopback-only bind, absence of embedded/command-line secrets,
  and absence of Firebase/model/provider dependencies in the shutdown seam.
- Process-level fixture proving zero-exit coordinator/watchdog shutdown without
  recovery, plus negative wrong-identity fixtures.
- Proportionate coordinator, Core, commitment scheduler, operations journal,
  Windows runner, and Brief 018 verifier regressions.
- Attended evidence is a later gate and cannot be replaced by fixture results.

## Failure and rollback

- Preserve the pre-change branch and accepted artifact manifest.
- A failed or ambiguous shutdown request leaves the runtime active and records a
  privacy-safe refusal; it must not fall back to forced termination.
- Roll back by returning to the pre-brief commit and its bound artifact. Never
  overwrite the live old root as part of rollback.
- Retain failing request receipts, process identities, exit codes, hashes, and
  journal anchors without retaining the capability itself.

## Stop and report

Stop after a new artifact is locally tested and bound. Report files and behavior,
exact tests/results, identity and security evidence, Claude findings and their
independent adjudication, remaining risks, rollback, and the exact attended
authority required to replace the old runtime and resume Brief 018.

Do not replace the live runtime, invoke the new seam against a live process,
resume Brief 018, or start Brief 020 in this repair phase.
