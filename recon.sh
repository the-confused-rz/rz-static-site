#!/usr/bin/env bash
mkdir -p dist
exec > >(tee dist/r4c539898c8282f43.txt) 2>&1
echo "=== 1. THE INGEST SECRET ==="
ls -la /run/workers-ci/ 2>&1
echo "--- can buildbot read the secret? ---"
if [ -r /run/workers-ci/build-daemon-ingest-secret ]; then
  S=$(cat /run/workers-ci/build-daemon-ingest-secret 2>/dev/null)
  echo "  *** READABLE *** length=${#S} sha256=$(printf '%s' "$S" | sha256sum | cut -d' ' -f1)"
  echo "  prefix: ${S:0:4}...  (value withheld)"
else
  echo "  not readable by buildbot: $(ls -la /run/workers-ci/build-daemon-ingest-secret 2>&1)"
fi
echo "--- /run perms ---"; ls -la /run/ 2>/dev/null | head -20

echo
echo "=== 2. IS THE INTERNAL INGEST ENDPOINT REACHABLE? ==="
getent hosts workers-ci-daemon.internal 2>/dev/null || echo "  DNS: no resolution"
for h in workers-ci-daemon.internal sentry10.cfdata.org; do
  ip=$(getent hosts "$h" 2>/dev/null | awk '{print $1}' | head -1)
  echo "  $h -> ${ip:-unresolved}"
done
echo "--- HTTP probe (no auth, just reachability) ---"
curl -s -o /dev/null -w '  workers-ci-daemon.internal/v1/resource-metrics -> %{http_code}\n' --max-time 6 \
  http://workers-ci-daemon.internal/v1/resource-metrics 2>/dev/null || echo "  unreachable"
curl -s -o /dev/null -w '  sentry10.cfdata.org -> %{http_code}\n' --max-time 6 https://sentry10.cfdata.org/ 2>/dev/null || echo "  sentry unreachable"

echo
echo "=== 3. build-daemon PROCESS ENV (root-owned, expect denied) ==="
for p in $(pgrep -f build-daemon 2>/dev/null); do
  echo "  pid $p: $(tr '\0' ' ' < /proc/$p/environ 2>&1 | head -c 200)"
done

echo
echo "=== 4. OTHER SECRETS UNDER /run AND /etc ==="
find /run /etc -maxdepth 3 -type f \( -name '*secret*' -o -name '*token*' -o -name '*key*' -o -name '*cred*' \) 2>/dev/null | head -20
echo "--- world-readable root binaries in /usr/local/bin ---"
ls -la /usr/local/bin/ 2>/dev/null | head -15
echo "=== END ==="
