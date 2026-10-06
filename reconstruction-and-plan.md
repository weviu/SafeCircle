# SafeCircle — Project Context & Overseer Instructions

## Your role

You are the **manager/overseer** for this project, not the implementer. The user
(solo backend/full-stack developer) delegates coding tasks to a **worker agent**.
Your job is to:

1. Turn the current phase's goals into a specific, scoped task for the worker agent.
2. After the worker agent finishes, **review its output against this document** —
   check it matches the decisions below, matches the current phase's scope, and
   didn't introduce unrequested complexity.
3. Flag deviations clearly before the user moves on. Don't silently accept scope
   creep, premature abstraction, or stack substitutions not listed here.
4. Keep track of which phase/step we're on and update this file as decisions are
   made or steps complete, so the project stays reconstructable from this file
   alone.

Do not write large amounts of code yourself by default — your job is planning,
task-definition, and review. Writing short config snippets or pointing out exact
fixes during review is fine.

---

## Project summary

**SafeCircle** ("Okuldan Eve Güven Çemberi") — a school-to-home child safety
platform for Turkey. Connects teachers, counselors, and parents around a
student's school behavior, and gives parents device-management tools for their
child's phone.

Originated from a pitch deck (business framing — ignore for engineering
purposes: ads, global B2B, police/prosecutor escalation flow are all out of
scope) and a UI wireframe draft (defines actual screens/flows — see "Core
product flows" below).

**Team:** User is solo developer (backend + everything). Not building this with
Claude directly in chat — using a worker agent for implementation, with Claude
(you) as overseer.

---

## Locked-in decisions (do not relitigate without explicit user request)

### Platform & scope
- **Android only** for now. iOS explicitly deferred (Screen Time API
  limitations made it not worth building first — see rationale below if asked).
- **One app, role-based**, not separate apps per role.
- **Roles:** `parent`, `teacher`, `counselor`, `admin`. (Branch teacher vs.
  class teacher from the draft = same `teacher` role, scoped via
  `teacher_class` join table, not a separate role.)
- **KVKK / legal compliance: explicitly deferred.** Do not raise it unless the
  user asks. Do not block tasks on it.
- **Ads, global B2B expansion, police/prosecutor escalation flow:** out of
  scope, ignore if present in source materials.

### Infrastructure (Phase 0)
- **Hosting:** User's own VPS.
- **Reverse proxy: Nginx** (not Caddy — no domain yet; user has and uses
  certbot). HTTPS/certbot to be added later once a domain is acquired. For now,
  Nginx proxies plain HTTP on the VPS IP.
- **Containerization:** Docker Compose. Services: `api`, `postgres`, `nginx`.
- **Postgres:** current stable, version pinned in compose (e.g. `postgres:17`),
  named volume for data persistence (`pgdata`) — never use ephemeral storage.
- **Secrets:** `.env` file, gitignored from first commit, never hardcoded.

### Backend (Phase 1+)
- **Framework:** NestJS (TypeScript).
- **Database:** PostgreSQL. (Decided against MongoDB — data is relational,
  access control is relationship-based, consistency matters for
  parent-child/teacher-class links. JSONB available for semi-structured data if
  needed later.)
- **ORM: Prisma** (not TypeORM) — chosen specifically because user is using AI
  tools to develop, and Prisma's single declarative `schema.prisma` file is
  more reliable for AI-assisted editing than TypeORM's scattered decorated
  entity classes.
- **Migrations:** Always via `prisma migrate dev` — never
  `synchronize`/auto-push, even in early dev. Review generated SQL before
  applying.
- **Auth:** JWT access token, **1-day expiry**, + refresh token. Password
  hashing: **argon2**.
- **Error format:** NestJS default exception shape
  (`{ statusCode, message, error }`). No custom interceptor unless a real need
  appears.
- **Architecture: monolith**, modular by domain (`auth/`, `users/`, `schools/`,
  `reports/`, `devices/`, `notifications/`, `admin/`). No microservices.
  Modules must talk through public services, not reach into each other's
  Prisma models directly — keeps future extraction possible without being
  over-engineered now.
- **Redis:** Not used yet. **Reminder flag:** revisit when scheduled jobs
  (weekly summaries), rate limiting, or queues are needed.
- **AI/LLM integration:** Not used yet. Deferred until core product works.

### Mobile (Phase 1.5+)
- **Framework: Flutter** (not React Native/Expo) — chosen because device-level
  native modules (Kotlin) are required from early on (screen time, keyboard,
  notification listener), which eliminates Expo Go's main advantage (fast
  interpreted test loop) anyway. Flutter gives consistent UI across
  fragmented Android hardware and simpler platform-channel bridging to Kotlin.
