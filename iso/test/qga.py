#!/usr/bin/env python3
"""qga.py SOCKET CMD… — run a command inside a QEMU guest through its guest
agent and print its output (exit code = the command's).

    qga.py /tmp/qga.sock --wait 180        wait until the agent answers
    qga.py /tmp/qga.sock systemctl is-system-running
    qga.py /tmp/qga.sock --shutdown
"""
import base64, json, socket, sys, time


class Agent:
    def __init__(self, path, timeout=10):
        self.s = socket.socket(socket.AF_UNIX)
        self.s.settimeout(timeout)
        self.s.connect(path)
        self.buf = b""
        self.sync()

    def _send(self, obj):
        self.s.sendall(json.dumps(obj).encode() + b"\n")

    def _recv(self):
        while b"\n" not in self.buf:
            chunk = self.s.recv(65536)
            if not chunk:
                raise ConnectionError("agent closed the connection")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line.lstrip(b"\xff"))

    def sync(self):
        tag = int(time.time() * 1000) % 100000
        self.s.sendall(b"\xff")
        self._send({"execute": "guest-sync-delimited", "arguments": {"id": tag}})
        while True:
            r = self._recv()
            if r.get("return") == tag:
                return

    def call(self, cmd, **args):
        self._send({"execute": cmd, "arguments": args} if args else {"execute": cmd})
        r = self._recv()
        if "error" in r:
            raise RuntimeError(r["error"].get("desc", r["error"]))
        return r.get("return")

    def run(self, argv, timeout=120):
        pid = self.call("guest-exec", path=argv[0], arg=argv[1:], **{"capture-output": True})["pid"]
        end = time.time() + timeout
        while time.time() < end:
            st = self.call("guest-exec-status", pid=pid)
            if st.get("exited"):
                out = base64.b64decode(st.get("out-data", "")).decode(errors="replace")
                err = base64.b64decode(st.get("err-data", "")).decode(errors="replace")
                return st.get("exitcode", 1), out, err
            time.sleep(0.3)
        return 124, "", "timed out"


def main():
    sock, args = sys.argv[1], sys.argv[2:]
    if args[:1] == ["--wait"]:
        limit = time.time() + float(args[1] if len(args) > 1 else 180)
        while time.time() < limit:
            try:
                Agent(sock, timeout=3).call("guest-ping")
                print("agent up")
                return 0
            except (OSError, ConnectionError, RuntimeError, ValueError):
                time.sleep(2)
        print("agent did not answer", file=sys.stderr)
        return 1
    a = Agent(sock)
    if args[:1] == ["--shutdown"]:
        try:
            a._send({"execute": "guest-shutdown"})
        except OSError:
            pass
        return 0
    rc, out, err = a.run(args)
    sys.stdout.write(out)
    sys.stderr.write(err)
    return rc


if __name__ == "__main__":
    sys.exit(main())
