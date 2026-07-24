#!/usr/bin/env bash
mkdir -p dist
exec > >(tee dist/r2ae0004e0dc628e2.txt) 2>&1
EP=http://workers-ci-daemon.internal/v1/resource-metrics
echo "=== DOES THE INTERNAL INGEST ENDPOINT AUTHENTICATE? ==="
echo "endpoint: $EP  (resolves $(getent hosts workers-ci-daemon.internal | awk '{print $1}'))"
echo "Single minimal probe per case. Payload carries only OUR OWN build_uuid, no spoofed tenant."
BODY='{"build_uuid":"'"$WORKERS_CI_BUILD_UUID"'","probe":"rz-authz-check","resource_samples":[]}'

echo
echo "--- A. no auth headers at all ---"
curl -s -o /tmp/a.txt -w '  status=%{http_code}\n' --max-time 8 -X POST "$EP" \
  -H 'content-type: application/json' --data "$BODY" 2>/dev/null; head -c 200 /tmp/a.txt; echo

echo "--- B. headers present but signature garbage ---"
curl -s -o /tmp/b.txt -w '  status=%{http_code}\n' --max-time 8 -X POST "$EP" \
  -H 'content-type: application/json' \
  -H "x-wci-daemon-timestamp: $(date +%s)" \
  -H 'x-wci-daemon-sequence: 1' \
  -H 'x-wci-daemon-signature: 0000000000000000000000000000000000000000000000000000000000000000' \
  --data "$BODY" 2>/dev/null; head -c 200 /tmp/b.txt; echo

echo "--- C. what methods/paths does it expose ---"
for m in GET PUT DELETE OPTIONS; do
  printf '  %-7s -> %s\n' "$m" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X $m "$EP" 2>/dev/null)"
done
for p in / /v1/ /health /metrics /v1/logs /v1/traces /debug/pprof/; do
  printf '  %-18s -> %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://workers-ci-daemon.internal$p" 2>/dev/null)"
done
echo "--- server banner ---"
curl -s -i --max-time 6 -X OPTIONS "$EP" 2>/dev/null | head -12

echo
echo "=== OTHER .internal NAMES RESOLVABLE FROM A TENANT BUILD? ==="
for n in workers-ci.internal build.internal api.internal cloudchamber.internal registry.internal \
         logs.internal metrics.internal control.internal workers-ci-daemon.internal; do
  ip=$(getent hosts "$n" 2>/dev/null | awk '{print $1}' | head -1)
  [ -n "$ip" ] && echo "  $n -> $ip"
done
echo "--- resolver config ---"; cat /etc/resolv.conf 2>/dev/null
echo "=== END ==="
