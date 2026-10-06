# SafeCircle

School-to-home child safety platform (backend + Android app, one monorepo).

## Setup

```bash
cp .env.example .env   # then edit the values
```

`.env` is gitignored — never commit it. Real secrets live only there.

## Run

```bash
docker compose up --build -d
```

Services:

| service   | role                        | host port |
| --------- | --------------------------- | --------- |
| `nginx`   | reverse proxy (entry point) | 8080      |
| `api`     | NestJS backend              | none (internal 3000) |
| `postgres`| PostgreSQL 17 (volume `pgdata`) | none  |

## Health check

```bash
curl -i http://localhost:8080/health
# HTTP/1.1 200 OK
# {"status":"ok"}
```

## Stop

```bash
docker compose down        # keeps the pgdata volume
docker compose down -v     # deletes the database volume
```

See `reconstruction-and-plan.md` for the full project plan and locked-in decisions.
