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

### Phase 1: Core backend + data — [STATUS: done]
5. NestJS project scaffolded in `/backend`, module folders created:
   `auth/`, `users/`, `schools/`. ✅
6. Prisma installed, `schema.prisma` written per data model above. ✅
   - Prisma pinned to stable v6 (`^6.19.3`); v7/v8 are newer majors with
     changed generator/engine defaults — revisit deliberately later.
7. First migration run (`prisma migrate dev`), tables confirmed in Postgres. ✅
   - `20261007084616_init/migration.sql` committed: 8 tables (`users`,
     `refresh_tokens`, `schools`, `classes`, `students`, `parent_student`,
     `teacher_class`, `counselor_school`), join tables use
     composite PKs, all FKs `ON DELETE CASCADE`, no extra tables/columns.
   - **Workflow (decision):** Postgres publishes no host port (Phase 0), so new
     migrations are generated in a throwaway container:
     `docker compose run --rm --entrypoint "" -v ./backend/prisma:/app/prisma api npx prisma migrate dev --name <name>`
     The api entrypoint runs `migrate deploy` + `db seed` before `node
     dist/main.js`, so a fresh `down -v && up --build` ends with schema +
     seed data and no manual steps.
8. Auth module: signup/login, argon2 hashing, JWT (1-day expiry) + refresh
   token, NestJS guards keyed on `role`. ✅
   - Refresh tokens: opaque 48-byte random, sha256-hashed, 30-day TTL,
     rotated on use; presenting a revoked token revokes the whole family.
     Returned in the response body (no cookies).
   - `@Public()` on login/signup/refresh/health; **logout requires a Bearer
     token** (deliberately not on the public list).
   - **Deviation recorded (accepted):** signup validates `name` but does not
     persist it — the data model has no name column on `users`. Revisit via
     migration when a display name is actually needed.
   - `tsx` and `prisma` both sit in `dependencies`, not devDependencies: the
     production image must run `prisma migrate deploy` and `prisma db seed`
     from `docker-entrypoint.sh`, and `NODE_ENV=production` omits devDeps.
     (`prisma` reaches the image via `@prisma/client`'s peer dep either way,
     but declaring it explicitly keeps the boot-critical path from depending
     on peer auto-install behavior.)
   - No `PrismaModule` (kept to auth/users/schools): `PrismaService` is
     provided directly by AuthModule and UsersModule.
9. Seed script (Prisma seed) creating a test school/class/students — this is
   the stand-in "admin panel" until a real one is built. ✅
   - Idempotent (upsert by natural key): 1 admin, 1 school, 2 classes,
     6 students, 1 counselor, 2 teachers, 3 parents.

### Phase 1.5: Flutter skeleton — [STATUS: done]
10. Flutter project scaffolded in `/app`, `riverpod` + `go_router` + `dio`
    added. ✅ (also `shared_preferences` for token storage — **deviation
    recorded: plaintext prefs, not secure storage; move to
    `flutter_secure_storage`/Keystore during Phase 5 hardening, not before**)
