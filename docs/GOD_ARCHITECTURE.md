# God Kai — Multi-Project Architecture

Homecoming is the **god layer**. It holds the top-down view, calls Claude + OpenAI as tools,
and partners with you across many projects. Each project (Kingdom/tavern, and a dozen more to
come) is a **spoke** beneath it. This document defines how the pieces relate so that adding
project #13 is a *registration*, not a rewrite.

## The two kinds of "god access"

1. **Build-time partnership** — Kai as your partner *in the work*: reading code, remembering
   each project, orchestrating models, acting across folders. This needs no Firebase security
   model at all — it needs a **project registry** and **per-project memory**. Most projects
   only ever need this.

2. **Run-time data access** — only for projects with a live backend users touch (like Kingdom).
   These are the only ones with a Firebase auth/rules question, and there will only ever be a
   few of them.

## Where "god" actually lives

A client app ships public config and can be decompiled, so rules can never trust "the Homecoming
app" as god just because it claims to be. Real god power = **admin-SDK / service-account
credentials**, which bypass security rules on whatever project they point at. That already exists
in your world: the Cloud Functions and the Pi listeners authenticate this way. **Anything that
truly needs to see-and-touch-everything runs there — the hub, not the client.**

On the *client*, "god" is a **claim**, not raw access:
- **Bootstrap (no backend needed):** write your uid into `/config/god_uids/<yourUid>: true` using
  the admin SDK (a one-off script, a Cloud Function, or the Firebase console). `/config` is
  rules-locked (`.read:false/.write:false`) so only admin-SDK callers can seed it; rule
  *expressions* can still read it via `root.child(...)`.
- **Long-term:** mint a custom claim `{ god: true }` from an admin Cloud Function.

Every ruleset accepts **both**:
```
auth != null && ( auth.token.god === true
                  || root.child('config/god_uids').child(auth.uid).val() === true )
```

## Hub-and-spoke (why this scales to a dozen)

- **Hub = Homecoming's brain** (admin-credentialed Functions / small backend). It is the *only*
  thing that reaches into a spoke's live database. The client talks to Kai; Kai fans out to spokes
  with service-account access. You never mint and maintain a dozen god-claims in a dozen projects.
- **Spokes** hold their own data and their own scoped users.

### Where a spoke's data lives — the graduation rule
- **New creative projects start namespaced** inside Homecoming's own project under
  `/projects/{projectId}/...` — one auth, one rules file, cheap, instantly visible to Kai.
- **A project graduates to its own Firebase project only when it earns it:** real external users,
  separate billing, or hardware in the world. Kingdom has already graduated. Most projects never will.

## The project registry

Lives in Homecoming's RTDB at `/projects/{projectId}`. Readable by any authenticated session;
writable only by god. Suggested shape:

```
/projects/{projectId}
  name:        "Kingdom / Tavern"
  status:      "graduated" | "namespaced"
  firebase:    "kingdom-ac44f"        // null if namespaced under Homecoming
  rtdb:        "https://kingdom-ac44f-default-rtdb.europe-west1.firebasedatabase.app"
  repoPath:    "C:\\code\\kingdom_working3.0"
  summary:     "Restaurant themed as an RPG; NFC table presence."
  createdAt:   <ts>
```

This is the list Kai reads to know "which worlds exist" — the run-time equivalent of how an agent
enumerates the folders it can enter.

## Repo layout for multi-project deploys

Each **graduated** project is a self-contained folder so its rules deploy without clobbering others:

```
homecoming_app/
  database.rules.json          # Homecoming (default project: homecoming-74f73)
  firebase.json                # -> database.rules.json
  .firebaserc                  # aliases: default=homecoming-74f73, kingdom=kingdom-ac44f
  firebase/
    _template/
      database.rules.template.json   # reusable god-model template (copy for each new spoke)
    kingdom/
      database.rules.json      # Kingdom rules
      firebase.json            # -> database.rules.json
      .firebaserc              # default=kingdom-ac44f
```

## Deploy commands

Homecoming (from repo root):
```
firebase deploy --only database          # uses .firebaserc default = homecoming-74f73
```

Kingdom (isolated, from its own folder):
```
cd firebase/kingdom
firebase deploy --only database          # uses its .firebaserc default = kingdom-ac44f
```

**Rules are inert until deployed.** Test every ruleset in the Firebase console **Rules Playground**
before deploying.

## Adding project #13 — checklist

**If it starts namespaced (default):**
1. `POST /projects/{id}` in Homecoming RTDB with `status:"namespaced"` (god-write).
2. Store its data under `/projects/{id}/...`. No new rules file — Homecoming's rules already cover it.
3. Point Kai's registry at it. Done.

**If/when it graduates:**
1. Create the Firebase project; add it to root `.firebaserc` as an alias.
2. `cp -r firebase/_template firebase/<name>`; fill in `.firebaserc` (its project id) and adapt
   `database.rules.json` from the template.
3. Seed god: write your uid to that project's `/config/god_uids/<uid>: true` via admin SDK.
4. `cd firebase/<name> && firebase deploy --only database` (test in Playground first).
5. Update the registry entry to `status:"graduated"` with its `firebase`/`rtdb`/`repoPath`.

## Current status / open items

- **Homecoming rules** (`database.rules.json`): unauthenticated drive-by closed; native paths
  gated on `auth != null`; misplaced tavern paths removed; `/projects` registry + `/config` added.
  The app signs in anonymously, so it keeps working. **Still to do:** anonymous auth means an
  attacker can also sign in anonymously and read — per-persona scoping to a stable owner uid is
  the next tightening (blocked on the three conflicting `personaId` constants: `truekai` in
  `main_mobile.dart`, `kai` in `constants.dart`, `kai_persona_1` in `ambiance_service.dart` —
  reconcile these first).
- **Kingdom rules** (`firebase/kingdom/database.rules.json`): bootstrap posture — authenticated
  users keep full access, unauthenticated **write** is closed everywhere, unauthenticated **read**
  is closed except non-sensitive display paths (`menu`, `daily_quests`, `tavern_layout`).
  **Verify before deploying:** (a) does a guest ever read their own PII while *not* signed in?
  (b) does `tavern_console.html` obtain an auth token for its writes (`getFirebaseToken()`), i.e.
  is there a real signed-in session? If either is "no", adjust before flipping.
- **Pi + Cloud Functions:** unaffected — they use the admin SDK and bypass rules.
- **API keys:** unchanged by any of this. Still compiled into the APKs in `releases/`; rotate when
  you have solid products, per your call.
