#!/usr/bin/env bash
# The lab job: install every template whose "lab" isn't false into a running Caravana, through its
# API, with the template's example inputs; wait until it is healthy; delete it; print a table.
#
#   CARAVANA_URL=https://caravana.example.com CARAVANA_TOKEN=cvat_... lab/install-all.sh [name ...]
#
# With names, only those templates run. CARAVANA_URL is the console's address (http:// only for a
# machine you are on). CARAVANA_TOKEN is an API token (Settings > API tokens). The apps are named
# lab-<template>. A domain input takes its example with the first label replaced by the app's name
# (status.example.com becomes lab-uptime-kuma.example.com), so nothing real is claimed. Every other
# input takes its default, else its example. CARAVANA_WAIT is how long to wait for each, in seconds
# (default 600).
#
# A template with a backup is installed with its backups on when the installation has a backup
# destination, and with withoutBackups when it doesn't, so a bare installation can still run it.
# The exit status is 0 when every template passed.
set -euo pipefail

: "${CARAVANA_URL:?set CARAVANA_URL to the address of the console}"
: "${CARAVANA_TOKEN:?set CARAVANA_TOKEN to an API token}"
wait_seconds="${CARAVANA_WAIT:-600}"
url="${CARAVANA_URL%/}"

command -v curl >/dev/null || { echo "curl is needed" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is needed" >&2; exit 2; }

# api METHOD PATH [BODY]: prints the body, and the status on the last line.
api() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -X "$method" -w '\n%{http_code}' -H "Authorization: Bearer $CARAVANA_TOKEN" \
      -H 'Content-Type: application/json' --data "$body" "$url$path"
  else
    curl -sS -X "$method" -w '\n%{http_code}' -H "Authorization: Bearer $CARAVANA_TOKEN" "$url$path"
  fi
}

status_of() { tail -n 1 <<<"$1"; }
body_of() { sed '$d' <<<"$1"; }

# destination_set: true when the installation has a backup destination.
destination_set() {
  local out
  out="$(api GET /v1/backups/destination)"
  [ "$(status_of "$out")" = 200 ]
}

# wait_healthy APP DEPLOYMENT: waits for the deployment to end; succeeds only when it is healthy.
wait_healthy() {
  local app="$1" deployment="$2" deadline out state
  deadline=$((SECONDS + wait_seconds))
  while [ "$SECONDS" -lt "$deadline" ]; do
    out="$(api GET "/v1/apps/$app/deployments/$deployment")"
    state="$(body_of "$out" | jq -r '.status // empty')"
    case "$state" in
      healthy) return 0 ;;
      failed | reverted | superseded)
        echo "  the deployment ended $state: $(body_of "$out" | jq -r '.error // ""')" >&2
        return 1
        ;;
    esac
    sleep 5
  done
  echo "  not healthy after ${wait_seconds}s" >&2
  return 1
}

# remove_app APP: deletes it and waits until it is gone.
remove_app() {
  local app="$1" out deadline
  api DELETE "/v1/apps/$app" >/dev/null || true
  deadline=$((SECONDS + 120))
  while [ "$SECONDS" -lt "$deadline" ]; do
    out="$(api GET "/v1/apps/$app")"
    [ "$(status_of "$out")" = 404 ] && return 0
    sleep 2
  done
  return 1
}

# install_one NAME: installs, waits, deletes. Prints nothing on success; the reason on failure.
install_one() {
  local name="$1" app="lab-$1" template inputs backups out deployment
  out="$(api GET "/v1/templates/$name")"
  if [ "$(status_of "$out")" != 200 ]; then
    echo "  this Caravana doesn't know the template: $(body_of "$out" | jq -r '.error.message // ""')" >&2
    return 1
  fi
  template="$(body_of "$out")"
  if [ "$(jq -r '.available' <<<"$template")" != true ]; then
    echo "  not offered: $(jq -r '.unavailable' <<<"$template")" >&2
    return 1
  fi

  # The example (or default) of every input; a domain gets a lab domain of its own.
  inputs="$(jq -c --arg app "$app" '
    [.inputs[] | {key: .name, value: (if .type == "domain" and (.default // "") == "" then ($app + "." + ((.example // "x.localhost") | split(".") | .[1:] | join("."))) else (.default // .example // "") end)}]
    | from_entries' <<<"$template")"

  backups=false
  if jq -e '[.services[] | select(.backup != null)] | length > 0' >/dev/null <<<"$template" && ! destination_set; then
    backups=true # a template with a backup and no destination: install without them
  fi

  remove_app "$app" || true # a leftover of an earlier run
  out="$(api POST "/v1/templates/$name/install" "$(jq -c -n --arg id "$app" --argjson inputs "$inputs" --argjson without "$backups" \
    '{id: $id, inputs: $inputs, withoutBackups: $without}')")"
  if [ "$(status_of "$out")" != 202 ]; then
    echo "  install refused ($(status_of "$out")): $(body_of "$out" | jq -r '.error | "\(.code) \(.field // "") \(.message)"')" >&2
    return 1
  fi
  deployment="$(body_of "$out" | jq -r '.id')"
  local result=0
  wait_healthy "$app" "$deployment" || result=1
  remove_app "$app" || { echo "  couldn't delete $app" >&2; result=1; }
  return "$result"
}

# The templates to run: the names given, else every one with lab not false, read from the catalog the
# installation offers (so the table matches what this Caravana can install).
names=("$@")
if [ "${#names[@]}" -eq 0 ]; then
  list="$(api GET /v1/templates)"
  [ "$(status_of "$list")" = 200 ] || { echo "GET /v1/templates failed: $(status_of "$list")" >&2; exit 2; }
  while IFS= read -r n; do names+=("$n"); done < <(
    for n in $(body_of "$list" | jq -r '.templates[].name'); do
      if [ "$(body_of "$(api GET "/v1/templates/$n")" | jq -r '.lab')" = true ]; then echo "$n"; fi
    done)
fi

passed=0
failed=0
rows=()
for name in "${names[@]}"; do
  echo "== $name"
  started=$SECONDS
  if install_one "$name"; then
    rows+=("$(printf '%-20s %-6s %4ss' "$name" pass $((SECONDS - started)))")
    passed=$((passed + 1))
  else
    rows+=("$(printf '%-20s %-6s %4ss' "$name" FAIL $((SECONDS - started)))")
    failed=$((failed + 1))
  fi
done

echo
printf '%-20s %-6s %5s\n' TEMPLATE RESULT TIME
printf '%s\n' "${rows[@]}"
echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
