# SafeCircle

School-to-home child safety platform (backend + Android app, one monorepo).

## Setup

```bash
cp .env.example .env   # then edit the values
cd backend && npx prisma generate   # src/generated/ is gitignored — required
                                    # before any local `npm run build`
```

`.env` is gitignored — never commit it. Secrets live only there.
`DATABASE_URL` must point at the compose service (`postgres:5432`) and match
the `POSTGRES_*` values; `JWT_SECRET` should be a long random string
(`openssl rand -hex 32`). `NTFY_BASE_URL=http://ntfy:2586` enables real push;
leave it empty to run with a logging-only transport (the in-app inbox still
works, nothing is published).

## Run

```bash
docker compose up --build -d
```

On every start the `api` container runs `prisma migrate deploy` (applies
committed migrations) and then the seed (idempotent) before booting NestJS —
a fresh `docker compose down -v && docker compose up --build -d` therefore
ends with schema + seed data, no manual steps.

Services:

| service    | role                                     | host port |
| ---------- | ---------------------------------------- | --------- |
| `nginx`    | reverse proxy (entry point)              | 8080      |
| `api`      | NestJS + Prisma backend                  | none (internal 3000) |
| `postgres` | PostgreSQL 17 (volume `pgdata`)          | none      |
| `ntfy`     | self-hosted push broker (volume `ntfy_data`, v2.28.0) | none (internal 2586) |

nginx also proxies `/ntfy/` to the `ntfy` service with response buffering
off, so the app can hold a long-lived JSON stream through it.

## Health check

```bash
curl -i http://localhost:8080/health
# HTTP/1.1 200 OK
# {"status":"ok"}
```

## API (Phase 1)

| method | path               | auth  | notes |
| ------ | ------------------ | ----- | ----- |
| POST   | `/auth/signup`     | public| `{ email, password, role, name }`, role ∈ parent/teacher/counselor |
| POST   | `/auth/login`      | public| → `{ accessToken, refreshToken, user }` |
| POST   | `/auth/refresh`    | public| rotates the refresh token |
| POST   | `/auth/logout`     | Bearer| revokes the submitted refresh token |
| GET    | `/users/me`        | Bearer| `{ id, email, role, createdAt }` |
| GET    | `/health`          | public| → `{"status":"ok"}` |

Access tokens: JWT, 1-day expiry (`JWT_SECRET`). Refresh tokens: opaque,
30 days, stored sha256-hashed.

## API (Phase 2, reporting)

| method | path                    | auth / role        | notes |
| ------ | ----------------------- | ------------------ | ----- |
| POST   | `/reports/entries`      | Bearer, TEACHER    | bulk upsert `{ classId, reportDate, entries[] }` → 201, idempotent per (student, author, date) |
| GET    | `/reports/entries`      | Bearer, TEACHER    | `?classId=&date=` — caller's own entries for that class/day |
| PATCH  | `/reports/entries/:id`  | Bearer, TEACHER    | author-only edit of attendance/homework/behavior/note; flags recomputed |
| GET    | `/reports/summaries`    | Bearer, PARENT     | `?week=YYYY-Www` (default: current ISO week) — linked students' zero-filled weekly counts + notes |
| GET    | `/reports/flagged`      | Bearer, TEACHER / COUNSELOR / ADMIN | `?week=` — flagged entries, scoped to own classes / own schools / all |
| GET    | `/classes`              | Bearer, TEACHER / ADMIN | caller's classes (teachers) or all classes (admin): `{id,name,grade,school{id,name}}`, ordered by grade/name |
| GET    | `/classes/:id/students` | Bearer, TEACHER / ADMIN | `{id,name,schoolNumber}`, ordered by school number; 403 for a foreign class, 404 unknown |

Flag reasons, computed when an entry is written (no backfill):
`behavior_severe`, `behavior_concern`, `absence_streak` (≥3 consecutive
Mon–Fri school days all ABSENT/LATE), `homework_streak` (≥3 consecutive
entries all NOT_DONE).

## API (Phase 2c, notifications + push)

| method | path                          | auth  | notes |
| ------ | ----------------------------- | ----- | ----- |
| GET    | `/notifications`              | Bearer| `?limit=` (default 50) → `{ items[], unreadCount }`, own rows only, newest first |
| POST   | `/notifications/:id/read`     | Bearer| 201 → the row; **404 if it belongs to another user** |
| POST   | `/notifications/read-all`     | Bearer| → `{ ok: true, updated }` |
| POST   | `/notifications/subscribe`    | Bearer| → `{ topic }`, server-generated and stable per (user, platform) |

When a teacher saves an entry that is newly flagged **or** changes flag
reason, a `REPORT_FLAG` notification is created for each linked parent and
fanned out to that user's push subscriptions. Re-saving identical data does
not notify again. The inbox row is written **before** fan-out, so a broken or
absent push transport never fails the report request (transport errors are
logged only — no retries this phase).

Push goes through a `PushTransport` interface with two implementations:
`NtfyTransport` (HTTP to `NTFY_BASE_URL`) and `LogOnlyPushTransport` (default
when `NTFY_BASE_URL` is unset). Swapping in FCM later means implementing the
same interface and rebinding the DI token — no caller changes.

> **Foreground-only.** The Flutter app subscribes to
> `GET /ntfy/{topic}/json` while it is running; there is no background
> delivery, UnifiedPush, or FCM yet. The ntfy **topic suffix is required** —
> a bare `/ntfy/{topic}` returns a topic-info document, not a stream.
>
> **Security.** Topics are unguessable 48-hex values, but ntfy itself is
> unauthenticated: whoever holds a topic can publish to it or read it. Fine
> for the pilot (the topic is only ever returned to its own user via the API),
> but put access control on ntfy before exposing it publicly.

