#!/usr/bin/env bash
# Brings the app server up to date. Runs ON THE SERVER as root: GitHub Actions calls it through
# SSM after `git pull` (see .github/actions/deploy-to-server), or run it by hand:
#   sudo bash /opt/devops-lab/task_week1/deploy/deploy.sh
# The same script for every app: it always updates EVERYTHING, so running it twice is harmless.
set -euo pipefail
cd "$(dirname "$0")" # the deploy/ folder, wherever the repo is

# 1) Pull the newest image of every app service (names ending in -frontend / -backend).
#    Databases and edge use public images with fixed tags, so they are not pulled again.
APP_SERVICES=$(docker compose config --services | grep -E -- '-(frontend|backend)$')
docker compose pull $APP_SERVICES # no quotes: one argument per service name

# 2) Create missing containers, recreate the ones whose image or settings changed, leave the rest.
#    --remove-orphans: also delete containers of services that were REMOVED from docker-compose.yml
#    (the file in git is the truth: what is not in it should not run).
docker compose up -d --remove-orphans

# 3) Edge. compose only compares the LINES of docker-compose.yml, not the content of mounted files,
#    and edge turns its *.template files into the real config only when it starts.
#    So: if any nginx file changed since the last deploy -> test the new config -> restart edge.
HASH=$(find nginx -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
if [ "$HASH" != "$(cat .nginx-hash 2>/dev/null || true)" ]; then
  echo "nginx config changed: testing it in a throw-away edge container"
  # run = one-off container of the edge service (same image, mounts, networks; no published ports).
  # Its start script renders the templates, then `nginx -t` only checks them and exits.
  # If the test fails, set -e stops here and the running edge keeps the old, working config.
  docker compose run --rm --no-deps edge nginx -t
  docker compose restart edge
  echo "$HASH" > .nginx-hash
fi

# 4) Delete images no container uses any more (old versions), so the 20 GB disk does not fill up.
docker image prune -f
docker compose ps
