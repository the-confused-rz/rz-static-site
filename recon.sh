#!/usr/bin/env bash
# Recon build for Cloudflare Pages / Workers CI.
#
# Runs INSIDE our own build container, on our own account. Everything here is
# read-only observation of the environment we were given. It does not touch any
# other tenant, does not write anywhere outside the build workspace, and does
# not exfiltrate: all output goes to the build log we own.
#
# Purpose is to answer four questions:
#   1. What credential is the builder holding, and what does it authorize?
#   2. What can the builder reach on the network?
#   3. What is the isolation boundary (container, caps, mounts)?
#   4. What is left behind between builds (cache, workspace reuse)?

echo "=================================================================="
echo "1. IDENTITY AND ISOLATION"
echo "=================================================================="
echo "whoami         : $(whoami 2>/dev/null) uid=$(id -u 2>/dev/null) gid=$(id -g 2>/dev/null)"
echo "hostname       : $(hostname 2>/dev/null)"
echo "kernel         : $(uname -a 2>/dev/null)"
echo "--- container runtime hints ---"
cat /proc/1/cgroup 2>/dev/null | head -5
echo "container env  : ${container:-unset}"
ls -la /.dockerenv /run/.containerenv 2>/dev/null
echo "--- capabilities ---"
grep -E 'CapEff|CapPrm|CapBnd|Seccomp|NoNewPrivs' /proc/self/status 2>/dev/null
echo "--- can we see other processes? ---"
ps aux 2>/dev/null | head -15
echo "process count  : $(ps aux 2>/dev/null | wc -l)"

echo
echo "=================================================================="
echo "2. CREDENTIAL INVENTORY (names and shapes only, values redacted)"
echo "=================================================================="
# Print variable NAMES and a fingerprint, never the secret itself.
env | sort | while IFS='=' read -r k v; do
  n=${#v}
  case "$k" in
    *TOKEN*|*SECRET*|*KEY*|*PASS*|*CRED*|*AUTH*)
      echo "  $k = <redacted, ${n} chars, prefix $(printf '%s' "$v" | cut -c1-4)...>" ;;
    *)
      if [ "$n" -gt 60 ]; then echo "  $k = <long value, ${n} chars>"; else echo "  $k = $v"; fi ;;
  esac
done

echo
echo "--- credential-bearing files on disk ---"
for f in ~/.wrangler/config/default.toml ~/.config/.wrangler ~/.netrc ~/.git-credentials \
         /root/.docker/config.json ./.git/config; do
  [ -e "$f" ] && echo "  PRESENT: $f" && ls -la "$f"
done
echo "--- git remote (does it carry a token?) ---"
git remote -v 2>/dev/null | sed -E 's#(https://)[^@]*@#\1<redacted>@#g'

echo
echo "=================================================================="
echo "3. WHAT DOES THE BUILDER'S TOKEN AUTHORIZE?"
echo "=================================================================="
# The key question. If a CF API token is present, ask Cloudflare what it is
# scoped to. This only queries OUR OWN token's metadata.
TOK="${CLOUDFLARE_API_TOKEN:-${CF_API_TOKEN:-}}"
if [ -n "$TOK" ]; then
  echo "--- /user/tokens/verify ---"
  curl -s --max-time 10 "https://api.cloudflare.com/client/v4/user/tokens/verify" \
    -H "Authorization: Bearer $TOK" | head -c 800; echo
  echo "--- can it list ALL accounts, or only this project's? ---"
  curl -s --max-time 10 "https://api.cloudflare.com/client/v4/accounts" \
    -H "Authorization: Bearer $TOK" | head -c 800; echo
  echo "--- can it list zones (should be none for a build token) ---"
  curl -s --max-time 10 "https://api.cloudflare.com/client/v4/zones?per_page=5" \
    -H "Authorization: Bearer $TOK" | head -c 600; echo
else
  echo "  no CLOUDFLARE_API_TOKEN / CF_API_TOKEN in env"
fi

echo
echo "=================================================================="
echo "4. NETWORK REACH FROM THE BUILDER"
echo "=================================================================="
probe() {
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$1" 2>/dev/null)
  echo "  $(printf '%-46s' "$1") -> ${code:-no-response}"
}
echo "--- cloud metadata endpoints ---"
probe "http://169.254.169.254/latest/meta-data/"
probe "http://169.254.169.254/computeMetadata/v1/"
probe "http://metadata.google.internal/computeMetadata/v1/"
echo "--- loopback and private ranges ---"
probe "http://127.0.0.1:80/"
probe "http://127.0.0.1:8080/"
probe "http://10.0.0.1/"
probe "http://172.17.0.1/"
probe "http://192.168.0.1/"
echo "--- cloudflare internal-ish names ---"
probe "https://api.cloudflare.com/client/v4/"
for h in metadata internal build-cache registry consul vault; do
  ip=$(getent hosts "$h" 2>/dev/null | awk '{print $1}')
  [ -n "$ip" ] && echo "  DNS $h resolves -> $ip"
done
echo "--- outbound egress allowed at all? ---"
probe "https://example.com/"

echo
echo "=================================================================="
echo "5. FILESYSTEM AND BUILD REUSE"
echo "=================================================================="
echo "--- mounts ---"
mount 2>/dev/null | head -25
echo "--- writable dirs outside workspace ---"
for d in / /tmp /var /opt /usr/local /home; do
  [ -w "$d" ] && echo "  WRITABLE: $d"
done
echo "--- anything left from a previous build? ---"
ls -la /tmp 2>/dev/null | head -15
echo "--- cache dirs ---"
for d in /opt/buildhome ~/.cache /cache /build-cache; do
  [ -d "$d" ] && echo "  PRESENT: $d" && ls -la "$d" 2>/dev/null | head -8
done
echo "--- marker for cross-build persistence check ---"
echo "marker written at $(date -u 2>/dev/null)" >> /tmp/rz_build_marker.txt 2>/dev/null
echo "  marker file now contains $(wc -l < /tmp/rz_build_marker.txt 2>/dev/null) line(s)"
echo "  (if this is >1 on a fresh build, workspace or tmp is reused across builds)"

echo
echo "=================================================================="
echo "RECON COMPLETE"
echo "=================================================================="
mkdir -p dist && echo "ok" > dist/index.html

echo
echo "=================================================================="
echo "6. IS THE ACCOUNT-SCOPED BUILD TOKEN VISIBLE FROM HERE?"
echo "=================================================================="
# The dashboard mints an account-wide token named "<project> build token".
# The only question that matters is whether this container can see it.
found=0
for v in $(env | cut -d= -f1); do
  val=$(eval "printf '%s' \"\${$v}\"")
  case "$val" in
    cfut_*|cfat_*) echo "  CF TOKEN IN ENV: $v = <${#val} chars, prefix $(printf '%s' "$val" | cut -c1-5)...>"; found=1 ;;
  esac
done
grep -rlE 'cfut_|cfat_' /opt/buildhome ~/.wrangler /tmp . 2>/dev/null | grep -v recon.sh | head -5 | while read -r f; do
  echo "  CF TOKEN IN FILE: $f"; found=1
done
[ "$found" -eq 0 ] && echo "  no cfut_/cfat_ token visible in env or common paths"
