# Kingdom K1.6-M1 isolated acceptance — 2026-08-09

Verdict: **TESTED in isolation**. Authoritative adoption, registration, and
live proof remain **UNVERIFIED**.

## Evidence binding

- Isolated workspace:
  `C:\Users\sadeq\Documents\Codex\2026-08-09\kingdom-sectioning\work\kingdom_k1_1_integration`
- Base HEAD: `58dad479074ebdbaf2b3455b46a2c0356e18eaa9`
- Accepted isolated commit:
  `64997adfe2a3001862cbbb2bfc99877980cfb35e`
- Claude session: `92d04174-2a7f-4966-af3b-74fdee3ffa28`
- Relay-reported model: verified Claude Opus 5
- Worktree/index: clean after the four-file isolated commit.
- No authoritative integration was performed.

Bound files:

- `functions/index.js` —
  `0B138BB85131561F2BD42479A6A162932609AD7CA55031723C0A1C26BCCDE156`
- `test/k1_6/static-contract.test.mjs` —
  `177CA948A88FB34E2F1D6E4DACA752B1FFA8CE91C937C54F80379EC255662D91`
- `test/k1_6/voucher-emulator.test.mjs` —
  `386E9495DA6CD13FF941DEDDAEC0C394A173581439B712DB6BE876378A83251B`
- `docs/evidence/K1_6_M1_CLAUDE_IMPLEMENTATION.md` —
  `D5B84E07266E4C0A123037EED946E06BA7BC7A4DD92A835046F2B0B0BB3DF6A0`

## Independent verification

Command:

```powershell
scripts/delivery/run-box.ps1 -BoxId K1.6
```

Final result:

- Static safeguards: 10/10 PASS.
- Local Firebase-emulator behaviors: 15/15 PASS.
- The spoofed `actorUid` cannot debit another balance or create artifacts.
- Voucher, ledger, receipt, replay, and resulting balance bind to the
  authenticated caller.
- Existing nominal, insufficient-balance, catalog approval, idempotency,
  collision, concurrency, and receipt-integrity behaviors remain passing.

Two earlier attempts passed the static suite but stopped before emulator test
logic because adjacent K1.3/K1.7 suites owned ports 4400, 4500, 8080, 9000, and
9099. No process was killed. The final unchanged rerun began only after those
ports were released.

## Boundary and next gate

No live Firebase project, credential, deployment, authoritative checkout, or
production registration was touched. The next local-safe box is to audit and
bound adjacent callable wrappers that share the caller-data spread pattern.
Authoritative adoption requires a separate integration review of isolated
commit `64997adfe2a3001862cbbb2bfc99877980cfb35e`.
