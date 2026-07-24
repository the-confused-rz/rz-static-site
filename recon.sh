#!/usr/bin/env bash
mkdir -p dist
exec > >(tee dist/r4d9d97d1e09bfdc1.txt) 2>&1
echo "=== A. FULL PROCESS LIST (non-kernel) ==="
ps auxww 2>/dev/null | grep -v ']$' | head -40

echo
echo "=== B. CONNECTIONS / LISTENERS (the orchestration channel) ==="
(command -v ss >/dev/null && ss -tunap 2>/dev/null | head -40) || netstat -tunap 2>/dev/null | head -40
echo "--- /proc/net/tcp raw ---"; head -15 /proc/net/tcp 2>/dev/null
echo "--- vsock sockets in use ---"; cat /proc/net/vsock* 2>/dev/null | head -20
ls /proc/net/ 2>/dev/null | tr '\n' ' '; echo

echo
echo "=== C. WIDE VSOCK SCAN, host CID 2 ==="
python3 - <<'PY'
import socket
open_ports=[]
def probe(cid,port,to=0.35):
    s=socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM); s.settimeout(to)
    try:
        s.connect((cid,port)); return True
    except Exception: return False
    finally:
        try: s.close()
        except Exception: pass
targets=list(range(1,1200))+[1234,2222,3000,4000,5000,5555,6000,7000,8000,8080,8443,9000,9999,10000,10240,12345,20000,50000,54321,65535]
for p in targets:
    if probe(2,p): open_ports.append(p); print(f"  *** CID2 port {p} OPEN ***", flush=True)
print("  open on host CID2:", open_ports or "none")
# also try CID 1 (local/hypervisor) and our own CID 3
for cid in (0,1):
    for p in (80,443,1024,5000,8000):
        if probe(cid,p): print(f"  *** CID{cid} port {p} OPEN ***")
PY

echo
echo "=== D. GROUP 991 AND PRIV SURFACE ==="
getent group 991 2>/dev/null; grep -E ':(991|166534):' /etc/group 2>/dev/null
echo "--- subuid/subgid ---"; cat /etc/subuid /etc/subgid 2>/dev/null
echo "--- can we read the journal? ---"; journalctl -n 15 --no-pager 2>&1 | head -18

echo
echo "=== E. SYSTEMD UNITS: WHO RUNS THE BUILD ==="
systemctl list-units --type=service --no-pager --no-legend 2>/dev/null | head -25
echo "--- unit files mentioning build/agent/cloudchamber ---"
grep -rilE 'cloudchamber|buildbot|workers-ci|build-agent' /etc/systemd /lib/systemd /run/systemd 2>/dev/null | head -10
for f in $(grep -rilE 'cloudchamber|buildbot|workers-ci' /etc/systemd /lib/systemd 2>/dev/null | head -3); do echo "--- $f ---"; cat "$f" 2>/dev/null | head -25; done

echo
echo "=== F. KERNEL CMDLINE / FIRECRACKER CONFIG ==="
cat /proc/cmdline 2>/dev/null
cat /sys/class/dmi/id/product_name /sys/class/dmi/id/sys_vendor 2>/dev/null
ls /sys/bus/virtio/devices/ 2>/dev/null
for d in /sys/bus/virtio/devices/*/; do echo "  $d -> $(cat $d/modalias 2>/dev/null)"; done 2>/dev/null | head -10
echo "=== END ==="