11. `go_router` set up with role-based redirect (unauthenticated → login;
    authenticated → role-specific home `/parent|/teacher|/counselor|/admin`;
    another role's home is rejected). ✅
12. `dio` client: base URL from `--dart-define=API_BASE_URL` (default
    `http://localhost:8080`), interceptor attaching JWT, handling 401
    (single-flight refresh → retry once, else clear session → login). ✅
13. **Milestone:** login screen → `POST /auth/login` → tokens stored →
    redirect to placeholder home showing `Hello, {role}`. ✅
    - **Verification (deviation, accepted):** no Android SDK or Chrome in
      this environment, so the end-to-end proof is `flutter test` —
      widget tests driving the real screens against the real compose
      stack (real signup/login/refresh HTTP; flutter_test stubs HTTP with
      400s by default, cleared via `HttpOverrides.global = null`), plus
      4 plain-Dart API/interceptor tests. All 6 pass; `flutter build
      linux` also succeeds. `android/` is scaffolded and ready once the
      SDK is installed (required from Phase 3 device work).
    - `linux/` target added purely as a local dev harness, no product scope.

### Phase 2: School-side reporting — [STATUS: done]
- Teacher input screens (attendance/homework/behavior), rule-based flagging
  (no AI yet), parent weekly summary view, push notifications (originally
  listed as FCM — dropped in favor of a no-third-party approach, see the
  "Push transport" note below).
- This phase is demoable with no device-level Android code — good checkpoint
  to show the pilot school before Phase 3/4 complexity.
- **Verification note (2026-10-07, backend scope only):**
  - **Schema/migration:** `report_entries` table + `Attendance`/`Homework`/
    `Behavior` enums via `prisma migrate dev --name reporting`
    (`backend/prisma/migrations/20261007111140_reporting/migration.sql`);
    unique `(studentId, authorId, reportDate)`, indexes on `reportDate`,
    `authorId`; FK cascade to `students`/`users`. Verified from-scratch
    `down -v && up --build`: both migrations apply, seed prints
    `Report entries: 60 created, 4 newly flagged`, `/health` → `{"status":"ok"}`.
  - **Flagging:** one pure function `src/reports/flagging.ts` (rules:
    `behavior_severe|behavior_concern` → `absence_streak` (≥3 consecutive
    Mon–Fri school days all ABSENT/LATE, student-wide) → `homework_streak`
    (≥3 consecutive entries all NOT_DONE)). 23/23 offline unit checks passed
    (`/tmp/opencode/check-phase2.ts`). Flags computed at write time only —
    later rule changes won't backfill (documented, accepted for pilot).
  - **Endpoints (all curl-verified against live nginx stack, full transcript
    `/tmp/opencode/phase2-verify.log`, 46 requests):**
    `POST /reports/entries` 201 + re-POST same ids (upsert, no dupes);
    400 invalid enum / duplicate studentId / empty entries / bad week;
    401 no token; 403 parent/counselor/admin on POST, parent on
    `GET entries`+`summaries`+`flagged`, teacher2 on teacher1's class
    (GET + non-author PATCH), counselor/teacher on `summaries`;
    404 unknown studentId/classId/entryId; `GET entries` 200/`[]`;
    `PATCH entries/:id` re-flags both directions (Zeynep 09-25
    ABSENT→PRESENT clears `absence_streak`, Ayşe 09-28 DONE→NOT_DONE
    creates `homework_streak`, both restored);
    `GET summaries?week=2026-W39` parent1 → exactly 2 children with
    zero-filled counts + notes, parent2 → Zeynep `flaggedCount: 1`;
    default week = current ISO week, zero-filled;
    `GET flagged` scoped: teacher1 → 1 entry/week (class A only),
    teacher2 → class B only, counselor → both, admin → both, each with
    hydrated `student{name}` + `author{email}` via UsersService.
  - **Idempotency:** container restart → `0 created, 60 skipped`;
    second `down -v && up --build` → identical `60/4` state.
  - **Build/tests:** `npm run build` clean; `npx tsc --noEmit` clean;
    `git status` shows only `backend/` changes (no `app/` touched).
  - **Deviations:** (1) `SchoolsService` has 6 methods, not 4 — split
    `findByIds` into `classesByIds`/`studentsByIds` + added
    `studentsInSchool` for counselor scoping; no queries cross into
    `schools`/`classes`/`students` tables from `reports/`. **Review fix
    (overser):** `reports/` originally queried the `parent_student` join
    directly — now goes through `UsersService.linkedStudentIds()` so the
    boundary rule holds uniformly (join tables are reached only via the
    owning module's public service).
    (2) `backend/Dockerfile` now copies whole `src/` into the production
    image (was only `src/generated/prisma`) so `tsx prisma/seed.ts` can
    import the flagging module on boot.
    (3) FCM push notifications and Flutter teacher/parent screens from the
    phase description are **not** in this step (explicitly backend-only
    scope); they remain open for the next step of Phase 2.
  - **Known demo-data caveat:** seeded report entries use fixed past dates
    (2026-W39/W40), so the default "current ISO week" summary is empty.
    The Flutter screens task must pick a week that has data (or seed the
    current week) — otherwise the pilot demo shows all-zero summaries.
    **Resolved in the app step below via week/day arrow navigation.**
  - **Verification note (2026-10-07, app + step-1 backend scope):**
    - **Step-1 endpoints:** `GET /classes` and `GET /classes/:id/students`
      (SchoolsController, SchoolsService) — teacher gets own classes with
      `school{id,name}`, admin all classes, counselor/parent 403, no token
      401; students ordered by school number; 404 unknown class, 403 foreign
      class (teacher2 on class A). ReportsService.`requireOwnedClass`
      delegates to SchoolsService.`requireClassAccess` so the ownership rule
      is defined once. Curl transcript (12 cases + regressions):
      `/tmp/opencode/phase2b-classes-curl.log`.
    - **Flutter (`app/lib`):** `reports/{classes_repository,
      reports_repository}.dart` (lists/creates entries, weekly summaries),
      `reports/iso_week.dart` (ISO-8601 weeks, `yyyy-MM-dd`), `reports/
      report_values.dart` (TR labels), `reports/reports_models.dart`;
      `screens/teacher_home.dart` (day arrows, per-student SegmentedButtons,
      per-student **Öğretmen notu** TextField — maxLines 2 / maxLength 500,
      prefilled from GET /reports/entries — Kaydet → flag chip after save),
      `screens/parent_home.dart` (week arrows, week-level empty state + demo
      hint when *no* child has data, `İşaretli: N` badges; **all** linked
      children are rendered, a child without records showing "Bu hafta için
      kayıt yok" inside its card),
      `screens/home_screen.dart` → `PlaceholderHome` for counselor/admin,
      `router.dart` maps `/teacher`→TeacherHome, `/parent`→ParentHome,
      `/counselor|/admin`→placeholder.
    - **Fix round (2026-10-07, Phase 2b — note + child visibility):**
      - **Note-clearing semantics:** `_EntryDraft` gained `note`; the payload
        builder sends an empty/whitespace-only note as an *absent* `note`
        field (`EntryPayload.toJson` omits `note` when null), which
        `CreateReportDto` stores as NULL via `note: input.note ?? null` —
        the variant that lets a teacher clear a note. A literal empty string
        would be persisted as `''` (not cleared), so it is never sent.
        The teacher test round-trips this: types "Randevu gerekli" on
        2026-09-28 → submit → `GET /reports/entries` shows it → clears the
        field → re-submit → `GET` shows NULL → restore seed (DONE, note NULL).
      - **Parent child visibility:** the `hasData` filter is gone — **every
        linked child always renders.** A child with no records shows
        "Bu hafta için kayıt yok" inside its own card; when *no* child has
        data, a single demo-data hint line is appended below the cards
        (overser fix: the intermediate version hid all cards in that case,
        which reproduced the exact "no records vs not linked" ambiguity the
        fix was for). Covered by a
        repository-stubbed widget test (data child + record-less child in the
        same week) — the seeded W39 data always
        gives both children records, so the inline branch needs the stub.
      - Trailing newline restored at EOF of `home_screen.dart`.
      - `flutter analyze` clean; 11/11 tests pass live; `flutter build linux`
        green. Changes limited to `app/` (no backend/packages).
    - **Deviations:** (1) the login-screen E2E user (`flutter-e2e@test.local`)
      owns no class, so its test now asserts the TeacherHome *empty state*
      (`Atandığınız sınıf yok`) instead of a class label; the seed teacher
      flow lives in `reports_test.dart`. (2) screens use
      `SingleChildScrollView + Column` (not lazy lists) so off-screen rows
      stay findable in widget tests. (3) no new pubspec packages. Counselors
      get the placeholder because only their `GET /reports/flagged`
      endpoint is in Phase 2 scope — the counselor screen is Phase 4.
  - **Push transport (decision in progress):** no Firebase/FCM — user wants
    no third-party dependencies. Working plan: `notifications` table +
    in-app unread surface with a `PushTransport` interface (no-op now),
    then self-hosted **ntfy** as a compose service wired to it. Android
    background push without Google is best-effort by nature; the counselor's
    "call parent now" stays the real escalation path. Confirm before
    building.

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
- Prisma 7 upgrade: `package.json#prisma` (the seed config) is deprecated
  and removed in v7 — before any Prisma major bump, migrate to
  `prisma.config.ts`. Boot logs already warn about it. Not urgent while
  pinned to v6.
