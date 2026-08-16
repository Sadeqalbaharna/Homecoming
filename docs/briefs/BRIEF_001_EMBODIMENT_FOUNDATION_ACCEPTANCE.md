# Brief 001 — Embodiment foundation acceptance

Owner: Homecoming implementation team

Reviewer: Northstar project manager

Status: READY FOR ATTENDED VALIDATION

Current evidence: the full current `Assembly-CSharp` compiles successfully in
an isolated output using Unity's generated response-file references. The stale
Editor log's earlier `CS0104` ambiguity is absent from current source. Unity
domain reload and Play Mode remain `UNVERIFIED` because the open Editor's asset
watcher has not advanced.

## Goal

Prove that the current Central Kai outbound path reaches the intended Unity VR
body in Play Mode, is acknowledged exactly once, and does not create a model
call or cross-populate another conversation room.

This brief closes the Editor-level acceptance gate only. It must not be reported
as standalone Quest acceptance.

## In scope

- Unity C# compilation of the current KaiXR bridge.
- VR presence heartbeat from the Shack while idle.
- Exact derivation of the Core body ID.
- Core outbound polling and acknowledgement.
- Visible delivery through the existing Unity reply event.
- Voice presentation if the currently configured playback component supports
  it; visual acceptance is sufficient for the transport gate.
- Evidence capture from Core, Unity Console, and the acceptance script.

## Out of scope

- New animations, art, gestures, or UI polish.
- A new model call or proactive-generation tuning.
- Standalone Quest networking.
- AR validation.
- Memory redesign, self-improvement, scheduling, or completed-work routing.
- Refactoring unrelated Unity or Flutter code.

## Invariants

- One envelope targets one exact body and never fans out.
- Unity contains no provider or administrator credentials.
- Presence heartbeats create no chat turn, memory, TTS, or model call.
- An envelope is acknowledged only after Unity accepts it for presentation.
- Failure leaves the item pending until expiry; it must not be silently lost.
- Messenger and `in_person` history remain unchanged by this model-free test.
- Do not force-close Unity or discard an unsaved scene.

## Preconditions

1. Central Core health includes `outbound_inbox` at
   `http://127.0.0.1:8790/health`.
2. The Shack scene contains `KaiBridgeController` using
   `HomecomingKaiGateway`.
3. Unity Console is visible and cleared so new compile/runtime errors are
   attributable to this run.
4. The current scene is saved before Play Mode.

## Procedure

1. Allow Unity to finish script compilation.
2. If compilation fails, stop. Record the first causal error; do not repair
   unrelated warnings.
3. Enter Play Mode in the Shack.
4. Wait up to 30 seconds for the metadata-only VR presence heartbeat.
5. Run from `C:\code\homecoming_app`:

   ```powershell
   .\scripts\test\kai_outbound_attention_acceptance.ps1
   ```

6. Observe the line `Central Kai found the way back to this body.` in the Unity
   presentation path.
7. Confirm the script reports PASS within 20 seconds.
8. Exit Play Mode normally.
9. Inspect the Unity Console for bridge exceptions or repeated presentation.
10. Confirm Messenger and desktop transcripts did not gain this acceptance
    line.

## Pass criteria

- Unity compiles with no new error.
- One live VR body appears after the heartbeat.
- The acceptance script selects that body and queues one envelope.
- Unity presents the exact line once.
- Core no longer returns it as pending for that body.
- No other body presents it.
- No conversation transcript receives the line.
- No provider request is made.
- No bridge error occurs during polling or acknowledgement.

Any missing criterion is a failure or `UNVERIFIED`; it is not a partial pass.

## Failure handling

- Preserve the envelope and logs long enough to diagnose the first causal
  failure.
- Make only the smallest reversible repair within the Unity bridge/Core inbox
  seam.
- Add focused regression coverage for any behavior changed.
- Rerun the complete procedure after the final edit.
- If the failure is caused by `127.0.0.1` on a standalone headset, stop and
  report `EXPECTED DEVICE-TRANSPORT GAP`; do not weaken the loopback security
  binding as an improvised fix.

## Required report

Stop after validation and report:

- Unity compile result;
- observed VR body ID, device ID, and session ID;
- Core health capability result;
- outbound ID and target body ID;
- presentation count;
- acknowledgement result and latency;
- transcript-isolation result;
- provider-call result;
- Unity errors/warnings relevant to the bridge;
- exact files changed, if any;
- final verdict: PASS, FAIL, or UNVERIFIED;
- exact recommended next brief.

Do not begin device transport, AR, attention scheduling, memory work, or
self-improvement in this brief.