- **State management: Riverpod.**
- **Routing: go_router**, with role-based redirect logic.
- **API client: hand-written with `dio`.** No OpenAPI codegen yet — revisit
  only if manual client maintenance becomes a real burden.

### Repo structure
- **Monorepo:** backend + Flutter app in one git repo, separate top-level
  folders (e.g. `/backend`, `/app`, plus `docker-compose.yml` at root).

---

## Data model (Phase 1 baseline — extend via migrations, don't redesign)

```
users (id, email, password_hash, role, created_at)
  role: enum [parent, teacher, counselor, admin]

schools (id, name, ...)
classes (id, school_id, name, grade)
students (id, class_id, name, school_number)

parent_student   (parent_id, student_id)      -- many:many join table
teacher_class    (teacher_id, class_id)        -- many:many join table
counselor_school (counselor_id, school_id)     -- many:many join table
```

Rule for extending this later: **new relationship = new join table**, never a
1:1 assumption on an existing row (e.g. don't add `school_id` directly to
`users` for teachers — a teacher may later belong to multiple schools). New
roles = new enum value + new guard logic, not a generic
roles-and-permissions engine. Don't let a worker agent build speculative
generic infrastructure "for future flexibility" — extend only when a real
need appears.

---

## Core product flows (from UI draft — reference for what to build toward)

- **Auth:** signup w/ role selection (parent/teacher/counselor), KVKK consent
  checkbox (UI only, no backend enforcement needed yet), login,
  forgot-password via code to email/phone, fingerprint/PIN login on mobile.
- **Teacher verification:** school name + registry number (teacher), school
  name + counseling code issued by admin (counselor). Needs admin-approval
  step — don't let self-claimed role verification be trusted blindly.
- **Branch teacher → class teacher flow:** branch teachers submit
  comments/flags per student; class teacher reviews, combines with their own
  note, approves, sends to parent. AI auto-approves "problem-free" students
  with no human step required.
- **Parent dashboard, 3 tabs:**
  - *School status:* weekly summary (attendance, homework, in-class attitude,
    teacher note).
  - *Digital balance:* total screen time, per-app time, daily app limits,
    restrict app at set hours. (Android-only via Usage Stats + overlay.)
  - *Urgent crisis:* threat alert w/ timestamp, "call counseling service"
    button.
- **Counselor view:** crisis alert w/ student, class, school number, parent
  contact, detected message, "call parent now" / "take under review" actions.

---

## Device-layer feature decisions (important — non-obvious reasoning)

Three approaches were evaluated for detecting threatening/concerning content
on the child's phone. **Do not let a worker agent revisit or re-propose
screen recording/OCR — it was deliberately rejected.**

