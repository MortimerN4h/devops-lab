#!/usr/bin/env bash
# Read the access log of the edge nginx (EVERY request to EVERY app passes through it) and answer:
#   how many requests, which status codes, which IPs, what each IP asked for, and the raw lines.
#
# Run on the app server, in this folder:
#   ./logs.sh                       summary of the last 5 hours
#   ./logs.sh -s 24h -a go          only go.<domain>, last 24 hours
#   ./logs.sh -i 1.2.3.4            everything about one IP: counts, what it requested, raw lines
#   ./logs.sh -c 5xx -r             raw lines of server errors only
#   ./logs.sh -s 2026-11-25T00:00:00 -u 2026-11-26T00:00:00     one whole day (server time = UTC)
#   ./logs.sh -f saved.log          read a saved file instead of the container
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./logs.sh [options]
  -s SINCE   start of the window: 5h, 30m, 48h (no "d"), 2026-11-25T08:00:00  (default: 5h)
  -u UNTIL   end of the window, same format                                                    (default: now)
  -i IP      only requests from this client IP (also prints all its raw lines)
  -a APP     only this app: node | python | go | java | dotnet
  -c STATUS  only this status: 404, 500, 4xx, 5xx ...
  -p TEXT    only paths containing TEXT, e.g. /api/
  -r         print ONLY the matching raw lines (no summary), e.g. ./logs.sh -r | less
  -n N       rows in each "top" table                                                          (default: 10)
  -f FILE    read this file instead of "docker logs edge"
  -h         this help
EOF
}

SINCE=5h UNTIL="" IP="" APP="" STATUS="" PATH_TEXT="" RAW_ONLY=0 TOP=10 FILE=""
while getopts "s:u:i:a:c:p:rn:f:h" opt; do
  case "$opt" in
    s) SINCE=$OPTARG ;;   u) UNTIL=$OPTARG ;;   i) IP=$OPTARG ;;    a) APP=$OPTARG ;;
    c) STATUS=$OPTARG ;;  p) PATH_TEXT=$OPTARG ;;  r) RAW_ONLY=1 ;;  n) TOP=$OPTARG ;;
    f) FILE=$OPTARG ;;    h) usage; exit 0 ;;   *) usage; exit 1 ;;
  esac
done

# ---- 1. Get the raw log ----
# nginx in Docker writes the access log to stdout and errors to stderr; 2>/dev/null keeps only requests.
read_log() {
  if [ -n "$FILE" ]; then
    cat "$FILE"
  else
    docker logs edge --since "$SINCE" ${UNTIL:+--until "$UNTIL"} 2>/dev/null
  fi
}

# ---- 2. Parse + filter: one tab-separated row per request ----
# Splitting on the double quote is simpler than on spaces (the user agent contains spaces):
#   1.2.3.4 - - [25/Nov/2026:09:05:02 +0000] "GET /api/notes HTTP/2.0" 404 60 "-" "curl/8.5" host=go.x rt=0.003
#   q[1] = 1.2.3.4 - - [25/Nov/...]   q[2] = GET /api/notes HTTP/2.0   q[3] = 404 60
#   q[4] = referer                    q[6] = user agent                q[7] = host=... rt=...
# Output columns: ip, time, app, method, path, status, bytes, seconds, user agent, raw line
parse() {
  awk -F'"' -v want_ip="$IP" -v want_app="$APP" -v want_status="$STATUS" -v want_path="$PATH_TEXT" '
    BEGIN {
      OFS = "\t"
      st_re = want_status; gsub(/x/, ".", st_re); st_re = "^" st_re "$"   # 5xx -> ^5..$
    }
    # keep only access-log lines (skips nginx start-up messages)
    $1 !~ /^[0-9a-fA-F.:]+ - .* \[[^]]+\] $/ { next }
    {
      split($1, a, " "); ip = a[1]
      time = $1; sub(/^[^[]*\[/, "", time); sub(/ .*/, "", time)           # 25/Nov/2026:09:05:02
      n = split($2, r, " "); method = (n >= 2 ? r[1] : "-"); path = (n >= 2 ? r[2] : $2)  # junk (e.g. TLS on port 80) has no method
      split($3, s, " "); status = s[1]; bytes = s[2]
      host = "?"; rt = "-"
      if (match($7, /host=[^ ]+/)) host = substr($7, RSTART + 5, RLENGTH - 5)
      if (match($7, /rt=[^ ]+/))   rt   = substr($7, RSTART + 3, RLENGTH - 3)
      app = host
      if (host ~ /^(node|python|go|java|dotnet)\./) { app = host; sub(/\..*/, "", app) }
      else if (host != "?") app = "other(" host ")"                       # bare IP, scanners, unknown names

      if (want_ip     != "" && ip != want_ip)                 next
      if (want_app    != "" && app != want_app)               next
      if (want_status != "" && status !~ st_re)               next
      if (want_path   != "" && index(path, want_path) == 0)   next
      print ip, time, app, method, path, status, bytes, rt, $6, $0
    }'
}

ROWS=$(read_log | parse || true)

if [ "$RAW_ONLY" = 1 ]; then
  [ -n "$ROWS" ] && printf '%s\n' "$ROWS" | cut -f10
  exit 0
fi

# ---- 3. Summary ----
# count_by COLUMNS: group by those columns and count, biggest first.  ("cut -f" picks tab columns)
count_by() { printf '%s\n' "$ROWS" | cut -f"$1" | sort | uniq -c | sort -rn | head -n "$TOP"; }
title()    { printf '\n== %s ==\n' "$1"; }

FILTERS="${FILE:+file=$FILE }since=$SINCE${UNTIL:+ until=$UNTIL}${IP:+ ip=$IP}${APP:+ app=$APP}${STATUS:+ status=$STATUS}${PATH_TEXT:+ path~$PATH_TEXT}"
echo "Edge access log, $FILTERS"

if [ -z "$ROWS" ]; then
  echo "No requests match."; exit 0
fi

TOTAL=$(printf '%s\n' "$ROWS" | wc -l)
IPS=$(printf '%s\n' "$ROWS" | cut -f1 | sort -u | wc -l)
FIRST=$(printf '%s\n' "$ROWS" | head -n1 | cut -f2)
LAST=$(printf '%s\n' "$ROWS" | tail -n1 | cut -f2)
echo "Requests: $TOTAL   from $IPS different IPs   first: $FIRST   last: $LAST"

title "By status";            count_by 6
title "By app";               count_by 3
title "Top IPs";              count_by 1
title "Top requests (method path status)"
printf '%s\n' "$ROWS" | awk -F'\t' '{print $4, $5, $6}' | sort | uniq -c | sort -rn | head -n "$TOP"
title "Requests per hour"
printf '%s\n' "$ROWS" | cut -f2 | cut -c1-14 | uniq -c   # 25/Nov/2026:09 (the log is already in time order)

title "Slowest requests (seconds, ip, method path status)"
printf '%s\n' "$ROWS" | awk -F'\t' '$8 != "-" {print $8, $1, $4, $5, $6}' | sort -rn | head -n 5

if [ -n "$IP" ]; then
  title "User agents of $IP";   count_by 9
  title "Raw lines of $IP"
  printf '%s\n' "$ROWS" | cut -f10
else
  title "Last 10 raw lines (use -r for all, -i IP for one client)"
  printf '%s\n' "$ROWS" | tail -n 10 | cut -f10
fi
