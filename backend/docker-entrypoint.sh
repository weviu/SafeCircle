#!/bin/sh
set -e

export PATH="/app/node_modules/.bin:$PATH"

npx prisma migrate deploy
npx prisma db seed

exec "$@"
