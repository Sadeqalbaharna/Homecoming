# The Tavern / Kingdom — Session Handoff

Paste the "Continuation prompt" section into a new chat to pick this up. The rest is reference.

---

## Continuation prompt

I'm building a restaurant system themed as an RPG. Three connected systems share one Firebase
project (`kingdom-ac44f`).

**1. TAVERN CONSOLE (the focus)** — a single self-contained HTML/canvas app:
`C:\code\homecoming_app\scripts\firebase\tavern_console.html` (~72 KB).
Keep `patrons_anim.png` in the SAME folder (the sprite atlas it loads).
It currently has: a 2.5D oblique floor map (Ground Floor + Ale House / First Floor tabs), live
table occupancy from RTDB, an Edit-Layout mode (drag / rotate / add / remove / rename tables), a
manual "Seat" mode (click a seat, type a guest, the avatar walks in via A\* pathfinding; click an
occupied seat for the walk-out), a `/visits` order+spend ledger, per-hero avatar rendering (seated
guests show their own baked sprite), and a built-in Menu Manager tab.

**2. KINGDOM APP (Flutter)** at `C:\code\kingdom_working3.0\kingdom_working\kingdom`.
Firestore + Google/email auth. Onboarding: Sign in → Name → Faction → Avatar creator (paper-doll)
→ NFC link → app. A Cloud Function `bakeAvatar` (`functions/index.js`, Node + sharp) composites the
hero's Mana Seed layers into a walk atlas, stores it, and mirrors the URL to RTDB `/avatars/{uid}`.

**3. PI HARDWARE** — `C:\code\homecoming_app\scripts\pi\nfc_listener.py`.
NFC reader on each table. A guest tap seats them and opens a `/visits` record; a STAFF badge tap
(present in `/staff`) closes the table.

**RTDB** (`https://kingdom-ac44f-default-rtdb.europe-west1.firebasedatabase.app`, public-read on most):

- `/tables/{tableId}` — occupant + arrivedAt + visitId
- `/active_guests/{nfcUid}` — live presence `{ name, authUid, tableId, isVIP, usualOrder, notes, arrivedAt }`
- `/tavern_guests/{nfcUid}` — app-less guest profiles `{ name, visitCount, usualOrder, notes, isVIP }`
- `/nfc_links/{nfcUid}` — `{ authUid, email }`
- `/visits/{visitId}` — `{ tableId, authUid, items[], total, status, openedAt, closedAt }`
- `/avatars/{authUid}` — baked sprite atlas URL
- `/staff/{nfcUid}` — `{ name, role }`
- `/menu/{itemKey}` — menu items
- `/tavern_layout/{floor}` — saved table layout

(Kingdom user PROFILES live in FIRESTORE `users/{uid}`; RTDB holds the tavern-side mirrors.)

### New task — turn the console into a "Tavern Lord Dashboard" + add a GUEST DATABASE

I'll be working from a dashboard mockup (RPG-styled restaurant admin). Build it incrementally:
SCAFFOLD the full dashboard shell now with every section as a labelled PLACEHOLDER, then implement
the GUEST DATABASE first as a real, working CRUD hub. We develop one section at a time.

**Dashboard layout to scaffold** (study each, make a placeholder card/panel for each):

- **TOP KPI STRIP**: Live Revenue, Covers (x / capacity), Avg Spend / Head, Orders in Kitchen
  (+ delayed), Wait Time avg, date/clock + settings. Derive real numbers from `/visits` + `/tables`
  where possible; placeholder otherwise.
- **LEFT SIDEBAR NAV**: profile card (name / level / XP), then: Overview, Tavern Map (the existing
  floor view), Orders (badge count), Menu Analytics, Staff, Customers, Loyalty & Factions, Events,
  Reviews, Inventory, Reports, Settings. Bottom: a "Tavern Vibes" mood widget.
- **CENTER**: the existing floor map becomes the "Tavern Map" view; tables show per-table spend +
  timer + status colour (green ok / yellow new / red waiting).
- **RIGHT COLUMN**: "Orders in Progress" list + Kitchen Display button; "Staff Performance" table.
- **BOTTOM CARDS**: Popular Dishes, Preparation Times, Sales Trend chart, Customer Feedback, Top
  Spenders, Tavern Alerts, a flavour quote.

**Guest database** (build this for real first — it's the "Customers" section):

- A searchable, sortable table of guests, merged from `/tavern_guests` + `/active_guests` +
  `/nfc_links` + `/visits` (lifetime spend, visit count, last seen) keyed by nfcUid / authUid.
- Inline EDIT of fields (name, isVIP, faction, usualOrder, notes) writing back via RTDB REST
  PATCH / PUT.
- DELETE an account: confirm-gated; prefer a soft "archive" toggle plus an explicit hard-delete that
  removes the RTDB entries. Always confirm before destructive writes.
- All edits go straight to RTDB so the change is live everywhere.

### Constraints / environment notes (learned the hard way)

- Do NOT use `&&` in shell commands — run commands on separate lines.
- The editor's direct file-write truncates files larger than ~60 KB. `tavern_console.html` is bigger,
  so DON'T rewrite it whole. Use small targeted edits, OR patch it with Python in the sandbox
  (read / replace / write) and copy back. Keep a working copy in the outputs scratch folder.
- The sandbox bash mount of the project folders is STALE for host-edited files. Edit with the host
  Read / Edit / Write tools; use the outputs scratch dir (fresh both ways) for any bash processing.
- Verify console JS by extracting the inline `<script>` and running `node --check`, and render it
  headlessly with a `@napi-rs/canvas` + `vm` shim harness (stubs document / fetch / Image, then calls
  `render()`). Chrome can't open `file://` here.
- Keep `tavern_console.html` a SINGLE self-contained file (its only companion is `patrons_anim.png`).
- Licensing: only show COMPOSED sprites; never add a feature that exports or redistributes the raw
  Mana Seed layer files.

Goal vibe: a polished, genuinely usable restaurant dashboard (I want to monetize this as a real
product later), keeping the warm RPG "Tavern Lord" theme.

Start by: reading `tavern_console.html` to learn its current structure, then propose the dashboard
shell + guest-DB plan before writing code. Ask me anything ambiguous first.

---

## Already done (so you don't redo it)

- Floor map (GF + FF) to scale from the real plans, edit mode, doors/stairs/kitchen.
- Mana Seed directional patron sprites + real walk-cycle atlas (`patrons_anim.png`); walk-in / sit /
  walk-out animation with A\* pathing around furniture; guests face their tables.
- Merged the old `tavern_live` + `menu_manager` into the one `tavern_console.html` (Floor / Menu tabs).
- Manual Seat / Unseat writes the same RTDB shape as a real NFC tap; opens/closes `/visits`.
- Per-hero avatar rendering in the console from `/avatars`.
- Pi listener: `/staff` close routine + `/visits` ledger.
- Kingdom onboarding: redesigned faction screen, new paper-doll avatar creator, `bakeAvatar` Cloud
  Function (Node + sharp), `nfc_links` RTDB dual-write, portrait picker removed.

## Deploy / build reminders

- Functions: in `kingdom/functions`, run `npm install`, then `firebase deploy --only functions`.
- App: in `kingdom`, run `flutter pub get`, then build / run on a device.
- Console: open `tavern_console.html` in a browser (keep `patrons_anim.png` beside it).
