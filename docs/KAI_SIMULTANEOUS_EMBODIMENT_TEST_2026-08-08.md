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
while idle. Unity was open but its editor log had not advanced since launch, so
script compilation and Play Mode must be observed in the Unity console before
calling the physical Quest body fully accepted. Do not force-close Unity before
the scene is confirmed saved.
