# Simultaneous embodiment live checkpoint — 2026-08-08

## Result

Central Kai accepted VR and AR presence heartbeats concurrently through the two
authoritative gateway channels. Both bodies registered independently in Kai Core
while the coordinator remained online.

| Check | Result | Evidence |
|---|---|---|
| Central Core | PASS | `127.0.0.1:8790/health` returned Core v2 healthy |
| VR channel authority | PASS | `127.0.0.1:8787/health` reported `vr` |
| AR channel authority | PASS | `127.0.0.1:8788/health` reported `ar` |
| Concurrent presence responses | PASS | Two responses returned `presenceState: present` |
| Presence is not conversation | PASS | Both responses contained empty replies |
| VR body registration | PASS | Core listed `acceptance-vr`, world `vr_shack` |
| AR body registration | PASS | Core listed `acceptance-ar` |
| Messenger release | PASS | Installed on Samsung SM-G998B and rendered `CORE AWAKE` plus the Messenger body chip |

The acceptance bodies used 90-second leases and correctly disappeared when the
test stopped renewing them. This is intentional: the UI must never display a
body that is not actually present.

## Remaining attended check

The real Shack component now sends a metadata-only heartbeat every 25 seconds
while idle. Unity imported the bridge but initially logged `CS0104` in
`KaiPushToTalkController`: `InputDevice` was ambiguous between Input System and
XR. The current source already qualifies the field as
`UnityEngine.XR.InputDevice`. On 2026-08-08, the complete current
`Assembly-CSharp` compiled successfully against Unity's generated response-file
references into an isolated temporary output. Six unrelated obsolete-API
warnings remained and no C# error remained.

This proves current source compilation, not Editor domain reload or runtime
presentation. Unity's asset watcher did not advance after a content-preserving
timestamp refresh. Play Mode must therefore still be observed in the Unity
Console before Editor acceptance, and the tethered Quest brief remains a
separate later gate. Do not force-close Unity before the scene is confirmed
saved.

## Outbound attention checkpoint

Central Core now owns a durable, body-targeted outbound inbox. A proactive
friend line aimed at VR or AR is saved to Core before conversation history says
it was spoken. The chosen body polls its own inbox, presents the line, and then
acknowledges it. Another body cannot read or acknowledge that envelope.

Morning attended check:

1. Enter Play Mode in the Shack and wait up to 25 seconds for the VR heartbeat.
2. Run `scripts/test/kai_outbound_attention_acceptance.ps1` from the app root.
3. PASS means the script found the live VR body, queued one model-free line,
   and saw Unity acknowledge it within 20 seconds.
4. Confirm the same line appeared in the Shack and Unity has no bridge errors.