## App (Phase 1.5 + 2, Flutter)

Flutter app in `app/` — Riverpod + go_router + dio. Login screen posts to
`/auth/login`, stores the token pair (SharedPreferences), and a role-based
router redirect lands on the role-specific home. A dio interceptor attaches
the JWT, refreshes it on 401 (single-flight), and clears the session when
refresh fails. Reporting screens:

- **Teacher (`/teacher`)** — daily report for the teacher's class: pick a day
  with the week arrows, set attendance/homework/behavior per student
  (SegmentedButtons), add a short **Öğretmen notu** per student,
  save with **Kaydet**. Wait for the response to show the auto-computed flag
  chip (e.g. **Ödev şeridi**) on the affected student's row. Notes round-trip
  via `GET /reports/entries`; an empty note field clears the stored note.
- **Parent (`/parent`)** — weekly summary for every linked child: navigate
  weeks with the arrows, `‹ ›` for the week. A child without records shows
  "Bu hafta için kayıt yok" inside his/her card; when *no* child has records
  the screen shows the week-level hint instead (the seed data lives in
  **2026-W39/W40**; today's week, 2026-W41, is empty).
- **Counselor / Admin (`/counselor`, `/admin`)** — placeholder home;
  real screens arrive in Phase 4.
- **Parent & Teacher (`/notifications`)** — a bell in the AppBar shows an
  unread Badge. While the app is open it streams ntfy
  (`GET /ntfy/{topic}/json`) and refreshes the badge on every new
  notification; tapping the bell opens the inbox (**Bildirimler**) — tap a
  row to mark it read, or **Tümünü okundu işaretle**; pull down to refresh.
  Both homes start the stream on mount and drop it on dispose; the stream
  reconnects with a backoff.

### Demo walkthrough (seeded data)

1. `docker compose up --build -d`, then `cd app && flutter run -d linux`.
2. Teacher: `teacher1@test.local` / `Passw0rd!123` → class **5-A**.
   Navigate back to **2026-09-28** (W40, seeded). Student 1001 Ayşe Yılmaz
   shows *İzinli* (EXCUSED); set her homework to *Yapılmadı* and save — the
   row gains a **Ödev şeridi** chip (seed's 09-29/09-30/10-01 are also
   NOT_DONE, so the 3-day streak auto-flags). Also try **10-01** where the
   seed already carries that flag.
3. Parent: `parent2@test.local` / `Passw0rd!123` → weekly summary. The default
   week (2026-W41) is empty; arrow back to **2026-W39**: children Zeynep Kaya
   (badge **İşaretli: 1** — 09-25 absence-streak) and Mehmet Çelik, with
   zero-filled attendance/homework/behavior counts per child.
4. Counselor: `counselor1@test.local` → Phase-4 placeholder (in scope: the
   role-scoped `GET /reports/flagged` endpoint, curl-verified).
5. Notifications: keep the parent app open, and from a second terminal save a
   flag for **Zeynep Kaya** on a date with no data yet (e.g. **2026-10-12**,
   2026-W42) as `teacher1@test.local`. The parent's bell badge appears
   without a reload; opening the bell shows
   **Uyarı: Zeynep Kaya** — *Zeynep Kaya — uyarı davranışı (2026-10-12)*.
   Re-saving the same values creates nothing new.

> Week/day navigation is the `‹ ›` arrow buttons — there is no calendar picker
> yet, so reach seeded dates/W39–W40 by stepping back from today.

```bash
cd app
flutter pub get
flutter test          # E2E against a running stack (real signup/login/refresh
                      # HTTP + a live notification/badge/inbox flow)

# dev targets
flutter run -d linux                                  # desktop (default http://localhost:8080)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080   # Android emulator
flutter run --dart-define=API_BASE_URL=http://<vps-ip>:8080    # real device
```

The `android/` target is scaffolded but the Android SDK is not installed on
this machine yet (needed from Phase 3 onward); `linux/` is only a local dev
harness. Seeded test account works directly: `teacher1@test.local` /
`Passw0rd!123`.

## Database / migrations

Migrations live in `backend/prisma/migrations/` and are applied by the
container entrypoint. To create a new one (Postgres has no host port, so the
Prisma CLI runs in a throwaway container):

```bash
# 1. edit backend/prisma/schema.prisma
npx prisma generate   # refresh local types in backend/

# 2. create + apply the migration (writes SQL into backend/prisma/migrations/)
docker compose run --rm --entrypoint "" -v ./backend/prisma:/app/prisma \
  api npx prisma migrate dev --name <name>

# 3. rebuild so the image gets the regenerated client, restart
docker compose up --build -d
```

Never use `prisma db push` — always `migrate dev`, and review the generated
`migration.sql` before committing it. Applied so far: `init`, `reporting`,
`notifications` (the last one adds the inbox and push-subscription tables).

## Seed data

Runs automatically on start (idempotent, upsert by natural key). Manual run:

```bash
docker compose run --rm --entrypoint "" api npx prisma db seed
```

Creates 1 admin, 1 school, 2 classes, 6 students, 1 counselor, 2 teachers,
3 parents. Emails `admin@test.local`, `counselor1@test.local`,
`teacher1@test.local`, `teacher2@test.local`, `parent1..3@test.local`,
dev password `Passw0rd!123` (printed by the seed — dev only, never production).

## Stop

```bash
docker compose down        # keeps the pgdata volume
docker compose down -v     # deletes the database volume
```

See `reconstruction-and-plan.md` for the full project plan and locked-in decisions.
