# Turning the console into a multi-tenant platform

The app runs in two modes from **one file**:

- **Offline mode** (default): `CLOUD_CONFIG` is blank. The single HTML file works
  with no network, no accounts, storing everything in the browser. This is the
  distributable `tavern_console_blank.html`. Unchanged.
- **Platform mode**: paste a Firebase config into `CLOUD_CONFIG` and the same
  file becomes a signed-in, cloud-synced, multi-venue product.

Switching is one object. Nothing else in the app changes.

---

## What platform mode gives you

- **Accounts** — email/password + Google, via Firebase Auth.
- **Durable storage** — each venue's book is one JSON object in Cloud Storage,
  so a cleared browser loses nothing.
- **Multi-device** — sign in anywhere; the newest edit wins.
- **Offline-first, still** — writes hit the browser instantly and sync up when
  the network is there. A venue with bad wifi keeps working.
- **Tenant isolation** — a user can only ever touch the org they belong to,
  enforced by the security rules in this folder.

## Data model

```
Firestore
  users/{uid}   { org, role, email }          <- the caller's membership
  orgs/{org}    { owner, name, venues[], members{uid:role}, created }

Cloud Storage
  orgs/{org}/venues/{venue}.json              <- the venue's whole book
```

First sign-in mints a fresh org owned by that user, with one venue
(`venue1`). The book blob is byte-identical to what the offline app stores in
`localStorage`.

---

## One-time setup

You need the Firebase CLI (`npm i -g firebase-tools`) and a Google account.

1. **Create the project.** In the [Firebase console](https://console.firebase.google.com):
   New project (separate from any existing one). Give it a name.

2. **Enable Auth.** Build → Authentication → Get started → enable
   **Email/Password** and **Google**.

3. **Enable Firestore** (production mode) and **Storage**.

4. **Get the web config.** Project settings → General → Your apps → Web app
   (`</>`). Copy the `firebaseConfig` values.

5. **Paste them into the app.** In `tavern_console.html` (or the built file you
   ship), find:

   ```js
   const CLOUD_CONFIG={apiKey:'',authDomain:'',projectId:'',storageBucket:'',appId:''};
   ```

   and fill in the five values from step 4.

6. **Deploy the rules and hosting.** From this folder:

   ```bash
   firebase login
   firebase use --add            # pick the project you created
   mkdir -p public
   cp tavern_console.html public/index.html   # or the built file
   firebase deploy --only firestore:rules,storage:rules,hosting
   ```

   `firebase.json`, `firestore.rules`, and `storage.rules` in this folder are
   already written for you.

That's it. Visit the hosting URL, create the owner account, and the venue book
syncs to the cloud.

---

## Notes and next steps

- **Conflict handling is last-write-wins** by edit time. Fine for one person on
  two devices; if you later have two people editing the *same* venue at the same
  second, the later save wins. Field-level merge is a future upgrade.
- **Inviting a second user to an org** (a manager, staff) is not wired into the
  UI yet — the membership model supports it (`orgs/{org}.members`), but adding a
  member currently needs a small admin action. This is the natural next feature.
- **The LLM key** still lives client-side in offline mode. In platform mode you
  should proxy AI calls through a Cloud Function so the key never ships to the
  browser — also a clean next step.
- **Never commit a filled-in `CLOUD_CONFIG` to a public repo.** The web API key
  is not a secret in the dangerous sense (the rules are what protect data), but
  keep it out of public history as hygiene.