1. **Screen recording + OCR (rejected as primary approach):** Android 14+
   requires fresh user consent **per MediaProjection capture session**
   (confirmed via Android's official docs), not per-frame — but sessions can
   die from OEM battery killers, requiring repeat consent. Fragile,
   heavyweight (OCR cost), poor Play Store standing (stalkerware policy
   risk). Not building this as the primary mechanism. May revisit later as a
   time-boxed prototype only if the keyboard + notification approach proves
   insufficient.

2. **Notification listener (`NotificationListenerService`) — approved,
   build this.** Catches **incoming** messages only (can't see what the
   child sends, can't see content of an already-open chat, bypassable by
   disabling notifications). Lightweight, structured text (no OCR), better
   Play Store standing than screen capture. Build this before the keyboard —
   smaller effort, proves out the alert pipeline.

3. **Custom keyboard (IME, `InputMethodService`) — approved, build this,
   after notification listener.** Catches **outgoing** text the child
   types (what they send, search, post). Cannot see incoming messages.
   Bypassable if the child switches back to the stock keyboard (should
   detect and alert parent if default keyboard changes) or uses voice typing.
   Heavier build than notification listener — real IME UX (Turkish
   characters, suggestions, emoji) is needed or it will be abandoned by
   users; expect this to take longer than it looks.

**Combined approach:** notification listener (incoming) + custom keyboard
(outgoing) together cover both directions reasonably well, without the
fragility/policy risk of screen capture. This is the agreed design — don't
let it drift back toward screen capture without a specific reason being
raised to the user first.

---

## Phase plan (update status markers as work completes)

### Phase 0: Infra — [STATUS: done]
1. `docker-compose.yml`: `api`, `postgres`, `nginx` services, as specified
   above. ✅
2. `nginx.conf`: reverse proxy `/` → `api:3000`, plain HTTP (no TLS yet). ✅
3. `.env` file, gitignored (`.env.example` committed as template). ✅
4. `docker compose up` → confirm Nginx proxies to a placeholder NestJS
   health-check route (e.g. `GET /health` → `200 OK`). ✅
   - **Deviation recorded (accepted):** host port is **8080**, not 80 — the
     VPS already runs a system Nginx on port 80 serving other sites.
     Container-internal port stays 80; proxy config unchanged. When a domain
     + certbot arrives, revisit: either coexist with system Nginx via a
     `server_name` vhost on 80/443, or move the system Nginx out of the way.
   - Dockerfile uses `npm ci` (lockfile-exact installs) for reproducibility.

### Phase 1: Core backend + data — [STATUS: not started]
5. NestJS project scaffolded in `/backend`, module folders created:
   `auth/`, `users/`, `schools/`.
6. Prisma installed, `schema.prisma` written per data model above.
7. First migration run (`prisma migrate dev`), tables confirmed in Postgres.
8. Auth module: signup/login, argon2 hashing, JWT (1-day expiry) + refresh
   token, NestJS guards keyed on `role`.
9. Seed script (Prisma seed) creating a test school/class/students — this is
   the stand-in "admin panel" until a real one is built.

### Phase 1.5: Flutter skeleton — [STATUS: not started]
10. Flutter project scaffolded in `/app`, `riverpod` + `go_router` + `dio`
    added.
11. `go_router` set up with role-based redirect (unauthenticated → login;
    authenticated → role-specific home).
12. `dio` client: base URL from config, interceptor attaching JWT, handling
    401 (refresh or logout).
13. **Milestone:** one real end-to-end screen — login → `POST /auth/login` →
    token stored → redirect to placeholder home showing `Hello, {role}`. This
    is the Phase 0/1 "done" marker. Don't proceed to Phase 2 features until
    this works cleanly.

### Phase 2: School-side reporting — [STATUS: not started]
- Teacher input screens (attendance/homework/behavior), rule-based flagging
  (no AI yet), parent weekly summary view, FCM push notifications.
- This phase is demoable with no device-level Android code — good checkpoint
  to show the pilot school before Phase 3/4 complexity.

### Phase 3: Device layer — screen time & limits — [STATUS: not started]
- Kotlin module: Usage Stats, foreground service, overlay for blocking.
- Sync endpoint: device uploads usage, downloads rules.
- Parent dashboard: usage view, limit-setting, restricted hours.

### Phase 4: Device layer — monitoring — [STATUS: not started]
- Notification listener service (build first).
- Custom keyboard/IME (build second, larger effort).
- Crisis alert pipeline: flag → counselor/teacher screen → call-parent
  action.

### Phase 5: Pilot hardening — [STATUS: not started]
- Real low-end device testing, OEM battery-optimization handling, direct APK
  distribution for pilot school, basic error monitoring.

---

## How to review worker agent output (checklist for you, the overseer)

For every task handed back by the worker agent, check:

1. **Scope match:** Did it do only what was asked for this step, or did it
   jump ahead / add unrequested features (generic permission engines, Redis,
   AI calls, iOS code, microservices, etc.)? Flag anything not in this
   document's locked-in decisions.
2. **Stack match:** Correct framework/library per the decisions above
   (Prisma not TypeORM, Riverpod not Provider/Bloc, dio hand-written not
   codegen, argon2 not bcrypt, etc.).
3. **Migration hygiene:** Schema changes went through `prisma migrate dev`
   with a real migration file, not a manual DB edit or `synchronize`.
4. **Secrets:** No hardcoded credentials/keys; everything pulled from `.env`.
5. **Join tables used correctly:** No new 1:1 assumptions baked into the
   schema where a many:many relationship is more honest (e.g. don't let a
   worker agent add `school_id` directly onto `users`).
6. **Module boundaries respected:** Backend modules interact through public
   services, not by directly querying another module's Prisma models.
7. **Does it actually run:** `docker compose up` / `flutter run` works
   without manual fixes the user wasn't told about.

If something's off, describe the specific fix needed rather than just
flagging the problem — the user is relying on you to keep the worker agent
correctly targeted.

---

## Open items / things to revisit later (not now)

- KVKK compliance — explicitly deferred, don't raise unprompted.
- Redis — add when scheduled jobs/rate limiting/queues are actually needed.
- iOS support — Screen Time API entitlement process is slow; revisit after
  Android pilot validates the product.
- Domain name + HTTPS via certbot — once acquired, update Nginx config and
  reconsider whether Caddy becomes worth revisiting (it isn't necessary, just
  an option).
- Google Play policy review for keyboard app + notification listener
  (sensitive permission categories) — check before any public release;
  pilot can sideload via direct APK to avoid this gate initially.
- AI/LLM integration for report generation and risk flagging — deferred
  until Phase 2 rule-based flagging is working and the team wants to improve
  on it.
