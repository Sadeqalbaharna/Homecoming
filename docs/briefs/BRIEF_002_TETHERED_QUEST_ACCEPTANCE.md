# Brief 002 — Tethered Quest embodiment acceptance

Owner: Homecoming implementation team

Reviewer: Northstar project manager

Status: BLOCKED BY BRIEF 001 PASS

## Goal

Prove the real Quest build can use the existing loopback-only Homecoming bridge
through an explicit USB debugging tunnel, without exposing Kai Core to the LAN
or placing provider credentials in Unity.

This is a physical-device milestone. It is not the final untethered transport
architecture and must not be reported as always-on device independence.

## Entry gate

Brief 001 must have a PASS report. If the Editor path is not accepted, do not
add a headset and a USB tunnel to the diagnostic surface.

## In scope

- One connected and authorized Meta Quest.
- `adb reverse` for VR gateway port 8787 and Kai Core port 8790.
- The current Quest build and current `127.0.0.1` Unity configuration.
- On-device presence heartbeat, one friend turn, and one exact-body outbound
  delivery/acknowledgement.
- Disconnect/reconnect observation for the body lease.

## Out of scope

- Binding Kai services to `0.0.0.0` or a LAN interface.
- Permanent secrets in a Unity scene, APK, source file, or command history.
- Wi-Fi-only, Internet, Tailscale, tunnel-provider, or cloud relay design.
- AR, animation polish, memory redesign, or attention scheduling.
- Claiming the laptop can be turned off.

## Invariants

- The host services remain bound to loopback.
- Provider and administrator credentials remain outside the Quest application.
- One physical body has one body ID and one active session.
- Presence is metadata-only.
- Outbound delivery targets and acknowledges that exact Quest body.
- Removing USB or stopping the app allows the body lease to expire; the UI must
  not show a ghost body indefinitely.

## Procedure

1. Confirm Brief 001 passed.
2. Connect the Quest by USB and accept the debugging prompt in the headset.
3. From `C:\code\homecoming_app`, run:

   ```powershell
   .\scripts\test\kai_quest_loopback_bridge.ps1
   ```

4. Confirm both port reversals report PASS.
5. Install or launch the current KaiXR Quest build.
6. Enter the Shack and wait up to 30 seconds for a VR body lease.
7. Speak one nontechnical friend turn and confirm exactly one response.
8. Run:

   ```powershell
   .\scripts\test\kai_outbound_attention_acceptance.ps1
   ```

9. Confirm the outbound line appears once in the headset and the script reports
   PASS.
10. Exit the Quest app or disconnect debugging. Wait for the 90-second body
    lease to expire and confirm the VR body disappears.

## Pass criteria

- The script identifies a Meta Quest rather than an unrelated Android phone.
- Ports 8787 and 8790 are reversed for the selected serial.
- The Quest registers one live VR body with a unique body/session identity.
- A friend turn completes without technical leakage.
- One exact-body outbound envelope is presented and acknowledged once.
- No provider credential exists in the Unity build.
- The body disappears after its lease expires when the app stops.
- Host services remain loopback-only throughout the test.

## Required report

Stop and report:

- Quest model and serial suffix;
- APK/build identifier;
- configured reversals;
- VR body ID, device ID, and session ID;
- turn result and latency;
- outbound ID, presentation count, and acknowledgement latency;
- lease-expiry result;
- relevant Unity/Android logs;
- exact files changed, if any;
- verdict: PASS, FAIL, or UNVERIFIED;
- recommendation for the untethered authenticated-transport brief.

Do not design or implement untethered transport in this brief.

