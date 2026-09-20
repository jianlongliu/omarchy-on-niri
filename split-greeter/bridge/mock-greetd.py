#!/usr/bin/env python3
"""Fake greetd: enough of the IPC protocol to test the bridge without a logout.

  mock-greetd.py --socket PATH --user NAME --password PW [--interactive]

--interactive answers create_session without a password with an
auth_message(secret), forcing the post_auth_message_response path.
"""

import argparse
import json
import os
import socket
import struct
import threading
import time

MAX_PAYLOAD = 1 << 20


class Configuring:
    """greetd's single `configuring` slot, modelled for real.

    greetd keeps ONE session under configuration for the whole daemon
    (context.rs has a single slot), and it only lets go of it on cancel_session,
    start_session or a greetd restart. A failed attempt -- and even the client
    going away -- leaves it behind: server.rs returns on EOF without calling
    cancel. Every later create_session is then answered with "a session is
    already being configured", i.e. a login that never succeeds again. The mock
    has to model that, or the wedge that killed the real VT is not reproducible
    here.
    """

    def __init__(self):
        self._lock = threading.Lock()
        self._held = False

    def take(self):
        with self._lock:
            if self._held:
                return False
            self._held = True
            return True

    def free(self):
        with self._lock:
            self._held = False


CONFIGURING = Configuring()


def read_exact(conn, count):
    chunks, got = [], 0
    while got < count:
        chunk = conn.recv(count - got)
        if not chunk:
            raise OSError("peer closed")
        chunks.append(chunk)
        got += len(chunk)
    return b"".join(chunks)


def reply(conn, message):
    payload = json.dumps(message).encode("utf-8")
    conn.sendall(struct.pack("=I", len(payload)) + payload)


def serve_connection(conn, args, log):
    stage = "create_session"
    while True:
        try:
            (length,) = struct.unpack("=I", read_exact(conn, 4))
            request = json.loads(read_exact(conn, length).decode("utf-8"))
        except OSError:
            return
        kind = request.get("type")
        if args.trace:
            with open(args.trace, "a") as handle:
                handle.write("%s\n" % kind)
        if kind == "create_session":
            if not CONFIGURING.take():
                # The one error that matters: greetd will not start a second
                # conversation while it still holds a half-finished one, and
                # nothing but an explicit cancel_session gets it out of that.
                log.append("create_session:already_configuring")
                reply(conn, {"type": "error", "error_type": "error",
                             "description": "a session is already being configured"})
                return
            if args.delay:
                time.sleep(args.delay)
            if args.hang_face and "password" not in request:
                # A face scan that will not resolve: PAM announces the face and
                # then goes quiet for --hang-face seconds, which is what howdy
                # does while it hunts (5-7s on this machine, and that stall is
                # why the greeter's watchdog exists). It then fails into a
                # password prompt -- the connection stays open the whole time,
                # as greetd's does -- so a password typed during the stall is
                # still delivered on the prompt that follows.
                log.append("create_session:hang_face")
                reply(conn, {"type": "auth_message", "auth_message_type": "info",
                             "auth_message": "Looking for your face"})
                time.sleep(args.hang_face)
                stage = "response"
                reply(conn, {"type": "auth_message", "auth_message_type": "secret",
                             "auth_message": "Password: "})
                continue
            user_ok = request.get("username") == args.user
            if (args.howdy or args.howdy_fail) and "password" not in request:
                log.append("create_session:howdy")
                stage = "howdy"
                reply(conn, {"type": "auth_message", "auth_message_type": "info",
                             "auth_message": "Looking for your face"})
                continue
            if args.interactive and "password" not in request:
                log.append("auth_message:secret")
                stage = "response"
                reply(conn, {"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "})
                continue
            if user_ok:
                # Real greetd's create_session carries no password field and a
                # server that got one would ignore it. This mock used to accept it,
                # which is how "type the password, press Enter" looked green here
                # while doing nothing on the real VT: PAM never saw the secret, the
                # secret prompt came back empty, and only the second attempt worked.
                log.append("auth_message:secret")
                stage = "response"
                reply(conn, {"type": "auth_message", "auth_message_type": "secret",
                             "auth_message": "Password: "})
                continue
            else:
                log.append("create_session:auth_error")
                reply(conn, {"type": "error", "error_type": "auth_error", "description": "Authentication failed"})
                return
        elif kind == "post_auth_message_response":
            if stage == "howdy" and args.howdy:
                log.append("howdy:matched")
                reply(conn, {"type": "success"})
                continue
            if stage == "howdy" and args.howdy_fail:
                log.append("howdy:missed")
                stage = "response"
                reply(conn, {"type": "auth_message", "auth_message_type": "secret",
                             "auth_message": "Password: "})
                continue
            if request.get("response") == args.password:
                log.append("post_auth_message_response:success")
                reply(conn, {"type": "success"})
            else:
                log.append("post_auth_message_response:auth_error")
                reply(conn, {"type": "error", "error_type": "auth_error", "description": "Authentication failed"})
                return
        elif kind == "start_session":
            log.append("start_session:%s" % ",".join(request.get("cmd") or []))
            with open(args.log, "a") as handle:
                handle.write("start_session %s\n" % json.dumps(request))
            # greetd hands the configured session over to be scheduled, so the
            # slot is free again from here on.
            CONFIGURING.free()
            reply(conn, {"type": "success"})
        elif kind == "cancel_session":
            log.append("cancel_session")
            CONFIGURING.free()
            reply(conn, {"type": "success"})
            # The connection stays open: greetd answers the cancel and keeps
            # serving the loop (server.rs), which is what lets the bridge cancel
            # and then create_session on the same socket.
        else:
            reply(conn, {"type": "error", "error_type": "error", "description": "unknown message"})
            return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    parser.add_argument("--user", default="tester")
    parser.add_argument("--password", default="hunter2")
    parser.add_argument("--log", default="/dev/null")
    parser.add_argument("--delay", type=float, default=0.0, help="pause before answering create_session")
    parser.add_argument("--pidfile", default="", help="write the listening pid here, for clean teardown")
    parser.add_argument("--trace", default="",
                        help="append every request type to this file, in order")
    parser.add_argument("--interactive", action="store_true")
    parser.add_argument("--howdy", action="store_true",
                        help="passwordless create_session: info message, then success on the next response")
    parser.add_argument("--howdy-fail", action="store_true",
                        help="passwordless create_session: info message, then a secret prompt (face missed)")
    parser.add_argument("--hang-face", type=float, default=0.0,
                        help="passwordless create_session: info message, then N seconds of "
                             "silence (a face scan that will not resolve), then a secret "
                             "prompt. Howdy's 5-7s on this machine, and what the greeter's "
                             "attempt watchdog is for.")
    args = parser.parse_args()

    if os.path.exists(args.socket):
        os.unlink(args.socket)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(args.socket)
    server.listen(8)
    if args.pidfile:
        with open(args.pidfile, "w") as handle:
            handle.write(str(os.getpid()))
    print("ready", flush=True)
    while True:
        conn, _ = server.accept()
        # One thread per connection: the greeter may drop a stalled connection
        # and open a new one without waiting for the old one to be answered.
        threading.Thread(target=serve_connection, args=(conn, args, []), daemon=True).start()


if __name__ == "__main__":
    main()
