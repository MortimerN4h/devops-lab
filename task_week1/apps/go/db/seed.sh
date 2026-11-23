#!/bin/sh
# Seed Redis with sample notes. Runs once in a short-lived "redis-seed" container (see docker-compose.yml),
# which uses the redis image only for its redis-cli tool. Redis has no "docker-entrypoint-initdb.d"
# like Postgres/Mongo, so we do it ourselves, and skip if the data already exists.
set -eu
R="redis-cli -h ${REDIS_HOST:-redis}"

if [ "$($R EXISTS notes:next_id)" = "1" ]; then
  echo "Redis already has notes, skipping seed"
  exit 0
fi

# day N -> the date N days from today, YYYY-MM-DD (empty = no deadline)
day() { date -u -d "@$(( $(date +%s) + $1 * 86400 ))" +%Y-%m-%d; }
NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

# add ID TEXT DONE DUE  ->  same data model as main.go: a HASH per note + its id in the sorted set
add() {
  $R HSET "note:$1" text "$2" done "$3" dueDate "$4" createdAt "$NOW" > /dev/null
  $R ZADD notes:by_id "$1" "$1" > /dev/null
}
# Same sample notes as the other apps (id 4 = newest = shown first)
add 1 "Learn Docker"        1 "$(day -2)"
add 2 "Learn Terraform"     0 "$(day 0)"
add 3 "Deploy to AWS"       0 "$(day 7)"
add 4 "Read the Nginx docs" 0 ""
$R SET notes:next_id 4 > /dev/null # the next note created by the API gets id 5
echo "Seeded 4 notes"
