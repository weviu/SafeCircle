# SafeCircle

School to home child safety platform (Android app).

## Setup

```bash
cp .env.example .env   # then edit the values
```

## Run

```bash
docker compose up --build -d
```

Services:
`nginx`:    reverse proxy (entry point). Port: 8080      |
`api`:      NestJS backend  Port: 3000
`postgres`: PostgreSQL 17

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