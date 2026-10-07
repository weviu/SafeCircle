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
(`openssl rand -hex 32`).

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

Flag reasons, computed when an entry is written (no backfill):
`behavior_severe`, `behavior_concern`, `absence_streak` (≥3 consecutive
Mon–Fri school days all ABSENT/LATE), `homework_streak` (≥3 consecutive
entries all NOT_DONE).

## App (Phase 1.5, Flutter skeleton)

Flutter app in `app/` — Riverpod + go_router + dio. Login screen posts to
`/auth/login`, stores the token pair (SharedPreferences), and a role-based
router redirect lands on a role-specific placeholder home (`Hello, {role}`).
A dio interceptor attaches the JWT, refreshes it on 401 (single-flight), and
clears the session when refresh fails.

```bash
cd app
flutter pub get
flutter test          # E2E against a running stack (real signup/login/refresh HTTP)

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
`migration.sql` before committing it.

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
