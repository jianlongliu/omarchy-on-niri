#!/usr/bin/env python3
"""greetd IPC bridge for the Omarchy Quickshell greeter.

Wire format:
  stdin/stdout : one JSON object per line (requests in, events out)
  GREETD_SOCK  : greetd's unix socket, 4-byte native-endian length + JSON

One bridge process serves one login attempt chain: greetd keeps the session
under configuration on the socket connection, so that connection has to stay
open from create_session all the way to start_session.
"""

import json
import os
import socket
import struct
import sys

MAX_PAYLOAD = 1 << 20


def emit(event, **fields):
    sys.stdout.write(json.dumps({"event": event, **fields}) + "\n")
    sys.stdout.flush()


def log(message):
    sys.stderr.write("greetd-bridge: %s\n" % message)
    sys.stderr.flush()


class Greetd:
    def __init__(self, path):
        self.path = path
        self._sock = None

    def _connect(self):
        if self._sock is None:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(self.path)
            self._sock = sock

    def close(self):
        if self._sock is not None:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None

    def _read(self, count):
        chunks, got = [], 0
        while got < count:
            chunk = self._sock.recv(count - got)
            if not chunk:
                raise OSError("greetd closed the connection")
            chunks.append(chunk)
            got += len(chunk)
        return b"".join(chunks)

    def request(self, message):
        self._connect()
        payload = json.dumps(message).encode("utf-8")
        self._sock.sendall(struct.pack("=I", len(payload)) + payload)
        (length,) = struct.unpack("=I", self._read(4))
        if length > MAX_PAYLOAD:
            raise OSError("greetd sent an oversized reply (%d bytes)" % length)
        return json.loads(self._read(length).decode("utf-8"))


def describe(reply):
    return reply.get("error_type") or "error", reply.get("description") or "authentication failed"


def auth_reply(greetd, reply, epoch):
    """Map a create_session / post_auth_message_response reply onto an event.

    `epoch` is the caller's login-attempt counter, echoed back so the UI can
    drop replies from an attempt it has already abandoned (e.g. the face scan
    of the previous account finishing after the user switched accounts).
    """
    kind = reply.get("type")
    if kind == "success":
        emit("auth_ok", epoch=epoch)
        return
    if kind == "auth_message":
        emit(
            "auth_message",
            epoch=epoch,
            kind=reply.get("auth_message_type") or "info",
            message=reply.get("auth_message") or "",
        )
        return
    error_type, description = describe(reply)
    greetd.close()
    emit("auth_fail", epoch=epoch, kind=error_type, description=description)


def clear_pending(greetd):
    """Cancel whatever greetd still holds under configuration.

    greetd has ONE session under configuration for the whole daemon (context.rs
    keeps a single `configuring` slot) and it only lets go of it on
    cancel_session, start_session or a restart. A failed attempt -- and even the
    client going away -- leaves it behind: server.rs returns on EOF without
    calling cancel. Every later create_session is then refused with "a session
    is already being configured", i.e. a login that never succeeds again until
    greetd is restarted. That is a real boot: it is what tty1 did on 2026-09-20.

    Cancelling first is safe and cheap: greetd answers success whether or not
    anything was configured, and cancel can only ever touch a half-finished
    login, never the running greeter or a logged-in session.
    """
    try:
        greetd.request({"type": "cancel_session"})
    except OSError as exc:
        log("cancel before create_session failed: %s" % exc)
        greetd.close()


def handle(greetd, request):
    op = request.get("op")
    epoch = request.get("epoch")
    if op == "auth":
        # Every attempt gets a fresh session: a session left half-configured
        # after a failed create_session is not reusable -- and it also has to be
        # cleared out of the way first, see clear_pending().
        greetd.close()
        clear_pending(greetd)
        message = {"type": "create_session", "username": request.get("username") or ""}
        # No password here. greetd's create_session has no such field and would
        # ignore one, so the secret only ever travels as the answer to a prompt —
        # which is why the caller keeps it queued until a prompt arrives.

        auth_reply(greetd, greetd.request(message), epoch)
    elif op == "respond":
        auth_reply(
            greetd,
            greetd.request(
                {
                    "type": "post_auth_message_response",
                    "response": request.get("response") or None,
                }
            ),
            epoch,
        )
    elif op == "start":
        reply = greetd.request(
            {
                "type": "start_session",
                "cmd": request.get("cmd") or ["niri-session"],
                "env": request.get("env") or ["XDG_SESSION_TYPE=wayland"],
            }
        )
        if reply.get("type") == "success":
            # greetd starts the session once this whole greeter process tree is
            # gone, so the caller is expected to quit the shell now.
            emit("started", epoch=epoch)
        else:
            error_type, description = describe(reply)
            emit("start_failed", epoch=epoch, kind=error_type, description=description)
    elif op == "cancel":
        greetd.request({"type": "cancel_session"})
        greetd.close()
        emit("cancelled")
    else:
        emit("error", description="unknown op %r" % (op,))


def main():
    path = os.environ.get("GREETD_SOCK")
    if not path:
        emit("error", description="GREETD_SOCK is not set")
        return 1
    greetd = Greetd(path)
    emit("ready", socket=path, user=os.environ.get("USER") or "")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        epoch = None          # may be set by whatever parses the request
        try:
            request = json.loads(line)
            if request.get("op") == "quit":
                break
            handle(greetd, request)
        except Exception as exc:  # never take the greeter down with us
            greetd.close()
            log("%s: %s" % (type(exc).__name__, exc))
            emit("error", epoch=epoch, description=str(exc))
    greetd.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
