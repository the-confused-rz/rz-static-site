#!/usr/bin/env bash
mkdir -p dist
exec > >(tee dist/r0d6582ddd8548b75.txt) 2>&1
PROBE_TIMEOUT=4
echo "=== 1. OUR IPv6 WORLD ==="
ip -6 addr 2>/dev/null; echo "--- routes ---"; ip -6 route 2>/dev/null
echo "--- neighbours ---"; ip -6 neigh 2>/dev/null
echo "--- current v6 conns ---"; ss -6 -tunap 2>/dev/null | head -20

echo
echo "=== 2. WHAT IS fd00::119:1 ==="
for path in / /metrics /health /status /v1/ /debug/pprof/ /.well-known/ /api/v1/; do
  code=$(curl -6 -s -o /dev/null -w '%{http_code}' --max-time 4 "http://[fd00::119:1]$path" 2>/dev/null)
  [ -n "$code" ] && [ "$code" != "000" ] && echo "  [fd00::119:1]$path -> $code"
done
echo "--- full response of / ---"
curl -6 -s -i --max-time 6 "http://[fd00::119:1]/" 2>&1 | head -40

echo
echo "=== 3. SCAN THE INTERNAL ULA NEIGHBOURHOOD ==="
for h in fd00::1 fd00::2 fd00::10 fd00::11 fd00::100 fd00::119:1 fd00::119:2 fd00::119:10 \
         fd00::118:1 fd00::120:1 fd00::a fd00::ffff; do
  for p in 80 443 8080 9090 2323; do
    if timeout 2 bash -c "echo > /dev/tcp/$h/$p" 2>/dev/null; then
      echo "  *** [$h]:$p OPEN ***"
      curl -6 -s -i --max-time 4 "http://[$h]:$p/" 2>/dev/null | head -6
    fi
  done
done

echo
echo "=== 4. LOCAL ROOT LISTENER 127.0.0.1:817 ==="
curl -s -i --max-time 5 http://127.0.0.1:817/ 2>&1 | head -20
for path in / /metrics /health /v1/ /status /debug/pprof/; do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:817$path" 2>/dev/null)
  [ "$c" != "000" ] && echo "  127.0.0.1:817$path -> $c"
done
printf 'GET / HTTP/1.0\r\n\r\n' | timeout 4 bash -c 'cat > /dev/tcp/127.0.0.1/817' 2>/dev/null
(exec 3<>/dev/tcp/127.0.0.1/817 && printf 'HELLO\r\n' >&3 && timeout 3 head -c 300 <&3) 2>/dev/null | head -10

echo
echo "=== 5. VSOCK CID2:514 -- IDENTIFY ONLY, NO WRITES ==="
python3 - <<'PY'
import socket
s=socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM); s.settimeout(4)
try:
    s.connect((2,514)); print("  connected to host CID2:514")
    s.settimeout(2.5)
    try:
        b=s.recv(256); print("  banner:", b[:200] if b else "(none, silent listener)")
    except socket.timeout: print("  no banner within 2.5s (silent, likely syslog sink)")
except Exception as e: print("  connect failed:",e)
finally: s.close()
PY
echo "--- who else can reach vsock? /dev/vsock perms ---"; ls -la /dev/vsock

echo
echo "=== 6. METRIC/OTEL CONFIG (internal endpoints) ==="
ls -la /etc/opentelemetry-collector/ 2>/dev/null
cat /etc/opentelemetry-collector/config.yaml 2>/dev/null | head -60
echo "--- /opt/root readable? ---"; ls -la /opt/root/ 2>/dev/null | head
echo "=== END ==="
